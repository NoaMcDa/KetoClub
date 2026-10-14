/// Builds the plain-text menu summary shared through `MenuSharer` (issue
/// #54): the green dishes, then the yellow dishes each followed by their
/// waiter script, in the menu's own language (architecture.md §12) — never
/// the UI's.
library;

import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/profile_wording.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// Builds a plain-text, human-readable summary of a classified menu's safe
/// dishes, for the menu screen's share action (issue #54).
///
/// Pure and static: no I/O, no platform call. **Nothing about the user
/// appears in the result.** [build] is never given a personal note (issue
/// #52), a setting such as the net-carb limit, or an install id — its
/// three parameters carry only the venue's display name, the menu and its
/// analysis, so there is nothing about the person reading it for this
/// function to leak even by accident.
abstract final class MenuShareText {
  /// Builds the summary for [venueName]'s [menu], judged by [analysis].
  ///
  /// Lists every [DishVerdict.orderAsIs] dish under a green heading, then
  /// every [DishVerdict.modifiable] dish — each followed by its
  /// [AnalysedDish.modification], the same waiter script the Waiter Card
  /// shows — under a yellow heading. [DishVerdict.nonKeto] dishes and
  /// names in [MenuAnalysed.unclassified] are left out entirely: this is
  /// "what is safe to order here", not a full menu transcript. A group
  /// with no dishes is omitted — heading included — rather than printed
  /// empty; when both groups are empty the result is [venueName] alone.
  ///
  /// Both groups keep [MenuAnalysed.dishes]' own order. Every
  /// `MenuClassifier` already produces that list in the menu's own
  /// category order — `HeuristicMenuClassifier` walks `menu.allDishes`,
  /// and `MenuResponseParser` preserves the same source order for every
  /// dish it places — so this function does no re-sorting of its own.
  ///
  /// The heading language is the **menu's** language, never the UI's
  /// (architecture.md §12) — detected the same way the heuristic engine
  /// and the waiter script already are ([TextNormaliser.containsHebrew]
  /// over [TextNormaliser.dishSearchText]), applied here across every dish
  /// [menu] carries rather than one dish at a time; see [menuIsHebrew].
  ///
  /// **Banto (ALG-05, issue #347).** With a [wording] that
  /// [ProfileWording.usesStates] and the dishes' [evaluations] (by dish
  /// id), the groups are the on-device states instead: the dishes that fit
  /// (for a strict profile headed "No trigger found — ask the restaurant",
  /// never "safe"), those that fit with a change, each followed by the
  /// evaluator's change, and those to ask the restaurant about; a dish to
  /// avoid is left out, and a strict profile's text ends with a line
  /// saying only the menu text was read. The headings are [stateHeading]
  /// and [stateFooter], in the menu's language. The profile itself is
  /// never written: no restriction is named, and no question is copied.
  /// A keto-only [wording] (the default) is the text above, byte for byte.
  static String build({
    required String venueName,
    required Menu menu,
    required MenuAnalysed analysis,
    ProfileWording wording = ProfileWording.ketoOnly,
    Map<String, EvaluatedDish> evaluations = const <String, EvaluatedDish>{},
  }) {
    final isHebrew = menuIsHebrew(menu);
    if (wording.usesStates) {
      return _stateText(
        venueName: venueName,
        analysis: analysis,
        evaluations: evaluations,
        wording: wording,
        isHebrew: isHebrew,
      );
    }
    final green = <AnalysedDish>[
      for (final dish in analysis.dishes)
        if (dish.verdict == DishVerdict.orderAsIs) dish,
    ];
    final yellow = <AnalysedDish>[
      for (final dish in analysis.dishes)
        if (dish.verdict == DishVerdict.modifiable) dish,
    ];

    final lines = <String>[venueName];
    if (green.isNotEmpty) {
      lines
        ..add('')
        ..add(isHebrew ? shareGreenHeadingHe : shareGreenHeadingEn)
        ..addAll(green.map((dish) => '- ${dish.name}'));
    }
    if (yellow.isNotEmpty) {
      lines
        ..add('')
        ..add(isHebrew ? shareYellowHeadingHe : shareYellowHeadingEn)
        ..addAll(yellow.expand(_yellowLines));
    }
    return lines.join('\n');
  }

  /// The heading over [state]'s dishes in the shared text for [wording],
  /// in the menu's language ([hebrew]); null for [DishState.avoid], which
  /// is never shared. Keto-only reads today's green and yellow headings.
  /// Dart, not ARB, because it follows the menu's language (§6.3, §12).
  static String? stateHeading(
    DishState state,
    ProfileWording wording, {
    required bool hebrew,
  }) => switch (state) {
    DishState.fits => switch (wording) {
      ProfileWording.ketoOnly =>
        hebrew ? shareGreenHeadingHe : shareGreenHeadingEn,
      ProfileWording.flexible =>
        hebrew ? shareFitsHeadingHe : shareFitsHeadingEn,
      ProfileWording.strict =>
        hebrew ? shareFitsStrictHeadingHe : shareFitsStrictHeadingEn,
    },
    DishState.fitsWithChange =>
      wording == ProfileWording.ketoOnly
          ? (hebrew ? shareYellowHeadingHe : shareYellowHeadingEn)
          : (hebrew
                ? shareFitsWithChangeHeadingHe
                : shareFitsWithChangeHeadingEn),
    DishState.ask => hebrew ? shareAskHeadingHe : shareAskHeadingEn,
    DishState.avoid => null,
  };

