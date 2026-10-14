/// The keto-only baseline (epic "Principles", rule 1; issue #342).
///
/// A keto-only profile is today's app, byte for byte: the prompt, the
/// response schemas, the cache-key material, the rule engine's verdicts,
/// the keto score, the verdict copy and the share text. Every one of them
/// is rebuilt here from the real code and compared, as text, with a
/// hand-edited file under `test/fixtures/keto_baseline/`.
///
/// There is deliberately **no** update switch (unlike
/// `golden_drift_test.dart`): a drift must arrive as a reviewed diff to a
/// fixture, never as a regenerated one. When a keto change is intended,
/// edit the fixture by hand in the same pull request
/// (`test/fixtures/keto_baseline/README.md`).
///
/// The `with bantoMode: true` group is the second layer: every seam that
/// takes a `bantoMode` parameter must still produce the same keto-only
/// fixture with it switched on. Later waves add their seams there.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_analysis_prompt.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_response_parser.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/utils/keto_score.dart';
import 'package:ketoclub/utils/menu_share_text.dart';
import 'package:ketoclub/utils/verdict_counts.dart';
import 'package:ketoclub/widgets/route_title.dart';

import '../../tool/golden/golden_corpus.dart';
import '../fakes/fake_clock.dart';

/// Where the hand-edited baseline files live.
const String _fixtureDirectory = 'test/fixtures/keto_baseline';

/// The settings with every "Your keto rules" toggle on and the lowest
/// net-carb limit: golden_export.dart's `allRules_limit2` option set,
/// reached through the real `fromSettings` path. AI consent stays at its
/// default, given, as on a fresh install.
const AppSettings _allRulesLimit2Settings = AppSettings(
  seedOilFree: true,
  dairyFree: true,
  carnivoreOnly: true,
  netCarbLimitGrams: 2,
);

/// golden_export.dart's `defaults` option set.
const ClassificationOptions _defaults = ClassificationOptions();

/// golden_export.dart's `allRules_limit2` option set, built from
/// [_allRulesLimit2Settings].
final ClassificationOptions _allRulesLimit2 =
    ClassificationOptions.fromSettings(_allRulesLimit2Settings);

/// The two option sets the rules-verdict fixtures are written under, by
/// the name used in their file names.
final Map<String, ClassificationOptions> _optionSets =
    <String, ClassificationOptions>{
      'defaults': _defaults,
      'all_rules_limit2': _allRulesLimit2,
    };

/// The ARB keys whose copy names a verdict to the user: the pill, the
/// counter tiles and the legend.
const List<String> _copyKeys = <String>[
  'verdictOrderAsIs',
  'verdictModifiable',
  'verdictNonKeto',
  'tileGreenLabel',
  'tileYellowLabel',
  'tileRedLabel',
  'legendToggle',
  'legendHide',
  'legendNote',
  'legendEngines',
  'legendFoodOnly',
  'legendBudget',
];

/// Every fixture this test reads, so a stray or missing file is caught.
final List<String> _fixtureNames = <String>[
  'system_prompt_defaults.txt',
  'system_prompt_all_rules_limit2.txt',
  'vision_system_prompt_defaults_2_pages.txt',
  'response_schema.json',
  'vision_response_schema.json',
  'options_snapshot_defaults.json',
  'options_snapshot_all_rules_limit2.json',
  'app_settings_defaults.json',
  'document_title.txt',
  for (final menu in goldenHandBuiltMenus.keys)
    for (final options in _optionSets.keys) 'rules_${menu}_$options.json',
  'copy_en.json',
  'copy_he.json',
  'share_text_english.txt',
  'share_text_hebrew.txt',
];

/// [value] as canonical JSON: keys sorted at every depth, two-space
/// indent — the form the backend's cache key hashes (`sort_keys=True`).
String _canonicalJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(_sorted(value));

Object? _sorted(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{for (final key in keys) key: _sorted(value[key])};
  }
  if (value is List) return <Object?>[for (final item in value) _sorted(item)];
  return value;
}

/// The first line on which [fixture] and [actual] differ, both shown, so
/// a failure names the drift without a byte-offset hunt.
String _firstDifference(String fixture, String actual) {
  final expectedLines = fixture.split('\n');
  final actualLines = actual.split('\n');
  final count = expectedLines.length > actualLines.length
      ? expectedLines.length
      : actualLines.length;
  for (var i = 0; i < count; i++) {
    final want = i < expectedLines.length ? expectedLines[i] : '<no line>';
    final got = i < actualLines.length ? actualLines[i] : '<no line>';
    if (want != got) {
      return 'first difference at line ${i + 1}:\n'
          '  fixture: $want\n'
          '  actual:  $got';
    }
  }
  return 'no line differs';
}

