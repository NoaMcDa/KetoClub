/// Builds the golden parity corpus (architecture.md D25; issue #320): the
/// JSON files under `backend/tests/fixtures/golden/` that prove a Python
/// port of the menu logic byte-equal to the Dart source of truth.
///
/// [buildGoldens] runs the real Dart code — the normaliser, the rule
/// engine, the heuristic classifier, the prompt, the reply parser, the
/// pasted-menu reader, the platform mappers, the website locator, dish
/// kinds and the keto score — over the inputs in `golden_corpus.dart`,
/// the vocabulary in `constants.dart` and the fixtures in
/// `test/fixtures/`, and returns one JSON document per file.
/// `test/golden/golden_drift_test.dart` compares them with the committed
/// files, or rewrites those with `--dart-define=UPDATE_GOLDEN=true`.
///
/// It runs under `flutter test`, not `dart run`: `classification_rules.dart`
/// imports `package:flutter/foundation.dart`, which needs `dart:ui`. It
/// reads fixtures relative to the working directory, which `flutter test`
/// sets to the package root.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_analysis_prompt.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_response_parser.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/tenbis/tenbis_menu_mapper.dart';
import 'package:ketoclub/services/menu/text/text_menu_source.dart';
import 'package:ketoclub/services/menu/website/json_ld_menu_mapper.dart';
import 'package:ketoclub/services/menu/website/website_html.dart';
import 'package:ketoclub/services/menu/website/website_menu_locator.dart';
import 'package:ketoclub/services/menu/wolt/wolt_menu_mapper.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/venue/wolt/wolt_venue_mapper.dart';
import 'package:ketoclub/utils/classification_rules.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/dish_kind.dart';
import 'package:ketoclub/utils/hebrew_order.dart';
import 'package:ketoclub/utils/keto_score.dart';
import 'package:ketoclub/utils/text_normaliser.dart';
import 'package:ketoclub/utils/verdict_counts.dart';

import 'golden_corpus.dart';

/// Where the golden files live, relative to the repository root.
const String goldenDirectory = 'backend/tests/fixtures/golden';

/// Every file [buildGoldens] writes, in a fixed order.
const List<String> goldenFileNames = <String>[
  'vocabulary.json',
  'normaliser.json',
  'fingerprint.json',
  'rules.json',
  'heuristic.json',
  'prompt.json',
  'parser.json',
  'text_menu.json',
  'website.json',
  'wolt_menu.json',
  'tenbis_menu.json',
  'wolt_venues.json',
  'dish_kind.json',
  'score.json',
];

/// [document] in the corpus's canonical form: two-space indentation, every
/// object's keys sorted (by UTF-16 code unit, Dart's `String.compareTo`),
/// list order kept, and a trailing newline.
String encodeGolden(Object? document) =>
    '${const JsonEncoder.withIndent('  ').convert(_sorted(document))}\n';

Object? _sorted(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{for (final key in keys) key: _sorted(value[key])};
  }
  if (value is List) return <Object?>[for (final item in value) _sorted(item)];
  return value;
}

/// Every golden document, by file name (see [goldenFileNames]), computed by
/// running the real Dart code. Async only because the heuristic classifier
/// answers with a `Future`; nothing here performs I/O beyond reading
/// `test/fixtures/`.
Future<Map<String, Object?>> buildGoldens() async {
  final inputs = _Inputs.load();
  return <String, Object?>{
    'vocabulary.json': _vocabulary(),
    'normaliser.json': _normaliser(),
    'fingerprint.json': _fingerprints(inputs),
    'rules.json': _rules(),
    'heuristic.json': await _heuristic(inputs),
    'prompt.json': _prompt(inputs),
    'parser.json': _parser(),
    'text_menu.json': _textMenu(),
    'website.json': _website(),
    'wolt_menu.json': _woltMenus(inputs),
    'tenbis_menu.json': _tenBisMenus(inputs),
    'wolt_venues.json': _woltVenues(),
    'dish_kind.json': _dishKinds(inputs),
    'score.json': await _scores(inputs),
  };
}

// ---------------------------------------------------------------------------
// Shared inputs and serialisation
// ---------------------------------------------------------------------------

/// A [Clock] that always answers [goldenNow].
final class _GoldenClock implements Clock {
  const new();

  @override
  DateTime now() => goldenNow;
}

/// The engine every parsed reply is stamped with.
const LlmEngine _engine = LlmEngine(model: goldenModel);

/// Reads [path], relative to the repository root, as UTF-8 text.
String _read(String path) => File(path).readAsStringSync();

/// Reads and decodes the JSON object at [path].
Map<String, Object?> _readJson(String path) =>
    jsonDecode(_read(path)) as Map<String, Object?>;

/// The checked-in fixtures, read and mapped once.
final class _Inputs {
  new({
    required this.woltRaw,
    required this.tenBisRaw,
    required this.wolt,
    required this.tenBis,
  });

  factory load() {
    final woltRaw = _readJson('test/fixtures/wolt_hamosad_menu.json');
    final tenBisRaw = _readJson('test/fixtures/tenbis_synthetic_menu.json');
    return _Inputs(
      woltRaw: woltRaw,
      tenBisRaw: tenBisRaw,
      wolt: _mapped(
        WoltMenuMapper.toMenu(
          woltRaw,
          ref: goldenWoltRef,
          fetchedAt: goldenNow,
        ),
      )!,
      tenBis: _mapped(
        TenBisMenuMapper.toMenu(
          tenBisRaw,
          ref: goldenTenBisRef,
          fetchedAt: goldenNow,
        ),
      )!,
    );
  }

  final Map<String, Object?> woltRaw;
  final Map<String, Object?> tenBisRaw;
  final Menu wolt;
  final Menu tenBis;

  /// Every menu the classifier-facing goldens run over, by name.
  Map<String, Menu> get menus => <String, Menu>{
    'wolt_hamosad': wolt,
    'tenbis_synthetic': tenBis,
    ...goldenHandBuiltMenus,
  };
}

