// "They changed the dish as requested" on reopen (Banto, ALG-14, D27):
// the person's answer about the change they asked for is a dated line on
// the dish card and in the Why sheet, in English and Hebrew; it never
// changes the dish's state, and a keto build never shows it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dish_confirmation.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/profile_wording.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/status_badge.dart';
import 'package:ketoclub/widgets/why_sheet.dart';
import 'package:provider/provider.dart';

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

const Dish _dish = Dish(
  id: 'd1',
  name: 'סלט עם טחינה',
  description: '',
  price: 42,
  options: <DishOption>[],
);

const Concern _sesame = Concern(
  restrictionId: RestrictionId.sesame,
  source: ConcernSource.option,
  certainty: Certainty.stated,
  tier: EvidenceTier.stated,
  matchedText: 'טחינה',
);

final ChangeConfirmation _yes = ChangeConfirmation(
  dishId: 'd1',
  honoured: true,
  day: DateTime(2026, 5, 12),
);

final ChangeConfirmation _no = ChangeConfirmation(
  dishId: 'd1',
  honoured: false,
  day: DateTime(2026, 5, 12),
);

DishCard _card({
  ChangeConfirmation? answer,
  bool bantoMode = true,
  ProfileWording wording = ProfileWording.strict,
}) {
  const analysed = AnalysedDish(
    dishId: 'd1',
    name: 'סלט עם טחינה',
    verdict: DishVerdict.orderAsIs,
    why: 'why',
  );
  return DishCard(
    row: const DishRow(dish: _dish, category: 'Mains', analysis: analysed),
    localeTag: 'en',
    onShowScript: (_) {},
    evaluated: const EvaluatedDish(
      dish: analysed,
      concerns: <Concern>[_sesame],
      state: DishState.fitsWithChange,
      modification: 'לבקש את המנה בלי טחינה',
    ),
    wording: wording,
    holdsKeto: false,
    bantoMode: bantoMode,
    changeAnswer: answer,
  );
}

void main() {
  group('the dish card', () {
    testWidgets('shows the dated yes in English, with the state unchanged', (
      tester,
    ) async {
      // Act
      await _pump(tester, _card(answer: _yes));

      // Assert
      expect(
        find.text('The staff changed it as you asked, May 12'),
        findsOneWidget,
      );
      final badge = tester.widget<StateBadge>(find.byType(StateBadge));
      expect(badge.state, DishState.fitsWithChange);
    });

    testWidgets('shows the dated no in Hebrew', (tester) async {
      // Act
      await _pump(tester, _card(answer: _no), locale: const Locale('he'));

      // Assert
      final line = tester.widget<Text>(find.byKey(dishChangeAnswerKey));
      expect(line.data, contains('הצוות לא שינה את המנה כפי שביקשת'));
      expect(line.data, contains('12 במאי'));
    });

    testWidgets('shows nothing without an answer', (tester) async {
      await _pump(tester, _card());
      expect(find.byKey(dishChangeAnswerKey), findsNothing);
    });

    testWidgets('a keto build, or keto-only wording, never shows it', (
      tester,
    ) async {
      await _pump(tester, _card(answer: _yes, bantoMode: false));
      expect(find.byKey(dishChangeAnswerKey), findsNothing);

      await _pump(
        tester,
        _card(answer: _yes, wording: ProfileWording.ketoOnly),
      );
      expect(find.byKey(dishChangeAnswerKey), findsNothing);
    });

    testWidgets('Why? carries the answer to the sheet', (tester) async {
      // Arrange
      await _pump(tester, _card(answer: _yes));

      // Act
      await tester.tap(find.byKey(dishWhyKey));
      await tester.pumpAndSettle();

      // Assert
      expect(
        find.text(
          'On May 12 the staff changed the dish as you asked. That was for '
          'that visit, so ask for the change again each time.',
        ),
        findsOneWidget,
      );
    });
  });

  group('the Why sheet', () {
    Widget sheet(ChangeConfirmation? answer) => WhySheet(
      dishName: 'סלט עם טחינה',
      concerns: const <Concern>[_sesame],
      strictProfile: true,
      changeAnswer: answer,
      bantoMode: true,
    );

    testWidgets('dates the no in English', (tester) async {
      await _pump(tester, sheet(_no));
      expect(
        find.text('On May 12 the staff did not make the change you asked for.'),
        findsOneWidget,
      );
    });

    testWidgets('dates the yes in Hebrew, never saying safe', (tester) async {
      // Act
      await _pump(tester, sheet(_yes), locale: const Locale('he'));

      // Assert
      final line = tester.widget<Text>(find.byKey(whyChangeAnswerKey));
      expect(line.data, contains('הצוות שינה את המנה כפי שביקשת'));
      expect(line.data, contains('12 במאי'));
      expect(line.data, isNot(contains('בטוח')));
    });

    testWidgets('has no line without an answer', (tester) async {
      await _pump(tester, sheet(null));
      expect(find.byKey(whyChangeAnswerKey), findsNothing);
    });
  });
}
