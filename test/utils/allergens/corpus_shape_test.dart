// The shape check for the allergen safety corpus (ALG-10, issue #352).
//
// `test/fixtures/allergens/menus/*.json` holds labelled menus that a later
// test replays to measure the engine's recall per restriction. This file
// asserts *shape and bookkeeping* only: required keys, enum values, the
// size of the corpus, that every label names its evidence and cites a real
// section of the desk-research documents, and that the labels agree with
// one another (a gluten label is at least its wheat label). It says
// nothing about whether a label is right; the labels are unreviewed desk
// research (see `test/fixtures/allergens/README.md`).

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

/// The directory every corpus menu lives in.
const String _menusDir = 'test/fixtures/allergens/menus';

/// A decoded JSON object.
typedef _Json = Map<String, Object?>;

// TODO(ALG-01a): switch to RestrictionId.values once merged
/// The restriction ids a label may be keyed by, spelled exactly as the
/// `RestrictionId` enum will spell them.
const List<String> _restrictionIds = <String>[
  'peanuts',
  'treeNuts',
  'milk',
  'lactose',
  'eggs',
  'soy',
  'wheat',
  'gluten',
  'fish',
  'crustaceans',
  'molluscs',
  'sesame',
  'celery',
  'mustard',
  'lupin',
  'sulphites',
  'legumes',
  'alphaGal',
  'fodmap',
  'histamine',
  'vegan',
  'vegetarian',
  'glp1',
  'kosher',
  'halal',
  'buckwheat',
  'kiwi',
  'peach',
  'apple',
  'banana',
  'orange',
  'beef',
  'pork',
  'chicken',
  'gelatin',
  'yam',
  'corn',
  'sunflower',
  'flax',
  'chickpea',
  'lentil',
  'pea',
  'fenugreek',
  'fava',
  'nightshades',
  'msg',
  'caffeine',
  'salicylates',
  'oralAllergy',
  'pescatarian',
  'paleo',
  'whole30',
  'aip',
  'jain',
  'keto',
];

/// Restrictions that are not strict: the intolerances, the diets, kosher
/// and halal (issue #342) and keto. A `contains` label on any other id
/// must name the role of its trigger.
const Set<String> _flexibleIds = <String>{
  'lactose',
  'fodmap',
  'histamine',
  'vegan',
  'vegetarian',
  'glp1',
  'kosher',
  'halal',
  'nightshades',
  'msg',
  'caffeine',
  'salicylates',
  'oralAllergy',
  'pescatarian',
  'paleo',
  'whole30',
  'aip',
  'jain',
  'keto',
};

/// The strict research restrictions (issue #342) whose vocabularies are
/// still empty, so the corpus carries no labels for them yet and the
/// "three contains labels" floor does not apply. Each vocabulary
/// follow-up adds its labels and removes its ids from this set.
const Set<String> _awaitingLabels = <String>{
  'corn',
  'sunflower',
  'flax',
  'chickpea',
  'lentil',
  'pea',
  'fenugreek',
  'fava',
};

/// The values of a label's `label` key.
const Set<String> _labelValues = <String>{'contains', 'may_contain', 'free'};

/// The values of a label's `role` key.
const Set<String> _roleValues = <String>{
  'base',
  'protein',
  'side',
  'sauce',
  'garnish',
  'option',
  'hidden',
  'unknown',
};

/// The values of a menu's `language` key.
const Set<String> _languageValues = <String>{'he', 'en', 'mixed'};

/// A citation of a section of documentation file 11 or 12, such as
/// `11 §11` or `12 §1.1`.
final RegExp _sourcePattern = RegExp(r'^1[12] §\d+(\.\d+)?$');

/// Words by which a restaurant declares a dish vegan or egg-free, matched
/// against the dish text in lower case.
const List<String> _veganDeclarations = <String>[
  'טבעוני',
  'vegan',
  'צמחוני',
  'ללא ביצה',
];

/// A Hebrew letter, the heuristic that makes a dish a Hebrew dish.
final RegExp _hebrewLetter = RegExp('[א-ת]');

/// The sections of `11_hidden_allergen_sources.md` and
/// `12_israeli_and_us_menu_lexicon.md` a label may cite. A citation of a
/// section that does not exist fails the test.
final Set<String> _validSources = _buildValidSources();