Menu? _mapped(MenuFetchResult result) => switch (result) {
  MenuFetched(:final menu) => menu,
  MenuFetchFailed() => null,
};

/// The four option sets the classifier-facing goldens run under.
final Map<String, ClassificationOptions> _optionSets =
    <String, ClassificationOptions>{
      'defaults': const ClassificationOptions(),
      'seedOilFree_dairyFree': ClassificationOptions(
        dietaryConstraints: ClassificationOptions.dietaryConstraintsFor(
          seedOilFree: true,
          dairyFree: true,
          carnivoreOnly: false,
        ),
      ),
      'carnivoreOnly_limit10': ClassificationOptions(
        netCarbLimitGrams: 10,
        dietaryConstraints: ClassificationOptions.dietaryConstraintsFor(
          seedOilFree: false,
          dairyFree: false,
          carnivoreOnly: true,
        ),
      ),
      'allRules_limit2': ClassificationOptions(
        netCarbLimitGrams: 2,
        dietaryConstraints: ClassificationOptions.dietaryConstraintsFor(
          seedOilFree: true,
          dairyFree: true,
          carnivoreOnly: true,
        ),
      ),
    };

/// A [GuardWords] record as `{before, after}`.
Map<String, Object?> _guard(GuardWords guard) => <String, Object?>{
  'before': guard.before,
  'after': guard.after,
};

/// A guard table as `{trigger: {before, after}}`.
Map<String, Object?> _guards(Map<String, GuardWords> table) =>
    <String, Object?>{
      for (final entry in table.entries) entry.key: _guard(entry.value),
    };

/// An ordered map as `[[key, value], ...]`, so the order survives the
/// canonical key sort.
List<Object?> _pairs(Map<String, String> map) => <Object?>[
  for (final entry in map.entries) <Object?>[entry.key, entry.value],
];

/// A [RuleMatch] with every field, plus the verdict colour it implies.
Map<String, Object?> _match(RuleMatch match) => <String, Object?>{
  'kind': match.isNonKeto
      ? 'red'
      : (match.instructions.isEmpty ? 'green' : 'yellow'),
  'isNonKeto': match.isNonKeto,
  'baseLabel': match.baseLabel,
  'instructions': match.instructions,
};

/// A [Venue] in the shape the backend's `Venue` model mirrors. Written
/// here rather than read from `Venue.toJson`, which `lib/models/venue.dart`
/// does not have yet.
Map<String, Object?> _venue(Venue venue) => <String, Object?>{
  'ref': venue.ref.toJson(),
  'name': venue.name,
  'address': venue.address,
  'latitude': venue.latitude,
  'longitude': venue.longitude,
  'sourceUrl': venue.sourceUrl,
  'cuisineTags': venue.cuisineTags,
  'isOnline': venue.isOnline,
  'imageUrl': venue.imageUrl,
  'shortDescription': venue.shortDescription,
  'platformRating': venue.platformRating,
  'estimateMinutes': venue.estimateMinutes,
  'city': venue.city,
};

/// A [VerdictCounts] with its derived score.
Map<String, Object?> _counts(VerdictCounts counts) => <String, Object?>{
  'green': counts.green,
  'yellow': counts.yellow,
  'hiddenCarbYellow': counts.hiddenCarbYellow,
  'red': counts.red,
  'score': counts.score,
};

/// The 8-hex-digit form a scan's `VenueRef` carries.
String _hex(int fingerprint) => fingerprint.toRadixString(16).padLeft(8, '0');

/// [items] with duplicates removed, first occurrence kept.
List<String> _unique(Iterable<String> items) => <String>{...items}.toList();

// ---------------------------------------------------------------------------
// vocabulary.json
// ---------------------------------------------------------------------------

/// The trigger every Hebrew pattern example is built for.
const String _exampleHe = 'פסטה';

