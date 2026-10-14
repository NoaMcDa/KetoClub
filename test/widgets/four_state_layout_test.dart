// The layout fixes of the four-state menu's visual pass (Banto, ALG-05,
// issue #347; docs/VISUAL_AUDIT.md, "Banto four-state menu"): at a 390px
// phone width, in English and Hebrew, light and dark, the dish card's state
// pill keeps the "add a note" icon on the pill's line (B1), nothing overflows
// with long concern chips, the "Why?" button is a semantics node of its own
// rather than the whole card (B2), the four tiles share one height,
// the Why sheet lays the dish name out in its own direction (B4), and the
// "Why?" button draws the keyboard focus ring (B5).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/profile_wording.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/focus_ring.dart';
import 'package:ketoclub/widgets/status_badge.dart';
import 'package:ketoclub/widgets/verdict_counter_tiles.dart';
import 'package:ketoclub/widgets/why_sheet.dart';
import 'package:provider/provider.dart';

import '../fakes/focus_ring_probe.dart';

/// The phone width the audit renders at.
const Size _phone = Size(390, 844);

/// The locales and themes every layout test runs under.
final List<(String, Locale, ThemeData)> _variants =
    <(String, Locale, ThemeData)>[
      ('en light', const Locale('en'), AppTheme.light()),
      ('en dark', const Locale('en'), AppTheme.dark()),
      ('he light', const Locale('he'), AppTheme.light()),
      ('he dark', const Locale('he'), AppTheme.dark()),
    ];

/// Pumps [child] at the phone width with the menu screen's 20px gutters.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required Locale locale,
  required ThemeData theme,
}) async {
  tester.view.physicalSize = _phone;
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
        home: Scaffold(
          // A ListView, as the menu screen's: each child is then a
          // semantics node of its own, which a Semantics without
          // `container` merges into (finding B2).
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [child],
          ),
        ),
      ),
    ),
  );
}

/// A Hebrew dish whose concerns name four restrictions.
const Dish _dish = Dish(
  id: 'd1',
  name: 'סמאשבורגר עם גבינת שמנת, טחינה ואגוזים',
  description: 'קציצת סמאש כפולה בלחמניית בריוש עם רוטב הבית',
  price: 59,
  options: <DishOption>[],
);

/// Concerns with long matched text, so the concern chips wrap.
const List<Concern> _concerns = <Concern>[
  Concern(
    restrictionId: RestrictionId.peanuts,
    source: ConcernSource.hidden,
    certainty: Certainty.suspected,
    tier: EvidenceTier.suspected,
    matchedText: 'רוטב הבית של השף עם אגוזים קלויים',
  ),
  Concern(
    restrictionId: RestrictionId.milk,
    source: ConcernSource.option,
    certainty: Certainty.stated,
    tier: EvidenceTier.stated,
    matchedText: 'גבינת שמנת',
  ),
  Concern(
    restrictionId: RestrictionId.sesame,
    source: ConcernSource.model,
    certainty: Certainty.likely,
    tier: EvidenceTier.inferred,
    matchedText: 'לחמניית בריוש עם שומשום',
  ),
  Concern(
    restrictionId: RestrictionId.lactose,
    source: ConcernSource.description,
    certainty: Certainty.stated,
    tier: EvidenceTier.stated,
  ),
];

/// A card for [_dish] in [state], strictly worded, with a note button.
DishCard _card(DishState state) {
  final analysed = AnalysedDish(
    dishId: _dish.id,
    name: _dish.name,
    verdict: DishVerdict.orderAsIs,
    why: 'why',
  );
  return DishCard(
    row: DishRow(dish: _dish, category: 'Mains', analysis: analysed),
    localeTag: 'he',
    onShowScript: (_) {},
    onEditNote: (_) {},
    evaluated: EvaluatedDish(
      dish: analysed,
      concerns: _concerns,
      state: state,
      modification: state == DishState.fitsWithChange
          ? "לבקש את המנה בלי 'גבינת שמנת'"
          : null,
    ),
    wording: ProfileWording.strict,
    bantoMode: true,
  );
}

