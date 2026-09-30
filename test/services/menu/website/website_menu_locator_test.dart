// HTML here is written as adjacent string literals that concatenate into
// one document; markup needs no whitespace between tags, and adding it
// would change what these tests pin.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/menu/website/json_ld_menu_mapper.dart';
import 'package:ketoclub/services/menu/website/website_menu_locator.dart';

/// A synthetic page from `test/fixtures/website/` (issue #181).
String _fixture(String name) =>
    File('test/fixtures/website/$name').readAsStringSync();

final Uri _home = Uri.parse('https://cafe-noir.example/');

void main() {
  group('WebsiteMenuLocator.locate (issue #181)', () {
    test('step 1: a JSON-LD menu is mapped straight to categories', () {
      // Act
      final location = WebsiteMenuLocator.locate(
        _fixture('jsonld_menu.html'),
        _home,
      );

      // Assert
      expect(location, isA<JsonLdMenuFound>());
      final categories = (location as JsonLdMenuFound).categories;
      expect(categories.map((c) => c.name), ['Starters', 'Mains', 'Pasta']);
      final dishes = [for (final c in categories) ...c.dishes];
      expect(dishes.map((d) => d.name), [
        'Caesar salad',
        'Entrecote steak',
        'Spaghetti carbonara',
      ]);
      expect(dishes.map((d) => d.id), ['j1', 'j2', 'j3']);
      expect(dishes.first.description, 'Romaine, parmesan, croutons');
      expect(dishes.every((d) => d.price == 0), isTrue);
    });

    test('step 2: a same-site /menu link is followed, not the Wolt one', () {
      // Act
      final location = WebsiteMenuLocator.locate(
        _fixture('menu_link.html'),
        _home,
      );

      // Assert
      expect(location, isA<MenuLinkFound>());
      final link = location as MenuLinkFound;
      expect(link.uri, Uri.parse('https://cafe-noir.example/food/menu/'));
      expect(link.isPdf, isFalse);
    });

    test('step 2: a Hebrew תפריט link is found by its text', () {
      final location = WebsiteMenuLocator.locate(
        _fixture('hebrew_menu_link.html'),
        Uri.parse('https://www.cafe-noir.example/'),
      );

      expect(
        (location as MenuLinkFound).uri,
        Uri.parse('https://www.cafe-noir.example/page-3'),
      );
    });

    test('step 2: a menu PDF on a file host beats a wine-list PDF', () {
      final location = WebsiteMenuLocator.locate(
        _fixture('pdf_link.html'),
        _home,
      );

      final link = location as MenuLinkFound;
      expect(
        link.uri,
        Uri.parse('https://files.example-cdn.com/cafe-noir/Menu-2026.pdf?v=3'),
      );
      expect(link.isPdf, isTrue);
    });

    test('step 2: any PDF is a candidate when nothing names the menu', () {
      final location = WebsiteMenuLocator.locate(
        '<a href="/docs/today.pdf">Today</a>',
        _home,
      );

      expect((location as MenuLinkFound).uri.path, '/docs/today.pdf');
    });

    test('step 2: the JSON-LD hasMenu URL comes before page links', () {
      const html =
          '<script type="application/ld+json">{"@type": "Restaurant", '
          '"hasMenu": "/our-food"}</script><a href="/menu">Menu</a>';

      final location = WebsiteMenuLocator.locate(html, _home);

      expect(
        (location as MenuLinkFound).uri,
        Uri.parse('https://cafe-noir.example/our-food'),
      );
    });

    test('a link percent-encoded in windows-1255 is found, not thrown', () {
      // Act: `%FA%F4%F8%E9%E8` is not UTF-8, so a strict decode throws.
      final location = WebsiteMenuLocator.locate(
        _fixture('legacy_encoded_menu_link.html'),
        _home,
      );

      // Assert
      expect(
        (location as MenuLinkFound).uri,
        Uri.parse('https://cafe-noir.example/%FA%F4%F8%E9%E8.html'),
      );
    });

    test('a malformed escape beside a menu word still locates the link', () {
      final location = WebsiteMenuLocator.locate(
        '<a href="/about%FF.html">About</a><a href="/menu%FF">Food</a>',
        _home,
      );

      expect(
        (location as MenuLinkFound).uri,
        Uri.parse('https://cafe-noir.example/menu%FF'),
      );
    });

    test('step 3: a page with no menu link finds nothing', () {
      expect(
        WebsiteMenuLocator.locate(_fixture('no_menu.html'), _home),
        isA<NoMenuLink>(),
      );
    });

    test('a link back to the page itself is skipped', () {
      final location = WebsiteMenuLocator.locate(
        '<a href="/menu/">Menu</a><a href="/menu?x=1">Menu again</a>',
        Uri.parse('https://cafe-noir.example/menu'),
      );

      expect(
        (location as MenuLinkFound).uri,
        Uri.parse('https://cafe-noir.example/menu?x=1'),
      );
    });
  });

  group('WebsiteMenuLocator.menuText', () {
    test('reads a Hebrew page whose prices sit on their own lines', () {
      // Act
      final text = WebsiteMenuLocator.menuText(
        _fixture('menu_page_separate_prices.html'),
      );

      // Assert: headers, dishes and descriptions; no nav, footer or price.
      expect(
        text,
        '''
סלטים:
סלט קיסר
- חסה, פרמזן וקרוטונים
סלט יווני
- עגבניות, מלפפון, פטה
עיקריות:
אנטריקוט
- 300 גרם עם צ׳יפס
פסטה ברוטב שמנת'''
            .trim(),
      );
    });

    test('reads an English page whose prices end each dish line', () {
      final text = WebsiteMenuLocator.menuText(
        _fixture('menu_page_inline_prices.html'),
      );

      expect(
        text,
        '''
Starters:
Caesar salad
- romaine, parmesan, croutons
Soup of the day
Mains:
Grilled salmon
Burger & fries'''
            .trim(),
      );
    });

    test('a page with fewer than three prices is not a menu', () {
      expect(WebsiteMenuLocator.menuText(_fixture('no_menu.html')), isNull);
      expect(
        WebsiteMenuLocator.menuText('<p>Salad 40</p><p>Soup 30</p>'),
        isNull,
      );
    });

    test('inline: a lone description and multi-line gaps between dishes', () {
      const html =
          '<p>Kebab 50</p><p>With tahini, salad</p><p>Grill</p>'
          '<p>Steak 90</p><p>Aged 30 days</p><p>From the farm</p>'
          '<p>Desserts</p><p>Tiramisu 40</p><p>Classic</p>';

      expect(
        WebsiteMenuLocator.menuText(html),
        '''
Kebab
- With tahini, salad
Grill:
Steak
- Aged 30 days From the farm
Desserts:
Tiramisu'''
            .trim(),
      );
    });

    test('separate: a single-line block is a dish with no description', () {
      const html =
          '<p>Olives</p><p>12</p><p>12</p><p>Bread</p><p>- warm</p>'
          '<p>15</p><p>:</p><p>9</p>';

      expect(
        WebsiteMenuLocator.menuText(html),
        '''
Olives
Bread
- warm'''
            .trim(),
      );
    });
  });

  group('JsonLdMenuMapper', () {
    test('items directly on a Menu go under the menu name', () {
      final categories = JsonLdMenuMapper.categoriesFrom(<Object?>[
        <String, Object?>{
          '@type': <Object?>['Menu', 'CreativeWork'],
          'hasMenuItem': <Object?>[
            <String, Object?>{'@type': 'MenuItem', 'name': 'Soup'},
            'not an item',
          ],
        },
      ]);

      expect(categories!.single.name, 'Menu');
      expect(categories.single.dishes.single.name, 'Soup');
    });

    test('a menu with no named item is no menu', () {
      expect(
        JsonLdMenuMapper.categoriesFrom(<Object?>[
          <String, Object?>{'@type': 'Menu', 'hasMenuItem': <Object?>[]},
          42,
        ]),
        isNull,
      );
    });

    test('hasMenu may be an object with a url, or a Menu with its own url', () {
      expect(
        JsonLdMenuMapper.menuUrlFrom(<Object?>[
          <String, Object?>{
            'hasMenu': <String, Object?>{'url': 'https://x.example/m'},
          },
        ], _home),
        Uri.parse('https://x.example/m'),
      );
      expect(
        JsonLdMenuMapper.menuUrlFrom(<Object?>[
          <String, Object?>{'@type': 'Menu', 'url': '/food'},
        ], _home),
        Uri.parse('https://cafe-noir.example/food'),
      );
    });

    test('a non-http or malformed hasMenu is ignored', () {
      expect(
        JsonLdMenuMapper.menuUrlFrom(<Object?>[
          <String, Object?>{'hasMenu': 'mailto:a@b.c'},
          <String, Object?>{'hasMenu': 'http://[bad'},
          <String, Object?>{'hasMenu': 7},
        ], _home),
        isNull,
      );
    });
  });
}
