// The sensitivities' vocabulary (Banto, issue #342): nightshades, MSG,
// caffeine, salicylates and oral allergy syndrome, in English and Hebrew,
// with their prefix forms, their no-prefix traps and their guards, and a
// replay of their corpus menu, `sensitivities_labels.json`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/allergens/vocab_sensitivities.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';

// One expectation: `text` gives `id` a hit on `term` at certainty `c`.
typedef _Hit = (String text, RestrictionId id, String term, TriggerCertainty c);

/// A decoded JSON object.
typedef _Json = Map<String, Object?>;

const TriggerCertainty _stated = TriggerCertainty.stated;
const TriggerCertainty _likely = TriggerCertainty.likely;
const TriggerCertainty _suspected = TriggerCertainty.suspected;

const RestrictionId _nightshades = RestrictionId.nightshades;
const RestrictionId _msg = RestrictionId.msg;
const RestrictionId _caffeine = RestrictionId.caffeine;
const RestrictionId _salicylates = RestrictionId.salicylates;
const RestrictionId _oral = RestrictionId.oralAllergy;

const List<RestrictionId> _ids = <RestrictionId>[
  _nightshades,
  _msg,
  _caffeine,
  _salicylates,
  _oral,
];

/// The corpus menu labelled for these five restrictions.
const String _corpusPath =
    'test/fixtures/allergens/menus/sensitivities_labels.json';

/// Every hit [id] gets on [text].
List<AllergenHit> _hits(String text, RestrictionId id) =>
    AllergenMatcher.find(text)
        .where((hit) => hit.id == id)
        .toList(growable: false);

/// The certainty of [id]'s hit on [term] in [text], or null.
TriggerCertainty? _certaintyOf(String text, RestrictionId id, String term) {
  for (final hit in _hits(text, id)) {
    if (hit.term == term) return hit.certainty;
  }
  return null;
}

/// Whether [id]'s hits on [text] are all lowered by a guard, and there is
/// one (a guard lowers to suspected, never cancels; ALG-04a).
bool _lowered(String text, RestrictionId id) {
  final hits = _hits(text, id);
  return hits.isNotEmpty &&
      hits.every((hit) => hit.guarded && hit.certainty == _suspected);
}

/// Every term of [vocabulary] with its declared certainty and script.
List<({String term, TriggerCertainty certainty, bool hebrew})> _terms(
  RestrictionVocabulary vocabulary,
) => <({String term, TriggerCertainty certainty, bool hebrew})>[
  for (final term in vocabulary.directEn)
    (term: term, certainty: _stated, hebrew: false),
  for (final term in vocabulary.directHe)
    (term: term, certainty: _stated, hebrew: true),
  for (final t in vocabulary.hiddenEn)
    (term: t.term, certainty: t.certainty, hebrew: false),
  for (final t in vocabulary.hiddenHe)
    (term: t.term, certainty: t.certainty, hebrew: true),
];

/// The dishes of the corpus menu, as `Dish`es beside their labels.
List<({Dish dish, _Json labels})> _corpus() {
  final json = jsonDecode(File(_corpusPath).readAsStringSync()) as _Json;
  return <({Dish dish, _Json labels})>[
    for (final (index, raw)
        in (json['dishes']! as List<Object?>).cast<_Json>().indexed)
      (
        dish: Dish(
          id: 'sensitivities#$index',
          name: raw['name']! as String,
          description: raw['description']! as String,
          price: 0,
          options: const <DishOption>[],
        ),
        labels: raw['labels']! as _Json,
      ),
  ];
}

/// Whether the documentation file [file] (11 or 12) has the subsection
/// [section] (`29.1`) as a heading.
bool _hasSection(String file, String section) {
  final name = file == '11'
      ? '11_hidden_allergen_sources.md'
      : '12_israeli_and_us_menu_lexicon.md';
  final text = File('allergen app documentation/$name').readAsStringSync();
  return RegExp(
    '^### ${RegExp.escape(section)}[ ,]',
    multiLine: true,
  ).hasMatch(text);
}

/// Every corpus menu's dishes, as `name description` texts.
List<String> _allCorpusTexts() {
  final texts = <String>[];
  final files = Directory('test/fixtures/allergens/menus')
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'));
  for (final file in files) {
    final json = jsonDecode(file.readAsStringSync()) as _Json;
    for (final raw in (json['dishes']! as List<Object?>).cast<_Json>()) {
      final options = (raw['options']! as List<Object?>).cast<_Json>();
      texts.add(
        <Object?>[
          raw['name'],
          raw['description'],
          for (final option in options) ...(option['values']! as List<Object?>),
        ].join(' '),
      );
    }
  }
  return texts;
}

