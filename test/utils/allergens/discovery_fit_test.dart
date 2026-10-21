import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/utils/allergens/discovery_fit.dart';
import 'package:ketoclub/utils/profile_wording.dart';
import 'package:ketoclub/utils/verdict_counts.dart';

import '../../fakes/fake_clock.dart';

/// A dish priced 50 with [options].
Dish _dish(
  String id,
  String name,
  String description, {
  List<DishOption> options = const <DishOption>[],
}) => Dish(
  id: id,
  name: name,
  description: description,
  price: 50,
  options: options,
);

/// Five mains, one in each state for a sesame allergy, and a drink that
/// counts for nothing (D21).
final Menu _grill = Menu(
  venueRef: const VenueRef(source: MenuSource.wolt, platformId: 'grill'),
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(
      id: 'mains',
      name: 'Mains',
      dishes: <Dish>[
        // Nothing for sesame or lactose.
        _dish('salmon', 'Grilled salmon', 'With a green salad'),
        // Tahini or cream, a removable option: a change for both.
        _dish(
          'chicken',
          'Chicken skewers',
          'With a choice of sauce',
          options: const <DishOption>[
            DishOption(
              name: 'Sauce',
              values: <String>['Tahini', 'Cream sauce'],
            ),
          ],
        ),
        // Falafel is a suspected sesame source: ask.
        _dish('falafel', 'Falafel plate', 'With chopped salad'),
        // Sesame in the dish itself: avoid.
        _dish('steak', 'Steak', 'Sesame crusted'),
        // Cheese: avoid for lactose, nothing for sesame.
        _dish('omelette', 'Cheese omelette', 'Three eggs and cheddar'),
      ],
    ),
    MenuCategory(
      id: 'drinks',
      name: 'Drinks',
      dishes: <Dish>[_dish('lemonade', 'Lemonade', '')],
    ),
  ],
);

/// The rule engine's keto-only analysis of [menu], as the quick score
/// makes it (D21).
Future<MenuAnalysed> _rules(Menu menu) async {
  final result = await HeuristicMenuClassifier(
    clock: FakeClock(DateTime.utc(2026)),
  ).classify(menu);
  return result as MenuAnalysed;
}

/// A person [id], named the same, holding [ids].
NamedProfile _person(String id, List<RestrictionId> ids) {
  var profile = DietaryProfile.empty;
  for (final restriction in ids) {
    profile = profile.withEntry(restriction);
  }
  return NamedProfile(id: id, name: id, profile: profile);
}

