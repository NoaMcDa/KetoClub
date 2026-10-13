import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// A vocabulary citation: file 11 or 12 of the allergen documentation and
/// a section (`"11 §11"`, `"12 §1.1"`), or file 02.
final RegExp _citation = RegExp(r'^(1[12] §\d+(\.\d+)?|02 §)');

/// A Hebrew letter.
final RegExp _hebrew = RegExp('[א-ת]');

/// Every term in [vocabulary], direct and hidden, Hebrew or English.
Iterable<String> _hebrewTerms(RestrictionVocabulary vocabulary) => <String>[
  ...vocabulary.directHe,
  for (final trigger in vocabulary.hiddenHe) trigger.term,
];

Iterable<String> _englishTerms(RestrictionVocabulary vocabulary) => <String>[
  ...vocabulary.directEn,
  for (final trigger in vocabulary.hiddenEn) trigger.term,
];

void main() {
  group('allergenVocabulary', () {
    test('the six groups cover every id exactly once', () {
      // Act
      final owners = <RestrictionId, List<String>>{};
      for (final MapEntry(key: file, value: group)
          in allergenVocabularyGroups.entries) {
        for (final id in group.keys) {
          (owners[id] ??= <String>[]).add(file);
        }
      }

      // Assert
      expect(owners.keys.toSet(), RestrictionId.values.toSet());
      for (final MapEntry(key: id, value: files) in owners.entries) {
        expect(files, hasLength(1), reason: '${id.name}: $files');
      }
    });

    test('the registry is the union of the six groups', () {
      // Act
      final union = <RestrictionId, RestrictionVocabulary>{
        for (final group in allergenVocabularyGroups.values) ...group,
      };

      // Assert
      expect(allergenVocabulary.keys.toSet(), RestrictionId.values.toSet());
      for (final id in RestrictionId.values) {
        expect(identical(allergenVocabulary[id], union[id]), isTrue);
      }
    });

    test('keto stays empty: its vocabulary lives in constants.dart', () {
      expect(allergenVocabulary[RestrictionId.keto]!.isEmpty, isTrue);
    });

    for (final id in RestrictionId.values) {
      group(id.name, () {
        final vocabulary = allergenVocabulary[id]!;

        test('every source cites file 11, 12 or 02', () {
          for (final source in <String>[
            ...vocabulary.sources,
            for (final trigger in vocabulary.hiddenEn) trigger.source,
            for (final trigger in vocabulary.hiddenHe) trigger.source,
          ]) {
            expect(source, matches(_citation));
          }
        });

        test('a vocabulary with triggers cites at least one source', () {
          final hasDirect =
              vocabulary.directEn.isNotEmpty || vocabulary.directHe.isNotEmpty;
          if (hasDirect) expect(vocabulary.sources, isNotEmpty);
        });

        test('no hidden trigger claims to be stated', () {
          for (final trigger in <HiddenTrigger>[
            ...vocabulary.hiddenEn,
            ...vocabulary.hiddenHe,
          ]) {
            expect(
              trigger.certainty,
              isNot(TriggerCertainty.stated),
              reason: trigger.term,
            );
          }
        });

        test('every term normalises to something, in its own script', () {
          for (final term in _englishTerms(vocabulary)) {
            final normalised = TextNormaliser.normalise(term);
            expect(normalised, isNotEmpty, reason: term);
            expect(_hebrew.hasMatch(normalised), isFalse, reason: term);
          }
          for (final term in _hebrewTerms(vocabulary)) {
            expect(_hebrew.hasMatch(TextNormaliser.normalise(term)), isTrue);
          }
        });

        test('no term is listed twice in one language', () {
          final english = _englishTerms(vocabulary).toList();
          final hebrew = _hebrewTerms(vocabulary).toList();
          expect(english.toSet(), hasLength(english.length));
          expect(hebrew.toSet(), hasLength(hebrew.length));
        });

        test('every no-prefix term is one of its Hebrew terms', () {
          final hebrew = _hebrewTerms(vocabulary).toSet();
          for (final term in vocabulary.noPrefixHe) {
            expect(hebrew, contains(term));
          }
        });

        test('every guard phrase normalises to something', () {
          for (final guards in <AllergenGuards>[
            vocabulary.guards,
            ...vocabulary.termGuards.values,
          ]) {
            for (final phrase in <String>[
              ...guards.beforeEn,
              ...guards.afterEn,
              ...guards.beforeHe,
              ...guards.afterHe,
            ]) {
              expect(TextNormaliser.normalise(phrase), isNotEmpty);
            }
          }
        });

        test('every term guard names one of its terms, in its language', () {
          final english = _englishTerms(vocabulary).toSet();
          final hebrew = _hebrewTerms(vocabulary).toSet();
          for (final MapEntry(key: term, value: guards)
              in vocabulary.termGuards.entries) {
            expect(english.union(hebrew), contains(term));
            if (english.contains(term)) {
              expect(guards.beforeHe, isEmpty, reason: term);
              expect(guards.afterHe, isEmpty, reason: term);
            } else {
              expect(guards.beforeEn, isEmpty, reason: term);
              expect(guards.afterEn, isEmpty, reason: term);
            }
          }
        });
      });
    }
  });

  group('RestrictionVocabulary', () {
    test('empty has no triggers, guards or sources', () {
      // Arrange
      const empty = RestrictionVocabulary.empty;

      // Assert
      expect(empty.isEmpty, isTrue);
      expect(empty.guards.beforeEn, isEmpty);
      expect(empty.guards.afterHe, isEmpty);
      expect(empty.termGuards, isEmpty);
      expect(empty.noPrefixHe, isEmpty);
      expect(empty.sources, isEmpty);
    });

    test('isEmpty is false once any trigger list holds a term', () {
      expect(
        const RestrictionVocabulary(directHe: <String>['שומשום']).isEmpty,
        isFalse,
      );
      expect(
        const RestrictionVocabulary(
          hiddenEn: <HiddenTrigger>[
            HiddenTrigger(
              term: 'pesto',
              certainty: TriggerCertainty.likely,
              source: '11 §2.2',
            ),
          ],
        ).isEmpty,
        isFalse,
      );
    });
  });

  group('HiddenTrigger', () {
    const pesto = HiddenTrigger(
      term: 'pesto',
      certainty: TriggerCertainty.likely,
      source: '11 §2.2',
    );

    test('equal values are equal and hash alike', () {
      // Arrange
      const same = HiddenTrigger(
        term: 'pesto',
        certainty: TriggerCertainty.likely,
        source: '11 §2.2',
      );

      // Assert
      expect(same, pesto);
      expect(same.hashCode, pesto.hashCode);
      expect(
        pesto,
        isNot(
          const HiddenTrigger(
            term: 'pesto',
            certainty: TriggerCertainty.suspected,
            source: '11 §2.2',
          ),
        ),
      );
    });

    test('toString names the term and the certainty', () {
      expect(pesto.toString(), 'HiddenTrigger(pesto, likely)');
    });
  });

  group('TriggerCertainty', () {
    test('has stated, likely and suspected, in that order', () {
      expect(TriggerCertainty.values.map((c) => c.name).toList(), <String>[
        'stated',
        'likely',
        'suspected',
      ]);
    });

    test('tryParse reads by name and rejects anything else', () {
      for (final certainty in TriggerCertainty.values) {
        expect(TriggerCertainty.tryParse(certainty.name), certainty);
      }
      expect(TriggerCertainty.tryParse('certain'), isNull);
    });
  });
}
