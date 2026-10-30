/// The heuristic (rules) classifier's vocabulary matcher
/// (`vocabulary_spec.md`; architecture.md §6.2).
///
/// [ClassificationRules.match] is the entire fallback engine: no HTTP, no
/// LLM, on-device, in milliseconds. It runs the bilingual vocabulary in
/// `constants.dart` over one dish's text and returns what it found.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/vocab_religious.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/text_normaliser.dart';
import 'package:ketoclub/utils/trigger_patterns.dart';

export 'package:ketoclub/utils/trigger_patterns.dart';

/// A compiled non-keto-base trigger: its dictionary key (for guard and
/// label lookups) and the pattern that finds it in normalised text.
typedef _CompiledBase = ({String key, RegExp pattern});

/// A compiled carb-modifier trigger: its dictionary key (for guard and
/// suppression lookups), its pattern, and its waiter sentence.
typedef _CompiledModifier = ({String key, RegExp pattern, String sentence});

/// A compiled hidden-carb trigger (issue #213 on the rules path): its
/// dictionary key (for its per-trigger guard), its pattern, and its flag.
typedef _CompiledHidden = ({
  String key,
  RegExp pattern,
  HiddenCarbTrigger flag,
});

/// One unguarded hidden-carb occurrence; `end` is exclusive.
typedef _HiddenOccurrence = ({int start, int end, HiddenCarbTrigger flag});

/// One surviving (unguarded) carb-modifier occurrence, in match order.
/// `end` is exclusive, so `start`..`end` is the matched span — which the
/// carb-only-dish rule blanks out to see what else a dish name says.
typedef _Occurrence = ({int start, int end, String key, String sentence});

/// The entries where the permissive prefix lookbehind is unsafe: folded
/// `חלה` also spells "began" (a common verb form), and `שמרים` with a מ
/// prefix is `משמרים` ("preservatives", as in "ללא חומרים משמרים"), and
/// `הפוך` collides with "to flip/reverse" (e.g. `להפוך`), and `חלבה`
/// with a מ prefix is `מחלבה` ("dairy", issue #273), so all of them are
/// compiled with no permissive prefix — see [hebrewTriggerPattern]'s
/// `allowPrefix`. `חלבה`'s two commonest particles (`וחלבה`, `בחלבה`)
/// are entries of their own, also prefix-free; `החלבה` deliberately is
/// not, so the golden exporter's ה-prefix probe still finds `חלבה`
/// prefix-free. Applied to both [_compileBasesHe] and [_compileCarbHe].
const Set<String> _noPrefixHebrewTriggers = <String>{
  'חלה',
  'שמרים',
  'הפוך',
  'חלבה',
  'וחלבה',
  'בחלבה',
};

/// Compiles [nonKetoBasesEn], normalising each key at compile time so a
/// human-readable, correctly-spelled `constants.dart` still matches
/// normalised dish text. Each base also matches its regular `s`/`es`
/// plural (issue #274) under its own key, so the singular's guard and
/// label apply to "dumplings" and "zucchini noodles" alike.
List<_CompiledBase> _compileBasesEn() => nonKetoBasesEn
    .map(
      (key) => (
        key: key,
        pattern: latinTriggerPattern(
          TextNormaliser.normalise(key),
          allowPlural: true,
        ),
      ),
    )
    .toList(growable: false);

/// Compiles [nonKetoBasesHe], same rule as [_compileBasesEn].
List<_CompiledBase> _compileBasesHe() => nonKetoBasesHe
    .map(
      (key) => (
        key: key,
        pattern: hebrewTriggerPattern(
          TextNormaliser.normalise(key),
          allowPrefix: !_noPrefixHebrewTriggers.contains(key),
        ),
      ),
    )
    .toList(growable: false);

/// Compiles [carbModifiersEn], same rule as [_compileBasesEn].
List<_CompiledModifier> _compileCarbEn() => carbModifiersEn.entries
    .map(
      (entry) => (
        key: entry.key,
        pattern: latinTriggerPattern(TextNormaliser.normalise(entry.key)),
        sentence: entry.value,
      ),
    )
    .toList(growable: false);

/// Compiles [carbModifiersHe], same rule as [_compileBasesHe]: entries
/// in [_noPrefixHebrewTriggers] disable the permissive prefix.
List<_CompiledModifier> _compileCarbHe() => carbModifiersHe.entries
    .map(
      (entry) => (
        key: entry.key,
        pattern: hebrewTriggerPattern(
          TextNormaliser.normalise(entry.key),
          allowPrefix: !_noPrefixHebrewTriggers.contains(entry.key),
        ),
        sentence: entry.value,
      ),
    )
    .toList(growable: false);

/// Compiles a dietary-rule trigger list (issue #56) in English, same
/// rule as [_compileBasesEn]. Reuses [_CompiledBase]: a dietary trigger
/// is, like a base, a key plus a pattern, with no sentence of its own —
/// the rule's one sentence is chosen by the dish's language instead.
List<_CompiledBase> _compileDietaryEn(List<String> triggers) => triggers
    .map(
      (key) => (
        key: key,
        pattern: latinTriggerPattern(TextNormaliser.normalise(key)),
      ),
    )
    .toList(growable: false);

/// Compiles a dietary-rule trigger list (issue #56) in Hebrew, through
/// [hebrewTriggerPattern]'s unicode lookaround — never `\b`.
List<_CompiledBase> _compileDietaryHe(List<String> triggers) => triggers
    .map(
      (key) => (
        key: key,
        pattern: hebrewTriggerPattern(TextNormaliser.normalise(key)),
      ),
    )
    .toList(growable: false);

/// Compiles [hiddenCarbTriggersEn] with the Latin word boundary, each key
/// normalised at compile time like every other table.
List<_CompiledHidden> _compileHiddenEn() => hiddenCarbTriggersEn.entries
    .map(
      (entry) => (
        key: entry.key,
        pattern: latinTriggerPattern(TextNormaliser.normalise(entry.key)),
        flag: entry.value,
      ),
    )
    .toList(growable: false);