Map<String, Object?> _vocabulary() {
  final defaultSystem = MenuAnalysisPrompt.systemPrompt();
  final definitions = promptVerdictDefinitionsFor(defaultNetCarbLimitGrams);
  final rules = promptKetoRulesFor(defaultNetCarbLimitGrams);
  final rolePreamble = defaultSystem.substring(
    0,
    defaultSystem.indexOf('\n\n$definitions'),
  );
  final outputRules = defaultSystem.substring(
    defaultSystem.indexOf('$rules\n\n') + rules.length + 2,
  );
  final dietary = MenuAnalysisPrompt.systemPrompt(
    options: const ClassificationOptions(
      dietaryConstraints: <String>[seedOilFreePromptFragment],
    ),
  );
  final dietaryPreamble = dietary
      .substring(defaultSystem.length + 2)
      .split('\n')
      .first;
  if ('$rolePreamble\n\n$definitions\n\n$rules\n\n$outputRules' !=
      defaultSystem) {
    throw StateError('The system prompt no longer splits into its parts.');
  }

  return <String, Object?>{
    'carbModifiersEn': _pairs(carbModifiersEn),
    'carbModifiersHe': _pairs(carbModifiersHe),
    'nonKetoDrinkBasesEn': nonKetoDrinkBasesEn,
    'nonKetoDrinkBasesHe': nonKetoDrinkBasesHe,
    'nonKetoBasesEn': nonKetoBasesEn,
    'nonKetoBasesHe': nonKetoBasesHe,
    'nonKetoBaseLabelsEn': nonKetoBaseLabelsEn,
    'nonKetoBaseLabelsHe': nonKetoBaseLabelsHe,
    'carbOnlyBaseLabels': carbOnlyBaseLabels,
    'carbOnlyEligibleTriggers': carbOnlyEligibleTriggers.toList(),
    'carbOnlyQualifiersEn': carbOnlyQualifiersEn,
    'carbOnlyQualifiersHe': carbOnlyQualifiersHe,
    'fillingProteinTriggersEn': fillingProteinTriggersEn,
    'fillingProteinTriggersHe': fillingProteinTriggersHe,
    'seedOilTriggersEn': seedOilTriggersEn,
    'seedOilTriggersHe': seedOilTriggersHe,
    'dairyTriggersEn': dairyTriggersEn,
    'dairyTriggersHe': dairyTriggersHe,
    'plantTriggersEn': plantTriggersEn,
    'plantTriggersHe': plantTriggersHe,
    'triggerSuppresses': triggerSuppresses,
    'ketoQualifierGuardsEn': _guards(ketoQualifierGuardsEn),
    'ketoQualifierGuardsHe': _guards(ketoQualifierGuardsHe),
    'dairyGuardsEn': _guards(dairyGuardsEn),
    'dairyGuardsHe': _guards(dairyGuardsHe),
    'optionRemovalWordsEn': optionRemovalWordsEn,
    'optionRemovalWordsHe': optionRemovalWordsHe,
    'noPrefixHebrewTriggers': _noPrefixHebrewTriggers(),
    'hebrewTriggerPatternExample': <String, Object?>{
      'trigger': _exampleHe,
      'withPrefix': hebrewTriggerPattern(_exampleHe).pattern,
      'withoutPrefix': hebrewTriggerPattern(
        _exampleHe,
        allowPrefix: false,
      ).pattern,
      'withInflection': hebrewTriggerPattern(
        _exampleHe,
        allowInflection: true,
      ).pattern,
    },
    'latinTriggerPatternExample': <String, Object?>{
      'trigger': 'sweet potato',
      'pattern': latinTriggerPattern('sweet potato').pattern,
      'caseSensitive': latinTriggerPattern('x').isCaseSensitive,
      'unicode': latinTriggerPattern('x').isUnicode,
    },
    'dishKinds': <String, Object?>{
      'drinkCategoryWordsEn': drinkCategoryWordsEn,
      'drinkCategoryWordsHe': drinkCategoryWordsHe,
      'extraCategoryWordsEn': extraCategoryWordsEn,
      'extraCategoryWordsHe': extraCategoryWordsHe,
      'foodCategoryWordsEn': foodCategoryWordsEn,
      'foodCategoryWordsHe': foodCategoryWordsHe,
      'noticeCategoryWordsEn': noticeCategoryWordsEn,
      'noticeCategoryWordsHe': noticeCategoryWordsHe,
      'yellowDrinkTriggersEn': yellowDrinkTriggersEn,
      'yellowDrinkTriggersHe': yellowDrinkTriggersHe,
      'plainDrinkWordsEn': plainDrinkWordsEn,
      'plainDrinkWordsHe': plainDrinkWordsHe,
      'drinkNameTriggersEn': drinkNameTriggersEn,
      'drinkNameTriggersHe': drinkNameTriggersHe,
      'drinkNameGuardWordsEn': drinkNameGuardWordsEn,
      'drinkNameGuardWordsHe': drinkNameGuardWordsHe,
      // Read from `utils/dish_kind.dart`, where they are private: which
      // vocabularies match Hebrew with the permissive prefix.
      'hebrewPrefixAllowed': <String, Object?>{
        'drinkCategories': false,
        'extraCategories': false,
        'foodCategories': true,
        'notice': false,
        'drinkNames': true,
        'drinkNameGuards': true,
      },
    },
    'templates': <String, Object?>{
      'greenWhyEn': greenWhyEn,
      'greenWhyHe': greenWhyHe,
      'yellowWhyEn': yellowWhyEn,
      'yellowWhyHe': yellowWhyHe,
      'redWhyEn': redWhyEn,
      'redWhyHe': redWhyHe,
      'dietaryRuleWhyEn': dietaryRuleWhyEn,
      'dietaryRuleWhyHe': dietaryRuleWhyHe,
      'seedOilFreeModificationEn': seedOilFreeModificationEn,
      'seedOilFreeModificationHe': seedOilFreeModificationHe,
      'dairyFreeModificationEn': dairyFreeModificationEn,
      'dairyFreeModificationHe': dairyFreeModificationHe,
      'carnivoreOnlyModificationEn': carnivoreOnlyModificationEn,
      'carnivoreOnlyModificationHe': carnivoreOnlyModificationHe,
      'optionBaseModificationEn': optionBaseModificationEn,
      'optionBaseModificationHe': optionBaseModificationHe,
    },
    'prompt': <String, Object?>{
      'promptVerdictDefinitionsTemplate': promptVerdictDefinitionsTemplate,
      'promptKetoRulesTemplate': promptKetoRulesTemplate,
      'seedOilFreePromptFragment': seedOilFreePromptFragment,
      'dairyFreePromptFragment': dairyFreePromptFragment,
      'carnivoreOnlyPromptFragment': carnivoreOnlyPromptFragment,
      'netCarbLimitPlaceholder': netCarbLimitPlaceholder,
      // Private to `menu_analysis_prompt.dart`; cut out of its real output.
      'rolePreamble': rolePreamble,
      'outputRules': outputRules,
      'dietaryConstraintsPreamble': dietaryPreamble,
      'schemaName': MenuAnalysisPrompt.schemaName,
    },
    'caps': <String, Object?>{
      'maxAnalysedDishes': maxAnalysedDishes,
      'maxWhyLength': maxWhyLength,
      'maxModificationLength': maxModificationLength,
      'minOverlapWordLength': minOverlapWordLength,
      'defaultNetCarbLimitGrams': defaultNetCarbLimitGrams,
      'minNetCarbLimitGrams': minNetCarbLimitGrams,
      'maxNetCarbLimitGrams': maxNetCarbLimitGrams,
      // A literal in `MenuResponseParser._parseHiddenCarbs`.
      'maxHiddenCarbsPerDish': 3,
      'parserSchemaVersion': MenuResponseParser.schemaVersion,
      'maxScanPages': maxScanPages,
      'maxScanPageBytes': maxScanPageBytes,
    },
    'scanned': <String, Object?>{
      'scannedCategoryId': scannedCategoryId,
      'scannedCategoryNameEn': scannedCategoryNameEn,
      'scannedCategoryNameHe': scannedCategoryNameHe,
      'scannedDishIdPrefix': scannedDishIdPrefix,
      'scannedMenuCurrency': scannedMenuCurrency,
    },
    'pasted': <String, Object?>{
      'pastedHeaderMaxWords': pastedHeaderMaxWords,
      'pastedPriceSuffix': <String, Object?>{
        'pattern': pastedPriceSuffix.pattern,
        'caseSensitive': pastedPriceSuffix.isCaseSensitive,
        'unicode': pastedPriceSuffix.isUnicode,
      },
    },
    'website': <String, Object?>{
      'websiteCategoryNameEn': websiteCategoryNameEn,
      'websiteCategoryNameHe': websiteCategoryNameHe,
      'menuWords': WebsiteMenuLocator.menuWords,
      'minPricedLines': WebsiteMenuLocator.minPricedLines,
      'jsOnlyTextChars': WebsiteHtml.jsOnlyTextChars,
      'jsOnlyNoscriptTextChars': WebsiteHtml.jsOnlyNoscriptTextChars,
    },
    'ketoScoreWeights': <String, Object?>{
      // Private to `utils/keto_score.dart`; read back from the formula.
      'yellow':
          ketoScore(
            greenCount: 0,
            hiddenCarbYellowCount: 0,
            otherYellowCount: 1,
            redCount: 0,
          )! /
          10,
      'hiddenCarbYellow':
          ketoScore(
            greenCount: 0,
            hiddenCarbYellowCount: 1,
            otherYellowCount: 0,
            redCount: 0,
          )! /
          10,
    },
  };
}

