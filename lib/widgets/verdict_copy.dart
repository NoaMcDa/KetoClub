/// The words the menu screen gives a dish's state, for one profile (Banto,
/// ALG-05, issue #347; architecture.md D26).
///
/// One pure function of (state, wording) per surface — the pill, the
/// counter tiles, the "Showing" label, the legend, the header counts and
/// the share text — so a surface can never word a state differently from
/// the others, and one test can sweep every combination for the word
/// "safe" (file 09 §3.6, the sibling of `failure_copy.dart`'s
/// no-shared-copy test).
///
/// [ProfileWording.ketoOnly] is today's app: every function returns today's
/// string, verbatim, and `keto_unchanged_test` pins it. A profile with an
/// allergy or celiac disease ([ProfileWording.strict]) never reads as fine:
/// a dish with nothing found is "No trigger found — ask the restaurant",
/// the floor file 09 sets.
///
/// The chrome is ARB. The share headings and the fallback waiter question
/// are Dart, in English and Hebrew, because they follow the **menu's**
/// language rather than the UI's (architecture.md §6.3's exception, §12),
/// as `shareGreenHeadingEn` and the waiter templates already do.
library;

import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/menu_share_text.dart';
import 'package:ketoclub/utils/profile_wording.dart';
import 'package:ketoclub/utils/text_normaliser.dart';
import 'package:ketoclub/utils/verdict_counts.dart';

/// The question for a concern that carries none of its own, in English;
/// `{item}` is the restriction's English name, lower-cased.
const String askQuestionTemplateEn =
    'Does this dish contain {item}, even in a sauce, a dressing or a '
    'garnish?';

/// [askQuestionTemplateEn] in Hebrew; `{item}` is the Hebrew name.
const String askQuestionTemplateHe = 'האם יש במנה {item}, גם ברוטב או בתוספת?';

/// The words for every state-bearing surface; see the library comment.
abstract final class VerdictCopy {
  /// The pill's label for [state].
  static String badge(
    AppLocalizations l10n,
    DishState state,
    ProfileWording wording,
  ) => switch (wording) {
    ProfileWording.ketoOnly => switch (state) {
      DishState.fits => l10n.verdictOrderAsIs,
      DishState.fitsWithChange => l10n.verdictModifiable,
      // Keto alone never asks; the word is still never "safe".
      DishState.ask => l10n.stateAskBadge,
      DishState.avoid => l10n.verdictNonKeto,
    },
    ProfileWording.flexible || ProfileWording.strict => switch (state) {
      DishState.fits =>
        wording == ProfileWording.strict
            ? l10n.stateFitsStrictBadge
            : l10n.stateFitsBadge,
      DishState.fitsWithChange => l10n.stateFitsWithChangeBadge,
      DishState.ask => l10n.stateAskBadge,
      DishState.avoid => l10n.stateAvoidBadge,
    },
  };

  /// The counter tile's label for [state].
  static String tile(
    AppLocalizations l10n,
    DishState state,
    ProfileWording wording,
  ) => switch (wording) {
    ProfileWording.ketoOnly => switch (state) {
      DishState.fits => l10n.tileGreenLabel,
      DishState.fitsWithChange => l10n.tileYellowLabel,
      DishState.ask => l10n.stateAskTile,
      DishState.avoid => l10n.tileRedLabel,
    },
    ProfileWording.flexible || ProfileWording.strict => switch (state) {
      DishState.fits =>
        wording == ProfileWording.strict
            ? l10n.stateFitsStrictTile
            : l10n.stateFitsTile,
      DishState.fitsWithChange => l10n.stateFitsWithChangeTile,
      DishState.ask => l10n.stateAskTile,
      DishState.avoid => l10n.stateAvoidTile,
    },
  };

  /// The legend's definition of [state] for a profile that
  /// [ProfileWording.usesStates];
  /// keto-only legends keep the prompt's own definitions.
  static String legendDefinition(
    AppLocalizations l10n,
    DishState state,
    ProfileWording wording,
  ) => switch (state) {
    DishState.fits =>
      wording == ProfileWording.strict
          ? l10n.stateLegendFitsStrict
          : l10n.stateLegendFits,
    DishState.fitsWithChange => l10n.stateLegendFitsWithChange,
    DishState.ask => l10n.stateLegendAsk,
    DishState.avoid => l10n.stateLegendAvoid,
  };

  /// The notes under the four definitions of a state legend: the engines,
  /// what the counters count, and the helper-tool sentence, which every
  /// menu's legend carries for a non-keto profile (file 09 §4, D-b).
  static List<String> legendNotes(AppLocalizations l10n) => <String>[
    l10n.legendEngines,
    l10n.stateLegendFoodOnly,
    l10n.helperToolSentence,
  ];

