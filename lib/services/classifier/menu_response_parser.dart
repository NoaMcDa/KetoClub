/// Parses an LLM reply into a [MenuAnalysis] (architecture.md §9.4).
///
/// The reply is untrusted input from a third party, shaped by menu text a
/// restaurant typed (architecture.md §9, §11): every rule below exists
/// to make a wrong green rare and visible (constraint 5), never to trust
/// a field the model sent. No field is ever interpreted as an
/// instruction — a dish named "ignore previous instructions" is a dish
/// with an odd name and passes or fails these rules like any other.
library;

import 'dart:convert';

import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// Matches a whole reply wrapped in a markdown code fence, with or
/// without a `json` language tag (architecture.md §9.4 rule 1).
final RegExp _fencedJson = RegExp(
  r'^```(?:json)?\s*\n?([\s\S]*?)\n?```$',
  caseSensitive: false,
);

/// Parses the model's reply against the menu it was computed from
/// (architecture.md §9.4).
///
/// Static, pure, and never throws: every rule below either places a
/// dish, demotes it to [MenuAnalysed.unclassified], or fails the whole
/// reply as [MenuAnalysisFailed] — there is no fourth outcome and no
/// exception crosses this class's boundary.
abstract final class MenuResponseParser {
  /// Parses [body] — the raw LLM reply — against [source], the [Menu] it
  /// was computed from, stamping the result [analysedAt] with [engine].
  ///
  /// In order (architecture.md §9.4):
  ///
  /// 1. Strips a markdown fence if present, then `jsonDecode`s [body]; a
  ///    throw, or a root that is not a JSON object, is
  ///    [MenuAnalysisFailureReason.badResponse].
  /// 2. `dishes` missing or not a list is also
  ///    [MenuAnalysisFailureReason.badResponse]; naming more than
  ///    [maxAnalysedDishes] dishes is too.
  /// 3. Each element must be traceable to a dish in [source] — by `id`,
  ///    or by a shared normalised word of [minOverlapWordLength]+
  ///    letters with a source dish's name — or it is an invention and
  ///    never receives a verdict (constraint 6).
  /// 4. Its `verdict` must be one of [DishVerdict]'s names and its `why`
  ///    non-empty, or the dish is demoted to
  ///    [MenuAnalysed.unclassified].
  /// 5. A [DishVerdict.modifiable] verdict with a null, blank, or
  ///    over-[maxModificationLength] `modification` is demoted the same
  ///    way (constraint 7); any other verdict keeps its verdict and
  ///    drops the field regardless of what the model sent.
  /// 6. `why` is truncated at [maxWhyLength], never rejected for length
  ///    alone.
  ///
  /// Then one post-rule (issue #57): a [DishVerdict.orderAsIs] verdict
  /// whose own `net_carbs_estimate` exceeds [netCarbLimitGrams] contradicts
  /// the green definition the prompt stated, so it is not kept green. It
  /// is demoted to [DishVerdict.modifiable] when the model also sent a
  /// usable `modification` (non-blank, within [maxModificationLength]) —
  /// the instruction a yellow needs — and to [MenuAnalysed.unclassified]
  /// otherwise, since a yellow without an instruction does not exist
  /// (constraint 7). An estimate at or under the limit, or no estimate at
  /// all, leaves the verdict alone: the limit is "N g or less", and the
  /// parser never invents a figure the model did not send.
  ///
  /// Finally:
  ///
  /// 7. Every dish in [source] the reply never mentioned is added to
  ///    [MenuAnalysed.unclassified] by name, so the user can see the
  ///    model skipped it.
  /// 8. An empty result with nothing unclassified either is
  ///    [MenuAnalysisFailureReason.noDishesFound]; an empty result with
  ///    something unclassified is a placed (empty) [MenuAnalysed] —
  ///    "the model saw the dishes and could place none" is a result to
  ///    show, not a failure to retry.
  static MenuAnalysis parse(
    String body, {
    required Menu source,
    required DateTime analysedAt,
    required AnalysisEngine engine,
    int netCarbLimitGrams = defaultNetCarbLimitGrams,
  }) {
    final decoded = _decode(body);
    if (decoded == null) return _badResponse();

    final rawDishes = decoded['dishes'];
    if (rawDishes is! List<Object?>) return _badResponse();
    if (rawDishes.length > maxAnalysedDishes) return _badResponse();

    final placedSourceIds = <String>{};
    final dishes = <AnalysedDish>[];
    final unclassified = <String>[];

    for (final rawDish in rawDishes) {
      _processElement(
        rawDish,
        source: source,
        netCarbLimitGrams: netCarbLimitGrams,
        placedSourceIds: placedSourceIds,
        dishes: dishes,
        unclassified: unclassified,
      );
    }

    // Rule 7: a source dish no reply element matched at all — by id or
    // by name overlap — was skipped by the model, not merely demoted.
    for (final dish in source.allDishes) {
      if (!placedSourceIds.contains(dish.id)) unclassified.add(dish.name);
    }

    if (dishes.isEmpty && unclassified.isEmpty) {
      return const MenuAnalysisFailed(
        reason: MenuAnalysisFailureReason.noDishesFound,
      );
    }
    return MenuAnalysed(
      dishes: dishes,
      unclassified: unclassified,
      engine: engine,
      analysedAt: analysedAt,
    );
  }

  /// Strips a markdown fence if present and `jsonDecode`s [body].
  ///
  /// Returns null when [jsonDecode] throws or the decoded root is not a
  /// JSON object (architecture.md §9.4 rules 1-2).
  static Map<String, Object?>? _decode(String body) {
    final trimmed = body.trim();
    final fenceMatch = _fencedJson.firstMatch(trimmed);
    final unfenced = fenceMatch?.group(1)?.trim() ?? trimmed;
    final Object? decoded;
    try {
      decoded = jsonDecode(unfenced);
    } on FormatException {
      return null;
    }
    return decoded is Map<String, Object?> ? decoded : null;
  }

