/// The rule engine's hidden-carb flags (issue #213 on the rules path;
/// architecture.md §9.4 rule 5a): the bilingual trigger tables in
/// `constants.dart`, their guards, the covering rule, the overlap and
/// source dedupe, the cap, and which text of a dish is read.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/utils/classification_rules.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// An English sentence with [trigger] in the middle and no other trigger.
String _en(String trigger) => 'Grilled salmon with $trigger for dinner';

/// A Hebrew sentence with [trigger] in the middle and no other trigger.
String _he(String trigger) => 'סלמון על הגריל עם $trigger להיום';

/// The sources of [text]'s flags, in order.
List<String> _sources(String text) => [
  for (final flag in ClassificationRules.match(text).hiddenCarbs) flag.source,
];

/// A dish with [name], [description] and [options].
Dish _dish(
  String name, {
  String description = '',
  List<DishOption> options = const <DishOption>[],
}) => Dish(
  id: 'd1',
  name: name,
  description: description,
  price: 10,
  options: options,
);

void main() {
  group('hidden-carb vocabulary', () {
    final tables = <String, Map<String, HiddenCarbTrigger>>{
      'en': hiddenCarbTriggersEn,
      'he': hiddenCarbTriggersHe,
    };

    test('every flag has a known certainty and concern', () {
      for (final table in tables.values) {
        for (final MapEntry(key: trigger, value: flag) in table.entries) {
          expect(
            HiddenCarbCertainty.tryParse(flag.certainty),
            isNotNull,
            reason: trigger,
          );
          expect(
            <String>['sugar', 'flour', 'sugarOrFlour'],
            contains(flag.concern),
            reason: trigger,
          );
        }
      }
    });

    test('every source and question is non-blank and within the caps', () {
      for (final table in tables.values) {
        for (final MapEntry(key: trigger, value: flag) in table.entries) {
          for (final text in <String>[flag.sourceEn, flag.sourceHe]) {
            expect(text.trim(), isNotEmpty, reason: trigger);
            expect(text.length, lessThanOrEqualTo(maxWhyLength));
          }
          for (final text in <String>[flag.questionEn, flag.questionHe]) {
            expect(text.trim(), isNotEmpty, reason: trigger);
            expect(text.length, lessThanOrEqualTo(maxModificationLength));
          }
          expect(TextNormaliser.containsHebrew(flag.sourceEn), isFalse);
          expect(TextNormaliser.containsHebrew(flag.questionEn), isFalse);
          expect(TextNormaliser.containsHebrew(flag.sourceHe), isTrue);
          expect(TextNormaliser.containsHebrew(flag.questionHe), isTrue);
        }
      }
    });

    test('English triggers are Latin and Hebrew triggers are Hebrew', () {
      for (final trigger in hiddenCarbTriggersEn.keys) {
        expect(TextNormaliser.containsHebrew(trigger), isFalse);
      }
      for (final trigger in hiddenCarbTriggersHe.keys) {
        expect(TextNormaliser.containsHebrew(trigger), isTrue);
      }
    });

    test('no two triggers of one table normalise alike', () {
      for (final table in tables.values) {
        final normalised = table.keys.map(TextNormaliser.normalise).toList();
        expect(normalised.toSet(), hasLength(normalised.length));
      }
    });

    test('no trigger doubles a carb modifier', () {
      final modifiers = <String>{
        for (final key in <String>[
          ...carbModifiersEn.keys,
          ...carbModifiersHe.keys,
        ])
          TextNormaliser.normalise(key),
      };
      for (final table in tables.values) {
        for (final trigger in table.keys) {
          expect(
            modifiers,
            isNot(contains(TextNormaliser.normalise(trigger))),
            reason: trigger,
          );
        }
      }
    });

    test('every covering modifier is a carb modifier', () {
      for (final key in hiddenCarbCoveringModifiers) {
        expect(
          carbModifiersEn.containsKey(key) || carbModifiersHe.containsKey(key),
          isTrue,
          reason: key,
        );
      }
    });

    test('every per-trigger guard belongs to a trigger of its table', () {
      for (final key in hiddenCarbTriggerGuardsEn.keys) {
        expect(hiddenCarbTriggersEn, contains(key));
      }
      for (final key in hiddenCarbTriggerGuardsHe.keys) {
        expect(hiddenCarbTriggersHe, contains(key));
      }
    });

    test('the guard phrase tables answer sugar, flour or any', () {
      for (final table in [
        hiddenCarbGuardPhrasesEn,
        hiddenCarbGuardPhrasesHe,
      ]) {
        expect(table.keys.toSet(), <String>{'sugar', 'flour', 'any'});
      }
    });

    test('the cap is the model path cap and the window is three words', () {
      expect(maxHiddenCarbsPerDish, 3);
      expect(hiddenCarbWindowWords, 3);
    });
  });

  group('ClassificationRules.match — every hiddenCarbTriggersEn trigger', () {
    for (final MapEntry(key: trigger, value: flag)
        in hiddenCarbTriggersEn.entries) {
      test('"$trigger" raises its English flag and nothing else', () {
        // Act
        final match = ClassificationRules.match(_en(trigger));

        // Assert
        expect(match.isNonKeto, isFalse);
        expect(match.instructions, isEmpty);
        expect(match.hiddenCarbs, [
          HiddenCarb(
            source: flag.sourceEn,
            certainty: HiddenCarbCertainty.values.byName(flag.certainty),
            waiterQuestion: flag.questionEn,
          ),
        ]);
      });

      test('"$trigger" in capitals still matches', () {
        expect(_sources(_en(trigger.toUpperCase())), [flag.sourceEn]);
      });
    }
  });

  group('ClassificationRules.match — every hiddenCarbTriggersHe trigger', () {
    for (final MapEntry(key: trigger, value: flag)
        in hiddenCarbTriggersHe.entries) {
      test('"$trigger" raises its Hebrew flag', () {
        // Act
        final match = ClassificationRules.match(_he(trigger));

        // Assert
        expect(match.instructions, isEmpty);
        expect(match.hiddenCarbs, [
          HiddenCarb(
            source: flag.sourceHe,
            certainty: HiddenCarbCertainty.values.byName(flag.certainty),
            waiterQuestion: flag.questionHe,
          ),
        ]);
      });

      test('"$trigger" matches behind a prefix particle', () {
        expect(_sources(_he('ב$trigger')), [flag.sourceHe]);
        expect(_sources(_he('וה$trigger')), [flag.sourceHe]);
      });

      test('"$trigger" does not match inside a longer word', () {
        expect(_sources(_he('$triggerתי')), isNot(contains(flag.sourceHe)));
      });
    }
  });

  group('ClassificationRules.match — guard phrases', () {
    test('a sugar phrase cancels a sugar flag on either side', () {
      expect(_sources('Glazed salmon, sugar-free'), isEmpty);
      expect(_sources('Sugar free glaze on salmon'), isEmpty);
      expect(_sources('House sauce, no added sugar'), isEmpty);
      expect(_sources('פרגית ברוטב שום ללא סוכר'), isEmpty);
      expect(_sources('פרגית במרינדה ללא תוספת סוכר'), isEmpty);
      expect(_sources('פרגית ברוטב שום וללא סוכר'), isEmpty);
    });

    test('a sugar phrase does not answer a flour flag', () {
      expect(_sources('Steak with gravy, sugar-free'), ['gravy']);
      expect(_sources('אנטריקוט ברוטב חום ללא סוכר'), ['רוטב חום']);
    });

    test('a flour phrase answers a flour flag, not a sugar one', () {
      expect(_sources('Steak with gravy, flourless'), isEmpty);
      expect(_sources('אנטריקוט ברוטב חום ללא קמח'), isEmpty);
      expect(_sources('Salmon glaze, no flour'), ['glaze']);
    });

    test('a keto phrase answers every flag', () {
      expect(_sources('Keto gravy'), isEmpty);
      expect(_sources('Keto glazed salmon'), isEmpty);
      expect(_sources('אנטריקוט ברוטב חום דל פחמימות'), isEmpty);
    });

    test('a phrase inside the three-word window cancels; past it, not', () {
      expect(_sources('House sauce with no sugar'), isEmpty);
      expect(_sources('House sauce with herbs and no sugar'), ['house sauce']);
    });
  });

  group('ClassificationRules.match — per-trigger guards', () {
    test('crispy skin, bacon and pork belly carry no coating', () {
      expect(_sources('Crispy skin salmon'), isEmpty);
      expect(_sources('Salad with crispy bacon'), isEmpty);
      expect(_sources('Crispy pork belly'), isEmpty);
      expect(_sources('Crispy salmon'), ['crispy coating']);
    });

    test('Hebrew crispy is guarded on both sides', () {
      expect(_sources('סלמון בעור קריספי'), isEmpty);
      expect(_sources('קריספי עם בייקון'), isEmpty);
      expect(_sources('סלמון קריספי'), ['ציפוי קריספי']);
    });

    test('an antipasto marinade of oil and herbs is not flagged', () {
      expect(_sources('Marinated olives'), isEmpty);
      expect(_sources('זיתים במרינדה'), isEmpty);
      expect(_sources('Marinated chicken skewers'), ['marinade']);
    });
  });

  group('ClassificationRules.match — covering', () {
    test('a carb modifier overlapping the trigger covers it', () {
      // Act
      final match = ClassificationRules.match('Steak with crispy onion');

      // Assert
      expect(match.instructions, [carbModifiersEn['crispy onion']]);
      expect(match.hiddenCarbs, isEmpty);
    });

    test('a sweetener within three words covers a sugar flag', () {
      expect(_sources('Chicken in honey marinade'), isEmpty);
      expect(_sources('Chicken marinated in honey'), isEmpty);
      expect(_sources('Chicken in honey and soy marinade'), isEmpty);
      expect(_sources('Teriyaki glazed salmon'), isEmpty);
      expect(_sources('BBQ rub ribs'), isEmpty);
      expect(_sources('סלמון מזוגג בדבש'), isEmpty);
      expect(_sources('עוף במרינדה של דבש וסויה'), isEmpty);
    });

    test('a sweetener four words away does not cover', () {
      expect(_sources('Honey, then lemon, soy, ginger marinade'), ['marinade']);
    });

    test('a sweetener never covers a flour or mixed flag', () {
      expect(_sources('Honey and gravy'), ['gravy']);
      expect(_sources('House sauce with honey'), ['house sauce']);
    });

    test('a carb modifier that is not a sweetener covers nothing', () {
      // Act
      final match = ClassificationRules.match('Crispy salmon with fries');

      // Assert
      expect(match.instructions, [carbModifiersEn['fries']]);
      expect(match.hiddenCarbs.map((flag) => flag.source), ['crispy coating']);
    });
  });

  group('ClassificationRules.match — overlap, dedupe and cap', () {
    test('the longer of two overlapping triggers wins', () {
      expect(_sources('Chicken in sweet marinade'), ['sweet marinade']);
      expect(_sources('עוף במרינדה מתוקה'), ['מרינדה מתוקה']);
    });

    test('two triggers with one source give one flag', () {
      expect(_sources('Marinade and marinated chicken'), ['marinade']);
    });

    test('at most three flags, in text order', () {
      // Act
      final match = ClassificationRules.match(
        'House sauce, special sauce, garlic sauce, amba and gravy',
      );

      // Assert
      expect(match.hiddenCarbs.map((flag) => flag.source), [
        'house sauce',
        'special sauce',
        'garlic sauce',
      ]);
    });

    test('a red base drops every flag', () {
      // Act
      final match = ClassificationRules.match('Spaghetti in house sauce');

      // Assert
      expect(match.isNonKeto, isTrue);
      expect(match.hiddenCarbs, isEmpty);
    });

    test('an astral letter before the window moves nothing', () {
      expect(
        _sources(
          '\u{1D401}\u{1D41E}\u{1D41E}\u{1D41F} with honey and soy marinade',
        ),
        isEmpty,
      );
      expect(
        _sources('\u{1D401}\u{1D41E}\u{1D41E}\u{1D41F} with house sauce'),
        ['house sauce'],
      );
    });
  });

  group('ClassificationRules.match — language', () {
    test('a Hebrew dish with an English trigger gets the Hebrew flag', () {
      // Act
      final match = ClassificationRules.match('סלמון with house sauce');

      // Assert
      expect(match.hiddenCarbs.single.source, 'רוטב הבית');
      expect(
        match.hiddenCarbs.single.waiterQuestion,
        'יש סוכר או קמח ברוטב הבית?',
      );
    });

    test('an English dish with no Hebrew gets the English flag', () {
      expect(
        ClassificationRules.match('Salmon in house sauce').hiddenCarbs.single,
        const HiddenCarb(
          source: 'house sauce',
          certainty: HiddenCarbCertainty.suspected,
          waiterQuestion: 'Is there sugar or flour in the house sauce?',
        ),
      );
    });
  });

  group('ClassificationRules.matchDish — hidden carbs', () {
    test('reads the description', () {
      // Act
      final match = ClassificationRules.matchDish(
        _dish('Grilled chicken', description: 'With our house sauce'),
      );

      // Assert
      expect(match.hiddenCarbs.single.source, 'house sauce');
    });

    test('reads a choice option value', () {
      // Act
      final match = ClassificationRules.matchDish(
        _dish(
          'Grilled chicken',
          options: const <DishOption>[
            DishOption(name: 'Sauce', values: <String>['Garlic sauce']),
          ],
        ),
      );

      // Assert
      expect(match.hiddenCarbs.single.source, 'garlic sauce');
    });

    test('drops a removal option value (#192)', () {
      // Act
      final english = ClassificationRules.matchDish(
        _dish(
          'Grilled chicken',
          options: const <DishOption>[
            DishOption(name: 'Changes', values: <String>['No house sauce']),
          ],
        ),
      );
      final hebrew = ClassificationRules.matchDish(
        _dish(
          'שיפודי פרגית',
          options: const <DishOption>[
            DishOption(name: 'שינויים', values: <String>['ללא עמבה']),
          ],
        ),
      );

      // Assert
      expect(english.hiddenCarbs, isEmpty);
      expect(hebrew.hiddenCarbs, isEmpty);
    });

    test('a red dish carries no flags', () {
      // Act
      final red = ClassificationRules.matchDish(
        _dish('Spaghetti', description: 'In house sauce'),
      );
      final carbOnly = ClassificationRules.matchDish(
        _dish('Fries', description: 'Crispy'),
      );

      // Assert
      expect(red.isNonKeto, isTrue);
      expect(red.hiddenCarbs, isEmpty);
      expect(carbOnly.isNonKeto, isTrue);
      expect(carbOnly.hiddenCarbs, isEmpty);
    });

    test('a yellow by option base keeps its flags', () {
      // Act
      final match = ClassificationRules.matchDish(
        _dish(
          'Steak',
          description: 'With gravy',
          options: const <DishOption>[
            DishOption(name: 'Side', values: <String>['Pasta', 'Salad']),
          ],
        ),
      );

      // Assert
      expect(match.isNonKeto, isFalse);
      expect(match.instructions, isNotEmpty);
      expect(match.hiddenCarbs.single.source, 'gravy');
    });

    test('a flag never adds to the instructions', () {
      // Act
      final match = ClassificationRules.matchDish(
        _dish('Grilled salmon', description: 'House sauce'),
      );

      // Assert
      expect(match.instructions, isEmpty);
      expect(match.hiddenCarbs, isNotEmpty);
    });
  });
}
