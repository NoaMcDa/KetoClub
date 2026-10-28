/// The keto accuracy scorer: a labelled keto corpus replayed through the
/// on-device rule engine and measured.
///
/// Pure functions and plain value types, no widgets. The corpus contract is
/// `test/fixtures/keto/SCHEMA.md`: one JSON file per menu under
/// `test/fixtures/keto/menus/`, each `{id, name, source, language,
/// categories: [{name, dishes: [...]}]}`, and each dish `{id, name,
/// description, options: [{name, values}], expected, acceptable?,
/// hiddenCarbs: [{source, certainty, term?}], why, evidence}`, where
/// `expected` and every `acceptable` entry is a `DishVerdict` name. The
/// shape itself is enforced by the corpus's own shape test; this file reads
/// only the fields it scores.
///
/// [replayKetoCorpus] runs `HeuristicMenuClassifier` with the default
/// `ClassificationOptions` (keto only, no consent, no dietary toggles),
/// exactly what the app answers with no model. [KetoReport] then computes:
///
/// - a 3x3 confusion matrix, expected verdict by verdict given, plus a
///   column of dishes the engine did not place;
/// - accuracy: dishes whose verdict is `expected` or one of `acceptable`,
///   over all dishes;
/// - the false-green rate, the headline: dishes labelled `modifiable` or
///   `nonKeto` that came back `orderAsIs` (and do not list `orderAsIs` as
///   acceptable), over every dish not labelled `orderAsIs`. A false green
///   tells a keto dieter to order a dish as printed when it is not safe;
/// - the false-red rate: dishes labelled `orderAsIs` or `modifiable` that
///   came back `nonKeto` (and do not list it as acceptable), over every
///   dish not labelled `nonKeto`. The safe direction, but a lost dish;
/// - unclassified: dishes the analysis gave no verdict;
/// - hidden-carb recall and precision: a labelled flag and an engine flag
///   on the same dish match by the label's `term` when it has one (the
///   normalised engine source contains the normalised term, or the term
///   contains the source), and otherwise when the normalised words
///   (`TextNormaliser.words`) of the engine's source and the label's
///   English `source` are one a subset of the other; pairs are matched one
///   to one. Recall is matched pairs over labelled flags;
///   precision is matched pairs over engine flags, and reads as "-" while
///   the engine raises none;
/// - the same counts per menu and per language.
///
/// It runs under `flutter test`, not `dart run`: the rule engine imports
/// `package:flutter/foundation.dart`, which needs `dart:ui`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// A decoded JSON object.
typedef Json = Map<String, Object?>;

/// The directory every labelled keto menu lives in.
const String ketoMenusDir = 'test/fixtures/keto/menus';

/// The reviewed list of false greens the rules do not close yet.
const String ketoKnownMissesPath = 'test/fixtures/keto/known_keto_misses.json';

// ---------------------------------------------------------------------------
// The corpus
// ---------------------------------------------------------------------------

/// One labelled hidden-carb source on a corpus dish.
final class KetoHiddenCarbLabel {
  /// Creates a label for [source] at [certainty], pointed at by [term].
  const new({required this.source, required this.certainty, this.term});

  /// What may hide the carbs, in English with the Hebrew word in brackets
  /// when there is one, e.g. "house sauce (רוטב הבית)".
  final String source;

  /// `suspected` or `likely`.
  final String certainty;

  /// The dish text that points at the flag, or null when the carb is
  /// implied by the dish rather than named.
  final String? term;
}

/// One labelled dish of the corpus.
final class KetoCorpusDish {
  /// Creates a labelled dish.
  const new({
    required this.id,
    required this.name,
    required this.description,
    required this.options,
    required this.expected,
    required this.acceptable,
    required this.hiddenCarbs,
  });

  /// The dish's id, unique within its menu.
  final String id;

  /// The dish's name, as printed.
  final String name;

  /// The dish's description, `''` when none.
  final String description;

  /// The dish's option groups.
  final List<DishOption> options;

  /// The verdict the label asks for.
  final DishVerdict expected;

  /// Other verdicts the label also accepts as correct.
  final List<DishVerdict> acceptable;

