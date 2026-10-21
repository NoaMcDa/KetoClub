// Counts other people shared as evidence (Banto, ALG-14, issue #409;
// architecture.md D27): `Confirmations.sharedForDish` turns the backend's
// counts into shared pieces from the threshold up, and `ProfileEvaluator`
// lets a shared denial lower a concern one step but never lets a shared
// present raise one: it is a hint, not a verdict. Only the profile's own
// restrictions reach `EvaluatedDish.sharedConfirmations`.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/dish_confirmation.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/shared_confirmation.dart';
import 'package:ketoclub/utils/allergens/confirmations.dart';
import 'package:ketoclub/utils/allergens/group_evaluator.dart';
import 'package:ketoclub/utils/allergens/kitchen_reach.dart';
import 'package:ketoclub/utils/allergens/kitchen_signals.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';

/// A dish named [name], id `d`.
Dish _dish(String name) => Dish(
  id: 'd',
  name: name,
  description: '',
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

/// A shared count of [count] people about [id], as the backend answers it.
ConfirmationEvidence _shared(
  RestrictionId id,
  ConfirmationPolarity polarity, {
  int count = sharedConfirmationThreshold,
}) => ConfirmationEvidence(
  restrictionId: id,
  polarity: polarity,
  day: DateTime(2026, 10, 12),
  shared: true,
  count: count,
);

/// The evaluation's one concern about [id].
Concern _concern(EvaluatedDish evaluated, RestrictionId id) =>
    evaluated.concerns.singleWhere((concern) => concern.restrictionId == id);

/// A plate whose sesame is only suspected, in a removable sauce.
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

  group('Confirmations.sharedForDish', () {
    test('one piece per polarity from the threshold, dated last', () {
      // Arrange
      final shared = SharedConfirmations.tryFrom(<Object?>[
        <String, Object?>{
          'dishFingerprint': dishFingerprint('d'),
          'restrictionId': 'sesame',
          'present': 3,
          'absent': 5,
          'first': '2026-10-01',
          'last': '2026-10-12',
        },
        <String, Object?>{
          'dishFingerprint': dishFingerprint('d'),
          'restrictionId': 'peanuts',
          'present': 2,
          'absent': 0,
          'first': '2026-10-01',
          'last': '2026-10-12',
        },
        <String, Object?>{
          'dishFingerprint': dishFingerprint('other'),
          'restrictionId': 'milk',
          'present': 9,
          'absent': 0,
          'first': '2026-10-01',
          'last': '2026-10-12',
        },
      ]);

      // Act
      final pieces = Confirmations.sharedForDish('d', shared);

      // Assert: below the threshold and another dish's counts are none.
      expect(pieces, <ConfirmationEvidence>[
        _shared(RestrictionId.sesame, ConfirmationPolarity.present),
        _shared(RestrictionId.sesame, ConfirmationPolarity.absent, count: 5),
      ]);
      expect(pieces.first.source, isNull);
      expect(Confirmations.sharedForDish('d', null), isEmpty);
    });
  });

  group('ProfileEvaluator with shared evidence', () {
    test('a shared present never raises a concern', () {
      // Arrange
      final before = ProfileEvaluator.evaluate(
        _plateWithGuess,
        _dish('Plate'),
        sesame,
      );

      // Act
      final after = ProfileEvaluator.evaluate(
        _plateWithGuess,
        _dish('Plate'),
        sesame,
        confirmations: <ConfirmationEvidence>[
          _shared(RestrictionId.sesame, ConfirmationPolarity.present, count: 9),
        ],
      );

      // Assert: still suspected and still to ask, as without it.
      expect(before.state, DishState.ask);
      expect(after.state, DishState.ask);
      expect(
        _concern(after, RestrictionId.sesame),
        _concern(before, RestrictionId.sesame),
      );
      expect(after.sharedConfirmations, hasLength(1));
    });

    test('a shared present adds no concern the menu does not show', () {
      // Act
      final after = ProfileEvaluator.evaluate(
        _green('Plate'),
        _dish('Plate'),
        sesame,
        confirmations: <ConfirmationEvidence>[
          _shared(RestrictionId.sesame, ConfirmationPolarity.present),
        ],
      );

      // Assert: nothing found, nothing raised; the line still says it.
      expect(after.concerns, isEmpty);
      expect(after.state, DishState.fits);
      expect(
        after.sharedConfirmations.single.polarity,
        ConfirmationPolarity.present,
      );
    });

    test('a shared denial lowers one step, as a hint', () {
      // Arrange
      final dish = _dish('Tahini salad');

      // Act
      final after = ProfileEvaluator.evaluate(
        _green(dish.name),
        dish,
        sesame,
        confirmations: <ConfirmationEvidence>[
          _shared(RestrictionId.sesame, ConfirmationPolarity.absent),
        ],
      );

      // Assert
      final concern = _concern(after, RestrictionId.sesame);
      expect(concern.certainty, Certainty.likely);
      expect(concern.tier, EvidenceTier.denied);
      expect(after.state, DishState.avoid);
    });

    test('a strict suspected concern stays to ask after a denial', () {
      // Act
      final after = ProfileEvaluator.evaluate(
        _plateWithGuess,
        _dish('Plate'),
        sesame,
        confirmations: <ConfirmationEvidence>[
          _shared(RestrictionId.sesame, ConfirmationPolarity.absent, count: 40),
        ],
      );

      // Assert: never below suspected, so never "fits".
      expect(
        _concern(after, RestrictionId.sesame).certainty,
        Certainty.suspected,
      );
      expect(after.state, DishState.ask);
    });

    test('a denial is blocked by a shared present', () {
      // Arrange
      final dish = _dish('Tahini salad');

      // Act
      final after = ProfileEvaluator.evaluate(
        _green(dish.name),
        dish,
        sesame,
        confirmations: <ConfirmationEvidence>[
          _shared(RestrictionId.sesame, ConfirmationPolarity.absent, count: 8),
          _shared(RestrictionId.sesame, ConfirmationPolarity.present),
        ],
      );

      // Assert
      expect(_concern(after, RestrictionId.sesame).certainty, Certainty.stated);
    });

    test("only the profile's restrictions, from the threshold, are kept "
        'for the dish card', () {
      // Act
      final after = ProfileEvaluator.evaluate(
        _green('Plate'),
        _dish('Plate'),
        sesame,
        confirmations: <ConfirmationEvidence>[
          _shared(RestrictionId.peanuts, ConfirmationPolarity.absent),
          _shared(
            RestrictionId.sesame,
            ConfirmationPolarity.absent,
            count: sharedConfirmationThreshold - 1,
          ),
          ConfirmationEvidence(
            restrictionId: RestrictionId.sesame,
            polarity: ConfirmationPolarity.absent,
            day: DateTime(2026, 10, 12),
          ),
        ],
      );

      // Assert: the person's own answer is not a shared line either.
      expect(after.sharedConfirmations, isEmpty);
    });

    test("a group keeps every person's shared lines", () {
      // Arrange
      final people = <NamedProfile>[
        NamedProfile(id: 'me', name: '', profile: sesame),
        NamedProfile(
          id: 'p1',
          name: 'Dana',
          profile: _profile(<RestrictionId>[RestrictionId.peanuts]),
        ),
      ];

      // Act
      final group = GroupEvaluator.evaluate(
        _green('Plate'),
        _dish('Plate'),
        people,
        confirmations: <ConfirmationEvidence>[
          _shared(RestrictionId.sesame, ConfirmationPolarity.absent),
          _shared(RestrictionId.peanuts, ConfirmationPolarity.present),
          _shared(RestrictionId.milk, ConfirmationPolarity.present),
        ],
      );

      // Assert: milk is no one's, so it is no one's line.
      expect(
        group.combined.sharedConfirmations.map((p) => p.restrictionId),
        unorderedEquals(<RestrictionId>[
          RestrictionId.sesame,
          RestrictionId.peanuts,
        ]),
      );
    });

    test('the kitchen signals keep the shared lines', () {
      // Arrange
      final evaluated = EvaluatedDish(
        dish: _green('Plate'),
        concerns: const <Concern>[],
        state: DishState.fits,
        sharedConfirmations: <ConfirmationEvidence>[
          _shared(RestrictionId.sesame, ConfirmationPolarity.absent),
        ],
      );

      const reach = KitchenReach(
        signals: <KitchenSignal>[
          KitchenSignal(
            kind: KitchenSignalKind.wok,
            threatens: <RestrictionId>[RestrictionId.sesame],
            evidence: <String>['Pad thai'],
            questionEn: 'Is the wok shared?',
            questionHe: 'האם הווק משותף?',
          ),
        ],
        scope: <KitchenSignalKind, Set<String>>{
          KitchenSignalKind.wok: <String>{'d'},
        },
        hebrew: false,
      );

      // Act
      final after = applyKitchenSignals(
        evaluated,
        _dish('Plate'),
        sesame,
        reach,
      );

      // Assert: the kitchen made it "ask"; the lines are still there.
      expect(after.state, DishState.ask);
      expect(after.sharedConfirmations, evaluated.sharedConfirmations);
    });
  });
}
