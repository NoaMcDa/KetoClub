// The shape check for the keto ground-truth corpus.
//
// `test/fixtures/keto/menus/*.json` holds Israeli menus whose every dish
// carries the verdict a careful keto reader would give it and the hidden
// carbs it likely hides (`test/fixtures/keto/SCHEMA.md`). This file asserts
// *shape and bookkeeping* only: required keys, enum values, the size and
// Hebrew share of the corpus, unique ids, that every label names evidence
// found in the dish's own text, and that copied dish texts still match
// their source. It says nothing about whether a label is right; the labels
// are unreviewed desk labelling (see `test/fixtures/keto/README.md`).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/menu.dart';

/// The directory every corpus menu lives in.
const String _menusDir = 'test/fixtures/keto/menus';

/// A decoded JSON object.
typedef _Json = Map<String, Object?>;

/// The verdicts, spelled as the `DishVerdict` enum spells them.
const List<String> _verdicts = <String>['orderAsIs', 'modifiable', 'nonKeto'];

/// The hidden-carb certainties, spelled as `HiddenCarbCertainty` spells
/// them.
const List<String> _certainties = <String>['suspected', 'likely'];

/// The values a menu's `language` may take.
const Set<String> _languages = <String>{'he', 'en', 'mixed'};

/// The keys a menu file has, exactly.
const Set<String> _menuKeys = <String>{
  'id',
  'name',
  'source',
  'language',
  'note',
  'categories',
};

/// The keys every dish has.
const Set<String> _dishKeys = <String>{
  'id',
  'name',
  'description',
  'options',
  'expected',
  'hiddenCarbs',
  'why',
  'evidence',
};

/// The one key a dish may have beyond [_dishKeys].
const String _acceptableKey = 'acceptable';

/// The sentence every file's `note` starts with, and the README states.
const String _caveat =
    'Unreviewed desk labelling — not reviewed by a dietitian.';

/// The prefix of a `source` naming the fixture the texts were copied from.
const String _copiedPrefix = 'copied:';

/// The minimum number of menus, dishes and per-value occurrences.
const int _minMenus = 20;
const int _minDishes = 400;
const int _minPerValue = 15;

/// The share of dishes that must read as Hebrew, exclusive.
const double _minHebrewShare = 0.6;

/// A Hebrew letter.
final RegExp _hebrewLetter = RegExp('[א-ת]');

/// One menu file: its file name and decoded content.
typedef _Menu = ({String file, _Json json});

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
      (
        file: file.uri.pathSegments.last,
        json: jsonDecode(file.readAsStringSync()) as _Json,
      ),
  ];
}

/// The categories of [menu], or empty when the shape is wrong.
List<_Json> _categoriesOf(_Json menu) {
  final raw = menu['categories'];
  if (raw is! List<Object?>) return const <_Json>[];
  return raw.whereType<_Json>().toList();
}

/// The dishes of [category], or empty when the shape is wrong.
List<_Json> _dishesOfCategory(_Json category) {
  final raw = category['dishes'];
  if (raw is! List<Object?>) return const <_Json>[];
  return raw.whereType<_Json>().toList();
}

/// Every dish of [menu], in order.
List<_Json> _dishesOf(_Json menu) => <_Json>[
  for (final category in _categoriesOf(menu)) ..._dishesOfCategory(category),
];

/// Whether [value] is a non-blank string.
bool _isText(Object? value) => value is String && value.trim().isNotEmpty;

/// The strings of [value], or null when it is not a list of strings.
List<String>? _strings(Object? value) {
  if (value is! List<Object?>) return null;
  if (value.any((item) => item is! String)) return null;
  return value.cast<String>();
}

/// The hidden-carb flags of [dish].
List<_Json> _hiddenOf(_Json dish) {
  final raw = dish['hiddenCarbs'];
  if (raw is! List<Object?>) return const <_Json>[];
  return raw.whereType<_Json>().toList();
}

/// The dish's own text, lower-cased: name, description, option names and
/// option values.
String _textOf(_Json dish) {
  final options = dish['options'];
  final parts = <String>[
    '${dish['name']}',
    '${dish['description']}',
    if (options is List<Object?>)
      for (final option in options)
        if (option is _Json) ...<String>[
          '${option['name']}',
          ...?_strings(option['values']),
        ],
  ];
  return parts.join('\n').toLowerCase();
}

/// Whether [dish] reads as Hebrew: a Hebrew letter in its name or
/// description.
bool _isHebrew(_Json dish) =>
    _hebrewLetter.hasMatch('${dish['name']} ${dish['description']}');

