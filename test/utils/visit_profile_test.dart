// The pure helpers behind the Recent tab's per-profile row and "Worked for
// me" mark (Banto, issues #411 and #412).
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/visit_profile.dart';

const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v');

Concern _concern(
  RestrictionId id, {
  ConcernSource source = ConcernSource.name,
  String? text,
}) => Concern(
  restrictionId: id,
  source: source,
  certainty: Certainty.stated,
  tier: EvidenceTier.stated,
  matchedText: text,
);

EvaluatedDish _evaluated(
  String id,
  List<Concern> concerns, {
  String? modification,
}) => EvaluatedDish(
  dish: AnalysedDish(
    dishId: id,
    name: id,
    verdict: DishVerdict.orderAsIs,
    why: '',
  ),
  concerns: concerns,
  state: DishState.ask,
  modification: modification,
);

void main() {
  group('profileFingerprintOf', () {
    test('is eight hex digits and ignores the order entries were added', () {
      // Arrange
      final a = DietaryProfile.empty
          .withEntry(RestrictionId.sesame)
          .withEntry(RestrictionId.peanuts);
      final b = DietaryProfile.empty
          .withEntry(RestrictionId.peanuts)
          .withEntry(RestrictionId.sesame);

      // Act & Assert
      expect(profileFingerprintOf(a), matches(RegExp(r'^[0-9a-f]{8}$')));
      expect(profileFingerprintOf(a), profileFingerprintOf(b));
    });

    test('differs when a restriction is added or swapped', () {
      // Arrange
      final sesame = DietaryProfile.empty.withEntry(RestrictionId.sesame);

      // Act & Assert
      expect(
        profileFingerprintOf(sesame),
        isNot(profileFingerprintOf(sesame.withEntry(RestrictionId.peanuts))),
      );
      expect(
        profileFingerprintOf(sesame),
        isNot(
          profileFingerprintOf(
            DietaryProfile.empty.withEntry(RestrictionId.peanuts),
          ),
        ),
      );
    });

    test('is a pure function of the ids: exceptions do not move it', () {
      // Arrange
      final plain = DietaryProfile.empty.withEntry(RestrictionId.lactose);
      final excepting = DietaryProfile.empty.withEntry(
        RestrictionId.lactose,
        exceptions: const <String>['butter'],
      );

      // Act & Assert
      expect(profileFingerprintOf(plain), profileFingerprintOf(excepting));
    });
  });

  group('strictDishesOf', () {
    final menu = Menu(
      venueRef: _ref,
      currency: 'ILS',
      fetchedAt: DateTime.utc(2026),
      categories: const <MenuCategory>[
        MenuCategory(
          id: 'c',
          name: 'C',
          dishes: <Dish>[
            Dish(id: 'a', name: 'A', description: '', price: 1, options: []),
            Dish(id: 'b', name: 'B', description: '', price: 1, options: []),
            Dish(id: 'c', name: 'C', description: '', price: 1, options: []),
            Dish(id: 'd', name: 'D', description: '', price: 1, options: []),
          ],
        ),
      ],
    );

    test('keeps strict concerns found in the dish, in menu order', () {
      // Act
      final dishes = strictDishesOf(menu, <String, EvaluatedDish>{
        'd': _evaluated('d', <Concern>[_concern(RestrictionId.milk)]),
        'a': _evaluated('a', <Concern>[
          _concern(RestrictionId.sesame),
          _concern(RestrictionId.lactose),
          _concern(RestrictionId.sesame),
        ], modification: 'without it'),
      });

      // Assert
      expect(dishes.map((dish) => dish.dishId), <String>['a', 'd']);
      expect(dishes.first.concerns.map((c) => c.restrictionId), <Object>[
        RestrictionId.sesame,
      ]);
      expect(dishes.first.hasChange, isTrue);
      expect(dishes.last.hasChange, isFalse);
    });

    test("leaves out a dish with no strict concern and the kitchen's and "
        "the matrix's concerns", () {
      // Act
      final dishes = strictDishesOf(menu, <String, EvaluatedDish>{
        'a': _evaluated('a', <Concern>[_concern(RestrictionId.lactose)]),
        'b': _evaluated('b', <Concern>[
          _concern(RestrictionId.sesame, source: ConcernSource.kitchen),
          _concern(RestrictionId.peanuts, source: ConcernSource.matrix),
        ]),
        'c': _evaluated('c', const <Concern>[]),
      });

      // Assert
      expect(dishes, isEmpty);
    });

    test("keeps the words of the user's own restriction", () {
      // Act
      final dishes = strictDishesOf(menu, <String, EvaluatedDish>{
        'a': _evaluated('a', <Concern>[
          _concern(RestrictionId.custom, text: 'kiwi'),
        ]),
      });

      // Assert
      expect(dishes.single.concerns.single.matchedText, 'kiwi');
    });
  });

  group('the names a mark is stored under', () {
    test('the unnamed owner is Me, a named one keeps the name', () {
      // Act & Assert
      expect(
        workedForNameOf(const NamedProfile(id: 'me', name: '')),
        workedForSelf,
      );
      expect(workedForNameOf(const NamedProfile(id: 'me', name: 'Noa')), 'Noa');
      expect(
        workedForNameOf(const NamedProfile(id: 'dana', name: 'Dana')),
        'Dana',
      );
    });

    test('markedAmong keeps the marked people the menu is read for', () {
      // Arrange
      const people = <NamedProfile>[
        NamedProfile(id: 'me', name: ''),
        NamedProfile(id: 'dana', name: 'Dana'),
      ];

      // Act & Assert
      expect(
        markedAmong(<String>['Dana', 'Gone', workedForSelf], people),
        <String>['Dana', workedForSelf],
      );
      expect(markedAmong(const <String>[], people), isEmpty);
    });
  });
}
