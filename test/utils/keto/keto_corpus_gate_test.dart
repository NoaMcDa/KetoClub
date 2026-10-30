// The keto accuracy gate: the labelled Israeli keto corpus replayed through
// the on-device rule engine (`HeuristicMenuClassifier`, default options).
//
// Every dish of `test/fixtures/keto/menus/*.json` is classified the way the
// app classifies with no model, and the report (`keto_scoring.dart`: the
// confusion matrix, accuracy, the false-green and false-red rates, the
// unplaced count, hidden-carb recall and precision, per menu and per
// language) is printed. The gate is the false green: a dish the corpus
// labels `modifiable` or `nonKeto` that the rules call `orderAsIs`. A false
// green that `test/fixtures/keto/known_keto_misses.json` does not list
// fails, and so does a listed entry that is no longer a false green, so the
// list can only shrink, exactly like the allergen corpus's
// `known_misses.json`. Every other disagreement is printed and never fails.
//
// The labels are unreviewed (`test/fixtures/keto/SCHEMA.md`): a mismatch is
// a question for the label as much as for the rules.
//
// `--dart-define=KETO_GATE_WRITE_MISSES=true` rewrites the known-misses
// file from the current false greens first (an existing entry keeps its
// reason, a new one reads `TODO`), for a person to review before it is
// committed. `--dart-define=KETO_GATE_MARKDOWN=true` prints the report as
// markdown, for a pull request or an evaluation note.
//
// With no corpus (`test/fixtures/keto/menus/` absent or empty) every test
// is skipped with a printed note.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'keto_scoring.dart';

/// Whether to rewrite the known-misses file from the current false greens.
const bool _writeMisses = bool.fromEnvironment('KETO_GATE_WRITE_MISSES');

/// Whether to print the report as markdown.
const bool _markdown = bool.fromEnvironment('KETO_GATE_MARKDOWN');

void main() {
  final corpus = loadKetoCorpus(Directory(ketoMenusDir));
  final skip = corpus.isEmpty
      ? 'no keto corpus under $ketoMenusDir; the gate has nothing to replay'
      : null;
  if (skip != null) stdout.writeln('keto corpus gate skipped: $skip');

  late final KetoReport report;
  late final List<KetoKnownMiss> known;

  setUpAll(() async {
    if (corpus.isEmpty) return;
    report = KetoReport.of(await replayKetoCorpus(corpus));
    if (_writeMisses) {
      final regenerated = regenerateKnownKetoMisses(
        report,
        readKnownKetoMisses(ketoKnownMissesPath),
      );
      File(ketoKnownMissesPath)
          .writeAsStringSync(encodeKnownKetoMisses(regenerated));
      stdout.writeln(
        'rewrote $ketoKnownMissesPath: ${regenerated.length} known misses',
      );
    }
    known = readKnownKetoMisses(ketoKnownMissesPath);
  });

  test('prints the accuracy report', skip: skip, () {
    stdout.writeln(renderKetoReport(report, markdown: _markdown));
    final todo = known.where((entry) => entry.reason == 'TODO').length;
    stdout.writeln(
      'known misses: ${known.length} listed, $todo still read TODO '
      '(review each before it is committed)',
    );
    expect(report.all.total, greaterThan(0));
  });

  test('every corpus dish has an id unique within its menu', skip: skip, () {
    final keys = [for (final replay in report.replays) replayKey(replay)];
    final menus = [for (final menu in corpus) menu.id];
    expect(keys.toSet().length, keys.length, reason: 'duplicate dish id');
    expect(menus.toSet().length, menus.length, reason: 'duplicate menu id');
  });

  test('the known-misses list is well-formed', skip: skip, () {
    final keys = [for (final entry in known) entry.key];
    expect(keys.toSet().length, keys.length, reason: 'duplicate entry');
  });

  test('every false green is a reviewed known miss', skip: skip, () {
    final unlisted = unlistedFalseGreens(report, known);
    expect(
      unlisted,
      isEmpty,
      reason:
          'a dish the corpus labels not green that the rules call '
          'orderAsIs, and known_keto_misses.json does not list:\n'
          '${[for (final r in unlisted) _line(r)].join('\n')}',
    );
  });

  test('every known miss is still a false green', skip: skip, () {
    final stale = staleKnownKetoMisses(report, known);
    expect(
      stale,
      isEmpty,
      reason:
          'known_keto_misses.json lists a dish that is no longer a false '
          'green (or names a dish, expected or got the corpus does not '
          'carry); delete or correct the entry:\n'
          '${[for (final e in stale) '${e.menu} / ${e.dish}'].join('\n')}',
    );
  });
}

/// One line naming a false green.
String _line(KetoReplay replay) =>
    '${replay.menu.id} / ${replay.dish.id} "${replay.dish.name}": '
    'expected ${replay.dish.expected.name}';
