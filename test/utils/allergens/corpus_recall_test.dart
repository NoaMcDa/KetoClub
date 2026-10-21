// The rules-recall gate over the allergen safety corpus (ALG-10, issue #352).
//
// Every dish of `test/fixtures/allergens/menus/*.json` is run through
// `ClassificationRules.allergenConcerns`, the same rules pass the app runs
// with no model. The gate: for every strict restriction, a `contains` label
// must come back as a concern of at least `likely` certainty and a
// `may_contain` label as a concern of at least `suspected`. False positives
// (a concern where the label is `free` or absent) are reported and never
// fail; a false alarm is the acceptable direction.
//
// The labels are unreviewed desk research (`test/fixtures/allergens/README.md`).
// A miss that the vocabulary does not yet close is listed in
// `known_misses.json`; the test fails for a miss that is not listed and for
// a listed entry that no longer misses, so the list can only shrink. The
// Python twin, `backend/tests/test_allergen_corpus_recall.py`, replays the
// same files against the same list and must agree with this one.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/classification_rules.dart';

/// The directory every corpus menu lives in.
const String _menusDir = 'test/fixtures/allergens/menus';

/// The reviewed list of misses the vocabulary does not close yet.
const String _knownMissesPath = 'test/fixtures/allergens/known_misses.json';

/// A decoded JSON object.
typedef _Json = Map<String, Object?>;

/// One labelled dish and what the rules found on it.
class _Replay {
  const new({
    required this.menu,
    required this.dish,
    required this.labels,
    required this.found,
  });

  /// The corpus file the dish is in.
  final String menu;

  /// The dish's name.
  final String dish;

  /// The dish's labels, keyed by restriction id name.
  final _Json labels;

  /// The rules' concerns for the dish, keyed by restriction.
  final Map<RestrictionId, Concern> found;
}

/// One failure of the gate: a label the rules did not meet.
class _Miss {
  const new(this.id, this.menu, this.dish, this.label, this.got);

  /// The restriction id name.
  final String id;

  /// The corpus file.
  final String menu;

  /// The dish name.
  final String dish;

  /// `contains` or `may_contain`.
  final String label;

  /// The certainty found, or null when there was no concern at all.
  final Certainty? got;

  /// The key an allowlist entry matches.
  String get key => '$id|$menu|$dish';

  @override
  String toString() =>
      '$id  $menu  "$dish"  $label  found: ${got?.name ?? 'nothing'}';
}

/// The key of the allowlist [entry].
String _keyOf(_Json entry) =>
    '${entry['id']}|${entry['menu']}|${entry['dish']}';

/// The weakest certainty a [label] must reach.
Certainty _required(String label) =>
    label == 'contains' ? Certainty.likely : Certainty.suspected;

/// Whether [got] is at least [needed] (`stated` is the surest).
bool _meets(Certainty? got, Certainty needed) =>
    got != null && got.index <= needed.index;

/// Every dish of every corpus menu, replayed through the rules.
List<_Replay> _replayAll() {
  final files =
      Directory(_menusDir)
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final out = <_Replay>[];
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final json = jsonDecode(file.readAsStringSync()) as _Json;
    final dishes = (json['dishes']! as List<Object?>).cast<_Json>();
    for (var i = 0; i < dishes.length; i++) {
      final raw = dishes[i];
      final dish = Dish(
        id: '$name#$i',
        name: raw['name']! as String,
        description: raw['description']! as String,
        price: 0,
        options: <DishOption>[
          for (final option in (raw['options']! as List<Object?>).cast<_Json>())
            DishOption(
              name: option['name']! as String,
              values: (option['values']! as List<Object?>).cast<String>(),
            ),
        ],
      );
      out.add(
        _Replay(
          menu: name,
          dish: raw['name']! as String,
          labels: raw['labels']! as _Json,
          found: <RestrictionId, Concern>{
            for (final concern in ClassificationRules.allergenConcerns(dish))
              concern.restrictionId: concern,
          },
        ),
      );
    }
  }
  return out;
}

/// The strict restriction ids, from the taxonomy, without the user's own
/// restriction (ALG-17): it is strict, but its words live in the profile
/// on the device, so the corpus has nothing to label for it.
List<RestrictionId> _strictIds() => <RestrictionId>[
  for (final id in RestrictionId.values)
    if (restrictionFor(id).isStrict && id != RestrictionId.custom) id,
];

/// Every label of a strict restriction that the rules did not meet.
List<_Miss> _misses(List<_Replay> replay) {
  final strict = _strictIds();
  final out = <_Miss>[];
  for (final dish in replay) {
    for (final id in strict) {
      final label = (dish.labels[id.name] as _Json?)?['label'];
      if (label is! String || label == 'free') {
        continue;
      }
      final got = dish.found[id]?.certainty;
      if (!_meets(got, _required(label))) {
        out.add(_Miss(id.name, dish.menu, dish.dish, label, got));
      }
    }
  }
  return out;
}

/// The allowlist entries, as written.
List<_Json> _knownMisses() {
  final json = jsonDecode(File(_knownMissesPath).readAsStringSync()) as _Json;
  return (json['misses']! as List<Object?>).cast<_Json>();
}

/// [hit] of [total] as a percentage, or a dash for an empty denominator.
String _pct(int hit, int total) => total == 0
    ? '     -'
    : '${(100 * hit / total).toStringAsFixed(1)}%'.padLeft(6);

