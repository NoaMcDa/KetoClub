/// The user's own restriction, matched on the device (Banto; the Allergens
/// epic, ALG-17, issue #359; architecture.md D26).
///
/// A profile's [RestrictionId.custom] entry holds free-text words
/// ("kiwi", "pine nuts", "כוסברה"). [customTermVocabulary] turns them into
/// a one-restriction [RestrictionVocabulary] that `AllergenMatcher` and
/// `ClassificationRules.allergenFindings` read exactly as they read the
/// group files: an English word compiles with the ASCII word boundary
/// (`latinTriggerPattern`), a Hebrew one with `hebrewTriggerPattern`, whose
/// permissive prefix lets "בכוסברה" and "והכוסברה" match "כוסברה". An
/// English word also matches its plain plural and, when it ends in "s",
/// its singular ("pine nut" for "pine nuts"); nothing looser, so "pea"
/// never matches "peanut" or "peach".
///
/// "No kiwi", "without kiwi", "kiwi-free", "ללא כוסברה" and "בלי כוסברה"
/// beside a word lower it to suspected rather than clear it (file 11 §0,
/// ALG-04a: a guard lowers, never cancels).
///
/// Device-only (D26 C1): the words are the person's own, and neither they
/// nor this vocabulary ever reach a request, the server, the model or a
/// golden. Unlike the group files, nothing here is sourced: the person
/// is the source.
library;

import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/allergen_matcher.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// The guards every one of the user's own words takes.
const AllergenGuards _ownGuards = AllergenGuards(
  beforeEn: <String>['no', 'without'],
  afterEn: <String>['free'],
  beforeHe: <String>['ללא', 'וללא', 'בלי', 'ובלי'],
);

/// A letter or a digit: a word without one ("!!", "--") would match
/// nothing a menu prints, or everything, and is left out.
final RegExp _wordy = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Every vocabulary built so far, keyed on the list of words it was built
/// from: a menu evaluates every dish for one profile, and the profile's
/// words are one list instance until the profile changes, so one menu
/// compiles them once (`AllergenMatcher` caches its patterns per map
/// instance). Keyed on identity, like the matcher's own cache.
final Expando<Map<RestrictionId, RestrictionVocabulary>> _built =
    Expando<Map<RestrictionId, RestrictionVocabulary>>('custom vocabulary');

/// The English forms [term] matches: itself, its plural, and its singular
/// when it ends in "s" (not "ss").
List<String> _englishForms(String term) {
  final lower = term.toLowerCase();
  return <String>[
    term,
    if (!lower.endsWith('s')) '${term}s',
    if (lower.endsWith('s') && !lower.endsWith('ss') && term.length > 3)
      term.substring(0, term.length - 1),
  ];
}

/// [terms], the user's own words, as a vocabulary of
/// [RestrictionId.custom] alone: each Hebrew word (one holding a Hebrew
/// letter) a direct Hebrew trigger, each other word and its plural and
/// singular a direct English trigger, all with the "no", "without",
/// "-free", "ללא" and "בלי" guards. Empty for no words. A word with no
/// letter or digit once normalised is left out, and forms that normalise
/// alike are listed once. Pure; the same map is
/// returned for the same list instance.
Map<RestrictionId, RestrictionVocabulary> customTermVocabulary(
  List<String> terms,
) {
  if (terms.isEmpty) return const <RestrictionId, RestrictionVocabulary>{};
  return _built[terms] ??= _build(terms);
}

/// [customTermVocabulary], uncached.
Map<RestrictionId, RestrictionVocabulary> _build(List<String> terms) {
  final english = <String>[];
  final hebrew = <String>[];
  final seen = <String>{};
  for (final term in terms) {
    final trimmed = term.trim();
    if (!_wordy.hasMatch(AllergenMatcher.matchText(trimmed))) continue;
    final isHebrew = TextNormaliser.containsHebrew(trimmed);
    final forms = isHebrew ? <String>[trimmed] : _englishForms(trimmed);
    for (final form in forms) {
      final normalised = AllergenMatcher.matchText(form);
      if (normalised.isEmpty || !seen.add(normalised)) continue;
      (isHebrew ? hebrew : english).add(form);
    }
  }
  return english.isEmpty && hebrew.isEmpty
      ? const <RestrictionId, RestrictionVocabulary>{}
      : Map<RestrictionId, RestrictionVocabulary>.unmodifiable(
          <RestrictionId, RestrictionVocabulary>{
            RestrictionId.custom: RestrictionVocabulary(
              directEn: List<String>.unmodifiable(english),
              directHe: List<String>.unmodifiable(hebrew),
              guards: _ownGuards,
            ),
          },
        );
}
