/// Tests for `tool/perf_menu.dart`, the issue #65 performance harness.
///
/// The harness has to run under `flutter test` (see its own doc comment
/// for why `dart run` cannot load it), and issue #65 asks for exactly
/// that: it runs here over the checked-in fixtures, and one test prints
/// the table so `flutter test test/tool/perf_menu_test.dart` doubles as
/// the host-side way to read it. No test asserts a duration: host JIT
/// timings say nothing about a phone, and a timing assertion would only
/// make CI flaky. The device numbers are recorded by hand in
/// `docs/RELEASE.md`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_response_parser.dart';

import '../../tool/perf_menu.dart' as perf;
import '../fakes/fake_clock.dart';

/// Reads the checked-in fixture [fileName] from `test/fixtures/`.
String _fixture(String fileName) =>
    File('test/fixtures/$fileName').readAsStringSync();

/// The two well-formed platform fixtures, as the harness takes them.
List<perf.PerfFixture> _fixtures() => <perf.PerfFixture>[
  perf.PerfFixture(
    name: 'wolt_hamosad_menu.json',
    format: perf.PerfPayloadFormat.wolt,
    json: _fixture('wolt_hamosad_menu.json'),
  ),
  perf.PerfFixture(
    name: 'tenbis_synthetic_menu.json',
    format: perf.PerfPayloadFormat.tenbis,
    json: _fixture('tenbis_synthetic_menu.json'),
  ),
];