  /// The hidden-carb sources the label names.
  final List<KetoHiddenCarbLabel> hiddenCarbs;

  /// Whether [got] is a correct answer for this dish.
  bool accepts(DishVerdict? got) =>
      got != null && (got == expected || acceptable.contains(got));
}

/// One category of a corpus menu.
final class KetoCorpusCategory {
  /// Creates a category named [name] holding [dishes].
  const new({required this.name, required this.dishes});

  /// The category heading, as printed.
  final String name;

  /// The category's dishes, in menu order.
  final List<KetoCorpusDish> dishes;
}

/// One labelled menu of the corpus.
final class KetoCorpusMenu {
  /// Creates a labelled menu.
  const new({
    required this.file,
    required this.id,
    required this.name,
    required this.language,
    required this.categories,
  });

  /// The file the menu was read from (its base name).
  final String file;

  /// The menu's id, unique across the corpus.
  final String id;

  /// The venue's name.
  final String name;

  /// The menu's language tag, e.g. `he`, `en` or `mixed`.
  final String language;

  /// The menu's categories, in menu order.
  final List<KetoCorpusCategory> categories;

  /// Every dish, in menu order.
  Iterable<KetoCorpusDish> get dishes =>
      categories.expand((category) => category.dishes);
}

/// [json]'s [key] as a [T], or a [FormatException] naming [where].
T _field<T>(Json json, String key, String where) {
  final value = json[key];
  if (value is T) return value;
  throw FormatException('$where: "$key" is ${value.runtimeType}, not $T');
}

/// [json]'s list [key] as JSON objects, empty when absent.
List<Json> _objects(Json json, String key, String where) {
  final value = json[key];
  if (value == null) return const <Json>[];
  if (value is! List<Object?>) {
    throw FormatException('$where: "$key" is not a list');
  }
  return [
    for (final entry in value)
      if (entry is Json)
        entry
      else
        throw FormatException('$where: "$key" holds a non-object'),
  ];
}

/// The verdict named [wire], or a [FormatException] naming [where].
DishVerdict _verdict(Object? wire, String where) {
  final verdict = wire is String ? DishVerdict.tryParse(wire) : null;
  if (verdict == null) {
    throw FormatException('$where: "$wire" is not a verdict');
  }
  return verdict;
}

/// Reads one corpus menu from [json], read from [file].
///
/// Throws a [FormatException] naming the file, and the dish where there is
/// one, for any shape the schema does not allow.
KetoCorpusMenu parseKetoCorpusMenu(Json json, {required String file}) {
  final menuId = _field<String>(json, 'id', file);
  return KetoCorpusMenu(
    file: file,
    id: menuId,
    name: _field<String>(json, 'name', file),
    language: _field<String>(json, 'language', file),
    categories: [
      for (final category in _objects(json, 'categories', file))
        KetoCorpusCategory(
          name: _field<String>(category, 'name', file),
          dishes: [
            for (final dish in _objects(category, 'dishes', file))
              _parseDish(dish, file),
          ],
        ),
    ],
  );
}

/// Reads one corpus dish from [json], in [file].
KetoCorpusDish _parseDish(Json json, String file) {
  final where = '$file#${json['id']}';
  final acceptable = json['acceptable'];
  if (acceptable != null && acceptable is! List<Object?>) {
    throw FormatException('$where: "acceptable" is not a list');
  }
  return KetoCorpusDish(
    id: _field<String>(json, 'id', where),
    name: _field<String>(json, 'name', where),
    description: json['description'] is String
        ? json['description']! as String
        : '',
    options: [
      for (final option in _objects(json, 'options', where))
        DishOption(
          name: _field<String>(option, 'name', where),
          values: _field<List<Object?>>(option, 'values', where).cast<String>(),
        ),
    ],
    expected: _verdict(json['expected'], where),
    acceptable: [
      for (final wire in (acceptable as List<Object?>?) ?? const <Object?>[])
        _verdict(wire, where),
    ],
    hiddenCarbs: [
      for (final flag in _objects(json, 'hiddenCarbs', where))
        KetoHiddenCarbLabel(
          source: _field<String>(flag, 'source', where),
          certainty: _field<String>(flag, 'certainty', where),
          term: flag['term'] is String ? flag['term']! as String : null,
        ),
    ],
  );
}

