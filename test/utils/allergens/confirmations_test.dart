// Staff confirmations as evidence (Banto, ALG-14, issue #356;
// architecture.md D27): the tier effects through ProfileEvaluator,
// including "a denial never goes below suspected for a strict entry", and
// the shape that will later read shared counts.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/dish_confirmation.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/confirmations.dart';
import 'package:ketoclub/utils/allergens/group_evaluator.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';

/// A dish named [name] with [description].
Dish _dish(String name, {String description = ''}) => Dish(
  id: 'd',
  name: name,
  description: description,
  price: 10,
  options: const <DishOption>[],
);

/// A green analysis of [name] carrying [ingredients].
AnalysedDish _green(
  String name, {
  List<ExtractedIngredient> ingredients = const <ExtractedIngredient>[],
}) => AnalysedDish(
  dishId: 'd',
  name: name,
  verdict: DishVerdict.orderAsIs,
  why: 'Fits',
  ingredients: ingredients,
);

/// A profile holding [ids].
DietaryProfile _profile(List<RestrictionId> ids) {
  var profile = DietaryProfile.empty;
  for (final id in ids) {
    profile = profile.withEntry(id);
  }
  return profile;
}

/// The person's own answer about [id].
ConfirmationEvidence _own(
  RestrictionId id,
  ConfirmationPolarity polarity, {
  DateTime? day,
  ConcernSource? source,
  String? matchedText,
}) => ConfirmationEvidence(
  restrictionId: id,
  polarity: polarity,
  day: day ?? DateTime(2026, 5, 12),
  source: source,
  matchedText: matchedText,
);

/// A shared count about [id].
ConfirmationEvidence _shared(
  RestrictionId id,
  ConfirmationPolarity polarity, {
  required int count,
  DateTime? day,
}) => ConfirmationEvidence(
  restrictionId: id,
  polarity: polarity,
  day: day ?? DateTime(2026, 5, 12),
  shared: true,
  count: count,
  source: ConcernSource.name,
);

/// The evaluation's one concern about [id].
Concern _concern(EvaluatedDish evaluated, RestrictionId id) =>
    evaluated.concerns.singleWhere((concern) => concern.restrictionId == id);

/// A dish whose sesame is only suspected: a model ingredient guessed at
/// a typical recipe.
final Dish _plate = _dish('Plate');
final AnalysedDish _plateWithGuess = _green(
  'Plate',
  ingredients: const <ExtractedIngredient>[
    ExtractedIngredient(
      name: 'tahini',
      certainty: Certainty.suspected,
      role: ComponentRole.sauce,
    ),
  ],
);

