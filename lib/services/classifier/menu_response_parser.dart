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
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
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
  /// The schema version stamped on every [MenuAnalysed] this parser
  /// produces (issue #213). `MenuController._reusableAnalysis` rejects a
  /// cached result whose [MenuAnalysed.schemaVersion] does not equal this,
  /// so upgrading the schema forces a re-analysis rather than reusing a
  /// stale result.
  static const int schemaVersion = 1;

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
      schemaVersion: schemaVersion,
    );
  }

  /// Parses [body] — the raw reply to a vision request that transcribed
  /// and classified photographed or PDF pages in one call — into the
  /// transcribed [Menu] addressed to [ref] and its analysis, stamped
  /// [analysedAt] with [engine] (architecture.md §9.4, scanned variant;
  /// D15, issue #89).
  ///
  /// There is no source menu to check a reply against: the pages are the
  /// source, and the user checks the transcription against them ("View
  /// pages"). So §9.4 rule 3 (provenance) and rule 7 (skipped source
  /// dishes) are replaced by:
  ///
  /// - an element with no non-empty `name` (after trimming) is dropped —
  ///   it names no dish, so there is nothing to transcribe or show; and
  /// - of several elements whose names normalise alike
  ///   ([TextNormaliser.normalise]), the first is kept and the rest are
  ///   dropped, so one dish printed twice, or read twice across two
  ///   overlapping photographs, is one dish.
  ///
  /// Every kept element becomes a [Dish] of the transcription, in reply
  /// order, with the id `v1`, `v2`, … assigned here rather than trusted
  /// from the model, the trimmed name exactly as the model read it, an
  /// empty description, `price: 0` (a scan has no trustworthy price) and
  /// no options. Every other rule applies verbatim to each kept element:
  /// rules 1-2 and the [maxAnalysedDishes] cap fail the whole reply as
  /// [MenuAnalysisFailureReason.badResponse]; rules 4-6 and issue #57's
  /// net-carb post-rule place the dish or demote it to
  /// [MenuAnalysed.unclassified]. A demoted dish stays in the
  /// transcription, so the menu still lists it and the rules engine can
  /// judge it later. Rule 8: a reply with no kept element is
  /// [MenuAnalysisFailureReason.noDishesFound].
  ///
  /// The transcription's single category is [scannedCategoryId], named in
  /// the menu's own language ([scannedCategoryNameHe] when any dish name
  /// is Hebrew, else [scannedCategoryNameEn]) — the same rule the waiter
  /// script follows (architecture.md §12). Its [Menu.fetchedAt] is
  /// [analysedAt] and it has no [Menu.venueName].
  ///
  /// Each transcribed [Dish.page] is the element's `page` (issue #299)
  /// only when it is an integral number from 1 to [pageCount] — `2.0`
  /// reads as 2. Anything else — absent, null, a string, a fraction, out
  /// of range, or any value when [pageCount] is null — leaves the page
  /// null. A bad page is never a rejection: the dish keeps its verdict.
  ///
  /// Static, pure, and never throws, like [parse].
  static ScannedMenuResult parseScanned(
    String body, {
    required VenueRef ref,
    required DateTime analysedAt,
    required AnalysisEngine engine,
    int netCarbLimitGrams = defaultNetCarbLimitGrams,
    int? pageCount,
  }) {
    final decoded = _decode(body);
    if (decoded == null) return _scannedBadResponse();

    final rawDishes = decoded['dishes'];
    if (rawDishes is! List<Object?>) return _scannedBadResponse();
    if (rawDishes.length > maxAnalysedDishes) return _scannedBadResponse();

    final seenNames = <String>{};
    final transcribed = <Dish>[];
    final dishes = <AnalysedDish>[];
    final unclassified = <String>[];

    for (final rawDish in rawDishes) {
      if (rawDish is! Map<String, Object?>) continue;
      final rawName = rawDish['name'];
      final name = rawName is String ? rawName.trim() : '';
      if (name.isEmpty) continue;
      final normalised = TextNormaliser.normalise(name);
      // A name with no letter or digit normalises to nothing; its trimmed
      // text is then its own key, so two such names still dedupe exactly.
      if (!seenNames.add(normalised.isEmpty ? name : normalised)) continue;

      final dish = Dish(
        id: '$scannedDishIdPrefix${transcribed.length + 1}',
        name: name,
        description: '',
        price: 0,
        options: const <DishOption>[],
        page: _page(rawDish['page'], pageCount),
      );
      transcribed.add(dish);
      _judge(
        rawDish,
        dish,
        netCarbLimitGrams: netCarbLimitGrams,
        dishes: dishes,
        unclassified: unclassified,
      );
    }

    if (transcribed.isEmpty) {
      return const ScannedMenuFailed(
        reason: MenuAnalysisFailureReason.noDishesFound,
      );
    }
    final isHebrew = transcribed.any(
      (dish) => TextNormaliser.containsHebrew(dish.name),
    );
    final menu = Menu(
      venueRef: ref,
      currency: scannedMenuCurrency,
      fetchedAt: analysedAt,
      categories: <MenuCategory>[
        MenuCategory(
          id: scannedCategoryId,
          name: isHebrew ? scannedCategoryNameHe : scannedCategoryNameEn,
          dishes: transcribed,
        ),
      ],
    );
    return ScannedMenuRead(
      menu: menu,
      analysis: MenuAnalysed(
        dishes: dishes,
        unclassified: unclassified,
        engine: engine,
        analysedAt: analysedAt,
        schemaVersion: schemaVersion,
      ),
    );
  }

  /// The 1-based page [raw] names, when it is an integral number from 1
  /// to [pageCount]; null otherwise, and always null when [pageCount] is
  /// null (issue #299).
  static int? _page(Object? raw, int? pageCount) {
    if (pageCount == null || raw is! num || !raw.isFinite) return null;
    if (raw != raw.truncate()) return null;
    final page = raw.toInt();
    return page >= 1 && page <= pageCount ? page : null;
  }

  static ScannedMenuFailed _scannedBadResponse() =>
      const ScannedMenuFailed(reason: MenuAnalysisFailureReason.badResponse);

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
    _judge(
      rawDish,
      matched,
      netCarbLimitGrams: netCarbLimitGrams,
      dishes: dishes,
      unclassified: unclassified,
    );
  }

  /// Applies §9.4 rules 4-6, issue #57's post-rule, and issue #213's
  /// hidden-carb rule (rule 5a) to [rawDish], a reply element already
  /// resolved to [matched]: places it onto [dishes] under [matched]'s own
  /// id and name, or demotes [matched]'s name onto [unclassified]. Shared
  /// verbatim by [parse] and [parseScanned] — only how an element finds
  /// its dish differs between the two.
  static void _judge(
    Map<String, Object?> rawDish,
    Dish matched, {
    required int netCarbLimitGrams,
    required List<AnalysedDish> dishes,
    required List<String> unclassified,
  }) {
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

    // Issue #213 rule 5a: a green with a valid hidden-carb flag is a
    // wrong green (architecture.md §3 constraint 5). Parse flags first;
    // a red drops them (red has no modification), a pre-existing yellow
    // is left alone (it already has an instruction).
    final hiddenCarbs = verdict == DishVerdict.nonKeto
        ? const <HiddenCarb>[]
        : _parseHiddenCarbs(rawDish['hidden_carbs']);

    if (finalVerdict == DishVerdict.orderAsIs && hiddenCarbs.isNotEmpty) {
      // Demote green → yellow. The instruction is the model's own
      // modification if usable; otherwise the first flag's waiter
      // question (guaranteed non-empty by _parseHiddenCarbs).
      finalVerdict = DishVerdict.modifiable;
    }

    String? finalModification;
    if (finalVerdict == DishVerdict.modifiable) {
      if (hasUsableModification) {
        finalModification = modification;
      } else if (hiddenCarbs.isNotEmpty) {
        // The only instruction we have is from the hidden-carb flag.
        finalModification = hiddenCarbs.first.waiterQuestion;
      } else {
        // Constraint 7: a yellow without an instruction does not exist.
        // An over-length instruction is demoted, not truncated: cutting
        // a waiter script off mid-sentence could leave a shorter
        // instruction that reads as complete and correct but is not —
        // exactly the wrong-green-shaped failure constraint 5 warns
        // about, just for yellow instead of green.
        unclassified.add(matched.name);
        return;
      }
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
        hiddenCarbs: finalVerdict == DishVerdict.nonKeto
            ? const <HiddenCarb>[]
            : hiddenCarbs,
      ),
    );
  }

  /// Parses the raw `hidden_carbs` array from a reply element (issue
  /// #213, architecture.md §9.4 rule 5a).
  ///
  /// Silently drops any entry that is malformed, missing required fields,
  /// has an unknown certainty, carries a blank source or waiter question,
  /// or whose source or waiter_question exceeds [maxWhyLength] characters
  /// (same budget as `why` — 300 chars). Never throws (constraint 7).
  /// Caps the result at 3 entries per issue #213.
  static List<HiddenCarb> _parseHiddenCarbs(Object? raw) {
    if (raw is! List<Object?>) return const <HiddenCarb>[];
    final result = <HiddenCarb>[];
    for (final entry in raw) {
      if (result.length >= 3) break;
      if (entry is! Map<String, Object?>) continue;
      final rawSource = entry['source'];
      final rawCertainty = entry['certainty'];
      final rawQuestion = entry['waiter_question'];
      if (rawSource is! String || rawSource.trim().isEmpty) continue;
      if (rawSource.length > maxWhyLength) continue;
      if (rawCertainty is! String) continue;
      final certainty = HiddenCarbCertainty.tryParse(rawCertainty);
      if (certainty == null) continue;
      if (rawQuestion is! String || rawQuestion.trim().isEmpty) continue;
      if (rawQuestion.length > maxWhyLength) continue;
      result.add(
        HiddenCarb(
          source: rawSource.trim(),
          certainty: certainty,
          waiterQuestion: rawQuestion.trim(),
        ),
      );
    }
    return result;
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