/// The Hebrew triggers compiled with no permissive prefix, found by
/// behaviour rather than copied from `classification_rules.dart`, where
/// the set is private: a trigger whose ה-prefixed form no longer yields its
/// own sentence (a carb modifier) or a red (a base).
List<String> _noPrefixHebrewTriggers() {
  String inContext(String text) => hebrewContext.replaceAll('{t}', text);
  final found = <String>[];
  for (final entry in carbModifiersHe.entries) {
    final prefixed = ClassificationRules.match(inContext('ה${entry.key}'));
    if (!prefixed.instructions.contains(entry.value)) found.add(entry.key);
  }
  for (final trigger in nonKetoBasesHe) {
    if (!ClassificationRules.match(inContext('ה$trigger')).isNonKeto) {
      found.add(trigger);
    }
  }
  return found;
}

// ---------------------------------------------------------------------------
// normaliser.json
// ---------------------------------------------------------------------------

/// Every vocabulary word the rule engine and dish kinds compile.
List<String> _allVocabularyWords() => <String>[
  ...carbModifiersEn.keys,
  ...carbModifiersEn.values,
  ...carbModifiersHe.keys,
  ...carbModifiersHe.values,
  ...nonKetoBasesEn,
  ...nonKetoBasesHe,
  ...nonKetoBaseLabelsEn.values,
  ...nonKetoBaseLabelsHe.values,
  ...carbOnlyQualifiersEn,
  ...carbOnlyQualifiersHe,
  ...fillingProteinTriggersEn,
  ...fillingProteinTriggersHe,
  ...seedOilTriggersEn,
  ...seedOilTriggersHe,
  ...dairyTriggersEn,
  ...dairyTriggersHe,
  ...plantTriggersEn,
  ...plantTriggersHe,
  for (final guard in <GuardWords>[
    ...ketoQualifierGuardsEn.values,
    ...ketoQualifierGuardsHe.values,
    ...dairyGuardsEn.values,
    ...dairyGuardsHe.values,
  ]) ...<String>[...guard.before, ...guard.after],
  ...optionRemovalWordsEn,
  ...optionRemovalWordsHe,
  ...drinkCategoryWordsEn,
  ...drinkCategoryWordsHe,
  ...extraCategoryWordsEn,
  ...extraCategoryWordsHe,
  ...foodCategoryWordsEn,
  ...foodCategoryWordsHe,
  ...noticeCategoryWordsEn,
  ...noticeCategoryWordsHe,
  ...plainDrinkWordsEn,
  ...plainDrinkWordsHe,
  ...drinkNameGuardWordsEn,
  ...drinkNameGuardWordsHe,
];

List<Object?> _normaliser() {
  final inputs = _unique(<String>[
    ...normaliserEdgeCases,
    for (final mark in normaliserQuoteMarks) 'א$markב',
    // Every Latin-1 Supplement character alone: the fold table, NBSP,
    // the symbols that are neither letters nor numbers.
    for (var code = 0xA0; code <= 0xFF; code++) String.fromCharCode(code),
    ..._allVocabularyWords(),
  ]);
  return <Object?>[
    for (final text in inputs)
      <String, Object?>{
        'in': text,
        'normalised': TextNormaliser.normalise(text),
        'containsHebrew': TextNormaliser.containsHebrew(text),
        'words': TextNormaliser.words(text),
        'wordsMin3': TextNormaliser.words(
          text,
          minLength: minOverlapWordLength,
        ),
        'isRemovalOptionValue': TextNormaliser.isRemovalOptionValue(text),
      },
  ];
}

// ---------------------------------------------------------------------------
// fingerprint.json
// ---------------------------------------------------------------------------

List<Object?> _fingerprints(_Inputs inputs) {
  final menus = <String, Menu>{
    'wolt_hamosad': inputs.wolt,
    'tenbis_synthetic': inputs.tenBis,
    for (final (index, text) in <String>[
      'Grilled salmon\nCaesar salad\nPasta carbonara',
      'ראשונות:\nחומוס 32 ₪\nמרק היום\n\nעיקריות:\nסטייק 120',
      'Steak 89\nwith fries 12 ₪\nSalmon 75 NIS',
    ].indexed)
      'pasted_${index + 1}': TextMenuSource.parse(text, now: goldenNow)!,
    for (final name in _scannedFixtureNames)
      if (_scannedMenu(name) case final Menu menu) 'scanned_$name': menu,
    ...goldenHandBuiltMenus,
  };
  return <Object?>[
    for (final MapEntry(key: name, value: menu) in menus.entries)
      <String, Object?>{
        'name': name,
        'menu': menu.toJson(),
        'searchTexts': <String>[
          for (final dish in menu.allDishes)
            TextNormaliser.dishSearchText(dish),
        ],
        'hex': _hex(TextNormaliser.menuFingerprint(menu)),
      },
  ];
}