  static MenuAnalysisFailed _badResponse() =>
      const MenuAnalysisFailed(reason: MenuAnalysisFailureReason.badResponse);

  /// Processes one element of the reply's `dishes` array: places it onto
  /// [dishes], demotes it onto [unclassified], or — for an element with
  /// no source name to show at all — drops it silently. Any source dish
  /// it resolves to (by id or by name overlap) is recorded in
  /// [placedSourceIds], whether the element is ultimately placed or
  /// demoted, so rule 7 does not also report that source dish as
  /// skipped.
  ///
  /// A non-map element, or one with neither a string `id` nor a string
  /// `name`, carries nothing this parser can trust or display and is
  /// dropped without being counted anywhere — it is not an invention (it
  /// names no dish) and not a source dish (it has no provenance to
  /// check).
  static void _processElement(
    Object? rawDish, {
    required Menu source,
    required int netCarbLimitGrams,
    required Set<String> placedSourceIds,
    required List<AnalysedDish> dishes,
    required List<String> unclassified,
  }) {
    if (rawDish is! Map<String, Object?>) return;

    final rawId = rawDish['id'];
    final rawName = rawDish['name'];
    final modelId = rawId is String ? rawId : '';
    final modelName = rawName is String ? rawName : '';
    if (modelId.isEmpty && modelName.isEmpty) return;

    final matched = _findSourceDish(source, id: modelId, name: modelName);
    if (matched == null) {
      // Constraint 6: never invent a dish. There is no source dish to
      // trust a name from, so the model's own, unverifiable name is
      // what the user sees flagged — never a verdict.
      if (modelName.isNotEmpty) unclassified.add(modelName);
      return;
    }
    placedSourceIds.add(matched.id);

    final rawVerdict = rawDish['verdict'];
    // Matched by string, never by ordinal (DishVerdict.tryParse), so a
    // reordering of the enum can never silently re-map a live reply.
    final verdict = rawVerdict is String
        ? DishVerdict.tryParse(rawVerdict)
        : null;
    if (verdict == null) {
      unclassified.add(matched.name);
      return;
    }

    final rawWhy = rawDish['why'];
    final why = rawWhy is String ? rawWhy.trim() : '';
    if (why.isEmpty) {
      unclassified.add(matched.name);
      return;
    }

    final rawModification = rawDish['modification'];
    final modification = rawModification is String
        ? rawModification.trim()
        : null;

    final hasUsableModification =
        modification != null &&
        modification.isNotEmpty &&
        modification.length <= maxModificationLength;

    final rawNetCarbs = rawDish['net_carbs_estimate'];
    final netCarbsEstimate = rawNetCarbs is num ? rawNetCarbs.toDouble() : null;

    var finalVerdict = verdict;
    if (verdict == DishVerdict.orderAsIs &&
        netCarbsEstimate != null &&
        netCarbsEstimate > netCarbLimitGrams) {
      // Issue #57's post-rule: the model's own figure is over the limit
      // the prompt gave it, so this cannot stay green. With an
      // instruction it becomes the yellow that instruction describes;
      // without one it falls through to the demotion below, because a
      // yellow without an instruction does not exist (constraint 7).
      finalVerdict = DishVerdict.modifiable;
    }

    String? finalModification;
    if (finalVerdict == DishVerdict.modifiable) {
      if (!hasUsableModification) {
        // Constraint 7: a yellow without an instruction does not exist.
        // An over-length instruction is demoted, not truncated: cutting
        // a waiter script off mid-sentence could leave a shorter
        // instruction that reads as complete and correct but is not —
        // exactly the wrong-green-shaped failure constraint 5 warns
        // about, just for yellow instead of green.
        unclassified.add(matched.name);
        return;
      }
      finalModification = modification;
    }
    // Any other verdict keeps it and drops the field: a green or red
    // carrying a `modification` is not demoted for it.

    dishes.add(
      AnalysedDish(
        dishId: matched.id,
        name: matched.name,
        verdict: finalVerdict,
        why: _truncated(why, maxWhyLength),
        modification: finalModification,
        netCarbsEstimate: netCarbsEstimate,
      ),
    );
  }

  /// Finds the dish in [source] a reply element with this [id] and
  /// [name] refers to (architecture.md §9.4 rule 3): first by an exact
  /// [Dish.id] match, then by a shared normalised word of
  /// [minOverlapWordLength]+ letters between [name] and a source dish's
  /// [Dish.name]. Both sides go through [TextNormaliser] — never a
  /// bespoke comparison. Returns null when neither matches: an
  /// invention.
  static Dish? _findSourceDish(
    Menu source, {
    required String id,
    required String name,
  }) {
    if (id.isNotEmpty) {
      for (final dish in source.allDishes) {
        if (dish.id == id) return dish;
      }
    }
    if (name.isEmpty) return null;
    final nameWords = TextNormaliser.words(
      name,
      minLength: minOverlapWordLength,
    ).toSet();
    if (nameWords.isEmpty) return null;
    for (final dish in source.allDishes) {
      final dishWords = TextNormaliser.words(
        dish.name,
        minLength: minOverlapWordLength,
      );
      if (dishWords.any(nameWords.contains)) return dish;
    }
    return null;
  }

  /// [text], cut to at most [maxLength] characters (architecture.md §9.4
  /// rule 6 — truncated, never rejected for length alone).
  static String _truncated(String text, int maxLength) =>
      text.length > maxLength ? text.substring(0, maxLength) : text;
}
