import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/menu_question.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_question_parser.dart';

/// The venue every [Menu] built by this file is addressed to.
const VenueRef _venueRef = VenueRef(
  source: MenuSource.wolt,
  platformId: 'question-parser-test-venue',
);

/// A minimal dish with [id] and [name].
Dish _dish(String id, String name) =>
    Dish(id: id, name: name, description: '', price: 10, options: const []);

/// A menu addressed to [_venueRef] containing [dishes] in one category.
Menu _menuOf(List<Dish> dishes) => Menu(
  venueRef: _venueRef,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: [MenuCategory(id: 'cat-1', name: 'Mains', dishes: dishes)],
);

/// A well-formed reply body with [answer] and optional [dishIds].
String _validBody({required String answer, List<String> dishIds = const []}) =>
    jsonEncode(<String, Object?>{'answer': answer, 'dish_ids': dishIds});

void main() {
  group('MenuQuestionParser', () {
    group('happy path', () {
      test('parses a valid JSON reply into a MenuQuestionAnswered', () {
        final menu = _menuOf([_dish('d1', 'Steak')]);
        final body = _validBody(answer: 'The steak is keto-friendly.');

        final result = MenuQuestionParser.parse(body, menu);

        expect(result, isA<MenuQuestionAnswered>());
        final answered = result as MenuQuestionAnswered;
        expect(answered.answer, 'The steak is keto-friendly.');
        expect(answered.referencedDishIds, isEmpty);
      });

      test('includes real dish ids from the menu in referencedDishIds', () {
        final dish = _dish('steak-id', 'Grilled Steak');
        final menu = _menuOf([dish]);
        final body = _validBody(
          answer: 'The steak is keto-friendly.',
          dishIds: ['steak-id'],
        );

        final result = MenuQuestionParser.parse(body, menu);

        final answered = result as MenuQuestionAnswered;
        expect(answered.referencedDishIds, ['steak-id']);
      });

      test('drops invented dish ids not present in the menu', () {
        final menu = _menuOf([_dish('real-id', 'Real Dish')]);
        final body = _validBody(
          answer: 'Some dishes are keto-friendly.',
          dishIds: ['real-id', 'invented-id'],
        );

        final result = MenuQuestionParser.parse(body, menu);

        final answered = result as MenuQuestionAnswered;
        expect(answered.referencedDishIds, ['real-id']);
      });

      test('deduplicates dish ids keeping the first occurrence', () {
        final dish = _dish('d1', 'Dish One');
        final menu = _menuOf([dish]);
        final body = _validBody(
          answer: 'Great choice.',
          dishIds: ['d1', 'd1', 'd1'],
        );

        final result = MenuQuestionParser.parse(body, menu);

        final answered = result as MenuQuestionAnswered;
        expect(answered.referencedDishIds, ['d1']);
      });

      test('caps dish ids at 10', () {
        final dishes = [for (var i = 1; i <= 15; i++) _dish('d$i', 'Dish $i')];
        final menu = _menuOf(dishes);
        final body = _validBody(
          answer: 'Many keto options.',
          dishIds: [for (var i = 1; i <= 15; i++) 'd$i'],
        );

        final result = MenuQuestionParser.parse(body, menu);

        final answered = result as MenuQuestionAnswered;
        expect(answered.referencedDishIds, hasLength(10));
        expect(answered.referencedDishIds.first, 'd1');
        expect(answered.referencedDishIds.last, 'd10');
      });

      test('trims the answer', () {
        final menu = _menuOf([_dish('d1', 'Steak')]);
        final body = _validBody(answer: '   Yes, it is keto.   ');

        final result = MenuQuestionParser.parse(body, menu);

        final answered = result as MenuQuestionAnswered;
        expect(answered.answer, 'Yes, it is keto.');
      });

      test('caps the answer at 1200 characters', () {
        final menu = _menuOf([_dish('d1', 'Steak')]);
        final longAnswer = 'x' * 1500;
        final body = _validBody(answer: longAnswer);

        final result = MenuQuestionParser.parse(body, menu);

        final answered = result as MenuQuestionAnswered;
        expect(answered.answer.length, 1200);
        expect(answered.answer, 'x' * 1200);
      });

      test('accepts an answer exactly 1200 characters long', () {
        final menu = _menuOf([_dish('d1', 'Steak')]);
        final body = _validBody(answer: 'a' * 1200);

        final result = MenuQuestionParser.parse(body, menu);

        final answered = result as MenuQuestionAnswered;
        expect(answered.answer.length, 1200);
      });

      test('treats a missing dish_ids field as an empty list', () {
        final menu = _menuOf([_dish('d1', 'Steak')]);
        final body = jsonEncode(<String, Object?>{'answer': 'Great dish.'});

        final result = MenuQuestionParser.parse(body, menu);

        final answered = result as MenuQuestionAnswered;
        expect(answered.referencedDishIds, isEmpty);
      });

      test('treats a non-list dish_ids field as an empty list', () {
        final menu = _menuOf([_dish('d1', 'Steak')]);
        final body = jsonEncode(<String, Object?>{
          'answer': 'Great dish.',
          'dish_ids': 'not-a-list',
        });

        final result = MenuQuestionParser.parse(body, menu);

        final answered = result as MenuQuestionAnswered;
        expect(answered.referencedDishIds, isEmpty);
      });

      test('skips non-string entries inside dish_ids', () {
        final dish = _dish('d1', 'Steak');
        final menu = _menuOf([dish]);
        final body = jsonEncode(<String, Object?>{
          'answer': 'Good choice.',
          'dish_ids': <Object?>[42, null, 'd1', true],
        });

        final result = MenuQuestionParser.parse(body, menu);

        final answered = result as MenuQuestionAnswered;
        expect(answered.referencedDishIds, ['d1']);
      });

      test('skips blank string entries inside dish_ids', () {
        final dish = _dish('d1', 'Steak');
        final menu = _menuOf([dish]);
        final body = jsonEncode(<String, Object?>{
          'answer': 'Good choice.',
          'dish_ids': <Object?>['', '   ', 'd1'],
        });

        final result = MenuQuestionParser.parse(body, menu);

        final answered = result as MenuQuestionAnswered;
        // Blank strings are either empty after trim (dropped) or not in menu.
        expect(answered.referencedDishIds, ['d1']);
      });

      test('strips a json markdown fence', () {
        final menu = _menuOf([_dish('d1', 'Steak')]);
        const fenced =
            '```json\n{"answer": "Good option.", "dish_ids": []}\n```';

        final result = MenuQuestionParser.parse(fenced, menu);

        expect(result, isA<MenuQuestionAnswered>());
        final answered = result as MenuQuestionAnswered;
        expect(answered.answer, 'Good option.');
      });

      test('strips a bare markdown fence without a language tag', () {
        final menu = _menuOf([_dish('d1', 'Steak')]);
        const fenced = '```\n{"answer": "A bare fence.", "dish_ids": []}\n```';

        final result = MenuQuestionParser.parse(fenced, menu);

        expect(result, isA<MenuQuestionAnswered>());
        final answered = result as MenuQuestionAnswered;
        expect(answered.answer, 'A bare fence.');
      });

      test('referencedDishIds is unmodifiable', () {
        final menu = _menuOf([_dish('d1', 'Steak')]);
        final body = _validBody(answer: 'Good.', dishIds: ['d1']);

        final result =
            MenuQuestionParser.parse(body, menu) as MenuQuestionAnswered;

        // `referencedDishIds` is declared as `List<String>` but backed by
        // `List.unmodifiable`; the cast below is already typed so no warn.
        expect(() => result.referencedDishIds.add('x'), throwsUnsupportedError);
      });
    });

    group('badResponse failures', () {
      test('returns MenuQuestionFailed with badResponse on invalid JSON', () {
        final menu = _menuOf([_dish('d1', 'Steak')]);

        final result = MenuQuestionParser.parse('not-json!', menu);

        expect(result, isA<MenuQuestionFailed>());
        final failed = result as MenuQuestionFailed;
        expect(failed.reason, MenuQuestionFailureReason.badResponse);
      });

      test(
        'returns badResponse when the JSON root is an array not an object',
        () {
          final menu = _menuOf([_dish('d1', 'Steak')]);

          final result = MenuQuestionParser.parse(
            '[{"answer": "hi", "dish_ids": []}]',
            menu,
          );

          expect(result, isA<MenuQuestionFailed>());
          expect(
            (result as MenuQuestionFailed).reason,
            MenuQuestionFailureReason.badResponse,
          );
        },
      );

      test('returns badResponse when the JSON root is a string', () {
        final menu = _menuOf([_dish('d1', 'Steak')]);

        final result = MenuQuestionParser.parse('"just a string"', menu);

        expect(result, isA<MenuQuestionFailed>());
        expect(
          (result as MenuQuestionFailed).reason,
          MenuQuestionFailureReason.badResponse,
        );
      });

      test('returns badResponse when answer field is missing', () {
        final menu = _menuOf([_dish('d1', 'Steak')]);
        final body = jsonEncode(<String, Object?>{'dish_ids': []});

        final result = MenuQuestionParser.parse(body, menu);

        expect(result, isA<MenuQuestionFailed>());
        expect(
          (result as MenuQuestionFailed).reason,
          MenuQuestionFailureReason.badResponse,
        );
      });

      test('returns badResponse when answer field is null', () {
        final menu = _menuOf([_dish('d1', 'Steak')]);
        final body = jsonEncode(<String, Object?>{
          'answer': null,
          'dish_ids': [],
        });

        final result = MenuQuestionParser.parse(body, menu);

        expect(result, isA<MenuQuestionFailed>());
        expect(
          (result as MenuQuestionFailed).reason,
          MenuQuestionFailureReason.badResponse,
        );
      });

      test('returns badResponse when answer field is not a string', () {
        final menu = _menuOf([_dish('d1', 'Steak')]);
        final body = jsonEncode(<String, Object?>{
          'answer': 42,
          'dish_ids': [],
        });

        final result = MenuQuestionParser.parse(body, menu);

        expect(result, isA<MenuQuestionFailed>());
        expect(
          (result as MenuQuestionFailed).reason,
          MenuQuestionFailureReason.badResponse,
        );
      });

      test('returns badResponse when answer is empty after trimming', () {
        final menu = _menuOf([_dish('d1', 'Steak')]);
        final body = _validBody(answer: '   ');

        final result = MenuQuestionParser.parse(body, menu);

        expect(result, isA<MenuQuestionFailed>());
        expect(
          (result as MenuQuestionFailed).reason,
          MenuQuestionFailureReason.badResponse,
        );
      });

      test('parse never throws — even on truly broken input', () {
        final menu = _menuOf([_dish('d1', 'Steak')]);

        // Should not throw.
        expect(() => MenuQuestionParser.parse('', menu), returnsNormally);
        expect(
          () => MenuQuestionParser.parse('\x00\x01\x02', menu),
          returnsNormally,
        );
        expect(() => MenuQuestionParser.parse('null', menu), returnsNormally);
      });
    });
  });
}
