import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/tenbis/tenbis_menu_mapper.dart';

/// The ref every mapper test asks for.
const VenueRef _ref = VenueRef(source: MenuSource.tenbis, platformId: '9001');

/// The fixed timestamp every mapper test stamps a menu with.
final DateTime _fetchedAt = DateTime.utc(2026);

/// Loads and decodes a fixture from `test/fixtures/` by file name.
Map<String, Object?> _loadFixture(String fileName) {
  final text = File('test/fixtures/$fileName').readAsStringSync();
  final decoded = jsonDecode(text);
  return decoded as Map<String, Object?>;
}

/// The synthetic, hand-built 10bis fixture (see `test/fixtures/README.md`).
Map<String, Object?> _validFixture() =>
    _loadFixture('tenbis_synthetic_menu.json');

/// Asserts that mapping [json] yields a bare `platformChanged` failure.
void _expectPlatformChanged(Map<String, Object?> json) {
  final result = TenBisMenuMapper.toMenu(
    json,
    ref: _ref,
    fetchedAt: _fetchedAt,
  );
  expect(
    result,
    equals(
      const MenuFetchFailed(reason: MenuFetchFailureReason.platformChanged),
    ),
  );
}

void main() {
  group('TenBisMenuMapper', () {
    test('toMenu ignores the leading _synthetic key', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      );

      // Assert
      expect(result, isA<MenuFetched>());
      expect(json.keys.first, equals('_synthetic'));
    });

    test('toMenu returns a menu whose venueRef equals the requested ref', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      expect(result.menu.venueRef, equals(_ref));
    });

    test('toMenu stamps the menu with the given fetchedAt', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      expect(result.menu.fetchedAt, equals(_fetchedAt));
    });

    test('toMenu defaults currency to ILS when the payload names none', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      expect(result.menu.currency, equals('ILS'));
    });

    test('toMenu reads an explicit top-level currency when present', () {
      // Arrange
      final json = <String, Object?>{..._validFixture(), 'currency': 'USD'};

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      expect(result.menu.currency, equals('USD'));
    });

    test('toMenu reads venueName from a top-level restaurantName', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      expect(result.menu.venueName, equals('Vitrina Tel Aviv'));
    });

    test('toMenu produces every category in menu order', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      expect(
        result.menu.categories.map((category) => category.name),
        equals(<String>['Steaks', "Chef's Specials", 'סלטים', 'Coming Soon']),
      );
    });

    test('toMenu derives a stable slugified id from categoryName', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      expect(result.menu.categories.first.id, equals('cat_steaks'));
    });

    test('toMenu derives the same category id across two calls for the same '
        'name', () {
      // Arrange
      final json = _validFixture();

      // Act
      final first = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;
      final second = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      expect(
        first.menu.categories.first.id,
        equals(second.menu.categories.first.id),
      );
    });

    test('toMenu falls back to a hash-derived slug when categoryName leaves '
        'nothing after stripping', () {
      // Arrange
      final json = <String, Object?>{
        'categoriesList': <Object?>[
          <String, Object?>{'categoryName': '!!!', 'dishList': <Object?>[]},
        ],
      };

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final id = result.menu.categories.single.id;
      expect(id, startsWith('cat_'));
      expect(id, isNot(equals('cat_')));
    });

    test('toMenu leaves venueName null when restaurantName is absent', () {
      // Arrange
      final json = <String, Object?>{'categoriesList': <Object?>[]};

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      expect(result.menu.venueName, isNull);
    });

    test('toMenu treats an empty dishList as a valid, empty category', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final comingSoon = result.menu.categories.firstWhere(
        (category) => category.name == 'Coming Soon',
      );
      expect(comingSoon.dishes, isEmpty);
    });

    test('toMenu accepts a numeric dishId, converted to a String', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      expect(result.menu.allDishes.map((dish) => dish.id), contains('1001'));
    });

    test('toMenu reads a decimal price with no unit conversion', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final entrecote = result.menu.allDishes.firstWhere(
        (dish) => dish.id == '1001',
      );
      expect(entrecote.price, equals(142.0));
    });

    test('toMenu keeps a zero price as 0.0', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final bread = result.menu.allDishes.firstWhere(
        (dish) => dish.id == '1003',
      );
      expect(bread.price, equals(0.0));
    });

    test('toMenu pins the entrecôte image URL from the fixture', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final entrecote = result.menu.allDishes.firstWhere(
        (dish) => dish.id == '1001',
      );
      expect(
        entrecote.imageUrl,
        equals('https://example.invalid/entrecote.jpg'),
      );
    });

    test('toMenu defaults an absent dishImageUrl to null', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final bread = result.menu.allDishes.firstWhere(
        (dish) => dish.id == '1003',
      );
      expect(bread.imageUrl, isNull);
    });

    test('toMenu defaults a missing dishDescription to the empty string', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final babyGem = result.menu.allDishes.firstWhere(
        (dish) => dish.id == '1005',
      );
      expect(babyGem.description, equals(''));
    });

    test('toMenu flattens a dishOptionsList entry into name and values', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final entrecote = result.menu.allDishes.firstWhere(
        (dish) => dish.id == '1001',
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

    test('toMenu leaves a dish with no dishOptionsList empty', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final bread = result.menu.allDishes.firstWhere(
        (dish) => dish.id == '1003',
      );
      expect(bread.options, isEmpty);
    });

    test('toMenu drops a duplicate dish id from every category after the '
        'first', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final steaks = result.menu.categories[0];
      final specials = result.menu.categories[1];
      expect(steaks.dishes.map((dish) => dish.id), contains('1002-shared'));
      expect(
        specials.dishes.map((dish) => dish.id),
        isNot(contains('1002-shared')),
      );
      expect(
        result.menu.allDishes.where((dish) => dish.id == '1002-shared'),
        hasLength(1),
      );
      // The dedupe drops only the repeated id; the specials category's
      // own "Bread Basket" dish is unaffected.
      expect(specials.dishes.map((dish) => dish.id), contains('1003'));
    });

    test('toMenu preserves Hebrew category and dish names', () {
      // Arrange
      final json = _validFixture();

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      ) as MenuFetched;

      // Assert
      final salads = result.menu.categories.firstWhere(
        (category) => category.name == 'סלטים',
      );
      expect(salads.name, equals('סלטים'));
      final hebrewSalad = result.menu.allDishes.firstWhere(
        (dish) => dish.id == '1004',
      );
      expect(hebrewSalad.name, equals('סלט ירקות'));
    });

    test('toMenu treats an empty categoriesList as a valid empty menu', () {
      // Arrange
      final json = <String, Object?>{'categoriesList': <Object?>[]};

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      );

      // Assert
      expect(result, isA<MenuFetched>());
      expect((result as MenuFetched).menu.categories, isEmpty);
    });

    test('toMenu returns platformChanged for the malformed fixture', () {
      // Arrange
      final json = _loadFixture('tenbis_malformed_menu.json');

      // Act
      final result = TenBisMenuMapper.toMenu(
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

    test('toMenu returns platformChanged when categoriesList is missing', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{});
    });

    test(
      'toMenu returns platformChanged when categoriesList is not a list',
      () {
        // Arrange & Act & Assert
        _expectPlatformChanged(<String, Object?>{
          'categoriesList': 'not a list',
        });
      },
    );

    test('toMenu returns platformChanged when a category is not a map', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'categoriesList': <Object?>['not a map'],
      });
    });

    test('toMenu returns platformChanged when a category has no name', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'categoriesList': <Object?>[
          <String, Object?>{'dishList': <Object?>[]},
        ],
      });
    });

    test('toMenu returns platformChanged when a category name is empty', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'categoriesList': <Object?>[
          <String, Object?>{'categoryName': '', 'dishList': <Object?>[]},
        ],
      });
    });

    test("toMenu returns platformChanged when a category's dishList is not a "
        'list', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'categoriesList': <Object?>[
          <String, Object?>{'categoryName': 'Mains', 'dishList': 'not a list'},
        ],
      });
    });

    test('toMenu returns platformChanged when a dish is not a map', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'categoriesList': <Object?>[
          <String, Object?>{
            'categoryName': 'Mains',
            'dishList': <Object?>['not a map'],
          },
        ],
      });
    });

    test('toMenu returns platformChanged when a dish has no dishId', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'categoriesList': <Object?>[
          <String, Object?>{
            'categoryName': 'Mains',
            'dishList': <Object?>[
              <String, Object?>{'dishName': 'No Id', 'price': 10},
            ],
          },
        ],
      });
    });

    test('toMenu returns platformChanged when a dishId is empty', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'categoriesList': <Object?>[
          <String, Object?>{
            'categoryName': 'Mains',
            'dishList': <Object?>[
              <String, Object?>{
                'dishId': '',
                'dishName': 'Empty Id',
                'price': 10,
              },
            ],
          },
        ],
      });
    });

    test('toMenu returns platformChanged when a dish has no dishName', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'categoriesList': <Object?>[
          <String, Object?>{
            'categoryName': 'Mains',
            'dishList': <Object?>[
              <String, Object?>{'dishId': '1', 'price': 10},
            ],
          },
        ],
      });
    });

    test('toMenu returns platformChanged when a dishDescription is not a '
        'string', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'categoriesList': <Object?>[
          <String, Object?>{
            'categoryName': 'Mains',
            'dishList': <Object?>[
              <String, Object?>{
                'dishId': '1',
                'dishName': 'Odd',
                'dishDescription': 42,
                'price': 10,
              },
            ],
          },
        ],
      });
    });

    test('toMenu returns platformChanged when a dish has a negative price', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'categoriesList': <Object?>[
          <String, Object?>{
            'categoryName': 'Mains',
            'dishList': <Object?>[
              <String, Object?>{
                'dishId': '1',
                'dishName': 'Broken',
                'price': -10,
              },
            ],
          },
        ],
      });
    });

    test('toMenu returns platformChanged when a dish has no price', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'categoriesList': <Object?>[
          <String, Object?>{
            'categoryName': 'Mains',
            'dishList': <Object?>[
              <String, Object?>{'dishId': '1', 'dishName': 'No Price'},
            ],
          },
        ],
      });
    });

    test("toMenu returns platformChanged when a dish's dishOptionsList is not "
        'a list', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'categoriesList': <Object?>[
          <String, Object?>{
            'categoryName': 'Mains',
            'dishList': <Object?>[
              <String, Object?>{
                'dishId': '1',
                'dishName': 'Odd',
                'price': 10,
                'dishOptionsList': 'not a list',
              },
            ],
          },
        ],
      });
    });

    test(
      'toMenu returns platformChanged when an option group is not a map',
      () {
        // Arrange & Act & Assert
        _expectPlatformChanged(<String, Object?>{
          'categoriesList': <Object?>[
            <String, Object?>{
              'categoryName': 'Mains',
              'dishList': <Object?>[
                <String, Object?>{
                  'dishId': '1',
                  'dishName': 'Odd',
                  'price': 10,
                  'dishOptionsList': <Object?>['not a map'],
                },
              ],
            },
          ],
        });
      },
    );

    test('toMenu returns platformChanged when an option group has no name', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'categoriesList': <Object?>[
          <String, Object?>{
            'categoryName': 'Mains',
            'dishList': <Object?>[
              <String, Object?>{
                'dishId': '1',
                'dishName': 'Odd',
                'price': 10,
                'dishOptionsList': <Object?>[
                  <String, Object?>{'values': <Object?>[]},
                ],
              },
            ],
          },
        ],
      });
    });

    test("toMenu returns platformChanged when an option group's values is not "
        'a list', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'categoriesList': <Object?>[
          <String, Object?>{
            'categoryName': 'Mains',
            'dishList': <Object?>[
              <String, Object?>{
                'dishId': '1',
                'dishName': 'Odd',
                'price': 10,
                'dishOptionsList': <Object?>[
                  <String, Object?>{'name': 'Choice', 'values': 'not a list'},
                ],
              },
            ],
          },
        ],
      });
    });

    test(
      'toMenu returns platformChanged when an option value is not a map',
      () {
        // Arrange & Act & Assert
        _expectPlatformChanged(<String, Object?>{
          'categoriesList': <Object?>[
            <String, Object?>{
              'categoryName': 'Mains',
              'dishList': <Object?>[
                <String, Object?>{
                  'dishId': '1',
                  'dishName': 'Odd',
                  'price': 10,
                  'dishOptionsList': <Object?>[
                    <String, Object?>{
                      'name': 'Choice',
                      'values': <Object?>['not a map'],
                    },
                  ],
                },
              ],
            },
          ],
        });
      },
    );

    test('toMenu returns platformChanged when an option value has no name', () {
      // Arrange & Act & Assert
      _expectPlatformChanged(<String, Object?>{
        'categoriesList': <Object?>[
          <String, Object?>{
            'categoryName': 'Mains',
            'dishList': <Object?>[
              <String, Object?>{
                'dishId': '1',
                'dishName': 'Odd',
                'price': 10,
                'dishOptionsList': <Object?>[
                  <String, Object?>{
                    'name': 'Choice',
                    'values': <Object?>[
                      <String, Object?>{'unknown': 'x'},
                    ],
                  },
                ],
              },
            ],
          },
        ],
      });
    });

    test('toMenu tolerates a dish with no dishOptionsList key at all', () {
      // Arrange
      final json = <String, Object?>{
        'categoriesList': <Object?>[
          <String, Object?>{
            'categoryName': 'Mains',
            'dishList': <Object?>[
              <String, Object?>{
                'dishId': '1',
                'dishName': 'Plain Chicken',
                'price': 30,
              },
            ],
          },
        ],
      };

      // Act
      final result = TenBisMenuMapper.toMenu(
        json,
        ref: _ref,
        fetchedAt: _fetchedAt,
      );

      // Assert
      expect(result, isA<MenuFetched>());
      final dish = (result as MenuFetched).menu.allDishes.single;
      expect(dish.id, equals('1'));
      expect(dish.options, isEmpty);
    });
  });
}
