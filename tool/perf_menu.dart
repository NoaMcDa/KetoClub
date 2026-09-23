/// Performance harness for issue #65: how long the CPU-bound steps of
/// opening a menu take on the thread that also draws frames.
///
/// Times, over a 60-dish menu (the size the issue budgets for):
///
/// - **decode + map** — `jsonDecode` of a platform payload followed by
///   `WoltMenuMapper.toMenu` or `TenBisMenuMapper.toMenu`, the step the
///   issue says moves to `compute` if it exceeds [mappingBudgetMs] on a
///   phone;
/// - **fingerprint** — `TextNormaliser.menuFingerprint`, which a refresh
///   runs twice to decide whether to reclassify (issue #49);
/// - **rules engine** — `HeuristicMenuClassifier.classify`, the fallback
///   every no-consent or offline open runs;
/// - **reply parse** — `MenuResponseParser.parse` of a 60-dish AI reply,
///   the other JSON step the issue names.
///
/// The 60-dish payloads are generated in code by [syntheticWoltPayload]
/// and [syntheticTenBisPayload], not read from disk, so [main] runs
/// unchanged on a phone (`flutter run --profile -t tool/perf_menu.dart`)
/// where `test/fixtures/` does not exist. A caller that *can* read the
/// checked-in fixtures passes them to [runMenuPerf] as [PerfFixture]s, and
/// they are timed alongside — `test/tool/perf_menu_test.dart` does that.
///
/// # Why not `dart run`
///
/// Everything timed here lives under `lib/` and transitively imports
/// `package:flutter/foundation.dart`, which needs `dart:ui`: plain
/// `dart run` cannot load it. The harness runs under `flutter test` (on
/// the host) or `flutter run` (on a device) instead. It also imports no
/// `dart:io`, so the same file compiles for every platform.
///
/// # What the numbers mean
///
/// Only a `--profile` build on a real device counts against
/// [mappingBudgetMs]. `flutter test` runs unoptimised JIT code on a
/// desktop CPU: its numbers show the relative cost of each step and catch
/// a regression by orders of magnitude, not whether a phone drops a
/// frame. `tool/README.md` has the commands and `docs/RELEASE.md` the
/// table the device numbers go in.
library;

// ignore_for_file: avoid_print — this is a CLI report; printing the
// table is the whole point of running it.

import 'dart:convert';

import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_response_parser.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/tenbis/tenbis_menu_mapper.dart';
import 'package:ketoclub/services/menu/wolt/wolt_menu_mapper.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// The per-step budget for decoding and mapping a menu payload on the
/// main thread, in milliseconds: one frame at 60 Hz. Issue #65 moves a
/// step to `compute` when a phone measurement exceeds it.
const double mappingBudgetMs = 16;

/// The dish count issue #65 measures against.
const int defaultDishCount = 60;

/// The fixed instant every timed call is stamped with, so no step reads
/// the wall clock inside a measurement.
final DateTime _fixedNow = DateTime.utc(2026);

/// Which platform mapper a [PerfFixture]'s payload is fed to.
enum PerfPayloadFormat {
  /// A Wolt `menu/data` payload, mapped by `WoltMenuMapper`.
  wolt,

  /// A 10bis `Menu` payload, mapped by `TenBisMenuMapper`.
  tenbis,
}

/// One checked-in fixture to time decode + map over, in addition to the
/// synthetic 60-dish payloads [runMenuPerf] always times.
final class PerfFixture {
  /// Creates a fixture named [name] holding [json] in [format].
  const new({required this.name, required this.format, required this.json});

  /// A short label for the table, e.g. the fixture's file name.
  final String name;

  /// Which mapper [json] is fed to.
  final PerfPayloadFormat format;

  /// The raw payload text, exactly as it would arrive over HTTP.
  final String json;
}

/// The timing of one step, over [runs] measured calls after a warm-up.
final class PerfResult {
  /// Creates a result for the step [label] over a [dishCount]-dish menu.
  const new({
    required this.label,
    required this.dishCount,
    required this.runs,
    required this.medianMs,
    required this.maxMs,
    this.budgetMs,
  });

  /// What was timed, e.g. `decode + map (Wolt, synthetic)`.
  final String label;

  /// How many dishes the menu this step ran over held.
  final int dishCount;

  /// How many measured calls [medianMs] and [maxMs] summarise.
  final int runs;

  /// The median wall time of one call, in milliseconds.
  final double medianMs;

  /// The slowest single call, in milliseconds.
  final double maxMs;