void main() {
  final replay = _replayAll();
  final misses = _misses(replay);
  final known = _knownMisses();

  test('prints per-restriction recall and false positives', () {
    const columns =
        'contains  recall   may_contain  recall   FP(free)  FP(unlabelled)';
    final lines = <String>[
      'allergen corpus recall (rules only, ${replay.length} dishes)',
      '  ${'restriction'.padRight(12)} $columns',
    ];
    var containsTotal = 0;
    var containsHit = 0;
    var mayTotal = 0;
    var mayHit = 0;
    for (final id in _strictIds()) {
      var c = 0;
      var cHit = 0;
      var m = 0;
      var mHit = 0;
      var fpFree = 0;
      var fpUnlabelled = 0;
      for (final dish in replay) {
        final label = (dish.labels[id.name] as _Json?)?['label'];
        final got = dish.found[id]?.certainty;
        switch (label) {
          case 'contains':
            c++;
            if (_meets(got, Certainty.likely)) cHit++;
          case 'may_contain':
            m++;
            if (_meets(got, Certainty.suspected)) mHit++;
          case 'free':
            if (got != null) fpFree++;
          default:
            if (got != null) fpUnlabelled++;
        }
      }
      containsTotal += c;
      containsHit += cHit;
      mayTotal += m;
      mayHit += mHit;
      lines.add(
        '  ${id.name.padRight(12)} ${'$cHit/$c'.padLeft(8)}  ${_pct(cHit, c)}'
        '   ${'$mHit/$m'.padLeft(11)}  ${_pct(mHit, m)}'
        '   ${'$fpFree'.padLeft(8)}  ${'$fpUnlabelled'.padLeft(14)}',
      );
    }
    lines
      ..add(
        '  ${'all strict'.padRight(12)} '
        '${'$containsHit/$containsTotal'.padLeft(8)}  '
        '${_pct(containsHit, containsTotal)}   '
        '${'$mayHit/$mayTotal'.padLeft(11)}  ${_pct(mayHit, mayTotal)}',
      )
      ..add('  misses: ${misses.length}, known: ${known.length}');
    stdout.writeln(lines.join('\n'));
    expect(containsTotal, greaterThan(0));
  });

  // Kosher and halal (#342) are flexible, so they stay outside the gate;
  // their recall and false positives are printed only, so a vocabulary
  // change shows what it moves.
  test("prints the religious components' recall and false positives", () {
    const columns = 'contains  may_contain  free  FP(free)  FP(unlabelled)';
    final lines = <String>[
      'religious components (rules only, not gated)',
      '  ${'restriction'.padRight(12)} $columns',
    ];
    var labelled = 0;
    for (final id in <RestrictionId>[
      RestrictionId.kosher,
      RestrictionId.halal,
    ]) {
      var c = 0;
      var cHit = 0;
      var m = 0;
      var mHit = 0;
      var free = 0;
      var fpFree = 0;
      var fpUnlabelled = 0;
      for (final dish in replay) {
        final label = (dish.labels[id.name] as _Json?)?['label'];
        final got = dish.found[id]?.certainty;
        switch (label) {
          case 'contains':
            c++;
            if (_meets(got, Certainty.likely)) cHit++;
          case 'may_contain':
            m++;
            if (_meets(got, Certainty.suspected)) mHit++;
          case 'free':
            free++;
            if (got != null) fpFree++;
          default:
            if (got != null) fpUnlabelled++;
        }
      }
      labelled += c + m + free;
      lines.add(
        '  ${id.name.padRight(12)} ${'$cHit/$c'.padLeft(8)}  '
        '${'$mHit/$m'.padLeft(11)}  ${'$free'.padLeft(4)}  '
        '${'$fpFree'.padLeft(8)}  ${'$fpUnlabelled'.padLeft(14)}',
      );
    }
    stdout.writeln(lines.join('\n'));
    expect(labelled, greaterThan(0));
  });

  test('the allowlist is well-formed', () {
    for (final entry in known) {
      expect(entry.keys.toSet(), <String>{
        'id',
        'menu',
        'dish',
        'label',
        'reason',
      });
      for (final value in entry.values) {
        expect(value, isA<String>());
        expect((value! as String).trim(), isNotEmpty);
      }
    }
    final keys = [for (final entry in known) _keyOf(entry)];
    expect(keys.toSet().length, keys.length, reason: 'duplicate entry');
  });

  test('every strict contains and may_contain label is found', () {
    final listed = <String>{for (final entry in known) _keyOf(entry)};
    final unlisted = [
      for (final miss in misses)
        if (!listed.contains(miss.key)) miss,
    ];
    expect(
      unlisted,
      isEmpty,
      reason:
          'a label the rules miss and known_misses.json does not list:\n'
          '${unlisted.join('\n')}',
    );
  });

  test('every allowlisted miss still misses', () {
    final current = <String>{for (final miss in misses) miss.key};
    final stale = [
      for (final entry in known)
        if (!current.contains(_keyOf(entry)))
          '${entry['id']}  ${entry['menu']}  "${entry['dish']}"',
    ];
    expect(
      stale,
      isEmpty,
      reason:
          'known_misses.json lists a miss that is no longer one (or names '
          'a label that does not exist); delete the entry:\n'
          '${stale.join('\n')}',
    );
  });

  test('an allowlist entry names the label the corpus carries', () {
    final byKey = <String, _Miss>{for (final miss in misses) miss.key: miss};
    final wrong = [
      for (final entry in known)
        if (byKey[_keyOf(entry)] case final miss?
            when miss.label != entry['label'])
          '${miss.key}: allowlist says ${entry['label']}, corpus ${miss.label}',
    ];
    expect(wrong, isEmpty);
  });
}
