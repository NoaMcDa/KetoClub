import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/wolt/wolt_menu_mapper.dart';

/// The ref every mapper test asks for.
const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'hamosad');

/// The fixed timestamp every mapper test stamps a menu with.
final DateTime _fetchedAt = DateTime.utc(2026);

/// Loads and decodes a fixture from `test/fixtures/` by file name.
Map<String, Object?> _loadFixture(String fileName) {
  final text = File('test/fixtures/$fileName').readAsStringSync();
  final decoded = jsonDecode(text);
  return decoded as Map<String, Object?>;
}

/// The real recorded consumer-assortment payload (issue #168; see
/// `test/fixtures/README.md`).
Map<String, Object?> _realFixture() => _loadFixture('wolt_hamosad_menu.json');

/// Maps the real fixture, which must succeed.
Menu _realMenu() {
  final result = WoltMenuMapper.toMenu(
    _realFixture(),
    ref: _ref,
    fetchedAt: _fetchedAt,
  );
  return (result as MenuFetched).menu;
}

/// The dish with [id] on [menu].
Dish _dish(Menu menu, String id) =>
    menu.allDishes.firstWhere((dish) => dish.id == id);

/// A synthetic, assortment-shaped payload: the three collections the
/// mapper reads, and nothing else unless a test adds it.
Map<String, Object?> _payload({
  List<Object?> categories = const <Object?>[],
  List<Object?> items = const <Object?>[],
  List<Object?>? options,
}) => <String, Object?>{
  'categories': categories,
  'items': items,
  'options': ?options,
};

/// A synthetic category holding [itemIds].
Map<String, Object?> _category(
  String id,
  List<Object?> itemIds, {
  Object? subcategories,
}) => <String, Object?>{
  'id': id,
  'name': 'Category $id',
  'item_ids': itemIds,
  'subcategories': ?subcategories,
};

/// A synthetic item: a plain dish, with any of [extra] merged over it.
Map<String, Object?> _item(
  String id, [
  Map<String, Object?> extra = const <String, Object?>{},
]) => <String, Object?>{
  'id': id,
  'name': 'Dish $id',
  'description': 'Description of $id',
  'price': 3000,
  'options': <Object?>[],
  'images': <Object?>[],
  ...extra,
};