void main() {
  group('perf_menu synthetic payloads', () {
    test('syntheticWoltPayload maps to the default 60 dishes through '
        'WoltMenuMapper', () {
      // Act
      final menu = perf.decodeAndMap(
        jsonEncode(perf.syntheticWoltPayload()),
        perf.PerfPayloadFormat.wolt,
      );

      // Assert
      expect(perf.defaultDishCount, 60);
      expect(menu.allDishes, hasLength(60));
      expect(
        menu.allDishes.where((dish) => dish.options.isNotEmpty),
        hasLength(20),
      );
    });

    test('syntheticTenBisPayload maps to the default 60 dishes through '
        'TenBisMenuMapper', () {
      // Act
      final menu = perf.decodeAndMap(
        jsonEncode(perf.syntheticTenBisPayload()),
        perf.PerfPayloadFormat.tenbis,
      );

      // Assert
      expect(menu.allDishes, hasLength(60));
      expect(menu.venueName, 'Synthetic Venue');
    });

    test('a smaller dishCount is honoured by both payloads', () {
      // Act
      final wolt = perf.decodeAndMap(
        jsonEncode(perf.syntheticWoltPayload(dishCount: 4)),
        perf.PerfPayloadFormat.wolt,
      );
      final tenbis = perf.decodeAndMap(
        jsonEncode(perf.syntheticTenBisPayload(dishCount: 4)),
        perf.PerfPayloadFormat.tenbis,
      );

      // Assert
      expect(wolt.allDishes, hasLength(4));
      expect(tenbis.allDishes, hasLength(4));
    });

    test('the synthetic menu gives the rules engine all three verdicts, so '
        'the harness times real vocabulary work', () async {
      // Arrange
      final menu = perf.decodeAndMap(
        jsonEncode(perf.syntheticWoltPayload()),
        perf.PerfPayloadFormat.wolt,
      );
      final classifier = HeuristicMenuClassifier(
        clock: FakeClock(DateTime.utc(2026)),
      );

      // Act
      final result = await classifier.classify(menu);

      // Assert
      final analysed = result as MenuAnalysed;
      expect(analysed.dishes, hasLength(60));
      expect(
        analysed.dishes.map((dish) => dish.verdict).toSet(),
        containsAll(DishVerdict.values),
      );
    });

    test('syntheticReplyBody is a reply MenuResponseParser accepts for '
        'every dish', () {
      // Arrange
      final menu = perf.decodeAndMap(
        jsonEncode(perf.syntheticWoltPayload()),
        perf.PerfPayloadFormat.wolt,
      );

      // Act
      final result = MenuResponseParser.parse(
        perf.syntheticReplyBody(menu),
        source: menu,
        analysedAt: DateTime.utc(2026),
        engine: const LlmEngine(model: 'perf-harness'),
      );

      // Assert
      final analysed = result as MenuAnalysed;
      expect(analysed.dishes, hasLength(60));
      expect(analysed.unclassified, isEmpty);
    });
  });

  group('perf_menu decodeAndMap', () {
    test('throws StateError when the mapper rejects the payload, rather '
        'than timing a failure path', () {
      // Act & Assert
      expect(
        () => perf.decodeAndMap(
          _fixture('wolt_malformed_menu.json'),
          perf.PerfPayloadFormat.wolt,
        ),
        throwsStateError,
      );
    });

    test('throws StateError when the payload is not a JSON object', () {
      // Act & Assert
      expect(
        () => perf.decodeAndMap('[]', perf.PerfPayloadFormat.tenbis),
        throwsStateError,
      );
    });
  });

  group('perf_menu runMenuPerf', () {
    test('times every step over the checked-in fixtures and prints the '
        'table', () async {
      // Act
      final results = await perf.runMenuPerf(
        fixtures: _fixtures(),
        runs: 3,
        warmup: 1,
      );

      // Assert
      expect(results.map((r) => r.label), [
        'decode + map (Wolt, synthetic)',
        'decode + map (10bis, synthetic)',
        'decode + map (wolt_hamosad_menu.json)',
        'decode + map (tenbis_synthetic_menu.json)',
        'fingerprint',
        'rules engine',
        'reply parse',
      ]);
      for (final result in results) {
        expect(result.runs, 3);
        expect(result.dishCount, greaterThan(0));
        expect(result.medianMs, greaterThanOrEqualTo(0));
        expect(result.maxMs, greaterThanOrEqualTo(result.medianMs));
      }
      expect(results.first.dishCount, 60);
      expect(results.last.dishCount, 60);
      // Only the JSON steps carry the issue's 16 ms budget.
      expect(
        results.where((r) => r.budgetMs != null).map((r) => r.label),
        isNot(contains('fingerprint')),
      );
      expect(results.last.budgetMs, perf.mappingBudgetMs);

      // The host-side way to read the table (see this file's doc comment).
      // ignore: avoid_print, printing the table is this test's other job.
      print(perf.formatPerfTable(results));
    });

    test('rejects a non-positive run count', () async {
      // Act & Assert
      await expectLater(perf.runMenuPerf(runs: 0), throwsArgumentError);
    });
  });

  group('perf_menu formatPerfTable', () {
    test('prints a header, one line per result, a dash for no budget and '
        'OVER for a median past its budget', () {
      // Arrange
      const results = <perf.PerfResult>[
        perf.PerfResult(
          label: 'within',
          dishCount: 60,
          runs: 5,
          medianMs: 1.5,
          maxMs: 2,
          budgetMs: 16,
        ),
        perf.PerfResult(
          label: 'over',
          dishCount: 60,
          runs: 5,
          medianMs: 20,
          maxMs: 25,
          budgetMs: 16,
        ),
        perf.PerfResult(
          label: 'unbudgeted',
          dishCount: 60,
          runs: 5,
          medianMs: 30,
          maxMs: 31,
        ),
      ];

      // Act
      final lines = perf.formatPerfTable(results).trimRight().split('\n');

      // Assert
      expect(lines, hasLength(4));
      expect(lines.first, contains('median ms'));
      expect(lines[1], allOf(contains('1.50'), isNot(contains('OVER'))));
      expect(lines[2], endsWith('OVER'));
      expect(lines[3], allOf(contains('-'), isNot(contains('OVER'))));
      expect(results[1].overBudget, isTrue);
      expect(results[2].overBudget, isFalse);
    });
  });

  group('perf_menu main', () {
    test('prints the table and a budget verdict line', () async {
      // Arrange
      final printed = <String>[];

      // Act
      await runZoned(
        perf.main,
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );

      // Assert
      final output = printed.join('\n');
      expect(output, contains('decode + map (Wolt, synthetic)'));
      expect(output, contains('reply parse'));
      expect(output, contains('perf_menu: '));
    });
  });
}