/// Compiles [hiddenCarbTriggersHe] through [hebrewTriggerPattern]'s
/// unicode lookaround, with the permissive prefix (`במרינדה`, `ברוטב
/// שום`) for every entry.
List<_CompiledHidden> _compileHiddenHe() => hiddenCarbTriggersHe.entries
    .map(
      (entry) => (
        key: entry.key,
        pattern: hebrewTriggerPattern(TextNormaliser.normalise(entry.key)),
        flag: entry.value,
      ),
    )
    .toList(growable: false);

/// Compiled once, on first use of this library (Dart top-level `final`
/// fields initialise lazily).
final List<_CompiledBase> _baseEn = _compileBasesEn();

/// See [_baseEn].
final List<_CompiledBase> _baseHe = _compileBasesHe();

/// See [_baseEn].
final List<_CompiledModifier> _carbEn = _compileCarbEn();

/// See [_baseEn].
final List<_CompiledModifier> _carbHe = _compileCarbHe();

/// See [_baseEn]; the hidden-carb triggers (issue #213).
final List<_CompiledHidden> _hiddenEn = _compileHiddenEn();

/// See [_hiddenEn].
final List<_CompiledHidden> _hiddenHe = _compileHiddenHe();

/// The hidden-carb guard phrases, both languages, that answer a flag of
/// [concern] (`sugar`, `flour` or `sugarOrFlour`; issue #213): the `any`
/// phrases, the `sugar` ones unless the flag is about flour alone, and
/// the `flour` ones unless it is about sugar alone.
List<String> _hiddenGuardPhrasesFor(String concern) => <String>[
  for (final table in [hiddenCarbGuardPhrasesEn, hiddenCarbGuardPhrasesHe])
    for (final MapEntry(key: answers, value: phrases) in table.entries)
      if (answers == 'any' ||
          (answers == 'sugar' && concern != 'flour') ||
          (answers == 'flour' && concern != 'sugar'))
        ...phrases,
];

/// [_hiddenGuardPhrasesFor] each concern, computed once.
final Map<String, List<String>> _hiddenGuardPhrases = <String, List<String>>{
  for (final concern in const ['sugar', 'flour', 'sugarOrFlour'])
    concern: _hiddenGuardPhrasesFor(concern),
};

/// See [_baseEn]; the seed-oil rule's triggers (issue #56).
final List<_CompiledBase> _seedOilEn = _compileDietaryEn(seedOilTriggersEn);

/// See [_seedOilEn].
final List<_CompiledBase> _seedOilHe = _compileDietaryHe(seedOilTriggersHe);

/// See [_baseEn]; the dairy-free rule's triggers (issue #56).
final List<_CompiledBase> _dairyEn = _compileDietaryEn(dairyTriggersEn);

/// See [_dairyEn].
final List<_CompiledBase> _dairyHe = _compileDietaryHe(dairyTriggersHe);

/// See [_baseEn]; the carnivore rule's plant triggers (issue #56).
final List<_CompiledBase> _plantEn = _compileDietaryEn(plantTriggersEn);

/// See [_plantEn].
final List<_CompiledBase> _plantHe = _compileDietaryHe(plantTriggersHe);

/// See [_baseEn]; the filling words the carb-only rule defers to (issue
/// #191).
final List<_CompiledBase> _fillingProteinEn = _compileDietaryEn(
  fillingProteinTriggersEn,
);

/// See [_fillingProteinEn].
final List<_CompiledBase> _fillingProteinHe = _compileDietaryHe(
  fillingProteinTriggersHe,
);

/// Every carb-only qualifier word, both languages, normalised once
/// (issue #191) — the set [ClassificationRules.carbOnlyBase] tests a dish
/// name's leftover words against. The toppings ([carbOnlyToppingsEn],
/// [carbOnlyToppingsHe]) qualify too (issue #273).
final Set<String> _carbOnlyQualifiers = <String>{
  for (final word in carbOnlyQualifiersEn) TextNormaliser.normalise(word),
  for (final word in carbOnlyQualifiersHe) TextNormaliser.normalise(word),
  for (final word in carbOnlyToppingsEn) TextNormaliser.normalise(word),
  for (final word in carbOnlyToppingsHe) TextNormaliser.normalise(word),
};

/// See [_baseEn]; the toppings [ClassificationRules.describesFilling]
/// blanks out before it looks for a filling (issue #273), English then
/// Hebrew, in list order.
final List<_CompiledBase> _toppings = <_CompiledBase>[
  ..._compileDietaryEn(carbOnlyToppingsEn),
  ..._compileDietaryHe(carbOnlyToppingsHe),
];

/// No dietary rule but dairy has guards; the seed-oil and plant tables
/// scan against this empty map.
const Map<String, GuardWords> _noGuards = <String, GuardWords>{};

/// The words in [windowWords], padded with spaces, joined into a single
/// string — matched against each of [phrases] (already normalised) with
/// space-padding of its own, so a multi-word guard phrase (`low carb`)
/// only matches when it is literally adjacent within the window, while a
/// single-word guard (`keto`) matches either window slot.
bool _windowContainsAnyPhrase(List<String> windowWords, List<String> phrases) {
  if (windowWords.isEmpty || phrases.isEmpty) return false;
  final windowText = ' ${windowWords.join(' ')} ';
  for (final phrase in phrases) {
    if (windowText.contains(' ${TextNormaliser.normalise(phrase)} ')) {
      return true;
    }
  }
  return false;
}

