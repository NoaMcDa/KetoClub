// The shape check for the allergen safety corpus (ALG-10, issue #352).
//
// `test/fixtures/allergens/menus/*.json` holds labelled menus that a later
// test replays to measure the engine's recall per restriction. This file
// asserts *shape and bookkeeping* only: required keys, enum values, the
// size of the corpus, and that every label names its evidence and cites a
// section of the desk-research documents. It says nothing about whether a
// label is right; the labels are unreviewed desk research (see
// `test/fixtures/allergens/README.md`).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The directory every corpus menu lives in.
const String _menusDir = 'test/fixtures/allergens/menus';

// TODO(ALG-01a): switch to RestrictionId.values once merged
/// The 20 restriction ids a label may be keyed by, spelled exactly as the
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
  'vegan',
  'vegetarian',
  'keto',
];

/// Restrictions that are not strict: an intolerance, two diets and keto. A
/// `contains` label on any other id must name the role of its trigger.
const Set<String> _flexibleIds = <String>{
  'lactose',
  'vegan',
  'vegetarian',
  'keto',
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

/// A Hebrew letter, the heuristic that makes a dish a Hebrew dish.
final RegExp _hebrewLetter = RegExp('[א-ת]');

/// A corpus file: its name and decoded JSON.
class _Menu {
  new(this.name, this.json);

  final String name;
  final Map<String, Object?> json;

  List<Map<String, Object?>> get dishes =>
      (json['dishes']! as List<Object?>).cast<Map<String, Object?>>();
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
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
      ),
  ];
}

/// Whether [dish] reads as Hebrew: a Hebrew letter in its name or
/// description.
bool _isHebrew(Map<String, Object?> dish) {
  final text = '${dish['name']} ${dish['description']}';
  return _hebrewLetter.hasMatch(text);
}

/// Every way [dish] of [menu] breaks the schema, as readable lines.
List<String> _dishProblems(String menu, int index, Map<String, Object?> dish) {
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
      if (option is! Map<String, Object?> ||
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
  if (labels is! Map<String, Object?>) {
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
  if (value is! Map<String, Object?>) {
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
  }
  final source = value['source'];
  if (source is! String || !_sourcePattern.hasMatch(source)) {
    problems.add(
      '$at: source must match ${_sourcePattern.pattern}, got $source',
    );
  }
  return problems;
}

void main() {
  final menus = _loadMenus();
  final dishes = <Map<String, Object?>>[
    for (final menu in menus) ...menu.dishes,
  ];

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

    test('labels every restriction as contained at least once', () {
      final contained = <String>{
        for (final dish in dishes)
          for (final entry in (dish['labels']! as Map<String, Object?>).entries)
            if ((entry.value! as Map<String, Object?>)['label'] == 'contains')
              entry.key,
      };
      final missing = _restrictionIds
          .where((id) => id != 'keto' && !contained.contains(id))
          .toList();
      expect(missing, isEmpty);
    });

    test('carries explicit free labels for false-positive measurement', () {
      final free = dishes
          .expand(
            (dish) => (dish['labels']! as Map<String, Object?>).values
                .cast<Map<String, Object?>>(),
          )
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
    }
  });

  group('allergen corpus labels', () {
    test('every contains label on a strict restriction names a role', () {
      final missing = <String>[];
      for (final menu in menus) {
        for (final dish in menu.dishes) {
          final labels = dish['labels']! as Map<String, Object?>;
          for (final entry in labels.entries) {
            final label = entry.value! as Map<String, Object?>;
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

    test('every label has evidence and a source citation', () {
      final bad = <String>[];
      for (final menu in menus) {
        for (final dish in menu.dishes) {
          final labels = dish['labels']! as Map<String, Object?>;
          for (final entry in labels.entries) {
            final label = entry.value! as Map<String, Object?>;
            final evidence = label['evidence'];
            final source = label['source'];
            if (evidence is! String ||
                evidence.trim().isEmpty ||
                source is! String ||
                !_sourcePattern.hasMatch(source)) {
              bad.add('${menu.name}: ${dish['name']} / ${entry.key}');
            }
          }
        }
      }
      expect(bad, isEmpty);
    });
  });

  group('allergen corpus README', () {
    test('says the labels are unreviewed desk research', () {
      final readme = File('test/fixtures/allergens/README.md')
          .readAsStringSync()
          .toLowerCase();
      expect(readme, contains('unreviewed'));
      expect(readme, contains('desk research'));
    });
  });
}