Set<String> _buildValidSources() {
  final out = <String>{'11 §0', '11 §18', '11 §19', '11 §20'};
  for (var s = 1; s <= 17; s++) {
    out.add('11 §$s');
    for (var k = 1; k <= 5; k++) {
      out.add('11 §$s.$k');
    }
  }
  for (var k = 1; k <= 4; k++) {
    out.add('11 §19.$k');
  }
  // Kosher (§24, eight subsections) and halal (§25, six), issue #342.
  // Buckwheat and Japan's recommended foods (§26, eleven).
  const research = <int, int>{24: 8, 25: 6, 26: 11};
  research.forEach((section, count) {
    out.add('11 §$section');
    for (var k = 1; k <= count; k++) {
      out.add('11 §$section.$k');
    }
  });
  // Documentation file 12: section 1 has 11 subsections, 2 has two, 3 has
  // five, 4 has four, 5 has none and 6 is a numbered list of five.
  // Section 9 (issue #342) has five: the Hebrew kosher and halal terms;
  // section 10 twelve: buckwheat and Japan's recommended foods.
  const subsections = <int, int>{
    1: 11,
    2: 2,
    3: 5,
    4: 4,
    5: 0,
    6: 5,
    9: 5,
    10: 12,
  };
  subsections.forEach((section, count) {
    out.add('12 §$section');
    for (var k = 1; k <= count; k++) {
      out.add('12 §$section.$k');
    }
  });
  return out;
}

/// A corpus file: its name and decoded JSON.
class _Menu {
  new(this.name, this.json);

  final String name;
  final _Json json;

  List<_Json> get dishes => (json['dishes']! as List<Object?>).cast<_Json>();
}

/// Every `*.json` in the menus directory, sorted by name.
List<_Menu> _loadMenus() {
  final files =
      Directory(_menusDir)
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return <_Menu>[
    for (final file in files)
      _Menu(
        file.uri.pathSegments.last,
        jsonDecode(file.readAsStringSync()) as _Json,
      ),
  ];
}

/// Decodes the JSON file at [path].
_Json _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as _Json;

/// Whether [dish] reads as Hebrew: a Hebrew letter in its name or
/// description.
bool _isHebrew(_Json dish) {
  final text = '${dish['name']} ${dish['description']}';
  return _hebrewLetter.hasMatch(text);
}

/// The labels of [dish], keyed by restriction id.
_Json _labelsOf(_Json dish) => dish['labels']! as _Json;

/// The strength of [id] on [dish]: absent and free are 0, may_contain is 1
/// and contains is 2.
int _rank(_Json dish, String id) {
  final label = _labelsOf(dish)[id];
  if (label == null) {
    return 0;
  }
  return switch ((label as _Json)['label']) {
    'contains' => 2,
    'may_contain' => 1,
    _ => 0,
  };
}

/// Every way [dish] of [menu] breaks the schema, as readable lines.
List<String> _dishProblems(String menu, int index, _Json dish) {
  final where = '$menu dish #$index (${dish['name']})';
  final problems = <String>[];
  const keys = <String>{'name', 'description', 'options', 'labels'};
  if (dish.keys.toSet().difference(keys).isNotEmpty ||
      keys.difference(dish.keys.toSet()).isNotEmpty) {
    problems.add('$where: keys must be exactly $keys, got ${dish.keys}');
    return problems;
  }
  final name = dish['name'];
  if (name is! String || name.trim().isEmpty) {
    problems.add('$where: name must be a non-empty string');
  }
  if (dish['description'] is! String) {
    problems.add('$where: description must be a string');
  }
  final options = dish['options'];
  if (options is! List<Object?>) {
    problems.add('$where: options must be a list');
  } else {
    for (final option in options) {
      if (option is! _Json ||
          option['name'] is! String ||
          option['values'] is! List<Object?> ||
          (option['values']! as List<Object?>).any(
            (value) => value is! String,
          )) {
        problems.add('$where: an option must be {name, values: [string]}');
      }
    }
  }
  final labels = dish['labels'];
  if (labels is! _Json) {
    problems.add('$where: labels must be an object');
    return problems;
  }
  for (final entry in labels.entries) {
    problems.addAll(_labelProblems(where, entry.key, entry.value));
  }
  return problems;
}