  /// The shared text's closing line for [wording]: only a strict profile
  /// has one, saying only the menu text was read.
  static String? stateFooter(ProfileWording wording, {required bool hebrew}) =>
      wording == ProfileWording.strict
      ? (hebrew ? shareStrictFooterHe : shareStrictFooterEn)
      : null;

  /// The state-mode text; see [build].
  static String _stateText({
    required String venueName,
    required MenuAnalysed analysis,
    required Map<String, EvaluatedDish> evaluations,
    required ProfileWording wording,
    required bool isHebrew,
  }) {
    List<EvaluatedDish> inState(DishState state) => <EvaluatedDish>[
      for (final dish in analysis.dishes)
        if (evaluations[dish.dishId] case final evaluated?
            when evaluated.state == state)
          evaluated,
    ];
    final lines = <String>[venueName];
    for (final state in <DishState>[
      DishState.fits,
      DishState.fitsWithChange,
      DishState.ask,
    ]) {
      final dishes = inState(state);
      final heading = stateHeading(state, wording, hebrew: isHebrew);
      if (dishes.isEmpty || heading == null) continue;
      lines
        ..add('')
        ..add(heading);
      for (final evaluated in dishes) {
        lines.add('- ${evaluated.dish.name}');
        final change = evaluated.modification;
        if (state == DishState.fitsWithChange &&
            change != null &&
            change.isNotEmpty) {
          lines.add('  ${change.replaceAll('\n', '\n  ')}');
        }
      }
    }
    final footer = stateFooter(wording, hebrew: isHebrew);
    if (footer != null) {
      lines
        ..add('')
        ..add(footer);
    }
    return lines.join('\n');
  }

  /// The lines one [DishVerdict.modifiable] dish contributes: its name,
  /// then its [AnalysedDish.modification] on its own line — omitted only
  /// when [dish] somehow carries none, which a well-formed
  /// `MenuClassifier` result never does (`AnalysedDish.tryFrom`'s own
  /// invariant), but this function still never prints the literal string
  /// "null" if one slips through.
  static Iterable<String> _yellowLines(AnalysedDish dish) sync* {
    yield '- ${dish.name}';
    final modification = dish.modification;
    if (modification != null && modification.isNotEmpty) {
      // A script holds one instruction per line (architecture.md §6.3);
      // each keeps the same indent under the dish name.
      yield '  ${modification.replaceAll('\n', '\n  ')}';
    }
  }

  /// Whether [menu] reads as Hebrew: true when any dish's searchable text
  /// ([TextNormaliser.dishSearchText] — name, description and every
  /// option) contains a Hebrew letter ([TextNormaliser.containsHebrew]),
  /// the same test `HeuristicMenuClassifier` runs per dish to pick a
  /// waiter-script language, run once here over the whole menu instead of
  /// once per dish.
  static bool menuIsHebrew(Menu menu) {
    final buffer = StringBuffer();
    for (final dish in menu.allDishes) {
      buffer
        ..write(TextNormaliser.dishSearchText(dish))
        ..write(' ');
    }
    return TextNormaliser.containsHebrew(buffer.toString());
  }
}

/// The share heading over the dishes that fit, for a strict profile, in
/// English: never "safe" (file 09 §3.6).
const String shareFitsStrictHeadingEn =
    'No trigger found — ask the restaurant:';

/// [shareFitsStrictHeadingEn] in Hebrew.
const String shareFitsStrictHeadingHe = 'לא נמצא חשש — לשאול את המסעדה:';

/// The share heading over the dishes that fit, for a flexible profile.
const String shareFitsHeadingEn = 'Fits:';

/// [shareFitsHeadingEn] in Hebrew.
const String shareFitsHeadingHe = 'מתאימות:';

/// The share heading over the dishes that fit with a change.
const String shareFitsWithChangeHeadingEn = 'With a change:';

/// [shareFitsWithChangeHeadingEn] in Hebrew.
const String shareFitsWithChangeHeadingHe = 'עם שינוי:';

/// The share heading over the dishes to ask about.
const String shareAskHeadingEn = 'Ask the restaurant first:';

/// [shareAskHeadingEn] in Hebrew.
const String shareAskHeadingHe = 'לשאול את המסעדה קודם:';

/// The closing line of a strict profile's share text.
const String shareStrictFooterEn =
    'Read from the menu text only. Ask the restaurant.';

/// [shareStrictFooterEn] in Hebrew.
const String shareStrictFooterHe = 'נקרא מטקסט התפריט בלבד. לשאול את המסעדה.';