/// Asserts that [actual], plus the one trailing newline every fixture
/// file ends with, equals the fixture [name] byte for byte.
void _expectFixture(String name, String actual) {
  final file = File('$_fixtureDirectory/$name');
  expect(
    file.existsSync(),
    isTrue,
    reason:
        '$name is missing; write it by hand '
        '($_fixtureDirectory/README.md)',
  );
  final fixture = file.readAsStringSync();
  final text = '$actual\n';
  expect(
    text,
    fixture,
    reason:
        '$name drifted from the keto-only baseline; '
        '${_firstDifference(fixture, text)}\n'
        'If the keto change is intended, edit the fixture by hand in the '
        'same pull request ($_fixtureDirectory/README.md).',
  );
}

/// The rule engine's analysis of [menu] under [options], at a fixed time.
Future<MenuAnalysed> _rulesAnalysis(
  Menu menu,
  ClassificationOptions options,
) async {
  final classifier = HeuristicMenuClassifier(clock: FakeClock(goldenNow));
  final result = await classifier.classify(menu, options: options);
  return switch (result) {
    final MenuAnalysed analysed => analysed,
    MenuAnalysisFailed() => throw StateError('the rules never fail'),
  };
}

/// [analysis] as JSON without `analysedAt`, which records the clock and
/// not the verdicts.
Map<String, Object?> _verdictJson(MenuAnalysed analysis) =>
    analysis.toJson()..remove('analysedAt');

/// The verdict copy of [locale], by ARB key.
Map<String, String> _copyFor(Locale locale) {
  final l10n = lookupAppLocalizations(locale);
  final byKey = <String, String>{
    'verdictOrderAsIs': l10n.verdictOrderAsIs,
    'verdictModifiable': l10n.verdictModifiable,
    'verdictNonKeto': l10n.verdictNonKeto,
    'tileGreenLabel': l10n.tileGreenLabel,
    'tileYellowLabel': l10n.tileYellowLabel,
    'tileRedLabel': l10n.tileRedLabel,
    'legendToggle': l10n.legendToggle,
    'legendHide': l10n.legendHide,
    'legendNote': l10n.legendNote,
    'legendEngines': l10n.legendEngines,
    'legendFoodOnly': l10n.legendFoodOnly,
    'legendBudget': l10n.legendBudget,
  };
  expect(byKey.keys.toList(), _copyKeys);
  return byKey;
}

/// A seam that takes a `bantoMode` parameter, paired with the keto-only
/// fixture it must still produce with `bantoMode: true`.
typedef _BantoSeam = ({
  String fixture,
  String Function({required bool bantoMode}) build,
});

/// The second layer: every seam that takes `bantoMode`, or that Banto
/// touches, with the keto-only fixture it must still build. Each later
/// wave adds its seam here, e.g. the system prompt once `systemPrompt`
/// takes `bantoMode`, against `system_prompt_defaults.txt`.
///
/// The first two (ALG-02a, issue #344): the document title a build without
/// the define shows, and the settings record with an explicitly empty
/// dietary profile, which must store exactly what a keto-only install
/// stored before the profile existed.
/// The options [fromSettings][ClassificationOptions.fromSettings] builds
/// with a keto-only profile (none, or keto alone), the way the menu
/// screen builds them (ALG-03, D26 C2).
ClassificationOptions _ketoOnlyOptions({
  required bool bantoMode,
  required bool withKetoEntry,
}) => ClassificationOptions.fromSettings(
  const AppSettings().copyWith(
    profile: withKetoEntry
        ? DietaryProfile.empty.withEntry(RestrictionId.keto)
        : DietaryProfile.empty,
  ),
  bantoMode: bantoMode,
);