/// The scanned-reply fixtures under `test/fixtures/llm/`.
const List<String> _scannedFixtureNames = <String>[
  'llm_scanned_duplicate_names.json',
  'llm_scanned_empty.json',
  'llm_scanned_nameless_element.json',
  'llm_scanned_over_cap.json',
  'llm_scanned_pages.json',
  'llm_scanned_valid.json',
];

/// The page count each scanned fixture is parsed with.
int? _scannedPageCount(String name) =>
    name == 'llm_scanned_pages.json' ? 3 : null;

/// The transcription of the scanned fixture [name], or null when the
/// reply is rejected.
Menu? _scannedMenu(String name) => switch (MenuResponseParser.parseScanned(
  _read('test/fixtures/llm/$name'),
  analysedAt: goldenNow,
  engine: _engine,
  pageCount: _scannedPageCount(name),
)) {
  ScannedMenuRead(:final menu) => menu,
  ScannedMenuFailed() => null,
};

// ---------------------------------------------------------------------------
// rules.json
// ---------------------------------------------------------------------------

Map<String, Object?> _rules() {
  String en(String text) => englishContext.replaceAll('{t}', text);
  String he(String text) => hebrewContext.replaceAll('{t}', text);

  final texts = <String>[
    ...ruleTexts,
    for (final trigger in carbModifiersEn.keys) ...<String>[
      trigger,
      en(trigger),
      en(trigger.toUpperCase()),
    ],
    for (final trigger in nonKetoBasesEn) ...<String>[trigger, en(trigger)],
    for (final trigger in <String>[
      ...carbModifiersHe.keys,
      ...nonKetoBasesHe,
    ]) ...<String>[
      trigger,
      he(trigger),
      he('ה$trigger'),
      he('וב$trigger'),
      he('ושה$trigger'),
      he('$triggerי'),
    ],
    for (final MapEntry(key: trigger, value: guard)
        in ketoQualifierGuardsEn.entries) ...<String>[
      for (final word in guard.before) ...<String>[
        en('$word $trigger'),
        en('$word extra $trigger'),
        en('$word $guardFillerEn $trigger'),
      ],
      for (final word in guard.after) ...<String>[
        en('$trigger $word'),
        en('$trigger extra $word'),
        en('$trigger $guardFillerEn $word'),
      ],
    ],
    for (final MapEntry(key: trigger, value: guard)
        in ketoQualifierGuardsHe.entries) ...<String>[
      for (final word in guard.before) ...<String>[
        he('$word $trigger'),
        he('$trigger $word'),
        he('$trigger עם $word'),
        he('$word $guardFillerHe $trigger'),
      ],
    ],
    for (final MapEntry(key: trigger, value: victims)
        in triggerSuppresses.entries) ...<String>[
      trigger,
      for (final victim in victims) '$trigger, $victim',
    ],
  ];

  final mentions = _unique(<String>[
    ...mentionTexts,
    ...seedOilTriggersEn,
    ...dairyTriggersEn,
    ...plantTriggersEn,
    for (final trigger in <String>[
      ...seedOilTriggersHe,
      ...dairyTriggersHe,
      ...plantTriggersHe,
    ]) ...<String>[trigger, 'ה$trigger', '$triggerי'],
    for (final MapEntry(key: trigger, value: guard)
        in <MapEntry<String, GuardWords>>[
          ...dairyGuardsEn.entries,
          ...dairyGuardsHe.entries,
        ]) ...<String>[
      for (final word in guard.before) ...<String>[
        '$word $trigger',
        '$word big fat $trigger',
      ],
      for (final word in guard.after) '$trigger $word',
    ],
  ]);

  final carbOnly = _unique(<String>[
    ...carbOnlyNames,
    for (final trigger in carbOnlyEligibleTriggers) trigger,
    for (final trigger in carbOnlyEligibleTriggers) 'plain $trigger',
    for (final trigger in carbOnlyEligibleTriggers) '$trigger רגילה',
  ]);

  final dishes = <Dish>[
    ...ruleDishes,
    for (final name in carbOnlyNames) ruleDish(name),
  ];

  return <String, Object?>{
    'texts': <Object?>[
      for (final text in _unique(texts))
        <String, Object?>{
          'text': text,
          'match': _match(ClassificationRules.match(text)),
        },
    ],
    'dishes': <Object?>[
      for (final dish in dishes)
        <String, Object?>{
          'dish': dish.toJson(),
          'match': _match(ClassificationRules.matchDish(dish)),
          'carbOnlyBase': ClassificationRules.carbOnlyBase(dish.name),
          'describesFilling': ClassificationRules.describesFilling(dish),
          'coreText': TextNormaliser.dishCoreText(dish),
          'rulesText': TextNormaliser.dishRulesText(dish),
          'optionRulesText': TextNormaliser.dishOptionRulesText(dish),
          'searchText': TextNormaliser.dishSearchText(dish),
        },
    ],
    'mentions': <Object?>[
      for (final text in mentions)
        <String, Object?>{
          'text': text,
          'seedOil': ClassificationRules.mentionsSeedOil(text),
          'dairy': ClassificationRules.mentionsDairy(text),
          'plant': ClassificationRules.mentionsPlant(text),
        },
    ],
    'carbOnly': <Object?>[
      for (final name in carbOnly)
        <String, Object?>{
          'name': name,
          'base': ClassificationRules.carbOnlyBase(name),
        },
    ],
  };
}

