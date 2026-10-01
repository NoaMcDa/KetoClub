// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §15, §18.4): the
// journey of pasting a Wolt link and seeing the resulting menu classified
// into keto verdicts, filtered, and turned into a waiter script; and
// searching it from behind the Filters row (issue #234).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:ketoclub/widgets/menu_search_field.dart';
import 'package:ketoclub/widgets/rules_reason_banner.dart';
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

/// The loaded menu's list. Named explicitly because the screen holds
/// other scrollables too — the search field and the category chip row
/// (issue #51), and on a wide window the side pane (issue #225), which
/// `flutter drive`'s 1600px window shows — and `scrollUntilVisible` needs
/// exactly one: the list under the RefreshIndicator.
final Finder _menuList = find
    .descendant(
      of: find.descendant(
        of: find.byType(RefreshIndicator),
        matching: find.byType(ListView),
      ),
      matching: find.byType(Scrollable),
    )
    .first;

/// The yellow counter tile, found inside the counter row: a yellow dish's
/// badge now carries the same words (issue #243).
final Finder _yellowTile = find.descendant(
  of: find.byType(VerdictCounterTiles),
  matching: find.text(_en.tileYellowLabel.toUpperCase()),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Menu display flow', () {
    // The Waiter Card's copy button goes through `Clipboard.setData`, which
    // needs a platform channel this binding does not provide on its own;
    // a mock handler that records every call stands in for it (mirrors
    // test/widgets/waiter_script_widget_test.dart).
    late List<MethodCall> platformCalls;

    setUp(() {
      platformCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            platformCalls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

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
      await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

      // Assert: the classified menu is shown — the verdict counter tiles
      // and the rules banner only appear once an analysis has landed,
      // the source line names the platform, and every dish is visible
      // under the default filter. Issue #35 changed `AppSettings`'s
      // default from `greenAndYellow` to `all` (no tile could reproduce
      // the old default), so the non-keto dish shows here too; it is
      // third in a deliberately lazy `ListView` (CLAUDE.md's traps), so
      // it must be scrolled into view before it is findable.
      expect(find.byType(RulesReasonBanner), findsOneWidget);
      expect(find.byType(VerdictCounterTiles), findsOneWidget);
      expect(find.textContaining('Wolt'), findsWidgets);
      expect(find.text(fixture.green.name), findsOneWidget);
      expect(find.text(fixture.yellow.name), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(fixture.red.name),
        200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      expect(find.text(fixture.red.name), findsOneWidget);
      expect(find.byType(DishCard), findsNWidgets(3));

      // Act: scroll back up until the yellow counter tile itself is on
      // screen. Scrolling to some other widget and hoping the tile came
      // with it depends on the viewport's height — it holds on web and
      // fails on the smaller flutter-tester surface. Scroll to the thing
      // about to be tapped.
      await tester.scrollUntilVisible(_yellowTile, -200, scrollable: _menuList);
      await tester.pumpAndSettle();

      // Act: tap the "With changes" tile to narrow to the modifiable dish
      // alone — the acceptance criterion's "filter to yellow".
      await tapAndSettle(tester, _yellowTile);

      // Assert: only the modifiable dish shows.
      expect(find.byType(DishCard), findsOneWidget);
      expect(find.text(fixture.yellow.name), findsOneWidget);
      expect(find.text(fixture.green.name), findsNothing);
      expect(find.text(_en.menuShowingYellow), findsOneWidget);

      // Act: tap the now-active tile again to return to showing everything.
      await tapAndSettle(tester, _yellowTile);

      // Assert: every verdict is back, including the non-keto dish — issue
      // #29 shows red dishes inline under "all" rather than in a separate
      // always-collapsed group. The red dish is third in a ListView that
      // stays deliberately lazy (CLAUDE.md's traps), so it must be
      // scrolled into view before a widget below the fold is findable.
      expect(find.text(fixture.green.name), findsOneWidget);
      expect(find.text(fixture.yellow.name), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(fixture.red.name),
        200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      expect(find.text(fixture.red.name), findsOneWidget);

      // Act: scroll back up to the modifiable dish, expand its script and
      // open its Waiter Card from inside it — the scroll above may have
      // taken its disclosure row out of the lazy list's built range.
      await tester.scrollUntilVisible(
        find.text(_en.dishCardAskWaiter),
        -200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.text(_en.dishCardAskWaiter));
      await tester.scrollUntilVisible(
        find.text(_en.dishCardFullScreen),
        200,
        scrollable: _menuList,
      );
      await tapAndSettle(tester, find.text(_en.dishCardFullScreen));

      // Assert: the Waiter Card is open and its script text is on screen.
      expect(find.byType(WaiterCardSheet), findsOneWidget);
      expect(find.text(_yellowScript), findsWidgets);

      // Act: copy the script from the Waiter Card.
      // The dish card behind the sheet has its own Copy button; the sheet's
      // is the last one in the tree.
      await tapAndSettle(tester, find.text(_en.waiterCardCopyButton).last);

      // Assert: the confirmation shows, and the plain script — not any
      // numbering the card draws around it — reached the clipboard.
      expect(find.text(_en.waiterCardCopied), findsOneWidget);
      final setData = platformCalls.singleWhere(
        (call) => call.method == 'Clipboard.setData',
      );
      final arguments = setData.arguments as Map<Object?, Object?>;
      expect(arguments['text'], _yellowScript);
    });

    testWidgets(
      'user opens the Filters row, searches the menu, and the search keeps '
      'narrowing it alongside a verdict tile once the row is closed',
      (tester) async {
        // Setup: the same scripted menu as the journey above.
        final fixture = _buildFixture();
        final fakes = FakeAppDependencies();
        fakes.repository.stub(_ref, MenuFetched(menu: fixture.menu));
        fakes.classifier.respondWith(fixture.analysis);
        await pumpApp(tester, fakes);
        await enterText(tester, _woltUrl);
        await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

        // Assert: the search field sits behind the collapsed Filters row,
        // and the first dish is already on screen above the fold.
        expect(find.text(_en.menuFilters), findsOneWidget);
        expect(find.byType(MenuSearchField), findsNothing);
        expect(find.text(fixture.green.name), findsOneWidget);

        // Act: open the row and search for the steak.
        await tapAndSettle(tester, find.text(_en.menuFilters));
        final searchField = find.descendant(
          of: find.byType(MenuSearchField),
          matching: find.byType(TextField),
        );
        await tester.enterText(searchField, 'steak');
        await tester.pumpAndSettle();

        // Assert: only the matching dish is left.
        expect(find.byType(DishCard), findsOneWidget);
        expect(find.text(fixture.green.name), findsOneWidget);
        expect(find.text(fixture.yellow.name), findsNothing);

        // Act: close the row, then narrow to the modifiable tile.
        await tapAndSettle(tester, find.text(_en.menuFiltersActive(1)));
        await tester.scrollUntilVisible(
          _yellowTile,
          -200,
          scrollable: _menuList,
        );
        await tester.pumpAndSettle();
        await tapAndSettle(tester, _yellowTile);

        // Assert: the hidden search still applies with the tile — no
        // modifiable dish matches "steak" — and the row says a filter is
        // active, so the empty list is explained.
        expect(find.byType(DishCard), findsNothing);
        expect(find.text(_en.menuNoResults), findsOneWidget);
        expect(find.text(_en.menuFiltersActive(1)), findsOneWidget);
      },
    );
  });
}