void main() {
  group('sensitivities vocabulary', () {
    test('covers the five research sensitivities, all heads-ups', () {
      expect(sensitivitiesVocabulary.keys.toSet(), _ids.toSet());
      expect(headsUpRestrictions, containsAll(_ids));
    });

    for (final id in _ids) {
      group(id.name, () {
        final vocabulary = allergenVocabulary[id]!;

        test('is filled in both languages and cites its sources', () {
          expect(vocabulary.isEmpty, isFalse);
          expect(vocabulary.hiddenEn, isNotEmpty);
          expect(vocabulary.hiddenHe, isNotEmpty);
          expect(vocabulary.sources, isNotEmpty);
          if (id != _salicylates) {
            expect(vocabulary.directEn, isNotEmpty);
            expect(vocabulary.directHe, isNotEmpty);
          }
        });

        test('every term is found when it stands alone, at its certainty', () {
          for (final entry in _terms(vocabulary)) {
            expect(
              _certaintyOf(entry.term, id, entry.term),
              entry.certainty,
              reason: entry.term,
            );
          }
        });

        test('every Hebrew term takes ב, ו and ה in front', () {
          final noPrefix = vocabulary.noPrefixHe.toSet();
          for (final entry in _terms(vocabulary)) {
            if (!entry.hebrew || noPrefix.contains(entry.term)) continue;
            for (final prefix in <String>['ב', 'ו', 'ה']) {
              expect(
                _hits('עם $prefix${entry.term}', id).map((hit) => hit.term),
                contains(entry.term),
                reason: '$prefix${entry.term}',
              );
            }
          }
        });

        test('every English term matches in capitals too', () {
          for (final entry in _terms(vocabulary)) {
            if (entry.hebrew) continue;
            expect(
              _certaintyOf(
                'Served with ${entry.term.toUpperCase()} today',
                id,
                entry.term,
              ),
              entry.certainty,
              reason: entry.term,
            );
          }
        });
      });
    }

    test('every source names a real heading of file 11 or 12', () {
      for (final id in _ids) {
        final vocabulary = allergenVocabulary[id]!;
        for (final source in <String>{
          ...vocabulary.sources,
          for (final t in vocabulary.hiddenEn) t.source,
          for (final t in vocabulary.hiddenHe) t.source,
        }) {
          final [file, section] = source.split(' §');
          expect(_hasSection(file, section), isTrue, reason: source);
        }
      }
    });

    test('salicylates are suspected only: the data are contested', () {
      final vocabulary = allergenVocabulary[_salicylates]!;
      expect(vocabulary.directEn, isEmpty);
      expect(vocabulary.directHe, isEmpty);
      for (final entry in _terms(vocabulary)) {
        expect(entry.certainty, _suspected, reason: entry.term);
      }
    });
  });

  group('hits', () {
    const cases = <_Hit>[
      ('Tomato soup', _nightshades, 'tomato', _stated),
      ('Roasted aubergine', _nightshades, 'aubergine', _stated),
      ('Chilli con carne', _nightshades, 'chilli', _stated),
      ('Smoked paprika chicken', _nightshades, 'paprika', _stated),
      ('Shakshuka', _nightshades, 'shakshuka', _likely),
      ('Burger and fries', _nightshades, 'fries', _likely),
      ('Pizza margherita', _nightshades, 'pizza', _suspected),
      (
        'Steak with green peppercorns and pepper',
        _nightshades,
        'pepper',
        _suspected,
      ),
      ('שקשוקה ביתית', _nightshades, 'שקשוקה', _likely),
      ('סלט עגבניות', _nightshades, 'עגבניות', _stated),
      ('חציל בטחינה', _nightshades, 'חציל', _stated),
      ('פלפלים קלויים', _nightshades, 'פלפלים', _stated),
      ('פירה תפו"א', _nightshades, 'תפו"א', _stated),
      ('חומוס עם סחוג', _nightshades, 'סחוג', _likely),
      ('Seasoned with MSG', _msg, 'msg', _stated),
      ('Contains E621', _msg, 'e621', _stated),
      ('Gravy from a stock cube', _msg, 'stock cube', _suspected),
      ('Contains flavour enhancer', _msg, 'flavour enhancer', _likely),
      ('מרק על בסיס אבקת מרק', _msg, 'אבקת מרק', _suspected),
      ('עם משפר טעם', _msg, 'משפר טעם', _likely),
      ('Double espresso', _caffeine, 'espresso', _stated),
      ('Iced matcha', _caffeine, 'matcha', _stated),
      ('Pot of tea', _caffeine, 'tea', _likely),
      ('Tiramisu', _caffeine, 'tiramisu', _likely),
      ('Dark chocolate mousse', _caffeine, 'chocolate', _suspected),
      ('קפה שחור', _caffeine, 'קפה', _stated),
      ('הפוך גדול', _caffeine, 'הפוך', _stated),
      ('תה ירוק', _caffeine, 'תה', _likely),
      ('קולה זירו', _caffeine, 'קולה', _stated),
      ('Chicken curry', _salicylates, 'curry', _suspected),
      ('Raspberry sorbet', _salicylates, 'raspberry', _suspected),
      ('לימונדה עם נענע', _salicylates, 'נענע', _suspected),
      ('Sliced apple', _oral, 'apple', _stated),
      ('Fresh peach', _oral, 'peach', _stated),
      ('Roasted almonds', _oral, 'almonds', _stated),
      ('Celery soup', _oral, 'celery', _stated),
      ('Fruit salad', _oral, 'fruit salad', _likely),
      ('סלט פירות', _oral, 'סלט פירות', _likely),
      ('בננה טרייה', _oral, 'בננה', _stated),
      ('אגוזי לוז קלויים', _oral, 'אגוזי לוז', _stated),
    ];
    for (final (text, id, term, certainty) in cases) {
      test('$text gives ${id.name} "$term" (${certainty.name})', () {
        expect(_certaintyOf(text, id, term), certainty);
      });
    }
  });

  group('no-prefix traps', () {
    const misses = <(String, RestrictionId)>[
      // "שתה" is "drank", "מתה" "dead", "כתה" a classroom and "שהתה"
      // "stayed": none of them is tea.
      ('הוא שתה מים', _caffeine),
      ('כתה א', _caffeine),
      ('היא שהתה שם', _caffeine),
      // "שקולה" is "balanced", "להפוך" "to flip": not cola, not a latte.
      ('ארוחה שקולה', _caffeine),
      ('אפשר להפוך את המנה', _caffeine),
      // "מגזר" is a sector, "במלון" "at the hotel".
      ('מגזר העסקים', _oral),
      ('ארוחת בוקר במלון', _oral),
      // "Peppercorn" and "peppermint" are not peppers; "colada" is not cola.
      ('Peppercorn sauce', _nightshades),
      ('Peppermint tea', _nightshades),
      ('Pina colada', _caffeine),
    ];
    for (final (text, id) in misses) {
      test('"$text" gives ${id.name} nothing', () {
        expect(_hits(text, id), isEmpty);
      });
    }
  });

  group('guards lower, never cancel', () {
    const lowered = <(String, RestrictionId)>[
      ('Sweet potato', _nightshades),
      ('Sweet potato fries', _nightshades),
      ('Black pepper', _nightshades),
      ('Salt and pepper', _nightshades),
      ('Pepper steak', _nightshades),
      ('Pizza bianca', _nightshades),
      ('Nightshade-free: no tomato', _nightshades),
      ('פלפל שחור', _nightshades),
      ('מלח ופלפל', _nightshades),
      ("צ'יפס בטטה", _nightshades),
      ('No MSG', _msg),
      ('MSG-free', _msg),
      ('No added MSG', _msg),
      ('ללא MSG', _msg),
      ('ללא תוספת מונוסודיום גלוטמט', _msg),
      ('Decaf latte', _caffeine),
      ('Coffee decaf', _caffeine),
      ('Coffee cake', _caffeine),
      ('Herbal tea', _caffeine),
      ('Turmeric latte', _caffeine),
      ('White chocolate', _caffeine),
      ('Caffeine-free', _caffeine),
      ('קפה נטול קפאין', _caffeine),
      ('תה צמחים', _caffeine),
      ('שוקולד לבן', _caffeine),
      ('No honey', _salicylates),
      ('Baked apple', _oral),
      ('Apple pie', _oral),
      ('Cherry tomatoes', _oral),
      ('Carrot cake', _oral),
      ('Grilled zucchini', _oral),
      ('גזר מבושל', _oral),
      ('ריבת דובדבנים', _oral),
      ('פאי תפוחים', _oral),
      ('תפוח אדמה', _oral),
      ('מלפפון חמוץ', _oral),
    ];
    for (final (text, id) in lowered) {
      test('"$text" lowers ${id.name} to a guarded suspicion', () {
        expect(_lowered(text, id), isTrue, reason: '${_hits(text, id)}');
      });
    }

    test('celery and nuts keep their hit when cooked: they may react', () {
      expect(_certaintyOf('Roasted hazelnuts', _oral, 'hazelnuts'), _stated);
      expect(_certaintyOf('Braised celery', _oral, 'celery'), _stated);
      expect(_certaintyOf('סלרי מבושל', _oral, 'סלרי'), _stated);
      expect(_certaintyOf('שקדים קלויים', _oral, 'שקדים'), _stated);
    });

    test('a potato beside "sweet" still names nothing else', () {
      expect(_certaintyOf('Baked potato', _nightshades, 'potato'), _stated);
    });
  });

  group('every concern is a heads-up that never moves a dish', () {
    final cases = <(RestrictionId, Dish)>[
      (_nightshades, _dish('Patatas bravas', 'potatoes, tomato sauce')),
      (_nightshades, _dish('שקשוקה', 'ביצים ברוטב עגבניות')),
      (_msg, _dish('Fried rice', 'with MSG')),
      (_caffeine, _dish('Espresso', '')),
      (_caffeine, _dish('קפה הפוך', '')),
      (_salicylates, _dish('Berry tart', 'raspberries and honey')),
      (_oral, _dish('Fruit salad', 'raw apple, kiwi, peach')),
      (_oral, _dish('סלט פירות', 'תפוח ואגס')),
    ];
    for (final (id, dish) in cases) {
      test('${id.name}: "${dish.name}" is suspected and still fits', () {
        // Arrange
        final profile = DietaryProfile.empty.withEntry(id);

        // Act
        final result = ProfileEvaluator.evaluate(
          AnalysedDish(
            dishId: dish.id,
            name: dish.name,
            verdict: DishVerdict.orderAsIs,
            why: 'Fits',
          ),
          dish,
          profile,
        );

        // Assert
        expect(result.state, DishState.fits);
        expect(result.modification, isNull);
        expect(result.concerns, isNotEmpty);
        for (final concern in result.concerns) {
          expect(concern.restrictionId, id);
          expect(concern.certainty, Certainty.suspected);
          expect(concern.waiterQuestion, endsWith('?'));
        }
      });
    }
  });

  group('the sensitivities corpus menu', () {
    final corpus = _corpus();

    test('labels every one of the five, with contains and free', () {
      for (final id in _ids) {
        final labels = <Object?>[
          for (final entry in corpus)
            (entry.labels[id.name] as _Json?)?['label'],
        ];
        expect(labels, contains('free'), reason: id.name);
        expect(
          labels.where(
            (label) => label == 'contains' || label == 'may_contain',
          ),
          isNotEmpty,
          reason: id.name,
        );
      }
    });

    test('every contains and may_contain label is found', () {
      final missed = <String>[];
      for (final entry in corpus) {
        final hits = AllergenMatcher.findInDish(entry.dish);
        for (final id in _ids) {
          final label = (entry.labels[id.name] as _Json?)?['label'];
          if (label != 'contains' && label != 'may_contain') continue;
          if (!hits.any((hit) => hit.id == id)) {
            missed.add('${id.name}: ${entry.dish.name}');
          }
        }
      }
      expect(missed, isEmpty);
    });

    test('a contains label is found unguarded', () {
      final lowered = <String>[];
      for (final entry in corpus) {
        final hits = AllergenMatcher.findInDish(entry.dish);
        for (final id in _ids) {
          final label = (entry.labels[id.name] as _Json?)?['label'];
          if (label != 'contains') continue;
          if (!hits.any((hit) => hit.id == id && !hit.guarded)) {
            lowered.add('${id.name}: ${entry.dish.name}');
          }
        }
      }
      expect(lowered, isEmpty);
    });

    test('a free label gets no hit, or only guarded ones', () {
      final flagged = <String>[];
      for (final entry in corpus) {
        final hits = AllergenMatcher.findInDish(entry.dish);
        for (final id in _ids) {
          final label = (entry.labels[id.name] as _Json?)?['label'];
          if (label != 'free') continue;
          final open = hits.where((hit) => hit.id == id && !hit.guarded);
          if (open.isNotEmpty) {
            flagged.add('${id.name}: ${entry.dish.name} $open');
          }
        }
      }
      expect(flagged, isEmpty, reason: flagged.join('\n'));
    });

    test('prints how many corpus dishes each sensitivity flags', () {
      // A heads-up never moves a dish, so a false alarm costs a line of
      // text, not a meal; the count is printed so a change that floods
      // every dish shows up in review.
      final texts = _allCorpusTexts();
      stdout.writeln(
        'sensitivities: dishes flagged of ${texts.length} corpus dishes',
      );
      for (final id in _ids) {
        var flagged = 0;
        var unguarded = 0;
        for (final text in texts) {
          final hits = _hits(text, id);
          if (hits.isNotEmpty) flagged++;
          if (hits.any((hit) => !hit.guarded)) unguarded++;
        }
        stdout.writeln(
          '  ${id.name.padRight(12)} ${'$flagged'.padLeft(4)} '
          '(unguarded ${'$unguarded'.padLeft(4)})',
        );
        expect(flagged, lessThan(texts.length), reason: id.name);
      }
    });
  });
}

/// A dish named [name] with [description].
Dish _dish(String name, String description) => Dish(
  id: 'd',
  name: name,
  description: description,
  price: 10,
  options: const <DishOption>[],
);
