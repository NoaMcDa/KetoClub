// MenuScreen in Banto's four-state mode (ALG-05, issue #347): the header
// counts in place of the keto score, the four tiles, the state legend
// with the helper-tool sentence, the "Rules checked" chip and the Showing
// label, in English and Hebrew, light and dark; and the same screen with
// bantoMode off or a keto-only profile rendering exactly as before.
import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/menu_screen.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/keto_score_badge.dart';
import 'package:ketoclub/widgets/status_badge.dart';
import 'package:ketoclub/widgets/verdict_counter_tiles.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_connectivity.dart';
import '../fakes/fake_external_link_opener.dart';
import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_menu_sharer.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_screen_brightness.dart';
import '../fakes/fake_settings_store.dart';

/// The venue every test opens.
const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

/// A dish named [name] with [id].
Dish _dish(String id, String name) => Dish(
  id: id,
  name: name,
  description: '',
  price: 10,
  options: const <DishOption>[],
);

/// A tahini salad, a nut cake and a steak.
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'מנות',
      dishes: <Dish>[
        _dish('salad', 'סלט עם טחינה'),
        _dish('cake', 'עוגת אגוזים'),
        _dish('steak', 'סטייק'),
      ],
    ),
  ],
);

/// A controller whose classifier answers every dish green from the model,
/// over settings holding [profile].
MenuController _controller(DietaryProfile profile) {
  final repository = FakeMenuRepository()..stub(_ref, MenuFetched(menu: _menu));
  final classifier = FakeMenuClassifier()
    ..respondWith(
      MenuAnalysed(
        dishes: <AnalysedDish>[
          for (final dish in _menu.allDishes)
            AnalysedDish(
              dishId: dish.id,
              name: dish.name,
              verdict: DishVerdict.orderAsIs,
              why: 'why',
            ),
        ],
        unclassified: const <String>[],
        engine: const LlmEngine(model: 'm'),
        analysedAt: DateTime.utc(2026),
      ),
    );
  return MenuController(
    repository,
    classifier,
    FakeSettingsStore(initial: AppSettings(profile: profile)),
    FakeNotesStore(),
    CarbBudgetController(),
  );
}

