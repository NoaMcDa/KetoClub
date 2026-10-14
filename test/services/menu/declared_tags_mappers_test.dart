// Dish.declaredTags through both platform mappers (Banto, ALG-09, issue
// #351): Wolt's item `dietary_preferences` and 10bis's `kosher` flag.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/tenbis/tenbis_menu_mapper.dart';
import 'package:ketoclub/services/menu/wolt/wolt_menu_mapper.dart';
import 'package:ketoclub/utils/allergens/declarations.dart';

/// The fixed timestamp every menu here is stamped with.
final DateTime _fetchedAt = DateTime.utc(2026);

/// Loads and decodes a fixture from `test/fixtures/` by file name.
Map<String, Object?> _fixture(String fileName) =>
    jsonDecode(File('test/fixtures/$fileName').readAsStringSync())
        as Map<String, Object?>;

/// The one dish of a Wolt payload whose item is [item] merged over a plain
/// one.
Dish _woltDish(Map<String, Object?> item) {
  final result = WoltMenuMapper.toMenu(
    <String, Object?>{
      'categories': <Object?>[
        <String, Object?>{
          'id': 'c',
          'name': 'Mains',
          'item_ids': <Object?>['i1'],
        },
      ],
      'items': <Object?>[
        <String, Object?>{'id': 'i1', 'name': 'Bowl', 'price': 4200, ...item},
      ],
    },
    ref: const VenueRef(source: MenuSource.wolt, platformId: 'v'),
    fetchedAt: _fetchedAt,
  );
  return (result as MenuFetched).menu.allDishes.single;
}

/// The one dish of a 10bis payload whose dish is [dish] merged over a plain
/// one.
Dish _tenBisDish(Map<String, Object?> dish) {
  final result = TenBisMenuMapper.toMenu(
    <String, Object?>{
      'categoriesList': <Object?>[
        <String, Object?>{
          'categoryName': 'Mains',
          'dishList': <Object?>[
            <String, Object?>{
              'dishId': 1,
              'dishName': 'Bowl',
              'price': 42,
              ...dish,
            },
          ],
        },
      ],
    },
    ref: const VenueRef(source: MenuSource.tenbis, platformId: '1'),
    fetchedAt: _fetchedAt,
  );
  return (result as MenuFetched).menu.allDishes.single;
}

void main() {
  group('WoltMenuMapper — dietary_preferences', () {
    test('every item of the real recording declares nothing', () {
      // Arrange
      final result = WoltMenuMapper.toMenu(
        _fixture('wolt_hamosad_menu.json'),
        ref: const VenueRef(source: MenuSource.wolt, platformId: 'hamosad'),
        fetchedAt: _fetchedAt,
      );

      // Act
      final dishes = (result as MenuFetched).menu.allDishes.toList();

      // Assert
      expect(dishes, isNotEmpty);
      expect(dishes.every((dish) => dish.declaredTags.isEmpty), isTrue);
    });

    test('string entries are kept as the platform wrote them', () {
      // Act
      final dish = _woltDish(<String, Object?>{
        'dietary_preferences': <Object?>['VEGAN', 'GLUTEN_FREE'],
      });

      // Assert
      expect(dish.declaredTags, <String>['VEGAN', 'GLUTEN_FREE']);
      expect(dish.toJson()['declaredTags'], <String>['VEGAN', 'GLUTEN_FREE']);
    });

    test('map entries give their id, else their name; the rest drop', () {
      // Act
      final dish = _woltDish(<String, Object?>{
        'dietary_preferences': <Object?>[
          <String, Object?>{'id': 'vegan', 'name': 'Vegan'},
          <String, Object?>{'name': 'Gluten free'},
          <String, Object?>{'id': '  ', 'name': 'Dairy free'},
          'vegan',
          '',
          '  ',
          7,
          null,
          <String, Object?>{'label': 'ignored'},
        ],
      });

      // Assert
      expect(dish.declaredTags, <String>['vegan', 'Gluten free', 'Dairy free']);
    });

    for (final raw in <Object?>[null, 'VEGAN', 3]) {
      test('a dietary_preferences of $raw is no tags, never a failure', () {
        // Act
        final dish = _woltDish(<String, Object?>{'dietary_preferences': raw});

        // Assert
        expect(dish.declaredTags, isEmpty);
        expect(dish.toJson().containsKey('declaredTags'), isFalse);
      });
    }
  });

  group('TenBisMenuMapper — kosher', () {
    test('the synthetic fixture flags exactly one dish kosher', () {
      // Act
      final result = TenBisMenuMapper.toMenu(
        _fixture('tenbis_synthetic_menu.json'),
        ref: const VenueRef(source: MenuSource.tenbis, platformId: '9001'),
        fetchedAt: _fetchedAt,
      );
      final menu = (result as MenuFetched).menu;

      // Assert
      expect(
        <String>[
          for (final dish in menu.allDishes)
            if (dish.declaredTags.isNotEmpty) dish.id,
        ],
        <String>['1003'],
      );
    });

    test('kosher: true is the one tag', () {
      // Act
      final dish = _tenBisDish(<String, Object?>{'kosher': true});

      // Assert
      expect(dish.declaredTags, <String>[kosherDeclaredTag]);
      expect(Declarations.declaresKosher(dish), isTrue);
    });

    for (final raw in <Object?>[false, null, 1, 'true']) {
      test('kosher: $raw is no tag', () {
        // Act
        final dish = _tenBisDish(<String, Object?>{'kosher': raw});

        // Assert
        expect(dish.declaredTags, isEmpty);
        expect(Declarations.declaresKosher(dish), isFalse);
      });
    }
  });
}