// ---------------------------------------------------------------------------
// heuristic.json
// ---------------------------------------------------------------------------

Future<List<Object?>> _heuristic(_Inputs inputs) async {
  const classifier = HeuristicMenuClassifier(clock: _GoldenClock());
  final entries = <Object?>[];
  for (final MapEntry(key: menuName, value: menu) in inputs.menus.entries) {
    for (final MapEntry(key: optionsName, value: options)
        in _optionSets.entries) {
      final analysis =
          await classifier.classify(menu, options: options) as MenuAnalysed;
      entries.add(<String, Object?>{
        'name': '$menuName/$optionsName',
        'menu': menu.toJson(),
        'options': options.snapshot.toJson(),
        'analysis': analysis.toJson(),
      });
    }
  }
  return entries;
}

// ---------------------------------------------------------------------------
// prompt.json
// ---------------------------------------------------------------------------

Map<String, Object?> _prompt(_Inputs inputs) => <String, Object?>{
  'schemaName': MenuAnalysisPrompt.schemaName,
  'schema': MenuAnalysisPrompt.responseSchema(),
  'visionSchema': MenuAnalysisPrompt.visionResponseSchema(),
  'entries': <Object?>[
    for (final MapEntry(key: menuName, value: menu) in inputs.menus.entries)
      for (final MapEntry(key: optionsName, value: options)
          in _optionSets.entries)
        <String, Object?>{
          'name': '$menuName/$optionsName',
          'menu': menu.toJson(),
          'options': options.snapshot.toJson(),
          'systemPrompt': MenuAnalysisPrompt.systemPrompt(options: options),
          'userPrompt': MenuAnalysisPrompt.userPrompt(menu),
          'visionPreamble1': MenuAnalysisPrompt.visionPreamble(1),
          'visionPreamble3': MenuAnalysisPrompt.visionPreamble(3),
          'visionUserPrompt1': MenuAnalysisPrompt.visionUserPrompt(1),
          'visionUserPrompt3': MenuAnalysisPrompt.visionUserPrompt(3),
          'visionSystemPrompt1': MenuAnalysisPrompt.visionSystemPrompt(
            pageCount: 1,
            options: options,
          ),
          'visionSystemPrompt3': MenuAnalysisPrompt.visionSystemPrompt(
            pageCount: 3,
            options: options,
          ),
        },
  ],
};

// ---------------------------------------------------------------------------
// parser.json
// ---------------------------------------------------------------------------

/// A text parse result as `{analysed}` or `{failed}`.
Map<String, Object?> _textResult(MenuAnalysis result) => switch (result) {
  final MenuAnalysed analysed => <String, Object?>{
    'analysed': analysed.toJson(),
  },
  MenuAnalysisFailed(:final reason) => <String, Object?>{'failed': reason.name},
};

/// A scanned parse result as `{menu, analysis}` or `{failed}`.
Map<String, Object?> _scannedResult(ScannedMenuResult result) =>
    switch (result) {
      ScannedMenuRead(:final menu, :final analysis) => <String, Object?>{
        'menu': menu.toJson(),
        'analysis': analysis.toJson(),
      },
      ScannedMenuFailed(:final reason) => <String, Object?>{
        'failed': reason.name,
      },
    };

Map<String, Object?> _textEntry(
  String name,
  String reply,
  Menu source,
  int limit,
) => <String, Object?>{
  'name': name,
  'reply': reply,
  'sourceMenu': source.toJson(),
  'netCarbLimitGrams': limit,
  'result': _textResult(
    MenuResponseParser.parse(
      reply,
      source: source,
      analysedAt: goldenNow,
      engine: _engine,
      netCarbLimitGrams: limit,
    ),
  ),
};

Map<String, Object?> _scannedEntry(
  String name,
  String reply,
  int? pageCount,
  int limit,
) => <String, Object?>{
  'name': name,
  'reply': reply,
  'pageCount': pageCount,
  'netCarbLimitGrams': limit,
  'result': _scannedResult(
    MenuResponseParser.parseScanned(
      reply,
      analysedAt: goldenNow,
      engine: _engine,
      netCarbLimitGrams: limit,
      pageCount: pageCount,
    ),
  ),
};

Map<String, Object?> _parser() {
  final fixtureNames = parserFixtureSources.keys.toList()..sort();
  return <String, Object?>{
    'text': <Object?>[
      for (final name in fixtureNames)
        _textEntry(
          name,
          _read('test/fixtures/$name'),
          parserFixtureSources[name]!,
          defaultNetCarbLimitGrams,
        ),
      // The empty-dishes reply against a menu it skipped entirely, and the
      // two-dish variants reply under a lower and a higher limit.
      _textEntry(
        'llm_empty_dishes.json@steak',
        _read('test/fixtures/llm_empty_dishes.json'),
        parserSteakMenu,
        defaultNetCarbLimitGrams,
      ),
      for (final limit in <int>[2, 25])
        _textEntry(
          'llm_net_carbs_variants.json@limit$limit',
          _read('test/fixtures/llm_net_carbs_variants.json'),
          parserFixtureSources['llm_net_carbs_variants.json']!,
          limit,
        ),
      for (final reply in handTextReplies())
        _textEntry(reply.name, reply.body, reply.source!, reply.limit),
    ],
    'scanned': <Object?>[
      for (final name in _scannedFixtureNames)
        _scannedEntry(
          name,
          _read('test/fixtures/llm/$name'),
          _scannedPageCount(name),
          defaultNetCarbLimitGrams,
        ),
      for (final pageCount in <int?>[1, 2])
        _scannedEntry(
          'llm_scanned_pages.json@pages$pageCount',
          _read('test/fixtures/llm/llm_scanned_pages.json'),
          pageCount,
          defaultNetCarbLimitGrams,
        ),
      _scannedEntry(
        'llm_scanned_valid.json@limit10',
        _read('test/fixtures/llm/llm_scanned_valid.json'),
        null,
        10,
      ),
      // The text fixtures read as scans, as the scanned parser test does.
      for (final name in fixtureNames)
        _scannedEntry(
          '$name@scanned',
          _read('test/fixtures/$name'),
          null,
          defaultNetCarbLimitGrams,
        ),
      for (final reply in handScannedReplies())
        _scannedEntry(reply.name, reply.body, reply.pageCount, reply.limit),
    ],
  };
}

