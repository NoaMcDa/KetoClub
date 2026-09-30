// `material.dart` exports its own `MenuController`, which would collide with
// ours from `state/` if that were imported. This file does not import our
// `MenuController`, but the hide is here to match the style the widget itself
// uses and to guard against a future import.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/menu_question.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/widgets/menu_question_sheet.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// A minimal dish with [id] and [name].
Dish _dish(String id, String name) =>
    Dish(id: id, name: name, description: '', price: 10, options: const []);

/// Pumps [sheet] inside a localised, themed [MaterialApp] with a [Scaffold],
/// so all localisation look-ups resolve.
Future<void> _pump(WidgetTester tester, MenuQuestionSheet sheet) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: sheet),
    ),
  );
}

void main() {
  group('MenuQuestionSheet', () {
    group('idle state', () {
      testWidgets('shows a text field and Ask button when idle', (
        tester,
      ) async {
        // Arrange
        await _pump(
          tester,
          MenuQuestionSheet(
            questionState: QuestionState.idle,
            answer: null,
            failure: null,
            allDishes: const [],
            onAsk: (_) {},
            onDismiss: () {},
          ),
        );

        // Assert
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text(_en.menuQuestionSheetAsk), findsOneWidget);
      });

      testWidgets('shows the hint text when idle', (tester) async {
        await _pump(
          tester,
          MenuQuestionSheet(
            questionState: QuestionState.idle,
            answer: null,
            failure: null,
            allDishes: const [],
            onAsk: (_) {},
            onDismiss: () {},
          ),
        );

        expect(find.text(_en.menuQuestionSheetHint), findsOneWidget);
      });

      testWidgets('calls onAsk with trimmed text when Ask is tapped', (
        tester,
      ) async {
        String? receivedQuestion;
        await _pump(
          tester,
          MenuQuestionSheet(
            questionState: QuestionState.idle,
            answer: null,
            failure: null,
            allDishes: const [],
            onAsk: (q) => receivedQuestion = q,
            onDismiss: () {},
          ),
        );

        await tester.enterText(find.byType(TextField), '  Is this keto?  ');
        await tester.tap(find.text(_en.menuQuestionSheetAsk));
        await tester.pump();

        expect(receivedQuestion, 'Is this keto?');
      });

      testWidgets('does not call onAsk when the text field is empty', (
        tester,
      ) async {
        var called = false;
        await _pump(
          tester,
          MenuQuestionSheet(
            questionState: QuestionState.idle,
            answer: null,
            failure: null,
            allDishes: const [],
            onAsk: (_) => called = true,
            onDismiss: () {},
          ),
        );

        // Leave the text field empty and tap Ask.
        await tester.tap(find.text(_en.menuQuestionSheetAsk));
        await tester.pump();

        expect(called, isFalse);
      });
    });

    group('loading state', () {
      testWidgets('shows a spinner when loading', (tester) async {
        await _pump(
          tester,
          MenuQuestionSheet(
            questionState: QuestionState.loading,
            answer: null,
            failure: null,
            allDishes: const [],
            onAsk: (_) {},
            onDismiss: () {},
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text(_en.menuQuestionSheetLoading), findsOneWidget);
      });

      testWidgets('hides the text field and Ask button when loading', (
        tester,
      ) async {
        await _pump(
          tester,
          MenuQuestionSheet(
            questionState: QuestionState.loading,
            answer: null,
            failure: null,
            allDishes: const [],
            onAsk: (_) {},
            onDismiss: () {},
          ),
        );

        expect(find.byType(TextField), findsNothing);
        expect(find.text(_en.menuQuestionSheetAsk), findsNothing);
      });
    });

    group('answered state', () {
      testWidgets('shows the answer text', (tester) async {
        const answer = MenuQuestionAnswered(
          answer: 'The steak is keto-friendly.',
          referencedDishIds: [],
        );
        await _pump(
          tester,
          MenuQuestionSheet(
            questionState: QuestionState.answered,
            answer: answer,
            failure: null,
            allDishes: const [],
            onAsk: (_) {},
            onDismiss: () {},
          ),
        );

        expect(find.text('The steak is keto-friendly.'), findsOneWidget);
      });

      testWidgets('shows Chip widgets for every referenced dish id that '
          'resolves in allDishes', (tester) async {
        final dish1 = _dish('d1', 'Grilled Steak');
        final dish2 = _dish('d2', 'Lamb Chops');
        const answer = MenuQuestionAnswered(
          answer: 'Both are keto.',
          referencedDishIds: ['d1', 'd2'],
        );
        await _pump(
          tester,
          MenuQuestionSheet(
            questionState: QuestionState.answered,
            answer: answer,
            failure: null,
            allDishes: [dish1, dish2],
            onAsk: (_) {},
            onDismiss: () {},
          ),
        );

        expect(find.text('Grilled Steak'), findsOneWidget);
        expect(find.text('Lamb Chops'), findsOneWidget);
        expect(find.byType(Chip), findsNWidgets(2));
      });

      testWidgets('does not crash when a referenced dish id is not in '
          'allDishes (invented id)', (tester) async {
        const answer = MenuQuestionAnswered(
          answer: 'Steak is fine.',
          referencedDishIds: ['invented-id'],
        );
        await _pump(
          tester,
          MenuQuestionSheet(
            questionState: QuestionState.answered,
            answer: answer,
            failure: null,
            allDishes: const [],
            onAsk: (_) {},
            onDismiss: () {},
          ),
        );

        // No chips for invented ids; the answer text still shows.
        expect(find.byType(Chip), findsNothing);
        expect(find.text('Steak is fine.'), findsOneWidget);
      });

      testWidgets('shows no Chip row when referencedDishIds is empty', (
        tester,
      ) async {
        const answer = MenuQuestionAnswered(
          answer: 'No specific dish mentioned.',
          referencedDishIds: [],
        );
        await _pump(
          tester,
          MenuQuestionSheet(
            questionState: QuestionState.answered,
            answer: answer,
            failure: null,
            allDishes: [_dish('d1', 'Steak')],
            onAsk: (_) {},
            onDismiss: () {},
          ),
        );

        expect(find.byType(Chip), findsNothing);
      });

      testWidgets('shows Ask-another button', (tester) async {
        const answer = MenuQuestionAnswered(
          answer: 'Good choice.',
          referencedDishIds: [],
        );
        await _pump(
          tester,
          MenuQuestionSheet(
            questionState: QuestionState.answered,
            answer: answer,
            failure: null,
            allDishes: const [],
            onAsk: (_) {},
            onDismiss: () {},
          ),
        );

        expect(find.text(_en.menuQuestionSheetAskAnother), findsOneWidget);
      });

      testWidgets('calls onDismiss when Ask-another is tapped', (tester) async {
        var dismissed = false;
        const answer = MenuQuestionAnswered(
          answer: 'Good choice.',
          referencedDishIds: [],
        );
        await _pump(
          tester,
          MenuQuestionSheet(
            questionState: QuestionState.answered,
            answer: answer,
            failure: null,
            allDishes: const [],
            onAsk: (_) {},
            onDismiss: () => dismissed = true,
          ),
        );

        await tester.tap(find.text(_en.menuQuestionSheetAskAnother));
        await tester.pump();

        expect(dismissed, isTrue);
      });
    });

    group('failed state', () {
      testWidgets('shows the failure message for the reason', (tester) async {
        await _pump(
          tester,
          MenuQuestionSheet(
            questionState: QuestionState.failed,
            answer: null,
            failure: MenuQuestionFailureReason.offline,
            allDishes: const [],
            onAsk: (_) {},
            onDismiss: () {},
          ),
        );

        expect(find.text(_en.menuQuestionFailedOffline), findsOneWidget);
      });

      testWidgets('shows the bad-response copy when failure is null', (
        tester,
      ) async {
        await _pump(
          tester,
          MenuQuestionSheet(
            questionState: QuestionState.failed,
            answer: null,
            failure: null,
            allDishes: const [],
            onAsk: (_) {},
            onDismiss: () {},
          ),
        );

        expect(find.text(_en.menuQuestionFailedBadResponse), findsOneWidget);
      });

      testWidgets('shows Ask-another button in failed state', (tester) async {
        await _pump(
          tester,
          MenuQuestionSheet(
            questionState: QuestionState.failed,
            answer: null,
            failure: MenuQuestionFailureReason.timeout,
            allDishes: const [],
            onAsk: (_) {},
            onDismiss: () {},
          ),
        );

        expect(find.text(_en.menuQuestionSheetAskAnother), findsOneWidget);
      });

      testWidgets(
        'calls onDismiss when Ask-another is tapped in failed state',
        (tester) async {
          var dismissed = false;
          await _pump(
            tester,
            MenuQuestionSheet(
              questionState: QuestionState.failed,
              answer: null,
              failure: MenuQuestionFailureReason.rateLimited,
              allDishes: const [],
              onAsk: (_) {},
              onDismiss: () => dismissed = true,
            ),
          );

          await tester.tap(find.text(_en.menuQuestionSheetAskAnother));
          await tester.pump();

          expect(dismissed, isTrue);
        },
      );
    });

    group('title', () {
      testWidgets('shows the sheet title in every state', (tester) async {
        for (final state in QuestionState.values) {
          await _pump(
            tester,
            MenuQuestionSheet(
              questionState: state,
              answer: state == QuestionState.answered
                  ? const MenuQuestionAnswered(
                      answer: 'yes',
                      referencedDishIds: [],
                    )
                  : null,
              failure: state == QuestionState.failed
                  ? MenuQuestionFailureReason.offline
                  : null,
              allDishes: const [],
              onAsk: (_) {},
              onDismiss: () {},
            ),
          );

          expect(
            find.text(_en.menuQuestionSheetTitle),
            findsOneWidget,
            reason: 'title should appear in state $state',
          );
        }
      });
    });
  });
}
