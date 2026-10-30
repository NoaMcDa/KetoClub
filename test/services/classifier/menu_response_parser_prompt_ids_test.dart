// MenuResponseParser.parse with the prompt's short ids
// (MenuAnalysisPrompt.promptIds): a reply id is read through them first,
// then compared with the dishes' own ids, then the name is read.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_analysis_prompt.dart';
import 'package:ketoclub/services/classifier/menu_response_parser.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/wolt/wolt_menu_mapper.dart';

const AnalysisEngine _engine = LlmEngine(model: 'test-model');

final DateTime _analysedAt = DateTime.utc(2026, 10, 28);

Dish _dish(String id, String name) =>
    Dish(id: id, name: name, description: '', price: 10, options: const []);

Menu _menuOf(List<Dish> dishes) => Menu(
  venueRef: const VenueRef(source: MenuSource.wolt, platformId: 'venue'),
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: [MenuCategory(id: 'cat-1', name: 'Mains', dishes: dishes)],
);

String _reply(List<(String id, String name, String verdict)> elements) =>
    jsonEncode(<String, Object?>{
      'dishes': <Object?>[
        for (final (id, name, verdict) in elements)
          <String, Object?>{
            'id': id,
            'name': name,
            'verdict': verdict,
            'why': 'Reason.',
            'modification': verdict == 'modifiable' ? 'No bun.' : null,
            'net_carbs_estimate': null,
            'hidden_carbs': <Object?>[],
          },
      ],
    });

MenuAnalysed _parse(String body, Menu source, {bool withPromptIds = true}) =>
    MenuResponseParser.parse(
      body,
      source: source,
      promptIds: withPromptIds
          ? MenuAnalysisPrompt.promptIds(source)
          : const <String, String>{},
      analysedAt: _analysedAt,
      engine: _engine,
    ) as MenuAnalysed;

List<(String, DishVerdict)> _placed(MenuAnalysed analysis) => [
  for (final dish in analysis.dishes) (dish.dishId, dish.verdict),
];

void main() {
  final burgerA = _dish('65b0c1f2a3d4e5f60718293a', 'Smashburger');
  final burgerB = _dish('65b0c1f2a3d4e5f60718293b', 'Smashburger');
  final salad = _dish('65b0c1f2a3d4e5f6071829ff', 'Caesar Salad');
  final fries = _dish('1', 'Fries');
  final menu = _menuOf([burgerA, burgerB, salad, fries]);

  group('MenuResponseParser.parse through promptIds', () {
    test('short ids place every dish, two of one name included', () {
      // Act
      final analysis = _parse(
        _reply([
          ('1', 'Smashburger', 'orderAsIs'),
          ('2', 'Smashburger', 'modifiable'),
          ('3', 'Caesar Salad', 'nonKeto'),
          ('4', 'Fries', 'nonKeto'),
        ]),
        menu,
      );

      // Assert
      expect(_placed(analysis), [
        (burgerA.id, DishVerdict.orderAsIs),
        (burgerB.id, DishVerdict.modifiable),
        (salad.id, DishVerdict.nonKeto),
        (fries.id, DishVerdict.nonKeto),
      ]);
      expect(analysis.unclassified, isEmpty);
    });

    test('a short id wins over a reworded name', () {
      // Act
      final analysis = _parse(
        _reply([('2', 'Special Smashburger 🌟', 'nonKeto')]),
        menu,
      );

      // Assert: the source dish's own name, never the model's.
      expect(_placed(analysis), [(burgerB.id, DishVerdict.nonKeto)]);
      expect(analysis.dishes.single.name, 'Smashburger');
    });

    test('a short id wins over a platform id spelled the same', () {
      // Act: '1' is the first dish's prompt id and the fries' own id.
      final analysis = _parse(_reply([('1', 'Fries', 'nonKeto')]), menu);

      // Assert
      expect(_placed(analysis), [(burgerA.id, DishVerdict.nonKeto)]);
    });

    test('full platform ids, from a model ignoring the short ids, still '
        'place their dishes', () {
      // Act
      final analysis = _parse(
        _reply([
          (burgerB.id, 'Smashburger', 'nonKeto'),
          (salad.id, 'Caesar Salad', 'orderAsIs'),
        ]),
        menu,
      );

      // Assert
      expect(_placed(analysis), [
        (burgerB.id, DishVerdict.nonKeto),
        (salad.id, DishVerdict.orderAsIs),
      ]);
    });

    test('an id that is neither falls back to the name, and a dish is '
        'never placed twice', () {
      // Act
      final analysis = _parse(
        _reply([
          ('9', 'Caesar Salad', 'nonKeto'),
          ('3', 'Caesar Salad', 'orderAsIs'),
          ('65b0c1f2a3d4e5f6', 'Smashburger', 'modifiable'),
          ('65b0c1f2a3d4e5f6', 'Smashburger', 'nonKeto'),
        ]),
        menu,
      );

      // Assert: the prefixes both name the first burger by name, so the
      // second is a duplicate and its namesake goes unplaced.
      expect(_placed(analysis), [
        (salad.id, DishVerdict.nonKeto),
        (burgerA.id, DishVerdict.modifiable),
      ]);
      expect(analysis.unclassified, ['Smashburger', 'Fries']);
    });

    test('the recorded Hebrew smoke reply (16-character id prefixes) parses '
        'exactly as it does without prompt ids', () {
      // Arrange: the recorded Wolt menu, mapped as the app maps it, and
      // the reply Gemini sent for it.
      final payload = jsonDecode(
        File('test/fixtures/wolt_hamosad_menu.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final wolt = (WoltMenuMapper.toMenu(
        payload,
        ref: const VenueRef(source: MenuSource.wolt, platformId: 'hamosad'),
        fetchedAt: DateTime.utc(2026, 9, 25),
      ) as MenuFetched).menu;
      final wrapper = jsonDecode(
        File('test/fixtures/llm/smoke_10_dish_hebrew.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final body = wrapper['content']! as String;

      // Act
      final withIds = _parse(body, wolt);
      final without = _parse(body, wolt, withPromptIds: false);

      // Assert
      expect(withIds.toJson(), without.toJson());
      expect(withIds.dishes, isNotEmpty);
    });
  });
}
