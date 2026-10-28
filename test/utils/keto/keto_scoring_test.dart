// The keto accuracy scorer (`keto_scoring.dart`), proven on a small
// synthetic fixture (`test/fixtures/keto_gate_test/`) rather than the real
// corpus, so the metrics stay pinned whatever the corpus holds.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';

import 'keto_scoring.dart';

/// The synthetic fixture: two menus, four dishes.
const String _fixtureDir = 'test/fixtures/keto_gate_test';

/// Suspected hidden-carb labels for [sources], with no term.
List<KetoHiddenCarbLabel> _labels(List<String> sources) => [
  for (final source in sources)
    KetoHiddenCarbLabel(source: source, certainty: 'suspected'),
];

/// A replay of one dish labelled [expected] that came back [got].
KetoReplay _replay({
  required DishVerdict expected,
  required DishVerdict? got,
  List<DishVerdict> acceptable = const <DishVerdict>[],
  List<String> labels = const <String>[],
  List<String> flags = const <String>[],
  String language = 'en',
}) {
  final dish = KetoCorpusDish(
    id: 'd',
    name: 'd',
    description: '',
    options: const [],
    expected: expected,
    acceptable: acceptable,
    hiddenCarbs: _labels(labels),
  );
  return KetoReplay(
    menu: KetoCorpusMenu(
      file: 'm.json',
      id: 'm',
      name: 'm',
      language: language,
      categories: [
        KetoCorpusCategory(name: 'c', dishes: [dish]),
      ],
    ),
    dish: dish,
    got: got,
    flags: [
      for (final source in flags)
        HiddenCarb(
          source: source,
          certainty: HiddenCarbCertainty.suspected,
          waiterQuestion: '?',
        ),
    ],
  );
}