/// Every way the label [value] for restriction [id] breaks the schema.
List<String> _labelProblems(String where, String id, Object? value) {
  final at = '$where, label "$id"';
  if (!_restrictionIds.contains(id)) {
    return <String>['$at: unknown restriction id'];
  }
  if (id == 'keto') {
    return <String>['$at: keto is never labelled in this corpus'];
  }
  if (value is! _Json) {
    return <String>['$at: must be an object'];
  }
  final problems = <String>[];
  const keys = <String>{'label', 'role', 'evidence', 'source'};
  final extra = value.keys.toSet().difference(keys);
  if (extra.isNotEmpty) {
    problems.add('$at: unknown keys $extra');
  }
  final label = value['label'];
  if (!_labelValues.contains(label)) {
    problems.add('$at: label must be one of $_labelValues, got $label');
  }
  final role = value['role'];
  if (role != null && !_roleValues.contains(role)) {
    problems.add('$at: role must be one of $_roleValues, got $role');
  }
  if (label == 'free' && role != null) {
    problems.add('$at: a free label names no trigger, so it has no role');
  }
  if (label != 'free' && role == null && !_flexibleIds.contains(id)) {
    problems.add('$at: a $label label on a strict restriction needs a role');
  }
  final evidence = value['evidence'];
  if (evidence is! String || evidence.trim().isEmpty) {
    problems.add('$at: evidence must be a non-empty string');
  } else if (label == 'free' && !_flexibleIds.contains(id)) {
    // C8: a free label is never "safe"; it states its limit.
    final lower = evidence.toLowerCase();
    if (!lower.contains('cross-contact') && !lower.contains('guard')) {
      problems.add(
        '$at: a free label on a strict restriction must say '
        '"cross-contact" is not assessed or name the guard',
      );
    }
  }
  final source = value['source'];
  if (source is! String || !_sourcePattern.hasMatch(source)) {
    problems.add(
      '$at: source must match ${_sourcePattern.pattern}, got $source',
    );
  } else if (!_validSources.contains(source)) {
    problems.add('$at: source cites a section that does not exist: $source');
  }
  return problems;
}

/// Every way the labels of [dish] disagree with one another.
///
/// The families are: gluten covers wheat (and takes its role); legumes
/// cover peanut, soy and lupin; milk covers lactose; vegetarian covers
/// fish, crustaceans and molluscs; vegan covers eggs, fish, crustaceans,
/// molluscs, vegetarian and milk. The exceptions, all for the flexible
/// diet labels: an egg or milk label whose evidence starts with `guard:`,
/// an explicit vegan `free` beside the restaurant's own vegan declaration
/// (`_veganDeclarations` in the dish text), and a substitute-product milk
/// `may_contain` (12 §2.1) beside an explicit vegan `free`.
List<String> _consistencyProblems(String menu, int index, _Json dish) {
  final where = '$menu dish #$index (${dish['name']})';
  final problems = <String>[];
  int r(String id) => _rank(dish, id);
  _Json? l(String id) => _labelsOf(dish)[id] as _Json?;

  if (r('gluten') < r('wheat')) {
    problems.add('$where: gluten must be at least wheat');
  }
  if (r('wheat') >= 1 && l('gluten')?['role'] != l('wheat')?['role']) {
    problems.add('$where: gluten must have the role of wheat');
  }
  if (r('legumes') < [r('peanuts'), r('soy'), r('lupin')].reduce(max)) {
    problems.add('$where: legumes must be at least peanuts, soy and lupin');
  }
  if (r('milk') < r('lactose')) {
    problems.add('$where: milk must be at least lactose');
  }
  final fishes = [r('fish'), r('crustaceans'), r('molluscs')].reduce(max);
  if (r('vegetarian') < fishes) {
    problems.add('$where: vegetarian must be at least fish and shellfish');
  }
  final vegan = l('vegan');
  final veganFree = vegan != null && vegan['label'] == 'free';
  final text = [
    dish['name'],
    dish['description'],
    for (final option in (dish['options']! as List<Object?>).cast<_Json>())
      ...(option['values']! as List<Object?>),
  ].join(' ').toLowerCase();
  final declared = _veganDeclarations.any(text.contains);
  // A strict allergen label that only a guard lowered, or one kept for the
  // allergy beside a restaurant's own vegan declaration, does not pull a
  // flexible diet label up: the declaration is the evidence a vegan user
  // wants.
  bool excluded(String id) {
    final label = l(id);
    if (label == null) {
      return false;
    }
    if ((label['evidence']! as String).startsWith('guard:')) {
      return true;
    }
    if (veganFree && declared) {
      return true;
    }
    return veganFree &&
        id == 'milk' &&
        label['label'] == 'may_contain' &&
        label['source'] == '12 §2.1';
  }

  final needed = [
    if (!excluded('eggs')) r('eggs'),
    fishes,
    r('vegetarian'),
    if (!excluded('milk')) r('milk'),
  ].reduce(max);
  if (r('vegan') < needed) {
    problems.add('$where: vegan must cover animal ingredients and milk');
  }
  return problems;
}

