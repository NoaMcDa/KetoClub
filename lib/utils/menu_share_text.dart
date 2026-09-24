/// Builds the plain-text menu summary shared through `MenuSharer` (issue
/// #54): the green dishes, then the yellow dishes each followed by their
/// waiter script, in the menu's own language (architecture.md §12) — never
/// the UI's.
library;

import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/utils/constants.dart';
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
  /// [menu] carries rather than one dish at a time; see [_menuIsHebrew].
  static String build({
    required String venueName,
    required Menu menu,
    required MenuAnalysed analysis,
  }) {
    final isHebrew = _menuIsHebrew(menu);
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
  static bool _menuIsHebrew(Menu menu) {
    final buffer = StringBuffer();
    for (final dish in menu.allDishes) {
      buffer
        ..write(TextNormaliser.dishSearchText(dish))
        ..write(' ');
    }
    return TextNormaliser.containsHebrew(buffer.toString());
  }
}