/// Every `*.json` menu in [dir], sorted by file name; empty when [dir] does
/// not exist.
List<KetoCorpusMenu> loadKetoCorpus(Directory dir) {
  if (!dir.existsSync()) return const <KetoCorpusMenu>[];
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final file in files)
      parseKetoCorpusMenu(
        jsonDecode(file.readAsStringSync()) as Json,
        file: file.uri.pathSegments.last,
      ),
  ];
}

/// [menu] as the app's own [Menu], every dish priced 0, addressed as a
/// scan by its id. The dish ids are the corpus ids, so the analysis maps
/// back one to one.
Menu toAppMenu(KetoCorpusMenu menu) => Menu(
  venueRef: VenueRef(source: MenuSource.scan, platformId: menu.id),
  currency: 'ILS',
  fetchedAt: _epoch,
  venueName: menu.name,
  categories: [
    for (var i = 0; i < menu.categories.length; i++)
      MenuCategory(
        id: '${menu.id}#c$i',
        name: menu.categories[i].name,
        dishes: [
          for (final dish in menu.categories[i].dishes)
            Dish(
              id: dish.id,
              name: dish.name,
              description: dish.description,
              price: 0,
              options: dish.options,
            ),
        ],
      ),
  ],
);

// ---------------------------------------------------------------------------
// The replay
// ---------------------------------------------------------------------------

/// The fixed time every replay is stamped with.
final DateTime _epoch = DateTime.utc(2026);

/// A [Clock] that always answers [_epoch].
final class _FixedClock implements Clock {
  const new();

  @override
  DateTime now() => _epoch;
}

/// One corpus dish and what the engine said about it.
final class KetoReplay {
  /// Creates a replay of [dish] on [menu].
  const new({
    required this.menu,
    required this.dish,
    required this.got,
    required this.flags,
  });

  /// The menu the dish is on.
  final KetoCorpusMenu menu;

  /// The labelled dish.
  final KetoCorpusDish dish;

  /// The engine's verdict, or null when it did not place the dish.
  final DishVerdict? got;

  /// The hidden-carb flags the engine raised on the dish.
  final List<HiddenCarb> flags;

  /// Whether [got] is a correct answer.
  bool get correct => dish.accepts(got);

  /// A dish labelled not green that came back green: the headline error.
  bool get isFalseGreen =>
      dish.expected != DishVerdict.orderAsIs &&
      got == DishVerdict.orderAsIs &&
      !dish.acceptable.contains(DishVerdict.orderAsIs);

  /// A dish labelled green or yellow that came back red.
  bool get isFalseRed =>
      dish.expected != DishVerdict.nonKeto &&
      got == DishVerdict.nonKeto &&
      !dish.acceptable.contains(DishVerdict.nonKeto);
}

/// [analysis]'s dishes by id; empty for a failed analysis.
Map<String, AnalysedDish> _byId(MenuAnalysis analysis) => switch (analysis) {
  MenuAnalysed(:final dishes) => {for (final dish in dishes) dish.dishId: dish},
  MenuAnalysisFailed() => const <String, AnalysedDish>{},
};

