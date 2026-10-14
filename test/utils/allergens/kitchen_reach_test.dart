// The kitchen's reach and the strict-entry demotion (Banto; ALG-07, issue
// #349): KitchenSignals.scopeOf, KitchenReach and applyKitchenSignals.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/utils/allergens/kitchen_reach.dart';
import 'package:ketoclub/utils/allergens/kitchen_signals.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';

const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

Dish _dish(String id, String name) => Dish(
  id: id,
  name: name,
  description: '',
  price: 10,
  options: const <DishOption>[],
);

/// A menu with one dish in each kitchen's scope, a wok section, a dish no
/// per-dish kind reaches and a drink.
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(
      id: 'mains',
      name: 'Mains',
      dishes: <Dish>[
        _dish('fries', 'French fries'),
        _dish('steak', 'Grilled steak'),
        _dish('salmon', 'Grilled salmon'),
        _dish('salad', 'Green salad'),
        _dish('bread', 'Sourdough bread'),
        _dish('dip', 'Tahini dip'),
        _dish('friedBread', 'Fried bread'),
      ],
    ),
    MenuCategory(
      id: 'asian',
      name: 'Asian kitchen',
      dishes: <Dish>[
        _dish('padThai', 'Pad thai'),
        _dish('greens', 'Steamed greens'),
      ],
    ),
    MenuCategory(
      id: 'dessert',
      name: 'Dessert',
      dishes: <Dish>[_dish('cake', 'Walnut cake')],
    ),
    MenuCategory(
      id: 'drinks',
      name: 'Drinks',
      dishes: <Dish>[_dish('cola', 'Cola')],
    ),
  ],
);

/// A Hebrew menu: fries and a tahini salad.
final Menu _hebrewMenu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'מנות',
      dishes: <Dish>[
        _dish('chips', "צ'יפס"),
        _dish('salad', 'סלט עם טחינה'),
        _dish('steak', 'סטייק'),
      ],
    ),
  ],
);

final KitchenReach _reach = KitchenReach.of(_menu);

Dish _byId(Menu menu, String id) =>
    menu.allDishes.firstWhere((dish) => dish.id == id);

/// [dishId] evaluated as [state] with [concerns].
EvaluatedDish _evaluated(
  String dishId, {
  DishState state = DishState.fits,
  List<Concern> concerns = const <Concern>[],
  String? modification,
}) => EvaluatedDish(
  dish: AnalysedDish(
    dishId: dishId,
    name: dishId,
    verdict: DishVerdict.orderAsIs,
    why: 'why',
  ),
  concerns: concerns,
  state: state,
  modification: modification,
);

DietaryProfile _profile(List<RestrictionId> ids) =>
    <RestrictionId>[...ids]
        .fold(DietaryProfile.empty, (profile, id) => profile.withEntry(id));

/// The kitchen concern [applyKitchenSignals] adds for [id] through [kind].
Concern _kitchen(RestrictionId id, KitchenSignalKind kind, String question) =>
    Concern(
      restrictionId: id,
      source: ConcernSource.kitchen,
      certainty: Certainty.suspected,
      tier: EvidenceTier.inferred,
      matchedText: kind.name,
      waiterQuestion: question,
    );

String _questionEn(KitchenSignalKind kind) =>
    _reach.signals.firstWhere((signal) => signal.kind == kind).questionEn;