/// True when a rescuing word from [guard] sits within two words of the
/// match spanning [start]-[end] in [haystack] (D-V1): `guard.before` in
/// the up-to-two words immediately preceding it, `guard.after` in the
/// up-to-two words immediately following it.
bool _isGuarded(String haystack, int start, int end, GuardWords? guard) {
  if (guard == null) return false;
  if (guard.before.isNotEmpty) {
    final beforeText = haystack.substring(0, start).trimRight();
    if (beforeText.isNotEmpty) {
      final words = beforeText.split(' ');
      final window = words.length <= 2
          ? words
          : words.sublist(words.length - 2);
      if (_windowContainsAnyPhrase(window, guard.before)) return true;
    }
  }
  if (guard.after.isNotEmpty) {
    final afterText = haystack.substring(end).trimLeft();
    if (afterText.isNotEmpty) {
      final words = afterText.split(' ');
      final window = words.length <= 2 ? words : words.sublist(0, 2);
      if (_windowContainsAnyPhrase(window, guard.after)) return true;
    }
  }
  return false;
}

/// True when the normalised dish [name] contains, as whole words, one of
/// the keto-substitute phrases [ketoSubstituteNameWordsEn] or
/// [ketoSubstituteNameWordsHe] list for [key] (issue #273): the guard
/// that reaches past the two-word window, across the whole name.
bool _isNameGuarded(String name, String key) {
  final phrases =
      ketoSubstituteNameWordsEn[key] ?? ketoSubstituteNameWordsHe[key];
  if (phrases == null || name.isEmpty) return false;
  return _windowContainsAnyPhrase(<String>[name], phrases);
}

/// Whether the match of [key] spanning [start]-[end] in [haystack] is
/// cancelled: by its two-word-window guard in [guards] (D-V1), or by a
/// keto substitute named anywhere in the dish [name] (issue #273).
bool _isCancelled(
  String haystack,
  String name,
  int start,
  int end,
  String key,
  Map<String, GuardWords> guards,
) => _isGuarded(haystack, start, end, guards[key]) || _isNameGuarded(name, key);

/// The earliest-occurring, unguarded non-keto-base match in [haystack]
/// across both language tables, or null when none survives. [name] is
/// the normalised dish name the name-wide substitute guard reads.
///
/// "Earliest-occurring" (smallest match-start offset) is this file's own
/// tie-break for when more than one base matches one dish — the spec
/// does not name one, since [RuleMatch.baseLabel] holds a single label.
({int start, String label})? _firstUnguardedBaseMatch(
  String haystack, {
  required String name,
}) {
  ({int start, String label})? best;
  void scan(
    List<_CompiledBase> table,
    Map<String, GuardWords> guards,
    Map<String, String> labels,
  ) {
    for (final entry in table) {
      for (final match in entry.pattern.allMatches(haystack)) {
        if (_isCancelled(
          haystack,
          name,
          match.start,
          match.end,
          entry.key,
          guards,
        )) {
          continue;
        }
        final current = best;
        if (current == null || match.start < current.start) {
          best = (start: match.start, label: labels[entry.key] ?? entry.key);
        }
      }
    }
  }

  scan(_baseEn, ketoQualifierGuardsEn, nonKetoBaseLabelsEn);
  scan(_baseHe, ketoQualifierGuardsHe, nonKetoBaseLabelsHe);
  return best;
}

/// Whether any trigger in [tables] — each paired with its guard map —
/// survives its guards somewhere in [haystack] (issue #56).
bool _anyUnguardedMatch(
  String haystack,
  List<(List<_CompiledBase>, Map<String, GuardWords>)> tables,
) {
  for (final (table, guards) in tables) {
    for (final entry in table) {
      for (final match in entry.pattern.allMatches(haystack)) {
        if (!_isGuarded(haystack, match.start, match.end, guards[entry.key])) {
          return true;
        }
      }
    }
  }
  return false;
}

/// Every unguarded carb-modifier occurrence in [haystack], across both
/// language tables, in match-start order. [name] is the normalised dish
/// name, as for [_firstUnguardedBaseMatch].
List<_Occurrence> _unguardedModifierOccurrences(
  String haystack, {
  required String name,
}) {
  final occurrences = <_Occurrence>[];
  void scan(List<_CompiledModifier> table, Map<String, GuardWords> guards) {
    for (final entry in table) {
      for (final match in entry.pattern.allMatches(haystack)) {
        if (_isCancelled(
          haystack,
          name,
          match.start,
          match.end,
          entry.key,
          guards,
        )) {
          continue;
        }
        occurrences.add((
          start: match.start,
          end: match.end,
          key: entry.key,
          sentence: entry.sentence,
        ));
      }
    }
  }

  scan(_carbEn, ketoQualifierGuardsEn);
  scan(_carbHe, ketoQualifierGuardsHe);
  occurrences.sort((a, b) => a.start.compareTo(b.start));
  return occurrences;
}

/// The occurrences [triggerSuppresses] leaves standing, in their order:
/// the ones whose sentences [_sentencesAfterSuppression] keeps.
List<_Occurrence> _unsuppressed(List<_Occurrence> occurrences) {
  final suppressedKeys = <String>{};
  for (final occurrence in occurrences) {
    final victims = triggerSuppresses[occurrence.key];
    if (victims != null) suppressedKeys.addAll(victims);
  }
  return <_Occurrence>[
    for (final occurrence in occurrences)
      if (!suppressedKeys.contains(occurrence.key)) occurrence,
  ];
}

/// The words around the match spanning [start]-[end] in [haystack]: up to
/// [count] words before it and up to [count] after it, read the way
/// [_isGuarded] reads its window, and the offsets where that window
/// starts and ends (the match's own offsets on a side with no words).
({List<String> before, List<String> after, int start, int end}) _window(
  String haystack,
  int start,
  int end,
  int count,
) {
  var before = const <String>[];
  var windowStart = start;
  final beforeText = haystack.substring(0, start).trimRight();
  if (beforeText.isNotEmpty) {
    final words = beforeText.split(' ');
    before = words.length <= count
        ? words
        : words.sublist(words.length - count);
    windowStart = beforeText.length - before.join(' ').length;
  }
  var after = const <String>[];
  var windowEnd = end;
  final rest = haystack.substring(end);
  final afterText = rest.trimLeft();
  if (afterText.isNotEmpty) {
    final words = afterText.split(' ');
    after = words.length <= count ? words : words.sublist(0, count);
    windowEnd = end + rest.length - afterText.length + after.join(' ').length;
  }
  return (before: before, after: after, start: windowStart, end: windowEnd);
}

