// Banto's four-state widgets (ALG-05, issue #347): the state pill, the
// dish card's state mode (concern lines, the Why button, the waiter row),
// the four counter tiles and the "Rules checked" chip, in English and
// Hebrew, light and dark. Each is also pinned to render exactly as before
// with a keto-only wording or bantoMode off.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/theme/verdict_colors.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/profile_wording.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/status_badge.dart';
import 'package:ketoclub/widgets/verdict_counter_tiles.dart';
import 'package:ketoclub/widgets/why_sheet.dart';
import 'package:provider/provider.dart';

/// Pumps [child] in a localised app, at [locale] and [theme].
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) {
  return tester.pumpWidget(
    ChangeNotifierProvider<CarbBudgetController>.value(
      value: CarbBudgetController(),
      child: MaterialApp(
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

/// A Hebrew tahini-and-nuts salad.
const Dish _hebrewDish = Dish(
  id: 'd1',
  name: 'סלט עם טחינה ואגוזים',
  description: '',
  price: 42,
  options: <DishOption>[],
);

/// An English dish.
const Dish _englishDish = Dish(
  id: 'd2',
  name: 'Nut cake',
  description: '',
  price: 30,
  options: <DishOption>[],
);

/// A green analysis of [dish] with a net-carb estimate.
AnalysedDish _analysed(Dish dish) => AnalysedDish(
  dishId: dish.id,
  name: dish.name,
  verdict: DishVerdict.orderAsIs,
  why: 'why',
  netCarbsEstimate: 4,
);

/// The sesame concern, stated in the name.
const Concern _sesame = Concern(
  restrictionId: RestrictionId.sesame,
  source: ConcernSource.name,
  certainty: Certainty.stated,
  tier: EvidenceTier.stated,
  matchedText: 'טחינה',
);

/// The peanut concern, suspected from "nuts".
const Concern _peanut = Concern(
  restrictionId: RestrictionId.peanuts,
  source: ConcernSource.hidden,
  certainty: Certainty.suspected,
  tier: EvidenceTier.suspected,
  matchedText: 'אגוזים',
);

/// A card for [dish] evaluated to [state] with [concerns].
DishCard _card(
  Dish dish,
  DishState state, {
  List<Concern> concerns = const <Concern>[],
  String? modification,
  ProfileWording wording = ProfileWording.strict,
  bool bantoMode = true,
  bool holdsKeto = false,
}) {
  final analysed = _analysed(dish);
  return DishCard(
    row: DishRow(dish: dish, category: 'Mains', analysis: analysed),
    localeTag: 'en',
    onShowScript: (_) {},
    evaluated: EvaluatedDish(
      dish: analysed,
      concerns: concerns,
      state: state,
      modification: modification,
    ),
    wording: wording,
    holdsKeto: holdsKeto,
    bantoMode: bantoMode,
  );
}

void main() {
  group('StateBadge', () {
    for (final (tag, locale) in <(String, Locale)>[
      ('en', const Locale('en')),
      ('he', const Locale('he')),
    ]) {
      testWidgets('every state has an icon and a word ($tag)', (tester) async {
        for (final state in DishState.values) {
          // Act
          await _pump(
            tester,
            StateBadge(state: state, wording: ProfileWording.strict),
            locale: locale,
          );

          // Assert
          expect(find.byType(Icon), findsOneWidget);
          expect(find.byType(Text), findsOneWidget);
          expect(
            find.byKey(stateBadgeOutlineKey),
            state == DishState.ask ? findsOneWidget : findsNothing,
          );
        }
      });
    }

    testWidgets('strict fits reads "ask the restaurant", not fits', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        const StateBadge(state: DishState.fits, wording: ProfileWording.strict),
      );

      // Assert
      expect(
        find.text('NO TRIGGER FOUND — ASK THE RESTAURANT'),
        findsOneWidget,
      );
    });

    for (final (name, theme) in <(String, ThemeData)>[
      ('light', AppTheme.light()),
      ('dark', AppTheme.dark()),
    ]) {
      testWidgets('ask is drawn in the ask tone ($name)', (tester) async {
        // Act
        await _pump(
          tester,
          const StateBadge(
            state: DishState.ask,
            wording: ProfileWording.strict,
          ),
          theme: theme,
        );

        // Assert
        final box = tester.widget<DecoratedBox>(
          find.byKey(stateBadgeOutlineKey),
        );
        final decoration = box.decoration as BoxDecoration;
        final tone = theme.extension<VerdictColors>()!.ask;
        expect(decoration.color, tone.pill);
        expect((decoration.border! as Border).top.color, tone.rail);
      });
    }
  });

  group('DishCard in state mode', () {
    testWidgets('a Hebrew dish shows Hebrew restriction names and the pill', (
      tester,
    ) async {
      // Act: the UI is English, the dish Hebrew.
      await _pump(
        tester,
        _card(
          _hebrewDish,
          DishState.avoid,
          concerns: const <Concern>[_sesame, _peanut],
        ),
      );

      // Assert
      expect(find.byType(StateBadge), findsOneWidget);
      expect(find.byType(StatusBadge), findsNothing);
      expect(find.text('AVOID'), findsOneWidget);
      expect(find.text('שומשום'), findsOneWidget);
      expect(find.text('בוטנים'), findsOneWidget);
      expect(find.text('in the name · stated'), findsOneWidget);
      expect(find.text('hidden: אגוזים · suspected — ask'), findsOneWidget);
      expect(find.byKey(dishConcernKey(1)), findsOneWidget);
      // Avoid has no waiter row, and keto is not in the profile.
      expect(find.text('Ask your waiter'), findsNothing);
      expect(find.textContaining('net carbs'), findsNothing);
    });

    testWidgets('the Hebrew UI words the concern line in Hebrew', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        _card(_hebrewDish, DishState.ask, concerns: const <Concern>[_peanut]),
        locale: const Locale('he'),
      );

      // Assert
      expect(find.text('בוטנים'), findsOneWidget);
      expect(find.text('רכיב נסתר: אגוזים · חשד — לשאול'), findsOneWidget);
      expect(find.text('מה לשאול את המלצר'), findsOneWidget);
      expect(find.text('למה?'), findsOneWidget);
    });

    testWidgets('ask offers the question to ask, in the dish language', (
      tester,
    ) async {
      // Arrange
      await _pump(
        tester,
        _card(_englishDish, DishState.ask, concerns: const <Concern>[_peanut]),
      );

      // Act
      await tester.tap(find.text('What to ask the waiter'));
      await tester.pumpAndSettle();

      // Assert
      expect(
        find.textContaining('Does this dish contain peanuts'),
        findsOneWidget,
      );
    });

    testWidgets("fits with a change offers the evaluator's change", (
      tester,
    ) async {
      // Arrange
      await _pump(
        tester,
        _card(
          _englishDish,
          DishState.fitsWithChange,
          modification: 'Ask for it without walnuts',
        ),
        theme: AppTheme.dark(),
      );

      // Act
      await tester.tap(find.text('Ask your waiter'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.textContaining('without walnuts'), findsOneWidget);
    });

    testWidgets('Why? opens the Why sheet with the dish concerns', (
      tester,
    ) async {
      // Arrange
      await _pump(
        tester,
        _card(
          _hebrewDish,
          DishState.avoid,
          concerns: const <Concern>[_sesame, _peanut],
        ),
      );

      // Act
      await tester.tap(find.byKey(dishWhyKey));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(WhySheet), findsOneWidget);
      expect(find.byKey(whyConcernKey(0)), findsOneWidget);
      expect(find.byKey(whyConcernKey(1)), findsOneWidget);
      expect(find.byKey(whyFooterKey), findsOneWidget);
    });

    testWidgets('keto in the profile keeps the net-carb chip', (tester) async {
      // Act
      await _pump(tester, _card(_englishDish, DishState.fits, holdsKeto: true));

      // Assert
      expect(find.textContaining('net carbs'), findsOneWidget);
    });

    testWidgets("keto-only wording renders today's card", (tester) async {
      // Act
      await _pump(
        tester,
        _card(
          _englishDish,
          DishState.avoid,
          concerns: const <Concern>[_peanut],
          wording: ProfileWording.ketoOnly,
        ),
      );

      // Assert: the wire verdict's pill, no concern line, no Why.
      expect(find.byType(StatusBadge), findsOneWidget);
      expect(find.byType(StateBadge), findsNothing);
      expect(find.byKey(dishWhyKey), findsNothing);
      expect(find.text('ORDER AS-IS'), findsOneWidget);
    });

    testWidgets("bantoMode off renders today's card", (tester) async {
      // Act
      await _pump(
        tester,
        _card(
          _englishDish,
          DishState.avoid,
          concerns: const <Concern>[_peanut],
          bantoMode: false,
        ),
      );

      // Assert
      expect(find.byType(StatusBadge), findsOneWidget);
      expect(find.byKey(dishConcernKey(0)), findsNothing);
    });
  });

  group('VerdictCounterTiles', () {
    for (final (tag, locale) in <(String, Locale)>[
      ('en', const Locale('en')),
      ('he', const Locale('he')),
    ]) {
      testWidgets('four tiles for a strict profile ($tag)', (tester) async {
        // Act
        await _pump(
          tester,
          VerdictCounterTiles(
            greenCount: 1,
            yellowCount: 2,
            askCount: 3,
            redCount: 4,
            filter: MenuFilter.greenAndYellow,
            onFilterChanged: (_) {},
            wording: ProfileWording.strict,
            bantoMode: true,
          ),
          locale: locale,
        );

        // Assert
        for (final count in <String>['1', '2', '3', '4']) {
          expect(find.text(count), findsOneWidget);
        }
        final label = tag == 'en' ? 'NO TRIGGER FOUND' : 'לא נמצא חשש';
        expect(find.text(label), findsOneWidget);
        expect(find.text(tag == 'en' ? 'TO ASK' : 'לשאול'), findsOneWidget);
      });
    }

    testWidgets('the ask tile selects askOnly, and again all', (tester) async {
      // Arrange
      final chosen = <MenuFilter>[];
      Future<void> pump(MenuFilter filter) => _pump(
        tester,
        VerdictCounterTiles(
          greenCount: 1,
          yellowCount: 0,
          askCount: 2,
          redCount: 0,
          filter: filter,
          onFilterChanged: chosen.add,
          wording: ProfileWording.flexible,
          bantoMode: true,
        ),
      );

      // Act
      await pump(MenuFilter.all);
      await tester.tap(find.text('TO ASK'));
      await pump(MenuFilter.askOnly);
      await tester.tap(find.text('TO ASK'));

      // Assert
      expect(chosen, <MenuFilter>[MenuFilter.askOnly, MenuFilter.all]);
      expect(find.text('FIT'), findsOneWidget);
    });

    testWidgets('keto-only wording keeps three tiles', (tester) async {
      // Act
      await _pump(
        tester,
        VerdictCounterTiles(
          greenCount: 1,
          yellowCount: 2,
          askCount: 3,
          redCount: 4,
          filter: MenuFilter.all,
          onFilterChanged: (_) {},
          bantoMode: true,
        ),
      );

      // Assert
      expect(find.text('3'), findsNothing);
      expect(find.text('ORDER AS-IS'), findsOneWidget);
    });
  });

  group('RulesCheckedChip', () {
    testWidgets('names the rules check in both languages', (tester) async {
      await _pump(tester, const RulesCheckedChip(bantoMode: true));
      expect(find.text('Rules checked'), findsOneWidget);
      await _pump(
        tester,
        const RulesCheckedChip(bantoMode: true),
        locale: const Locale('he'),
      );
      expect(find.text('נבדק גם בכללים'), findsOneWidget);
    });

    testWidgets('builds nothing with bantoMode off', (tester) async {
      await _pump(tester, const RulesCheckedChip());
      expect(find.byType(Text), findsNothing);
    });
  });
}