// ---------------------------------------------------------------------------
// text_menu.json
// ---------------------------------------------------------------------------

List<Object?> _textMenu() {
  final cases = <(String, String)>[
    for (final text in pastedTexts) (text, 'Pasted menu'),
    ('Steak', 'תפריט שהודבק'),
    ('Steak\nSalmon', websiteCategoryNameHe),
    (
      <String>[
        for (var i = 0; i < maxAnalysedDishes + 3; i++) 'Dish number $i x',
      ].join('\n'),
      'Pasted menu',
    ),
  ];
  return <Object?>[
    for (final (text, uncategorisedName) in cases)
      <String, Object?>{
        'text': text,
        'uncategorisedName': uncategorisedName,
        'menu': TextMenuSource.parse(
          text,
          now: goldenNow,
          uncategorisedName: uncategorisedName,
        )?.toJson(),
      },
  ];
}

// ---------------------------------------------------------------------------
// website.json
// ---------------------------------------------------------------------------

/// A [MenuLocation] as `{kind, ...}`.
Map<String, Object?> _location(MenuLocation location) => switch (location) {
  JsonLdMenuFound(:final categories) => <String, Object?>{
    'kind': 'jsonLd',
    'categories': <Object?>[
      for (final category in categories) category.toJson(),
    ],
  },
  final MenuLinkFound link => <String, Object?>{
    'kind': 'link',
    'uri': link.uri.toString(),
    'isPdf': link.isPdf,
  },
  NoMenuLink() => <String, Object?>{'kind': 'none'},
};

final RegExp _hebrewLetter = RegExp('[א-ת]');

List<Object?> _website() {
  final cases = <WebsiteCase>[
    for (final MapEntry(key: name, value: base) in websiteFixtureBases.entries)
      (name: name, html: _read('test/fixtures/website/$name'), baseUrl: base),
    ...websiteInlineCases,
  ];
  return <Object?>[for (final page in cases) _websiteEntry(page)];
}

Map<String, Object?> _websiteEntry(WebsiteCase page) {
  final base = Uri.parse(page.baseUrl);
  final blocks = WebsiteHtml.jsonLdBlocks(page.html);
  final menuText = WebsiteMenuLocator.menuText(page.html);
  final textMenu = menuText == null
      ? null
      : TextMenuSource.parse(
          menuText,
          now: goldenNow,
          uncategorisedName: _hebrewLetter.hasMatch(menuText)
              ? websiteCategoryNameHe
              : websiteCategoryNameEn,
        );
  final jsonLdCategories = JsonLdMenuMapper.categoriesFrom(blocks);
  final read = jsonLdCategories ?? textMenu?.categories;
  return <String, Object?>{
    'name': page.name,
    'html': page.html,
    'baseUrl': page.baseUrl,
    'located': _location(WebsiteMenuLocator.locate(page.html, base)),
    'jsonLdBlocks': blocks,
    'jsonLdCategories': jsonLdCategories == null
        ? null
        : <Object?>[for (final c in jsonLdCategories) c.toJson()],
    'jsonLdMenuUrl': JsonLdMenuMapper.menuUrlFrom(blocks, base)?.toString(),
    'links': <Object?>[
      for (final link in WebsiteHtml.links(page.html, base))
        <String, Object?>{'uri': link.uri.toString(), 'text': link.text},
    ],
    'lines': WebsiteHtml.lines(page.html),
    'menuText': menuText,
    'textMenu': textMenu?.toJson(),
    'isJavaScriptOnly': WebsiteHtml.isJavaScriptOnly(page.html),
    'reservesAi': WebsiteHtml.reservesAi(page.html),
    'anyCharacterReversed': read
        ?.expand((category) => category.dishes)
        .any(
          (dish) =>
              looksCharacterReversed(dish.name) ||
              looksCharacterReversed(dish.description),
        ),
  };
}

// ---------------------------------------------------------------------------
// wolt_menu.json, tenbis_menu.json, wolt_venues.json
// ---------------------------------------------------------------------------

List<Object?> _woltMenus(_Inputs inputs) {
  final payloads = <String, Map<String, Object?>>{
    'wolt_hamosad_menu.json': inputs.woltRaw,
    'wolt_malformed_menu.json': _readJson(
      'test/fixtures/wolt_malformed_menu.json',
    ),
    ...woltSyntheticPayloads(),
  };
  return <Object?>[
    for (final MapEntry(key: name, value: raw) in payloads.entries)
      <String, Object?>{
        'name': name,
        'ref': goldenWoltRef.toJson(),
        'fetchedAt': goldenNow.toIso8601String(),
        'raw': raw,
        'menu': _mapped(
          WoltMenuMapper.toMenu(raw, ref: goldenWoltRef, fetchedAt: goldenNow),
        )?.toJson(),
      },
  ];
}

List<Object?> _tenBisMenus(_Inputs inputs) {
  final payloads = <String, Map<String, Object?>>{
    'tenbis_synthetic_menu.json': inputs.tenBisRaw,
    'tenbis_malformed_menu.json': _readJson(
      'test/fixtures/tenbis_malformed_menu.json',
    ),
    ...tenBisSyntheticPayloads(),
  };
  return <Object?>[
    for (final MapEntry(key: name, value: raw) in payloads.entries)
      <String, Object?>{
        'name': name,
        'ref': goldenTenBisRef.toJson(),
        'fetchedAt': goldenNow.toIso8601String(),
        'raw': raw,
        'menu': _mapped(
          TenBisMenuMapper.toMenu(
            raw,
            ref: goldenTenBisRef,
            fetchedAt: goldenNow,
          ),
        )?.toJson(),
      },
  ];
}