void main() {
  group('DishCard at 390px (B1)', () {
    for (final (name, locale, theme) in _variants) {
      for (final state in DishState.values) {
        testWidgets('${state.name}, $name: the note icon shares the pill '
            'line and nothing overflows', (tester) async {
          // Act
          await _pump(tester, _card(state), locale: locale, theme: theme);

          // Assert: no RenderFlex overflow, at any state.
          expect(tester.takeException(), isNull);
          final header = find.byKey(dishStateHeaderKey);
          expect(header, findsOneWidget);
          final pill = tester.getRect(find.byType(StateBadge));
          final note = tester.getRect(
            find.descendant(of: header, matching: find.byType(IconButton)),
          );
          // The icon sits beside the pill, not on a line below it.
          expect(note.top, lessThan(pill.bottom));
          expect(pill.top, lessThan(note.bottom));
          // And at the end of the line: right in English, left in Hebrew.
          if (locale.languageCode == 'he') {
            expect(note.right, lessThanOrEqualTo(pill.left));
          } else {
            expect(note.left, greaterThanOrEqualTo(pill.right));
          }
        });
      }
    }

    testWidgets('a keto card keeps its Wrap header', (tester) async {
      // Arrange: the same dish on a keto-only screen.
      final analysed = AnalysedDish(
        dishId: _dish.id,
        name: _dish.name,
        verdict: DishVerdict.orderAsIs,
        why: 'why',
      );

      // Act
      await _pump(
        tester,
        DishCard(
          row: DishRow(dish: _dish, category: 'Mains', analysis: analysed),
          localeTag: 'he',
          onShowScript: (_) {},
          onEditNote: (_) {},
          bantoMode: true,
        ),
        locale: const Locale('he'),
        theme: AppTheme.light(),
      );

      // Assert
      expect(find.byKey(dishStateHeaderKey), findsNothing);
      expect(find.byType(StatusBadge), findsOneWidget);
    });
  });

  group('DishCard semantics (B2)', () {
    testWidgets('"Why?" is a button node of its own, not the card', (
      tester,
    ) async {
      // Arrange
      final handle = tester.ensureSemantics();

      // Act
      await _pump(
        tester,
        _card(DishState.ask),
        locale: const Locale('en'),
        theme: AppTheme.light(),
      );

      // Assert: the Why node is a button with its own tap and label.
      final why = tester.getSemantics(
        find.bySemanticsLabel('Why this result for ${_dish.name}'),
      );
      expect(why.flagsCollection.isButton, isTrue);
      expect(why.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      // The card's own node, which carries the pill's label, is neither a
      // button nor tappable, and does not swallow the Why label.
      final card = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^Verdict: ')),
      );
      expect(card.label, isNot(contains('Why this result for')));
      expect(card.flagsCollection.isButton, isFalse);
      expect(card.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      // Each concern line is a node of its own.
      for (final concern in _concerns) {
        final name = restrictionFor(concern.restrictionId).nameHe;
        expect(
          find.bySemanticsLabel(RegExp('^${RegExp.escape(name)}')),
          findsOneWidget,
        );
      }
      handle.dispose();
    });
  });

  testWidgets('the "Why?" button draws the keyboard focus ring (B5)', (
    tester,
  ) async {
    // Arrange
    await _pump(
      tester,
      _card(DishState.fits),
      locale: const Locale('he'),
      theme: AppTheme.dark(),
    );
    final ring = find.ancestor(
      of: find.byKey(dishWhyKey),
      matching: find.byType(FocusRing),
    );
    expect(ring, findsOneWidget);
    expect(focusRingShown(tester, ring), isFalse);

    // Act: Tab until the Why button holds focus (the note icon is first).
    var shown = false;
    for (var i = 0; i < 6 && !shown; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      shown = focusRingShown(tester, ring);
    }

    // Assert
    expect(shown, isTrue);
  });

  group('WhySheet menu text (B4)', () {
    for (final (ui, dishName, expected) in <(Locale, String, TextDirection)>[
      (const Locale('en'), 'סמאשבורגר', TextDirection.rtl),
      (const Locale('he'), 'Smash burger', TextDirection.ltr),
      (const Locale('he'), 'סמאשבורגר', TextDirection.rtl),
    ]) {
      testWidgets('"$dishName" in the ${ui.languageCode} UI reads '
          '${expected.name}', (tester) async {
        // Act
        await _pump(
          tester,
          WhySheet(
            dishName: dishName,
            concerns: const <Concern>[
              Concern(
                restrictionId: RestrictionId.sesame,
                source: ConcernSource.hidden,
                certainty: Certainty.suspected,
                tier: EvidenceTier.suspected,
                matchedText: 'בלחמנייה',
                waiterQuestion: 'האם יש שומשום בלחמנייה?',
              ),
            ],
            strictProfile: true,
            bantoMode: true,
          ),
          locale: ui,
          theme: AppTheme.light(),
        );

        // Assert: the dish name follows its own text, at the matching
        // edge; the Hebrew waiter question reads right to left.
        final name = find.byKey(whyDishNameKey);
        expect(tester.widget<Text>(name).textDirection, expected);
        final question = find.text('האם יש שומשום בלחמנייה?');
        expect(tester.widget<Text>(question).textDirection, TextDirection.rtl);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('VerdictCounterTiles at 390px', () {
    for (final (name, locale, theme) in _variants) {
      testWidgets('four strict tiles share one height ($name)', (tester) async {
        // Act
        await _pump(
          tester,
          VerdictCounterTiles(
            greenCount: 128,
            yellowCount: 2,
            askCount: 15,
            redCount: 15,
            filter: MenuFilter.greenAndYellow,
            onFilterChanged: (_) {},
            wording: ProfileWording.strict,
            bantoMode: true,
          ),
          locale: locale,
          theme: theme,
        );

        // Assert
        expect(tester.takeException(), isNull);
        final tiles = find.descendant(
          of: find.byType(VerdictCounterTiles),
          matching: find.byType(InkWell),
        );
        expect(tiles, findsNWidgets(4));
        final heights = <double>{
          for (final element in tiles.evaluate())
            tester.getSize(find.byWidget(element.widget)).height,
        };
        expect(heights, hasLength(1));
      });
    }
  });
}
