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
import 'package:ketoclub/models/concern.dart';
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

/// The most ingredients kept for one dish (ALG-03); later entries are
/// dropped. A sanity bound against a runaway reply, not a recipe size.
const int maxIngredientsPerDish = 40;

/// The longest ingredient name kept, in UTF-16 code units (ALG-03). A
/// longer name is dropped, as an over-length hidden-carb flag is: it is
/// not an ingredient name.
const int maxIngredientNameLength = 100;

/// The longest transcribed description a scan keeps, in UTF-16 code
/// units (ALG-03). Longer text is truncated, never rejected, as `why` is.
const int maxTranscribedDescriptionLength = 1000;

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
  /// 3. Each element must be traceable to a dish in [source] or it is an
  ///    invention and never receives a verdict (constraint 6). A matching
  ///    `id` always wins; only an element whose `id` is missing or names
  ///    no source dish falls back to its `name`, which must normalise
  ///    exactly to a source dish's name or share at least
  ///    [nameOverlapNumerator]/[nameOverlapDenominator] of its content
  ///    words ([minOverlapWordLength]+ letters, not in [nameStopWords])
  ///    with exactly one best source dish (see [_findSourceDish]). Each
  ///    source dish is judged at most once: a later element resolving to
  ///    a dish an earlier one already resolved to is dropped, so a dish
  ///    is never in [MenuAnalysed.dishes] twice or in both lists.
  /// 4. Its `verdict` must be one of [DishVerdict]'s names and its `why`
  ///    non-empty, or the dish is demoted to
  ///    [MenuAnalysed.unclassified].
  /// 5. A [DishVerdict.modifiable] verdict with a null, blank, or
  ///    over-[maxModificationLength] `modification` is demoted the same
  ///    way (constraint 7), even when it carries `hidden_carbs` (issue
  ///    #277); any other verdict keeps its verdict and drops the field
  ///    regardless of what the model sent.
  ///
  ///    5a. A [DishVerdict.orderAsIs] verdict carrying a well-formed
  ///    hidden-carb flag is a wrong green (issue #213) and becomes a
  ///    [DishVerdict.modifiable]: its instruction is the model's usable
  ///    `modification`, else the first flag's waiter question, which is
  ///    a complete instruction here because the flag is the dish's only
  ///    reason to be yellow.
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
  ///
  /// With [extract] (ALG-03; the caller passes
  /// `ClassificationOptions.restrictionsRequested`) each placed dish also
  /// carries the ingredients [_parseIngredients] keeps from its
  /// `ingredients`. Without it `ingredients` is never read, so a keto
  /// analysis is today's whatever the model sent. A model-sent `concerns`
  /// is never read either way: concerns are computed on the device (D26
  /// C1). See [extractionMissing] for a dish whose extraction is missing.
  static MenuAnalysis parse(
    String body, {
    required Menu source,
    required DateTime analysedAt,
    required AnalysisEngine engine,
    int netCarbLimitGrams = defaultNetCarbLimitGrams,
    bool extract = false,
  }) {
    final decoded = _decode(body);
    if (decoded == null) return _badResponse();

    final rawDishes = decoded['dishes'];
    if (rawDishes is! List<Object?>) return _badResponse();
    if (rawDishes.length > maxAnalysedDishes) return _badResponse();

    final resolvedSourceIds = <String>{};
    final dishes = <AnalysedDish>[];
    final unclassified = <String>[];

    for (final rawDish in rawDishes) {
      _processElement(
        rawDish,
        source: source,
        netCarbLimitGrams: netCarbLimitGrams,
        extract: extract,
        resolvedSourceIds: resolvedSourceIds,
        dishes: dishes,
        unclassified: unclassified,
      );
    }

    // Rule 7: a source dish no reply element matched at all — by id or
    // by name — was skipped by the model, not merely demoted.
    for (final dish in source.allDishes) {
      if (!resolvedSourceIds.contains(dish.id)) unclassified.add(dish.name);
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
  /// transcribed [Menu] and its analysis, stamped [analysedAt] with
  /// [engine] (architecture.md §9.4, scanned variant; D15, issue #89).
  ///
  /// The menu's reference is content-addressed (D23, issue #308):
  /// `VenueRef(scan, <8 hex digits of`
  /// [TextNormaliser.menuFingerprint]` of the transcription>)`, exactly
  /// the scheme a pasted menu follows, so a photograph and a paste of
  /// the same dishes are one entry, and reading the same pages twice is
  /// one entry too. The fingerprint reads dish text only, so a dish's
  /// [Dish.page] and the read time never change it.
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
  /// With [extract] (ALG-03) each transcribed [Dish.description] is the
  /// element's `description` when it is a string — trimmed, and cut at
  /// [maxTranscribedDescriptionLength] like `why` — and empty otherwise,
  /// and each placed dish carries its ingredients as [parse] reads them,
  /// against that transcription. The description is dish text, so it
  /// enters the menu's fingerprint: an extracting scan of the same pages
  /// is a different entry from a keto one. Without [extract] neither key
  /// is read and the transcription is today's.
  ///
  /// Static, pure, and never throws, like [parse].
  static ScannedMenuResult parseScanned(
    String body, {
    required DateTime analysedAt,
    required AnalysisEngine engine,
    int netCarbLimitGrams = defaultNetCarbLimitGrams,
    int? pageCount,
    bool extract = false,
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

      final rawDescription = rawDish['description'];
      final dish = Dish(
        id: '$scannedDishIdPrefix${transcribed.length + 1}',
        name: name,
        description: extract && rawDescription is String
            ? _truncated(rawDescription.trim(), maxTranscribedDescriptionLength)
            : '',
        price: 0,
        options: const <DishOption>[],
        page: _page(rawDish['page'], pageCount),
      );
      transcribed.add(dish);
      _judge(
        rawDish,
        dish,
        netCarbLimitGrams: netCarbLimitGrams,
        extract: extract,
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
    final categories = <MenuCategory>[
      MenuCategory(
        id: scannedCategoryId,
        name: isHebrew ? scannedCategoryNameHe : scannedCategoryNameEn,
        dishes: transcribed,
      ),
    ];
    // The paste scheme (TextMenuSource): fingerprint a provisional menu,
    // then address the final one by it.
    final provisional = Menu(
      venueRef: const VenueRef(source: MenuSource.scan, platformId: 'pending'),
      currency: scannedMenuCurrency,
      fetchedAt: analysedAt,
      categories: categories,
    );
    final fingerprint = TextNormaliser.menuFingerprint(provisional);
    final menu = Menu(
      venueRef: VenueRef(
        source: MenuSource.scan,
        platformId: fingerprint.toRadixString(16).padLeft(8, '0'),
      ),
      currency: scannedMenuCurrency,
      fetchedAt: analysedAt,
      categories: categories,
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

  /// Whether [analysed], the verdict on [dish] from an analysis made with
  /// extraction requested ([extract]), is missing its extraction (ALG-03):
  /// [dish] has a description, so it has text an ingredient list is read
  /// from, yet no ingredient was kept — the model sent none, or none
  /// survived [_parseIngredients]. Always false without [extract].
  ///
  /// **The mark is computed, never stored**, like a dish's kind (D21).
  /// Demoting the dish to [MenuAnalysed.unclassified], the way §9.4 marks
  /// any other per-dish failure, would throw away a valid keto verdict
  /// over a missing half that keto never asked for. So the verdict stands,
  /// `ingredients` stays empty, and the rules pass (ALG-04), which reads
  /// every dish's own text whatever the model sent, is that dish's only
  /// source of concerns — the epic's "rules-only concerns" for a dish
  /// whose extraction is missing.
  static bool extractionMissing(
    Dish dish,
    AnalysedDish analysed, {
    required bool extract,
  }) =>
      extract &&
      analysed.ingredients.isEmpty &&
      dish.description.trim().isNotEmpty;

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
  /// [dishes], demotes it onto [unclassified], or drops it silently. Any
  /// source dish it resolves to (by id or by name) is recorded in
  /// [resolvedSourceIds], whether the element is ultimately placed or
  /// demoted, so rule 7 does not also report that source dish as
  /// skipped.
  ///
  /// An element resolving to a source dish already in
  /// [resolvedSourceIds] is a duplicate and is dropped without being
  /// counted anywhere (issue #277): the first element naming a dish is
  /// the one judged, so a dish never carries two conflicting verdicts and
  /// is never both placed and unclassified.
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
    required bool extract,
    required Set<String> resolvedSourceIds,
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
    // A second element for a dish already judged: drop it (issue #277).
    if (!resolvedSourceIds.add(matched.id)) return;
    _judge(
      rawDish,
      matched,
      netCarbLimitGrams: netCarbLimitGrams,
      extract: extract,
      dishes: dishes,
      unclassified: unclassified,
    );
  }

  /// Applies §9.4 rules 4-6, issue #57's post-rule, and issue #213's
  /// hidden-carb rule (§9.4 rule 5a) to [rawDish], a reply element already
  /// resolved to [matched]: places it onto [dishes] under [matched]'s own
  /// id and name, or demotes [matched]'s name onto [unclassified]. Shared
  /// verbatim by [parse] and [parseScanned] — only how an element finds
  /// its dish differs between the two. With [extract] the placed dish
  /// also carries [_parseIngredients] of its `ingredients`, whatever its
  /// verdict: the extraction is independent of keto (ALG-03).
  static void _judge(
    Map<String, Object?> rawDish,
    Dish matched, {
    required int netCarbLimitGrams,
    required bool extract,
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

    // §9.4 rule 5a (issue #213): a green with a valid hidden-carb flag
    // is a wrong green (architecture.md §3 constraint 5). Parse flags
    // first; a red drops them (red has no modification).
    final hiddenCarbs = verdict == DishVerdict.nonKeto
        ? const <HiddenCarb>[]
        : _parseHiddenCarbs(rawDish['hidden_carbs']);

    // Rule 5a applies only to a dish that is still green: the flag is
    // then its only reason to be yellow, so the flag's own waiter
    // question is a complete instruction for it. A yellow the model sent
    // (or #57 produced) is yellow for a reason the flag need not cover —
    // a side of fries, a carb count — so rule 5 holds for it as written
    // and a missing instruction demotes it (issue #277).
    final hiddenCarbYellow =
        finalVerdict == DishVerdict.orderAsIs && hiddenCarbs.isNotEmpty;
    if (hiddenCarbYellow) finalVerdict = DishVerdict.modifiable;

    String? finalModification;
    if (finalVerdict == DishVerdict.modifiable) {
      if (hasUsableModification) {
        finalModification = modification;
      } else if (hiddenCarbYellow) {
        // The flag is the only reason this dish is yellow, and its
        // question (non-empty, guaranteed by _parseHiddenCarbs) is what
        // the waiter needs to be asked.
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
        ingredients: extract
            ? _parseIngredients(rawDish['ingredients'], matched)
            : const <ExtractedIngredient>[],
      ),
    );
  }

  /// Parses a reply element's raw `ingredients` array against [dish], the
  /// dish it was placed on (ALG-03, in the §9.4 spirit). Never throws.
  ///
  /// - An entry that is not an object, whose `name` is not a string, is
  ///   blank after trimming or is over [maxIngredientNameLength] once
  ///   trimmed, or whose `certainty` is not one of [Certainty]'s names, is
  ///   dropped.
  /// - A `role` that is missing or not one of [ComponentRole]'s names
  ///   reads as [ComponentRole.unknown], as [ExtractedIngredient.tryFromJson]
  ///   reads it: an ingredient is never lost over its role, since losing
  ///   one could hide an allergen.
  /// - **An ingredient the dish text does not support is kept but capped
  ///   at [Certainty.suspected].** Supported means the normalised name is
  ///   a substring of the dish's [TextNormaliser.dishRulesText] — its name,
  ///   description and every option except a removal ("No sesame"). A
  ///   substring rather than a whole word, so a Hebrew particle
  ///   ("הטחינה") still supports "טחינה"; a name that normalises to
  ///   nothing is never supported.
  /// - Of entries whose names normalise alike, the first is kept (the
  ///   trimmed name is its own key when it normalises to nothing).
  /// - At most [maxIngredientsPerDish] are kept.
  static List<ExtractedIngredient> _parseIngredients(Object? raw, Dish dish) {
    if (raw is! List<Object?>) return const <ExtractedIngredient>[];
    final dishText = TextNormaliser.dishRulesText(dish);
    final seen = <String>{};
    final result = <ExtractedIngredient>[];
    for (final entry in raw) {
      if (result.length >= maxIngredientsPerDish) break;
      if (entry is! Map<String, Object?>) continue;
      final rawName = entry['name'];
      if (rawName is! String) continue;
      final name = rawName.trim();
      if (name.isEmpty || name.length > maxIngredientNameLength) continue;
      final rawCertainty = entry['certainty'];
      if (rawCertainty is! String) continue;
      final certainty = Certainty.tryParse(rawCertainty);
      if (certainty == null) continue;
      final rawRole = entry['role'];
      final role =
          (rawRole is String ? ComponentRole.tryParse(rawRole) : null) ??
          ComponentRole.unknown;
      final normalised = TextNormaliser.normalise(name);
      if (!seen.add(normalised.isEmpty ? name : normalised)) continue;
      final supported = normalised.isNotEmpty && dishText.contains(normalised);
      result.add(
        ExtractedIngredient(
          name: name,
          certainty: supported ? certainty : Certainty.suspected,
          role: role,
        ),
      );
    }
    return result;
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
  /// [name] refers to (architecture.md §9.4 rule 3, issue #277). Returns
  /// null when nothing matches: an invention.
  ///
  /// 1. A non-empty [id] equal to a source [Dish.id] always wins, whatever
  ///    [name] says: the model was given the ids, and a name can be
  ///    paraphrased into another dish's.
  /// 2. Only when [id] is missing or names no source dish is [name] read.
  ///    A source dish whose name normalises ([TextNormaliser.normalise])
  ///    exactly to [name]'s is the match — the first such in menu order.
  /// 3. Otherwise the dish whose content words overlap [name]'s most,
  ///    when that overlap is high: the content words of a name are its
  ///    normalised words of [minOverlapWordLength]+ letters that are not
  ///    in [nameStopWords], and the overlap is the shared words over all
  ///    words of the two sets (Jaccard), which must be at least
  ///    [nameOverlapNumerator]/[nameOverlapDenominator]. Two dishes tied
  ///    for the best overlap are ambiguous, and an ambiguous name matches
  ///    neither. Counted in whole numbers, so the Python twin cannot
  ///    round differently.
  ///
  /// Every source dish is a candidate, including one an earlier element
  /// already resolved to: the caller then drops the element as a
  /// duplicate, rather than this method re-routing it to a lookalike that
  /// is still free.
  static Dish? _findSourceDish(
    Menu source, {
    required String id,
    required String name,
  }) {
    final all = source.allDishes;
    if (id.isNotEmpty) {
      for (final dish in all) {
        if (dish.id == id) return dish;
      }
    }
    final normalisedName = TextNormaliser.normalise(name);
    if (normalisedName.isEmpty) return null;
    for (final dish in all) {
      if (TextNormaliser.normalise(dish.name) == normalisedName) return dish;
    }
    final nameWords = _contentWords(name);
    if (nameWords.isEmpty) return null;
    Dish? best;
    var bestShared = 0;
    var bestUnion = 1;
    var tied = false;
    for (final dish in all) {
      final dishWords = _contentWords(dish.name);
      final shared = dishWords.where(nameWords.contains).length;
      if (shared == 0) continue;
      final union = nameWords.length + dishWords.length - shared;
      if (shared * nameOverlapDenominator < union * nameOverlapNumerator) {
        continue;
      }
      final compare = shared * bestUnion - bestShared * union;
      if (best == null || compare > 0) {
        best = dish;
        bestShared = shared;
        bestUnion = union;
        tied = false;
      } else if (compare == 0) {
        tied = true;
      }
    }
    return tied ? null : best;
  }

  /// The content words of [name]: its distinct normalised words of
  /// [minOverlapWordLength]+ letters that are not in [nameStopWords].
  static Set<String> _contentWords(String name) => TextNormaliser.words(
    name,
    minLength: minOverlapWordLength,
  ).where((word) => !nameStopWords.contains(word)).toSet();

  /// [text], cut to at most [maxLength] characters (architecture.md §9.4
  /// rule 6 — truncated, never rejected for length alone). The cut never
  /// lands between the two halves of a surrogate pair: a lone surrogate
  /// is not valid UTF-8, so the analysis could not be sent to or stored by
  /// the backend (D25, found by the golden corpus, #320).
  static String _truncated(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    final end = _isHighSurrogate(text.codeUnitAt(maxLength - 1))
        ? maxLength - 1
        : maxLength;
    return text.substring(0, end);
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
}