/// The hidden-carb flags in [haystack] (issue #213 on the rules path;
/// architecture.md §9.4 rule 5a), written in Hebrew when [hebrew] and in
/// English otherwise. [modifiers] are the surviving carb-modifier
/// occurrences in the same [haystack].
///
/// In order: a trigger is dropped when its per-trigger guard
/// ([hiddenCarbTriggerGuardsEn]/`He`, D-V1's two-word window) or a guard
/// phrase answering its concern ([hiddenCarbGuardPhrasesEn]/`He`,
/// [hiddenCarbWindowWords] words either side) cancels it; of overlapping
/// triggers the earliest, and at
/// one start the longest, is kept; a trigger is **covered**, and dropped,
/// when a carb modifier's match overlaps it, or when its flag is about
/// sugar alone and a sweetener modifier ([hiddenCarbCoveringModifiers])
/// sits in its window, because that modifier's sentence already asks for
/// the sugar to go; flags with the same source are kept once; at most
/// [maxHiddenCarbsPerDish] survive, in text order.
List<HiddenCarb> _hiddenCarbsIn(
  String haystack, {
  required List<_Occurrence> modifiers,
  required bool hebrew,
}) {
  final found = <_HiddenOccurrence>[];
  void scan(List<_CompiledHidden> table, Map<String, GuardWords> guards) {
    for (final entry in table) {
      for (final match in entry.pattern.allMatches(haystack)) {
        if (_isGuarded(haystack, match.start, match.end, guards[entry.key])) {
          continue;
        }
        final window = _window(
          haystack,
          match.start,
          match.end,
          hiddenCarbWindowWords,
        );
        final phrases =
            _hiddenGuardPhrases[entry.flag.concern] ?? const <String>[];
        if (_windowContainsAnyPhrase(window.before, phrases) ||
            _windowContainsAnyPhrase(window.after, phrases)) {
          continue;
        }
        found.add((start: match.start, end: match.end, flag: entry.flag));
      }
    }
  }

  scan(_hiddenEn, hiddenCarbTriggerGuardsEn);
  scan(_hiddenHe, hiddenCarbTriggerGuardsHe);
  // A total order (no two triggers share a span), so the result never
  // depends on the sort's stability.
  found.sort(
    (a, b) => a.start != b.start
        ? a.start.compareTo(b.start)
        : b.end.compareTo(a.end),
  );

  final kept = <_HiddenOccurrence>[];
  for (final occurrence in found) {
    final overlapsKept = kept.any(
      (other) => occurrence.start < other.end && other.start < occurrence.end,
    );
    if (!overlapsKept) kept.add(occurrence);
  }

  final flags = <HiddenCarb>[];
  final sources = <String>{};
  for (final occurrence in kept) {
    if (flags.length >= maxHiddenCarbsPerDish) break;
    final flag = occurrence.flag;
    final window = _window(
      haystack,
      occurrence.start,
      occurrence.end,
      hiddenCarbWindowWords,
    );
    final covered = modifiers.any(
      (modifier) =>
          (modifier.start < occurrence.end &&
              occurrence.start < modifier.end) ||
          (flag.concern == 'sugar' &&
              hiddenCarbCoveringModifiers.contains(modifier.key) &&
              modifier.start < window.end &&
              window.start < modifier.end),
    );
    if (covered) continue;
    final source = hebrew ? flag.sourceHe : flag.sourceEn;
    if (!sources.add(source)) continue;
    flags.add(
      HiddenCarb(
        source: source,
        certainty: HiddenCarbCertainty.values.byName(flag.certainty),
        waiterQuestion: hebrew ? flag.questionHe : flag.questionEn,
      ),
    );
  }
  return flags;
}

/// Applies [triggerSuppresses] to [occurrences] and returns the
/// deduplicated sentence list, in match-start order: the more specific
/// phrase's trigger wins, so `sweet potato` does not also emit the bare
/// `potato` sentence.
List<String> _sentencesAfterSuppression(List<_Occurrence> occurrences) {
  final firedKeys = occurrences.map((occurrence) => occurrence.key).toSet();
  final suppressedKeys = <String>{};
  for (final key in firedKeys) {
    final victims = triggerSuppresses[key];
    if (victims != null) suppressedKeys.addAll(victims);
  }

  final sentences = <String>{};
  for (final occurrence in occurrences) {
    if (suppressedKeys.contains(occurrence.key)) continue;
    sentences.add(occurrence.sentence);
  }
  return sentences.toList(growable: false);
}

/// What the rule vocabulary found in one dish's text.
@immutable
final class RuleMatch {
  /// Creates a match result. [baseLabel] must be non-null exactly when
  /// [isNonKeto] is true.
  const new({
    required this.isNonKeto,
    required this.instructions,
    this.baseLabel,
    this.hiddenCarbs = const <HiddenCarb>[],
  });

  /// True when a non-keto base matched, which makes the dish red.
  final bool isNonKeto;

  /// Display label of the matched base, for rendering `{base}` in
  /// [redWhyEn]/[redWhyHe]. Non-null iff [isNonKeto]. Always the clean,
  /// unfolded (correctly-spelled) form — this string is read aloud.
  final String? baseLabel;

  /// Deduplicated waiter sentences, in the language of the dish text.
  /// Empty when [isNonKeto] or when nothing matched.
  final List<String> instructions;

