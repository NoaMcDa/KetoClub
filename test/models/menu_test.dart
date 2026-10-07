import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/menu.dart';

void main() {
  group('DishOption', () {
    test('tryFrom returns a DishOption for a valid map', () {
      // Arrange
      final json = <String, Object?>{
        'name': 'Choice of side',
        'values': ['Potato purée', 'Green salad'],
      };

      // Act
      final result = DishOption.tryFrom(json);

      // Assert
      expect(
        result,
        equals(
          const DishOption(
            name: 'Choice of side',
            values: ['Potato purée', 'Green salad'],
          ),
        ),
      );
    });

    test('tryFrom(x.toJson()) round-trips to an equal DishOption', () {
      // Arrange
      const option = DishOption(name: 'Choice of side', values: ['A', 'B']);

      // Act
      final result = DishOption.tryFrom(option.toJson());

      // Assert
      expect(result, equals(option));
    });

    test('tryFrom returns null when name is missing', () {
      // Arrange
      final json = <String, Object?>{
        'values': <String>['A'],
      };

      // Act
      final result = DishOption.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when name is empty', () {
      // Arrange
      final json = <String, Object?>{
        'name': '',
        'values': <String>['A'],
      };

      // Act
      final result = DishOption.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when name is not a String', () {
      // Arrange
      final json = <String, Object?>{
        'name': 1,
        'values': <String>['A'],
      };

      // Act
      final result = DishOption.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when values is missing', () {
      // Arrange
      final json = <String, Object?>{'name': 'Side'};

      // Act
      final result = DishOption.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when values is not a List', () {
      // Arrange
      final json = <String, Object?>{'name': 'Side', 'values': 'A'};

      // Act
      final result = DishOption.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when a value is not a String', () {
      // Arrange
      final json = <String, Object?>{
        'name': 'Side',
        'values': <Object?>['A', 1],
      };

      // Act
      final result = DishOption.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('== returns false for options differing in values', () {
      // Arrange
      const a = DishOption(name: 'Side', values: ['A']);
      const b = DishOption(name: 'Side', values: ['B']);

      // Act & Assert
      expect(a, isNot(equals(b)));
    });

    test('== returns true for options with equal fields', () {
      // Arrange: built at run time, so == is exercised rather than const
      // canonicalisation.
      final names = <String>['Side', 'Side'];
      final a = DishOption(name: names[0], values: const ['A', 'B']);
      final b = DishOption(name: names[1], values: const ['A', 'B']);

      // Act & Assert
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('Dish', () {
    const validJson = <String, Object?>{
      'id': 'dish_1',
      'name': 'Ribeye',
      'description': '300g',
      'price': 45.5,
      'options': <Object?>[],
    };

    test('tryFrom returns a Dish for a valid map', () {
      // Arrange & Act
      final result = Dish.tryFrom(validJson);

      // Assert
      expect(
        result,
        equals(
          const Dish(
            id: 'dish_1',
            name: 'Ribeye',
            description: '300g',
            price: 45.5,
            options: [],
          ),
        ),
      );
    });

    test('tryFrom(x.toJson()) round-trips to an equal Dish', () {
      // Arrange
      const dish = Dish(
        id: 'dish_1',
        name: 'Ribeye',
        description: '300g',
        price: 45.5,
        options: [
          DishOption(name: 'Side', values: ['A', 'B']),
        ],
      );

      // Act
      final result = Dish.tryFrom(dish.toJson());

      // Assert
      expect(result, equals(dish));
    });

    test('tryFrom defaults description to "" when absent', () {
      // Arrange
      final json = <String, Object?>{
        'id': 'dish_1',
        'name': 'Ribeye',
        'price': 45.5,
        'options': <Object?>[],
      };

      // Act
      final result = Dish.tryFrom(json);

      // Assert
      expect(result?.description, equals(''));
    });

    test('tryFrom decodes a map with no imageUrl key to a null imageUrl', () {
      // Arrange: a Hive entry written before imageUrl existed.
      final json = <String, Object?>{...validJson}..remove('imageUrl');

      // Act
      final result = Dish.tryFrom(json);

      // Assert
      expect(result, isNotNull);
      expect(result?.imageUrl, isNull);
    });

    test('tryFrom decodes a null imageUrl to null', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'imageUrl': null};

      // Act
      final result = Dish.tryFrom(json);

      // Assert
      expect(result?.imageUrl, isNull);
    });

    test('tryFrom decodes a non-String imageUrl to null, not a failure', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'imageUrl': 7};

      // Act
      final result = Dish.tryFrom(json);

      // Assert
      expect(result, isNotNull);
      expect(result?.imageUrl, isNull);
    });

    test('tryFrom decodes an empty imageUrl to null', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'imageUrl': ''};

      // Act
      final result = Dish.tryFrom(json);

      // Assert
      expect(result?.imageUrl, isNull);
    });

    test('tryFrom reads a present imageUrl', () {
      // Arrange
      final json = <String, Object?>{
        ...validJson,
        'imageUrl': 'https://example.invalid/dish.jpg',
      };

      // Act
      final result = Dish.tryFrom(json);

      // Assert
      expect(result?.imageUrl, equals('https://example.invalid/dish.jpg'));
    });

    test('tryFrom(x.toJson()) round-trips a dish with an imageUrl', () {
      // Arrange
      const dish = Dish(
        id: 'dish_1',
        name: 'Ribeye',
        description: '300g',
        price: 45.5,
        options: [],
        imageUrl: 'https://example.invalid/dish.jpg',
      );

      // Act
      final result = Dish.tryFrom(dish.toJson());

      // Assert
      expect(result, equals(dish));
    });

    test('== returns false when imageUrl differs', () {
      // Arrange
      const a = Dish(
        id: '1',
        name: 'Steak',
        description: '',
        price: 1,
        options: [],
        imageUrl: 'https://example.invalid/a.jpg',
      );
      const b = Dish(
        id: '1',
        name: 'Steak',
        description: '',
        price: 1,
        options: [],
      );

      // Act & Assert
      expect(a, isNot(equals(b)));
    });

    test('tryFrom decodes a map with no page key to a null page', () {
      // Arrange: a Hive entry written before page existed.
      final json = <String, Object?>{...validJson}..remove('page');

      // Act
      final result = Dish.tryFrom(json);

      // Assert
      expect(result, isNotNull);
      expect(result?.page, isNull);
    });

    test('tryFrom decodes a null page to null', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'page': null};

      // Act
      final result = Dish.tryFrom(json);

      // Assert
      expect(result, isNotNull);
      expect(result?.page, isNull);
    });

    test('tryFrom decodes a non-int page to null, not a failure', () {
      for (final raw in <Object?>['2', 2.5, true]) {
        // Arrange
        final json = <String, Object?>{...validJson, 'page': raw};

        // Act
        final result = Dish.tryFrom(json);

        // Assert
        expect(result, isNotNull, reason: 'page: $raw');
        expect(result?.page, isNull, reason: 'page: $raw');
      }
    });

    test('tryFrom decodes a page below 1 to null, not a failure', () {
      for (final raw in <int>[0, -3]) {
        // Arrange
        final json = <String, Object?>{...validJson, 'page': raw};

        // Act
        final result = Dish.tryFrom(json);

        // Assert
        expect(result, isNotNull, reason: 'page: $raw');
        expect(result?.page, isNull, reason: 'page: $raw');
      }
    });

    test('tryFrom reads a present page', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'page': 3};

      // Act
      final result = Dish.tryFrom(json);

      // Assert
      expect(result?.page, equals(3));
    });

    test('toJson writes the page', () {
      // Arrange
      const dish = Dish(
        id: 'dish_1',
        name: 'Ribeye',
        description: '',
        price: 0,
        options: [],
        page: 2,
      );

      // Act
      final json = dish.toJson();

      // Assert
      expect(json['page'], equals(2));
    });

    test('tryFrom(x.toJson()) round-trips a dish with a page', () {
      // Arrange
      const dish = Dish(
        id: 'dish_1',
        name: 'Ribeye',
        description: '300g',
        price: 45.5,
        options: [],
        page: 2,
      );

      // Act
      final result = Dish.tryFrom(dish.toJson());

      // Assert
      expect(result, equals(dish));
      expect(result?.page, equals(2));
    });

    test('== returns false when page differs', () {
      // Arrange
      const a = Dish(
        id: '1',
        name: 'Steak',
        description: '',
        price: 1,
        options: [],
        page: 1,
      );
      const b = Dish(
        id: '1',
        name: 'Steak',
        description: '',
        price: 1,
        options: [],
        page: 2,
      );

      // Act & Assert
      expect(a, isNot(equals(b)));
    });

    test('equal dishes with the same page share a hashCode', () {
      // Arrange
      const a = Dish(
        id: '1',
        name: 'Steak',
        description: '',
        price: 1,
        options: [],
        page: 2,
      );
      const b = Dish(
        id: '1',
        name: 'Steak',
        description: '',
        price: 1,
        options: [],
        page: 2,
      );

      // Act & Assert
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('tryFrom returns null when id is empty', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'id': ''};

      // Act
      final result = Dish.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when name is missing', () {
      // Arrange
      final json = <String, Object?>{...validJson}..remove('name');

      // Act
      final result = Dish.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when price is negative', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'price': -1.0};

      // Act
      final result = Dish.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when price is not a number', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'price': '45.5'};

      // Act
      final result = Dish.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when description is not a String', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'description': 7};

      // Act
      final result = Dish.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when options is not a List', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'options': 'none'};

      // Act
      final result = Dish.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when an option is malformed', () {
      // Arrange
      final json = <String, Object?>{
        ...validJson,
        'options': <Object?>[
          <String, Object?>{'name': '', 'values': <String>[]},
        ],
      };

      // Act
      final result = Dish.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom accepts an integer price', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'price': 45};

      // Act
      final result = Dish.tryFrom(json);

      // Assert
      expect(result?.price, equals(45.0));
    });

    test('== returns true for dishes with equal fields', () {
      // Arrange: built at run time, so == is exercised rather than const
      // canonicalisation.
      final names = <String>['Steak', 'Steak'];
      final a = Dish(
        id: '1',
        name: names[0],
        description: '',
        price: 1,
        options: const [],
      );
      final b = Dish(
        id: '1',
        name: names[1],
        description: '',
        price: 1,
        options: const [],
      );

      // Act & Assert
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('MenuCategory', () {
    const dishJson = <String, Object?>{
      'id': 'd1',
      'name': 'Ribeye',
      'description': '',
      'price': 10.0,
      'options': <Object?>[],
    };
    const validJson = <String, Object?>{
      'id': 'cat_1',
      'name': 'Steaks',
      'dishes': [dishJson],
    };

    test('tryFrom returns a MenuCategory for a valid map', () {
      // Arrange & Act
      final result = MenuCategory.tryFrom(validJson);

      // Assert
      expect(result?.id, equals('cat_1'));
      expect(result?.name, equals('Steaks'));
      expect(result?.dishes, hasLength(1));
    });

    test('tryFrom(x.toJson()) round-trips to an equal MenuCategory', () {
      // Arrange
      const category = MenuCategory(
        id: 'cat_1',
        name: 'Steaks',
        dishes: [
          Dish(
            id: 'd1',
            name: 'Ribeye',
            description: '',
            price: 10,
            options: [],
          ),
        ],
      );

      // Act
      final result = MenuCategory.tryFrom(category.toJson());

      // Assert
      expect(result, equals(category));
    });

    test('tryFrom returns null when id is missing', () {
      // Arrange
      final json = <String, Object?>{...validJson}..remove('id');

      // Act
      final result = MenuCategory.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when name is empty', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'name': ''};

      // Act
      final result = MenuCategory.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when dishes is not a List', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'dishes': 'none'};

      // Act
      final result = MenuCategory.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when a dish element is not a Map', () {
      // Arrange
      final json = <String, Object?>{
        ...validJson,
        'dishes': <Object?>['not a map'],
      };

      // Act
      final result = MenuCategory.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when a dish is malformed', () {
      // Arrange
      final json = <String, Object?>{
        ...validJson,
        'dishes': <Object?>[
          <String, Object?>{...dishJson, 'price': -5},
        ],
      };

      // Act
      final result = MenuCategory.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom accepts an empty dish list', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'dishes': <Object?>[]};

      // Act
      final result = MenuCategory.tryFrom(json);

      // Assert
      expect(result?.dishes, isEmpty);
    });
  });

  group('Menu', () {
    const venueRefJson = <String, Object?>{
      'source': 'wolt',
      'platformId': 'v1',
    };
    const dish1 = <String, Object?>{
      'id': 'd1',
      'name': 'Ribeye',
      'description': '',
      'price': 10.0,
      'options': <Object?>[],
    };
    const dish2 = <String, Object?>{
      'id': 'd2',
      'name': 'Salad',
      'description': '',
      'price': 5.0,
      'options': <Object?>[],
    };
    const category1 = <String, Object?>{
      'id': 'c1',
      'name': 'Mains',
      'dishes': [dish1],
    };
    const category2 = <String, Object?>{
      'id': 'c2',
      'name': 'Starters',
      'dishes': [dish2],
    };
    const validJson = <String, Object?>{
      'venueRef': venueRefJson,
      'currency': 'ILS',
      'fetchedAt': '2024-01-01T00:00:00.000Z',
      'categories': [category1, category2],
    };

    test('tryFrom returns a Menu for a valid map', () {
      // Arrange & Act
      final result = Menu.tryFrom(validJson);

      // Assert
      expect(result?.currency, equals('ILS'));
      expect(result?.categories, hasLength(2));
    });

    test('tryFrom(x.toJson()) round-trips to an equal Menu', () {
      // Arrange
      final menu = Menu.tryFrom(validJson)!;

      // Act
      final result = Menu.tryFrom(menu.toJson());

      // Assert
      expect(result, equals(menu));
    });

    test('tryFrom accepts an empty categories list', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'categories': <Object?>[]};

      // Act
      final result = Menu.tryFrom(json);

      // Assert
      expect(result?.categories, isEmpty);
      expect(result?.allDishes, isEmpty);
    });

    test('tryFrom returns null when venueRef is not a Map', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'venueRef': 'nope'};

      // Act
      final result = Menu.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when venueRef is malformed', () {
      // Arrange
      final json = <String, Object?>{
        ...validJson,
        'venueRef': <String, Object?>{'source': 'doordash', 'platformId': 'x'},
      };

      // Act
      final result = Menu.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when currency is empty', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'currency': ''};

      // Act
      final result = Menu.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when fetchedAt is missing', () {
      // Arrange
      final json = <String, Object?>{...validJson}..remove('fetchedAt');

      // Act
      final result = Menu.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when fetchedAt is unparseable', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'fetchedAt': 'not-a-date'};

      // Act
      final result = Menu.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when categories is not a List', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'categories': 'none'};

      // Act
      final result = Menu.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom returns null when a category is malformed', () {
      // Arrange
      final json = <String, Object?>{
        ...validJson,
        'categories': <Object?>[
          <String, Object?>{'id': 'c1', 'name': '', 'dishes': <Object?>[]},
        ],
      };

      // Act
      final result = Menu.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom decodes a Menu with venueName == null when the key is '
        'absent, not a failure — the shape of every cache entry written '
        'before venueName existed', () {
      // Arrange: validJson deliberately carries no 'venueName' key.
      expect(validJson.containsKey('venueName'), isFalse);

      // Act
      final result = Menu.tryFrom(validJson);

      // Assert
      expect(result, isNotNull);
      expect(result?.venueName, isNull);
    });

    test('tryFrom reads a present venueName', () {
      // Arrange
      final json = <String, Object?>{
        ...validJson,
        'venueName': 'Vitrina Lilinblum',
      };

      // Act
      final result = Menu.tryFrom(json);

      // Assert
      expect(result?.venueName, equals('Vitrina Lilinblum'));
    });

    test('tryFrom treats an explicit null venueName the same as absent', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'venueName': null};

      // Act
      final result = Menu.tryFrom(json);

      // Assert
      expect(result?.venueName, isNull);
    });

    test('tryFrom returns null when venueName is present but not a String', () {
      // Arrange
      final json = <String, Object?>{...validJson, 'venueName': 42};

      // Act
      final result = Menu.tryFrom(json);

      // Assert
      expect(result, isNull);
    });

    test('tryFrom(x.toJson()) round-trips a Menu carrying a venueName', () {
      // Arrange
      final menu = Menu.tryFrom(<String, Object?>{
        ...validJson,
        'venueName': 'Vitrina Lilinblum',
      })!;

      // Act
      final result = Menu.tryFrom(menu.toJson());

      // Assert
      expect(result, equals(menu));
      expect(result?.venueName, equals('Vitrina Lilinblum'));
    });

    test('== returns false for menus differing only in venueName', () {
      // Arrange
      final a = Menu.tryFrom(validJson)!;
      final b = Menu.tryFrom(<String, Object?>{
        ...validJson,
        'venueName': 'Named Venue',
      })!;

      // Act & Assert
      expect(a, isNot(equals(b)));
    });

    test('allDishes flattens categories, preserving order', () {
      // Arrange
      final menu = Menu.tryFrom(validJson)!;

      // Act
      final result = menu.allDishes.map((dish) => dish.id).toList();

      // Assert
      expect(result, equals(['d1', 'd2']));
    });

    test('categoryNameOf returns the owning category name', () {
      // Arrange
      final menu = Menu.tryFrom(validJson)!;

      // Act
      final result = menu.categoryNameOf('d2');

      // Assert
      expect(result, equals('Starters'));
    });

    test('categoryNameOf returns null when the dish is not in the menu', () {
      // Arrange
      final menu = Menu.tryFrom(validJson)!;

      // Act
      final result = menu.categoryNameOf('missing');

      // Assert
      expect(result, isNull);
    });

    test('== returns true for menus with equal fields', () {
      // Arrange
      final a = Menu.tryFrom(validJson)!;
      final b = Menu.tryFrom(validJson)!;

      // Act & Assert
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('== returns false for menus differing in categories', () {
      // Arrange
      final a = Menu.tryFrom(validJson)!;
      final b = Menu.tryFrom(<String, Object?>{
        ...validJson,
        'categories': [category1],
      })!;

      // Act & Assert
      expect(a, isNot(equals(b)));
    });
  });
}