  /// The budget this step is held to, or null when issue #65 sets none
  /// for it (the step is reported for information only).
  final double? budgetMs;

  /// Whether the median exceeds [budgetMs]; false when there is none.
  bool get overBudget {
    final budget = budgetMs;
    return budget != null && medianMs > budget;
  }
}

/// English dish names and descriptions cycled through the synthetic
/// menus, chosen so the rules engine sees all three verdicts and option
/// text, as a real menu would give it.
const List<(String, String)> _englishDishes = <(String, String)>[
  ('Grilled Salmon', 'With lemon butter and grilled asparagus'),
  ('Prime Entrecôte 300g', 'Served with potato purée and baby carrots'),
  ('Spaghetti Carbonara', 'Guanciale, egg yolk, pecorino'),
  ('Caesar Salad', 'Romaine, parmesan, croutons, anchovy dressing'),
  ('Chicken Teriyaki', 'Glazed thigh with steamed rice'),
  ('Margherita Pizza', 'Tomato, mozzarella, basil'),
];

/// Hebrew dish names and descriptions, so Hebrew vocabulary is timed
/// too (architecture.md §12).
const List<(String, String)> _hebrewDishes = <(String, String)>[
  ('סטייק אנטריקוט', 'מוגש עם צ׳יפס וסלט ירוק'),
  ('סלמון בתנור', 'עם ירקות צלויים ורוטב חמאה'),
  ('פסטה ברוטב שמנת', 'פטריות, שמנת ופרמזן'),
  ('סלט יווני', 'עגבניות, מלפפון, זיתים ופטה'),
];

/// The option group every third synthetic dish carries: a side choice,
/// where a dish's yellow-ness often lives.
const String _sideGroupName = 'Choice of Side';

/// The values of [_sideGroupName].
const List<String> _sideValues = <String>['Fries', 'Green Salad', 'Rice'];

/// The name and description of synthetic dish [index].
(String, String) _dishText(int index) {
  // Every fourth dish is Hebrew, so both vocabularies are exercised.
  if (index % 4 == 3) return _hebrewDishes[index ~/ 4 % _hebrewDishes.length];
  return _englishDishes[index % _englishDishes.length];
}

/// Whether synthetic dish [index] carries the side-choice option group.
bool _hasSides(int index) => index % 3 == 0;

/// How many categories the [dishCount] synthetic dishes are spread over.
int _categoryCount(int dishCount) => dishCount < 6 ? 1 : 6;

/// A Wolt `menu/data` payload holding [dishCount] dishes in the shape
/// `WoltMenuMapper` reads: flat `categories`, `items` and `options`
/// joined by id, prices in agorot.
Map<String, Object?> syntheticWoltPayload({int dishCount = defaultDishCount}) {
  final categoryCount = _categoryCount(dishCount);
  final itemIdsByCategory = List.generate(categoryCount, (_) => <String>[]);
  final items = <Map<String, Object?>>[];
  for (var i = 0; i < dishCount; i++) {
    final (name, description) = _dishText(i);
    final id = 'dish_$i';
    itemIdsByCategory[i % categoryCount].add(id);
    items.add(<String, Object?>{
      'id': id,
      'name': '$name #$i',
      'description': description,
      'price': 4200 + i * 100,
      'options': <String>[if (_hasSides(i)) 'opt_sides'],
      'image': 'https://example.invalid/dish_$i.jpg',
    });
  }
  return <String, Object?>{
    'currency': 'ILS',
    'categories': <Map<String, Object?>>[
      for (var c = 0; c < categoryCount; c++)
        <String, Object?>{
          'id': 'cat_$c',
          'name': 'Category $c',
          'item_ids': itemIdsByCategory[c],
        },
    ],
    'items': items,
    'options': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'opt_sides',
        'name': _sideGroupName,
        'values': <Map<String, Object?>>[
          for (final (i, value) in _sideValues.indexed)
            <String, Object?>{'id': 'val_$i', 'name': value, 'price': 0},
        ],
      },
    ],
  };
}