/// Expects the Wolt corpus menu to carry the text of the source fixture:
/// one dish per item, with its name, description and options.
void _expectWoltTextMatches(_Menu menu) {
  final source = _readJson('test/fixtures/wolt_hamosad_menu.json');
  final groups = <String, _Json>{
    for (final group in (source['options']! as List<Object?>).cast<_Json>())
      group['id']! as String: group,
  };
  final items = (source['items']! as List<Object?>).cast<_Json>();
  expect(menu.dishes.length, items.length, reason: 'one dish per item');
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final dish = menu.dishes[i];
    expect(dish['name'], item['name'], reason: 'item #$i name');
    expect(
      dish['description'],
      (item['description'] as String?) ?? '',
      reason: 'item #$i description',
    );
    final options = <_Json>[
      for (final option
          in ((item['options'] as List<Object?>?) ?? const <Object?>[])
              .cast<_Json>())
        if (groups[option['option_id']] != null)
          <String, Object?>{
            'name': groups[option['option_id']]!['name'],
            'values': <Object?>[
              for (final value
                  in (groups[option['option_id']]!['values']! as List<Object?>)
                      .cast<_Json>())
                value['name'],
            ],
          },
    ];
    expect(dish['options'], equals(options), reason: 'item #$i options');
  }
}

/// The text of the 10bis synthetic menu's distinct dishes, as the corpus
/// must carry it (the repeated "1002-shared" listing is dropped).
void _expectTenbisTextMatches(_Menu menu) {
  final source = _readJson('test/fixtures/tenbis_synthetic_menu.json');
  final seen = <String>{};
  final expected = <_Json>[];
  for (final category
      in (source['categoriesList']! as List<Object?>).cast<_Json>()) {
    for (final dish in (category['dishList']! as List<Object?>).cast<_Json>()) {
      if (!seen.add('${dish['dishId']}')) {
        continue;
      }
      expected.add(<String, Object?>{
        'name': dish['dishName'],
        'description': (dish['dishDescription'] as String?) ?? '',
        'options': <Object?>[
          for (final option
              in ((dish['dishOptionsList'] as List<Object?>?) ??
                      const <Object?>[])
                  .cast<_Json>())
            <String, Object?>{
              'name': option['name'],
              'values': <Object?>[
                for (final value
                    in (option['values']! as List<Object?>).cast<_Json>())
                  value['name'],
              ],
            },
        ],
      });
    }
  }
  expect(menu.dishes.length, expected.length);
  for (var i = 0; i < expected.length; i++) {
    for (final key in const <String>['name', 'description', 'options']) {
      expect(
        menu.dishes[i][key],
        equals(expected[i][key]),
        reason: 'dish #$i $key',
      );
    }
  }
}

