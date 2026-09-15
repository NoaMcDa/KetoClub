// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §15, §18.4): the
// journey of pasting a Wolt link and seeing the resulting menu classified
// into keto verdicts, filtered, and turned into a waiter script.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/waiter_card_sheet.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/verdict_counter_tiles.dart';

import 'flow_support.dart';

/// The Wolt venue page the user pastes, in the documented
/// `wolt.com/{lang}/{country}/{city}/restaurant/{slug}` form
/// (architecture.md §6.5 Tier A).
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/vitrina-lilinblum';

/// The [VenueRef] [_woltUrl] resolves to, and the key the fakes below are
/// stubbed under.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'vitrina-lilinblum',
);

/// The waiter script for the modifiable dish in [_buildFixture].
const String _yellowScript = 'Ask for a green salad instead of fries.';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// One [Menu] with a green, a modifiable, and a non-keto dish, and the
/// [MenuAnalysed] verdicts matching it, built once so the journey below
/// drives the real UI over a fixed, known fixture.
({Menu menu, MenuAnalysed analysis, Dish green, Dish yellow, Dish red})
_buildFixture() {
  const green = Dish(
    id: 'green',
    name: 'Herb Butter Steak',
    description: '',
    price: 42,
    options: <DishOption>[],
  );
  const yellow = Dish(
    id: 'yellow',
    name: 'Sirloin with Fries',
    description: '',
    price: 38,
    options: <DishOption>[],
  );
  const red = Dish(
    id: 'red',
    name: 'Spaghetti Carbonara',
    description: '',
    price: 30,
    options: <DishOption>[],
  );
  final menu = Menu(
    venueRef: _ref,
    currency: 'ILS',
    fetchedAt: DateTime.utc(2026),
    categories: const [
      MenuCategory(id: 'c1', name: 'Mains', dishes: [green, yellow, red]),
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
      AnalysedDish(
        dishId: 'yellow',
        name: 'Sirloin with Fries',
        verdict: DishVerdict.modifiable,
        why: 'The steak is keto-safe; the fries are not.',
        modification: _yellowScript,
      ),
      AnalysedDish(
        dishId: 'red',
        name: 'Spaghetti Carbonara',
        verdict: DishVerdict.nonKeto,
        why: 'Pasta is fundamentally high-carb.',
      ),
    ],
    unclassified: const <String>[],
    engine: const RulesEngine(reason: MenuAnalysisFailureReason.notConfigured),
    analysedAt: DateTime.utc(2026),
  );
  return (
    menu: menu,
    analysis: analysis,
    green: green,
    yellow: yellow,
    red: red,
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Menu display flow', () {
    testWidgets('user pastes a Wolt link and sees the classified menu', (
      tester,
    ) async {
      // Setup: a repository and classifier scripted to answer the pasted
      // link's venue with a menu that has one dish of each verdict.
      final fixture = _buildFixture();
      final fakes = FakeAppDependencies();
      fakes.repository.stub(_ref, MenuFetched(menu: fixture.menu));
      fakes.classifier.respondWith(fixture.analysis);
      await pumpApp(tester, fakes);

      // Act: paste the link and open the venue.
      await enterText(tester, _woltUrl);
      await tapAndSettle(tester, find.text(_en.venueSearchOpen));

      // Assert: the classified menu is shown — the verdict counter tiles
      // and the engine chip only appear once an analysis has succeeded,
      // the source line names the platform, and the green and modifiable
      // dishes are both visible under the default filter (red is not).
      expect(find.byType(EngineChip), findsOneWidget);
      expect(find.byType(VerdictCounterTiles), findsOneWidget);
      expect(find.textContaining('Wolt'), findsWidgets);
      expect(find.text(fixture.green.name), findsOneWidget);
      expect(find.text(fixture.yellow.name), findsOneWidget);
      expect(find.text(fixture.red.name), findsNothing);
      expect(find.byType(DishCard), findsNWidgets(2));

      // Act: tap the "With changes" tile to narrow to the modifiable dish
      // alone — the acceptance criterion's "filter to yellow".
      await tapAndSettle(tester, find.text(_en.tileYellowLabel.toUpperCase()));

      // Assert: only the modifiable dish shows.
      expect(find.byType(DishCard), findsOneWidget);
      expect(find.text(fixture.yellow.name), findsOneWidget);
      expect(find.text(fixture.green.name), findsNothing);
      expect(find.text(_en.menuShowingYellow), findsOneWidget);

      // Act: tap the now-active tile again to return to showing everything.
      await tapAndSettle(tester, find.text(_en.tileYellowLabel.toUpperCase()));

      // Assert: every verdict is back, including the non-keto dish — issue
      // #29 shows red dishes inline under "all" rather than in a separate
      // always-collapsed group. The red dish is third in a ListView that
      // stays deliberately lazy (CLAUDE.md's traps), so it must be
      // scrolled into view before a widget below the fold is findable.
      expect(find.text(fixture.green.name), findsOneWidget);
      expect(find.text(fixture.yellow.name), findsOneWidget);
      await tester.scrollUntilVisible(find.text(fixture.red.name), 200);
      await tester.pumpAndSettle();
      expect(find.text(fixture.red.name), findsOneWidget);

      // Act: scroll back up to the modifiable dish and open its Waiter
      // Card — the scroll above may have taken its button out of the
      // lazy list's built range.
      await tester.scrollUntilVisible(find.text(_en.waiterCardOpen), -200);
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.text(_en.waiterCardOpen));

      // Assert: the Waiter Card is open and its script text is on screen.
      expect(find.byType(WaiterCardSheet), findsOneWidget);
      expect(find.text(_yellowScript), findsWidgets);
    });
  });
}