/// A 10bis `Menu` payload holding [dishCount] dishes in the shape
/// `TenBisMenuMapper` reads: `categoriesList` with nested `dishList`s,
/// decimal prices and inline `dishOptionsList`s.
Map<String, Object?> syntheticTenBisPayload({
  int dishCount = defaultDishCount,
}) {
  final categoryCount = _categoryCount(dishCount);
  final dishesByCategory = List.generate(
    categoryCount,
    (_) => <Map<String, Object?>>[],
  );
  for (var i = 0; i < dishCount; i++) {
    final (name, description) = _dishText(i);
    dishesByCategory[i % categoryCount].add(<String, Object?>{
      'dishId': 1000 + i,
      'dishName': '$name #$i',
      'dishDescription': description,
      'price': 42.0 + i,
      'dishImageUrl': 'https://example.invalid/dish_$i.jpg',
      'dishOptionsList': <Map<String, Object?>>[
        if (_hasSides(i))
          <String, Object?>{
            'name': _sideGroupName,
            'values': <Map<String, Object?>>[
              for (final value in _sideValues) <String, Object?>{'name': value},
            ],
          },
      ],
    });
  }
  return <String, Object?>{
    'restaurantName': 'Synthetic Venue',
    'categoriesList': <Map<String, Object?>>[
      for (var c = 0; c < categoryCount; c++)
        <String, Object?>{
          'categoryName': 'Category $c',
          'dishList': dishesByCategory[c],
        },
    ],
  };
}

/// An AI reply body placing every dish on [menu], in the shape
/// `MenuResponseParser` accepts: alternately safe as-is and not keto,
/// so the parser's verdict handling runs rather than a trivial path.
String syntheticReplyBody(Menu menu) => jsonEncode(<String, Object?>{
  'dishes': <Map<String, Object?>>[
    for (final (i, dish) in menu.allDishes.indexed)
      <String, Object?>{
        'id': dish.id,
        'name': dish.name,
        'verdict': i.isEven ? 'orderAsIs' : 'nonKeto',
        'why': 'Synthetic verdict for the performance harness.',
        'modification': null,
        'net_carbs_estimate': null,
      },
  ],
});

/// A [Clock] frozen at [_fixedNow], so the rules engine reads no wall
/// clock during a measurement.
final class _FixedClock implements Clock {
  const new();

  @override
  DateTime now() => _fixedNow;
}

/// Decodes [json] and maps it with the mapper for [format], returning
/// the menu; throws [StateError] if the mapper rejects it, since a
/// harness timing a failure path would report a meaningless number.
Menu decodeAndMap(String json, PerfPayloadFormat format) {
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, Object?>) {
    throw StateError('payload is not a JSON object');
  }
  final ref = VenueRef(
    source: switch (format) {
      PerfPayloadFormat.wolt => MenuSource.wolt,
      PerfPayloadFormat.tenbis => MenuSource.tenbis,
    },
    platformId: 'perf-harness',
  );
  final result = switch (format) {
    PerfPayloadFormat.wolt => WoltMenuMapper.toMenu(
      decoded,
      ref: ref,
      fetchedAt: _fixedNow,
    ),
    PerfPayloadFormat.tenbis => TenBisMenuMapper.toMenu(
      decoded,
      ref: ref,
      fetchedAt: _fixedNow,
    ),
  };
  return switch (result) {
    MenuFetched(:final menu) => menu,
    MenuFetchFailed(:final reason) => throw StateError(
      'the ${format.name} mapper rejected the payload: $reason',
    ),
  };
}

/// Times [body] [runs] times after [warmup] untimed calls, returning the
/// median and maximum in milliseconds.
Future<(double, double)> _time(
  Future<void> Function() body, {
  required int runs,
  required int warmup,
}) async {
  for (var i = 0; i < warmup; i++) {
    await body();
  }
  final samples = <double>[];
  final stopwatch = Stopwatch();
  for (var i = 0; i < runs; i++) {
    stopwatch
      ..reset()
      ..start();
    await body();
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds / 1000);
  }
  samples.sort();
  return (samples[samples.length ~/ 2], samples.last);
}

