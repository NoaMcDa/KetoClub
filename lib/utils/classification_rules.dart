/// The heuristic (rules) classifier's vocabulary matcher
/// (`vocabulary_spec.md`; architecture.md §6.2).
///
/// [ClassificationRules.match] is the entire fallback engine: no HTTP, no
/// LLM, on-device, in milliseconds. It runs the bilingual vocabulary in
/// `constants.dart` over one dish's text and returns what it found.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// A compiled non-keto-base trigger: its dictionary key (for guard and
/// label lookups) and the pattern that finds it in normalised text.
typedef _CompiledBase = ({String key, RegExp pattern});

/// A compiled carb-modifier trigger: its dictionary key (for guard and
/// suppression lookups), its pattern, and its waiter sentence.
typedef _CompiledModifier = ({String key, RegExp pattern, String sentence});

/// One surviving (unguarded) carb-modifier occurrence, in match order.
typedef _Occurrence = ({int start, String key, String sentence});

/// Hebrew letters, including final forms — they are ordinary codepoints
/// inside this range, not appended ones (`vocabulary_spec.md` "regex
/// shape").
const String _heLetters = 'א-ת';

/// Grammatical prefix particles (ב/ה/ו/כ/ל/מ/ש) that may sit directly
/// before a Hebrew trigger with no space, e.g. `הפסטה`, `בפסטה`.
const String _hePrefixes = 'בהוכלמש';

/// The one entry where the permissive prefix lookbehind is unsafe:
/// folded `חלה` also spells "began" (a common verb form), so it is
/// compiled with no permissive prefix — see [_hebrewTriggerPattern]'s
/// `allowPrefix`.
const Set<String> _noPrefixHebrewTriggers = <String>{'חלה'};

/// Builds a Hebrew trigger pattern. Permissive on the left when
/// [allowPrefix] is true (ב/ה/ו/כ/ל/מ/ש are grammatical particles, so
/// `הפסטה` and `בפסטה` must match), strict on the right always (a suffix
/// means a different word, so folded `לחמ` must not match inside
/// `לחמנייה`).
///
/// [allowInflection] appends an optional Hebrew plural/construct suffix.
/// It is safe only on consonant-final stems and is not turned on by any
/// entry in `constants.dart` today, because every inflected form that
/// vocabulary needs is already its own explicit dictionary key; the
/// parameter exists so a future trigger can opt in without changing this
/// function's shape.
///
/// **Dart's `\b` is ASCII-only** — `RegExp(r'\bפסטה\b')` matches nothing
/// at all, with or without `unicode: true`, because a Hebrew letter is a
/// non-word character to the regex engine, so no `\b` boundary ever
/// exists beside one. This function's lookaround, built on the Hebrew
/// letter range directly, is the fix.
RegExp _hebrewTriggerPattern(
  String normalisedTrigger, {
  bool allowInflection = false,
  bool allowPrefix = true,
}) {
  final prefix = allowPrefix ? '[$_hePrefixes]{0,2}' : '';
  final inflection = allowInflection ? '(?:ימ|ות|יות|י|ית)?' : '';
  return RegExp(
    '(?<![$_heLetters])$prefix'
    '${RegExp.escape(normalisedTrigger)}$inflection'
    '(?![$_heLetters])',
  );
}

/// Builds a Latin trigger pattern with a plain, case-insensitive word
/// boundary. Never loosened to a substring match: `toasted almonds` and
/// `Sacramento tomato salad` would turn red if it were.
RegExp _latinTriggerPattern(String normalisedTrigger) =>
    RegExp('\\b${RegExp.escape(normalisedTrigger)}\\b', caseSensitive: false);

/// Compiles [nonKetoBasesEn], normalising each key at compile time so a
/// human-readable, correctly-spelled `constants.dart` still matches
/// normalised dish text.
List<_CompiledBase> _compileBasesEn() => nonKetoBasesEn
    .map(
      (key) => (
        key: key,
        pattern: _latinTriggerPattern(TextNormaliser.normalise(key)),
      ),
    )
    .toList(growable: false);