List<Object?> _woltVenues() {
  final payloads = <String, Map<String, Object?>>{
    'wolt_pages_restaurants.json': _readJson(
      'test/fixtures/wolt_pages_restaurants.json',
    ),
    'wolt_pages_search.json': _readJson('test/fixtures/wolt_pages_search.json'),
    ...woltVenueSyntheticPayloads(),
  };
  return <Object?>[
    for (final MapEntry(key: name, value: raw) in payloads.entries)
      <String, Object?>{
        'name': name,
        'raw': raw,
        'venues': WoltVenueMapper.map(raw)?.map(_venue).toList(),
      },
  ];
}

// ---------------------------------------------------------------------------
// dish_kind.json
// ---------------------------------------------------------------------------

/// A menu of [names] under one [heading], each dish priced [price].
Menu _kindMenu(String id, String heading, List<String> names, double price) =>
    Menu(
      venueRef: VenueRef(source: MenuSource.scan, platformId: id),
      currency: 'ILS',
      fetchedAt: goldenNow,
      categories: <MenuCategory>[
        MenuCategory(
          id: id,
          name: heading,
          dishes: <Dish>[
            for (final (index, name) in names.indexed)
              Dish(
                id: '$id-${index + 1}',
                name: name,
                description: 'served with a glass of wine and a cola',
                price: price,
                options: const <DishOption>[],
              ),
          ],
        ),
      ],
    );

Map<String, Object?> _dishKinds(_Inputs inputs) {
  final menus = <String, Menu>{
    ...inputs.menus,
    'names_under_mains': _kindMenu('mains', 'Mains', dishKindNames, 40),
    'names_under_drinks': _kindMenu('drinks', 'שתייה', dishKindNames, 40),
    'names_under_mixed': _kindMenu('mixed', 'קפה ומאפה', dishKindNames, 40),
    'notices_free': _kindMenu('free', 'Mains', dishKindNoticeNames, 0),
    'notices_priced': _kindMenu('priced', 'Mains', dishKindNoticeNames, 40),
    'empty_name': _kindMenu('empty', 'Mains', const <String>[''], 0),
  };
  return <String, Object?>{
    'headings': <Object?>[
      for (final heading in dishKindHeadings)
        <String, Object?>{
          'heading': heading,
          'kind': categoryKindOf(heading).name,
        },
    ],
    'menus': <Object?>[
      for (final MapEntry(key: name, value: menu) in menus.entries)
        <String, Object?>{
          'name': name,
          'menu': menu.toJson(),
          'kinds': <String, Object?>{
            for (final MapEntry(key: id, value: kind) in dishKindsOf(
              menu,
            ).entries)
              id: kind.name,
          },
        },
    ],
  };
}

// ---------------------------------------------------------------------------
// score.json
// ---------------------------------------------------------------------------

Future<Map<String, Object?>> _scores(_Inputs inputs) async {
  final formula = <Object?>[
    for (var green = 0; green <= 4; green++)
      for (var yellow = 0; yellow <= 3; yellow++)
        for (var hidden = 0; hidden <= yellow; hidden++)
          for (var red = 0; red <= 4; red++)
            <String, Object?>{
              'green': green,
              'yellow': yellow,
              'hiddenCarbYellow': hidden,
              'red': red,
              'score': ketoScore(
                greenCount: green,
                hiddenCarbYellowCount: hidden,
                otherYellowCount: yellow - hidden,
                redCount: red,
              ),
            },
    for (final (green, yellow, hidden, red) in <(int, int, int, int)>[
      (1, 0, 0, 7),
      (1, 1, 1, 6),
      (3, 3, 1, 11),
      (17, 9, 4, 13),
      (56, 0, 0, 0),
      (0, 0, 0, 56),
      (1, 0, 0, 999),
    ])
      <String, Object?>{
        'green': green,
        'yellow': yellow,
        'hiddenCarbYellow': hidden,
        'red': red,
        'score': ketoScore(
          greenCount: green,
          hiddenCarbYellowCount: hidden,
          otherYellowCount: yellow - hidden,
          redCount: red,
        ),
      },
  ];

  const classifier = HeuristicMenuClassifier(clock: _GoldenClock());
  final analysed = <(String, Menu, MenuAnalysed)>[
    for (final MapEntry(key: name, value: menu) in inputs.menus.entries)
      ('$name/rules', menu, await classifier.classify(menu) as MenuAnalysed),
  ];
  for (final reply in handTextReplies()) {
    final result = MenuResponseParser.parse(
      reply.body,
      source: reply.source!,
      analysedAt: goldenNow,
      engine: _engine,
      netCarbLimitGrams: reply.limit,
    );
    if (result is MenuAnalysed && result.dishes.isNotEmpty) {
      analysed.add((reply.name, reply.source!, result));
    }
  }
  for (final name in _scannedFixtureNames) {
    final result = MenuResponseParser.parseScanned(
      _read('test/fixtures/llm/$name'),
      analysedAt: goldenNow,
      engine: _engine,
      pageCount: _scannedPageCount(name),
    );
    if (result case ScannedMenuRead(:final menu, :final analysis)) {
      analysed.add((name, menu, analysis));
    }
  }
  // An analysis over a menu it does not match: dish ids the menu lacks
  // count as food.
  analysed.add((
    'english_analysis_over_hebrew_menu',
    goldenHebrewMenu,
    analysed.firstWhere((entry) => entry.$1 == 'english/rules').$3,
  ));

  return <String, Object?>{
    'formula': formula,
    'menus': <Object?>[
      for (final (name, menu, analysis) in analysed)
        <String, Object?>{
          'name': name,
          'menu': menu.toJson(),
          'analysis': analysis.toJson(),
          'counts': _counts(VerdictCounts.of(menu, analysis)),
        },
    ],
  };
}
