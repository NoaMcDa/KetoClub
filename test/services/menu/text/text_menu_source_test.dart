import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/text/text_menu_source.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

final DateTime _now = DateTime.utc(2026, 9, 29, 12);

Menu _parse(String text) => TextMenuSource.parse(text, now: _now)!;

List<String> _names(Menu menu) => [for (final d in menu.allDishes) d.name];

void main() {
  group('TextMenuSource.parse', () {
    test('turns one line per dish into dishes with no price or options', () {
      // Act
      final menu = _parse('Grilled salmon\nCaesar salad\nPasta carbonara');

      // Assert
      expect(_names(menu), [
        'Grilled salmon',
        'Caesar salad',
        'Pasta carbonara',
      ]);
      for (final dish in menu.allDishes) {
        expect(dish.price, 0);
        expect(dish.options, isEmpty);
        expect(dish.description, isEmpty);
      }
      expect(menu.currency, 'ILS');
      expect(menu.fetchedAt, _now);
      expect(menu.venueName, isNull);
    });

    test('numbers dish ids p1..pN in line order', () {
      // Act
      final menu = _parse('A one\nB two\nC three');

      // Assert
      expect([for (final d in menu.allDishes) d.id], ['p1', 'p2', 'p3']);
    });

    test('puts headerless dishes in the pasted category', () {
      // Act
      final menu = _parse('Steak\nSalmon');

      // Assert
      expect(menu.categories, hasLength(1));
      expect(menu.categories.single.id, 'pasted');
      expect(menu.categories.single.name, 'Pasted menu');
    });

    test('names the headerless category after uncategorisedName', () {
      // Act
      final menu = TextMenuSource.parse(
        'Steak',
        now: _now,
        uncategorisedName: 'תפריט שהודבק',
      )!;

      // Assert
      expect(menu.categories.single.name, 'תפריט שהודבק');
    });

    test('handles Windows and old-Mac line breaks and stray whitespace', () {
      // Act
      final menu = _parse('  Steak \r\n  Salmon\r  Tuna  ');

      // Assert
      expect(_names(menu), ['Steak', 'Salmon', 'Tuna']);
    });

    group('prices', () {
      final cases = <String, String>{
        'Grilled salmon 45': 'Grilled salmon',
        'Grilled salmon 45 ₪': 'Grilled salmon',
        'Grilled salmon 45₪': 'Grilled salmon',
        'Grilled salmon ₪45': 'Grilled salmon',
        'Grilled salmon - 45': 'Grilled salmon',
        'Grilled salmon – 45.90 NIS': 'Grilled salmon',
        'Grilled salmon 45,50 ILS': 'Grilled salmon',
        'Grilled salmon 45 nis': 'Grilled salmon',
        'סלמון על הגריל 68 ₪': 'סלמון על הגריל',
      };
      for (final MapEntry(key: line, value: expected) in cases.entries) {
        test('strips the price from "$line"', () {
          // Act
          final menu = _parse('$line\nSteak');

          // Assert
          expect(menu.allDishes.first.name, expected);
        });
      }

      test('leaves a digit inside a word, and a non-final number, alone', () {
        // Act
        final menu = _parse('Vitamin B12 shake\nPizza 4 formaggi\nSteak');

        // Assert
        expect(_names(menu), [
          'Vitamin B12 shake',
          'Pizza 4 formaggi',
          'Steak',
        ]);
      });

      test('drops a line that is only a price', () {
        // Act
        final menu = _parse('Steak\n45 ₪\nSalmon');

        // Assert
        expect(_names(menu), ['Steak', 'Salmon']);
      });

      test('never lets a price into any dish text', () {
        // Act
        final menu = _parse('Steak 89\nwith fries 12 ₪\nSalmon 75 NIS');

        // Assert
        for (final dish in menu.allDishes) {
          expect('${dish.name} ${dish.description}', isNot(contains('₪')));
          expect(dish.name, isNot(matches(r'\d')));
        }
        expect(menu.allDishes.first.description, 'with fries');
      });
    });

    group('section headers', () {
      test('a line ending in a colon starts a category', () {
        // Act
        final menu = _parse('Starters:\nHummus\nSoup\nMains:\nSteak');

        // Assert
        expect(
          [for (final c in menu.categories) c.name],
          ['Starters', 'Mains'],
        );
        expect(_names(menu), ['Hummus', 'Soup', 'Steak']);
        expect(menu.categories.first.dishes, hasLength(2));
      });

      test('a long line before a blank line stays a dish', () {
        // Act
        final menu = _parse(
          'Grilled salmon with lemon butter sauce\n\nSteak\nTuna',
        );

        // Assert
        expect(_names(menu).first, 'Grilled salmon with lemon butter sauce');
      });

      test('a short line with a digit before a blank line stays a dish', () {
        // Act: the trailing 1 is read as a price, the 2 stays.
        final menu = _parse('Combo 2 for 1\n\nSteak\nTuna');

        // Assert
        expect(_names(menu).first, 'Combo 2 for');
      });

      test('the last dish of a group is not a header', () {
        // Act: Soup is followed by a blank line but has a dish above it.
        final menu = _parse('Starters\n\nHummus\nSoup\n\nMains\n\nSteak');

        // Assert
        expect(_names(menu), ['Hummus', 'Soup', 'Steak']);
        expect(
          [for (final c in menu.categories) c.name],
          ['Starters', 'Mains'],
        );
      });

      test('a last short line is a dish, not a header for nothing', () {
        // Act
        final menu = _parse('Steak\nSalmon\n\nDessert\n\n');

        // Assert
        expect(_names(menu), ['Steak', 'Salmon', 'Dessert']);
        expect(menu.categories, hasLength(1));
      });

      test('a double-spaced paste is all dishes, not all headers', () {
        // Act
        final menu = _parse('Steak\n\nSalmon\n\nTuna');

        // Assert
        expect(_names(menu), ['Steak', 'Salmon', 'Tuna']);
      });

      test('a header with no dishes under it makes no category', () {
        // Act
        final menu = _parse('Empty:\nMains:\nSteak');

        // Assert
        expect([for (final c in menu.categories) c.name], ['Mains']);
      });

      test('a header ids each category apart', () {
        // Act
        final menu = _parse('A:\nSteak\nB:\nSalmon');

        // Assert
        final ids = [for (final c in menu.categories) c.id];
        expect(ids.toSet(), hasLength(2));
      });
    });

    group('wrapped lines', () {
      test('a lowercase, dash or parenthesis line joins the dish above', () {
        // Act
        final menu = _parse(
          'Grilled salmon\nwith lemon and herbs\n- served with greens\n'
          '(gluten free)\nCaesar salad',
        );

        // Assert
        expect(_names(menu), ['Grilled salmon', 'Caesar salad']);
        expect(
          menu.allDishes.first.description,
          'with lemon and herbs served with greens (gluten free)',
        );
      });

      test('a Hebrew wrapped line joins through a dash or parenthesis', () {
        // Act
        final menu = _parse('סלמון על הגריל\n- עם ירקות\nסלט קיסר');

        // Assert
        expect(_names(menu), ['סלמון על הגריל', 'סלט קיסר']);
        expect(menu.allDishes.first.description, 'עם ירקות');
      });

      test('a blank line stops a wrapped line from joining', () {
        // Act
        final menu = _parse('Steak\nSalmon\n\nwith rice');

        // Assert
        expect(_names(menu), ['Steak', 'Salmon', 'with rice']);
      });

      test('a wrapped line straight after a header is a dish of its own', () {
        // Act
        final menu = _parse('Mains:\nwith rice');

        // Assert
        expect(_names(menu), ['with rice']);
      });

      test('a parenthesis line is not mistaken for a short header', () {
        // Act
        final menu = _parse('Steak\n(200g)\n\nSalmon\nTuna');

        // Assert
        expect(_names(menu), ['Steak', 'Salmon', 'Tuna']);
        expect(menu.allDishes.first.description, '(200g)');
      });
    });

    group('no menu', () {
      for (final text in <String>['', '   ', '\n\n\n', '45 ₪\n12', ':\n:']) {
        test('returns null for ${text.isEmpty ? 'empty text' : '"$text"'}', () {
          expect(TextMenuSource.parse(text, now: _now), isNull);
        });
      }

      test('returns null when there are only headers', () {
        expect(TextMenuSource.parse('Starters:\nMains:', now: _now), isNull);
      });
    });

    group('cap', () {
      test('keeps at most maxAnalysedDishes dishes', () {
        // Arrange
        final text = [
          for (var i = 0; i < maxAnalysedDishes + 25; i++) 'Dish number $i x',
        ].join('\n');

        // Act
        final menu = _parse(text);

        // Assert
        expect(menu.allDishes, hasLength(maxAnalysedDishes));
        expect(menu.allDishes.last.id, 'p$maxAnalysedDishes');
      });

      test('keeps every dish of a menu exactly at the cap', () {
        // Arrange
        final text = [
          for (var i = 0; i < maxAnalysedDishes; i++) 'Dish number $i x',
        ].join('\n');

        // Act
        final menu = _parse(text);

        // Assert
        expect(menu.allDishes, hasLength(maxAnalysedDishes));
      });
    });

    group('reference', () {
      test('is a scan ref whose id is the hex fingerprint of the dishes', () {
        // Act
        final menu = _parse('Steak\nSalmon');

        // Assert
        final expected = TextNormaliser.menuFingerprint(menu)
            .toRadixString(16)
            .padLeft(8, '0');
        expect(menu.venueRef.source, MenuSource.scan);
        expect(menu.venueRef.platformId, expected);
        expect(menu.venueRef.platformId, hasLength(8));
      });

      test('is the same for the same text pasted twice, at any time', () {
        // Act
        final first = TextMenuSource.parse('Steak\nSalmon', now: _now)!;
        final second = TextMenuSource.parse(
          'Steak\nSalmon',
          now: _now.add(const Duration(days: 3)),
        )!;

        // Assert
        expect(second.venueRef, first.venueRef);
      });

      test('ignores the price a repeat paste carries', () {
        // Act
        final plain = _parse('Steak\nSalmon');
        final priced = _parse('Steak 89\nSalmon 75 ₪');

        // Assert
        expect(priced.venueRef, plain.venueRef);
      });

      test('differs for different dishes', () {
        // Act
        final a = _parse('Steak\nSalmon');
        final b = _parse('Steak\nTuna');

        // Assert
        expect(a.venueRef, isNot(b.venueRef));
      });

      test('survives a JSON round trip through the cache form', () {
        // Act
        final menu = _parse('Starters:\nHummus\nwith tahini\nMains:\nSteak');
        final decoded = Menu.tryFrom(menu.toJson());

        // Assert
        expect(decoded, menu);
      });
    });

    group('price shapes (#282)', () {
      final cases = <String, String>{
        'סלט יווני 48 ש"ח': 'סלט יווני',
        'סלט יווני 48 ש״ח': 'סלט יווני',
        'סלט יווני 48 שקלים': 'סלט יווני',
        'Tuna 67 shkalim': 'Tuna',
        'Cod מחיר: 89': 'Cod',
        '45 Pasta': 'Pasta',
        '₪38 Omelette': 'Omelette',
        'NIS 64 Burger': 'Burger',
        'Steak (128)': 'Steak',
        'Soup 32.-': 'Soup',
        'Wings 48/56': 'Wings',
        'Salad small 38 / large 52': 'Salad small / large',
        'Greek salad ........ 48': 'Greek salad',
        'Caesar salad | 52': 'Caesar salad',
      };
      for (final MapEntry(key: line, value: expected) in cases.entries) {
        test('strips the price from "$line"', () {
          // Act
          final menu = _parse('$line\nSteak');

          // Assert
          expect(menu.allDishes.first.name, expected);
        });
      }

      test('reads a 200 KB run of marks or spaces in linear time', () {
        for (final run in const ['-', ':', '.', ' ', ' .']) {
          // Arrange
          final text = 'Steak 45\nSalad${run * (200000 ~/ run.length)}x';
          final watch = Stopwatch()..start();

          // Act
          TextMenuSource.parse(text, now: _now);

          // Assert
          expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
        }
      });

      test('keeps a leading weight and a single leading digit', () {
        // Act
        final menu = _parse('300 גרם אנטריקוט 120\n200 g steak\n2 eggs');

        // Assert
        expect(_names(menu), ['300 גרם אנטריקוט', '200 g steak', '2 eggs']);
      });
    });

    group('bullets (#282)', () {
      test('a dashed list is one dish per line, without the dash', () {
        // Act
        final menu = _parse(
          '- Caesar salad 48\n- Greek salad 42\n- Steak frites 98',
        );

        // Assert
        expect(_names(menu), ['Caesar salad', 'Greek salad', 'Steak frites']);
        expect(menu.allDishes.first.description, isEmpty);
      });

      test('symbol and numbered bullets are removed', () {
        // Act
        final menu = _parse(
          '\u{1F538} סלט יווני 48\n▪\u{FE0F} Burger 64\n• Soup\n'
          '1. Caesar salad 48\n2) Pasta 52',
        );

        // Assert
        expect(_names(menu), [
          'סלט יווני',
          'Burger',
          'Soup',
          'Caesar salad',
          'Pasta',
        ]);
      });

      test('an all-lowercase list is one dish per line', () {
        // Act
        final menu = _parse('caesar salad\ngreek salad\nsteak');

        // Assert
        expect(_names(menu), ['caesar salad', 'greek salad', 'steak']);
      });
    });

    group('priced pastes (#479)', () {
      test('a price-less line under a priced dish is its description', () {
        // Act
        final menu = _parse(
          'סלט יווני 48\nעגבניות, מלפפון, בצל ופטה\n\nהמבורגר 68\n'
          'לחמניית בריוש, צ׳יפס בצד\n\nפסטה ברוטב עגבניות 52\n'
          'פנה, רוטב עגבניות, בזיליקום',
        );

        // Assert
        expect(_names(menu), ['סלט יווני', 'המבורגר', 'פסטה ברוטב עגבניות']);
        expect(
          menu.allDishes.elementAt(1).description,
          'לחמניית בריוש, צ׳יפס בצד',
        );
      });

      test('a capitalised English description joins its dish', () {
        // Act
        final menu = _parse(
          'Burger 64\nWith brioche bun and fries\nSteak 98\nSalad 42',
        );

        // Assert
        expect(_names(menu), ['Burger', 'Steak', 'Salad']);
        expect(menu.allDishes.first.description, 'With brioche bun and fries');
      });

      test('a price-less short line before priced dishes is a header', () {
        // Act
        final menu = _parse(
          'ראשונות\nחומוס 32\nמרק 28\n\nמנות עיקריות\nסטייק 120\nשניצל 68',
        );

        // Assert
        expect(
          [for (final c in menu.categories) c.name],
          ['ראשונות', 'מנות עיקריות'],
        );
        expect(_names(menu), ['חומוס', 'מרק', 'סטייק', 'שניצל']);
      });

      test('an all-capitals line after a dish is a header', () {
        // Act
        final menu = _parse(
          'STARTERS\nHummus 32\nSoup 28\nMAINS\nSteak 120\nSchnitzel 68',
        );

        // Assert
        expect(
          [for (final c in menu.categories) c.name],
          ['STARTERS', 'MAINS'],
        );
        expect(_names(menu), ['Hummus', 'Soup', 'Steak', 'Schnitzel']);
      });

      test('a paste without prices keeps one dish per line', () {
        // Act
        final menu = _parse('Burger\nWith brioche bun and fries\nSteak');

        // Assert
        expect(_names(menu), ['Burger', 'With brioche bun and fries', 'Steak']);
      });
    });

    group('WhatsApp copies (#479)', () {
      test('a bold or italic line is a header, without its markers', () {
        // Act
        final menu = _parse(
          '*סלטים*\nסלט יווני 48\nסלט קיסר 52\n_עיקריות_\nסטייק 120\n'
          '*Burger* 64',
        );

        // Assert
        expect([for (final c in menu.categories) c.name], ['סלטים', 'עיקריות']);
        expect(_names(menu), ['סלט יווני', 'סלט קיסר', 'סטייק', 'Burger']);
      });

      test('the sender and time are removed from each line', () {
        // Act
        final menu = _parse(
          '[12/11/2026, 14:02] Dana: Caesar salad 48\n'
          '[12/11/2026, 14:03:09 PM] Dana: Steak 98\n'
          '‎12.11.26, 14:04 - Dana Cohen: Soup 32',
        );

        // Assert
        expect(_names(menu), ['Caesar salad', 'Steak', 'Soup']);
      });
    });

    test('reads a Hebrew menu the same way', () {
      // Act
      final menu = _parse(
        'ראשונות:\nחומוס 32 ₪\nמרק היום\n\nעיקריות:\nסטייק 120',
      );

      // Assert
      expect(_names(menu), ['חומוס', 'מרק היום', 'סטייק']);
      expect([for (final c in menu.categories) c.name], ['ראשונות', 'עיקריות']);
    });
  });
}