/// Compiles [nonKetoBasesHe], same rule as [_compileBasesEn].
List<_CompiledBase> _compileBasesHe() => nonKetoBasesHe
    .map(
      (key) => (
        key: key,
        pattern: _hebrewTriggerPattern(
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
        pattern: _latinTriggerPattern(TextNormaliser.normalise(entry.key)),
        sentence: entry.value,
      ),
    )
    .toList(growable: false);

/// Compiles [carbModifiersHe], same rule as [_compileBasesEn].
List<_CompiledModifier> _compileCarbHe() => carbModifiersHe.entries
    .map(
      (entry) => (
        key: entry.key,
        pattern: _hebrewTriggerPattern(TextNormaliser.normalise(entry.key)),
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
        pattern: _latinTriggerPattern(TextNormaliser.normalise(key)),
      ),
    )
    .toList(growable: false);

/// Compiles a dietary-rule trigger list (issue #56) in Hebrew, through
/// [_hebrewTriggerPattern]'s unicode lookaround — never `\b`.
List<_CompiledBase> _compileDietaryHe(List<String> triggers) => triggers
    .map(
      (key) => (
        key: key,
        pattern: _hebrewTriggerPattern(TextNormaliser.normalise(key)),
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

/// The earliest-occurring, unguarded non-keto-base match in [haystack]
/// across both language tables, or null when none survives.
///
/// "Earliest-occurring" (smallest match-start offset) is this file's own
/// tie-break for when more than one base matches one dish — the spec
/// does not name one, since [RuleMatch.baseLabel] holds a single label.
({int start, String label})? _firstUnguardedBaseMatch(String haystack) {
  ({int start, String label})? best;
  void scan(
    List<_CompiledBase> table,
    Map<String, GuardWords> guards,
    Map<String, String> labels,
  ) {
    for (final entry in table) {
      for (final match in entry.pattern.allMatches(haystack)) {
        if (_isGuarded(haystack, match.start, match.end, guards[entry.key])) {
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
/// language tables, in match-start order.
List<_Occurrence> _unguardedModifierOccurrences(String haystack) {
  final occurrences = <_Occurrence>[];
  void scan(List<_CompiledModifier> table, Map<String, GuardWords> guards) {
    for (final entry in table) {
      for (final match in entry.pattern.allMatches(haystack)) {
        if (_isGuarded(haystack, match.start, match.end, guards[entry.key])) {
          continue;
        }
        occurrences.add((
          start: match.start,
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

  @override
  bool operator ==(Object other) =>
      other is RuleMatch &&
      other.isNonKeto == isNonKeto &&
      other.baseLabel == baseLabel &&
      _listEquals(other.instructions, instructions);

  @override
  int get hashCode =>
      Object.hash(isNonKeto, baseLabel, Object.hashAll(instructions));

  @override
  String toString() => isNonKeto
      ? 'RuleMatch(nonKeto: $baseLabel)'
      : 'RuleMatch(modifiers: $instructions)';
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

/// Runs the bilingual heuristic vocabulary over one dish's text
/// (`vocabulary_spec.md`; architecture.md §6.2).
abstract final class ClassificationRules {
  /// Runs both the English and Hebrew vocabularies over [rawText]
  /// unconditionally — Israeli menus mix scripts. Never throws.
  ///
  /// Order: keto-substitute guards (D-V1) cancel matches first; then a
  /// surviving non-keto base makes the dish red with no instructions;
  /// then carb-modifier matches (after suppression, §"triggerSuppresses")
  /// make it yellow with their deduplicated sentences.
  static RuleMatch match(String rawText) {
    final haystack = TextNormaliser.normalise(rawText);

    final base = _firstUnguardedBaseMatch(haystack);
    if (base != null) {
      return RuleMatch(
        isNonKeto: true,
        baseLabel: base.label,
        instructions: const <String>[],
      );
    }

    final occurrences = _unguardedModifierOccurrences(haystack);
    return RuleMatch(
      isNonKeto: false,
      instructions: _sentencesAfterSuppression(occurrences),
    );
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
}