void main() {
  group('KitchenSignals.scopeOf', () {
    test('the menu shows every kind', () {
      // Act
      final kinds = KitchenSignals.of(_menu).map((signal) => signal.kind);

      // Assert
      expect(kinds, KitchenSignalKind.values);
    });

    final all = <String>{for (final dish in _menu.allDishes) dish.id};
    for (final (kind, expected) in <(KitchenSignalKind, Set<String>)>[
      (KitchenSignalKind.fryer, {'fries', 'friedBread'}),
      (KitchenSignalKind.wok, {'padThai', 'greens'}),
      (KitchenSignalKind.sharedGrill, {'steak', 'salmon'}),
      (KitchenSignalKind.bakery, {'bread', 'friedBread', 'cake'}),
      (KitchenSignalKind.nuts, all),
      (KitchenSignalKind.sesame, all),
    ]) {
      test('${kind.name} reaches $expected', () {
        // Act
        final scope = KitchenSignals.scopeOf(_menu);

        // Assert
        expect(scope[kind], expected);
      });
    }

    test('a heading puts every dish of its section in scope', () {
      // Arrange
      final menu = Menu(
        venueRef: _ref,
        currency: 'ILS',
        fetchedAt: DateTime.utc(2026),
        categories: <MenuCategory>[
          MenuCategory(
            id: 'c1',
            name: 'From the grill',
            dishes: <Dish>[_dish('a', 'Entrecote'), _dish('b', 'Sea bass')],
          ),
          MenuCategory(
            id: 'c2',
            name: 'Wok',
            dishes: <Dish>[_dish('c', 'Chicken and vegetables')],
          ),
        ],
      );

      // Act
      final scope = KitchenSignals.scopeOf(menu);

      // Assert
      expect(scope[KitchenSignalKind.sharedGrill], {'a', 'b'});
      expect(scope[KitchenSignalKind.wok], {'c'});
      expect(scope[KitchenSignalKind.fryer], isEmpty);
    });
  });

  group('KitchenReach.of', () {
    test('leaves drinks out of every scope', () {
      // Assert
      for (final kind in KitchenSignalKind.values) {
        expect(_reach.reaches(kind, 'cola'), isFalse, reason: kind.name);
      }
      expect(_reach.reaches(KitchenSignalKind.sesame, 'salad'), isTrue);
    });

    test('reads the menu language', () {
      // Assert
      expect(_reach.hebrew, isFalse);
      expect(KitchenReach.of(_hebrewMenu).hebrew, isTrue);
    });

    test('a menu with no signal is the empty reach', () {
      // Arrange
      final menu = Menu(
        venueRef: _ref,
        currency: 'ILS',
        fetchedAt: DateTime.utc(2026),
        categories: <MenuCategory>[
          MenuCategory(
            id: 'c1',
            name: 'Salads',
            dishes: <Dish>[_dish('a', 'Green salad')],
          ),
        ],
      );

      // Act
      final reach = KitchenReach.of(menu);

      // Assert
      expect(identical(reach, KitchenReach.empty), isTrue);
      expect(reach.strictThreats(_profile([RestrictionId.sesame])), isEmpty);
    });
  });

  group('KitchenReach.strictThreats', () {
    test('lists only signals that threaten a strict entry, in kind order', () {
      // Act
      final threats = _reach.strictThreats(
        _profile([RestrictionId.lactose, RestrictionId.sesame]),
      );

      // Assert: lactose is flexible, so only sesame counts.
      expect(threats.map((threat) => threat.signal.kind), <KitchenSignalKind>[
        KitchenSignalKind.wok,
        KitchenSignalKind.bakery,
        KitchenSignalKind.sesame,
      ]);
      for (final threat in threats) {
        expect(threat.strict, <RestrictionId>[RestrictionId.sesame]);
      }
    });

    test('lists the strict entries in taxonomy order', () {
      // Act
      final threats = _reach.strictThreats(
        _profile([RestrictionId.gluten, RestrictionId.wheat]),
      );

      // Assert
      expect(threats.first.signal.kind, KitchenSignalKind.fryer);
      expect(threats.first.strict, <RestrictionId>[
        RestrictionId.wheat,
        RestrictionId.gluten,
      ]);
    });

    for (final (label, profile) in <(String, DietaryProfile)>[
      ('an empty (keto-only) profile', DietaryProfile.empty),
      ('a keto entry', _profile([RestrictionId.keto])),
      ('flexible entries only', _profile([RestrictionId.lactose])),
      ('a diet', _profile([RestrictionId.vegan, RestrictionId.vegetarian])),
    ]) {
      test('is empty for $label', () {
        // Assert
        expect(_reach.strictThreats(profile), isEmpty);
      });
    }
  });

  group('applyKitchenSignals', () {
    // (case, profile, dish, expected state, expected added concerns)
    final cases =
        <(String, List<RestrictionId>, String, DishState, List<Concern>)>[
          (
            'celiac: fries share the fryer',
            [RestrictionId.gluten],
            'fries',
            DishState.ask,
            [
              _kitchen(
                RestrictionId.gluten,
                KitchenSignalKind.fryer,
                _questionEn(KitchenSignalKind.fryer),
              ),
            ],
          ),
          (
            'celiac: a salad no flour-handling kind reaches',
            [RestrictionId.gluten],
            'salad',
            DishState.fits,
            [],
          ),
          (
            'celiac: a dish in the wok section',
            [RestrictionId.gluten],
            'greens',
            DishState.ask,
            [
              _kitchen(
                RestrictionId.gluten,
                KitchenSignalKind.wok,
                _questionEn(KitchenSignalKind.wok),
              ),
            ],
          ),
          (
            'celiac: fried bread takes the fryer, first in kind order',
            [RestrictionId.gluten],
            'friedBread',
            DishState.ask,
            [
              _kitchen(
                RestrictionId.gluten,
                KitchenSignalKind.fryer,
                _questionEn(KitchenSignalKind.fryer),
              ),
            ],
          ),
          (
            'fish: a steak on the shared grill',
            [RestrictionId.fish],
            'steak',
            DishState.ask,
            [
              _kitchen(
                RestrictionId.fish,
                KitchenSignalKind.sharedGrill,
                _questionEn(KitchenSignalKind.sharedGrill),
              ),
            ],
          ),
          (
            'sesame: the whole menu',
            [RestrictionId.sesame],
            'salad',
            DishState.ask,
            [
              _kitchen(
                RestrictionId.sesame,
                KitchenSignalKind.sesame,
                _questionEn(KitchenSignalKind.sesame),
              ),
            ],
          ),
          (
            'peanuts: the whole menu',
            [RestrictionId.peanuts],
            'fries',
            DishState.ask,
            [
              _kitchen(
                RestrictionId.peanuts,
                KitchenSignalKind.nuts,
                _questionEn(KitchenSignalKind.nuts),
              ),
            ],
          ),
          (
            'sesame: never a drink',
            [RestrictionId.sesame],
            'cola',
            DishState.fits,
            [],
          ),
          (
            'milk allergy: bread from the bakery',
            [RestrictionId.milk],
            'bread',
            DishState.ask,
            [
              _kitchen(
                RestrictionId.milk,
                KitchenSignalKind.bakery,
                _questionEn(KitchenSignalKind.bakery),
              ),
            ],
          ),
          (
            'lactose (flexible): bread is untouched',
            [RestrictionId.lactose],
            'bread',
            DishState.fits,
            [],
          ),
          ('keto-only: fries are untouched', [], 'fries', DishState.fits, []),
          (
            'keto and celiac: fries share the fryer',
            [RestrictionId.keto, RestrictionId.gluten],
            'fries',
            DishState.ask,
            [
              _kitchen(
                RestrictionId.gluten,
                KitchenSignalKind.fryer,
                _questionEn(KitchenSignalKind.fryer),
              ),
            ],
          ),
          (
            'celiac and wheat: one concern each, in taxonomy order',
            [RestrictionId.gluten, RestrictionId.wheat],
            'fries',
            DishState.ask,
            [
              _kitchen(
                RestrictionId.wheat,
                KitchenSignalKind.fryer,
                _questionEn(KitchenSignalKind.fryer),
              ),
              _kitchen(
                RestrictionId.gluten,
                KitchenSignalKind.fryer,
                _questionEn(KitchenSignalKind.fryer),
              ),
            ],
          ),
        ];
    for (final (label, ids, dishId, state, added) in cases) {
      test(label, () {
        // Arrange
        final evaluated = _evaluated(dishId);

        // Act
        final result = applyKitchenSignals(
          evaluated,
          _byId(_menu, dishId),
          _profile(ids),
          _reach,
        );

        // Assert
        expect(result.state, state);
        expect(result.concerns, added);
        expect(result.dish, evaluated.dish);
        expect(result.modification, isNull);
      });
    }

    for (final state in <DishState>[
      DishState.fitsWithChange,
      DishState.ask,
      DishState.avoid,
    ]) {
      test('leaves a dish in state ${state.name} as it is', () {
        // Arrange
        final evaluated = _evaluated(
          'fries',
          state: state,
          modification: state == DishState.fitsWithChange
              ? "Ask for it without 'ketchup'"
              : null,
        );

        // Act
        final result = applyKitchenSignals(
          evaluated,
          _byId(_menu, 'fries'),
          _profile([RestrictionId.gluten]),
          _reach,
        );

        // Assert
        expect(identical(result, evaluated), isTrue);
      });
    }

    test('keeps a flexible concern and sorts the kitchen one in', () {
      // Arrange
      const lactose = Concern(
        restrictionId: RestrictionId.lactose,
        source: ConcernSource.description,
        certainty: Certainty.suspected,
        tier: EvidenceTier.suspected,
      );
      final evaluated = _evaluated('bread', concerns: const [lactose]);

      // Act
      final result = applyKitchenSignals(
        evaluated,
        _byId(_menu, 'bread'),
        _profile([RestrictionId.lactose, RestrictionId.sesame]),
        _reach,
      );

      // Assert: lactose (index 3) before sesame.
      expect(result.state, DishState.ask);
      expect(result.concerns.map((concern) => concern.restrictionId), [
        RestrictionId.lactose,
        RestrictionId.sesame,
      ]);
      expect(result.concerns.last.source, ConcernSource.kitchen);
    });

    test('never repeats a restriction the dish already has a concern for', () {
      // Arrange
      const held = Concern(
        restrictionId: RestrictionId.gluten,
        source: ConcernSource.option,
        certainty: Certainty.likely,
        tier: EvidenceTier.stated,
      );
      final evaluated = _evaluated('fries', concerns: const [held]);

      // Act
      final result = applyKitchenSignals(
        evaluated,
        _byId(_menu, 'fries'),
        _profile([RestrictionId.gluten]),
        _reach,
      );

      // Assert
      expect(result.state, DishState.ask);
      expect(result.concerns, const [held]);
    });

    test('asks in the dish language', () {
      // Arrange
      final reach = KitchenReach.of(_hebrewMenu);
      final question = reach.signals
          .firstWhere((signal) => signal.kind == KitchenSignalKind.fryer)
          .questionHe;

      // Act
      final result = applyKitchenSignals(
        _evaluated('chips'),
        _byId(_hebrewMenu, 'chips'),
        _profile([RestrictionId.gluten]),
        reach,
      );

      // Assert
      expect(result.state, DishState.ask);
      expect(result.concerns.single.waiterQuestion, question);
    });

    test('the empty reach changes nothing', () {
      // Arrange
      final evaluated = _evaluated('fries');

      // Act
      final result = applyKitchenSignals(
        evaluated,
        _byId(_menu, 'fries'),
        _profile([RestrictionId.gluten]),
        KitchenReach.empty,
      );

      // Assert
      expect(identical(result, evaluated), isTrue);
    });
  });
}
