import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/vocab_legume_parts.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';
import 'package:ketoclub/utils/allergens/waiter_questions.dart';
import 'package:ketoclub/utils/classification_rules.dart';
import 'package:ketoclub/utils/text_normaliser.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';

/// The restrictions `vocab_legume_parts.dart` owns.
const List<RestrictionId> _ids = <RestrictionId>[
  RestrictionId.chickpea,
  RestrictionId.lentil,
  RestrictionId.pea,
  RestrictionId.fenugreek,
  RestrictionId.fava,
];

/// The hits [AllergenMatcher.find] reports for [id] in [text], each as
/// `term:certainty`, `:guarded` appended when a guard lowered it.
List<String> _hits(String text, RestrictionId id) => <String>[
  for (final hit in AllergenMatcher.find(text))
    if (hit.id == id)
      '${hit.term}:${hit.certainty.name}${hit.guarded ? ':guarded' : ''}',
];

/// One expectation: `text` reports every entry of `has` for `id` and none
/// of the terms in `lacks`; with both empty it reports nothing at all.
typedef _Case = ({
  String text,
  RestrictionId id,
  List<String> has,
  List<String> lacks,
  bool guarded,
});

_Case _hit(String text, RestrictionId id, List<String> has) =>
    (text: text, id: id, has: has, lacks: const <String>[], guarded: false);

/// A text whose every hit of `id` a guard lowered to suspected.
_Case _lowered(String text, RestrictionId id, List<String> has) =>
    (text: text, id: id, has: has, lacks: const <String>[], guarded: true);

_Case _miss(
  String text,
  RestrictionId id, {
  List<String> lacks = const <String>[],
}) => (text: text, id: id, has: const <String>[], lacks: lacks, guarded: false);

void _run(List<_Case> cases) {
  for (final c in cases) {
    test('${c.id.name}: "${c.text}"', () {
      // Act
      final hits = _hits(c.text, c.id);

      // Assert
      for (final expected in c.has) {
        expect(hits, contains(expected));
      }
      if (c.has.isEmpty && c.lacks.isEmpty) expect(hits, isEmpty);
      if (c.guarded) {
        expect(hits, isNotEmpty);
        expect(hits.every((hit) => hit.endsWith(':guarded')), isTrue);
      }
      for (final term in c.lacks) {
        expect(hits.where((hit) => hit.startsWith('$term:')), isEmpty);
      }
    });
  }
}

/// [text] as a one-dish menu item.
Dish _dish(String text) => Dish(
  id: 'd',
  name: text,
  description: '',
  price: 0,
  options: const <DishOption>[],
);

/// Whether the allergen documentation has the section [citation] names,
/// such as `11 §28.1` (a `### 28.1` heading in file 11) or `12 §12` (a
/// `## 12.` heading in file 12).
bool _sectionExists(String citation) {
  final match = RegExp(r'^(1[12]) §(\d+(?:\.\d+)?)$').firstMatch(citation);
  if (match == null) return false;
  final name = match.group(1) == '11'
      ? '11_hidden_allergen_sources.md'
      : '12_israeli_and_us_menu_lexicon.md';
  final section = match.group(2)!;
  final text = File('allergen app documentation/$name').readAsStringSync();
  final heading = section.contains('.')
      ? RegExp('^### ${RegExp.escape(section)}[ ,]', multiLine: true)
      : RegExp('^## ${RegExp.escape(section)}\\. ', multiLine: true);
  return heading.hasMatch(text);
}

