// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §9.5, §18.4):
// the journey of opening a classified menu and asking a free-text question
// about it — from the app-bar icon through the modal sheet to the answer
// and the Ask-another reset (issue #214).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/menu_question.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/widgets/menu_question_sheet.dart';

import 'flow_support.dart';

/// The Wolt venue URL the user pastes.
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/test-question-venue';

/// The [VenueRef] that URL resolves to.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'test-question-venue',
);

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// A menu and matching LLM analysis to drive the question flow.
({Menu menu, MenuAnalysed analysis, Dish steak}) _buildFixture() {
  const steak = Dish(
    id: 'steak',
    name: 'Herb Butter Steak',
    description: '',
    price: 42,
    options: <DishOption>[],
  );
  final menu = Menu(
    venueRef: _ref,
    currency: 'ILS',
    fetchedAt: DateTime.utc(2026),
    categories: const [
      MenuCategory(id: 'c1', name: 'Mains', dishes: [steak]),
    ],
  );
  final analysis = MenuAnalysed(
    dishes: const [
      AnalysedDish(
        dishId: 'steak',
        name: 'Herb Butter Steak',
        verdict: DishVerdict.orderAsIs,
        why: 'Lean protein, no carbs.',
      ),
    ],
    unclassified: const <String>[],
    engine: const LlmEngine(model: 'test-model'),
    analysedAt: DateTime.utc(2026),
  );
  return (menu: menu, analysis: analysis, steak: steak);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Menu question flow', () {
    testWidgets('happy path: ask a question and see the answer with chips', (
      tester,
    ) async {
      // Setup: script a menu with an LLM analysis and a canned answer.
      final fixture = _buildFixture();
      final fakes = FakeAppDependencies();
      fakes.repository.stub(_ref, MenuFetched(menu: fixture.menu));
      fakes.classifier.respondWith(fixture.analysis);
      fakes.questionAnswerer.enqueueAnswer(
        'The steak is perfect for keto.',
        dishIds: ['steak'],
      );
      await pumpApp(tester, fakes);

      // Act: open the menu.
      await enterText(tester, _woltUrl);
      await tapAndSettle(tester, find.text(_en.venueSearchOpen));

      // Assert: the question icon appears in the app bar (LLM analysis
      // succeeded, so isQuestionAvailable is true).
      expect(
        find.byIcon(Icons.question_answer),
        findsOneWidget,
        reason: 'question icon must appear after an LLM analysis',
      );

      // Act: tap the question icon to open the sheet.
      await tapAndSettle(tester, find.byIcon(Icons.question_answer));

      // Assert: the sheet is open and showing the idle state.
      expect(find.byType(MenuQuestionSheet), findsOneWidget);
      expect(find.text(_en.menuQuestionSheetTitle), findsOneWidget);
      // Scope the field lookup to the sheet — the menu screen itself has a
      // search field and a carb-budget field, so a bare `TextField` finder
      // is ambiguous.
      final sheetField = find.descendant(
        of: find.byType(MenuQuestionSheet),
        matching: find.byType(TextField),
      );
      expect(sheetField, findsOneWidget);

      // Act: type a question and tap Ask.
      await tester.enterText(sheetField, 'Is the steak keto-friendly?');
      await tapAndSettle(tester, find.text(_en.menuQuestionSheetAsk));

      // Assert: the answer is shown, including a chip for the referenced dish.
      // The dish name also appears in the DishCard behind the sheet, so
      // scope the chip lookup to the sheet.
      expect(find.text('The steak is perfect for keto.'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MenuQuestionSheet),
          matching: find.text(fixture.steak.name),
        ),
        findsOneWidget,
      );

      // Verify the question answerer received the question.
      expect(fakes.questionAnswerer.calls, hasLength(1));
      expect(
        fakes.questionAnswerer.calls.single.question,
        'Is the steak keto-friendly?',
      );

      // Act: tap Ask-another to reset to idle.
      await tapAndSettle(tester, find.text(_en.menuQuestionSheetAskAnother));

      // Assert: the sheet is back to idle.
      expect(sheetField, findsOneWidget);
      expect(find.text('The steak is perfect for keto.'), findsNothing);
    });

    testWidgets('failure path: question answerer returns an error', (
      tester,
    ) async {
      // Setup
      final fixture = _buildFixture();
      final fakes = FakeAppDependencies();
      fakes.repository.stub(_ref, MenuFetched(menu: fixture.menu));
      fakes.classifier.respondWith(fixture.analysis);
      fakes.questionAnswerer.enqueue(
        const MenuQuestionFailed(reason: MenuQuestionFailureReason.offline),
      );
      await pumpApp(tester, fakes);

      // Act: open the menu and ask a question.
      await enterText(tester, _woltUrl);
      await tapAndSettle(tester, find.text(_en.venueSearchOpen));
      await tapAndSettle(tester, find.byIcon(Icons.question_answer));
      await tester.enterText(
        find.descendant(
          of: find.byType(MenuQuestionSheet),
          matching: find.byType(TextField),
        ),
        'What can I eat?',
      );
      await tapAndSettle(tester, find.text(_en.menuQuestionSheetAsk));

      // Assert: the offline failure message is shown.
      expect(find.text(_en.menuQuestionFailedOffline), findsOneWidget);
      expect(find.text(_en.menuQuestionSheetAskAnother), findsOneWidget);
    });

    testWidgets('question icon is absent after a rules-engine analysis', (
      tester,
    ) async {
      // Setup: classifier returns a RulesEngine analysis.
      final fixture = _buildFixture();
      final fakes = FakeAppDependencies();
      fakes.repository.stub(_ref, MenuFetched(menu: fixture.menu));
      fakes.classifier.respondWith(
        MenuAnalysed(
          dishes: const [
            AnalysedDish(
              dishId: 'steak',
              name: 'Herb Butter Steak',
              verdict: DishVerdict.orderAsIs,
              why: 'Lean protein.',
            ),
          ],
          unclassified: const <String>[],
          engine: const RulesEngine(
            reason: MenuAnalysisFailureReason.notConfigured,
          ),
          analysedAt: DateTime.utc(2026),
        ),
      );
      await pumpApp(tester, fakes);

      // Act: open the menu.
      await enterText(tester, _woltUrl);
      await tapAndSettle(tester, find.text(_en.venueSearchOpen));

      // Assert: the question icon must not appear.
      expect(
        find.byIcon(Icons.question_answer),
        findsNothing,
        reason:
            'question icon must not appear when analysis used the rule engine',
      );
    });
  });
}
