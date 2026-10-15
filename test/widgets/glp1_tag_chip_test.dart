// The small-portions tag on the dish card (Banto; ALG-17's GLP-1
// follow-up, issue #359) and the Why sheet's coverage note opened from it
// (ALG-06, issue #348). The tag is words in a neutral outline: it never
// changes the state pill, the colours or the order.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/profile_wording.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/status_badge.dart';
import 'package:ketoclub/widgets/why_sheet.dart';
import 'package:provider/provider.dart';

final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _he = AppLocalizationsHe();

/// Pumps [child] in a localised app with a carb-budget controller.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
}) => tester.pumpWidget(
  ChangeNotifierProvider<CarbBudgetController>.value(
    value: CarbBudgetController(),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

/// A grilled salmon starter, read by the rules (no ingredient list).
const Dish _salmon = Dish(
  id: 's',
  name: 'Grilled salmon',
  description: '',
  price: 50,
  options: <DishOption>[],
);

/// Its keto-green analysis.
const AnalysedDish _analysed = AnalysedDish(
  dishId: 's',
  name: 'Grilled salmon',
  verdict: DishVerdict.orderAsIs,
  why: 'Fits',
);

/// A card for [_salmon] under [category], in flexible state mode.
DishCard _card({
  bool smallPortions = true,
  bool bantoMode = true,
  String category = 'Starters',
  ProfileWording wording = ProfileWording.flexible,
}) => DishCard(
  row: DishRow(dish: _salmon, category: category, analysis: _analysed),
  localeTag: 'en',
  onShowScript: (_) {},
  evaluated: const EvaluatedDish(
    dish: _analysed,
    concerns: <Concern>[],
    state: DishState.fits,
  ),
  wording: wording,
  holdsKeto: false,
  bantoMode: bantoMode,
  smallPortions: smallPortions,
);

void main() {
  group('the small-portions tag', () {
    testWidgets('shows both halves for a protein starter', (tester) async {
      // Act
      await _pump(tester, _card());

      // Assert
      expect(find.byKey(dishGlp1TagKey), findsOneWidget);
      expect(
        find.text('${_en.glp1TagProteinForward} · ${_en.glp1TagSmallPortion}'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          _en.glp1TagSemanticLabel(
            '${_en.glp1TagProteinForward} · ${_en.glp1TagSmallPortion}',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows the half that applies, in Hebrew', (tester) async {
      // Act
      await _pump(tester, _card(category: 'Mains'), locale: const Locale('he'));

      // Assert
      expect(find.text(_he.glp1TagProteinForward), findsOneWidget);
      expect(find.textContaining(_he.glp1TagSmallPortion), findsNothing);
    });

    testWidgets('never changes the state pill', (tester) async {
      // Act
      await _pump(tester, _card(smallPortions: false));
      final without = tester.widget<StateBadge>(find.byType(StateBadge));
      await _pump(tester, _card());
      final tagged = tester.widget<StateBadge>(find.byType(StateBadge));

      // Assert
      expect(tagged.state, without.state);
      expect(tagged.wording, without.wording);
    });

    testWidgets('is absent without small portions in the profile', (
      tester,
    ) async {
      await _pump(tester, _card(smallPortions: false));

      expect(find.byKey(dishGlp1TagKey), findsNothing);
    });

    testWidgets('is absent with Banto off or on a keto-only screen', (
      tester,
    ) async {
      await _pump(tester, _card(bantoMode: false));
      expect(find.byKey(dishGlp1TagKey), findsNothing);

      await _pump(tester, _card(wording: ProfileWording.ketoOnly));
      expect(find.byKey(dishGlp1TagKey), findsNothing);
    });

    test('the copy carries no number', () {
      for (final l10n in <AppLocalizations>[_en, _he]) {
        for (final text in <String>[
          l10n.glp1TagProteinForward,
          l10n.glp1TagSmallPortion,
          l10n.glp1TagSemanticLabel(''),
        ]) {
          expect(text, isNot(matches(RegExp('[0-9%]'))));
        }
      }
    });
  });

  group('the Why sheet from the card (ALG-06)', () {
    testWidgets('says the rules alone read this dish', (tester) async {
      // Arrange
      await _pump(tester, _card());

      // Act
      await tester.tap(find.byKey(dishWhyKey));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byKey(whyCoverageKey), findsOneWidget);
      expect(
        find.text('${_en.whyCoverageNameOnly} ${_en.whyCoverageRulesOnly}'),
        findsOneWidget,
      );
    });
  });
}
