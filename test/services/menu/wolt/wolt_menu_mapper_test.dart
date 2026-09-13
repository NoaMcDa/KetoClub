import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/wolt/wolt_menu_mapper.dart';

/// The ref every mapper test asks for.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'vitrina-lilinblum',
);

/// The fixed timestamp every mapper test stamps a menu with.
final DateTime _fetchedAt = DateTime.utc(2026);

/// Loads and decodes a fixture from `test/fixtures/` by file name.
Map<String, Object?> _loadFixture(String fileName) {
  final text = File('test/fixtures/$fileName').readAsStringSync();
  final decoded = jsonDecode(text);
  return decoded as Map<String, Object?>;
}

/// The real, hand-built Wolt fixture (see `test/fixtures/README.md`).
Map<String, Object?> _validFixture() =>
    _loadFixture('wolt_vitrina_lilinblum_menu.json');

/// Asserts that mapping [json] yields a bare `platformChanged` failure.
void _expectPlatformChanged(Map<String, Object?> json) {
  final result = WoltMenuMapper.toMenu(json, ref: _ref, fetchedAt: _fetchedAt);
  expect(
    result,
    equals(
      const MenuFetchFailed(reason: MenuFetchFailureReason.platformChanged),
    ),
  );
}

void main() {
  group('WoltMenuMapper', () {
    test('toMenu ignores the leading _fixture_note key', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      );

      // Assert
      expect(result, isA<MenuFetched>());
      expect(json.keys.first, equals('_fixture_note'));
    });

    test('toMenu returns a menu whose venueRef equals the requested ref', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      expect(result.menu.venueRef, equals(_ref));
    });

    test('toMenu copies currency verbatim', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      expect(result.menu.currency, equals('ILS'));
    });

    test('toMenu stamps the menu with the given fetchedAt', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      expect(result.menu.fetchedAt, equals(_fetchedAt));
    });

    test('toMenu produces every category in menu order', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      expect(
        result.menu.categories.map((category) => category.id),
        equals(<String>['cat_steaks', 'cat_specials', 'cat_salads']),
      );
    });

    test('toMenu flattens all dishes across categories', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      expect(
        result.menu.allDishes.map((dish) => dish.id).toSet(),
        equals(<String>{
          'dish_entrecote_300',
          'dish_shared_special',
          'dish_zero_price',
          'dish_hebrew_salad',
          'dish_no_description_key',
        }),
      );
    });

    test('toMenu skips an item_id with no matching entry in items[]', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      expect(
        result.menu.allDishes.map((dish) => dish.id),
        isNot(contains('dish_missing_from_items')),
      );
      final steaks = result.menu.categories.first;
      expect(steaks.dishes.map((dish) => dish.id), hasLength(2));
    });

    test('toMenu drops a duplicate dish id from every category after the '
        'first', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final steaks = result.menu.categories[0];
      final specials = result.menu.categories[1];
      expect(
        steaks.dishes.map((dish) => dish.id),
        contains('dish_shared_special'),
      );
      expect(
        specials.dishes.map((dish) => dish.id),
        isNot(contains('dish_shared_special')),
      );
      expect(
        result.menu.allDishes.where((dish) => dish.id == 'dish_shared_special'),
        hasLength(1),
      );
    });

    test('toMenu converts agorot price to major units exactly', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final entrecote = result.menu.allDishes.firstWhere(
        (dish) => dish.id == 'dish_entrecote_300',
      );
      expect(entrecote.price, equals(142.00));
    });

    test('toMenu keeps a zero price as 0.0', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final freeBread = result.menu.allDishes.firstWhere(
        (dish) => dish.id == 'dish_zero_price',
      );
      expect(freeBread.price, equals(0.0));
    });

    test('toMenu defaults a null description to the empty string', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final special = result.menu.allDishes.firstWhere(
        (dish) => dish.id == 'dish_shared_special',
      );
      expect(special.description, equals(''));
    });

    test('toMenu defaults an absent description to the empty string', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final babyGem = result.menu.allDishes.firstWhere(
        (dish) => dish.id == 'dish_no_description_key',
      );
      expect(babyGem.description, equals(''));
    });

    test('toMenu flattens a radio option group into name and values', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final entrecote = result.menu.allDishes.firstWhere(
        (dish) => dish.id == 'dish_entrecote_300',
      );
      expect(
        entrecote.options,
        equals(<DishOption>[
          const DishOption(
            name: 'Choice of Side',
            values: <String>['Potato Purée', 'Green Salad'],
          ),
        ]),
      );
    });

    test('toMenu flattens a checkbox option group into name and values', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final special = result.menu.allDishes.firstWhere(
        (dish) => dish.id == 'dish_shared_special',
      );
      expect(
        special.options,
        equals(<DishOption>[
          const DishOption(
            name: 'Add Extras',
            values: <String>['Extra Halloumi', 'Olives'],
          ),
        ]),
      );
    });

    test('toMenu leaves an empty options list empty', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final freeBread = result.menu.allDishes.firstWhere(
        (dish) => dish.id == 'dish_zero_price',
      );
      expect(freeBread.options, isEmpty);
    });

    test('toMenu skips an option id with no matching entry in options[]', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final hebrewSalad = result.menu.allDishes.firstWhere(
        (dish) => dish.id == 'dish_hebrew_salad',
      );
      expect(hebrewSalad.options, hasLength(1));
      expect(hebrewSalad.options.single.name, equals('Dressing'));
    });

    test('toMenu preserves Hebrew dish and category names', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final salads = result.menu.categories.firstWhere(
        (category) => category.id == 'cat_salads',
      );
      expect(salads.name, equals('סלטים'));
      final hebrewSalad = result.menu.allDishes.firstWhere(
        (dish) => dish.id == 'dish_hebrew_salad',
      );
      expect(hebrewSalad.name, equals('סלט ירקות'));
    });

    test('toMenu treats an empty categories list as a valid empty menu', () {
      // Arrange
      final json = <String, Object?>{
        'currency': 'ILS',
        'categories': <Object?>[],
        'items': <Object?>[],
        'options': <Object?>[],
      };

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      );

      // Assert
      expect(result, isA<MenuFetched>());
      expect((result as MenuFetched).menu.categories, isEmpty);
    });

    test('toMenu tolerates a payload with no options key at all', () {
      // Arrange
      final json = <String, Object?>{
        'currency': 'ILS',
        'categories': <Object?>[
          <String, Object?>{
            'id': 'cat_1',
            'name': 'Mains',
            'item_ids': <Object?>['dish_1'],
          },
        ],
        'items': <Object?>[
          <String, Object?>{
            'id': 'dish_1',
            'name': 'Plain Chicken',
            'price': 3000,
          },
        ],
      };

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      );

      // Assert
      expect(result, isA<MenuFetched>());
      final dish = (result as MenuFetched).menu.allDishes.single;
      expect(dish.id, equals('dish_1'));
      expect(dish.options, isEmpty);
    });

    test('toMenu returns platformChanged when currency is missing', () {
      // Arrange
      final json = <String, Object?>{
        'categories': <Object?>[],
        'items': <Object?>[],
      };

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      );

      // Assert
      expect(
        result,
        equals(
          const MenuFetchFailed(reason: MenuFetchFailureReason.platformChanged),
        ),
      );
    });

    test('toMenu returns platformChanged when categories is not a list', () {
      // Arrange
      final json = <String, Object?>{
        'currency': 'ILS',
        'categories': 'not a list',
        'items': <Object?>[],
      };

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      );

      // Assert
      expect(
        result,
        equals(
          const MenuFetchFailed(reason: MenuFetchFailureReason.platformChanged),
        ),
      );
    });

    test('toMenu returns platformChanged when items is missing', () {
      // Arrange
      final json = <String, Object?>{
        'currency': 'ILS',
        'categories': <Object?>[],
      };

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      );

      // Assert
      expect(
        result,
        equals(
          const MenuFetchFailed(reason: MenuFetchFailureReason.platformChanged),
        ),
      );
    });

    test(
      'toMenu returns platformChanged when an item has a negative price',
      () {
        // Arrange
        final json = <String, Object?>{
          'currency': 'ILS',
          'categories': <Object?>[],
          'items': <Object?>[
            <String, Object?>{'id': 'dish_1', 'name': 'Broken', 'price': -100},
          ],
        };

        // Act
        final result = WoltMenuMapper.toMenu(
          json,
          ref: _ref,
          fetchedAt: _fetchedAt,
        );

        // Assert
        expect(
          result,
          equals(
            const MenuFetchFailed(
              reason: MenuFetchFailureReason.platformChanged,
            ),
          ),
        );
      },
    );

    test('toMenu returns platformChanged when a category is missing an id', () {
      // Arrange
      final json = <String, Object?>{
        'currency': 'ILS',
        'categories': <Object?>[
          <String, Object?>{'name': 'Mains', 'item_ids': <Object?>[]},
        ],
        'items': <Object?>[],
      };

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      );

      // Assert
      expect(
        result,
        equals(
          const MenuFetchFailed(reason: MenuFetchFailureReason.platformChanged),
        ),
      );
    });

    test('toMenu returns platformChanged for the malformed fixture', () {
      // Arrange
      final json = _loadFixture('wolt_malformed_menu.json');

      // Act
      final result = WoltMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      );

      // Assert
      expect(
        result,
        equals(
          const MenuFetchFailed(reason: MenuFetchFailureReason.platformChanged),
        ),
      );
    });

    test('toMenu returns platformChanged when options is not a list', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'currency': 'ILS',
        'categories': <Object?>[],
        'items': <Object?>[],
        'options': 'not a list',
      });
    });

    test(
      'toMenu returns platformChanged when an option group is not a map',
      () {
        // Arrange & Act & Assert
        _expectPlatformChanged(<String, Object?>{
          'currency': 'ILS',
          'categories': <Object?>[],
          'items': <Object?>[],
          'options': <Object?>['not a map'],
        });
      },
    );

    test('toMenu returns platformChanged when an option group has no id', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'currency': 'ILS',
        'categories': <Object?>[],
        'items': <Object?>[],
        'options': <Object?>[
          <String, Object?>{'name': 'Choice', 'values': <Object?>[]},
        ],
      });
    });

    test('toMenu returns platformChanged when an option group has no name', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'currency': 'ILS',
        'categories': <Object?>[],
        'items': <Object?>[],
        'options': <Object?>[
          <String, Object?>{'id': 'opt_1', 'values': <Object?>[]},
        ],
      });
    });

    test("toMenu returns platformChanged when an option group's values is "
        'not a list', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'currency': 'ILS',
        'categories': <Object?>[],
        'items': <Object?>[],
        'options': <Object?>[
          <String, Object?>{
            'id': 'opt_1',
            'name': 'Choice',
            'values': 'not a list',
          },
        ],
      });
    });

    test(
      'toMenu returns platformChanged when an option value is not a map',
      () {
        // Arrange & Act & Assert
        _expectPlatformChanged(<String, Object?>{
          'currency': 'ILS',
          'categories': <Object?>[],
          'items': <Object?>[],
          'options': <Object?>[
            <String, Object?>{
              'id': 'opt_1',
              'name': 'Choice',
              'values': <Object?>['not a map'],
            },
          ],
        });
      },
    );

    test('toMenu returns platformChanged when an option value has no name', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'currency': 'ILS',
        'categories': <Object?>[],
        'items': <Object?>[],
        'options': <Object?>[
          <String, Object?>{
            'id': 'opt_1',
            'name': 'Choice',
            'values': <Object?>[
              <String, Object?>{'id': 'val_1'},
            ],
          },
        ],
      });
    });

    test('toMenu returns platformChanged when an item is not a map', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'currency': 'ILS',
        'categories': <Object?>[],
        'items': <Object?>['not a map'],
      });
    });

    test('toMenu returns platformChanged when an item has no id', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'currency': 'ILS',
        'categories': <Object?>[],
        'items': <Object?>[
          <String, Object?>{'name': 'No Id', 'price': 100},
        ],
      });
    });

    test('toMenu returns platformChanged when an item has no name', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'currency': 'ILS',
        'categories': <Object?>[],
        'items': <Object?>[
          <String, Object?>{'id': 'dish_1', 'price': 100},
        ],
      });
    });

    test(
      'toMenu returns platformChanged when a description is not a string',
      () {
        // Arrange & Act & Assert
        _expectPlatformChanged(<String, Object?>{
          'currency': 'ILS',
          'categories': <Object?>[],
          'items': <Object?>[
            <String, Object?>{
              'id': 'dish_1',
              'name': 'Odd',
              'description': 42,
              'price': 100,
            },
          ],
        });
      },
    );

    test("toMenu returns platformChanged when an item's options is not a "
        'list', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'currency': 'ILS',
        'categories': <Object?>[],
        'items': <Object?>[
          <String, Object?>{
            'id': 'dish_1',
            'name': 'Odd',
            'price': 100,
            'options': 'not a list',
          },
        ],
      });
    });

    test("toMenu returns platformChanged when an item's option id is not a "
        'string', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'currency': 'ILS',
        'categories': <Object?>[],
        'items': <Object?>[
          <String, Object?>{
            'id': 'dish_1',
            'name': 'Odd',
            'price': 100,
            'options': <Object?>[123],
          },
        ],
      });
    });

    test('toMenu returns platformChanged when a category is not a map', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'currency': 'ILS',
        'categories': <Object?>['not a map'],
        'items': <Object?>[],
      });
    });

    test('toMenu returns platformChanged when a category has no name', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'currency': 'ILS',
        'categories': <Object?>[
          <String, Object?>{'id': 'cat_1', 'item_ids': <Object?>[]},
        ],
        'items': <Object?>[],
      });
    });

    test("toMenu returns platformChanged when a category's item_ids is not "
        'a list', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'currency': 'ILS',
        'categories': <Object?>[
          <String, Object?>{
            'id': 'cat_1',
            'name': 'Mains',
            'item_ids': 'not a list',
          },
        ],
        'items': <Object?>[],
      });
    });

    test("toMenu returns platformChanged when a category's item_id is not a "
        'string', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'currency': 'ILS',
        'categories': <Object?>[
          <String, Object?>{
            'id': 'cat_1',
            'name': 'Mains',
            'item_ids': <Object?>[123],
          },
        ],
        'items': <Object?>[],
      });
    });
  });
}