  /// The "Showing" label for [filter]; [total] is the menu's dish count.
  ///
  /// [MenuFilter.greenAndYellow] reads, in state mode, as "everything except
  /// what to avoid": the default filter of a strict profile, which keeps
  /// the dishes that fit, fit with a change, and the ones to ask about.
  /// [MenuFilter.askOnly] has no keto meaning and shows every dish there.
  static String showing(
    AppLocalizations l10n,
    MenuFilter filter,
    ProfileWording wording, {
    required int total,
  }) => switch (wording) {
    ProfileWording.ketoOnly => switch (filter) {
      MenuFilter.greenOnly => l10n.menuShowingGreen,
      MenuFilter.yellowOnly => l10n.menuShowingYellow,
      MenuFilter.redOnly => l10n.menuShowingRed,
      MenuFilter.greenAndYellow => l10n.menuShowingGreenAndYellow,
      MenuFilter.all || MenuFilter.askOnly => l10n.menuShowingAll(total),
    },
    ProfileWording.flexible || ProfileWording.strict => switch (filter) {
      MenuFilter.greenOnly =>
        wording == ProfileWording.strict
            ? l10n.menuShowingFitsStrict
            : l10n.menuShowingFits,
      MenuFilter.yellowOnly => l10n.menuShowingFitsWithChange,
      MenuFilter.askOnly => l10n.menuShowingAsk,
      MenuFilter.redOnly => l10n.menuShowingAvoid,
      MenuFilter.greenAndYellow => l10n.menuShowingNotAvoid,
      MenuFilter.all => l10n.menuShowingAll(total),
    },
  };

  /// The header line that replaces the keto score for a profile without
  /// keto: "N fit · M with a change · K to ask" (file 09 §5).
  static String headerCounts(
    AppLocalizations l10n,
    VerdictCounts counts,
    ProfileWording wording,
  ) => wording == ProfileWording.strict
      ? l10n.headerStateCountsStrict(counts.green, counts.yellow, counts.ask)
      : l10n.headerStateCounts(counts.green, counts.yellow, counts.ask);

  /// The share text's heading over [state]'s dishes, in the menu's
  /// language; null for [DishState.avoid], which is never shared. The
  /// table lives in `utils/menu_share_text.dart`, which builds the text.
  static String? shareHeading(
    DishState state,
    ProfileWording wording, {
    required bool hebrew,
  }) => MenuShareText.stateHeading(state, wording, hebrew: hebrew);

  /// The share text's closing line, in the menu's language: only a strict
  /// profile has one.
  static String? shareFooter(ProfileWording wording, {required bool hebrew}) =>
      MenuShareText.stateFooter(wording, hebrew: hebrew);

  /// The question to read to the waiter about [evaluated], in the menu's
  /// language ([hebrew]): the first concern's own question, else one
  /// built from the first concern that made the dish an "ask" — a
  /// suspected one on a strict restriction — or, failing that, the first
  /// concern. Null when there is no concern at all.
  static String? waiterQuestion(
    EvaluatedDish evaluated, {
    required bool hebrew,
  }) {
    final concerns = evaluated.concerns;
    for (final concern in concerns) {
      final question = concern.waiterQuestion;
      if (question != null && question.trim().isNotEmpty) return question;
    }
    if (concerns.isEmpty) return null;
    final asking = concerns.firstWhere(
      (concern) =>
          concern.certainty == Certainty.suspected &&
          restrictionFor(concern.restrictionId).isStrict,
      orElse: () => concerns.first,
    );
    return askQuestionFor(asking.restrictionId, hebrew: hebrew);
  }

  /// The one waiter line a dish card offers for [evaluated], the analysis
  /// of [dish], in the menu's language: the evaluator's modification for a
  /// dish that fits with a change, the [waiterQuestion] for one to ask
  /// about, and null for a dish that fits as it is or is to be avoided.
  static String? waiterLine(EvaluatedDish evaluated, Dish dish) =>
      switch (evaluated.state) {
        DishState.fitsWithChange => evaluated.modification,
        DishState.ask => waiterQuestion(evaluated, hebrew: dishIsHebrew(dish)),
        DishState.fits || DishState.avoid => null,
      };

  /// Whether [dish]'s own text is Hebrew, the language its waiter line and
  /// its restriction names are written in (§12), as the rule engine and
  /// `ProfileEvaluator` choose it.
  static bool dishIsHebrew(Dish dish) =>
      TextNormaliser.containsHebrew(TextNormaliser.dishRulesText(dish));

  /// The name of [id] in the dish's language ([hebrew]), from the
  /// taxonomy rather than ARB: it is read beside the dish's own name
  /// (file 10 §ALG-05, "Accessibility and RTL").
  static String restrictionName(RestrictionId id, {required bool hebrew}) {
    final restriction = restrictionFor(id);
    return hebrew ? restriction.nameHe : restriction.nameEn;
  }

  /// [askQuestionTemplateEn] or [askQuestionTemplateHe] for [id].
  static String askQuestionFor(RestrictionId id, {required bool hebrew}) {
    final restriction = restrictionFor(id);
    return hebrew
        ? askQuestionTemplateHe.replaceAll('{item}', restriction.nameHe)
        : askQuestionTemplateEn.replaceAll(
            '{item}',
            restriction.nameEn.toLowerCase(),
          );
  }
}
