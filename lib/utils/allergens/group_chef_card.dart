/// The chef card for several people (Banto; the Allergens epic, ALG-12,
/// issue #354): one section per person, each the ALG-08a card's own entry
/// lines ([ChefCardText.compose]) under the person's name.
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

/// One person's section of the group card.
typedef ChefCardSection = ({String heading, List<String> lines});

/// The whole group card: a greeting, the sections, a closing line.
typedef GroupChefCard = ({
  String intro,
  List<ChefCardSection> sections,
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
      closing: whole.isEmpty ? '' : whole.last,
    );
  }

  /// [card] as the plain text that is shared: the greeting, each heading
  /// followed by its lines, and the closing, one per line.
  static String asText(GroupChefCard card) => <String>[
    card.intro,
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

  static const String _meEn = 'Me';
  static const String _meHe = 'אני';
}
