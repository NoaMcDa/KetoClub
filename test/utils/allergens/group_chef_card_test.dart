// GroupChefCardText (Banto; ALG-12, #354): the chef card with one section
// per person, built from the ALG-08a templates.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/utils/allergens/group_chef_card.dart';

void main() {
  group('GroupChefCardText', () {
    final me = NamedProfile(
      id: NamedProfile.primaryId,
      name: '',
      profile: DietaryProfile.empty.withEntry(RestrictionId.milk),
    );
    const dana = NamedProfile(id: 'p1', name: 'Dana');

    test('one section per person under their name', () {
      // Act
      final card = GroupChefCardText.compose(<NamedProfile>[
        me,
        dana,
      ], hebrew: false);

      // Assert
      expect(card.sections.map((section) => section.heading).toList(), <String>[
        'Me',
        'Dana',
      ]);
    });

    test('a section is the single card without its greeting and closing', () {
      // Arrange
      final single = ChefCardText.compose(me.profile, hebrew: false);

      // Act
      final card = GroupChefCardText.compose(<NamedProfile>[
        me,
        dana,
      ], hebrew: false);

      // Assert
      expect(card.sections.first.lines, single.sublist(1, single.length - 1));
    });

    test('an empty profile gets the keto line', () {
      // Arrange
      final keto = ChefCardText.compose(
        DietaryProfile.empty.withEntry(RestrictionId.keto),
        hebrew: true,
      );

      // Act
      final card = GroupChefCardText.compose(<NamedProfile>[
        me,
        dana,
      ], hebrew: true);

      // Assert
      expect(card.sections.last.lines, <String>[keto[1]]);
      expect(card.sections.first.heading, 'אני');
    });

    test('the closing asks about cross-contact when anyone is strict', () {
      // Arrange
      final strictClosing = ChefCardText.compose(
        me.profile,
        hebrew: false,
      ).last;

      // Act
      final card = GroupChefCardText.compose(<NamedProfile>[
        dana,
        me,
      ], hebrew: false);

      // Assert
      expect(card.closing, strictClosing);
    });

    test('asText lists each heading before its lines, and no "safe"', () {
      // Act
      final card = GroupChefCardText.compose(<NamedProfile>[
        me,
        dana,
      ], hebrew: false);
      final text = GroupChefCardText.asText(card);

      // Assert
      final lines = text.split('\n');
      expect(lines.first, card.intro);
      expect(lines, containsAllInOrder(<String>['Me:', 'Dana:']));
      expect(lines.last, card.closing);
      expect(text.toLowerCase(), isNot(contains('safe')));
    });
  });
}