void main() {
  late MenuAnalysed analysis;

  setUpAll(() async {
    analysis = await _rules(_grill);
  });

  group('DiscoveryFit.of', () {
    final rows =
        <
          ({
            String label,
            List<NamedProfile> people,
            VerdictCounts counts,
            ProfileWording wording,
          })
        >[
          (
            label: 'a sesame allergy',
            people: <NamedProfile>[
              _person('me', <RestrictionId>[RestrictionId.sesame]),
            ],
            counts: const VerdictCounts(
              green: 2,
              yellow: 1,
              hiddenCarbYellow: 0,
              red: 1,
              ask: 1,
            ),
            wording: ProfileWording.strict,
          ),
          (
            label: 'a lactose intolerance (flexible)',
            people: <NamedProfile>[
              _person('me', <RestrictionId>[RestrictionId.lactose]),
            ],
            counts: const VerdictCounts(
              green: 3,
              yellow: 1,
              hiddenCarbYellow: 0,
              red: 1,
            ),
            wording: ProfileWording.flexible,
          ),
          (
            label: 'sesame and lactose in one profile',
            people: <NamedProfile>[
              _person('me', <RestrictionId>[
                RestrictionId.sesame,
                RestrictionId.lactose,
              ]),
            ],
            counts: const VerdictCounts(
              green: 1,
              yellow: 1,
              hiddenCarbYellow: 0,
              red: 2,
              ask: 1,
            ),
            wording: ProfileWording.strict,
          ),
          (
            label: 'a group: sesame for me, lactose for Dana (fits everyone)',
            people: <NamedProfile>[
              _person('me', <RestrictionId>[RestrictionId.sesame]),
              _person('dana', <RestrictionId>[RestrictionId.lactose]),
            ],
            counts: const VerdictCounts(
              green: 1,
              yellow: 1,
              hiddenCarbYellow: 0,
              red: 2,
              ask: 1,
            ),
            wording: ProfileWording.strict,
          ),
        ];

    for (final row in rows) {
      test('counts food dishes by state for ${row.label}', () {
        // Act
        final fit = DiscoveryFit.of(
          _grill,
          analysis,
          row.people,
          bantoMode: true,
        );

        // Assert
        expect(fit, isNotNull);
        expect(fit!.counts, row.counts);
        expect(fit.wording, row.wording);
      });
    }

    test('a group counts only what fits everyone', () {
      // Arrange
      final me = _person('me', <RestrictionId>[RestrictionId.sesame]);
      final dana = _person('dana', <RestrictionId>[RestrictionId.lactose]);

      // Act
      final mine = DiscoveryFit.of(_grill, analysis, <NamedProfile>[
        me,
      ], bantoMode: true)!;
      final hers = DiscoveryFit.of(_grill, analysis, <NamedProfile>[
        dana,
      ], bantoMode: true)!;
      final ours = DiscoveryFit.of(_grill, analysis, <NamedProfile>[
        me,
        dana,
      ], bantoMode: true)!;

      // Assert: the omelette fits me and the steak fits Dana, but neither
      // fits both of us.
      expect(ours.counts.green, lessThan(mine.counts.green));
      expect(ours.counts.green, lessThan(hers.counts.green));
      expect(ours.counts.green, 1);
    });

    test('never counts the drink, whatever its state', () {
      // Arrange
      final people = <NamedProfile>[
        _person('me', <RestrictionId>[RestrictionId.sesame]),
      ];

      // Act
      final fit = DiscoveryFit.of(_grill, analysis, people, bantoMode: true)!;

      // Assert: five mains placed, the lemonade left out.
      expect(analysis.dishes.map((dish) => dish.dishId), contains('lemonade'));
      expect(fit.counts.total, 5);
    });

    test('is null for an empty (keto-only) profile', () {
      // Act
      final fit = DiscoveryFit.of(_grill, analysis, const <NamedProfile>[
        NamedProfile(id: NamedProfile.primaryId, name: ''),
      ], bantoMode: true);

      // Assert
      expect(fit, isNull);
    });

    test('is null for a profile holding keto alone', () {
      // Act
      final fit = DiscoveryFit.of(_grill, analysis, <NamedProfile>[
        _person('me', <RestrictionId>[RestrictionId.keto]),
      ], bantoMode: true);

      // Assert
      expect(fit, isNull);
    });

    test('is null with bantoMode off, whatever the profile', () {
      // Act
      final fit = DiscoveryFit.of(
        _grill,
        analysis,
        <NamedProfile>[
          _person('me', <RestrictionId>[RestrictionId.sesame]),
        ],
        // An explicit false, whatever the define.
        // ignore: avoid_redundant_argument_values
        bantoMode: false,
      );

      // Assert
      expect(fit, isNull);
    });

    test('is null with no people', () {
      // Act
      final fit = DiscoveryFit.of(
        _grill,
        analysis,
        const <NamedProfile>[],
        bantoMode: true,
      );

      // Assert
      expect(fit, isNull);
    });

    test('is null when no food dish was placed', () {
      // Arrange
      final empty = MenuAnalysed(
        dishes: const <AnalysedDish>[],
        unclassified: const <String>['salmon'],
        engine: analysis.engine,
        analysedAt: analysis.analysedAt,
      );

      // Act
      final fit = DiscoveryFit.of(_grill, empty, <NamedProfile>[
        _person('me', <RestrictionId>[RestrictionId.sesame]),
      ], bantoMode: true);

      // Assert
      expect(fit, isNull);
    });
  });

  group('DiscoveryFit.hasFittingDish', () {
    VerdictCounts counts({int green = 0, int yellow = 0, int ask = 0}) =>
        VerdictCounts(
          green: green,
          yellow: yellow,
          hiddenCarbYellow: 0,
          red: 1,
          ask: ask,
        );

    test('holds for a dish that fits as it is', () {
      expect(
        DiscoveryFit(
          counts: counts(green: 1),
          wording: ProfileWording.strict,
        ).hasFittingDish,
        isTrue,
      );
    });

    test('holds for a dish that fits with a change', () {
      expect(
        DiscoveryFit(
          counts: counts(yellow: 1),
          wording: ProfileWording.strict,
        ).hasFittingDish,
        isTrue,
      );
    });

    test('does not hold for dishes only to ask about or avoid', () {
      expect(
        DiscoveryFit(
          counts: counts(ask: 2),
          wording: ProfileWording.strict,
        ).hasFittingDish,
        isFalse,
      );
    });
  });

  group('DiscoveryFit.wordingFor', () {
    test('words a group by the union of its profiles', () {
      // Act
      final wording = DiscoveryFit.wordingFor(<NamedProfile>[
        _person('me', <RestrictionId>[RestrictionId.lactose]),
        _person('dana', <RestrictionId>[RestrictionId.sesame]),
      ], bantoMode: true);

      // Assert: Dana's allergy makes the group strict.
      expect(wording, ProfileWording.strict);
    });

    test('is keto-only with bantoMode off', () {
      // Act
      final wording = DiscoveryFit.wordingFor(
        <NamedProfile>[
          _person('me', <RestrictionId>[RestrictionId.sesame]),
        ],
        // An explicit false, whatever the define.
        // ignore: avoid_redundant_argument_values
        bantoMode: false,
      );

      // Assert
      expect(wording, ProfileWording.ketoOnly);
    });
  });

  group('equality', () {
    test('two fits with the same counts and wording are equal', () {
      // Arrange
      const counts = VerdictCounts(
        green: 1,
        yellow: 0,
        hiddenCarbYellow: 0,
        red: 0,
      );
      const a = DiscoveryFit(counts: counts, wording: ProfileWording.flexible);
      const b = DiscoveryFit(counts: counts, wording: ProfileWording.flexible);

      // Assert
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), contains('flexible'));
    });
  });
}