/// Runs every measurement and returns one [PerfResult] per step, in the
/// order the table prints them.
///
/// Always times the synthetic [dishCount]-dish Wolt and 10bis payloads,
/// then each of [fixtures] (decode + map only), then fingerprinting, the
/// rules engine and the reply parser over the synthetic Wolt menu.
/// [runs] measured calls follow [warmup] untimed ones for every step, so
/// the JIT's first-call compilation is not billed to the first sample.
Future<List<PerfResult>> runMenuPerf({
  List<PerfFixture> fixtures = const <PerfFixture>[],
  int dishCount = defaultDishCount,
  int runs = 50,
  int warmup = 5,
}) async {
  if (runs < 1) throw ArgumentError.value(runs, 'runs', 'must be positive');
  final results = <PerfResult>[];

  Future<void> timeMapping(
    String label,
    String json,
    PerfPayloadFormat format,
  ) async {
    // Mapped once untimed, both to fail fast on a bad payload and to
    // learn its dish count for the table.
    final menu = decodeAndMap(json, format);
    final (median, max) = await _time(
      () async => decodeAndMap(json, format),
      runs: runs,
      warmup: warmup,
    );
    results.add(
      PerfResult(
        label: label,
        dishCount: menu.allDishes.length,
        runs: runs,
        medianMs: median,
        maxMs: max,
        budgetMs: mappingBudgetMs,
      ),
    );
  }

  final woltJson = jsonEncode(syntheticWoltPayload(dishCount: dishCount));
  final tenbisJson = jsonEncode(syntheticTenBisPayload(dishCount: dishCount));
  await timeMapping(
    'decode + map (Wolt, synthetic)',
    woltJson,
    PerfPayloadFormat.wolt,
  );
  await timeMapping(
    'decode + map (10bis, synthetic)',
    tenbisJson,
    PerfPayloadFormat.tenbis,
  );
  for (final fixture in fixtures) {
    await timeMapping(
      'decode + map (${fixture.name})',
      fixture.json,
      fixture.format,
    );
  }

  final menu = decodeAndMap(woltJson, PerfPayloadFormat.wolt);
  final menuDishes = menu.allDishes.length;

  final (fingerprintMedian, fingerprintMax) = await _time(
    () async => TextNormaliser.menuFingerprint(menu),
    runs: runs,
    warmup: warmup,
  );
  results.add(
    PerfResult(
      label: 'fingerprint',
      dishCount: menuDishes,
      runs: runs,
      medianMs: fingerprintMedian,
      maxMs: fingerprintMax,
    ),
  );

  const classifier = HeuristicMenuClassifier(clock: _FixedClock());
  final (rulesMedian, rulesMax) = await _time(
    () => classifier.classify(menu),
    runs: runs,
    warmup: warmup,
  );
  results.add(
    PerfResult(
      label: 'rules engine',
      dishCount: menuDishes,
      runs: runs,
      medianMs: rulesMedian,
      maxMs: rulesMax,
    ),
  );

  final reply = syntheticReplyBody(menu);
  const engine = LlmEngine(model: 'perf-harness');
  final (parseMedian, parseMax) = await _time(
    () async => MenuResponseParser.parse(
      reply,
      source: menu,
      analysedAt: _fixedNow,
      engine: engine,
    ),
    runs: runs,
    warmup: warmup,
  );
  results.add(
    PerfResult(
      label: 'reply parse',
      dishCount: menuDishes,
      runs: runs,
      medianMs: parseMedian,
      maxMs: parseMax,
      budgetMs: mappingBudgetMs,
    ),
  );

  return results;
}

/// Renders [results] as a fixed-width text table, one row per step, with
/// an `OVER` marker on any row whose median exceeds its budget.
String formatPerfTable(List<PerfResult> results) {
  String ms(double value) => value.toStringAsFixed(2);
  final labelWidth = results.fold<int>(
    'step'.length,
    (width, r) => r.label.length > width ? r.label.length : width,
  );
  final buffer = StringBuffer()
    ..writeln(
      '${'step'.padRight(labelWidth)}  dishes  runs  '
      'median ms  max ms  budget ms',
    );
  for (final r in results) {
    final budget = r.budgetMs;
    final budgetCell = budget == null ? '-' : ms(budget);
    buffer.writeln(
      '${r.label.padRight(labelWidth)}  '
      '${'${r.dishCount}'.padLeft(6)}  '
      '${'${r.runs}'.padLeft(4)}  '
      '${ms(r.medianMs).padLeft(9)}  '
      '${ms(r.maxMs).padLeft(6)}  '
      '${budgetCell.padLeft(9)}'
      '${r.overBudget ? '  OVER' : ''}',
    );
  }
  return buffer.toString();
}

/// Times the synthetic 60-dish menus and prints the table.
///
/// Run on a device with `flutter run --profile -t tool/perf_menu.dart`;
/// on the host, `flutter test test/tool/perf_menu_test.dart` prints the
/// same table with the checked-in fixtures added. The screen stays blank
/// on a device: this entry point never calls `runApp`, it only prints.
Future<void> main() async {
  final results = await runMenuPerf();
  print(formatPerfTable(results));
  final over = results.where((r) => r.overBudget).toList();
  print(
    over.isEmpty
        ? 'perf_menu: every budgeted step is within '
              '${mappingBudgetMs.toStringAsFixed(0)} ms.'
        : 'perf_menu: over budget: '
              '${over.map((r) => r.label).join(', ')}. '
              'Only a --profile run on a device decides a move to compute.',
  );
}
