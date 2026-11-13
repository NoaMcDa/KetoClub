import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/tenbis/tenbis_menu_mapper.dart';

/// The ref every mapper test asks for.
const VenueRef _ref = VenueRef(source: MenuSource.tenbis, platformId: '19156');

/// The fixed timestamp every mapper test stamps a menu with.
final DateTime _fetchedAt = DateTime.utc(2026);

/// The recorded, trimmed 10bis payload (see `test/fixtures/README.md`).
Map<String, Object?> _recording() =>
    jsonDecode(File('test/fixtures/tenbis_19156_menu.json').readAsStringSync())
        as Map<String, Object?>;

/// A dish in the live shape, with [extra] merged over it.
Map<String, Object?> _dish(
  Object? id, [
  Map<String, Object?> extra = const <String, Object?>{},
]) => <String, Object?>{
  'dishId': id,
  'dishName': 'Dish $id',
  'dishDescription': 'Description of $id',
  'dishPrice': 42,
  'dishImageUrl': '',
  'choices': <Object?>[],
  ...extra,
};

/// A category in the live shape holding [dishes], with [extra] merged
/// over it.
Map<String, Object?> _category(
  List<Object?> dishes, [
  Map<String, Object?> extra = const <String, Object?>{},
]) => <String, Object?>{
  'categoryID': 1,
  'categoryName': 'Mains',
  'dishList': dishes,
  ...extra,
};

/// The live envelope around [categories].
Map<String, Object?> _envelope(Object? categories) => <String, Object?>{
  'Errors': null,
  'Success': true,
  'Data': <String, Object?>{'resId': 19156, 'categoriesList': categories},
  'ShoppingCartGuid': '00000000-0000-0000-0000-000000000000',
};

MenuFetchResult _map(Map<String, Object?> json) =>
    TenBisMenuMapper.toMenu(json, ref: _ref, fetchedAt: _fetchedAt);

Menu _mapped(Map<String, Object?> json) => (_map(json) as MenuFetched).menu;

/// Asserts that mapping [json] yields a bare [reason] failure.
void _expectFailure(Map<String, Object?> json, MenuFetchFailureReason reason) {
  expect(_map(json), equals(MenuFetchFailed(reason: reason)));
}