void main() {
  final menus = _loadMenus();
  final dishes = <_Json>[for (final menu in menus) ...menu.dishes];

  group('allergen corpus size', () {
    test('has at least 15 menus', () {
      expect(menus.length, greaterThanOrEqualTo(15));
    });

    test('has at least 300 labelled dishes', () {
      expect(dishes.length, greaterThanOrEqualTo(300));
    });

    test('is at least half Hebrew by dish', () {
      final hebrew = dishes.where(_isHebrew).length;
      expect(
        hebrew / dishes.length,
        greaterThanOrEqualTo(0.5),
        reason: '$hebrew of ${dishes.length} dishes carry a Hebrew letter',
      );
    });

    test('has at least three contains labels per strict restriction', () {
      // The n behind every recall figure: print it so a later gate never
      // reports a rate without its denominator.
      stdout
        ..writeln('allergen corpus: n per restriction')
        ..writeln('  ${'restriction'.padRight(12)} contains  free');
      final short = <String>[];
      for (final id in _restrictionIds.where((id) => id != 'keto')) {
        var contains = 0;
        var free = 0;
        for (final dish in dishes) {
          final label = _labelsOf(dish)[id] as _Json?;
          if (label == null) {
            continue;
          }
          if (label['label'] == 'contains') {
            contains++;
          } else if (label['label'] == 'free') {
            free++;
          }
        }
        stdout.writeln(
          '  ${id.padRight(12)} ${'$contains'.padLeft(8)}  '
          '${'$free'.padLeft(4)}',
        );
        if (!_flexibleIds.contains(id) &&
            !_awaitingLabels.contains(id) &&
            contains < 3) {
          short.add('$id has $contains');
        }
      }
      expect(short, isEmpty, reason: 'needs at least 3 contains each');
    });

    test('carries explicit free labels for false-positive measurement', () {
      final free = dishes
          .expand((dish) => _labelsOf(dish).values.cast<_Json>())
          .where((label) => label['label'] == 'free')
          .length;
      expect(free, greaterThanOrEqualTo(dishes.length ~/ 4));
    });
  });

  group('allergen corpus schema', () {
    test('finds the menus directory', () {
      expect(Directory(_menusDir).existsSync(), isTrue);
    });

    for (final menu in menus) {
      test('${menu.name} has the menu keys', () {
        expect(menu.json.keys.toSet(), <String>{
          '_fixture_note',
          'language',
          'dishes',
        });
        final note = menu.json['_fixture_note'];
        expect(note, isA<String>());
        expect((note! as String).trim(), isNotEmpty);
        expect(_languageValues, contains(menu.json['language']));
        expect(menu.json['dishes'], isA<List<Object?>>());
        expect(menu.dishes, isNotEmpty);
      });

      test('${menu.name} labels every dish well-formed', () {
        final problems = <String>[
          for (var i = 0; i < menu.dishes.length; i++)
            ..._dishProblems(menu.name, i, menu.dishes[i]),
        ];
        expect(problems, isEmpty, reason: problems.join('\n'));
      });

      test('${menu.name} labels agree with one another', () {
        final problems = <String>[
          for (var i = 0; i < menu.dishes.length; i++)
            ..._consistencyProblems(menu.name, i, menu.dishes[i]),
        ];
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    }
  });

  group('allergen corpus labels', () {
    test('every contains label on a strict restriction names a role', () {
      final missing = <String>[];
      for (final menu in menus) {
        for (final dish in menu.dishes) {
          for (final entry in _labelsOf(dish).entries) {
            final label = entry.value! as _Json;
            if (label['label'] == 'contains' &&
                !_flexibleIds.contains(entry.key) &&
                (label['role'] is! String ||
                    !_roleValues.contains(label['role']))) {
              missing.add('${menu.name}: ${dish['name']} / ${entry.key}');
            }
          }
        }
      }
      expect(missing, isEmpty);
    });

    test('every label has evidence and a citation of a real section', () {
      final bad = <String>[];
      for (final menu in menus) {
        for (final dish in menu.dishes) {
          for (final entry in _labelsOf(dish).entries) {
            final label = entry.value! as _Json;
            final evidence = label['evidence'];
            final source = label['source'];
            if (evidence is! String ||
                evidence.trim().isEmpty ||
                source is! String ||
                !_validSources.contains(source)) {
              bad.add('${menu.name}: ${dish['name']} / ${entry.key}');
            }
          }
        }
      }
      expect(bad, isEmpty);
    });
  });

  group('allergen corpus copies', () {
    test('wolt_hamosad.json carries the text of the source fixture', () {
      _expectWoltTextMatches(
        menus.firstWhere((m) => m.name.startsWith('wolt')),
      );
    });

    test('tenbis_synthetic.json carries the text of the source fixture', () {
      _expectTenbisTextMatches(
        menus.firstWhere((m) => m.name.startsWith('tenbis')),
      );
    });
  });

  group('allergen corpus README', () {
    final readme = File('test/fixtures/allergens/README.md').readAsStringSync();

    test('says the labels are unreviewed desk research', () {
      final lower = readme.toLowerCase();
      expect(lower, contains('unreviewed'));
      expect(lower, contains('desk research'));
    });

    test('lists every menu file', () {
      final missing = [
        for (final menu in menus)
          if (!readme.contains(menu.name)) menu.name,
      ];
      expect(missing, isEmpty);
    });
  });
}