/// Every dish of [corpus], replayed through the rule engine with the
/// default options.
Future<List<KetoReplay>> replayKetoCorpus(List<KetoCorpusMenu> corpus) async {
  const classifier = HeuristicMenuClassifier(clock: _FixedClock());
  final out = <KetoReplay>[];
  for (final menu in corpus) {
    final analysed = _byId(await classifier.classify(toAppMenu(menu)));
    for (final dish in menu.dishes) {
      final got = analysed[dish.id];
      out.add(
        KetoReplay(
          menu: menu,
          dish: dish,
          got: got?.verdict,
          flags: got?.hiddenCarbs ?? const <HiddenCarb>[],
        ),
      );
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Hidden carbs
// ---------------------------------------------------------------------------

/// The normalised word set of a hidden-carb source.
Set<String> _sourceWords(String source) => TextNormaliser.words(source).toSet();

/// Whether two hidden-carb descriptions name the same thing: the
/// normalised words of one are a subset of the other's.
bool hiddenCarbSourcesMatch(String label, String found) {
  final a = _sourceWords(label);
  final b = _sourceWords(found);
  if (a.isEmpty || b.isEmpty) return false;
  return b.containsAll(a) || a.containsAll(b);
}

/// Whether the engine flag source [found] matches [label].
///
/// By the label's `term` when it has one (the exact dish text that points
/// at the flag): after `TextNormaliser.normalise`, [found] contains the
/// term or the term contains [found]. Only a label with no term falls back
/// to its English `source`, by [hiddenCarbSourcesMatch].
bool hiddenCarbLabelMatches(KetoHiddenCarbLabel label, String found) {
  final term = label.term;
  if (term == null) return hiddenCarbSourcesMatch(label.source, found);
  final t = TextNormaliser.normalise(term);
  final f = TextNormaliser.normalise(found);
  if (t.isEmpty || f.isEmpty) return false;
  return f.contains(t) || t.contains(f);
}

/// How many pairs of [labels] and engine sources [found] match, one to one,
/// greedily in label order.
int matchHiddenCarbs(List<KetoHiddenCarbLabel> labels, List<String> found) {
  final open = [...found];
  var matched = 0;
  for (final label in labels) {
    final at = open.indexWhere((f) => hiddenCarbLabelMatches(label, f));
    if (at >= 0) {
      open.removeAt(at);
      matched++;
    }
  }
  return matched;
}

// ---------------------------------------------------------------------------
// The report
// ---------------------------------------------------------------------------

/// The counts of one slice of the corpus: all of it, one menu or one
/// language.
final class KetoSlice {
  /// Counts [replays].
  factory of(Iterable<KetoReplay> replays) {
    final matrix = <DishVerdict, Map<DishVerdict?, int>>{
      for (final expected in DishVerdict.values)
        expected: <DishVerdict?, int>{
          for (final got in <DishVerdict?>[...DishVerdict.values, null]) got: 0,
        },
    };
    var total = 0;
    var correct = 0;
    var nonGreen = 0;
    var falseGreens = 0;
    var notRed = 0;
    var falseReds = 0;
    var unclassified = 0;
    var labels = 0;
    var flags = 0;
    var matched = 0;
    for (final replay in replays) {
      final expected = replay.dish.expected;
      matrix[expected]![replay.got] = matrix[expected]![replay.got]! + 1;
      total++;
      if (replay.correct) correct++;
      if (expected != DishVerdict.orderAsIs) nonGreen++;
      if (replay.isFalseGreen) falseGreens++;
      if (expected != DishVerdict.nonKeto) notRed++;
      if (replay.isFalseRed) falseReds++;
      if (replay.got == null) unclassified++;
      final found = [for (final f in replay.flags) f.source];
      labels += replay.dish.hiddenCarbs.length;
      flags += found.length;
      matched += matchHiddenCarbs(replay.dish.hiddenCarbs, found);
    }
    return KetoSlice._(
      matrix: matrix,
      total: total,
      correct: correct,
      nonGreen: nonGreen,
      falseGreens: falseGreens,
      notRed: notRed,
      falseReds: falseReds,
      unclassified: unclassified,
      hiddenCarbLabels: labels,
      hiddenCarbFlags: flags,
      hiddenCarbMatches: matched,
    );
  }

  const new _({
    required this.matrix,
    required this.total,
    required this.correct,
    required this.nonGreen,
    required this.falseGreens,
    required this.notRed,
    required this.falseReds,
    required this.unclassified,
    required this.hiddenCarbLabels,
    required this.hiddenCarbFlags,
    required this.hiddenCarbMatches,
  });

  /// Expected verdict, then verdict given (null: not placed), to a count.
  final Map<DishVerdict, Map<DishVerdict?, int>> matrix;

  /// Dishes in the slice.
  final int total;

  /// Dishes given the expected or an acceptable verdict.
  final int correct;

  /// Dishes not labelled `orderAsIs`: the false-green denominator.
  final int nonGreen;

  /// Dishes labelled not green that came back green.
  final int falseGreens;

  /// Dishes not labelled `nonKeto`: the false-red denominator.
  final int notRed;

  /// Dishes labelled green or yellow that came back red.
  final int falseReds;

  /// Dishes the engine gave no verdict.
  final int unclassified;

  /// Hidden-carb sources the labels name.
  final int hiddenCarbLabels;

  /// Hidden-carb flags the engine raised.
  final int hiddenCarbFlags;

  /// Label-flag pairs that matched, one to one.
  final int hiddenCarbMatches;

  /// [correct] over [total], or null for an empty slice.
  double? get accuracy => _ratio(correct, total);

  /// [falseGreens] over [nonGreen], or null when every dish is green.
  double? get falseGreenRate => _ratio(falseGreens, nonGreen);

  /// [falseReds] over [notRed], or null when every dish is red.
  double? get falseRedRate => _ratio(falseReds, notRed);

  /// Matched labels over all labels, or null when there are none.
  double? get hiddenCarbRecall => _ratio(hiddenCarbMatches, hiddenCarbLabels);

  /// Matched flags over all flags, or null while the engine raises none.
  double? get hiddenCarbPrecision => _ratio(hiddenCarbMatches, hiddenCarbFlags);
}

/// [hit] over [total], or null for an empty denominator.
double? _ratio(int hit, int total) => total == 0 ? null : hit / total;

/// The whole report over one replay.
final class KetoReport {
  /// Builds the report of [replays].
  factory of(List<KetoReplay> replays) {
    final byMenu = <String, List<KetoReplay>>{};
    final byLanguage = <String, List<KetoReplay>>{};
    for (final replay in replays) {
      (byMenu[replay.menu.id] ??= <KetoReplay>[]).add(replay);
      (byLanguage[replay.menu.language] ??= <KetoReplay>[]).add(replay);
    }
    final languages = byLanguage.keys.toList()..sort();
    return KetoReport._(
      replays: replays,
      all: KetoSlice.of(replays),
      perMenu: {
        for (final entry in byMenu.entries)
          entry.key: KetoSlice.of(entry.value),
      },
      perLanguage: {
        for (final language in languages)
          language: KetoSlice.of(byLanguage[language]!),
      },
    );
  }

  const new _({
    required this.replays,
    required this.all,
    required this.perMenu,
    required this.perLanguage,
  });

  /// Every dish replayed.
  final List<KetoReplay> replays;

  /// The whole corpus.
  final KetoSlice all;

  /// One slice per menu id, in corpus order.
  final Map<String, KetoSlice> perMenu;

  /// One slice per language tag, sorted.
  final Map<String, KetoSlice> perLanguage;

  /// Every false green, in corpus order.
  List<KetoReplay> get falseGreens => [
    for (final replay in replays)
      if (replay.isFalseGreen) replay,
  ];

  /// Every other disagreement: wrong but not a false green.
  List<KetoReplay> get otherDisagreements => [
    for (final replay in replays)
      if (!replay.correct && !replay.isFalseGreen) replay,
  ];
}

// ---------------------------------------------------------------------------
// Known misses
// ---------------------------------------------------------------------------

/// One reviewed false green the rules do not close yet.
final class KetoKnownMiss {
  /// Creates an entry for [dish] on [menu].
  const new({
    required this.menu,
    required this.dish,
    required this.expected,
    required this.got,
    required this.reason,
  });

  /// The entry for [replay], with [reason].
  factory of(KetoReplay replay, {required String reason}) => KetoKnownMiss(
    menu: replay.menu.id,
    dish: replay.dish.id,
    expected: replay.dish.expected.name,
    got: replay.got?.name ?? 'unclassified',
    reason: reason,
  );

  /// Reads one entry; throws a [FormatException] for any other shape.
  factory fromJson(Json json) {
    const keys = <String>{'menu', 'dish', 'expected', 'got', 'reason'};
    if (json.keys.toSet().difference(keys).isNotEmpty ||
        !json.keys.toSet().containsAll(keys)) {
      throw FormatException('a known miss has keys ${json.keys}, not $keys');
    }
    String text(String key) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value;
      throw FormatException('a known miss has a blank or non-string "$key"');
    }

    return KetoKnownMiss(
      menu: text('menu'),
      dish: text('dish'),
      expected: text('expected'),
      got: text('got'),
      reason: text('reason'),
    );
  }

  /// The menu id.
  final String menu;

  /// The dish id.
  final String dish;

  /// The verdict the corpus labels the dish with.
  final String expected;

  /// The verdict the rules give it (always `orderAsIs` for a false green).
  final String got;

  /// Why the rules cannot close it yet, or `TODO` before review.
  final String reason;

  /// The key a replay matches.
  String get key => ketoMissKey(menu, dish);

  /// Writes the form [KetoKnownMiss.fromJson] reads.
  Json toJson() => <String, Object?>{
    'menu': menu,
    'dish': dish,
    'expected': expected,
    'got': got,
    'reason': reason,
  };
}

/// The corpus-wide key of [dish] on [menu] (SCHEMA.md: `<menu id>/<dish id>`).
String ketoMissKey(String menu, String dish) => '$menu/$dish';

/// The key of [replay].
String replayKey(KetoReplay replay) =>
    ketoMissKey(replay.menu.id, replay.dish.id);

/// The entries of the known-misses file at [path]; empty when absent.
List<KetoKnownMiss> readKnownKetoMisses(String path) {
  final file = File(path);
  if (!file.existsSync()) return const <KetoKnownMiss>[];
  final json = jsonDecode(file.readAsStringSync());
  if (json is! List<Object?>) {
    throw FormatException('$path is not a JSON list');
  }
  return [
    for (final entry in json)
      if (entry is Json)
        KetoKnownMiss.fromJson(entry)
      else
        throw FormatException('$path holds a non-object'),
  ];
}

/// The known-misses list for [report]'s false greens: an existing entry
/// keeps its reason, a new one reads `TODO`.
List<KetoKnownMiss> regenerateKnownKetoMisses(
  KetoReport report,
  List<KetoKnownMiss> existing,
) {
  final reasons = {for (final entry in existing) entry.key: entry.reason};
  return [
    for (final replay in report.falseGreens)
      KetoKnownMiss.of(replay, reason: reasons[replayKey(replay)] ?? 'TODO'),
  ];
}

/// [entries] as the file's text: a two-space-indented JSON list.
String encodeKnownKetoMisses(List<KetoKnownMiss> entries) {
  final json = [for (final entry in entries) entry.toJson()];
  return '${const JsonEncoder.withIndent('  ').convert(json)}\n';
}

/// The false greens of [report] that [known] does not list.
List<KetoReplay> unlistedFalseGreens(
  KetoReport report,
  List<KetoKnownMiss> known,
) {
  final listed = {for (final entry in known) entry.key};
  return [
    for (final replay in report.falseGreens)
      if (!listed.contains(replayKey(replay))) replay,
  ];
}

/// The entries of [known] that are no longer a false green in [report], or
/// whose `expected` or `got` no longer says what the replay does.
List<KetoKnownMiss> staleKnownKetoMisses(
  KetoReport report,
  List<KetoKnownMiss> known,
) {
  final current = {
    for (final replay in report.falseGreens) replayKey(replay): replay,
  };
  bool stillMisses(KetoKnownMiss entry) {
    final replay = current[entry.key];
    return replay != null &&
        replay.dish.expected.name == entry.expected &&
        replay.got?.name == entry.got;
  }

  return [
    for (final entry in known)
      if (!stillMisses(entry)) entry,
  ];
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

/// [value] as a percentage with one decimal, or a dash for null.
String percent(double? value) =>
    value == null ? '-' : '${(100 * value).toStringAsFixed(1)}%';

/// The short column label of [verdict] (null: not placed).
String _short(DishVerdict? verdict) => switch (verdict) {
  DishVerdict.orderAsIs => 'green',
  DishVerdict.modifiable => 'yellow',
  DishVerdict.nonKeto => 'red',
  null => 'none',
};

/// The cells of one summary row for [slice], under [label].
List<String> _summaryCells(String label, KetoSlice slice) => [
  label,
  '${slice.total}',
  _cell(slice.correct, slice.total, slice.accuracy),
  _cell(slice.falseGreens, slice.nonGreen, slice.falseGreenRate),
  _cell(slice.falseReds, slice.notRed, slice.falseRedRate),
  '${slice.unclassified}',
  _cell(
    slice.hiddenCarbMatches,
    slice.hiddenCarbLabels,
    slice.hiddenCarbRecall,
  ),
  _cell(
    slice.hiddenCarbMatches,
    slice.hiddenCarbFlags,
    slice.hiddenCarbPrecision,
  ),
];

/// One `hit/total rate` cell.
String _cell(int hit, int total, double? rate) =>
    '$hit/$total ${percent(rate)}';

/// The header of every summary table.
const List<String> _summaryHeader = [
  'slice',
  'dishes',
  'accuracy',
  'false green',
  'false red',
  'unplaced',
  'hidden recall',
  'hidden precision',
];

/// [rows] as a fixed-width text table, or a markdown table when
/// [markdown].
String _table(List<List<String>> rows, {required bool markdown}) {
  if (markdown) {
    final out = <String>[
      '| ${rows.first.join(' | ')} |',
      '|${[for (final _ in rows.first) '---'].join('|')}|',
      for (final row in rows.skip(1)) '| ${row.join(' | ')} |',
    ];
    return out.join('\n');
  }
  final widths = [
    for (var c = 0; c < rows.first.length; c++)
      rows.map((row) => row[c].length).reduce((a, b) => a > b ? a : b),
  ];
  String line(List<String> row) =>
      [for (var c = 0; c < row.length; c++) row[c].padRight(widths[c])]
          .join('  ')
          .trimRight();
  return [for (final row in rows) '  ${line(row)}'].join('\n');
}

/// The rows of the confusion matrix of [slice].
List<List<String>> _matrixRows(KetoSlice slice) => [
  [
    r'expected \ got',
    for (final got in <DishVerdict?>[...DishVerdict.values, null]) _short(got),
  ],
  for (final expected in DishVerdict.values)
    [
      _short(expected),
      for (final got in <DishVerdict?>[...DishVerdict.values, null])
        '${slice.matrix[expected]![got]}',
    ],
];

/// One line naming [replay]'s dish and what went wrong.
String _describe(KetoReplay replay) =>
    '${replay.menu.id} / ${replay.dish.id} "${replay.dish.name}": '
    'expected ${replay.dish.expected.name}, '
    'got ${replay.got?.name ?? 'unclassified'}';

/// [report] as text, or as markdown when [markdown]: the summary, the
/// confusion matrix, the per-menu and per-language slices, then every
/// false green and every other disagreement.
String renderKetoReport(KetoReport report, {required bool markdown}) {
  final h = markdown ? '### ' : '';
  final bullet = markdown ? '- ' : '  ';
  final size = '${report.all.total} dishes, ${report.perMenu.length} menus';
  final falseGreens = report.falseGreens;
  final others = report.otherDisagreements;
  final sections = <String>[
    '${h}keto corpus accuracy (rules only, $size)',
    _table([
      _summaryHeader,
      _summaryCells('all', report.all),
    ], markdown: markdown),
    '${h}confusion matrix (rows: expected; columns: got)',
    _table(_matrixRows(report.all), markdown: markdown),
    '${h}per menu',
    _table([
      _summaryHeader,
      for (final entry in report.perMenu.entries)
        _summaryCells(entry.key, entry.value),
    ], markdown: markdown),
    '${h}per language',
    _table([
      _summaryHeader,
      for (final entry in report.perLanguage.entries)
        _summaryCells(entry.key, entry.value),
    ], markdown: markdown),
    '${h}false greens (${falseGreens.length})',
    if (falseGreens.isNotEmpty)
      [for (final r in falseGreens) '$bullet${_describe(r)}'].join('\n'),
    '${h}other disagreements (${others.length}, not gated)',
    if (others.isNotEmpty)
      [for (final r in others) '$bullet${_describe(r)}'].join('\n'),
  ];
  return sections.join(markdown ? '\n\n' : '\n');
}
