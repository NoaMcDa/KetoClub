// ProfileEvaluator, the waiter questions and the chef card for kosher and
// halal (Banto, issue #342): components only, never certification. Both are
// flexible, so a stated or likely component in the dish is "avoid", one in
// an option a change, and a suspected one is listed and moves nothing; no
// question names kosher or halal, and the chef card asks about the meat's
// certificate on a line of its own.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/allergens/waiter_questions.dart';

/// A dish with [name], [description], [options] and platform [tags].
Dish _dish(
  String name, {
  String description = '',
  List<String> options = const <String>[],
  List<String> tags = const <String>[],
}) => Dish(
  id: 'd',
  name: name,
  description: description,
  price: 10,
  options: options.isEmpty
      ? const <DishOption>[]
      : <DishOption>[DishOption(name: 'Extras', values: options)],
  declaredTags: tags,
);

/// [dish] evaluated as green for a profile of [id] alone.
EvaluatedDish _evaluate(Dish dish, RestrictionId id) =>
    ProfileEvaluator.evaluate(
      AnalysedDish(
        dishId: 'd',
        name: dish.name,
        verdict: DishVerdict.orderAsIs,
        why: 'Fits',
      ),
      dish,
      DietaryProfile.empty.withEntry(id),
    );

/// The concern of [result] for [id], or null.
Concern? _concern(EvaluatedDish result, RestrictionId id) {
  for (final concern in result.concerns) {
    if (concern.restrictionId == id) return concern;
  }
  return null;
}

/// The words no religious question or note may say: a component is
/// flagged, a certificate never claimed.
const List<String> _verdictWords = <String>['kosher', 'halal', 'כשר', 'חלאל'];

void _expectNoVerdictWord(String text) {
  for (final word in _verdictWords) {
    expect(text.toLowerCase(), isNot(contains(word)), reason: text);
  }
}