  /// The hidden-carb flags the vocabulary raised (issue #213 on the rules
  /// path), in the language of the dish text, none covered by one of
  /// [instructions], at most [maxHiddenCarbsPerDish]. Empty when
  /// [isNonKeto]: a red drops its flags (§9.4 rule 5a). A flag never adds
  /// to [instructions]; the heuristic classifier decides what it does to
  /// the verdict.
  final List<HiddenCarb> hiddenCarbs;

  @override
  bool operator ==(Object other) =>
      other is RuleMatch &&
      other.isNonKeto == isNonKeto &&
      other.baseLabel == baseLabel &&
      _listEquals(other.instructions, instructions) &&
      _listEquals(other.hiddenCarbs, hiddenCarbs);

  @override
  int get hashCode => Object.hash(
    isNonKeto,
    baseLabel,
    Object.hashAll(instructions),
    Object.hashAll(hiddenCarbs),
  );

  @override
  String toString() => isNonKeto
      ? 'RuleMatch(nonKeto: $baseLabel)'
      : 'RuleMatch(modifiers: $instructions, hiddenCarbs: $hiddenCarbs)';
}

/// Element-wise list equality. Not shared with other files in this
/// package: each keeps its own copy so it stays self-contained
/// (architecture.md §18.2).
bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The Hebrew maqaf, U+05BE. [AllergenMatcher] reads it as a space; the
/// removal check here does the same, so "ללא־שומשום" is a removal value
/// for the allergen pass as it is for [AllergenMatcher.findInDish].
const String _maqaf = '־';

/// [Certainty] by name from a matcher hit's [TriggerCertainty]; the two
/// enums share their names (a test in `concern_test.dart` pins it).
Certainty _certaintyOf(TriggerCertainty certainty) =>
    Certainty.values.byName(certainty.name);

/// How much stronger [a] is than [b]: positive when [a] is the surer one
/// (stated > likely > suspected).
int _compareCertainty(Certainty a, Certainty b) => b.index.compareTo(a.index);

/// The slice of [raw] that produced the span [start]-[end] of
/// `AllergenMatcher.matchText(raw)` (ALG-04b): the menu's own spelling,
/// case, points and prefix letters, which the UI shows and the waiter
/// sentence names.
///
/// The match text of a prefix of [raw] is a prefix of the match text of
/// [raw] (every normalising step is local; leading and trailing non-letter
/// runs are trimmed, never moved), and its length never shrinks as the
/// prefix grows, so each end is found by a binary search for the shortest
/// raw prefix whose match text reaches it. A start that lands on the low
/// half of a surrogate pair steps back over the high half.
String _rawSlice(String raw, int start, int end) {
  int shortestPrefixReaching(int length) {
    var low = 0;
    var high = raw.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (AllergenMatcher.matchText(raw.substring(0, mid)).length >= length) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low;
  }

  var rawStart = shortestPrefixReaching(start + 1) - 1;
  if (rawStart > 0 &&
      _isLowSurrogate(raw.codeUnitAt(rawStart)) &&
      _isHighSurrogate(raw.codeUnitAt(rawStart - 1))) {
    rawStart--;
  }
  final rawEnd = shortestPrefixReaching(end);
  if (rawStart < 0 || rawEnd <= rawStart) {
    // Unreachable for a span the matcher reported; the normalised slice
    // is the honest fallback.
    return AllergenMatcher.matchText(raw).substring(start, end);
  }
  return raw.substring(rawStart, rawEnd);
}

/// Whether [unit] is the high (leading) half of a UTF-16 surrogate pair.
bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

/// Whether [unit] is the low (trailing) half of a UTF-16 surrogate pair.
bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

/// One [Concern] per allergen hit in [hits], read from [raw] where
/// [source] says.
Iterable<Concern> _findingsIn(
  String raw,
  ConcernSource source,
  List<AllergenHit> hits,
) sync* {
  for (final hit in hits) {
    final lowered = hit.hidden || hit.guarded;
    yield Concern(
      restrictionId: hit.id,
      source: hit.hidden ? ConcernSource.hidden : source,
      certainty: _certaintyOf(hit.certainty),
      tier: lowered ? EvidenceTier.inferred : EvidenceTier.stated,
      matchedText: _rawSlice(raw, hit.start, hit.end),
    );
  }
}

/// One side of the meat-with-dairy rule: a hit, the part it was read
/// from, and that part's source.
typedef _SideHit = ({AllergenHit hit, String raw, ConcernSource source});

/// The surest of [hits] (stated > likely > suspected), the earliest at a
/// tie; null when there is none.
_SideHit? _surest(Iterable<_SideHit> hits) {
  _SideHit? best;
  for (final candidate in hits) {
    if (best == null ||
        candidate.hit.certainty.index < best.hit.certainty.index) {
      best = candidate;
    }
  }
  return best;
}

/// Whether two spans of one part overlap.
bool _overlaps(AllergenHit a, AllergenHit b) =>
    a.start < b.end && b.start < a.end;

/// The kosher meat-with-dairy concern of one dish (issue #342; file 11
/// §24.5), from its unguarded [meat] hits ([meatWithDairyMeatVocabulary])
/// and its unguarded stated or likely Milk hits ([dairy]); null unless
/// both sides have one.
///
/// Both sides in the name, the description or a hidden source → stated
/// when the surest of each is stated, suspected otherwise, with the dairy
/// side's source; one side only in an option → suspected, source
/// [ConcernSource.option], since leaving the option off may settle it.
/// The matched text is the meat words, [meatWithDairyJoiner], then the
/// dairy words ("Ribeye + butter").
Concern? _meatWithDairy(List<_SideHit> meat, List<_SideHit> dairy) {
  bool inDish(_SideHit side) => side.source != ConcernSource.option;
  final meatInDish = _surest(meat.where(inDish));
  final dairyInDish = _surest(dairy.where(inDish));
  final meatSide = meatInDish ?? _surest(meat);
  final dairySide = dairyInDish ?? _surest(dairy);
  if (meatSide == null || dairySide == null) return null;
  final inOption = meatInDish == null || dairyInDish == null;
  final stated =
      !inOption &&
      meatSide.hit.certainty == TriggerCertainty.stated &&
      dairySide.hit.certainty == TriggerCertainty.stated;
  final ConcernSource source;
  if (inOption) {
    source = ConcernSource.option;
  } else if (dairySide.hit.hidden) {
    source = ConcernSource.hidden;
  } else {
    source = dairySide.source;
  }
  return Concern(
    restrictionId: RestrictionId.kosher,
    source: source,
    certainty: stated ? Certainty.stated : Certainty.suspected,
    tier: stated ? EvidenceTier.stated : EvidenceTier.inferred,
    matchedText:
        '${_rawSlice(meatSide.raw, meatSide.hit.start, meatSide.hit.end)}'
        '$meatWithDairyJoiner'
        '${_rawSlice(dairySide.raw, dairySide.hit.start, dairySide.hit.end)}',
  );
}

