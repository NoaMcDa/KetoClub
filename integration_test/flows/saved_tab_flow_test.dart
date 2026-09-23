// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §18.4; issue #48):
// open a venue's menu, find it listed on the Saved tab, and reopen it from
// there — the "works offline" promise, driven end to end through the real
// UI rather than by asserting on FlowFakeMenuRepository directly.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/widgets/engine_chip.dart';

import 'flow_support.dart';

/// The Wolt venue page the user pastes (architecture.md §6.5 Tier A).
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/vitrina-lilinblum';

/// The [VenueRef] [_woltUrl] resolves to.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'vitrina-lilinblum',
);

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Saved tab flow', () {
    testWidgets(
      'user opens a venue, finds it on Saved, and reopens it from there',
      (tester) async {
        // Setup: a repository and classifier scripted to answer the pasted
        // link's venue with a named, single-dish menu.
        final fixtureMenu = Menu(
          venueRef: _ref,
          currency: 'ILS',
          fetchedAt: DateTime.utc(2026),
          venueName: 'Vitrina',
          categories: const [
            MenuCategory(
              id: 'c1',
              name: 'Mains',
              dishes: [
                Dish(
                  id: 'green',
                  name: 'Herb Butter Steak',
                  description: '',
                  price: 42,
                  options: <DishOption>[],
                ),
              ],
            ),
          ],
        );
        final analysis = MenuAnalysed(
          dishes: const [
            AnalysedDish(
              dishId: 'green',
              name: 'Herb Butter Steak',
              verdict: DishVerdict.orderAsIs,
              why: 'Protein and butter, no starch.',
            ),
          ],
          unclassified: const <String>[],
          engine: const RulesEngine(
            reason: MenuAnalysisFailureReason.notConfigured,
          ),
          analysedAt: DateTime.utc(2026),
        );
        final fakes = FakeAppDependencies();
        fakes.repository.stub(_ref, MenuFetched(menu: fixtureMenu));
        fakes.classifier.respondWith(analysis);
        await pumpApp(tester, fakes);

        // Act: paste the link and open the venue.
        await enterText(tester, _woltUrl);
        await tapAndSettle(tester, find.text(_en.venueSearchOpen));

        // Assert: the menu opened.
        expect(find.text('Herb Butter Steak'), findsOneWidget);

        // Act: back to Explore (the venue route is pushed on top of the
        // Explore tab's own route, not a tab root itself, so a plain pop
        // returns to it — `app.dart`'s own doc comment on this route),
        // then to Saved via the bottom nav.
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tapAndSettle(tester, navDestination(_en.navSaved));

        // Assert: the just-opened venue is listed, named, with its dish
        // count and the engine that analysed it.
        expect(find.text('Vitrina'), findsOneWidget);
        expect(find.text(_en.savedEntryDishCount(1)), findsOneWidget);
        expect(find.byType(EngineChip), findsOneWidget);

        // Act: tap it to reopen the same menu.
        await tapAndSettle(tester, find.text('Vitrina'));

        // Assert: the same dish is shown again — served from cache, the
        // way it would be offline too.
        expect(find.text('Herb Butter Steak'), findsOneWidget);
      },
    );
  });
}