void main() {
  final sesame = _profile(<RestrictionId>[RestrictionId.sesame]);

  group('a confirmed present raises the concern', () {
    test('suspected → stated at tier confirmed, and the dish is avoid', () {
      // Arrange
      final dish = _dish('Eggplant salad', description: 'with tahini');
      final before = ProfileEvaluator.evaluate(_green(dish.name), dish, sesame);

      // Act
      final after = ProfileEvaluator.evaluate(
        _green(dish.name),
        dish,
        sesame,
        confirmations: <ConfirmationEvidence>[
          _own(RestrictionId.sesame, ConfirmationPolarity.present),
        ],
      );

      // Assert
      expect(before.state, DishState.avoid);
      final concern = _concern(after, RestrictionId.sesame);
      expect(concern.tier, EvidenceTier.confirmed);
      expect(concern.certainty, Certainty.stated);
      expect(after.state, DishState.avoid);
      expect(after.confirmations, hasLength(1));
    });

    test('a suspected sauce becomes a change to ask for', () {
      // Act
      final after = ProfileEvaluator.evaluate(
        _plateWithGuess,
        _plate,
        sesame,
        confirmations: <ConfirmationEvidence>[
          _own(RestrictionId.sesame, ConfirmationPolarity.present),
        ],
      );

      // Assert: the sauce is removable, so it is left off.
      expect(
        _concern(after, RestrictionId.sesame).tier,
        EvidenceTier.confirmed,
      );
      expect(after.state, DishState.fitsWithChange);
      expect(after.modification, contains('tahini'));
    });

    test('is added where it was found when the menu no longer says it', () {
      // Act
      final after = ProfileEvaluator.evaluate(
        _green('Plate'),
        _plate,
        sesame,
        confirmations: <ConfirmationEvidence>[
          _own(
            RestrictionId.sesame,
            ConfirmationPolarity.present,
            source: ConcernSource.description,
            matchedText: 'tahini',
          ),
        ],
      );

      // Assert
      final concern = _concern(after, RestrictionId.sesame);
      expect(concern.source, ConcernSource.description);
      expect(concern.tier, EvidenceTier.confirmed);
      expect(after.state, DishState.avoid);
    });

    test('is not added for a restriction the profile does not hold', () {
      // Act
      final after = ProfileEvaluator.evaluate(
        _green('Plate'),
        _plate,
        sesame,
        confirmations: <ConfirmationEvidence>[
          _own(
            RestrictionId.peanuts,
            ConfirmationPolarity.present,
            source: ConcernSource.name,
          ),
        ],
      );

      // Assert
      expect(after.concerns, isEmpty);
      expect(after.confirmations, isEmpty);
      expect(after.state, DishState.fits);
    });

    test('is not added when it does not know where it was found', () {
      // Act
      final after = ProfileEvaluator.evaluate(
        _green('Plate'),
        _plate,
        sesame,
        confirmations: <ConfirmationEvidence>[
          _own(RestrictionId.sesame, ConfirmationPolarity.present),
        ],
      );

      // Assert
      expect(after.concerns, isEmpty);
    });

    test("leaves a heads-up restriction's certainty suspected", () {
      // Arrange
      final fodmap = _profile(<RestrictionId>[RestrictionId.fodmap]);
      final dish = _dish('Onion soup', description: 'with garlic and onion');

      // Act
      final after = ProfileEvaluator.evaluate(
        _green(dish.name),
        dish,
        fodmap,
        confirmations: <ConfirmationEvidence>[
          _own(RestrictionId.fodmap, ConfirmationPolarity.present),
        ],
      );

      // Assert
      final concern = _concern(after, RestrictionId.fodmap);
      expect(concern.tier, EvidenceTier.confirmed);
      expect(concern.certainty, Certainty.suspected);
      expect(after.state, isNot(DishState.avoid));
    });
  });

  group('a confirmed absent lowers the concern, never below suspected', () {
    test('a strict entry stated in the name stays to ask about', () {
      // Arrange
      final dish = _dish('Tahini salad');

      // Act
      final after = ProfileEvaluator.evaluate(
        _green(dish.name),
        dish,
        sesame,
        confirmations: <ConfirmationEvidence>[
          _own(RestrictionId.sesame, ConfirmationPolarity.absent),
        ],
      );

      // Assert: lowered from avoid, but never to "fits" for an allergen.
      final concern = _concern(after, RestrictionId.sesame);
      expect(concern.tier, EvidenceTier.denied);
      expect(concern.certainty, Certainty.suspected);
      expect(after.state, DishState.ask);
    });

    test('a strict entry already suspected stays suspected', () {
      // Act
      final after = ProfileEvaluator.evaluate(
        _plateWithGuess,
        _plate,
        sesame,
        confirmations: <ConfirmationEvidence>[
          _own(RestrictionId.sesame, ConfirmationPolarity.absent),
        ],
      );

      // Assert
      expect(
        _concern(after, RestrictionId.sesame).certainty,
        Certainty.suspected,
      );
      expect(after.state, DishState.ask);
    });

    test('celiac stays to ask about too', () {
      // Arrange
      final celiac = _profile(<RestrictionId>[RestrictionId.gluten]);
      final dish = _dish('Schnitzel', description: 'breaded chicken');

      // Act
      final after = ProfileEvaluator.evaluate(
        _green(dish.name),
        dish,
        celiac,
        confirmations: <ConfirmationEvidence>[
          _own(RestrictionId.gluten, ConfirmationPolarity.absent),
        ],
      );

      // Assert
      expect(after.state, DishState.ask);
      expect(_concern(after, RestrictionId.gluten).tier, EvidenceTier.denied);
    });

    test('a flexible entry is kept, listed, and moves nothing', () {
      // Arrange
      final lactose = _profile(<RestrictionId>[RestrictionId.lactose]);
      final dish = _dish('Cheese plate', description: 'with cream');

      // Act
      final after = ProfileEvaluator.evaluate(
        _green(dish.name),
        dish,
        lactose,
        confirmations: <ConfirmationEvidence>[
          _own(RestrictionId.lactose, ConfirmationPolarity.absent),
        ],
      );

      // Assert
      final concern = _concern(after, RestrictionId.lactose);
      expect(concern.certainty, Certainty.suspected);
      expect(concern.tier, EvidenceTier.denied);
      expect(after.state, DishState.fits);
    });
  });

  group('which answer decides', () {
    test("the person's latest answer wins", () {
      // Arrange
      final dish = _dish('Tahini salad');

      // Act
      final after = ProfileEvaluator.evaluate(
        _green(dish.name),
        dish,
        sesame,
        confirmations: <ConfirmationEvidence>[
          _own(
            RestrictionId.sesame,
            ConfirmationPolarity.present,
            day: DateTime(2026, 5),
          ),
          _own(
            RestrictionId.sesame,
            ConfirmationPolarity.absent,
            day: DateTime(2026, 6),
          ),
        ],
      );

      // Assert
      expect(_concern(after, RestrictionId.sesame).tier, EvidenceTier.denied);
      expect(after.confirmations.single.day, DateTime(2026, 6));
    });

    test('on one day, present outranks absent', () {
      // Arrange
      const concern = Concern(
        restrictionId: RestrictionId.sesame,
        source: ConcernSource.name,
        certainty: Certainty.stated,
        tier: EvidenceTier.stated,
      );

      // Act
      final piece = Confirmations.deciding(concern, <ConfirmationEvidence>[
        _own(RestrictionId.sesame, ConfirmationPolarity.absent),
        _own(RestrictionId.sesame, ConfirmationPolarity.present),
      ]);

      // Assert
      expect(piece?.polarity, ConfirmationPolarity.present);
    });

    test('a shared count under the threshold is no evidence', () {
      // Arrange
      final dish = _dish('Tahini salad');

      // Act
      final after = ProfileEvaluator.evaluate(
        _green(dish.name),
        dish,
        sesame,
        confirmations: <ConfirmationEvidence>[
          _shared(
            RestrictionId.sesame,
            ConfirmationPolarity.absent,
            count: sharedConfirmationThreshold - 1,
          ),
        ],
      );

      // Assert
      expect(_concern(after, RestrictionId.sesame).tier, EvidenceTier.stated);
      expect(after.state, DishState.avoid);
    });

    test('a shared denial lowers one step, never below suspected', () {
      // Arrange
      const concern = Concern(
        restrictionId: RestrictionId.sesame,
        source: ConcernSource.name,
        certainty: Certainty.stated,
        tier: EvidenceTier.stated,
      );
      final denial = _shared(
        RestrictionId.sesame,
        ConfirmationPolarity.absent,
        count: sharedConfirmationThreshold,
      );

      // Act
      final once = Confirmations.adjust(concern, denial);
      final twice = Confirmations.adjust(once, denial);
      final thrice = Confirmations.adjust(twice, denial);

      // Assert
      expect(once.certainty, Certainty.likely);
      expect(twice.certainty, Certainty.suspected);
      expect(thrice.certainty, Certainty.suspected);
      expect(thrice.tier, EvidenceTier.denied);
    });

    test("the person's own answer outranks a shared count", () {
      // Arrange
      const concern = Concern(
        restrictionId: RestrictionId.sesame,
        source: ConcernSource.name,
        certainty: Certainty.stated,
        tier: EvidenceTier.stated,
      );

      // Act
      final piece = Confirmations.deciding(concern, <ConfirmationEvidence>[
        _shared(RestrictionId.sesame, ConfirmationPolarity.absent, count: 9),
        _own(
          RestrictionId.sesame,
          ConfirmationPolarity.present,
          day: DateTime(2020),
        ),
      ]);

      // Assert
      expect(piece?.shared, isFalse);
    });

    test('among shared counts, present outranks absent', () {
      // Arrange
      const concern = Concern(
        restrictionId: RestrictionId.sesame,
        source: ConcernSource.name,
        certainty: Certainty.stated,
        tier: EvidenceTier.stated,
      );

      // Act
      final piece = Confirmations.deciding(concern, <ConfirmationEvidence>[
        _shared(
          RestrictionId.sesame,
          ConfirmationPolarity.absent,
          count: 5,
          day: DateTime(2026, 7),
        ),
        _shared(
          RestrictionId.sesame,
          ConfirmationPolarity.absent,
          count: 4,
          day: DateTime(2026, 8),
        ),
        _shared(RestrictionId.sesame, ConfirmationPolarity.present, count: 3),
        _shared(
          RestrictionId.sesame,
          ConfirmationPolarity.present,
          count: 3,
          day: DateTime(2026, 6),
        ),
      ]);

      // Assert
      expect(piece?.polarity, ConfirmationPolarity.present);
      expect(piece?.day, DateTime(2026, 6));
      expect(piece.toString(), contains('shared'));
    });

    test("the user's own words are answered per word", () {
      // Arrange
      const kiwi = Concern(
        restrictionId: RestrictionId.custom,
        source: ConcernSource.description,
        certainty: Certainty.stated,
        tier: EvidenceTier.stated,
        matchedText: 'kiwi',
      );

      // Act
      final piece = Confirmations.deciding(kiwi, <ConfirmationEvidence>[
        _own(
          RestrictionId.custom,
          ConfirmationPolarity.absent,
          matchedText: 'coriander',
        ),
      ]);

      // Assert
      expect(piece, isNull);
    });
  });

  test('forDish keeps only the dish and reads each answer as its own', () {
    // Arrange
    final stored = <DishConfirmation>[
      DishConfirmation(
        dishId: 'a',
        restrictionId: RestrictionId.sesame,
        polarity: ConfirmationPolarity.present,
        day: DateTime(2026, 5, 12),
      ),
      DishConfirmation(
        dishId: 'b',
        restrictionId: RestrictionId.peanuts,
        polarity: ConfirmationPolarity.absent,
        day: DateTime(2026, 5, 12),
      ),
    ];

    // Act
    final evidence = Confirmations.forDish('a', stored);

    // Assert
    expect(evidence, <ConfirmationEvidence>[
      _own(RestrictionId.sesame, ConfirmationPolarity.present),
    ]);
    expect(evidence.single.shared, isFalse);
    expect(evidence.single.count, 1);
    expect(evidence.single.hashCode, isNot(0));
  });

  test('with no evidence the evaluation is unchanged', () {
    // Arrange
    final dish = _dish('Tahini salad');

    // Act
    final plain = ProfileEvaluator.evaluate(_green(dish.name), dish, sesame);
    final empty = ProfileEvaluator.evaluate(
      _green(dish.name),
      dish,
      sesame,
      confirmations: List<ConfirmationEvidence>.empty(),
    );

    // Assert
    expect(empty, plain);
    expect(plain.confirmations, isEmpty);
  });

  test('a group carries the answers to every person', () {
    // Arrange
    final dish = _dish('Tahini salad');
    final people = <NamedProfile>[
      NamedProfile(id: 'me', name: '', profile: sesame),
      NamedProfile(
        id: 'p1',
        name: 'Dana',
        profile: _profile(<RestrictionId>[RestrictionId.lactose]),
      ),
    ];

    // Act
    final group = GroupEvaluator.evaluate(
      _green(dish.name),
      dish,
      people,
      confirmations: <ConfirmationEvidence>[
        _own(RestrictionId.sesame, ConfirmationPolarity.absent),
      ],
    );

    // Assert
    expect(group.state, DishState.ask);
    expect(group.combined.confirmations, hasLength(1));
    expect(
      _concern(group.combined, RestrictionId.sesame).tier,
      EvidenceTier.denied,
    );
  });
}