/// Runs the bilingual heuristic vocabulary over one dish's text
/// (`vocabulary_spec.md`; architecture.md §6.2).
abstract final class ClassificationRules {
  /// Whether [guard] cancels the match spanning [start]-[end] (`end`
  /// exclusive) in the normalised [haystack] — the guard window every
  /// table in this file uses (D-V1): a phrase from `guard.before` among
  /// the up-to-two words just before the match, or one from `guard.after`
  /// among the up-to-two words just after it. Each phrase is normalised
  /// first, and a multi-word phrase must be adjacent inside the window.
  /// A null [guard] cancels nothing.
  ///
  /// Made public for the allergen matcher (ALG-01); since ALG-04a that
  /// matcher checks only the slot adjacent to a term, with its own helper
  /// in `utils/allergens/allergen_matcher.dart`, and lowers rather than
  /// cancels. This window is the keto engine's alone. Never throws.
  static bool isGuarded(
    String haystack,
    int start,
    int end,
    GuardWords? guard,
  ) => _isGuarded(haystack, start, end, guard);

  /// Runs both the English and Hebrew vocabularies over [rawText]
  /// unconditionally — Israeli menus mix scripts. Never throws.
  ///
  /// Order: keto-substitute guards (D-V1) cancel matches first; then a
  /// surviving non-keto base makes the dish red with no instructions;
  /// then carb-modifier matches (after suppression, §"triggerSuppresses")
  /// make it yellow with their deduplicated sentences. The whole of
  /// [rawText] is read as the dish name for the name-wide substitute
  /// guard (issue #273).
  static RuleMatch match(String rawText) {
    final haystack = TextNormaliser.normalise(rawText);

    final base = _firstUnguardedBaseMatch(haystack, name: haystack);
    if (base != null) {
      return RuleMatch(
        isNonKeto: true,
        baseLabel: base.label,
        instructions: const <String>[],
      );
    }

    final occurrences = _unguardedModifierOccurrences(haystack, name: haystack);
    return RuleMatch(
      isNonKeto: false,
      instructions: _sentencesAfterSuppression(occurrences),
      hiddenCarbs: _hiddenCarbsIn(
        haystack,
        modifiers: _unsuppressed(occurrences),
        hebrew: TextNormaliser.containsHebrew(rawText),
      ),
    );
  }

  /// Runs the vocabulary over one whole [dish] rather than a flat string
  /// (issues #191, #192), in this order:
  ///
  /// 1. A name that is nothing but a starch or a bread ([carbOnlyBase])
  ///    is red — "פיתה רגילה", "Portion of fries" — unless the description
  ///    or an option names a filling ([describesFilling]): D-V3's "serve
  ///    it without the pita" cannot be followed when the pita is the dish,
  ///    but "לאפה" filled with shawarma is exactly the dish D-V3 means.
  /// 2. A non-keto base is matched on [TextNormaliser.dishCoreText] —
  ///    the name and description only. Option text can make a dish
  ///    yellow, never red: an option group named after a red base is
  ///    something the dish can be ordered *as*, not what it is.
  /// 3. Carb modifiers are matched on [TextNormaliser.dishRulesText],
  ///    which keeps a "choice of side" value and drops removal values
  ///    ("ללא אלף האיים"), so a burger is not told to swap a dressing it
  ///    only ever had the option to leave off.
  ///
  /// Steps 2 and 3, and the option scan, also apply the name-wide
  /// substitute guard (issue #273) with the dish's own name: "Pizza with
  /// cauliflower crust" is not red, and a name with `keto` in it rescues
  /// the description's `rice` too.
  ///
  /// A dish that is not red also carries its hidden-carb flags (issue
  /// #213 on the rules path), read from the same rules text as step 3 and
  /// written in that text's language; see [RuleMatch.hiddenCarbs].
  ///
  /// [match] stays for callers with only a string; the heuristic
  /// classifier uses this. Never throws.
  static RuleMatch matchDish(Dish dish) {
    final carbOnly = carbOnlyBase(dish.name);
    if (carbOnly != null && !describesFilling(dish)) {
      return RuleMatch(
        isNonKeto: true,
        baseLabel: carbOnly,
        instructions: const <String>[],
      );
    }

    final name = TextNormaliser.normalise(dish.name);
    final base = _firstUnguardedBaseMatch(
      TextNormaliser.dishCoreText(dish),
      name: name,
    );
    if (base != null) {
      return RuleMatch(
        isNonKeto: true,
        baseLabel: base.label,
        instructions: const <String>[],
      );
    }

    final rulesText = TextNormaliser.dishRulesText(dish);
    final occurrences = _unguardedModifierOccurrences(rulesText, name: name);
    final sentences = _sentencesAfterSuppression(occurrences);
    final hiddenCarbs = _hiddenCarbsIn(
      rulesText,
      modifiers: _unsuppressed(occurrences),
      hebrew: TextNormaliser.containsHebrew(rulesText),
    );

    // A red base offered only as an option ("Choice of side: pasta or
    // salad") is something to steer around, not a reason to skip the
    // dish: yellow, with the ask to pick the other option, first.
    final optionBase = _firstUnguardedBaseMatch(
      TextNormaliser.dishOptionRulesText(dish),
      name: name,
    );
    if (optionBase != null) {
      final template = TextNormaliser.containsHebrew(optionBase.label)
          ? optionBaseModificationHe
          : optionBaseModificationEn;
      return RuleMatch(
        isNonKeto: false,
        instructions: <String>[
          template.replaceAll('{base}', optionBase.label),
          ...sentences,
        ],
        hiddenCarbs: hiddenCarbs,
      );
    }

    return RuleMatch(
      isNonKeto: false,
      instructions: sentences,
      hiddenCarbs: hiddenCarbs,
    );
  }

