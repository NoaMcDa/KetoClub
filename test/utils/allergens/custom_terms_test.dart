// The user's own restriction, matched on the device (Banto, ALG-17, issue
// #359): free-text words in English and Hebrew, prefix-tolerant, plural-
// tolerant, guarded, and never mistaken for a longer word.

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/custom_terms.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';
import 'package:ketoclub/utils/classification_rules.dart';

/// The terms of [words]' hits in [text], as the vocabulary spells them.
List<String> _hitTerms(String text, List<String> words) => <String>[
  for (final hit in AllergenMatcher.findWith(text, customTermVocabulary(words)))
    hit.term,
];

/// The hits of [words] in [text].
List<AllergenHit> _hits(String text, List<String> words) =>
    AllergenMatcher.findWith(text, customTermVocabulary(words));

void main() {
  group('customTermVocabulary', () {
    test('no words is an empty vocabulary', () {
      expect(customTermVocabulary(const <String>[]), isEmpty);
      expect(customTermVocabulary(<String>['   ', '!!']), isEmpty);
    });

    test('splits the words by script, all under custom, all direct', () {
      // Act
      final vocabulary = customTermVocabulary(<String>['kiwi', 'כוסברה']);

      // Assert
      expect(vocabulary.keys, <RestrictionId>[RestrictionId.custom]);
      final own = vocabulary[RestrictionId.custom]!;
      expect(own.directEn, <String>['kiwi', 'kiwis']);
      expect(own.directHe, <String>['כוסברה']);
      expect(own.hiddenEn, isEmpty);
      expect(own.hiddenHe, isEmpty);
    });

    test('an English word ending in s also matches its singular', () {
      final own = customTermVocabulary(<String>[
        'pine nuts',
      ])[RestrictionId.custom]!;
      expect(own.directEn, <String>['pine nuts', 'pine nut']);
    });

    test('is the same map for the same list, and rebuilt for another', () {
      // Arrange
      final words = List<String>.unmodifiable(<String>['kiwi']);

      // Act
      final first = customTermVocabulary(words);
      final again = customTermVocabulary(words);
      final other = customTermVocabulary(<String>['kiwi']);

      // Assert
      expect(identical(first, again), isTrue);
      expect(other[RestrictionId.custom]!.directEn, <String>['kiwi', 'kiwis']);
    });

    test("the registry knows nothing of anyone's words (C1)", () {
      expect(allergenVocabulary[RestrictionId.custom]!.isEmpty, isTrue);
      expect(
        AllergenMatcher.find('Kiwi sorbet')
            .where((hit) => hit.id == RestrictionId.custom),
        isEmpty,
      );
    });
  });

  group('matching', () {
    const cases = <(String text, List<String> words, List<String> terms)>[
      ('Kiwi sorbet', <String>['kiwi'], <String>['kiwi']),
      ('KIWI SORBET', <String>['kiwi'], <String>['kiwi']),
      ('Sliced kiwis', <String>['kiwi'], <String>['kiwis']),
      ('Pesto with pine nuts', <String>['pine nuts'], <String>['pine nuts']),
      ('Toasted pine nut crumb', <String>['pine nuts'], <String>['pine nut']),
      ('סלט עם כוסברה', <String>['כוסברה'], <String>['כוסברה']),
      ('סלט בכוסברה', <String>['כוסברה'], <String>['כוסברה']),
      ('סלט והכוסברה', <String>['כוסברה'], <String>['כוסברה']),
      ('רוטב עם קיווי', <String>['קיווי'], <String>['קיווי']),
      (
        'Kiwi and coriander',
        <String>['kiwi', 'coriander'],
        <String>['kiwi', 'coriander'],
      ),
    ];
    for (final (text, words, terms) in cases) {
      test('"$text" for $words finds $terms', () {
        expect(_hitTerms(text, words), terms);
      });
    }

    const misses = <(String text, List<String> words)>[
      // A word never matches inside a longer one.
      ('Peanut butter cookie', <String>['pea']),
      ('Peach melba', <String>['pea']),
      ('Kiwifruit jam', <String>['kiwi']),
      ('כוסברות', <String>['כוסברה']),
      // Nor does it match a word it is not.
      ('Green salad', <String>['kiwi']),
    ];
    for (final (text, words) in misses) {
      test('"$text" for $words finds nothing', () {
        expect(_hits(text, words), isEmpty);
      });
    }

    test('"no", "without", "-free", "ללא" and "בלי" lower, never clear', () {
      for (final (text, word) in <(String, String)>[
        ('No kiwi please', 'kiwi'),
        ('Served without coriander', 'coriander'),
        ('Kiwi-free fruit salad', 'kiwi'),
        ('סלט ללא כוסברה', 'כוסברה'),
        ('סלט בלי כוסברה', 'כוסברה'),
      ]) {
        final hits = _hits(text, <String>[word]);
        expect(hits, hasLength(1), reason: text);
        expect(hits.single.guarded, isTrue, reason: text);
        expect(hits.single.certainty, TriggerCertainty.suspected);
      }
    });
  });

  group('ClassificationRules.allergenFindings with the own vocabulary', () {
    test('reads the name, description and option values as their parts, '
        "skipping a removal value, with the menu's own slice", () {
      // Arrange
      const dish = Dish(
        id: 'd1',
        name: 'Fruit salad',
        description: 'Mango, KIWI and mint',
        price: 30,
        options: <DishOption>[
          DishOption(
            name: 'Toppings',
            values: <String>['Extra kiwi', 'No kiwi'],
          ),
        ],
      );

      // Act
      final findings = ClassificationRules.allergenFindings(
        dish,
        vocabulary: customTermVocabulary(<String>['kiwi']),
      );

      // Assert
      expect(
        findings.map((concern) => (concern.source, concern.matchedText)),
        <(ConcernSource, String?)>[
          (ConcernSource.description, 'KIWI'),
          (ConcernSource.option, 'kiwi'),
        ],
      );
      expect(
        findings.every(
          (concern) => concern.restrictionId == RestrictionId.custom,
        ),
        isTrue,
      );
    });
  });
}