final List<_BantoSeam> _bantoSeams = <_BantoSeam>[
  (
    fixture: 'document_title.txt',
    // `app` defaults to BantoMode.appName, the build's display name.
    build: ({required bool bantoMode}) => documentTitle(null),
  ),
  (
    fixture: 'app_settings_defaults.json',
    // Through copyWith, so the empty profile is set explicitly rather than
    // left at the constructor's default.
    build: ({required bool bantoMode}) => _canonicalJson(
      const AppSettings().copyWith(profile: DietaryProfile.empty).toJson(),
    ),
  ),
  // ALG-03 (#345): a keto-only profile — empty, or keto alone — asks for
  // no extraction, so the prompt, both schemas and the cache-key snapshot
  // the menu screen builds through fromSettings are today's.
  for (final withKetoEntry in <bool>[false, true]) ...<_BantoSeam>[
    (
      fixture: 'system_prompt_defaults.txt',
      build: ({required bool bantoMode}) => MenuAnalysisPrompt.systemPrompt(
        options: _ketoOnlyOptions(
          bantoMode: bantoMode,
          withKetoEntry: withKetoEntry,
        ),
      ),
    ),
    (
      fixture: 'vision_system_prompt_defaults_2_pages.txt',
      build: ({required bool bantoMode}) =>
          MenuAnalysisPrompt.visionSystemPrompt(
            pageCount: 2,
            options: _ketoOnlyOptions(
              bantoMode: bantoMode,
              withKetoEntry: withKetoEntry,
            ),
          ),
    ),
    (
      fixture: 'response_schema.json',
      build: ({required bool bantoMode}) => _canonicalJson(
        MenuAnalysisPrompt.responseSchema(
          extract: _ketoOnlyOptions(
            bantoMode: bantoMode,
            withKetoEntry: withKetoEntry,
          ).restrictionsRequested,
        ),
      ),
    ),
    (
      fixture: 'vision_response_schema.json',
      build: ({required bool bantoMode}) => _canonicalJson(
        MenuAnalysisPrompt.visionResponseSchema(
          extract: _ketoOnlyOptions(
            bantoMode: bantoMode,
            withKetoEntry: withKetoEntry,
          ).restrictionsRequested,
        ),
      ),
    ),
    (
      fixture: 'options_snapshot_defaults.json',
      build: ({required bool bantoMode}) => _canonicalJson(
        _ketoOnlyOptions(
          bantoMode: bantoMode,
          withKetoEntry: withKetoEntry,
        ).snapshot.toJson(),
      ),
    ),
  ],
];