void main() {
  group('chickpea', () {
    _run(<_Case>[
      _hit('Chickpea salad', RestrictionId.chickpea, <String>[
        'chickpea:stated',
      ]),
      _hit('Hummus plate', RestrictionId.chickpea, <String>['hummus:stated']),
      _hit('Chana masala', RestrictionId.chickpea, <String>['chana:stated']),
      _hit('Chole bhature', RestrictionId.chickpea, <String>['chole:stated']),
      _hit('Fried in gram flour', RestrictionId.chickpea, <String>[
        'gram flour:stated',
      ]),
      _hit('Besan chilla', RestrictionId.chickpea, <String>['besan:stated']),
      _hit('Falafel wrap', RestrictionId.chickpea, <String>['falafel:likely']),
      _hit('Onion bhaji', RestrictionId.chickpea, <String>['bhaji:likely']),
      _hit('Vegetable pakoras', RestrictionId.chickpea, <String>[
        'pakoras:likely',
      ]),
      _hit('Aquafaba meringue', RestrictionId.chickpea, <String>[
        'aquafaba:likely',
      ]),
      _hit('Moroccan harira', RestrictionId.chickpea, <String>[
        'harira:likely',
      ]),
      _hit('Koshari bowl', RestrictionId.chickpea, <String>[
        'koshari:suspected',
      ]),
      _hit('חומוס עם טחינה', RestrictionId.chickpea, <String>['חומוס:stated']),
      _hit('גרגרי חומוס חמים', RestrictionId.chickpea, <String>[
        'גרגרי חומוס:stated',
      ]),
      _hit('מסבחה חמה', RestrictionId.chickpea, <String>['מסבחה:stated']),
      _hit('משאוושה', RestrictionId.chickpea, <String>['משאוושה:stated']),
      _hit('פלאפל בפיתה', RestrictionId.chickpea, <String>['פלאפל:likely']),
      _hit('סביח', RestrictionId.chickpea, <String>['סביח:suspected']),
      _lowered('Chickpea-free', RestrictionId.chickpea, <String>[
        'chickpea:suspected:guarded',
      ]),
      _lowered('ללא חומוס', RestrictionId.chickpea, <String>[
        'חומוס:suspected:guarded',
      ]),
      _miss('Green peas and lentils', RestrictionId.chickpea),
    ]);
  });

  group('lentil', () {
    _run(<_Case>[
      _hit('Red lentil soup', RestrictionId.lentil, <String>['lentil:stated']),
      _hit('Masoor dal', RestrictionId.lentil, <String>[
        'masoor:stated',
        'dal:likely',
      ]),
      _hit('Dhal of the day', RestrictionId.lentil, <String>['dhal:likely']),
      _hit('Mujadara', RestrictionId.lentil, <String>['mujadara:stated']),
      _hit('Mercimek corbasi', RestrictionId.lentil, <String>[
        'mercimek:stated',
      ]),
      _hit('Koshari bowl', RestrictionId.lentil, <String>['koshari:likely']),
      _hit('מרק עדשים', RestrictionId.lentil, <String>['עדשים:stated']),
      _hit("אורז מג'דרה", RestrictionId.lentil, <String>["מג'דרה:stated"]),
      _hit("מג'אדרה עם בצל", RestrictionId.lentil, <String>["מג'אדרה:stated"]),
      _lowered('No lentils', RestrictionId.lentil, <String>[
        'lentils:suspected:guarded',
      ]),
      _miss('Chickpea salad', RestrictionId.lentil),
    ]);
  });

  group('pea', () {
    _run(<_Case>[
      _hit('Green peas', RestrictionId.pea, <String>[
        'green peas:stated',
        'peas:stated',
      ]),
      _hit('Pea protein patty', RestrictionId.pea, <String>[
        'pea protein:stated',
      ]),
      _hit('Mushy peas', RestrictionId.pea, <String>['peas:stated']),
      _hit('Mangetout stir fry', RestrictionId.pea, <String>[
        'mangetout:stated',
      ]),
      _hit('Sugar snap salad', RestrictionId.pea, <String>[
        'sugar snap:stated',
      ]),
      _hit('Aloo matar', RestrictionId.pea, <String>['matar:stated']),
      _hit('Veggie burger', RestrictionId.pea, <String>[
        'veggie burger:suspected',
      ]),
      _hit('Beyond Meat burger', RestrictionId.pea, <String>[
        'beyond meat:suspected',
      ]),
      _hit('Vegetable samosas', RestrictionId.pea, <String>[
        'samosas:suspected',
      ]),
      _hit('Santorini fava', RestrictionId.pea, <String>[
        'santorini fava:likely',
      ]),
      _hit('אורז עם אפונה', RestrictionId.pea, <String>['אפונה:stated']),
      _hit('שניצל טבעוני', RestrictionId.pea, <String>[
        'שניצל טבעוני:suspected',
      ]),
      _miss('Chickpea curry', RestrictionId.pea),
      _miss('Peanut butter', RestrictionId.pea),
      _miss('Peach melba', RestrictionId.pea),
      _lowered('Hummus with chick peas', RestrictionId.pea, <String>[
        'peas:suspected:guarded',
      ]),
      _lowered('Black-eyed peas', RestrictionId.pea, <String>[
        'peas:suspected:guarded',
      ]),
      _lowered('Pea-free', RestrictionId.pea, <String>[
        'pea:suspected:guarded',
      ]),
    ]);
  });

  group('fenugreek', () {
    _run(<_Case>[
      _hit('Fenugreek bread', RestrictionId.fenugreek, <String>[
        'fenugreek:stated',
      ]),
      _hit('Methi malai paneer', RestrictionId.fenugreek, <String>[
        'methi:stated',
      ]),
      _hit('Hilbeh dip', RestrictionId.fenugreek, <String>['hilbeh:stated']),
      _hit('Panch phoron potatoes', RestrictionId.fenugreek, <String>[
        'panch phoron:likely',
      ]),
      _hit('Saltah', RestrictionId.fenugreek, <String>['saltah:likely']),
      _hit('Spiced with curry powder', RestrictionId.fenugreek, <String>[
        'curry powder:suspected',
      ]),
      _hit("ג'חנון עם חילבה", RestrictionId.fenugreek, <String>[
        'חילבה:stated',
      ]),
      _hit('גרגרנית יוונית', RestrictionId.fenugreek, <String>[
        'גרגרנית:stated',
      ]),
      _hit('מרק תימני', RestrictionId.fenugreek, <String>[
        'מרק תימני:suspected',
      ]),
      // Halva is sesame, not fenugreek (12 §1.1, §12.4).
      _miss('חלבה', RestrictionId.fenugreek),
      _miss('עוגת חלבה', RestrictionId.fenugreek),
      _miss('Green curry', RestrictionId.fenugreek),
      _lowered('בלי חילבה', RestrictionId.fenugreek, <String>[
        'חילבה:suspected:guarded',
      ]),
    ]);
  });

  group('fava', () {
    _run(<_Case>[
      _hit('Fava bean purée', RestrictionId.fava, <String>['fava:stated']),
      _hit('Broad beans and mint', RestrictionId.fava, <String>[
        'broad beans:stated',
      ]),
      _hit('Ful medames', RestrictionId.fava, <String>[
        'ful medames:stated',
        'ful:stated',
      ]),
      _hit('Foul mudammas', RestrictionId.fava, <String>[
        'foul mudammas:stated',
      ]),
      _hit("Ta'ameya", RestrictionId.fava, <String>["ta'ameya:likely"]),
      _hit('Bissara soup', RestrictionId.fava, <String>['bissara:likely']),
      _hit('Falafel wrap', RestrictionId.fava, <String>['falafel:suspected']),
      _hit('פול מדמס', RestrictionId.fava, <String>['פול:stated']),
      _hit('חומוס ופול', RestrictionId.fava, <String>['ופול:stated']),
      _hit('חומוס הפול', RestrictionId.fava, <String>['הפול:stated']),
      _hit('פולים ירוקים', RestrictionId.fava, <String>['פולים:stated']),
      _hit('פלאפל בפיתה', RestrictionId.fava, <String>['פלאפל:suspected']),
      // כפול is "double"; פולי is the construct of soybeans, coffee and
      // cocoa beans (12 §12.5).
      _miss('אספרסו כפול', RestrictionId.fava),
      _miss('שניצל כפול', RestrictionId.fava),
      _miss('פולי סויה', RestrictionId.fava),
      _miss('פולי קפה טחונים', RestrictionId.fava),
      _miss('Foul language', RestrictionId.fava),
      _miss('Customer fave', RestrictionId.fava),
      _lowered('Santorini fava', RestrictionId.fava, <String>[
        'fava:suspected:guarded',
      ]),
      _lowered('No fava beans', RestrictionId.fava, <String>[
        'fava:suspected:guarded',
        'fava beans:suspected:guarded',
      ]),
    ]);

    test('a falafel concern asks for fava beans, never "favism"', () {
      // Arrange
      final english = ClassificationRules.allergenConcerns(_dish('Falafel'));
      final hebrew = ClassificationRules.allergenConcerns(_dish('פלאפל'));

      // Act
      final en = WaiterQuestions.questionFor(
        english.singleWhere((c) => c.restrictionId == RestrictionId.fava),
        hebrew: false,
      );
      final he = WaiterQuestions.questionFor(
        hebrew.singleWhere((c) => c.restrictionId == RestrictionId.fava),
        hebrew: true,
      );

      // Assert
      expect(en, contains('fava beans'));
      expect(en, contains('Falafel'));
      expect(en.toLowerCase(), isNot(contains('favism')));
      expect(he, contains('פול'));
      expect(he, contains('פלאפל'));
      expect(he, isNot(contains('פביזם')));
    });
  });

  group('every term, in its own sentence', () {
    for (final id in _ids) {
      final vocabulary = allergenVocabulary[id]!;
      group(id.name, () {
        test('has direct triggers in both languages and guards', () {
          expect(vocabulary.directEn, isNotEmpty);
          expect(vocabulary.directHe, isNotEmpty);
          expect(vocabulary.hiddenEn, isNotEmpty);
          expect(vocabulary.sources, isNotEmpty);
          expect(vocabulary.guards.beforeEn, isNotEmpty);
          expect(vocabulary.guards.beforeHe, isNotEmpty);
        });

        test('every source names a section the documentation has', () {
          for (final source in <String>[
            ...vocabulary.sources,
            for (final trigger in vocabulary.hiddenEn) trigger.source,
            for (final trigger in vocabulary.hiddenHe) trigger.source,
          ]) {
            expect(_sectionExists(source), isTrue, reason: source);
          }
        });

        test('every direct English term is found, stated', () {
          for (final term in vocabulary.directEn) {
            for (final text in <String>[
              term,
              'Served with $term on the side',
              'Served with ${term.toUpperCase()} on the side',
            ]) {
              expect(_hits(text, id), contains('$term:stated'), reason: text);
            }
          }
        });

        test('every direct Hebrew term is found, stated, with prefixes', () {
          final noPrefix = vocabulary.noPrefixHe.toSet();
          for (final term in vocabulary.directHe) {
            expect(_hits(term, id), contains('$term:stated'), reason: term);
            expect(
              _hits('מוגש עם $term בצד', id),
              contains('$term:stated'),
              reason: term,
            );
            if (noPrefix.contains(term)) continue;
            for (final text in <String>['ה$term', 'וב$term']) {
              expect(
                _hits('מוגש עם $text בצד', id),
                contains('$term:stated'),
                reason: text,
              );
            }
          }
        });

        test('every hidden term is found with its own certainty', () {
          for (final trigger in vocabulary.hiddenEn) {
            expect(
              _hits('Served with ${trigger.term} on the side', id),
              contains('${trigger.term}:${trigger.certainty.name}'),
              reason: trigger.term,
            );
          }
          for (final trigger in vocabulary.hiddenHe) {
            final expected = '${trigger.term}:${trigger.certainty.name}';
            for (final text in <String>[
              'מוגש עם ${trigger.term} בצד',
              'מוגש עם ה${trigger.term} בצד',
            ]) {
              expect(_hits(text, id), contains(expected), reason: text);
            }
          }
        });

        test('a no-prefix Hebrew term is not found behind a prefix', () {
          for (final term in vocabulary.noPrefixHe) {
            for (final text in <String>['מוגש עם ל$term בצד', 'כ$term']) {
              expect(
                _hits(text, id).where((hit) => hit.startsWith('$term:')),
                isEmpty,
                reason: text,
              );
            }
          }
        });

        test('the guard words lower a trigger beside them', () {
          final guards = vocabulary.guards;
          final term = vocabulary.directEn.first;
          final he = vocabulary.directHe.first;
          void lowered(String text, String trigger) {
            final hits = _hits(
              text,
              id,
            ).where((hit) => hit.startsWith('$trigger:'));
            expect(hits, isNotEmpty, reason: text);
            expect(hits, everyElement('$trigger:suspected:guarded'));
          }

          for (final word in guards.beforeEn) {
            lowered('$word $term', term);
          }
          for (final word in guards.afterEn) {
            lowered('$term $word', term);
          }
          for (final word in guards.beforeHe) {
            lowered('$word $he', he);
          }
        });

        test('a guard three words away no longer lowers', () {
          final term = vocabulary.directEn.first;
          expect(_hits('no big fat $term', id), contains('$term:stated'));
        });
      });
    }
  });

  group('legumes is a superset of every single legume', () {
    String key(String term) => TextNormaliser.normalise(term);
    final legumes = allergenVocabulary[RestrictionId.legumes]!;
    final english = <String>{
      for (final term in legumes.directEn) key(term),
      for (final trigger in legumes.hiddenEn) key(trigger.term),
    };
    final hebrew = <String>{
      for (final term in legumes.directHe) key(term),
      for (final trigger in legumes.hiddenHe) key(trigger.term),
    };

    for (final id in _ids) {
      test('every ${id.name} term is a legumes term', () {
        final vocabulary = allergenVocabulary[id]!;
        for (final term in <String>[
          ...vocabulary.directEn,
          for (final trigger in vocabulary.hiddenEn) trigger.term,
        ]) {
          expect(english, contains(key(term)), reason: term);
        }
        for (final term in <String>[
          ...vocabulary.directHe,
          for (final trigger in vocabulary.hiddenHe) trigger.term,
        ]) {
          expect(hebrew, contains(key(term)), reason: term);
        }
      });
    }

    test('legumes keeps its guards and its fava no-prefix rule', () {
      expect(identical(legumes.guards, legumeGuards), isTrue);
      expect(legumes.noPrefixHe, contains('פול'));
      expect(allergenVocabulary[RestrictionId.fava]!.noPrefixHe, <String>[
        'פול',
      ]);
    });

    test('every single legume is offered in the picker now', () {
      for (final id in _ids) {
        expect(restrictionOffered(id), isTrue, reason: id.name);
      }
    });
  });
}
