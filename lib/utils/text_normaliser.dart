/// Text normalisation for the heuristic classifier and menu-cache hashing
/// (`vocabulary_spec.md`; architecture.md §6.2, §6.4, §12).
///
/// [TextNormaliser.normalise] runs the exact seven-step pipeline the
/// vocabulary spec requires, in order. Steps 3 and 4 are the two the
/// README's own `name.lower()` omits, and are correctness fixes, not
/// style:
///
/// - Deleting quote marks before collapsing punctuation is what makes
///   `צ'יפס` and `ציפס`, and `תפו"א` and `תפוא`, the same key.
/// - Folding diacritics is what makes `purée` match the `puree` trigger;
///   without it, README's own worked example (`"butter-infused potato
///   purée"`) classifies GREEN.
library;

import 'package:ketoclub/models/menu.dart';

/// Bidi control characters Wolt and 10bis Hebrew payloads carry around
/// mixed-script runs (vocabulary spec, normaliser step 1): LRM, RLM, LRE,
/// RLE, PDF, LRO, RLO, LRI, RLI, FSI, PDI.
///
/// Built from code points rather than written as literal characters or
/// `\u` escapes in a string literal, so the source file itself never
/// contains a character that changes how the surrounding text renders
/// (`text_direction_code_point_in_literal`).
final String _bidiControlChars = String.fromCharCodes(const <int>[
  0x200E,
  0x200F,
  0x202A,
  0x202B,
  0x202C,
  0x202D,
  0x202E,
  0x2066,
  0x2067,
  0x2068,
  0x2069,
]);
final RegExp _bidiControls = RegExp('[$_bidiControlChars]');

/// Hebrew points and teamim (niqqud, cantillation marks), stripped
/// wholesale because pasted menus carry them inconsistently (step 2).
final RegExp _hebrewPointsAndTeamim = RegExp('[֑-ׇ]');

/// Quote marks deleted (not replaced with a space) so that a geresh or
/// gershayim inside a word does not split it: `צ'יפס` → `ציפס`,
/// `תפו"א` → `תפוא` (step 3). Includes the Hebrew geresh/gershayim
/// (U+05F3, U+05F4), the ASCII quote and backtick, and the common
/// "smart quote" and modifier-apostrophe forms platforms substitute.
final RegExp _quoteMarks = RegExp("[׳״'\"`’”ʼ]");

/// Any run of characters that is neither a letter nor a number,
/// collapsed to one space (step 6). Deliberately the negated-letter
/// class rather than an explicit punctuation list, so a hyphen, the
/// Hebrew maqaf, or a stray control character all collapse the same
/// way — this is what makes `תפוחי-אדמה` match the two-word trigger
/// `תפוחי אדמה`. Requires `unicode: true` for `\p{L}`/`\p{N}` to work.
final RegExp _nonLetterOrNumberRun = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// A Hebrew letter, for [TextNormaliser.containsHebrew].
final RegExp _hebrewLetter = RegExp('[֐-׿]');

/// Precomposed Latin letters with a diacritic, folded to their bare
/// base letter (step 4: NFD, drop combining marks U+0300-U+036F, NFC).
///
/// `dart:core` has no Unicode normalisation API, and `lib/utils/` may
/// import only `package:flutter/foundation.dart` and
/// `package:intl/intl.dart` (neither provides one either), so a literal
/// NFD/strip-combining-marks/NFC round-trip is not available. This table
/// is the practical equivalent for Latin-1 Supplement, which is every
/// accented character a European loanword on a Wolt/10bis menu actually
/// uses (café, purée, jalapeño, crème). A trigger or dish name outside
/// that block would not be folded; none of the vocabulary in
/// `constants.dart` needs one.
const Map<String, String> _diacriticFold = <String, String>{
  'À': 'A',
  'Á': 'A',
  'Â': 'A',
  'Ã': 'A',
  'Ä': 'A',
  'Å': 'A',
  'Æ': 'AE',
  'Ç': 'C',
  'È': 'E',
  'É': 'E',
  'Ê': 'E',
  'Ë': 'E',
  'Ì': 'I',
  'Í': 'I',
  'Î': 'I',
  'Ï': 'I',
  'Ð': 'D',
  'Ñ': 'N',
  'Ò': 'O',
  'Ó': 'O',
  'Ô': 'O',
  'Õ': 'O',
  'Ö': 'O',
  'Ø': 'O',
  'Ù': 'U',
  'Ú': 'U',
  'Û': 'U',
  'Ü': 'U',
  'Ý': 'Y',
  'Þ': 'TH',
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'æ': 'ae',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ð': 'd',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'þ': 'th',
  'ÿ': 'y',
};

/// Hebrew final-form letters folded to their medial spelling (step 7):
/// `ך→כ, ם→מ, ן→נ, ף→פ, ץ→צ`.
const Map<String, String> _hebrewFinalsFold = <String, String>{
  'ך': 'כ',
  'ם': 'מ',
  'ן': 'נ',
  'ף': 'פ',
  'ץ': 'צ',
};