void main() {
  group('the baseline folder', () {
    test('holds exactly the fixtures this test reads, plus README', () {
      // Act
      final onDisk = <String>[
        for (final entity in Directory(_fixtureDirectory).listSync())
          if (entity is File) entity.uri.pathSegments.last,
      ]..sort();

      // Assert
      expect(onDisk, <String>[..._fixtureNames, 'README.md']..sort());
    });
  });

  group('the system prompt', () {
    test('with default options is unchanged', () {
      // Act
      final prompt = MenuAnalysisPrompt.systemPrompt();

      // Assert
      _expectFixture('system_prompt_defaults.txt', prompt);
    });

    test('with every keto rule and a 2 g limit is unchanged', () {
      // Act
      final prompt = MenuAnalysisPrompt.systemPrompt(options: _allRulesLimit2);

      // Assert
      _expectFixture('system_prompt_all_rules_limit2.txt', prompt);
    });

    test('for two vision pages with default options is unchanged', () {
      // Act
      final prompt = MenuAnalysisPrompt.visionSystemPrompt(pageCount: 2);

      // Assert
      _expectFixture('vision_system_prompt_defaults_2_pages.txt', prompt);
    });
  });

  group('the response schemas', () {
    test('responseSchema is unchanged', () {
      // Act
      final schema = _canonicalJson(MenuAnalysisPrompt.responseSchema());

      // Assert
      _expectFixture('response_schema.json', schema);
    });

    test('visionResponseSchema is unchanged', () {
      // Act
      final schema = _canonicalJson(MenuAnalysisPrompt.visionResponseSchema());

      // Assert
      _expectFixture('vision_response_schema.json', schema);
    });
  });

  group('the schema version', () {
    test('stays 1', () {
      // Assert: contract decision C3 — new dish fields are read
      // tolerantly, so this never changes for Banto; a bump would
      // re-analyse every keto cache and lose scanned pages (D22).
      expect(MenuResponseParser.schemaVersion, 1);
    });
  });

  group('the cache-key material', () {
    test('the default options snapshot is unchanged', () {
      // Act
      final json = _canonicalJson(_defaults.snapshot.toJson());

      // Assert
      _expectFixture('options_snapshot_defaults.json', json);
    });

    test('the every-rule, 2 g options snapshot is unchanged', () {
      // Act
      final json = _canonicalJson(_allRulesLimit2.snapshot.toJson());

      // Assert
      _expectFixture('options_snapshot_all_rules_limit2.json', json);
    });

    test('fromSettings gives the golden allRules_limit2 snapshot', () {
      // Arrange: golden_export.dart's option set, rebuilt by value.
      final golden = ClassificationOptions(
        netCarbLimitGrams: 2,
        dietaryConstraints: ClassificationOptions.dietaryConstraintsFor(
          seedOilFree: true,
          dairyFree: true,
          carnivoreOnly: true,
        ),
      );

      // Assert
      expect(_allRulesLimit2.snapshot, golden.snapshot);
    });

    test('the default settings are unchanged', () {
      // Act
      final json = _canonicalJson(const AppSettings().toJson());

      // Assert
      _expectFixture('app_settings_defaults.json', json);
    });

    test('the default settings write no dietaryProfile key', () {
      // Act
      final json = const AppSettings().toJson();

      // Assert: an empty profile is never written (ALG-02a, issue #344),
      // so a keto-only install's stored record does not change.
      expect(json.containsKey('dietaryProfile'), isFalse);
    });
  });

  group('the rule engine verdicts', () {
    for (final menu in goldenHandBuiltMenus.entries) {
      for (final options in _optionSets.entries) {
        final name = 'rules_${menu.key}_${options.key}.json';
        test(
          'over the ${menu.key} menu, ${options.key}, are unchanged',
          () async {
            // Act
            final analysis = await _rulesAnalysis(menu.value, options.value);

            // Assert
            _expectFixture(name, _canonicalJson(_verdictJson(analysis)));
          },
        );
      }
    }
  });

  group('the keto score', () {
    // (green, hidden-carb yellow, other yellow, red) → score, computed
    // once from today's weights and written here by hand.
    const table =
        <({int green, int hidden, int other, int red, double? score})>[
          (green: 0, hidden: 0, other: 0, red: 0, score: null),
          (green: 1, hidden: 0, other: 0, red: 0, score: 10.0),
          (green: 0, hidden: 0, other: 0, red: 1, score: 0.0),
          (green: 0, hidden: 0, other: 1, red: 0, score: 5.0),
          (green: 0, hidden: 1, other: 0, red: 0, score: 2.5),
          (green: 1, hidden: 1, other: 1, red: 1, score: 4.4),
          (green: 2, hidden: 0, other: 1, red: 0, score: 8.3),
          (green: 1, hidden: 0, other: 2, red: 0, score: 6.7),
          (green: 1, hidden: 0, other: 0, red: 2, score: 3.3),
          (green: 3, hidden: 0, other: 1, red: 3, score: 5.0),
          (green: 5, hidden: 2, other: 3, red: 4, score: 5.0),
        ];

    for (final row in table) {
      test('is ${row.score} for ${row.green}/${row.hidden}/${row.other}/'
          '${row.red}', () {
        // Act
        final score = ketoScore(
          greenCount: row.green,
          hiddenCarbYellowCount: row.hidden,
          otherYellowCount: row.other,
          redCount: row.red,
        );

        // Assert
        expect(score, row.score);
      });
    }

    test('the English menu counts and scores are unchanged', () async {
      // Arrange
      final analysis = await _rulesAnalysis(goldenEnglishMenu, _defaults);

      // Act
      final counts = VerdictCounts.of(goldenEnglishMenu, analysis);

      // Assert
      expect(
        counts,
        const VerdictCounts(green: 4, yellow: 5, hiddenCarbYellow: 0, red: 3),
      );
      expect(counts.score, 5.4);
    });
  });

  group('the verdict copy', () {
    for (final tag in <String>['en', 'he']) {
      test('in $tag is unchanged', () {
        // Act
        final copy = _canonicalJson(_copyFor(Locale(tag)));

        // Assert
        _expectFixture('copy_$tag.json', copy);
      });
    }
  });

  group('the share text', () {
    for (final menu in <String, Menu>{
      'english': goldenEnglishMenu,
      'hebrew': goldenHebrewMenu,
    }.entries) {
      test('of the ${menu.key} menu is unchanged', () async {
        // Arrange
        final analysis = await _rulesAnalysis(menu.value, _defaults);

        // Act
        final text = MenuShareText.build(
          venueName: menu.value.venueName ?? '',
          menu: menu.value,
          analysis: analysis,
        );

        // Assert
        _expectFixture('share_text_${menu.key}.txt', text);
      });
    }
  });

  group('with bantoMode: true', () {
    test('lists its seams', () {
      // Assert: a seam dropped by accident would otherwise pass silently.
      expect(_bantoSeams.map((seam) => seam.fixture), <String>[
        'document_title.txt',
        'app_settings_defaults.json',
        // ALG-03: an empty profile, then keto alone.
        for (var i = 0; i < 2; i++) ...<String>[
          'system_prompt_defaults.txt',
          'vision_system_prompt_defaults_2_pages.txt',
          'response_schema.json',
          'vision_response_schema.json',
          'options_snapshot_defaults.json',
        ],
      ]);
    });

    test('every bantoMode seam still builds its keto-only fixture', () {
      for (final seam in _bantoSeams) {
        // Act
        final built = seam.build(bantoMode: true);

        // Assert
        _expectFixture(seam.fixture, built);
      }
    });
  });
}