/// The problems with one option of a dish at [at].
List<String> _optionProblems(String at, Object? option) {
  if (option is! _Json) return <String>['$at: an option is not an object'];
  final values = _strings(option['values']);
  return <String>[
    if (!setEquals(option.keys.toSet(), const <String>{'name', 'values'}))
      '$at: option keys are ${option.keys}',
    if (!_isText(option['name'])) '$at: option name is blank',
    if (values == null || values.isEmpty) '$at: option values are not strings',
  ];
}

/// The problems with one hidden-carb flag of a dish at [at].
List<String> _flagProblems(String at, String text, Object? flag) {
  if (flag is! _Json) return <String>['$at: a hidden carb is not an object'];
  final term = flag['term'];
  final keys = flag.keys.toSet()..remove('term');
  return <String>[
    if (!setEquals(keys, const <String>{'source', 'certainty'}))
      '$at: hidden-carb keys are ${flag.keys}',
    if (!_isText(flag['source'])) '$at: hidden-carb source is blank',
    if (!_certainties.contains(flag['certainty']))
      '$at: hidden-carb certainty ${flag['certainty']}',
    if (flag.containsKey('term') && !_isText(term))
      '$at: hidden-carb term is blank',
    if (term is String && !text.contains(term.toLowerCase()))
      '$at: hidden-carb term "$term" is not in the dish text',
  ];
}

/// The problems with [dish], found at [at].
List<String> _dishProblems(String at, _Json dish) {
  final keys = dish.keys.toSet()..remove(_acceptableKey);
  final options = dish['options'];
  final expected = dish['expected'];
  final acceptable = _strings(dish[_acceptableKey]);
  final hidden = dish['hiddenCarbs'];
  final evidence = _strings(dish['evidence']);
  final text = _textOf(dish);
  return <String>[
    if (!setEquals(keys, _dishKeys)) '$at: keys are ${dish.keys}',
    if (!_isText(dish['id'])) '$at: id is blank',
    if (!_isText(dish['name'])) '$at: name is blank',
    if (dish['description'] is! String) '$at: description is not a string',
    if (options is! List<Object?>)
      '$at: options is not a list'
    else
      for (final option in options) ..._optionProblems(at, option),
    if (!_verdicts.contains(expected)) '$at: expected is $expected',
    if (dish.containsKey(_acceptableKey) && acceptable == null)
      '$at: acceptable is not a list of strings',
    for (final verdict in acceptable ?? const <String>[])
      if (!_verdicts.contains(verdict)) '$at: acceptable holds $verdict',
    if (acceptable != null && acceptable.toSet().length != acceptable.length)
      '$at: acceptable repeats a verdict',
    if (acceptable != null && acceptable.contains(expected))
      '$at: acceptable holds the expected verdict',
    if (expected == 'nonKeto' && (acceptable?.contains('orderAsIs') ?? false))
      '$at: orderAsIs is acceptable on a nonKeto dish',
    if (hidden is! List<Object?>)
      '$at: hiddenCarbs is not a list'
    else
      for (final flag in hidden) ..._flagProblems(at, text, flag),
    if (!_isText(dish['why'])) '$at: why is blank',
    if (evidence == null || evidence.isEmpty) '$at: no evidence',
    for (final term in evidence ?? const <String>[])
      if (term.trim().isEmpty || !text.contains(term.toLowerCase()))
        '$at: evidence "$term" is not in the dish text',
  ];
}

/// The problems with the top level of [menu], read from [file].
List<String> _menuProblems(String file, _Json menu) {
  final categories = menu['categories'];
  final source = menu['source'];
  return <String>[
    if (!setEquals(menu.keys.toSet(), _menuKeys))
      '$file: keys are ${menu.keys}',
    if (menu['id'] != file.replaceAll('.json', ''))
      '$file: id ${menu['id']} is not the file name',
    if (!_isText(menu['name'])) '$file: name is blank',
    if (source != 'synthetic' &&
        !(source is String &&
            source.startsWith(_copiedPrefix) &&
            source.length > _copiedPrefix.length))
      '$file: source is $source',
    if (!_languages.contains(menu['language']))
      '$file: language is ${menu['language']}',
    if (menu['note'] is! String ||
        !(menu['note']! as String).startsWith(_caveat))
      '$file: note does not start with the caveat',
    if (categories is! List<Object?> || categories.isEmpty)
      '$file: no categories',
    for (final category in _categoriesOf(menu)) ...<String>[
      if (!setEquals(category.keys.toSet(), const <String>{'name', 'dishes'}))
        '$file: category keys are ${category.keys}',
      if (!_isText(category['name'])) '$file: a category name is blank',
      if (_dishesOfCategory(category).isEmpty)
        '$file: category ${category['name']} has no dishes',
    ],
  ];
}