  /// Whether [dish]'s description or non-removal option values name a
  /// filling — a protein ([fillingProteinTriggersEn]/`He`), a plant
  /// ([mentionsPlant]) or dairy ([mentionsDairy]) — so a dish named only
  /// by its bread ("לאפה", "Pita") is a filled one and D-V3's yellow
  /// applies, not the carb-only red (issue #191). The name is never
  /// consulted: [carbOnlyBase] already established it names only a carb.
  static bool describesFilling(Dish dish) {
    final parts = <String>[TextNormaliser.normalise(dish.description)];
    for (final option in dish.options) {
      for (final value in option.values) {
        if (TextNormaliser.isRemovalOptionValue(value)) continue;
        parts.add(TextNormaliser.normalise(value));
      }
    }
    var text = parts.where((part) => part.isNotEmpty).join(' ');
    if (text.isEmpty) return false;
    // A topping named again ("tossed in truffle oil and parmesan") is not
    // a filling (issue #273): each one is replaced with a space first.
    for (final topping in _toppings) {
      text = text.replaceAll(topping.pattern, ' ');
    }
    return mentionsPlant(text) ||
        mentionsDairy(text) ||
        _anyUnguardedMatch(text, [
          (_fillingProteinEn, _noGuards),
          (_fillingProteinHe, _noGuards),
        ]);
  }

  /// The carb-modifier trigger a dish [name] consists of, when the name
  /// is nothing but unguarded carb-modifier triggers and the portion or
  /// qualifier words in [carbOnlyQualifiersEn]/[carbOnlyQualifiersHe]
  /// (issue #191): "Plain pita", "Sourdough bun", "Large bag of chips",
  /// "מגש צ'יפס", "לחמניה ללא גלוטן". Null for every other name, including
  /// one with no carb trigger at all and one that names anything else
  /// ("Chicken with pita", "שווארמה בפיתה" — those stay D-V3 yellows).
  ///
  /// The label returned is the earliest (at a tie, longest) trigger's own
  /// dictionary key, through [carbOnlyBaseLabels] for the forms that do
  /// not read well alone. Only the **name** is consulted here; [matchDish]
  /// separately asks [describesFilling] whether the description or options
  /// name a filling, in which case the name is a carrier, not the dish.
  static String? carbOnlyBase(String name) {
    final haystack = TextNormaliser.normalise(name);
    if (haystack.isEmpty) return null;
    final occurrences = _unguardedModifierOccurrences(haystack, name: haystack);
    if (occurrences.isEmpty) return null;
    // Only a starch or a bread can be the whole dish; a sauce, a dressing
    // or a root vegetable in the name means this rule does not apply, and
    // neither does a bread-carried dish (burger, sandwich, wrap, toast).
    for (final occurrence in occurrences) {
      if (!carbOnlyEligibleTriggers.contains(occurrence.key)) return null;
    }

    final units = haystack.codeUnits.toList(growable: false);
    const space = 0x20;
    for (final occurrence in occurrences) {
      for (var i = occurrence.start; i < occurrence.end; i++) {
        units[i] = space;
      }
    }
    final remainder = String.fromCharCodes(units)
        .split(' ')
        .where((word) => word.isNotEmpty);
    for (final word in remainder) {
      if (!_isCarbOnlyQualifier(word)) return null;
    }

    // Label: the earliest trigger, and at a tie the longest — "פירה תפוחי
    // אדמה" is labelled by the whole phrase, not the bare "פירה".
    var best = occurrences.first;
    for (final occurrence in occurrences) {
      if (occurrence.start < best.start ||
          (occurrence.start == best.start && occurrence.end > best.end)) {
        best = occurrence;
      }
    }
    return carbOnlyBaseLabels[best.key] ?? best.key;
  }

  /// Whether a leftover [word] of a dish name is a carb-only qualifier,
  /// as written or with a leading ה/ו particle stripped ("הבית", "ורגילה").
  static bool _isCarbOnlyQualifier(String word) {
    if (_carbOnlyQualifiers.contains(word)) return true;
    if (word.length > 1 && (word.startsWith('ה') || word.startsWith('ו'))) {
      return _carbOnlyQualifiers.contains(word.substring(1));
    }
    return false;
  }

  /// Whether [rawText] names frying or an industrial seed oil
  /// ([seedOilTriggersEn], [seedOilTriggersHe]) — the "Strict seed-oil
  /// free" rule (issue #56). Both languages, unconditionally, like
  /// [match]. Never throws.
  static bool mentionsSeedOil(String rawText) => _anyUnguardedMatch(
    TextNormaliser.normalise(rawText),
    [(_seedOilEn, _noGuards), (_seedOilHe, _noGuards)],
  );

  /// Whether [rawText] names a dairy ingredient ([dairyTriggersEn],
  /// [dairyTriggersHe]) that no plant word beside it rescues
  /// ([dairyGuardsEn], [dairyGuardsHe]: `coconut cream`, `חלב שקדים`) —
  /// the "Dairy-free keto" rule (issue #56). Never throws.
  static bool mentionsDairy(String rawText) => _anyUnguardedMatch(
    TextNormaliser.normalise(rawText),
    [(_dairyEn, dairyGuardsEn), (_dairyHe, dairyGuardsHe)],
  );

