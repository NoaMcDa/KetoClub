// Dish.declaredTags (Banto, ALG-09, issue #351): read tolerantly, written
// only when non-empty, so a dish with none is the JSON it always was.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/menu.dart';

void main() {
  const validJson = <String, Object?>{
    'id': 'dish_1',
    'name': 'Ribeye',
    'description': '300g',
    'price': 45.5,
    'options': <Object?>[],
  };

  group('Dish.declaredTags', () {
    test('a dish with no tags writes no declaredTags key', () {
      // Arrange
      const dish = Dish(
        id: 'dish_1',
        name: 'Ribeye',
        description: '300g',
        price: 45.5,
        options: <DishOption>[],
      );

      // Act
      final json = dish.toJson();

      // Assert
      expect(json.keys, <String>[
        'id',
        'name',
        'description',
        'price',
        'options',
        'imageUrl',
        'page',
      ]);
    });

    test('tags are written last and round-trip', () {
      // Arrange
      const dish = Dish(
        id: 'dish_1',
        name: 'Ribeye',
        description: '300g',
        price: 45.5,
        options: <DishOption>[],
        declaredTags: <String>['kosher', 'GLUTEN_FREE'],
      );

      // Act
      final json = dish.toJson();
      final back = Dish.tryFrom(json);

      // Assert
      expect(json.keys.last, 'declaredTags');
      expect(back, equals(dish));
      expect(back?.declaredTags, <String>['kosher', 'GLUTEN_FREE']);
    });

    test('an entry cached before the field existed reads as no tags', () {
      // Act
      final dish = Dish.tryFrom(validJson);

      // Assert
      expect(dish?.declaredTags, isEmpty);
    });

    for (final raw in <Object?>[null, 'kosher', 7, <String, Object?>{}]) {
      test('a declaredTags of $raw reads as no tags, not a failure', () {
        // Act
        final dish = Dish.tryFrom(<String, Object?>{
          ...validJson,
          'declaredTags': raw,
        });

        // Assert
        expect(dish, isNotNull);
        expect(dish?.declaredTags, isEmpty);
      });
    }

    test('non-string and blank entries are dropped, the rest kept', () {
      // Act
      final dish = Dish.tryFrom(<String, Object?>{
        ...validJson,
        'declaredTags': <Object?>['vegan', 3, null, '', '  ', 'kosher'],
      });

      // Assert
      expect(dish?.declaredTags, <String>['vegan', 'kosher']);
    });

    test('tags take part in equality', () {
      // Arrange
      const plain = Dish(
        id: 'd',
        name: 'n',
        description: '',
        price: 1,
        options: <DishOption>[],
      );
      const tagged = Dish(
        id: 'd',
        name: 'n',
        description: '',
        price: 1,
        options: <DishOption>[],
        declaredTags: <String>['kosher'],
      );

      // Assert
      expect(tagged, isNot(equals(plain)));
      expect(tagged.hashCode, isNot(equals(plain.hashCode)));
    });
  });
}
