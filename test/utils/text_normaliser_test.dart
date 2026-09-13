import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

Dish _dish({
  String name = 'Dish',
  String description = '',
  List<DishOption> options = const <DishOption>[],
}) => Dish(
  id: 'd1',
  name: name,
  description: description,
  price: 10,
  options: options,
);

Menu _menu(List<Dish> dishes) => Menu(
  venueRef: const VenueRef(source: MenuSource.wolt, platformId: 'slug'),
  currency: 'ILS',
  fetchedAt: DateTime.utc(2024),
  categories: [MenuCategory(id: 'c1', name: 'Mains', dishes: dishes)],
);

void main() {
  group('TextNormaliser.normalise', () {
    test('normalise strips bidi control characters (step 1)', () {
      // Arrange: LRM, RLM, LRE, PDF, LRI, PDI around a plain word. Built
      // from code points rather than embedded as literal characters, so
      // the source file itself never contains a character that changes
      // how the surrounding text renders.
      final raw = String.fromCharCodes(const <int>[
        0x200E, 0x200F, 0x202A, 0x202C,
        0x50, 0x41, 0x53, 0x54, 0x41, // "PASTA"
        0x2066, 0x2069,
      ]);
      // Act
      final result = TextNormaliser.normalise(raw);
      // Assert
      expect(result, equals('pasta'));
    });

    test('normalise strips Hebrew points and teamim (step 2)', () {
      // Arrange: "שָׁלוֹם" with niqqud.
      const raw = 'שָׁלוֹם';
      // Act
      final result = TextNormaliser.normalise(raw);
      // Assert: the ם final folds to מ in step 7.
      expect(result, equals('שלומ'));
    });

    test('normalise deletes a Hebrew geresh (step 3)', () {
      // Act
      final result = TextNormaliser.normalise("צ'יפס");
      // Assert
      expect(result, equals('ציפס'));
      expect(result, equals(TextNormaliser.normalise('ציפס')));
    });

    test('normalise deletes a Hebrew gershayim (step 3)', () {
      // Act
      final result = TextNormaliser.normalise('תפו"א');
      // Assert
      expect(result, equals('תפוא'));
    });

    test('normalise deletes ASCII quote, backtick and smart quotes '
        '(step 3)', () {
      // Act, Assert
      expect(TextNormaliser.normalise("don't"), equals('dont'));
      expect(TextNormaliser.normalise('don’t'), equals('dont'));
      expect(
        TextNormaliser.normalise('the "chef" special'),
        equals('the chef special'),
      );
      expect(TextNormaliser.normalise('rock`n roll'), equals('rockn roll'));
    });

    test('normalise folds a Latin-1 diacritic (step 4)', () {
      // Act, Assert: README's own worked example.
      expect(TextNormaliser.normalise('purée'), equals('puree'));
      expect(TextNormaliser.normalise('café'), equals('cafe'));
      expect(TextNormaliser.normalise('jalapeño'), equals('jalapeno'));
    });

    test('normalise lower-cases Latin text (step 5)', () {
      // Act
      final result = TextNormaliser.normalise('PASTA Bolognese');
      // Assert
      expect(result, equals('pasta bolognese'));
    });

    test('normalise is a no-op case fold on Hebrew (step 5)', () {
      // Act
      final result = TextNormaliser.normalise('פסטה');
      // Assert
      expect(result, equals('פסטה'));
    });

    test('normalise collapses a hyphen into one space (step 6)', () {
      // Act
      final result = TextNormaliser.normalise('תפוחי-אדמה');
      // Assert
      expect(result, equals('תפוחי אדמה'));
    });

    test('normalise collapses a run of punctuation into one space '
        '(step 6)', () {
      // Act
      final result = TextNormaliser.normalise('salad,,,  with!!  corn');
      // Assert
      expect(result, equals('salad with corn'));
    });

    test('normalise trims leading and trailing punctuation (step 6)', () {
      // Act
      final result = TextNormaliser.normalise('  -- pasta! -- ');
      // Assert
      expect(result, equals('pasta'));
    });

    test('normalise folds every Hebrew final letter (step 7)', () {
      // Act, Assert: ך→כ, ם→מ, ן→נ, ף→פ, ץ→צ.
      expect(TextNormaliser.normalise('ך'), equals('כ'));
      expect(TextNormaliser.normalise('ם'), equals('מ'));
      expect(TextNormaliser.normalise('ן'), equals('נ'));
      expect(TextNormaliser.normalise('ף'), equals('פ'));
      expect(TextNormaliser.normalise('ץ'), equals('צ'));
    });

    test('normalise is idempotent', () {
      // Arrange
      const inputs = <String>[
        "Café Purée! צ'יפס",
        '  -- PASTA -- ',
        'תפו"א מטוגן‎',
        'שָׁלוֹם עוֹלָם',
        '',
      ];
      // Act, Assert
      for (final input in inputs) {
        final once = TextNormaliser.normalise(input);
        final twice = TextNormaliser.normalise(once);
        expect(
          twice,
          equals(once),
          reason: 'normalise("$input") is not idempotent',
        );
      }
    });

    test('normalise returns an empty string for an empty input', () {
      // Act
      final result = TextNormaliser.normalise('');
      // Assert
      expect(result, isEmpty);
    });
  });

  group('TextNormaliser.containsHebrew', () {
    test('containsHebrew returns true for Hebrew text', () {
      // Assert
      expect(TextNormaliser.containsHebrew('פסטה'), isTrue);
    });

    test('containsHebrew returns true for mixed-script text', () {
      // Assert
      expect(TextNormaliser.containsHebrew('Beef Burger בלחמנייה'), isTrue);
    });

    test('containsHebrew returns false for Latin-only text', () {
      // Assert
      expect(TextNormaliser.containsHebrew('Grilled salmon'), isFalse);
    });

    test('containsHebrew returns false for an empty string', () {
      // Assert
      expect(TextNormaliser.containsHebrew(''), isFalse);
    });
  });

  group('TextNormaliser.words', () {
    test('words returns the normalised words of the input', () {
      // Act
      final result = TextNormaliser.words('Grilled Salmon Fillet');
      // Assert
      expect(result, equals(['grilled', 'salmon', 'fillet']));
    });

    test('words filters out words shorter than minLength', () {
      // Act
      final result = TextNormaliser.words('a big ox on ice', minLength: 3);
      // Assert
      expect(result, equals(['big', 'ice']));
    });

    test('words returns an empty list for an empty input', () {
      // Act
      final result = TextNormaliser.words('');
      // Assert
      expect(result, isEmpty);
    });

    test('words returns an empty list for punctuation-only input', () {
      // Act
      final result = TextNormaliser.words('!!! ---');
      // Assert
      expect(result, isEmpty);
    });
  });

  group('TextNormaliser.dishSearchText', () {
    test('dishSearchText joins the normalised name and description', () {
      // Arrange
      final dish = _dish(name: 'Café Steak', description: 'With Purée');
      // Act
      final result = TextNormaliser.dishSearchText(dish);
      // Assert
      expect(result, equals('cafe steak with puree'));
    });

    test('dishSearchText includes option group names and value labels', () {
      // Arrange
      final dish = _dish(
        name: 'Burger',
        options: const [
          DishOption(name: 'Choice of side', values: ['Fries', 'Salad']),
        ],
      );
      // Act
      final result = TextNormaliser.dishSearchText(dish);
      // Assert
      expect(result, equals('burger choice of side fries salad'));
    });

    test('dishSearchText omits empty parts', () {
      // Arrange
      final dish = _dish(name: 'Soup');
      // Act
      final result = TextNormaliser.dishSearchText(dish);
      // Assert
      expect(result, equals('soup'));
    });
  });

  group('TextNormaliser.menuFingerprint', () {
    test('menuFingerprint is equal for two menus with identical dish text', () {
      // Arrange
      final menuA = _menu([_dish(name: 'Steak', description: 'Rare')]);
      final menuB = _menu([_dish(name: 'Steak', description: 'Rare')]);
      // Act, Assert
      expect(
        TextNormaliser.menuFingerprint(menuA),
        equals(TextNormaliser.menuFingerprint(menuB)),
      );
    });

    test('menuFingerprint changes when a dish name changes', () {
      // Arrange
      final before = _menu([_dish(name: 'Steak', description: 'Rare')]);
      final after = _menu([_dish(name: 'Chicken', description: 'Rare')]);
      // Act, Assert
      expect(
        TextNormaliser.menuFingerprint(before),
        isNot(equals(TextNormaliser.menuFingerprint(after))),
      );
    });

    test('menuFingerprint is order-sensitive', () {
      // Arrange
      final first = _menu([_dish(name: 'Steak'), _dish(name: 'Salad')]);
      final second = _menu([_dish(name: 'Salad'), _dish(name: 'Steak')]);
      // Act, Assert
      expect(
        TextNormaliser.menuFingerprint(first),
        isNot(equals(TextNormaliser.menuFingerprint(second))),
      );
    });

    test('menuFingerprint is stable across repeated calls', () {
      // Arrange
      final menu = _menu([_dish(name: 'Steak', description: 'Rare')]);
      // Act
      final first = TextNormaliser.menuFingerprint(menu);
      final second = TextNormaliser.menuFingerprint(menu);
      // Assert
      expect(first, equals(second));
    });

    test('menuFingerprint handles a menu with no dishes', () {
      // Arrange
      final menu = _menu(const []);
      // Act
      final result = TextNormaliser.menuFingerprint(menu);
      // Assert
      expect(result, isA<int>());
    });
  });
}