void main() {
  late final List<KetoCorpusMenu> corpus;
  late final KetoReport report;

  setUpAll(() async {
    corpus = loadKetoCorpus(Directory(_fixtureDir));
    report = KetoReport.of(await replayKetoCorpus(corpus));
  });

  group('loading', () {
    test('reads every menu, sorted by file, with its dishes', () {
      expect(
        [for (final menu in corpus) menu.id],
        ['gate_en_grill', 'gate_he_cafe'],
      );
      expect(corpus.first.dishes.map((d) => d.id), [
        'steak',
        'carbonara',
        'chicken',
      ]);
      final chicken = corpus.first.dishes.last;
      expect(chicken.acceptable, [DishVerdict.modifiable]);
      expect(chicken.options.single.values, ['Mashed potatoes', 'Green salad']);
      final flag = corpus.last.dishes.single.hiddenCarbs.single;
      expect(flag.source, 'breadcrumb binder (פירורי לחם)');
      expect(flag.certainty, 'likely');
      expect(flag.term, isNull);
    });

    test('an absent directory is an empty corpus', () {
      expect(loadKetoCorpus(Directory('test/fixtures/no_such_dir')), isEmpty);
    });

    test('an unknown verdict names the file and the dish', () {
      expect(
        () => parseKetoCorpusMenu(
          jsonDecode('''
            {"id": "m", "name": "m", "language": "en", "categories": [
              {"name": "c", "dishes": [
                {"id": "x", "name": "x", "options": [], "expected": "green"}
              ]}
            ]}
          ''') as Json,
          file: 'f.json',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('f.json#x'),
          ),
        ),
      );
    });

    test('the app menu keeps the corpus ids and text', () {
      final menu = toAppMenu(corpus.first);
      expect(menu.venueName, 'Gate Test Grill');
      expect(menu.allDishes.map((d) => d.id), [
        'steak',
        'carbonara',
        'chicken',
      ]);
      expect(menu.allDishes.first.description, contains('herb butter'));
    });
  });

  group('the fixture replay', () {
    test('gives the rule engine verdicts', () {
      expect(
        {for (final r in report.replays) r.dish.id: r.got},
        {
          'steak': DishVerdict.orderAsIs,
          'carbonara': DishVerdict.nonKeto,
          'chicken': DishVerdict.modifiable,
          'meatballs': DishVerdict.orderAsIs,
        },
      );
    });

    test('counts an acceptable verdict as correct', () {
      expect(report.all.total, 4);
      expect(report.all.correct, 3);
      expect(report.all.accuracy, 0.75);
    });

    test('the false green is the meatballs, over three non-green dishes', () {
      expect(report.falseGreens.map((r) => r.dish.id), ['meatballs']);
      expect(report.all.nonGreen, 3);
      expect(report.all.falseGreenRate, closeTo(1 / 3, 1e-9));
      expect(report.all.falseReds, 0);
      expect(report.all.notRed, 2);
      expect(report.all.unclassified, 0);
      expect(report.otherDisagreements, isEmpty);
    });

    test('fills the confusion matrix', () {
      final m = report.all.matrix;
      expect(m[DishVerdict.orderAsIs]![DishVerdict.orderAsIs], 1);
      expect(m[DishVerdict.nonKeto]![DishVerdict.nonKeto], 1);
      expect(m[DishVerdict.nonKeto]![DishVerdict.modifiable], 1);
      expect(m[DishVerdict.modifiable]![DishVerdict.orderAsIs], 1);
      final sum = m.values.expand((row) => row.values).reduce((a, b) => a + b);
      expect(sum, 4);
    });

    test('reports hidden carbs as 0 recall and no precision without flags', () {
      expect(report.all.hiddenCarbLabels, 1);
      expect(report.all.hiddenCarbFlags, 0);
      expect(report.all.hiddenCarbRecall, 0);
      expect(report.all.hiddenCarbPrecision, isNull);
      expect(percent(report.all.hiddenCarbPrecision), '-');
    });

    test('breaks down per menu and per language', () {
      expect(report.perMenu.keys, ['gate_en_grill', 'gate_he_cafe']);
      expect(report.perMenu['gate_en_grill']!.falseGreens, 0);
      expect(report.perLanguage.keys, ['en', 'he']);
      expect(report.perLanguage['he']!.falseGreenRate, 1);
      expect(report.perLanguage['en']!.accuracy, 1);
    });

    test('renders text and markdown', () {
      final text = renderKetoReport(report, markdown: false);
      expect(text, contains('false greens (1)'));
      expect(text, contains('gate_he_cafe / meatballs'));
      final markdown = renderKetoReport(report, markdown: true);
      expect(markdown, contains('| all | 4 | 3/4 75.0% | 1/3 33.3% |'));
      expect(markdown, contains('- gate_he_cafe / meatballs'));
    });
  });

  group('verdict errors', () {
    test('a yellow called green is a false green', () {
      final r = _replay(
        expected: DishVerdict.modifiable,
        got: DishVerdict.orderAsIs,
      );
      expect(r.isFalseGreen, isTrue);
      expect(r.correct, isFalse);
    });

    test('green listed as acceptable is not a false green', () {
      final r = _replay(
        expected: DishVerdict.modifiable,
        got: DishVerdict.orderAsIs,
        acceptable: [DishVerdict.orderAsIs],
      );
      expect(r.isFalseGreen, isFalse);
      expect(r.correct, isTrue);
    });

    test('a green called red is a false red; unplaced is neither', () {
      expect(
        _replay(
          expected: DishVerdict.orderAsIs,
          got: DishVerdict.nonKeto,
        ).isFalseRed,
        isTrue,
      );
      final unplaced = _replay(expected: DishVerdict.nonKeto, got: null);
      expect(unplaced.isFalseGreen, isFalse);
      expect(unplaced.isFalseRed, isFalse);
      expect(unplaced.correct, isFalse);
      expect(KetoSlice.of([unplaced]).unclassified, 1);
    });
  });

  group('hidden carbs', () {
    test('match by normalised words, either way round', () {
      expect(
        hiddenCarbSourcesMatch('House dressing', 'the house dressing'),
        isTrue,
      );
      expect(hiddenCarbSourcesMatch('רוטב הבית', 'רוטב  הבית!'), isTrue);
      expect(hiddenCarbSourcesMatch('teriyaki glaze', 'teriyaki'), isTrue);
      expect(hiddenCarbSourcesMatch('breadcrumbs', 'house dressing'), isFalse);
      expect(hiddenCarbSourcesMatch('', 'sugar'), isFalse);
    });

    test('match one to one', () {
      expect(matchHiddenCarbs(_labels(['sugar', 'sugar']), ['sugar']), 1);
      expect(
        matchHiddenCarbs(_labels(['flour', 'sugar']), ['sugar', 'flour']),
        2,
      );
    });

    test('match a label by its term, not its source, when it has one', () {
      const label = KetoHiddenCarbLabel(
        source: 'house sauce (רוטב הבית)',
        certainty: 'suspected',
        term: 'ברוטב הבית',
      );
      // The term contains the flag, or the flag contains the term.
      expect(hiddenCarbLabelMatches(label, 'רוטב הבית'), isTrue);
      expect(hiddenCarbLabelMatches(label, 'ברוטב הבית'), isTrue);
      expect(hiddenCarbLabelMatches(label, 'ברוטב הבית המתוק!'), isTrue);
      // The English source is not consulted once there is a term.
      expect(hiddenCarbLabelMatches(label, 'house sauce'), isFalse);
      expect(hiddenCarbLabelMatches(label, 'sweet marinade'), isFalse);
    });

    test('fall back to the source when a label has no term', () {
      const label = KetoHiddenCarbLabel(
        source: 'breadcrumb binder (פירורי לחם)',
        certainty: 'likely',
      );
      expect(hiddenCarbLabelMatches(label, 'פירורי לחם'), isTrue);
      expect(hiddenCarbLabelMatches(label, 'breadcrumb binder'), isTrue);
      expect(hiddenCarbLabelMatches(label, 'sugar'), isFalse);
    });

    test('recall and precision count matched sources', () {
      final slice = KetoSlice.of([
        _replay(
          expected: DishVerdict.modifiable,
          got: DishVerdict.modifiable,
          labels: ['house dressing', 'breading'],
          flags: ['dressing', 'honey glaze', 'croutons'],
        ),
      ]);
      expect(slice.hiddenCarbRecall, 0.5);
      expect(slice.hiddenCarbPrecision, closeTo(1 / 3, 1e-9));
    });
  });

  group('known misses', () {
    const meatballs = KetoKnownMiss(
      menu: 'gate_he_cafe',
      dish: 'meatballs',
      expected: 'modifiable',
      got: 'orderAsIs',
      reason: 'no printed word names the breadcrumbs',
    );

    test('a listed false green passes, an unlisted one fails', () {
      expect(unlistedFalseGreens(report, [meatballs]), isEmpty);
      expect(unlistedFalseGreens(report, const []).map(replayKey), [
        'gate_he_cafe/meatballs',
      ]);
    });

    test('an entry that no longer misses is stale', () {
      const steak = KetoKnownMiss(
        menu: 'gate_en_grill',
        dish: 'steak',
        expected: 'orderAsIs',
        got: 'orderAsIs',
        reason: 'r',
      );
      const relabelled = KetoKnownMiss(
        menu: 'gate_he_cafe',
        dish: 'meatballs',
        expected: 'nonKeto',
        got: 'orderAsIs',
        reason: 'r',
      );
      expect(staleKnownKetoMisses(report, [meatballs]), isEmpty);
      expect(staleKnownKetoMisses(report, [steak, relabelled]), [
        steak,
        relabelled,
      ]);
    });

    test('regenerating keeps a reason and marks a new entry TODO', () {
      expect(regenerateKnownKetoMisses(report, const []).single.reason, 'TODO');
      final kept = regenerateKnownKetoMisses(report, [meatballs]).single;
      expect(kept.reason, meatballs.reason);
      expect(kept.toJson(), meatballs.toJson());
    });

    test('round-trips through the file text', () {
      final dir = Directory.systemTemp.createTempSync('keto_gate');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/m.json')
        ..writeAsStringSync(encodeKnownKetoMisses([meatballs]));
      final read = readKnownKetoMisses(file.path).single;
      expect(read.toJson(), meatballs.toJson());
      expect(readKnownKetoMisses('${file.path}.absent'), isEmpty);
    });

    test('rejects an entry with a missing, extra or blank key', () {
      final good = meatballs.toJson();
      expect(
        () => KetoKnownMiss.fromJson({...good}..remove('reason')),
        throwsFormatException,
      );
      expect(
        () => KetoKnownMiss.fromJson({...good, 'note': 'x'}),
        throwsFormatException,
      );
      expect(
        () => KetoKnownMiss.fromJson({...good, 'reason': ' '}),
        throwsFormatException,
      );
    });

    test('the committed list parses', () {
      expect(() => readKnownKetoMisses(ketoKnownMissesPath), returnsNormally);
    });
  });
}
