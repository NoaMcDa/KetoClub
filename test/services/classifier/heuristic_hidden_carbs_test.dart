/// `HeuristicMenuClassifier` applies §9.4 rule 5a to the rule engine's
/// hidden-carb flags (issue #213 on the rules path): a green with a flag
/// becomes yellow with the flag's question, a yellow keeps its script and
/// carries the flags, and a red drops them.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/verdict_counts.dart';

import '../../fakes/fake_clock.dart';

/// A dish with [name], [description] and [options].
Dish _dish(
  String id,
  String name, {
  String description = '',
  List<DishOption> options = const <DishOption>[],
}) => Dish(
  id: id,
  name: name,
  description: description,
  price: 10,
  options: options,
);

/// A one-category menu of [dishes].
Menu _menuOf(List<Dish> dishes) => Menu(
  venueRef: const VenueRef(source: MenuSource.wolt, platformId: 'hc'),
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: [MenuCategory(id: 'c', name: 'Mains', dishes: dishes)],
);

/// The one analysed dish of a menu holding only [dish].
Future<AnalysedDish> _analyse(
  Dish dish, {
  ClassificationOptions options = const ClassificationOptions(),
}) async {
  final classifier = HeuristicMenuClassifier(
    clock: FakeClock(DateTime.utc(2026)),
  );
  final result = await classifier.classify(
    _menuOf([dish]),
    options: options,
  ) as MenuAnalysed;
  return result.dishes.single;
}

void main() {
  group('HeuristicMenuClassifier — hidden carbs (§9.4 rule 5a)', () {
    test('a green with a flag becomes yellow with its question', () async {
      // Act
      final dish = await _analyse(
        _dish('d1', 'Grilled salmon', description: 'House sauce'),
      );

      // Assert
      expect(dish.verdict, DishVerdict.modifiable);
      expect(dish.why, hiddenCarbWhyEn);
      expect(dish.modification, 'Is there sugar or flour in the house sauce?');
      expect(dish.hiddenCarbs, const [
        HiddenCarb(
          source: 'house sauce',
          certainty: HiddenCarbCertainty.suspected,
          waiterQuestion: 'Is there sugar or flour in the house sauce?',
        ),
      ]);
    });

    test(
      'a Hebrew green with a flag gets the Hebrew why and question',
      () async {
        // Act
        final dish = await _analyse(
          _dish('d1', 'פרגית במרינדה', description: 'עם סלט ירוק'),
        );

        // Assert
        expect(dish.verdict, DishVerdict.modifiable);
        expect(dish.why, hiddenCarbWhyHe);
        expect(dish.modification, 'יש סוכר או דבש במרינדה?');
        expect(dish.hiddenCarbs.single.source, 'מרינדה');
      },
    );

    test('with several flags, the first question is the script', () async {
      // Act
      final dish = await _analyse(
        _dish(
          'd1',
          'Ribeye',
          description: 'Glazed, amba, house sauce, gravy and garlic sauce',
        ),
      );

      // Assert
      expect(dish.hiddenCarbs.map((flag) => flag.source), [
        'glaze',
        'amba',
        'house sauce',
      ]);
      expect(dish.modification, dish.hiddenCarbs.first.waiterQuestion);
    });

    test('a yellow keeps its script and carries an uncovered flag', () async {
      // Act
      final dish = await _analyse(
        _dish('d1', 'Crispy salmon', description: 'With fries'),
      );

      // Assert
      expect(dish.verdict, DishVerdict.modifiable);
      expect(dish.why, yellowWhyEn);
      expect(dish.modification, carbModifiersEn['fries']);
      expect(dish.hiddenCarbs.single.source, 'crispy coating');
    });

    test('a yellow drops a flag its script already covers', () async {
      // Act
      final dish = await _analyse(_dish('d1', 'Honey-glazed salmon'));

      // Assert
      expect(dish.verdict, DishVerdict.modifiable);
      expect(dish.modification, carbModifiersEn['honey']);
      expect(dish.hiddenCarbs, isEmpty);
    });

    test('a red drops its flags', () async {
      // Act
      final dish = await _analyse(
        _dish('d1', 'Fettuccine', description: 'Creamy house sauce'),
      );

      // Assert
      expect(dish.verdict, DishVerdict.nonKeto);
      expect(dish.modification, isNull);
      expect(dish.hiddenCarbs, isEmpty);
    });

    test('a dietary yellow keeps the dietary why and script', () async {
      // Arrange
      final options = ClassificationOptions(
        dietaryConstraints: ClassificationOptions.dietaryConstraintsFor(
          seedOilFree: false,
          dairyFree: true,
          carnivoreOnly: false,
        ),
      );

      // Act
      final dish = await _analyse(
        _dish('d1', 'Steak', description: 'Butter, gravy'),
        options: options,
      );

      // Assert
      expect(dish.verdict, DishVerdict.modifiable);
      expect(dish.why, dietaryRuleWhyEn);
      expect(dish.modification, dairyFreeModificationEn);
      expect(dish.hiddenCarbs.single.source, 'gravy');
    });

    test('a guard phrase keeps the dish green', () async {
      // Act
      final dish = await _analyse(
        _dish('d1', 'Grilled salmon', description: 'Sugar-free glaze'),
      );

      // Assert
      expect(dish.verdict, DishVerdict.orderAsIs);
      expect(dish.hiddenCarbs, isEmpty);
    });

    test('a removal option naming a trigger raises nothing', () async {
      // Act
      final dish = await _analyse(
        _dish(
          'd1',
          'Chicken breast',
          description: 'With salad',
          options: const <DishOption>[
            DishOption(name: 'Changes', values: <String>['No marinade']),
          ],
        ),
      );

      // Assert
      expect(dish.verdict, DishVerdict.orderAsIs);
      expect(dish.hiddenCarbs, isEmpty);
    });

    test('the flagged dish round-trips through the cache form', () async {
      // Arrange
      final dish = await _analyse(
        _dish('d1', 'אנטריקוט', description: 'ברוטב חום, עם פירה'),
      );

      // Act
      final read = AnalysedDish.tryFrom(dish.toJson());

      // Assert
      expect(dish.hiddenCarbs.single.source, 'רוטב חום');
      expect(read, dish);
    });

    test('a flagged yellow counts as a hidden-carb yellow', () async {
      // Arrange
      final menu = _menuOf([
        _dish('d1', 'Grilled salmon', description: 'House sauce'),
        _dish('d2', 'Grilled salmon', description: 'Lemon'),
      ]);
      final classifier = HeuristicMenuClassifier(
        clock: FakeClock(DateTime.utc(2026)),
      );

      // Act
      final analysis = await classifier.classify(menu) as MenuAnalysed;
      final counts = VerdictCounts.of(menu, analysis);

      // Assert
      expect(counts.green, 1);
      expect(counts.yellow, 1);
      expect(counts.hiddenCarbYellow, 1);
    });
  });
}
