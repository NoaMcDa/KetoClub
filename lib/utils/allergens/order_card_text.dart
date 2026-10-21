/// The order card's text (Banto, issue #418): the dishes a person picked
/// from one menu, one section each — the dish's name as printed, its
/// change, the questions to ask about it — and the profile's allergy
/// note once at the end, for the waiter to read in one go.
///
/// Every sentence is reused from the per-dish surfaces rather than
/// written again: the change is the evaluator's (`ProfileEvaluator`,
/// ALG-05), the questions are the Waiter Card's (`VerdictCopy
/// .waiterQuestions`, ALG-08b, handed in by the screen since that lives in
/// `widgets/`), and the allergy note is [ChefCardText.allergyNote]
/// (ALG-15), the same one the menu's "Copy allergy note" copies. The one
/// sentence added here says, for a dish the profile would avoid, what the
/// menu names in it ("The menu names 'tahini' in this dish."); it is read
/// to restaurant staff, so it follows the dish's language and lives in
/// Dart, not ARB (architecture.md §6.3 and §12, the documented exception).
///
/// Nothing here says a dish is safe: an avoided dish keeps its question,
/// and a dish with nothing found has no line of its own. Pure: no widget,
/// no clock, no I/O.
library;

import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/allergens/waiter_questions.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// "The menu names {item} in this dish." in English; `{item}` is the
/// menu's own words in quotes, or the restriction as the thing avoided.
const String orderNamesTemplateEn = 'The menu names {item} in this dish.';

/// [orderNamesTemplateEn] in Hebrew.
const String orderNamesTemplateHe = 'התפריט מציין {item} במנה הזו.';

/// One dish of an order as the menu screen hands it over: the dish as
/// printed, its evaluation for the profile (a group's combined one), and
/// the questions the Waiter Card would read for it, already in the dish's
/// language.
typedef OrderDish = ({
  Dish dish,
  EvaluatedDish evaluated,
  List<String> questions,
});

/// One dish's section of the order card: its id (for removing it), its
/// name as printed, whether its lines are Hebrew, and the lines.
typedef OrderSection = ({
  String dishId,
  String name,
  bool hebrew,
  List<String> lines,
});

/// The whole order card: a section per dish, in the order they were
/// added, and the allergy note once (null for a profile with nothing but
/// keto), in the menu's language.
typedef OrderCard = ({
  List<OrderSection> sections,
  String? allergyNote,
  bool hebrew,
});

/// Composes the order card.
abstract final class OrderCardText {
  /// The card for [dishes], in order, under [profile] — the union of the
  /// people the menu is read for, as the menu's own allergy note uses it —
  /// with the allergy note in Hebrew when [hebrew] (the menu's language,
  /// `MenuShareText.menuIsHebrew`). Each section's lines are in its own
  /// dish's language ([sectionLines]).
  static OrderCard compose(
    List<OrderDish> dishes, {
    required DietaryProfile profile,
    required bool hebrew,
  }) => (
    sections: List<OrderSection>.unmodifiable(<OrderSection>[
      for (final item in dishes)
        (
          dishId: item.dish.id,
          name: item.dish.name.trim(),
          hebrew: dishIsHebrew(item.dish),
          lines: sectionLines(item),
        ),
    ]),
    allergyNote: ChefCardText.allergyNote(profile, hebrew: hebrew),
    hebrew: hebrew,
  );

  /// The lines under [item]'s name, in the dish's language.
  ///
  /// A dish to avoid first says what the menu names in it, once per
  /// restriction found stated or likely ([namesLine]); any other dish
  /// first gives its change, one line each. Then every one of the dish's
  /// questions, for every state: the person decides, and the waiter is
  /// asked either way. A dish with nothing found has no line.
  static List<String> sectionLines(OrderDish item) {
    final evaluated = item.evaluated;
    final hebrew = dishIsHebrew(item.dish);
    final lines = <String>[];
    void add(String line) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && !lines.contains(trimmed)) lines.add(trimmed);
    }

    if (evaluated.state == DishState.avoid) {
      for (final concern in evaluated.concerns) {
        if (concern.certainty == Certainty.suspected) continue;
        add(namesLine(concern, hebrew: hebrew));
      }
    } else if (evaluated.modification case final change?) {
      change.split('\n').forEach(add);
    }
    item.questions.forEach(add);
    return List<String>.unmodifiable(lines);
  }

  /// "The menu names {item} in this dish." for [concern], in Hebrew when
  /// [hebrew]: the menu's own words in single quotes when they are short
  /// enough to quote, else the restriction as the thing avoided
  /// ([WaiterQuestions.subject]).
  static String namesLine(Concern concern, {required bool hebrew}) {
    final matched = concern.matchedText?.trim();
    final item =
        matched != null &&
            matched.isNotEmpty &&
            matched.length <= _maxQuotedLength
        ? "'$matched'"
        : WaiterQuestions.subject(concern.restrictionId, hebrew: hebrew);
    return (hebrew ? orderNamesTemplateHe : orderNamesTemplateEn).replaceAll(
      '{item}',
      item,
    );
  }

  /// Whether [dish]'s own text is Hebrew: the language its change and its
  /// questions were written in (§12), as the evaluator chooses it.
  static bool dishIsHebrew(Dish dish) =>
      TextNormaliser.containsHebrew(TextNormaliser.dishRulesText(dish));

  /// [card] as the plain text that is copied and shared: each dish's name
  /// followed by its lines, a blank line between dishes, then the allergy
  /// note.
  static String asText(OrderCard card) => <String>[
    for (final section in card.sections)
      <String>[section.name, ...section.lines].join('\n'),
    ?card.allergyNote,
  ].join('\n\n');

  /// The most characters of menu text a line quotes, as a waiter question
  /// does: a longer slice is a sentence, not an ingredient.
  static const int _maxQuotedLength = 40;
}