/// The dishes of the fixture [path] a copied menu names, keyed by the
/// corpus dish id (`d1` is the first dish).
Map<String, _Json> _sourceDishes(String path) {
  final json = jsonDecode(File(path).readAsStringSync()) as _Json;
  final dishes = (json['dishes']! as List<Object?>).cast<_Json>();
  return <String, _Json>{
    for (var i = 0; i < dishes.length; i++) 'd${i + 1}': dishes[i],
  };
}

void main() {
  final menus = _loadMenus();
  final dishes = <({String menu, _Json dish})>[
    for (final menu in menus)
      for (final dish in _dishesOf(menu.json)) (menu: menu.file, dish: dish),
  ];

  group('keto corpus size', () {
    test('has at least $_minMenus menus', () {
      expect(menus.length, greaterThanOrEqualTo(_minMenus));
    });

    test('has at least $_minDishes dishes', () {
      expect(dishes.length, greaterThanOrEqualTo(_minDishes));
    });

    test('is more than 60% Hebrew', () {
      final hebrew = dishes.where((d) => _isHebrew(d.dish)).length;
      expect(hebrew / dishes.length, greaterThan(_minHebrewShare));
    });

    for (final verdict in _verdicts) {
      test('expects $verdict at least $_minPerValue times', () {
        final count = dishes.where((d) => d.dish['expected'] == verdict).length;
        expect(count, greaterThanOrEqualTo(_minPerValue));
      });
    }

    for (final certainty in _certainties) {
      test('flags a $certainty hidden carb at least $_minPerValue times', () {
        final count = dishes
            .expand((d) => _hiddenOf(d.dish))
            .where((flag) => flag['certainty'] == certainty)
            .length;
        expect(count, greaterThanOrEqualTo(_minPerValue));
      });
    }
  });

  group('keto corpus schema', () {
    test('finds the menus directory', () {
      expect(Directory(_menusDir).existsSync(), isTrue);
    });

    for (final menu in menus) {
      test('${menu.file} has the menu keys', () {
        final problems = _menuProblems(menu.file, menu.json);
        expect(problems, isEmpty, reason: problems.join('\n'));
      });

      test('${menu.file} labels every dish well-formed', () {
        final problems = <String>[
          for (final dish in _dishesOf(menu.json))
            ..._dishProblems('${menu.file}/${dish['id']}', dish),
        ];
        expect(problems, isEmpty, reason: problems.join('\n'));
      });

      test('${menu.file} decodes every dish as a Dish', () {
        final failed = <String>[
          for (final dish in _dishesOf(menu.json))
            if (Dish.tryFrom(<String, Object?>{
                  'id': dish['id'],
                  'name': dish['name'],
                  'description': dish['description'],
                  'price': 0,
                  'options': dish['options'],
                }) ==
                null)
              '${dish['id']}',
        ];
        expect(failed, isEmpty);
      });
    }
  });

  group('keto corpus ids', () {
    test('menu ids are unique', () {
      final ids = [for (final menu in menus) menu.json['id']];
      expect(ids.toSet().length, ids.length);
    });

    for (final menu in menus) {
      test('${menu.file} dish ids are unique', () {
        final ids = [for (final dish in _dishesOf(menu.json)) dish['id']];
        expect(ids.toSet().length, ids.length);
      });
    }
  });

  group('keto corpus copies', () {
    for (final menu in menus) {
      final source = menu.json['source'];
      if (source is! String || !source.startsWith(_copiedPrefix)) continue;
      final path = source.substring(_copiedPrefix.length);

      test('${menu.file} carries the text of $path', () {
        expect(File(path).existsSync(), isTrue, reason: path);
        final originals = _sourceDishes(path);
        final drifted = <String>[];
        for (final dish in _dishesOf(menu.json)) {
          final original = originals[dish['id']];
          if (original == null ||
              original['name'] != dish['name'] ||
              original['description'] != dish['description'] ||
              jsonEncode(original['options']) != jsonEncode(dish['options'])) {
            drifted.add('${dish['id']}');
          }
        }
        expect(drifted, isEmpty);
      });
    }
  });

  group('keto corpus README', () {
    final readme = File('test/fixtures/keto/README.md').readAsStringSync();

    test('says the labels are unreviewed', () {
      expect(readme, contains(_caveat));
    });

    test('lists every menu file', () {
      final missing = [
        for (final menu in menus)
          if (!readme.contains(menu.file)) menu.file,
      ];
      expect(missing, isEmpty);
    });
  });
}
