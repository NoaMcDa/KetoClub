/// The chef card for several people (Banto; the Allergens epic, ALG-12,
/// issue #354): one section per person, each the ALG-08a card's own entry
/// lines ([ChefCardText.compose]) under the person's name; and, for one
/// dish ([GroupChefCardText.composeForDish]), the dish's name once, then
/// the same sections each followed by that person's change and questions
/// for the dish, and one closing.
///
/// Like [ChefCardText], this text is shown and read to restaurant staff, so
/// it follows the language picked for the card, not the UI's, and the two
/// sentences it adds (a greeting and the primary profile's default name)
/// live here rather than in ARB (architecture.md §6.3 and §12, the
/// documented exception). It never says a dish is safe. Pure.
library;

import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/utils/allergens/group_evaluator.dart';
import 'package:ketoclub/utils/allergens/kitchen_signals.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';

/// One person's section of the group card.
typedef ChefCardSection = ({String heading, List<String> lines});

/// What one person's evaluation of the dish adds to their section of a
/// group dish card ([GroupChefCardText.composeForDish]): the change and
/// the questions that apply to them, already in the menu's language.
typedef PersonDishPart = ({
  NamedProfile person,
  String? modification,
  List<String> questions,
});

/// The whole group card: a greeting, the sections, the dish's naming line
/// (empty unless the card is for one dish) and a closing line.
typedef GroupChefCard = ({
  String intro,
  List<ChefCardSection> sections,
  String dishLine,
  String closing,
});

/// Composes the group chef card.
abstract final class GroupChefCardText {
  /// The card for [people] in Hebrew when [hebrew], else English.
  ///
  /// Each section is headed by the person's name — the primary profile's
  /// default name in the card's language when the user never renamed it —
  /// and holds [ChefCardText.compose]'s lines for that person without its
  /// greeting and closing. An empty profile reads as keto, as it does
  /// everywhere else, so it gets the keto line. The closing is the one
  /// [ChefCardText.compose] gives everyone's restrictions together: the
  /// cross-contact request whenever anyone has a strict entry.
  static GroupChefCard compose(
    List<NamedProfile> people, {
    required bool hebrew,
  }) {
    final sections = <ChefCardSection>[
      for (final person in people)
        (
          heading: headingFor(person, hebrew: hebrew),
          lines: _entryLines(_withKeto(person.profile), hebrew: hebrew),
        ),
    ];
    final everyone = GroupEvaluator.union(<DietaryProfile>[
      for (final person in people) _withKeto(person.profile),
    ]);
    final whole = ChefCardText.compose(everyone, hebrew: hebrew);
    return (
      intro: hebrew ? _introHe : _introEn,
      sections: List<ChefCardSection>.unmodifiable(sections),
      dishLine: '',
      closing: whole.isEmpty ? '' : whole.last,
    );
  }

  /// The group card for one dish (ALG-12, issue #354, the follow-up of
  /// ALG-08b), in Hebrew when [hebrew], else English: the greeting once;
  /// then the dish's name once, as the menu printed it, so the questions
  /// below read after it (empty when [dishName] is blank); then one
  /// section per entry of [parts], in order — the person's name,
  /// their restriction lines (their strict entries, or every entry when
  /// they hold none, as the single dish card does; keto for an empty
  /// profile), then the change and every question that apply to *them*
  /// for this dish; and one closing, the
  /// cross-contact request when [crossContact] (a kitchen signal
  /// threatens a strict entry of anyone, [kitchenThreatensStrict]) and
  /// thanks otherwise.
  ///
  /// A person the dish raises nothing for keeps their restriction lines,
  /// so the kitchen knows they are at the table, and has no change or
  /// question under them. A part's modification and questions are used as
  /// given. Nothing here says the dish is fine.
  static GroupChefCard composeForDish(
    List<PersonDishPart> parts, {
    required String dishName,
    required bool crossContact,
    required bool hebrew,
  }) {
    final sections = <ChefCardSection>[
      for (final part in parts)
        (
          heading: headingFor(part.person, hebrew: hebrew),
          lines: List<String>.unmodifiable(<String>[
            ..._entryLines(
              _headed(_withKeto(part.person.profile)),
              hebrew: hebrew,
            ),
            if (part.modification != null)
              for (final line in part.modification!.split('\n'))
                if (line.trim().isNotEmpty) line.trim(),
            for (final question in part.questions)
              if (question.trim().isNotEmpty) question.trim(),
          ]),
        ),
    ];
    final name = dishName.trim();
    return (
      intro: hebrew ? _introHe : _introEn,
      sections: List<ChefCardSection>.unmodifiable(sections),
      dishLine: name.isEmpty
          ? ''
          : (hebrew ? _dishLineHe : _dishLineEn).replaceAll('{dish}', name),
      closing: ChefCardText.closingLine(
        crossContact: crossContact,
        hebrew: hebrew,
      ),
    );
  }

  /// Whether any of [signals] threatens a strict entry of any of [people]
  /// ([ChefCardText.kitchenThreatensStrict] for each).
  static bool kitchenThreatensStrict(
    List<KitchenSignal> signals,
    List<NamedProfile> people,
  ) => people.any(
    (person) => ChefCardText.kitchenThreatensStrict(signals, person.profile),
  );

  /// [card] as the plain text that is shared: the greeting, the dish's
  /// name on a dish card, each heading followed by its lines, and the
  /// closing, one per line.
  static String asText(GroupChefCard card) => <String>[
    card.intro,
    if (card.dishLine.isNotEmpty) card.dishLine,
    for (final section in card.sections) ...<String>[
      '${section.heading}:',
      ...section.lines,
    ],
    if (card.closing.isNotEmpty) card.closing,
  ].join('\n');

  /// [person]'s name, or the primary profile's default name in the card's
  /// language when it has none.
  static String headingFor(NamedProfile person, {required bool hebrew}) {
    if (person.name.isNotEmpty) return person.name;
    return hebrew ? _meHe : _meEn;
  }

  /// [profile], or keto alone when it is empty.
  static DietaryProfile _withKeto(DietaryProfile profile) =>
      profile.isEmpty ? profile.withEntry(RestrictionId.keto) : profile;

  /// [profile]'s strict entries (an allergen or celiac disease) or, with
  /// none, all of it: the entries a dish card states.
  static DietaryProfile _headed(DietaryProfile profile) {
    final strict = <ProfileEntry>[
      for (final entry in profile.entries)
        if (restrictionFor(entry.restrictionId).isStrict) entry,
    ];
    if (strict.isEmpty) return profile;
    var headed = DietaryProfile.empty;
    for (final entry in strict) {
      headed = headed.withEntry(
        entry.restrictionId,
        exceptions: entry.exceptions,
      );
    }
    return headed;
  }

  /// [ChefCardText.compose]'s lines for [profile] between its greeting and
  /// its closing.
  static List<String> _entryLines(
    DietaryProfile profile, {
    required bool hebrew,
  }) {
    final lines = ChefCardText.compose(profile, hebrew: hebrew);
    if (lines.length < 2) return const <String>[];
    return List<String>.unmodifiable(lines.sublist(1, lines.length - 1));
  }

  static const String _introEn =
      'Hello, some of us have dietary restrictions and we would like your '
      'help with our order.';
  static const String _introHe =
      'שלום, לחלק מאיתנו יש הגבלות תזונה ונשמח לעזרתכם בהזמנה.';

  static const String _dishLineEn = 'The dish we would like: {dish}';
  static const String _dishLineHe = 'המנה שאנחנו רוצים להזמין: {dish}';

  static const String _meEn = 'Me';
  static const String _meHe = 'אני';
}
