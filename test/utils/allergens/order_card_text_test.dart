// The order card's text (Banto, issue #418): one section per chosen dish,
// in the dish's language, built from the evaluator's change and the
// Waiter Card's questions; an avoided dish says what the menu names in
// it; the profile's allergy note once, in the menu's language; never
// "safe".

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/wolt/wolt_menu_mapper.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/utils/allergens/group_evaluator.dart';
import 'package:ketoclub/utils/allergens/order_card_text.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/widgets/verdict_copy.dart';

final DietaryProfile _sesame = DietaryProfile.empty.withEntry(
  RestrictionId.sesame,
);

final DietaryProfile _milk = DietaryProfile.empty.withEntry(RestrictionId.milk);

/// A dish with [id] and [name], and [options] when given.
Dish _dish(
  String id,
  String name, {
  List<DishOption> options = const <DishOption>[],
}) => Dish(id: id, name: name, description: '', price: 10, options: options);

/// The model's green answer for [dish].
AnalysedDish _green(Dish dish) => AnalysedDish(
  dishId: dish.id,
  name: dish.name,
  verdict: DishVerdict.orderAsIs,
  why: 'Nothing starchy.',
);

/// [dish] as the menu screen hands it to the order card for [profile]:
/// evaluated on the device, with the Waiter Card's questions.
OrderDish _item(Dish dish, DietaryProfile profile) {
  final evaluated = ProfileEvaluator.evaluate(_green(dish), dish, profile);
  return (
    dish: dish,
    evaluated: evaluated,
    questions: VerdictCopy.waiterQuestions(
      evaluated,
      hebrew: VerdictCopy.dishIsHebrew(dish),
    ),
  );
}

/// The eggplant salad: sesame suspected, so "ask".
final Dish _eggplant = _dish('eggplant', 'סלט חצילים');

/// The tahini salad: sesame stated in the name, so "avoid".
final Dish _tahini = _dish('tahini', 'סלט עם טחינה');

/// "safe" as a word in English, "בטוח" anywhere in Hebrew.
final RegExp _safe = RegExp('(?<![A-Za-z])safe|בטוח', caseSensitive: false);

