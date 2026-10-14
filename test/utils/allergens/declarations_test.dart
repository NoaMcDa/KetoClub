// Declarations (Banto; ALG-09, issue #351): platform tags and the
// restaurant's own words ("טבעוני", "ללא גלוטן", 🌱) read as evidence.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/declarations.dart';

/// A dish named [name] with [description] and [tags].
Dish _dish(
  String name, {
  String description = '',
  List<String> tags = const <String>[],
}) => Dish(
  id: 'd',
  name: name,
  description: description,
  price: 0,
  options: const <DishOption>[],
  declaredTags: tags,
);

/// The (rule, source, matched text) of each declaration about [dish].
List<(String, DeclarationSource, String)> _read(Dish dish, {String? heading}) =>
    <(String, DeclarationSource, String)>[
      for (final declaration in Declarations.of(dish, heading: heading))
        (declaration.rule, declaration.source, declaration.matchedText),
    ];

void main() {
  group('Declarations — the table', () {
    test('every rule declares an absence, in taxonomy order, never keto', () {
      for (final rule in declarationRules) {
        // Assert
        expect(rule.polarity, DeclarationPolarity.absent, reason: rule.id);
        expect(
          rule.restrictions,
          <RestrictionId>[...rule.restrictions]
            ..sort((a, b) => a.index.compareTo(b.index)),
          reason: rule.id,
        );
        expect(rule.restrictions, isNot(contains(RestrictionId.keto)));
      }
    });

    test('rule ids are distinct', () {
      // Act
      final ids = <String>[for (final rule in declarationRules) rule.id];

      // Assert
      expect(ids.toSet().length, ids.length);
    });

    test('vegan speaks for milk and eggs; gluten-free for gluten only', () {
      // Act
      final byId = <String, DeclarationRule>{
        for (final rule in declarationRules) rule.id: rule,
      };

      // Assert
      expect(
        byId['vegan']!.restrictions,
        containsAll(<RestrictionId>[
          RestrictionId.vegan,
          RestrictionId.vegetarian,
          RestrictionId.milk,
          RestrictionId.eggs,
        ]),
      );
      expect(byId['glutenFree']!.restrictions, <RestrictionId>[
        RestrictionId.gluten,
      ]);
      expect(byId['lactoseFree']!.restrictions, <RestrictionId>[
        RestrictionId.lactose,
      ]);
    });
  });

  group('Declarations — Hebrew and English text', () {
    final cases =
        <(String, Dish, String?, List<(String, DeclarationSource, String)>)>[
          (
            'a Hebrew dish name',
            _dish('סלט קינואה טבעוני'),
            null,
            [('vegan', DeclarationSource.dishText, 'טבעוני')],
          ),
          (
            'two declarations in one name',
            _dish('תבשיל קטניות- טבעוני/ללא גלוטן'),
            null,
            [
              ('vegan', DeclarationSource.dishText, 'טבעוני'),
              ('glutenFree', DeclarationSource.dishText, 'ללא גלוטן'),
            ],
          ),
          (
            'a heading declares for its dishes',
            _dish('רול סלמון'),
            'סושי ללא גלוטן 🌾',
            [('glutenFree', DeclarationSource.heading, 'ללא גלוטן')],
          ),
          (
            'a symbol alone',
            _dish('Rice bowl'),
            'Specials 🌾',
            [('glutenFree', DeclarationSource.heading, '🌾')],
          ),
          (
            'the seedling in a name, a phrase in the description',
            _dish('Misi Masala Roti 🌱', description: 'Gluten Free'),
            null,
            [
              ('vegan', DeclarationSource.dishText, '🌱'),
              ('glutenFree', DeclarationSource.dishText, 'gluten free'),
            ],
          ),
          (
            'a feminine Hebrew form',
            _dish('פשטידה צמחונית'),
            null,
            [('vegetarian', DeclarationSource.dishText, 'צמחונית')],
          ),
          (
            'Hebrew prefixes',
            _dish('קציצות עדשים וטבעוני', description: 'ובלי גלוטן'),
            null,
            [
              ('vegan', DeclarationSource.dishText, 'טבעוני'),
              ('glutenFree', DeclarationSource.dishText, 'בלי גלוטן'),
            ],
          ),
          (
            'no dairy products',
            _dish('גלידה ללא מוצרי חלב'),
            null,
            [('dairyFree', DeclarationSource.dishText, 'ללא מוצרי חלב')],
          ),
          (
            'a hyphenated English phrase',
            _dish('Dairy-free ice cream'),
            null,
            [('dairyFree', DeclarationSource.dishText, 'dairy free')],
          ),
          (
            'the GF marker',
            _dish('Pancakes (GF)'),
            null,
            [('glutenFree', DeclarationSource.dishText, 'gf')],
          ),
          (
            'lactose-free in Hebrew',
            _dish('הפוך ללא לקטוז'),
            null,
            [('lactoseFree', DeclarationSource.dishText, 'ללא לקטוז')],
          ),
          (
            'egg-free in Hebrew',
            _dish('עוגת שוקולד ללא ביצים'),
            null,
            [('eggFree', DeclarationSource.dishText, 'ללא ביצים')],
          ),
          ('nothing declared', _dish('Entrecôte'), 'Steaks', []),
        ];
    for (final (label, dish, heading, expected) in cases) {
      test(label, () {
        // Act & Assert
        expect(_read(dish, heading: heading), expected);
      });
    }
  });

  group('Declarations — an offer or a negation is no declaration', () {
    final cases = <(String, String)>[
      ('a footnote offer', 'ניתן לקבל טבעוני'),
      ('on request', 'טבעוני לפי בקשה'),
      ('a surcharge', 'ללא גלוטן בתוספת 5 ש״ח'),
      ('also available', 'יש גם ללא גלוטן'),
      ('a Hebrew negation', 'לא טבעוני'),
      ('an English option', 'Vegan option available'),
      ('an English negation', 'Not vegan'),
      ('a hyphenated negation', 'non-vegan base'),
      ('can be made', 'Can be made gluten-free'),
      ('a substitute', 'gluten free bun available'),
    ];
    for (final (label, description) in cases) {
      test(label, () {
        // Act & Assert
        expect(_read(_dish('Dish', description: description)), isEmpty);
      });
    }
  });

  group('Declarations — platform tags', () {
    test('a tag is read through the same table, quoted as written', () {
      // Act
      final read = _read(
        _dish('Vegan bowl', tags: <String>['VEGAN', 'GLUTEN_FREE']),
      );

      // Assert: tags first, then the dish's own words.
      expect(read, <(String, DeclarationSource, String)>[
        ('vegan', DeclarationSource.platformTag, 'VEGAN'),
        ('glutenFree', DeclarationSource.platformTag, 'GLUTEN_FREE'),
        ('vegan', DeclarationSource.dishText, 'vegan'),
      ]);
    });

    test('one declaration per rule, the first tag kept', () {
      // Act & Assert
      expect(_read(_dish('Bowl', tags: <String>['vegan', 'Vegan'])), [
        ('vegan', DeclarationSource.platformTag, 'vegan'),
      ]);
    });

    test('a negated or unknown tag declares nothing', () {
      // Act & Assert
      expect(
        _read(_dish('Bowl', tags: <String>['NON_VEGAN', 'spicy', 'popular'])),
        isEmpty,
      );
    });

    test('kosher is no restriction, only the platform flag', () {
      // Arrange
      final dish = _dish('Bread', tags: <String>[kosherDeclaredTag]);

      // Act & Assert
      expect(_read(dish), isEmpty);
      expect(Declarations.declaresKosher(dish), isTrue);
      expect(
        Declarations.declaresKosher(_dish('Bread', tags: <String>['KOSHER'])),
        isTrue,
      );
      expect(
        Declarations.declaresKosher(_dish('Bread', tags: <String>['כשר'])),
        isTrue,
      );
      expect(Declarations.declaresKosher(_dish('Bread')), isFalse);
    });

    test('kosher in the dish text is not the platform flag', () {
      // Act & Assert
      expect(Declarations.declaresKosher(_dish('Kosher bread כשר')), isFalse);
    });
  });

  group('Declaration', () {
    test('toJson names every field', () {
      // Arrange
      const declaration = Declaration(
        rule: 'glutenFree',
        restrictionIds: <RestrictionId>[RestrictionId.gluten],
        polarity: DeclarationPolarity.absent,
        source: DeclarationSource.heading,
        matchedText: 'ללא גלוטן',
      );

      // Act & Assert
      expect(declaration.toJson(), <String, Object?>{
        'rule': 'glutenFree',
        'restrictionIds': <String>['gluten'],
        'polarity': 'absent',
        'source': 'heading',
        'matchedText': 'ללא גלוטן',
      });
      expect(declaration.toString(), contains('glutenFree'));
      expect(
        declaration,
        equals(
          const Declaration(
            rule: 'glutenFree',
            restrictionIds: <RestrictionId>[RestrictionId.gluten],
            polarity: DeclarationPolarity.absent,
            source: DeclarationSource.heading,
            matchedText: 'ללא גלוטן',
          ),
        ),
      );
    });
  });
}