/// Applies [table] one character at a time. Both fold tables are single
/// codepoints in the Basic Multilingual Plane, so iterating UTF-16 code
/// units (not grapheme clusters) is exact and avoids importing
/// `characters`, which `lib/utils/` may not do.
String _translate(String text, Map<String, String> table) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(table[char] ?? char);
  }
  return buffer.toString();
}

/// The bilingual text pipeline the heuristic classifier and the menu
/// cache both build on (`vocabulary_spec.md`).
abstract final class TextNormaliser {
  /// Applies the seven-step pipeline to [raw]: strip bidi controls,
  /// strip Hebrew points/teamim, delete quote marks, fold diacritics,
  /// lowercase, collapse non-letter/non-number runs to one space and
  /// trim, then fold Hebrew final letters.
  ///
  /// Idempotent: `normalise(normalise(x)) == normalise(x)`, because
  /// every step's output already satisfies that step's own input
  /// precondition (no bidi controls, no points, no quote marks, no
  /// diacritics, already lowercase, already single-space-separated,
  /// already final-folded).
  static String normalise(String raw) {
    var text = raw;
    text = text.replaceAll(_bidiControls, '');
    text = text.replaceAll(_hebrewPointsAndTeamim, '');
    text = text.replaceAll(_quoteMarks, '');
    text = _translate(text, _diacriticFold);
    text = text.toLowerCase();
    text = text.replaceAll(_nonLetterOrNumberRun, ' ').trim();
    text = _translate(text, _hebrewFinalsFold);
    return text;
  }

  /// True when [raw] contains a Hebrew letter (U+0590-U+05FF).
  ///
  /// Checked on the untouched string, so it reflects the script the
  /// dish was actually printed in — the heuristic engine uses this to
  /// pick which language's waiter sentences to read, per
  /// architecture.md §12 ("the script of the dish text, not the UI
  /// locale").
  static bool containsHebrew(String raw) => _hebrewLetter.hasMatch(raw);

  /// The normalised words of [raw] that are at least [minLength]
  /// characters long, in order.
  static List<String> words(String raw, {int minLength = 1}) {
    final normalised = normalise(raw);
    if (normalised.isEmpty) return const <String>[];
    return normalised
        .split(' ')
        .where((word) => word.length >= minLength)
        .toList();
  }

  /// The text a classifier sees for one dish: [dish]'s name and
  /// description, plus every option group's name and each of its value
  /// labels (architecture.md §6.1 — "a dish's yellow-ness often lives
  /// in the options, not the description"), normalised and joined with
  /// single spaces.
  static String dishSearchText(Dish dish) {
    final parts = <String>[normalise(dish.name), normalise(dish.description)];
    for (final option in dish.options) {
      parts.add(normalise(option.name));
      for (final value in option.values) {
        parts.add(normalise(value));
      }
    }
    return parts.where((part) => part.isNotEmpty).join(' ');
  }

  /// A stable hash of [menu]'s dish text, for the cache-staleness
  /// comparison architecture.md §6.4 describes ("compare a hash of the
  /// normalised dish text").
  ///
  /// Order-sensitive (dishes are hashed in menu order, not sorted) and
  /// stable across runs and platforms: it is a hand-rolled 32-bit
  /// FNV-1a hash over [dishSearchText]'s UTF-16 code units, not
  /// `String.hashCode` (an unspecified, JVM/V8/AOT-implementation
  /// detail that this file does not want to depend on) and not a
  /// 64-bit hash (web `int`s are IEEE-754 doubles, exact only up to
  /// 2^53; a 32-bit result is exact on every KetoClub target).
  static int menuFingerprint(Menu menu) {
    final buffer = StringBuffer();
    for (final dish in menu.allDishes) {
      buffer
        ..write(dishSearchText(dish))
        ..write(_dishBoundary);
    }
    return _fnv1a32(buffer.toString());
  }
}

/// Separates one dish's [TextNormaliser.dishSearchText] from the next
/// inside [TextNormaliser.menuFingerprint]'s buffer. A NUL character
/// never survives normalisation (step 6 strips every non-letter,
/// non-number character), so it cannot collide with real dish text;
/// built with [String.fromCharCode] rather than written as a literal
/// control character in a string literal.
final String _dishBoundary = String.fromCharCode(0);

/// 32-bit FNV-1a over [text]'s UTF-16 code units. See
/// [TextNormaliser.menuFingerprint] for why this is hand-rolled.
int _fnv1a32(String text) {
  const prime = 16777619;
  const mask = 0xFFFFFFFF;
  var hash = 2166136261;
  for (final unit in text.codeUnits) {
    hash = (hash ^ unit) & mask;
    hash = (hash * prime) & mask;
  }
  return hash;
}