void main() {
  group('OrderCardText.compose', () {
    test('a Hebrew menu: one section per dish in the order added, each in '
        'Hebrew, and the allergy note once at the end', () {
      // Arrange
      final dishes = <OrderDish>[
        _item(_tahini, _sesame),
        _item(_eggplant, _sesame),
      ];

      // Act
      final card = OrderCardText.compose(
        dishes,
        profile: _sesame,
        hebrew: true,
      );

      // Assert
      expect(card.sections.map((s) => s.dishId), <String>[
        'tahini',
        'eggplant',
      ]);
      expect(card.sections.map((s) => s.name), <String>[
        'סלט עם טחינה',
        'סלט חצילים',
      ]);
      expect(card.sections.every((s) => s.hebrew), isTrue);
      expect(card.sections[1].lines, <String>[
        "בתפריט כתוב 'סלט חצילים' — האם יש בזה שומשום?",
      ]);
      expect(card.allergyNote, ChefCardText.allergyNote(_sesame, hebrew: true));
      expect(card.allergyNote, startsWith('יש לי אלרגיה לשומשום.'));
    });

    test('an avoided dish can be ordered: it says plainly what the menu '
        'names in it, then asks', () {
      // Act
      final lines = OrderCardText.sectionLines(_item(_tahini, _sesame));

      // Assert
      expect(lines, <String>[
        "התפריט מציין 'טחינה' במנה הזו.",
        'אפשר להכין את המנה בלי שומשום?',
      ]);
    });

    test('an English avoided dish names the menu words in English', () {
      // Act
      final lines = OrderCardText.sectionLines(
        _item(_dish('t', 'Tahini salad'), _sesame),
      );

      // Assert
      expect(lines, <String>[
        "The menu names 'Tahini' in this dish.",
        'Can this be made without sesame?',
      ]);
    });

    test('an English menu: the change sentence quotes the menu, and the '
        'allergy note is English', () {
      // Arrange
      final burger = _dish(
        'burger',
        'Burger',
        options: const <DishOption>[
          DishOption(name: 'Toppings', values: <String>['sour cream']),
        ],
      );

      // Act
      final card = OrderCardText.compose(
        <OrderDish>[_item(burger, _milk)],
        profile: _milk,
        hebrew: false,
      );

      // Assert
      expect(card.sections.single.hebrew, isFalse);
      expect(card.sections.single.lines, <String>[
        "Ask for it without 'cream'",
      ]);
      expect(card.allergyNote, startsWith('I have an allergy to milk.'));
    });

    test('a dish with nothing found has its name and no line', () {
      // Act
      final card = OrderCardText.compose(
        <OrderDish>[_item(_dish('g', 'Green salad'), _sesame)],
        profile: _sesame,
        hebrew: false,
      );

      // Assert
      expect(card.sections.single.name, 'Green salad');
      expect(card.sections.single.lines, isEmpty);
    });

    test('a profile with nothing but keto carries no allergy note', () {
      // Act
      final card = OrderCardText.compose(
        <OrderDish>[_item(_dish('g', 'Green salad'), DietaryProfile.empty)],
        profile: DietaryProfile.empty,
        hebrew: false,
      );

      // Assert
      expect(card.allergyNote, isNull);
    });

    test('group mode: each dish reads the combined evaluation, and the '
        "union's allergy note comes once, not once per person", () {
      // Arrange: me with sesame, Dana with milk.
      final group = <NamedProfile>[
        NamedProfile(id: NamedProfile.primaryId, name: '', profile: _sesame),
        NamedProfile(id: 'p1', name: 'Dana', profile: _milk),
      ];
      final union = GroupEvaluator.union(<DietaryProfile>[_sesame, _milk]);
      final dish = _dish('sabich', 'Sabich with tahini and cheese');
      final combined = GroupEvaluator.evaluate(
        _green(dish),
        dish,
        group,
      ).combined;

      // Act
      final card = OrderCardText.compose(
        <OrderDish>[
          (
            dish: dish,
            evaluated: combined,
            questions: VerdictCopy.waiterQuestions(combined, hebrew: false),
          ),
        ],
        profile: union,
        hebrew: false,
      );
      final text = OrderCardText.asText(card);

      // Assert: both people's findings on the one dish, and one note
      // naming both restrictions.
      final lines = card.sections.single.lines.join('\n');
      expect(lines, contains('sesame'));
      expect(lines, contains('milk'));
      expect(card.allergyNote, contains('sesame'));
      expect(card.allergyNote, contains('milk'));
      expect('I have an allergy'.allMatches(text), hasLength(1));
    });
  });

  group('OrderCardText.namesLine', () {
    test('quotes the menu words when short enough, else names the '
        'restriction as the thing avoided', () {
      // Arrange
      const short = Concern(
        restrictionId: RestrictionId.sesame,
        source: ConcernSource.name,
        certainty: Certainty.stated,
        tier: EvidenceTier.stated,
        matchedText: 'tahini',
      );
      final long = Concern(
        restrictionId: RestrictionId.sesame,
        source: ConcernSource.description,
        certainty: Certainty.likely,
        tier: EvidenceTier.inferred,
        matchedText: 'x' * 41,
      );

      // Act / Assert
      expect(
        OrderCardText.namesLine(short, hebrew: false),
        "The menu names 'tahini' in this dish.",
      );
      expect(
        OrderCardText.namesLine(long, hebrew: false),
        'The menu names sesame in this dish.',
      );
      expect(
        OrderCardText.namesLine(long, hebrew: true),
        'התפריט מציין שומשום במנה הזו.',
      );
    });
  });

  group('OrderCardText.asText', () {
    test('each dish name then its lines, a blank line between dishes, then '
        'the allergy note', () {
      // Arrange
      final card = OrderCardText.compose(
        <OrderDish>[_item(_tahini, _sesame), _item(_eggplant, _sesame)],
        profile: _sesame,
        hebrew: true,
      );

      // Act
      final text = OrderCardText.asText(card);

      // Assert
      expect(
        text,
        'סלט עם טחינה\n'
        "התפריט מציין 'טחינה' במנה הזו.\n"
        'אפשר להכין את המנה בלי שומשום?\n'
        '\n'
        'סלט חצילים\n'
        "בתפריט כתוב 'סלט חצילים' — האם יש בזה שומשום?\n"
        '\n'
        '${card.allergyNote}',
      );
    });

    test('never says "safe" in either language', () {
      // Arrange
      final cards = <OrderCard>[
        for (final hebrew in <bool>[true, false])
          OrderCardText.compose(
            <OrderDish>[
              _item(_tahini, _sesame),
              _item(_eggplant, _sesame),
              _item(_dish('t', 'Tahini salad'), _sesame),
              _item(_dish('g', 'Green salad'), _sesame),
            ],
            profile: _sesame,
            hebrew: hebrew,
          ),
      ];

      // Act / Assert
      for (final card in cards) {
        final text = OrderCardText.asText(card);
        expect(text, isNot(matches(_safe)), reason: text);
      }
    });
  });

  group('the recorded Hebrew Wolt menu', () {
    test('a burger and fries ordered under a sesame profile: two Hebrew '
        'sections, the burger asking about the bun, one allergy note', () {
      // Arrange: the real recording (test/fixtures/README.md).
      final json = jsonDecode(
        File('test/fixtures/wolt_hamosad_menu.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final menu = (WoltMenuMapper.toMenu(
        json,
        ref: const VenueRef(source: MenuSource.wolt, platformId: 'hamosad'),
        fetchedAt: DateTime.utc(2026),
      ) as MenuFetched).menu;
      Dish byId(String id) => menu.allDishes.firstWhere((d) => d.id == id);
      final trump = byId('61ecfdac853cef6ba4d5e3ee');
      final fries = byId('61ecfdac853cef6ba4d5e3f6');

      // Act
      final card = OrderCardText.compose(
        <OrderDish>[_item(trump, _sesame), _item(fries, _sesame)],
        profile: _sesame,
        hebrew: true,
      );
      final text = OrderCardText.asText(card);

      // Assert
      expect(card.sections.map((s) => s.name), <String>[
        'המבורגר טראמפ',
        "צ'יפס",
      ]);
      expect(card.sections.first.lines, <String>[
        "בתפריט כתוב 'בלחמנייה' — האם יש בזה שומשום?",
      ]);
      expect(card.sections.last.lines, isEmpty);
      expect('יש לי אלרגיה לשומשום'.allMatches(text), hasLength(1));
    });
  });
}