void main() {
  group('TenBisMenuMapper on the recorded payload', () {
    test('maps every category and dish of the recording', () {
      // Arrange
      final json = _recording();

      // Act
      final menu = _mapped(json);

      // Assert
      expect(menu.venueRef, equals(_ref));
      expect(menu.fetchedAt, equals(_fetchedAt));
      expect(menu.currency, equals('ILS'));
      expect(menu.venueName, isNull);
      expect(menu.categories, hasLength(19));
      expect(menu.allDishes, hasLength(38));
    });

    test('pins the first dish: id, Hebrew name, price, photo, choices', () {
      // Arrange
      final json = _recording();

      // Act
      final first = _mapped(json).categories.first;
      final dish = first.dishes.first;

      // Assert
      expect(first.id, equals('cat_987906'));
      expect(first.name, equals('כריכים '));
      expect(dish.id, equals('22610556'));
      expect(dish.name, equals('פיקולי גאודה'));
      expect(
        dish.description,
        equals('לחמנית חלה, חסה, עגבניה, גבינת גאודה וחמאה.'),
      );
      expect(dish.price, equals(29.0));
      expect(dish.imageUrl, startsWith('https://'));
      expect(
        dish.options.map((option) => option.name),
        equals(<String>[
          'לחם ללא גלוטן - כריכים',
          'שתייה לבחירה',
          'קינוח לבחירה',
          'תוספת סלט?',
        ]),
      );
      expect(dish.options.first.values, equals(<String>['לחמנייה ללא גלוטן']));
      expect(dish.options[1].values, hasLength(6));
    });

    test('reads an empty dishImageUrl as no photo', () {
      // Arrange
      final json = _recording();

      // Act
      final dish = _mapped(json).allDishes
          .firstWhere((dish) => dish.id == '22610575');

      // Assert
      expect(dish.imageUrl, isNull);
    });

    test('reads an empty choices list as no options', () {
      // Arrange
      final json = _recording();

      // Act
      final dish = _mapped(json).allDishes
          .firstWhere((dish) => dish.id == '22610744');

      // Assert
      expect(dish.name, equals('פיצה'));
      expect(dish.options, isEmpty);
    });
  });

  group('TenBisMenuMapper not found', () {
    test('maps Success false with Errors to notFound', () {
      // Arrange: 10bis's live answer to a malformed id.
      final json = <String, Object?>{
        'Errors': <Object?>[
          <String, Object?>{
            'ErrorCode': 'InvalidParameters',
            'ErrorDesc': 'restaurantId',
          },
        ],
        'Success': false,
        'Data': null,
      };

      // Act & Assert
      _expectFailure(json, MenuFetchFailureReason.notFound);
    });

    test('maps a null categoriesList to notFound', () {
      // Arrange: 10bis's live answer to an id no restaurant has.
      final json = _envelope(null);

      // Act & Assert
      _expectFailure(json, MenuFetchFailureReason.notFound);
      expect(TenBisMenuMapper.isNotFound(json), isTrue);
    });

    test('does not call a well-formed menu not found', () {
      expect(TenBisMenuMapper.isNotFound(_recording()), isFalse);
    });
  });

  group('TenBisMenuMapper rules', () {
    test('treats an empty categoriesList as a valid empty menu', () {
      expect(_mapped(_envelope(<Object?>[])).categories, isEmpty);
    });

    test('treats an empty dishList as a valid empty category', () {
      expect(
        _mapped(_envelope(<Object?>[_category(<Object?>[])]))
            .categories
            .single
            .dishes,
        isEmpty,
      );
    });

    test('falls back to a name slug when categoryID is absent', () {
      // Arrange
      final json = _envelope(<Object?>[
        <String, Object?>{
          'categoryName': 'Hot Drinks! שתייה',
          'dishList': <Object?>[],
        },
      ]);

      // Act & Assert
      expect(
        _mapped(json).categories.single.id,
        equals('cat_hot-drinks-שתייה'),
      );
    });

    test('falls back to a hash slug when the name leaves nothing', () {
      // Arrange
      final json = _envelope(<Object?>[
        <String, Object?>{'categoryName': '!!!', 'dishList': <Object?>[]},
      ]);

      // Act
      final id = _mapped(json).categories.single.id;

      // Assert
      expect(id, startsWith('cat_'));
      expect(id.length, greaterThan('cat_'.length));
    });

    test('accepts a string dishId and a decimal price as-is', () {
      // Arrange
      final json = _envelope(<Object?>[
        _category(<Object?>[
          _dish('a-1', <String, Object?>{'dishPrice': 12.5}),
        ]),
      ]);

      // Act
      final dish = _mapped(json).allDishes.single;

      // Assert
      expect(dish.id, equals('a-1'));
      expect(dish.price, equals(12.5));
    });

    test('defaults a missing dishDescription and choices', () {
      // Arrange
      final dish = _dish(1)
        ..remove('dishDescription')
        ..remove('choices');

      // Act
      final mapped = _mapped(
        _envelope(<Object?>[
          _category(<Object?>[dish]),
        ]),
      ).allDishes.single;

      // Assert
      expect(mapped.description, isEmpty);
      expect(mapped.options, isEmpty);
    });

    test('drops a duplicate dish id from every category after the first', () {
      // Arrange
      final json = _envelope(<Object?>[
        _category(<Object?>[_dish(7)]),
        _category(
          <Object?>[_dish(7), _dish(8)],
          <String, Object?>{'categoryID': 2},
        ),
      ]);

      // Act
      final menu = _mapped(json);

      // Assert
      expect(menu.categories[0].dishes.map((dish) => dish.id), ['7']);
      expect(menu.categories[1].dishes.map((dish) => dish.id), ['8']);
    });
  });

  group('TenBisMenuMapper platformChanged', () {
    final cases = <String, Map<String, Object?>>{
      'the pre-#468 shape with no Data': <String, Object?>{
        'categoriesList': <Object?>[],
      },
      'Data that is not an object': <String, Object?>{'Data': 'x'},
      'Data with no categoriesList': <String, Object?>{
        'Data': <String, Object?>{'resId': 1},
      },
      'a categoriesList that is not a list': _envelope('x'),
      'a category that is not a map': _envelope(<Object?>['x']),
      'a category with an empty name': _envelope(<Object?>[
        _category(<Object?>[], <String, Object?>{'categoryName': ''}),
      ]),
      'a dishList that is not a list': _envelope(<Object?>[
        _category(<Object?>[], <String, Object?>{'dishList': 'x'}),
      ]),
      'a dish that is not a map': _envelope(<Object?>[
        _category(<Object?>['x']),
      ]),
      'an empty dishId': _envelope(<Object?>[
        _category(<Object?>[_dish('')]),
      ]),
      'a dish with no dishName': _envelope(<Object?>[
        _category(<Object?>[
          _dish(1, <String, Object?>{'dishName': null}),
        ]),
      ]),
      'a description that is not a string': _envelope(<Object?>[
        _category(<Object?>[
          _dish(1, <String, Object?>{'dishDescription': 3}),
        ]),
      ]),
      'a negative dishPrice': _envelope(<Object?>[
        _category(<Object?>[
          _dish(1, <String, Object?>{'dishPrice': -1}),
        ]),
      ]),
      'the old price key in place of dishPrice': _envelope(<Object?>[
        _category(<Object?>[
          _dish(1, <String, Object?>{'dishPrice': null, 'price': 5}),
        ]),
      ]),
      'choices that are not a list': _envelope(<Object?>[
        _category(<Object?>[
          _dish(1, <String, Object?>{'choices': 'x'}),
        ]),
      ]),
      'a choice with no textBeforeChoosing': _envelope(<Object?>[
        _category(<Object?>[
          _dish(1, <String, Object?>{
            'choices': <Object?>[
              <String, Object?>{'subs': <Object?>[]},
            ],
          }),
        ]),
      ]),
      'a choice whose subs is not a list': _envelope(<Object?>[
        _category(<Object?>[
          _dish(1, <String, Object?>{
            'choices': <Object?>[
              <String, Object?>{'textBeforeChoosing': 'Side', 'subs': 'x'},
            ],
          }),
        ]),
      ]),
      'a sub with no name': _envelope(<Object?>[
        _category(<Object?>[
          _dish(1, <String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'textBeforeChoosing': 'Side',
                'subs': <Object?>[
                  <String, Object?>{'price': 0},
                ],
              },
            ],
          }),
        ]),
      ]),
    };
    for (final MapEntry(key: name, value: json) in cases.entries) {
      test('returns platformChanged for $name', () {
        _expectFailure(json, MenuFetchFailureReason.platformChanged);
      });
    }

    test('reads the malformed fixture as platformChanged', () {
      // Arrange
      final json = jsonDecode(
        File('test/fixtures/tenbis_malformed_menu.json').readAsStringSync(),
      ) as Map<String, Object?>;

      // Act & Assert
      _expectFailure(json, MenuFetchFailureReason.platformChanged);
    });
  });
}
