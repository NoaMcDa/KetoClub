import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/wolt/wolt_menu_mapper.dart';
import 'package:ketoclub/utils/dish_kind.dart';

Dish _dish(String name, {double price = 40}) => Dish(
  id: name,
  name: name,
  description: 'served with a glass of wine and a cola',
  price: price,
  options: const <DishOption>[],
);

void main() {
  group('categoryKindOf', () {
    test('reads the headings of a real Wolt menu', () {
      // Arrange: the headings of wolt_hamosad_menu.json, as recorded.
      final expected = <String, DishKind>{
        '\u202Bלקוחות יקרים': DishKind.notice,
        'ספיישל סמאשבורגר 🌟': DishKind.food,
        '\u202Bהדילים של המוסד  🍔 +  🍟 + 🥤': DishKind.food,
        '\u202Bהמבורגר שף 🍔': DishKind.food,
        'ארוחות של המוסד 🍔 + 🍟': DishKind.food,
        'סנדוויצ׳ים': DishKind.food,
        'נשנושים': DishKind.food,
        'רטבים': DishKind.extra,
        'בירות': DishKind.drink,
        'שתייה': DishKind.drink,
      };

      // Act / Assert
      for (final entry in expected.entries) {
        expect(
          categoryKindOf(entry.key),
          entry.value,
          reason: 'heading "${entry.key}"',
        );
      }
    });

    test('reads the headings of the 10bis fixture and common English '
        'ones', () {
      final expected = <String, DishKind>{
        'Steaks': DishKind.food,
        "Chef's Specials": DishKind.food,
        'סלטים': DishKind.food,
        'Coming Soon': DishKind.notice,
        'Drinks': DishKind.drink,
        'Hot Drinks': DishKind.drink,
        'Beers & Wines': DishKind.drink,
        'Cocktails': DishKind.drink,
        'Sauces': DishKind.extra,
        'Add-ons': DishKind.extra,
        'Cutlery': DishKind.extra,
        'Dear customers': DishKind.notice,
        'Mains': DishKind.food,
        'Sides': DishKind.food,
        'Desserts': DishKind.food,
        '': DishKind.food,
      };
      for (final entry in expected.entries) {
        expect(
          categoryKindOf(entry.key),
          entry.value,
          reason: 'heading "${entry.key}"',
        );
      }
    });

    test('sides are food, even beside sauces: תוספות, "תוספות ורטבים" and '
        '"Sauces & Sides" all count', () {
      expect(categoryKindOf('תוספות'), DishKind.food);
      expect(categoryKindOf('תוספות ורטבים'), DishKind.food);
      expect(categoryKindOf('Sauces & Sides'), DishKind.food);
      expect(categoryKindOf('סלטים ורטבים'), DishKind.food);
    });

    test('a mixed food-and-drink heading decides nothing, so each dish is '
        'read by its name', () {
      expect(categoryKindOf('קפה ומאפה'), DishKind.food);
      expect(categoryKindOf('Coffee & Pastries'), DishKind.food);
      expect(categoryKindOf('Beers & Burgers'), DishKind.food);
      expect(
        dishKindOf(category: 'קפה ומאפה', dish: _dish('קרואסון חמאה')),
        DishKind.food,
      );
      expect(
        dishKindOf(category: 'קפה ומאפה', dish: _dish('הפוך גדול')),
        DishKind.drink,
      );
      expect(
        dishKindOf(category: 'Beers & Burgers', dish: _dish('Goldstar')),
        DishKind.food,
        reason: 'a brand name the vocabulary does not know stays food',
      );
    });

    test('a Hebrew heading matches through the unicode boundary, not an '
        r'ASCII \b', () {
      // Dart's \b never matches beside a Hebrew letter; these would all
      // be food under a \b pattern.
      expect(categoryKindOf('שתייה'), DishKind.drink);
      expect(categoryKindOf('משקאות קלים'), DishKind.drink);
      expect(categoryKindOf('שתייה חמה וקרה'), DishKind.drink);
      expect(categoryKindOf('רטבים ומטבלים'), DishKind.extra);
      // Strict on the right: a suffix is a different word.
      expect(categoryKindOf('ברים'), DishKind.food);
    });

    test('a notice word wins over a drink or extras word', () {
      expect(categoryKindOf('לקוחות יקרים - משלוח'), DishKind.notice);
      expect(categoryKindOf('Please note: delivery'), DishKind.notice);
    });
  });

  group('dishKindOf', () {
    test('the heading decides when it can', () {
      expect(
        dishKindOf(category: 'שתייה', dish: _dish('סטייק אנטריקוט')),
        DishKind.drink,
      );
      expect(
        dishKindOf(category: 'רטבים', dish: _dish("צ'ימיצ'ורי")),
        DishKind.extra,
      );
      expect(
        dishKindOf(category: 'Coming Soon', dish: _dish('Ribeye')),
        DishKind.notice,
      );
    });

    test('a drink filed under a food heading is read from its name, never '
        'its description', () {
      final drinks = <String>[
        'Coca-Cola Zero',
        'Espresso',
        'Iced Latte',
        'Fresh orange juice',
        'Sparkling water',
        'Beer',
        'מים מינרלים',
        'קולה',
        'הפוך',
        'תה קר',
        'יין אדום',
        'בירה מהחבית',
      ];
      for (final name in drinks) {
        expect(
          dishKindOf(category: 'Mains', dish: _dish(name)),
          DishKind.drink,
          reason: name,
        );
      }
      // The description names wine and cola; the name says steak.
      expect(
        dishKindOf(category: 'Mains', dish: _dish('Entrecote steak')),
        DishKind.food,
      );
    });

    test('a drink word used as an ingredient keeps the dish food', () {
      final food = <String>[
        'Beer-battered fish',
        'Wine-braised short rib',
        'Coffee-rubbed brisket',
        'Rum glazed pineapple',
        'Chicken in cola sauce',
        'עוף ברוטב יין',
        'דג בבלילת בירה',
        'בשר מעושן בוויסקי',
      ];
      for (final name in food) {
        expect(
          dishKindOf(category: 'Mains', dish: _dish(name)),
          DishKind.food,
          reason: name,
        );
      }
    });

    test('a notice line is a notice only at a price of zero', () {
      expect(
        dishKindOf(
          category: 'Mains',
          dish: _dish('Dear customers, we close at 22:00', price: 0),
        ),
        DishKind.notice,
      );
      expect(
        dishKindOf(
          category: 'Mains',
          dish: _dish('שימו לב: המטבח נסגר ב-22:00', price: 0),
        ),
        DishKind.notice,
      );
      expect(
        dishKindOf(category: 'Mains', dish: _dish('Important burger')),
        DishKind.food,
      );
    });

    test('anything else is food, an empty name included', () {
      expect(dishKindOf(category: 'Mains', dish: _dish('')), DishKind.food);
      expect(
        dishKindOf(category: 'Mains', dish: _dish('Halloumi salad')),
        DishKind.food,
      );
    });
  });

  group('DishKindCounting', () {
    test('only food counts toward the score', () {
      expect(DishKind.food.countsTowardScore, isTrue);
      for (final kind in DishKind.values.where((k) => k != DishKind.food)) {
        expect(kind.countsTowardScore, isFalse, reason: kind.name);
      }
    });
  });

  group('dishKindsOf', () {
    test('kinds every dish of the real Wolt menu by its heading', () {
      // Arrange
      final json = jsonDecode(
        File('test/fixtures/wolt_hamosad_menu.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final menu = (WoltMenuMapper.toMenu(
        json,
        ref: const VenueRef(source: MenuSource.wolt, platformId: 'hamosad'),
        fetchedAt: DateTime.utc(2026),
      ) as MenuFetched).menu;

      // Act
      final kinds = dishKindsOf(menu);

      // Assert: every dish kinded, and each excluded heading's dishes
      // excluded while the burger headings' dishes count.
      expect(kinds, hasLength(menu.allDishes.length));
      final excluded = <String, DishKind>{
        'רטבים': DishKind.extra,
        'בירות': DishKind.drink,
        'שתייה': DishKind.drink,
        'לקוחות יקרים': DishKind.notice,
      };
      for (final category in menu.categories) {
        final heading = category.name.replaceAll('\u202B', '').trim();
        final expected = excluded[heading] ?? DishKind.food;
        for (final dish in category.dishes) {
          expect(kinds[dish.id], expected, reason: '$heading / ${dish.name}');
        }
      }
      expect(kinds.values.where((k) => k == DishKind.food), isNotEmpty);
      expect(kinds.values.where((k) => k == DishKind.drink), isNotEmpty);
    });

    test('a dish id under two headings takes the first', () {
      const cola = Dish(
        id: 'cola',
        name: 'Cola',
        description: '',
        price: 12,
        options: <DishOption>[],
      );
      final menu = Menu(
        venueRef: const VenueRef(source: MenuSource.wolt, platformId: 'x'),
        currency: 'ILS',
        fetchedAt: DateTime.utc(2026),
        categories: const <MenuCategory>[
          MenuCategory(id: 'd', name: 'Drinks', dishes: <Dish>[cola]),
          MenuCategory(id: 'm', name: 'Mains', dishes: <Dish>[cola]),
        ],
      );
      expect(dishKindsOf(menu), {'cola': DishKind.drink});
    });
  });
}