  /// Whether [rawText] names a vegetable, salad, fruit, legume or other
  /// plant ([plantTriggersEn], [plantTriggersHe]) — the "Carnivore only"
  /// rule (issue #56). Never throws.
  static bool mentionsPlant(String rawText) => _anyUnguardedMatch(
    TextNormaliser.normalise(rawText),
    [(_plantEn, _noGuards), (_plantHe, _noGuards)],
  );

  /// Every allergen and diet trigger in [dish], one [Concern] per matcher
  /// hit (ALG-04b), whatever anyone's profile (D26 C1): the name's hits,
  /// then the description's, then each non-removal option value's, in the
  /// matcher's order within each. Option group names are not read, and a
  /// removal value ("No sesame", "ללא־שומשום") is skipped exactly as
  /// [TextNormaliser.dishRulesText] skips it.
  ///
  /// Each part is matched on its own, so a [Concern.matchedText] is a
  /// slice of that part as the menu printed it ("Tahini", "בטחינה"). The
  /// source is [ConcernSource.hidden] for a hidden-list trigger, wherever
  /// it sat, and the part's otherwise; the certainty is the hit's; the
  /// tier is [EvidenceTier.stated] for a direct, unguarded trigger and
  /// [EvidenceTier.inferred] for a hidden or a guarded one. The on-device
  /// `ProfileEvaluator` reads this list whole, so a weaker finding in the
  /// name is never hidden behind a stronger one in an option. Pure; never
  /// throws.
  ///
  /// After every hit, at most one more kosher concern: **meat with
  /// dairy** (issue #342; file 11 §24.5), when the dish names a meat or
  /// poultry ([meatWithDairyMeatVocabulary]) and a stated or likely dairy
  /// word (the Milk restriction's own hits) that do not overlap. Fish is
  /// no meat here, so a fish in a cream sauce raises nothing, and a
  /// guarded word on either side ("veggie burger", "goat cheese", "coconut
  /// milk", "no cheese") never counts; see [_meatWithDairy] for its
  /// certainty and source.
  ///
  /// [vocabulary] replaces the registry for one call: the on-device
  /// evaluator reads the user's own words through it (ALG-17,
  /// `custom_terms.dart`), with the same parts, removal skips and slices,
  /// and no meat-with-dairy rule.
  static List<Concern> allergenFindings(
    Dish dish, {
    Map<RestrictionId, RestrictionVocabulary>? vocabulary,
  }) {
    final parts = <(String, ConcernSource)>[
      (dish.name, ConcernSource.name),
      (dish.description, ConcernSource.description),
      for (final option in dish.options)
        for (final value in option.values)
          if (!TextNormaliser.isRemovalOptionValue(
            value.replaceAll(_maqaf, ' '),
          ))
            (value, ConcernSource.option),
    ];
    final findings = <Concern>[];
    final meat = <_SideHit>[];
    final dairy = <_SideHit>[];
    for (final (raw, source) in parts) {
      final hits = vocabulary == null
          ? AllergenMatcher.find(raw)
          : AllergenMatcher.findWith(raw, vocabulary);
      findings.addAll(_findingsIn(raw, source, hits));
      if (vocabulary != null) continue;
      final meatHits = AllergenMatcher.findWith(
        raw,
        meatWithDairyMeatVocabulary,
      );
      for (final hit in meatHits) {
        if (!hit.guarded) meat.add((hit: hit, raw: raw, source: source));
      }
      for (final hit in hits) {
        if (hit.id == RestrictionId.milk &&
            !hit.guarded &&
            hit.certainty != TriggerCertainty.suspected &&
            !meatHits.any((other) => _overlaps(hit, other))) {
          dairy.add((hit: hit, raw: raw, source: source));
        }
      }
    }
    final combined = _meatWithDairy(meat, dairy);
    if (combined != null) findings.add(combined);
    return findings;
  }

  /// Whether [concern] is the kosher meat-with-dairy concern
  /// ([allergenFindings]), whose matched text joins the meat words and the
  /// dairy words with [meatWithDairyJoiner].
  static bool isMeatWithDairy(Concern concern) =>
      concern.restrictionId == RestrictionId.kosher &&
      (concern.matchedText?.contains(meatWithDairyJoiner) ?? false);

  /// The meat words and the dairy words of a meat-with-dairy [concern]
  /// ([isMeatWithDairy]), as the menu printed them; null for any other
  /// concern.
  static ({String meat, String dairy})? meatWithDairyParts(Concern concern) {
    if (!isMeatWithDairy(concern)) return null;
    final text = concern.matchedText!;
    final at = text.indexOf(meatWithDairyJoiner);
    return (
      meat: text.substring(0, at),
      dairy: text.substring(at + meatWithDairyJoiner.length),
    );
  }

  /// [allergenFindings] reduced to one [Concern] per restriction (ALG-04b),
  /// in taxonomy order: the surest finding (stated > likely > suspected)
  /// with its own source, tier and text, the earliest at a tie. What the
  /// heuristic classifier attaches to a dish when
  /// `ClassificationOptions.restrictionsRequested` is true, and what the
  /// golden `allergen_concerns.json` pins against the Python twin
  /// (`backend/app/keto/rules.py`). Pure; never throws.
  static List<Concern> allergenConcerns(Dish dish) {
    final best = <RestrictionId, Concern>{};
    for (final finding in allergenFindings(dish)) {
      final kept = best[finding.restrictionId];
      if (kept == null ||
          _compareCertainty(finding.certainty, kept.certainty) > 0) {
        best[finding.restrictionId] = finding;
      }
    }
    final ids = best.keys.toList()..sort((a, b) => a.index.compareTo(b.index));
    return List<Concern>.unmodifiable(<Concern>[
      for (final id in ids) best[id]!,
    ]);
  }
}
