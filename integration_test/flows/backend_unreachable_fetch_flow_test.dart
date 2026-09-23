// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §18.4; issue #96): a
// Wolt fetch that fails because KetoClub's own backend could not be
// reached — the failure a web build sees when it is configured with a
// proxy base and that backend itself is down, distinct from Wolt being
// unreachable — shows its own honest copy rather than the generic
// "no connection" message.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// The Wolt venue page the user pastes, in the documented
/// `wolt.com/{lang}/{country}/{city}/restaurant/{slug}` form
/// (architecture.md §6.5 Tier A).
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/vitrina-lilinblum';

/// The [VenueRef] [_woltUrl] resolves to, and the key the fake repository
/// below is stubbed under.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'vitrina-lilinblum',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('backend-unreachable fetch flow', () {
    testWidgets(
      'pasting a Wolt link shows the backend-unreachable message when the '
      'repository reports it',
      (tester) async {
        // Setup: script the fake repository the way WoltMenuAdapter would
        // answer when its configured proxy base could not be reached
        // (a ClientException talking to KetoClub's own backend).
        final fakes = FakeAppDependencies();
        fakes.repository.stub(
          _ref,
          const MenuFetchFailed(
            reason: MenuFetchFailureReason.backendUnreachable,
          ),
        );
        await pumpApp(tester, fakes);

        // Act: paste the Wolt link and open it.
        await enterText(tester, _woltUrl);
        await tapAndSettle(tester, find.text(_en.venueSearchOpen));

        // Assert: the distinct backend-unreachable copy is shown, never
        // the plain "no connection" offline message.
        expect(find.text(_en.fetchFailedBackendUnreachable), findsOneWidget);
        expect(find.text(_en.fetchFailedOffline), findsNothing);
      },
    );
  });
}
