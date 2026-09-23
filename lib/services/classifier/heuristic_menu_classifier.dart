/// The offline fallback engine (architecture.md §6.2).
///
/// A Dart port of the README's `analyze_dish`: it runs
/// [ClassificationRules.match] over each dish's search text
/// ([TextNormaliser.dishSearchText]) and turns what it found into a
/// verdict, a `why`, and — for a modifiable dish — a waiter script. It
/// does no I/O, needs no key, and runs entirely on-device.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/utils/classification_rules.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// The offline, rule-based [MenuClassifier] (architecture.md §6.2).
///
/// Of [ClassificationOptions], only the three dietary toggles (issue #56)
/// steer a verdict here: [ClassificationOptions.seedOilFree],
/// [ClassificationOptions.dairyFree] and
/// [ClassificationOptions.carnivoreOnly] each switch on one extra rule
/// (see [_dietarySentences]). Consent is not a rules concern. Nor is
/// [ClassificationOptions.netCarbLimitGrams] (issue #57): the vocabulary is
/// keyword-based and never estimates grams, so there is no numeric green
/// threshold here for the limit to move; it reaches the LLM's prompt and
/// `MenuResponseParser` instead. The options are still recorded in
/// [MenuAnalysed.options], as the interface requires. Never throws, places
/// every dish it is given, and so never
/// reports [MenuAnalysed.unclassified].
///
/// This class does not know *why* it is running instead of the LLM
/// engine — that reason belongs to `RoutingMenuClassifier`, which calls
/// it, not to this class's constructor. A direct call therefore stamps
/// the honest default, [MenuAnalysisFailureReason.notConfigured] ("no
/// LLM was ever configured for this call"); the router re-stamps the
/// real reason afterwards with [MenuAnalysed.copyWithEngine], which the
/// model already provides for exactly this purpose.
@immutable
final class HeuristicMenuClassifier implements MenuClassifier {
  /// Creates a classifier that stamps results with [clock]'s time.
  const new({required this.clock});

  /// Supplies "now" for [MenuAnalysed.analysedAt] (architecture.md
  /// §18.4 — no real clock in tests).
  final Clock clock;

  @override
  Future<MenuAnalysis> classify(
    Menu menu, {
    ClassificationOptions options = const ClassificationOptions(),
  }) async {
    final dishes = <AnalysedDish>[
      for (final dish in menu.allDishes) _analyse(dish, options),
    ];
    return MenuAnalysed(
      dishes: dishes,
      unclassified: const <String>[],
      engine: const RulesEngine(
        reason: MenuAnalysisFailureReason.notConfigured,
      ),
      analysedAt: clock.now(),
      options: options.snapshot,
    );
  }

  /// Classifies one dish against the bilingual rule vocabulary, plus the
  /// dietary rules [options] switch on (issue #56).
  ///
  /// A red dish stays red with no script: no substitution rescues a
  /// non-keto base, whatever else it contains. Otherwise the carb
  /// sentences come first and each triggered dietary rule's sentence
  /// follows, so a green dish a rule catches becomes yellow and a yellow
  /// one gains the extra ask. A dish yellow only because of a dietary rule
  /// gets [dietaryRuleWhyEn]/[dietaryRuleWhyHe], since the carb-component
  /// `why` would not be true of it.
  AnalysedDish _analyse(Dish dish, ClassificationOptions options) {
    final text = TextNormaliser.dishSearchText(dish);
    // The script a waiter script is read in follows the dish's own
    // text, not the UI locale (architecture.md §12): a Hebrew menu
    // read by an English-UI user still gets a Hebrew script.
    final isHebrew = TextNormaliser.containsHebrew(text);
    final match = ClassificationRules.match(text);

    if (match.isNonKeto) {
      final template = isHebrew ? redWhyHe : redWhyEn;
      return AnalysedDish(
        dishId: dish.id,
        name: dish.name,
        verdict: DishVerdict.nonKeto,
        why: template.replaceAll('{base}', match.baseLabel ?? ''),
      );
    }

    final dietary = _dietarySentences(text, options, isHebrew: isHebrew);
    if (match.instructions.isNotEmpty || dietary.isNotEmpty) {
      final String why;
      if (match.instructions.isNotEmpty) {
        why = isHebrew ? yellowWhyHe : yellowWhyEn;
      } else {
        why = isHebrew ? dietaryRuleWhyHe : dietaryRuleWhyEn;
      }
      return AnalysedDish(
        dishId: dish.id,
        name: dish.name,
        verdict: DishVerdict.modifiable,
        why: why,
        modification: _joinInstructions([...match.instructions, ...dietary]),
      );
    }

    return AnalysedDish(
      dishId: dish.id,
      name: dish.name,
      verdict: DishVerdict.orderAsIs,
      why: isHebrew ? greenWhyHe : greenWhyEn,
    );
  }

  /// The waiter sentence of every dietary rule [options] switches on
  /// whose triggers [text] names (issue #56), in the fixed order seed-oil,
  /// dairy, carnivore, each in the dish's language ([isHebrew]) exactly
  /// like the `why` strings: the script is read aloud in that restaurant
  /// (architecture.md §12).
  ///
  /// - Seed-oil free: frying or a named seed oil
  ///   ([ClassificationRules.mentionsSeedOil]) asks for olive oil, butter
  ///   or tallow.
  /// - Dairy-free: cheese, cream, butter, milk or yogurt not rescued by a
  ///   plant word ([ClassificationRules.mentionsDairy]) asks for no dairy.
  /// - Carnivore only: any vegetable, salad or other plant
  ///   ([ClassificationRules.mentionsPlant]) asks for only the meat, fish
  ///   or eggs.
  List<String> _dietarySentences(
    String text,
    ClassificationOptions options, {
    required bool isHebrew,
  }) {
    final sentences = <String>[];
    if (options.seedOilFree && ClassificationRules.mentionsSeedOil(text)) {
      sentences.add(
        isHebrew ? seedOilFreeModificationHe : seedOilFreeModificationEn,
      );
    }
    if (options.dairyFree && ClassificationRules.mentionsDairy(text)) {
      sentences.add(
        isHebrew ? dairyFreeModificationHe : dairyFreeModificationEn,
      );
    }
    if (options.carnivoreOnly && ClassificationRules.mentionsPlant(text)) {
      sentences.add(
        isHebrew ? carnivoreOnlyModificationHe : carnivoreOnlyModificationEn,
      );
    }
    return sentences;
  }

  /// Joins several waiter sentences into one script read aloud to a
  /// waiter in one breath.
  ///
  /// Each sentence in `constants.dart` is already a complete, polite,
  /// punctuated request (English "Please ...", Hebrew "אפשר בבקשה
  /// ...?"), so a plain single space between them reads as a short run
  /// of separate asks — "Please omit the beetroot from the dish. Ask
  /// for barbecue glaze to be omitted." — rather than a bulleted list a
  /// person would have to read out loud as bullets. No extra connective
  /// word is needed in either language for that to sound natural.
  String _joinInstructions(List<String> instructions) => instructions.join(' ');
}
