// Widget tests for [CarbBudgetField] (issue #215, architecture.md §6.6).
//
// Covers the enabled state and the render-nothing disabled state, in
// English and Hebrew.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/widgets/carb_budget_field.dart';
import 'package:provider/provider.dart';

/// English strings used in assertions.
final AppLocalizations _en = AppLocalizationsEn();

/// Hebrew strings used in assertions.
final AppLocalizations _he = AppLocalizationsHe();

/// Pumps a [CarbBudgetField] with [isBudgetAvailable] inside a localised
/// [MaterialApp], injecting a [CarbBudgetController] via Provider.
Future<void> _pump(
  WidgetTester tester, {
  required bool isBudgetAvailable,
  Locale locale = const Locale('en'),
  CarbBudgetController? carbBudget,
}) {
  final controller = carbBudget ?? CarbBudgetController();
  return tester.pumpWidget(
    ChangeNotifierProvider<CarbBudgetController>.value(
      value: controller,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: CarbBudgetField(isBudgetAvailable: isBudgetAvailable),
        ),
      ),
    ),
  );
}

void main() {
  group('CarbBudgetField', () {
    group('enabled state (isBudgetAvailable: true)', () {
      testWidgets('shows a text field with the label', (tester) async {
        await _pump(tester, isBudgetAvailable: true);

        expect(find.byType(TextField), findsOneWidget);
        expect(find.text(_en.carbBudgetFieldLabel), findsOneWidget);
      });

      testWidgets('entering a value and submitting sets the budget', (
        tester,
      ) async {
        final budget = CarbBudgetController();
        addTearDown(budget.dispose);
        await _pump(tester, isBudgetAvailable: true, carbBudget: budget);

        await tester.enterText(find.byType(TextField), '15');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(budget.budgetGrams, equals(15));
      });

      testWidgets('typing a non-numeric value clears the budget', (
        tester,
      ) async {
        final budget = CarbBudgetController()..setBudget(20);
        addTearDown(budget.dispose);
        await _pump(tester, isBudgetAvailable: true, carbBudget: budget);

        await tester.enterText(find.byType(TextField), '');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(budget.budgetGrams, isNull);
      });

      testWidgets('a budget already set shows a clear button', (tester) async {
        final budget = CarbBudgetController()..setBudget(10);
        addTearDown(budget.dispose);
        await _pump(tester, isBudgetAvailable: true, carbBudget: budget);

        expect(find.widgetWithIcon(IconButton, Icons.clear), findsOneWidget);
      });

      testWidgets('tapping the clear button clears the budget', (tester) async {
        final budget = CarbBudgetController()..setBudget(10);
        addTearDown(budget.dispose);
        await _pump(tester, isBudgetAvailable: true, carbBudget: budget);

        await tester.tap(find.widgetWithIcon(IconButton, Icons.clear));
        await tester.pump();

        expect(budget.budgetGrams, isNull);
      });

      testWidgets('shows the Hebrew label in the he locale', (tester) async {
        await _pump(
          tester,
          isBudgetAvailable: true,
          locale: const Locale('he'),
        );

        expect(find.text(_he.carbBudgetFieldLabel), findsOneWidget);
      });
    });

    group('disabled state (isBudgetAvailable: false)', () {
      testWidgets('renders nothing: no field, label, hint or notice', (
        tester,
      ) async {
        await _pump(tester, isBudgetAvailable: false);

        expect(find.byType(TextField), findsNothing);
        expect(find.text(_en.carbBudgetFieldLabel), findsNothing);
        expect(find.text(_en.carbBudgetFieldHint), findsNothing);
        expect(tester.getSize(find.byType(CarbBudgetField)), equals(Size.zero));
      });

      testWidgets('renders nothing in the he locale either', (tester) async {
        await _pump(
          tester,
          isBudgetAvailable: false,
          locale: const Locale('he'),
        );

        expect(find.byType(TextField), findsNothing);
        expect(find.text(_he.carbBudgetFieldLabel), findsNothing);
        expect(tester.getSize(find.byType(CarbBudgetField)), equals(Size.zero));
      });

      testWidgets('shows the field once the budget becomes available', (
        tester,
      ) async {
        await _pump(tester, isBudgetAvailable: false);
        await _pump(tester, isBudgetAvailable: true);

        expect(find.byType(TextField), findsOneWidget);
      });
    });
  });
}