/// Maps [json], which must succeed, and returns the menu.
Menu _map(Map<String, Object?> json) {
  final result = WoltMenuMapper.toMenu(json, ref: _ref, fetchedAt: _fetchedAt);
  expect(result, isA<MenuFetched>());
  return (result as MenuFetched).menu;
}

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
  group('WoltMenuMapper against the real recording', () {
    test('toMenu succeeds and ignores the leading _fixture_note key', () {
      // Arrange
      final json = _realFixture();

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
      // Act
      final menu = _realMenu();

      // Assert
      expect(menu.venueRef, equals(_ref));
    });

    test('toMenu stamps the menu with the given fetchedAt', () {
      // Act
      final menu = _realMenu();

      // Assert
      expect(menu.fetchedAt, equals(_fetchedAt));
    });

    test('toMenu defaults the currency to ILS: the payload carries none', () {
      // Act
      final menu = _realMenu();

      // Assert
      expect(menu.currency, equals(WoltMenuMapper.defaultCurrency));
      expect(menu.currency, equals('ILS'));
    });

    test('toMenu leaves venueName null: the payload carries none', () {
      // Act
      final menu = _realMenu();

      // Assert
      expect(menu.venueName, isNull);
    });

    test('toMenu produces all twelve categories in menu order', () {
      // Act
      final menu = _realMenu();

      // Assert
      expect(
        menu.categories.map((category) => category.id),
        equals(<String>[
          '3b68fdc73e96b9d84dd8c2d6',
          '44b70bed7f6cbca07b606ef8',
          '805f2778173825e99c1d8581',
          '87e053f00c8c79a2a34824f5',
          '565f5876e7bbc7f42c9d6019',
          '9dd5d3c61e43d307ff0a083b',
          '89f6a573dd33050695effd49',
          'da0d9fe5082a67a511611cfd',
          '6d44bb01b5dfb5e75cf5e75d',
          '7cb0b2040b3a96cc548198ea',
          '7ff66a47178897e7267f7402',
          'd48f602303b4539f5b923a25',
        ]),
      );
      expect(
        menu.categories.map((category) => category.dishes.length),
        equals(<int>[1, 1, 7, 8, 1, 10, 2, 2, 6, 7, 2, 9]),
      );
    });

    test('toMenu places every one of the 56 items exactly once', () {
      // Act
      final menu = _realMenu();

      // Assert
      final ids = menu.allDishes.map((dish) => dish.id).toList();
      expect(ids, hasLength(56));
      expect(ids.toSet(), hasLength(56));
    });

    test('toMenu converts agorot price to major units exactly', () {
      // Act
      final menu = _realMenu();

      // Assert
      expect(_dish(menu, '038aaf7f3004f69283ee38b1').price, equals(77.0));
    });

    test('toMenu keeps a zero price as 0.0', () {
      // Act
      final menu = _realMenu();

      // Assert
      expect(_dish(menu, '6542410f5facbd8147a65286').price, equals(0.0));
    });

    test('toMenu reads the dish photo from images[0].url', () {
      // Act
      final menu = _realMenu();

      // Assert
      expect(
        _dish(menu, '038aaf7f3004f69283ee38b1').imageUrl,
        equals(
          'https://wolt-menu-images-cdn.wolt.com/menu-images/'
          '5bf18ad4e88d79000a325668/'
          'ef934a3e-dc54-11ee-9049-56c1b2c5a095_untitled_09014.jpg',
        ),
      );
    });

    test('toMenu gives an item with an empty images list a null '
        'imageUrl', () {
      // Act
      final menu = _realMenu();

      // Assert
      expect(_dish(menu, '61ecfdac853cef6ba4d5e3f0').imageUrl, isNull);
    });

    test('toMenu preserves Hebrew dish names and descriptions', () {
      // Act
      final menu = _realMenu();

      // Assert
      final dish = _dish(menu, '038aaf7f3004f69283ee38b1');
      expect(dish.name, equals('ארוחת צ׳יקן אמריקה'));
      expect(dish.description, contains('קולסלואו'));
    });

    test('toMenu resolves each item option through option_id into its '
        "group's value names", () {
      // Act
      final menu = _realMenu();

      // Assert
      final dish = _dish(menu, '038aaf7f3004f69283ee38b1');
      expect(dish.options, hasLength(5));
      expect(
        dish.options,
        contains(
          const DishOption(
            name: 'תוספת לבחירה',
            values: <String>["צ'יפס ", 'צ׳יפס פרמז׳ן כמהין'],
          ),
        ),
      );
    });

    test("toMenu labels an option with the item's own name when it differs "
        "from the group's", () {
      // Act
      final menu = _realMenu();

      // Assert
      final dish = _dish(menu, '61ecfdac853cef6ba4d5e3ef');
      final names = dish.options.map((option) => option.name);
      expect(names, contains('תוספות אפשריות - יוגשו בתוך המנה בלבד'));
      expect(names, isNot(contains('תוספות על ההמבורגר')));
    });

    test('toMenu skips an option_id with no matching entry in options[]', () {
      // Act
      final menu = _realMenu();

      // Assert: the recorded item lists five options, one of which points
      // at a group absent from options[].
      expect(_dish(menu, 'b14178df3e86843398570269').options, hasLength(4));
    });
  });

  group('WoltMenuMapper normalisation', () {
    test('toMenu uses a top-level currency when the payload carries one', () {
      // Arrange
      final json = <String, Object?>{..._payload(), 'currency': 'EUR'};

      // Act
      final menu = _map(json);

      // Assert
      expect(menu.currency, equals('EUR'));
    });

    test('toMenu falls back to ILS for an empty or non-string currency', () {
      // Arrange
      final empty = <String, Object?>{..._payload(), 'currency': ''};
      final number = <String, Object?>{..._payload(), 'currency': 42};

      // Act & Assert
      expect(_map(empty).currency, equals('ILS'));
      expect(_map(number).currency, equals('ILS'));
    });

    test('toMenu treats an empty categories list as a valid empty menu', () {
      // Act
      final menu = _map(_payload(options: <Object?>[]));

      // Assert
      expect(menu.categories, isEmpty);
    });

    test('toMenu tolerates a payload with no options key at all', () {
      // Arrange
      final json = _payload(
        categories: <Object?>[
          _category('c1', <Object?>['d1']),
        ],
        items: <Object?>[_item('d1')],
      );

      // Act
      final menu = _map(json);

      // Assert
      expect(menu.allDishes.single.options, isEmpty);
    });

    test('toMenu skips an item_id with no matching entry in items[]', () {
      // Arrange
      final json = _payload(
        categories: <Object?>[
          _category('c1', <Object?>['d1', 'missing']),
        ],
        items: <Object?>[_item('d1')],
      );

      // Act
      final menu = _map(json);

      // Assert
      expect(
        menu.categories.single.dishes.map((dish) => dish.id),
        equals(<String>['d1']),
      );
    });

    test('toMenu drops a duplicate dish id from every category after the '
        'first', () {
      // Arrange
      final json = _payload(
        categories: <Object?>[
          _category('c1', <Object?>['d1', 'd2']),
          _category('c2', <Object?>['d2', 'd3']),
        ],
        items: <Object?>[_item('d1'), _item('d2'), _item('d3')],
      );

      // Act
      final menu = _map(json);

      // Assert
      expect(
        menu.categories[0].dishes.map((dish) => dish.id),
        equals(<String>['d1', 'd2']),
      );
      expect(
        menu.categories[1].dishes.map((dish) => dish.id),
        equals(<String>['d3']),
      );
    });

    test('toMenu defaults a null or absent description to the empty '
        'string', () {
      // Arrange
      final withoutKey = _item('d2')..remove('description');
      final json = _payload(
        categories: <Object?>[
          _category('c1', <Object?>['d1', 'd2']),
        ],
        items: <Object?>[
          _item('d1', <String, Object?>{'description': null}),
          withoutKey,
        ],
      );

      // Act
      final menu = _map(json);

      // Assert
      expect(menu.allDishes.map((dish) => dish.description), everyElement(''));
    });

    test('toMenu treats an absent item options list as no options', () {
      // Arrange
      final json = _payload(
        categories: <Object?>[
          _category('c1', <Object?>['d1']),
        ],
        items: <Object?>[_item('d1')..remove('options')],
      );

      // Act
      final menu = _map(json);

      // Assert
      expect(menu.allDishes.single.options, isEmpty);
    });

    test("toMenu uses the group's own name when the item option has none", () {
      // Arrange
      final json = _payload(
        categories: <Object?>[
          _category('c1', <Object?>['d1']),
        ],
        items: <Object?>[
          _item('d1', <String, Object?>{
            'options': <Object?>[
              <String, Object?>{'id': 'io1', 'option_id': 'g1'},
            ],
          }),
        ],
        options: <Object?>[
          <String, Object?>{
            'id': 'g1',
            'name': 'Choice of Side',
            'type': 'choice',
            'values': <Object?>[
              <String, Object?>{'id': 'v1', 'name': 'Fries', 'price': 0},
              <String, Object?>{'id': 'v2', 'name': 'Green Salad'},
            ],
          },
        ],
      );

      // Act
      final menu = _map(json);

      // Assert
      expect(
        menu.allDishes.single.options,
        equals(<DishOption>[
          const DishOption(
            name: 'Choice of Side',
            values: <String>['Fries', 'Green Salad'],
          ),
        ]),
      );
    });

    test('toMenu keeps a disabled item', () {
      // Arrange
      final json = _payload(
        categories: <Object?>[
          _category('c1', <Object?>['d1']),
        ],
        items: <Object?>[
          _item('d1', <String, Object?>{
            'disabled_info': <String, Object?>{'disable_reason': 'sold_out'},
          }),
        ],
      );

      // Act
      final menu = _map(json);

      // Assert
      expect(menu.allDishes.single.id, equals('d1'));
    });

    test('toMenu never fails on an unusable image and reads the rest of the '
        'dish normally', () {
      // Arrange
      final unusable = <Object?>[
        null,
        'not a list',
        <Object?>['not a map'],
        <Object?>[
          <String, Object?>{'url': 42},
        ],
        <Object?>[
          <String, Object?>{'url': ''},
        ],
        <Object?>[<String, Object?>{}],
      ];
      final items = <Object?>[
        for (final (i, images) in unusable.indexed)
          _item('d$i', <String, Object?>{'images': images}),
      ];
      final json = _payload(
        categories: <Object?>[
          _category('c1', <Object?>[
            for (var i = 0; i < unusable.length; i++) 'd$i',
          ]),
        ],
        items: items,
      );

      // Act
      final menu = _map(json);

      // Assert
      expect(menu.allDishes, hasLength(unusable.length));
      expect(menu.allDishes.map((dish) => dish.imageUrl), everyElement(isNull));
      expect(menu.allDishes.first.name, equals('Dish d0'));
    });

    test('toMenu flattens subcategories into their parent, after its own '
        'items and depth first', () {
      // Arrange
      final json = _payload(
        categories: <Object?>[
          _category(
            'c1',
            <Object?>['d1'],
            subcategories: <Object?>[
              _category(
                's1',
                <Object?>['d2'],
                subcategories: <Object?>[
                  _category('s1a', <Object?>['d3']),
                ],
              ),
              _category('s2', <Object?>['d4']),
            ],
          ),
        ],
        items: <Object?>[_item('d1'), _item('d2'), _item('d3'), _item('d4')],
      );

      // Act
      final menu = _map(json);

      // Assert
      expect(menu.categories, hasLength(1));
      expect(menu.categories.single.name, equals('Category c1'));
      expect(
        menu.categories.single.dishes.map((dish) => dish.id),
        equals(<String>['d1', 'd2', 'd3', 'd4']),
      );
    });

    test('toMenu dedupes a subcategory item already placed earlier', () {
      // Arrange
      final json = _payload(
        categories: <Object?>[
          _category('c1', <Object?>['d1']),
          _category(
            'c2',
            <Object?>['d2'],
            subcategories: <Object?>[
              _category('s1', <Object?>['d1', 'd2']),
            ],
          ),
        ],
        items: <Object?>[_item('d1'), _item('d2')],
      );

      // Act
      final menu = _map(json);

      // Assert
      expect(
        menu.categories[1].dishes.map((dish) => dish.id),
        equals(<String>['d2']),
      );
    });

    test('toMenu skips a malformed subcategory entry rather than failing', () {
      // Arrange
      final json = _payload(
        categories: <Object?>[
          _category(
            'c1',
            <Object?>['d1'],
            subcategories: <Object?>[
              'not a map',
              <String, Object?>{'id': 's1', 'item_ids': 'not a list'},
              <String, Object?>{
                'id': 's2',
                'item_ids': <Object?>[42],
              },
              _category('s3', <Object?>['d2']),
            ],
          ),
          _category('c2', <Object?>[], subcategories: 'not a list'),
        ],
        items: <Object?>[_item('d1'), _item('d2')],
      );

      // Act
      final menu = _map(json);

      // Assert
      expect(
        menu.categories.first.dishes.map((dish) => dish.id),
        equals(<String>['d1', 'd2']),
      );
      expect(menu.categories[1].dishes, isEmpty);
    });
  });

  group('WoltMenuMapper shape failures', () {
    test('toMenu returns platformChanged for the malformed fixture', () {
      _expectPlatformChanged(_loadFixture('wolt_malformed_menu.json'));
    });

    test('toMenu returns platformChanged when categories is not a list', () {
      _expectPlatformChanged(<String, Object?>{
        'categories': 'not a list',
        'items': <Object?>[],
      });
    });

    test('toMenu returns platformChanged when items is missing', () {
      _expectPlatformChanged(<String, Object?>{'categories': <Object?>[]});
    });

    test('toMenu returns platformChanged when options is not a list', () {
      _expectPlatformChanged(<String, Object?>{
        ..._payload(),
        'options': 'not a list',
      });
    });

    test('toMenu returns platformChanged when an option group is not a '
        'map', () {
      _expectPlatformChanged(_payload(options: <Object?>['not a map']));
    });

    test('toMenu returns platformChanged when an option group has no id', () {
      _expectPlatformChanged(
        _payload(
          options: <Object?>[
            <String, Object?>{'name': 'Choice', 'values': <Object?>[]},
          ],
        ),
      );
    });

    test('toMenu returns platformChanged when an option group has no '
        'name', () {
      _expectPlatformChanged(
        _payload(
          options: <Object?>[
            <String, Object?>{'id': 'g1', 'values': <Object?>[]},
          ],
        ),
      );
    });

    test("toMenu returns platformChanged when an option group's values is "
        'not a list', () {
      _expectPlatformChanged(
        _payload(
          options: <Object?>[
            <String, Object?>{
              'id': 'g1',
              'name': 'Choice',
              'values': 'not a list',
            },
          ],
        ),
      );
    });

    test('toMenu returns platformChanged when an option value is not a '
        'map', () {
      _expectPlatformChanged(
        _payload(
          options: <Object?>[
            <String, Object?>{
              'id': 'g1',
              'name': 'Choice',
              'values': <Object?>['not a map'],
            },
          ],
        ),
      );
    });

    test('toMenu returns platformChanged when an option value has no '
        'name', () {
      _expectPlatformChanged(
        _payload(
          options: <Object?>[
            <String, Object?>{
              'id': 'g1',
              'name': 'Choice',
              'values': <Object?>[
                <String, Object?>{'id': 'v1'},
              ],
            },
          ],
        ),
      );
    });

    test('toMenu returns platformChanged when an item is not a map', () {
      _expectPlatformChanged(_payload(items: <Object?>['not a map']));
    });

    test('toMenu returns platformChanged when an item has no id', () {
      _expectPlatformChanged(
        _payload(items: <Object?>[_item('d1')..remove('id')]),
      );
    });

    test('toMenu returns platformChanged when an item has no name', () {
      _expectPlatformChanged(
        _payload(items: <Object?>[_item('d1')..remove('name')]),
      );
    });

    test('toMenu returns platformChanged when an item has a negative '
        'price', () {
      _expectPlatformChanged(
        _payload(
          items: <Object?>[
            _item('d1', <String, Object?>{'price': -100}),
          ],
        ),
      );
    });

    test('toMenu returns platformChanged when a description is not a '
        'string', () {
      _expectPlatformChanged(
        _payload(
          items: <Object?>[
            _item('d1', <String, Object?>{'description': 42}),
          ],
        ),
      );
    });

    test("toMenu returns platformChanged when an item's options is not a "
        'list', () {
      _expectPlatformChanged(
        _payload(
          items: <Object?>[
            _item('d1', <String, Object?>{'options': 'not a list'}),
          ],
        ),
      );
    });

    test("toMenu returns platformChanged when an item's option is a bare id "
        'string, the retired shape', () {
      _expectPlatformChanged(
        _payload(
          items: <Object?>[
            _item('d1', <String, Object?>{
              'options': <Object?>['g1'],
            }),
          ],
        ),
      );
    });

    test("toMenu returns platformChanged when an item's option has no "
        'string option_id', () {
      _expectPlatformChanged(
        _payload(
          items: <Object?>[
            _item('d1', <String, Object?>{
              'options': <Object?>[
                <String, Object?>{'id': 'io1', 'option_id': 123},
              ],
            }),
          ],
        ),
      );
    });

    test('toMenu returns platformChanged when a category is not a map', () {
      _expectPlatformChanged(_payload(categories: <Object?>['not a map']));
    });

    test('toMenu returns platformChanged when a category has no id', () {
      _expectPlatformChanged(
        _payload(
          categories: <Object?>[_category('c1', <Object?>[])..remove('id')],
        ),
      );
    });

    test('toMenu returns platformChanged when a category has no name', () {
      _expectPlatformChanged(
        _payload(
          categories: <Object?>[_category('c1', <Object?>[])..remove('name')],
        ),
      );
    });

    test("toMenu returns platformChanged when a category's item_ids is not "
        'a list', () {
      _expectPlatformChanged(
        _payload(
          categories: <Object?>[
            <String, Object?>{
              'id': 'c1',
              'name': 'Mains',
              'item_ids': 'not a list',
            },
          ],
        ),
      );
    });

    test("toMenu returns platformChanged when a category's item_id is not a "
        'string', () {
      _expectPlatformChanged(
        _payload(
          categories: <Object?>[
            _category('c1', <Object?>[123]),
          ],
        ),
      );
    });
  });
}