void main() {
  group('kosher', () {
    const kosher = RestrictionId.kosher;

    test('pork, shellfish and a cheeseburger in the dish are avoid', () {
      for (final dish in <Dish>[
        _dish('Pulled pork sandwich'),
        _dish('צלעות חזיר'),
        _dish('Shrimp tempura'),
        _dish('שרימפס בשום'),
        _dish('Cheeseburger'),
        _dish('Grilled eel'),
      ]) {
        final result = _evaluate(dish, kosher);
        expect(result.state, DishState.avoid, reason: dish.name);
        expect(_concern(result, kosher), isNotNull, reason: dish.name);
      }
    });

    test('meat with dairy stated in the dish is avoid', () {
      final result = _evaluate(
        _dish('Ribeye', description: 'With garlic butter'),
        kosher,
      );
      expect(result.state, DishState.avoid);
      expect(
        _concern(result, kosher)!.waiterQuestion,
        "Can this be made without the 'butter', so there is no dairy with "
        'the meat?',
      );
    });

    test('a fish in a cream sauce fits: fish is no meat', () {
      for (final dish in <Dish>[
        _dish('Salmon in cream sauce'),
        _dish('פילה לברק', description: 'ברוטב חמאה ולימון'),
      ]) {
        final result = _evaluate(dish, kosher);
        expect(result.state, DishState.fits, reason: dish.name);
        expect(result.concerns, isEmpty, reason: dish.name);
      }
    });

    test('cheese only in an option is listed, asking to leave one off', () {
      final result = _evaluate(
        _dish('Beef burger', options: <String>['Cheddar']),
        kosher,
      );
      expect(result.state, DishState.fits);
      final concern = _concern(result, kosher)!;
      expect(concern.certainty, Certainty.suspected);
      expect(
        concern.waiterQuestion,
        "This dish has 'Beef' and 'Cheddar': can one of them be left off, "
        'so there is no meat with dairy?',
      );
    });

    test('a likely dairy sauce on meat is listed, asking about dairy', () {
      final result = _evaluate(_dish('Chicken alfredo'), kosher);
      expect(result.state, DishState.fits);
      expect(
        _concern(result, kosher)!.waiterQuestion,
        waiterQuestionMeatDairyAskEn,
      );
    });

    test('shrimp in an option is a change, asking without it', () {
      final result = _evaluate(
        _dish('Caesar salad', options: <String>['Add shrimp']),
        kosher,
      );
      expect(result.state, DishState.fitsWithChange);
      expect(result.modification, "Ask for it without 'shrimp'");
      expect(
        _concern(result, kosher)!.waiterQuestion,
        "Can this be served without 'shrimp', so there is no shellfish in "
        'it?',
      );
    });

    test('a guarded substitute is listed and moves nothing', () {
      final result = _evaluate(_dish('Turkey bacon omelette'), kosher);
      expect(result.state, DishState.fits);
      expect(_concern(result, kosher)!.certainty, Certainty.suspected);
    });

    test('questions name the component, in the menu language', () {
      expect(
        _concern(
          _evaluate(_dish('Pulled pork'), kosher),
          kosher,
        )!.waiterQuestion,
        'Can this be made without pork?',
      );
      expect(
        _concern(
          _evaluate(_dish('Eggs with bacon'), kosher),
          kosher,
        )!.waiterQuestion,
        'Can this be made without pork?',
      );
      expect(
        _concern(
          _evaluate(_dish('צלעות חזיר'), kosher),
          kosher,
        )!.waiterQuestion,
        'אפשר להכין את המנה בלי חזיר?',
      );
      expect(
        _concern(
          _evaluate(_dish('Fried calamari'), kosher),
          kosher,
        )!.waiterQuestion,
        'Can this be made without shellfish?',
      );
      expect(
        _concern(
          _evaluate(_dish('Swordfish steak'), kosher),
          kosher,
        )!.waiterQuestion,
        "The menu says 'Swordfish': does it contain fish without fins and "
        'scales?',
      );
      final schnitzel = _evaluate(
        _dish('שניצל עוף', description: 'ברוטב שמנת'),
        kosher,
      );
      expect(
        _concern(schnitzel, kosher)!.waiterQuestion,
        "אפשר להכין את המנה בלי 'שמנת', כדי שלא יהיה בה בשר עם חלב?",
      );
    });

    test("a platform's kosher tag lowers kosher concerns one step, and "
        'clears a suspected one', () {
      final salami = _evaluate(
        _dish('Salami sandwich', tags: <String>['kosher']),
        kosher,
      );
      expect(_concern(salami, kosher), isNull);
      expect(salami.declarations.single.rule, 'kosher');
      final bacon = _evaluate(
        _dish('Bacon sandwich', tags: <String>['kosher']),
        kosher,
      );
      expect(_concern(bacon, kosher)!.certainty, Certainty.likely);
      expect(_concern(bacon, kosher)!.tier, EvidenceTier.declared);
    });

    test('"kosher salt" in the text declares nothing', () {
      final result = _evaluate(
        _dish('Bacon', description: 'Seasoned with kosher salt'),
        kosher,
      );
      expect(result.declarations, isEmpty);
      expect(result.state, DishState.avoid);
    });
  });

  group('halal', () {
    const halal = RestrictionId.halal;

    test('pork and alcohol in the dish are avoid', () {
      for (final dish in <Dish>[
        _dish('Ham and cheese'),
        _dish('Chicken in red wine sauce'),
        _dish('Penne alla vodka'),
        _dish('עוף ברוטב יין'),
        _dish('בירה מהחבית'),
      ]) {
        expect(
          _evaluate(dish, halal).state,
          DishState.avoid,
          reason: dish.name,
        );
      }
    });

    test('a drink without alcohol, wine vinegar and cherry tomatoes fit', () {
      for (final dish in <Dish>[
        _dish('Non-alcoholic beer'),
        _dish('Salad', description: 'Red wine vinegar dressing'),
        _dish('סלט עגבניות שרי'),
        _dish('Shrimp tempura'),
        _dish('Cheeseburger'),
      ]) {
        expect(_evaluate(dish, halal).state, DishState.fits, reason: dish.name);
      }
    });

    test('alcohol questions name the alcohol', () {
      expect(
        _concern(
          _evaluate(_dish('Chicken in red wine sauce'), halal),
          halal,
        )!.waiterQuestion,
        "The menu says 'wine': does it contain alcohol?",
      );
      expect(
        _concern(_evaluate(_dish('Panna cotta'), halal), halal)!.waiterQuestion,
        "The menu says 'Panna cotta': does it contain gelatin?",
      );
    });

    test('a kosher tag never lowers halal', () {
      final result = _evaluate(
        _dish('Salami sandwich', tags: <String>['kosher']),
        halal,
      );
      expect(_concern(result, halal)!.certainty, Certainty.suspected);
      expect(result.declarations, isEmpty);
    });
  });

  group('no question, note or subject says kosher or halal', () {
    final dishes = <Dish>[
      _dish('Pulled pork'),
      _dish('Shrimp', options: <String>['Add shrimp']),
      _dish('Ribeye', description: 'With butter'),
      _dish('Beef burger', options: <String>['Cheddar']),
      _dish('Chicken alfredo'),
      _dish('Red wine'),
      _dish('Panna cotta'),
      _dish('Black pudding'),
      _dish('Braised rabbit'),
      _dish('Grilled eel'),
      _dish('צלעות חזיר'),
      _dish('שניצל עוף', description: 'ברוטב שמנת'),
      _dish('עוף ברוטב יין'),
    ];
    for (final id in <RestrictionId>[
      RestrictionId.kosher,
      RestrictionId.halal,
    ]) {
      test(id.name, () {
        for (final hebrew in <bool>[false, true]) {
          _expectNoVerdictWord(WaiterQuestions.subject(id, hebrew: hebrew));
        }
        for (final dish in dishes) {
          final result = _evaluate(dish, id);
          for (final concern in result.concerns) {
            _expectNoVerdictWord(concern.waiterQuestion!);
          }
          final note = ChefCardText.dishAllergyNote(
            DietaryProfile.empty.withEntry(id),
            dishName: dish.name,
            concerns: result.concerns,
            hebrew: false,
          )!;
          _expectNoVerdictWord(note);
        }
      });
    }
  });

  group('the chef card', () {
    test('a kosher entry says what the person keeps, then asks about the '
        "meat's certificate on its own line", () {
      final lines = ChefCardText.compose(
        DietaryProfile.empty.withEntry(RestrictionId.kosher),
        hebrew: false,
      );
      const intro =
          'Hello, I have dietary restrictions and I would like your help '
          'with my order.';
      const entry =
          'I keep kosher — please tell me if a dish has pork, shellfish, '
          'fish without fins and scales, or mixes meat and dairy.';
      expect(lines, <String>[
        intro,
        entry,
        'Is your meat kosher-certified?',
        'Thank you.',
      ]);
    });

    test('a halal entry in Hebrew, then its certificate question', () {
      final lines = ChefCardText.compose(
        DietaryProfile.empty.withEntry(RestrictionId.halal),
        hebrew: true,
      );
      expect(lines[1], startsWith('אני אוכל/ת חלאל'));
      expect(lines[2], 'האם יש לבשר אצלכם תעודת חלאל?');
    });

    test('the dish card heads with the line and the question when no strict '
        'entry is there', () {
      final lines = ChefCardText.composeForDish(
        DietaryProfile.empty.withEntry(RestrictionId.kosher),
        dishName: 'Ribeye',
        modification: null,
        questions: const <String>['Is there any dairy?'],
        crossContact: false,
        hebrew: false,
      );
      expect(lines[2], 'Is your meat kosher-certified?');
      expect(lines[3], 'The dish I would like: Ribeye');
    });

    test('only kosher and halal ask about a certificate', () {
      for (final id in RestrictionId.values) {
        final question = ChefCardText.certificationQuestion(id, hebrew: false);
        expect(
          question != null,
          id == RestrictionId.kosher || id == RestrictionId.halal,
          reason: id.name,
        );
      }
    });

    test('the dish note leaves out the dairy, not the meat', () {
      final result = _evaluate(
        _dish('Ribeye', description: 'With butter'),
        RestrictionId.kosher,
      );
      final note = ChefCardText.dishAllergyNote(
        DietaryProfile.empty.withEntry(RestrictionId.kosher),
        dishName: 'Ribeye',
        concerns: result.concerns,
        hebrew: false,
      )!;
      expect(note, contains("please make it without 'butter'"));
      expect(note, isNot(contains('Ribeye +')));
    });
  });
}