/// Pumps the screen over [controller] and lets it open.
Future<void> _pump(
  WidgetTester tester,
  MenuController controller, {
  required bool bantoMode,
  Locale locale = const Locale('en'),
  ThemeData? theme,
  Size size = const Size(390, 2400),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<CarbBudgetController>.value(
      value: CarbBudgetController(),
      child: MaterialApp(
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ChangeNotifierProvider<MenuController>.value(
          value: controller,
          child: MenuScreen(
            ref: _ref,
            screenBrightness: FakeScreenBrightness(),
            connectivity: FakeConnectivity(),
            externalLinkOpener: FakeExternalLinkOpener(),
            menuSharer: FakeMenuSharer(),
            bantoMode: bantoMode,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Peanuts and sesame.
final DietaryProfile _strict = DietaryProfile.empty
    .withEntry(RestrictionId.peanuts)
    .withEntry(RestrictionId.sesame);

void main() {
  for (final (tag, locale) in <(String, Locale)>[
    ('en', const Locale('en')),
    ('he', const Locale('he')),
  ]) {
    for (final (mode, theme) in <(String, ThemeData)>[
      ('light', AppTheme.light()),
      ('dark', AppTheme.dark()),
    ]) {
      testWidgets('a strict profile: counts, four tiles, no score '
          '($tag, $mode)', (tester) async {
        // Arrange
        final l10n = lookupAppLocalizations(locale);

        // Act
        await _pump(
          tester,
          _controller(_strict),
          bantoMode: true,
          locale: locale,
          theme: theme,
        );

        // Assert
        expect(find.byType(KetoScoreBadge), findsNothing);
        expect(find.byKey(menuHeaderCountsKey), findsOneWidget);
        expect(
          find.text(l10n.headerStateCountsStrict(1, 0, 1)),
          findsOneWidget,
        );
        expect(find.text(l10n.stateAskTile.toUpperCase()), findsOneWidget);
        expect(find.text(l10n.menuShowingNotAvoid), findsOneWidget);
        expect(find.byType(RulesCheckedChip), findsOneWidget);
        // The tahini salad is avoided, so hidden by default.
        expect(find.text('סלט עם טחינה'), findsNothing);
        expect(find.byType(StateBadge), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the state legend carries the helper-tool sentence ($tag)', (
      tester,
    ) async {
      // Arrange
      final l10n = lookupAppLocalizations(locale);
      await _pump(
        tester,
        _controller(_strict),
        bantoMode: true,
        locale: locale,
      );

      // Act: open the Filters row, then the legend.
      await tester.tap(find.text(l10n.menuFilters));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.legendToggle));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(l10n.helperToolSentence), findsOneWidget);
      expect(find.text(l10n.stateLegendFoodOnly), findsOneWidget);
      expect(find.text(l10n.legendNote), findsNothing);
    });
  }

  // The visual pass (docs/VISUAL_AUDIT.md, "Banto four-state menu"): what
  // the web audit could not reach without a model, pinned here instead.
  for (final (tag, locale) in <(String, Locale)>[
    ('en', const Locale('en')),
    ('he', const Locale('he')),
  ]) {
    testWidgets('the AI and "Rules checked" chips wrap, never overflow, at '
        '320px and large text ($tag)', (tester) async {
      // Act
      await _pump(
        tester,
        _controller(_strict),
        bantoMode: true,
        locale: locale,
        size: const Size(320, 3200),
        textScale: 1.6,
      );

      // Assert: both chips drawn, nothing overflowing.
      expect(find.byType(EngineChip), findsOneWidget);
      expect(find.byType(RulesCheckedChip), findsOneWidget);
      expect(tester.takeException(), isNull);
      final ai = tester.getRect(find.byType(EngineChip));
      final rules = tester.getRect(find.byType(RulesCheckedChip));
      expect(ai.right, lessThanOrEqualTo(320));
      expect(rules.right, lessThanOrEqualTo(320));
      expect(rules.left, greaterThanOrEqualTo(0));
    });

    testWidgets('two panes at 1280px: the side pane sits at the start '
        '($tag)', (tester) async {
      // Act
      await _pump(
        tester,
        _controller(_strict),
        bantoMode: true,
        locale: locale,
        size: const Size(1280, 800),
      );

      // Assert: the tiles and counts in the side pane, the dishes beside
      // it, mirrored in Hebrew.
      expect(tester.takeException(), isNull);
      final tiles = tester.getRect(find.byType(VerdictCounterTiles));
      final dish = tester.getRect(find.byType(DishCard).first);
      if (tag == 'he') {
        expect(tiles.left, greaterThan(dish.right));
      } else {
        expect(tiles.right, lessThan(dish.left));
      }
      expect(find.byKey(menuHeaderCountsKey), findsOneWidget);
    });
  }

  testWidgets('keto in the profile keeps the keto score', (tester) async {
    // Act
    await _pump(
      tester,
      _controller(
        DietaryProfile.empty
            .withEntry(RestrictionId.keto)
            .withEntry(RestrictionId.sesame),
      ),
      bantoMode: true,
    );

    // Assert
    expect(find.byType(KetoScoreBadge), findsOneWidget);
    expect(find.byKey(menuHeaderCountsKey), findsNothing);
    expect(find.text('TO ASK'), findsOneWidget);
  });

  testWidgets("bantoMode off renders today's screen", (tester) async {
    // Act
    await _pump(tester, _controller(_strict), bantoMode: false);

    // Assert
    expect(find.byType(KetoScoreBadge), findsOneWidget);
    expect(find.byType(StateBadge), findsNothing);
    expect(find.byType(StatusBadge), findsNWidgets(3));
    expect(find.byType(RulesCheckedChip), findsNothing);
    expect(find.text('TO ASK'), findsNothing);
  });

  testWidgets("a keto-only profile renders today's screen", (tester) async {
    // Act
    await _pump(tester, _controller(DietaryProfile.empty), bantoMode: true);

    // Assert
    expect(find.byType(KetoScoreBadge), findsOneWidget);
    expect(find.byType(StateBadge), findsNothing);
    expect(find.byType(StatusBadge), findsNWidgets(3));
  });
}
