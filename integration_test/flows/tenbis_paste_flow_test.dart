// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §6.5, §18.4; issue
// #33): a pasted 10bis link or bare id resolves and navigates like any
// other recognised source, but there is no 10bis adapter yet (architecture.md
// §16 build-order step 6), so the honest `unsupportedSource` message is what
// the user sees next — never a dead end, and never a crash.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// A real 10bis restaurant URL shape (architecture.md §6.5): a
/// `restaurants` path segment followed, somewhere later, by the numeric
/// restaurant id.
const String _tenBisUrl =
    'https://www.10bis.co.il/next/restaurants/menu/delivery/654321/some-slug';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('10bis paste flow', () {
    testWidgets(
      'pasting a 10bis link resolves and navigates, then shows the honest '
      'unsupportedSource message rather than a dead end',
      (tester) async {
        // Setup: no adapter is registered for MenuSource.tenbis, so the
        // fake repository's unstubbed default answers unsupportedSource —
        // the same failure the real MenuRepository returns.
        final fakes = FakeAppDependencies();
        await pumpApp(tester, fakes);

        // Act: paste the 10bis URL and open it.
        await enterText(tester, _tenBisUrl);
        await tapAndSettle(tester, find.text(_en.venueSearchOpen));

        // Assert: the honest unsupportedSource copy is shown, not a crash
        // or a blank screen.
        expect(find.text(_en.fetchFailedUnsupportedSource), findsOneWidget);
      },
    );

    testWidgets(
      'pasting a bare 10bis id behaves the same way as the full url',
      (tester) async {
        // Setup
        final fakes = FakeAppDependencies();
        await pumpApp(tester, fakes);

        // Act: paste a bare numeric id and open it.
        await enterText(tester, '654321');
        await tapAndSettle(tester, find.text(_en.venueSearchOpen));

        // Assert
        expect(find.text(_en.fetchFailedUnsupportedSource), findsOneWidget);
      },
    );
  });
}
