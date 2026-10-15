// GroupChefCardText (Banto; ALG-12, #354): the chef card with one section
// per person, built from the ALG-08a templates.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/utils/allergens/group_chef_card.dart';
import 'package:ketoclub/utils/allergens/kitchen_signals.dart';

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

  group('GroupChefCardText.composeForDish', () {
    final sesame = NamedProfile(
      id: NamedProfile.primaryId,
      name: '',
      profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
    );
    const keto = NamedProfile(id: 'p1', name: 'Dana');
    const question = 'Can this be made without sesame?';
    const questionHe = 'אפשר להכין את המנה בלי שומשום?';
    final bannedWords = RegExp(
      '(?<![A-Za-z])(safe|fine|guarantee)|בטוח|מובטח',
      caseSensitive: false,
    );

    GroupChefCard card({
      bool hebrew = false,
      bool crossContact = false,
      String dishName = 'Tahini salad',
      String? change,
      List<String> questions = const <String>[question],
    }) => GroupChefCardText.composeForDish(
      <PersonDishPart>[
        (person: sesame, modification: change, questions: questions),
        (person: keto, modification: null, questions: const <String>[]),
      ],
      dishName: dishName,
      crossContact: crossContact,
      hebrew: hebrew,
    );

    test('each person has their lines and only their own questions', () {
      // Act
      final result = card(change: 'Ask for it without the tahini.');

      // Assert
      final single = ChefCardText.compose(sesame.profile, hebrew: false);
      expect(result.sections.map((s) => s.heading).toList(), <String>[
        'Me',
        'Dana',
      ]);
      expect(result.sections.first.lines, <String>[
        single[1],
        'Ask for it without the tahini.',
        question,
      ]);
    });

    test('a person with nothing for the dish keeps their lines and no '
        'question', () {
      // Act
      final result = card();

      // Assert: Dana (keto) states the keto line, nothing else.
      final ketoLine = ChefCardText.compose(
        DietaryProfile.empty.withEntry(RestrictionId.keto),
        hebrew: false,
      )[1];
      expect(result.sections.last.lines, <String>[ketoLine]);
    });

    test('a profile with a strict entry states only the strict ones', () {
      // Arrange
      final both = NamedProfile(
        id: 'p2',
        name: 'Lior',
        profile: DietaryProfile.empty
            .withEntry(RestrictionId.lactose)
            .withEntry(RestrictionId.sesame),
      );

      // Act
      final result = GroupChefCardText.composeForDish(
        <PersonDishPart>[
          (person: both, modification: null, questions: const <String>[]),
        ],
        dishName: 'x',
        crossContact: false,
        hebrew: false,
      );

      // Assert
      expect(result.sections.single.lines, hasLength(1));
      expect(result.sections.single.lines.single, contains('allergy'));
    });

    test('the dish is named once, before the sections, and the closing '
        'once', () {
      // Act
      final result = card(crossContact: true);
      final text = GroupChefCardText.asText(result);

      // Assert
      expect(result.dishLine, 'The dish we would like: Tahini salad');
      expect(
        ChefCardText.closingLine(crossContact: true, hebrew: false),
        result.closing,
      );
      final lines = text.split('\n');
      expect(lines.first, result.intro);
      expect(lines[1], result.dishLine);
      expect(lines.last, result.closing);
      expect('Tahini salad'.allMatches(text), hasLength(1));
      expect(lines, containsAllInOrder(<String>['Me:', 'Dana:']));
    });

    test('closes with thanks when the kitchen threatens no one', () {
      expect(card().closing, 'Thank you.');
      expect(card(hebrew: true).closing, 'תודה.');
    });

    test('a blank dish name leaves out the naming line', () {
      expect(card(dishName: '  ').dishLine, isEmpty);
      expect(
        GroupChefCardText.asText(card(dishName: '')).split('\n'),
        isNot(contains(startsWith('The dish'))),
      );
    });

    test('Hebrew: names, lines, the dish and the closing', () {
      // Act
      final result = card(
        hebrew: true,
        crossContact: true,
        dishName: 'סלט עם טחינה',
        questions: const <String>[questionHe],
      );

      // Assert
      expect(result.sections.first.heading, 'אני');
      expect(result.sections.first.lines.last, questionHe);
      expect(result.dishLine, 'המנה שאנחנו רוצים להזמין: סלט עם טחינה');
      expect(result.intro, startsWith('שלום'));
      expect(
        result.closing,
        ChefCardText.closingLine(crossContact: true, hebrew: true),
      );
    });

    test('no sentence says a dish is fine', () {
      for (final hebrew in <bool>[false, true]) {
        for (final crossContact in <bool>[false, true]) {
          final text = GroupChefCardText.asText(
            card(hebrew: hebrew, crossContact: crossContact),
          );
          expect(text, isNot(matches(bannedWords)), reason: text);
        }
      }
    });

    test('kitchenThreatensStrict is true when any person is threatened', () {
      // Arrange: a sesame signal threatens the sesame person, not Dana.
      final signals = <KitchenSignal>[
        const KitchenSignal(
          kind: KitchenSignalKind.sesame,
          threatens: <RestrictionId>[RestrictionId.sesame],
          evidence: <String>[],
          questionEn: 'q',
          questionHe: 'ש',
        ),
      ];

      // Assert
      expect(
        GroupChefCardText.kitchenThreatensStrict(signals, <NamedProfile>[
          keto,
          sesame,
        ]),
        isTrue,
      );
      expect(
        GroupChefCardText.kitchenThreatensStrict(signals, <NamedProfile>[keto]),
        isFalse,
      );
    });
  });
}
