/// The two trigger patterns every vocabulary matcher in this package
/// compiles its terms with: the keto engine (`classification_rules.dart`,
/// which re-exports this file), dish kinds (`dish_kind.dart`) and the
/// allergen matcher (`allergens/allergen_matcher.dart`).
///
/// Their own file so the allergen matcher can import them without
/// importing `classification_rules.dart`, which itself reads the matcher
/// for `ClassificationRules.allergenConcerns` (ALG-04b): one import graph,
/// no cycle.
library;

/// Hebrew letters, including final forms — they are ordinary codepoints
/// inside this range, not appended ones (`vocabulary_spec.md` "regex
/// shape").
const String _heLetters = 'א-ת';

/// Grammatical prefix particles (ב/ה/ו/כ/ל/מ/ש) that may sit directly
/// before a Hebrew trigger with no space, e.g. `הפסטה`, `בפסטה`.
const String _hePrefixes = 'בהוכלמש';

/// Builds a Hebrew trigger pattern for one already-normalised trigger.
///
/// Public so `utils/dish_kind.dart` (D21) matches category headings and
/// dish names with the same boundary rule as the classifier; there is one
/// Hebrew word-boundary in this codebase. Permissive on the left when
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
RegExp hebrewTriggerPattern(
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
/// boundary, for one already-normalised trigger. Never loosened to a
/// substring match: `toasted almonds` and `Sacramento tomato salad` would
/// turn red if it were. Public for the same reason as
/// [hebrewTriggerPattern].
RegExp latinTriggerPattern(String normalisedTrigger) =>
    RegExp('\\b${RegExp.escape(normalisedTrigger)}\\b', caseSensitive: false);
