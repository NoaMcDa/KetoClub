import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/utils/constants.dart';

import '../../fakes/fake_clock.dart';
import 'menu_classifier_contract.dart';

/// The venue every menu built by this file is addressed to.
const VenueRef _venueRef = VenueRef(
  source: MenuSource.wolt,
  platformId: 'heuristic-classifier-test-venue',
);

/// A dish carrying [name] and nothing else, for tests that only care
/// about one piece of text.
Dish _dishNamed(String id, String name) =>
    Dish(id: id, name: name, description: '', price: 10, options: const []);

/// A menu addressed to [_venueRef] containing [dishes] in one category.
Menu _menuOf(List<Dish> dishes) => Menu(
  venueRef: _venueRef,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: [MenuCategory(id: 'cat-1', name: 'Mains', dishes: dishes)],
);

/// Classifies [menu] with a classifier ticking from [FakeClock] at
/// [now], returning the typed result (never a [MenuAnalysisFailed] —
/// this engine never produces one).
Future<MenuAnalysed> _classify(Menu menu, {DateTime? now}) async {
  final classifier = HeuristicMenuClassifier(
    clock: FakeClock(now ?? DateTime.utc(2026)),
  );
  final result = await classifier.classify(menu);
  return result as MenuAnalysed;
}

void main() {
  runMenuClassifierContract(
    'HeuristicMenuClassifier',
    () => HeuristicMenuClassifier(clock: FakeClock(DateTime.utc(2026))),
  );

  group('HeuristicMenuClassifier', () {
    group('classify given an English non-keto base returns nonKeto', () {
      for (final trigger in nonKetoBasesEn) {
        test('for the "$trigger" trigger', () async {
          // Arrange
          final dish = _dishNamed('dish-1', 'Test dish with $trigger on it');
          final menu = _menuOf([dish]);

          // Act
          final result = await _classify(menu);

          // Assert
          final analysed = result.dishes.single;
          expect(
            analysed.verdict,
            DishVerdict.nonKeto,
            reason: 'English base trigger "$trigger" did not turn red',
          );
          expect(analysed.modification, isNull);
          expect(analysed.why, isNotEmpty);
        });
      }
    });

    group('classify given a Hebrew non-keto base returns nonKeto', () {
      for (final trigger in nonKetoBasesHe) {
        test('for the "$trigger" trigger', () async {
          // Arrange
          final dish = _dishNamed('dish-1', 'מנה עם $trigger בתפריט');
          final menu = _menuOf([dish]);

          // Act
          final result = await _classify(menu);

          // Assert
          final analysed = result.dishes.single;
          expect(
            analysed.verdict,
            DishVerdict.nonKeto,
            reason: 'Hebrew base trigger "$trigger" did not turn red',
          );
          expect(analysed.modification, isNull);
          expect(analysed.why, isNotEmpty);
        });
      }
    });

    group('classify given an English carb modifier returns modifiable', () {
      for (final entry in carbModifiersEn.entries) {
        test('for the "${entry.key}" trigger', () async {
          // Arrange
          final dish = _dishNamed(
            'dish-1',
            'Test dish with ${entry.key} on the side',
          );
          final menu = _menuOf([dish]);

          // Act
          final result = await _classify(menu);

          // Assert
          final analysed = result.dishes.single;
          expect(
            analysed.verdict,
            DishVerdict.modifiable,
            reason:
                'English carb trigger "${entry.key}" did not turn '
                'yellow',
          );
          expect(analysed.modification, isNotNull);
          expect(analysed.modification!.trim(), isNotEmpty);
          expect(
            analysed.modification,
            contains(entry.value),
            reason:
                'English carb trigger "${entry.key}" did not carry its '
                'own waiter sentence',
          );
          expect(analysed.why, yellowWhyEn);
        });
      }
    });

    group('classify given a Hebrew carb modifier returns modifiable', () {
      for (final entry in carbModifiersHe.entries) {
        test('for the "${entry.key}" trigger', () async {
          // Arrange
          final dish = _dishNamed('dish-1', 'מנה עם ${entry.key} בתפריט');
          final menu = _menuOf([dish]);

          // Act
          final result = await _classify(menu);

          // Assert
          final analysed = result.dishes.single;
          expect(
            analysed.verdict,
            DishVerdict.modifiable,
            reason:
                'Hebrew carb trigger "${entry.key}" did not turn '
                'yellow',
          );
          expect(analysed.modification, isNotNull);
          expect(analysed.modification!.trim(), isNotEmpty);
          expect(
            analysed.modification,
            contains(entry.value),
            reason:
                'Hebrew carb trigger "${entry.key}" did not carry its '
                'own waiter sentence',
          );
          expect(analysed.why, yellowWhyHe);
        });
      }
    });

    test('classify given the README entrecôte with potato purée returns '
        'modifiable with the purée swap', () async {
      // Arrange
      const dish = Dish(
        id: 'dish-entrecote-300',
        name: 'Prime Entrecôte 300g',
        description: 'Served with butter-infused potato purée and baby carrots',
        price: 189,
        options: [
          DishOption(
            name: 'Choice of side',
            values: ['Potato Purée', 'Green Salad'],
          ),
        ],
      );
      final menu = _menuOf([dish]);

      // Act
      final result = await _classify(menu);

      // Assert
      final analysed = result.dishes.single;
      expect(analysed.verdict, DishVerdict.modifiable);
      expect(analysed.modification, contains(carbModifiersEn['puree']));
      expect(analysed.why, yellowWhyEn);
    });

    test('classify given the README pizza returns nonKeto', () async {
      // Arrange
      const dish = Dish(
        id: 'dish-pizza',
        name: 'Margherita Pizza',
        description: 'Tomato, mozzarella, fresh basil',
        price: 52,
        options: [],
      );
      final menu = _menuOf([dish]);

      // Act
      final result = await _classify(menu);

      // Assert
      final analysed = result.dishes.single;
      expect(analysed.verdict, DishVerdict.nonKeto);
      expect(analysed.modification, isNull);
      expect(analysed.why, redWhyEn.replaceAll('{base}', 'pizza'));
    });

    test('classify given a plain grilled protein returns orderAsIs', () async {
      // Arrange
      const dish = Dish(
        id: 'dish-salmon',
        name: 'Grilled Salmon',
        description: 'Served with lemon butter and steamed greens',
        price: 68,
        options: [],
      );
      final menu = _menuOf([dish]);

      // Act
      final result = await _classify(menu);

      // Assert
      final analysed = result.dishes.single;
      expect(analysed.verdict, DishVerdict.orderAsIs);
      expect(analysed.modification, isNull);
      expect(analysed.why, greenWhyEn);
    });

    test('classify given a plain salad returns orderAsIs', () async {
      // Arrange
      const dish = Dish(
        id: 'dish-salad',
        name: 'Greek Salad',
        description: 'Feta, olives, cucumber, tomato, olive oil dressing',
        price: 38,
        options: [],
      );
      final menu = _menuOf([dish]);

      // Act
      final result = await _classify(menu);

      // Assert
      final analysed = result.dishes.single;
      expect(analysed.verdict, DishVerdict.orderAsIs);
      expect(analysed.modification, isNull);
      expect(analysed.why, greenWhyEn);
    });

    test('classify given a carb trigger only in an option value returns '
        'modifiable', () async {
      // Arrange
      const dish = Dish(
        id: 'dish-chicken',
        name: 'Grilled chicken',
        description: '',
        price: 45,
        options: [
          DishOption(
            name: 'Choice of side',
            values: ['Potato purée', 'Green salad'],
          ),
        ],
      );
      final menu = _menuOf([dish]);

      // Act
      final result = await _classify(menu);

      // Assert
      final analysed = result.dishes.single;
      expect(analysed.verdict, DishVerdict.modifiable);
      expect(analysed.modification, contains(carbModifiersEn['puree']));
      expect(analysed.why, yellowWhyEn);
    });

    test(
      'classify given a Hebrew dish returns a Hebrew why and modification',
      () async {
        // Arrange
        const dish = Dish(
          id: 'dish-steak-he',
          name: 'סטייק אנטריקוט',
          description: 'מוגש עם פירה',
          price: 120,
          options: [],
        );
        final menu = _menuOf([dish]);

        // Act
        final result = await _classify(menu);

        // Assert
        final analysed = result.dishes.single;
        expect(analysed.verdict, DishVerdict.modifiable);
        expect(analysed.why, yellowWhyHe);
        expect(analysed.modification, contains(carbModifiersHe['פירה']));
      },
    );

    test('classify given an English dish returns an English why and '
        'modification', () async {
      // Arrange
      const dish = Dish(
        id: 'dish-steak-en',
        name: 'Steak',
        description: 'Served with mashed potatoes',
        price: 120,
        options: [],
      );
      final menu = _menuOf([dish]);

      // Act
      final result = await _classify(menu);

      // Assert
      final analysed = result.dishes.single;
      expect(analysed.verdict, DishVerdict.modifiable);
      expect(analysed.why, yellowWhyEn);
      expect(
        analysed.modification,
        contains(carbModifiersEn['mashed potatoes']),
      );
    });

    test('classify given a mixed-script menu gives each dish its own '
        'language', () async {
      // Arrange
      const hebrewDish = Dish(
        id: 'dish-cake-he',
        name: 'עוגת שוקולד',
        description: 'עוגה עם שוקולד',
        price: 32,
        options: [],
      );
      const englishDish = Dish(
        id: 'dish-salmon-en',
        name: 'Grilled Salmon',
        description: 'Served with lemon butter and steamed greens',
        price: 68,
        options: [],
      );
      final menu = _menuOf([hebrewDish, englishDish]);

      // Act
      final result = await _classify(menu);

      // Assert
      final byId = {for (final dish in result.dishes) dish.dishId: dish};
      final cake = byId['dish-cake-he']!;
      final salmon = byId['dish-salmon-en']!;
      expect(cake.verdict, DishVerdict.nonKeto);
      expect(cake.why, redWhyHe.replaceAll('{base}', 'עוגה'));
      expect(salmon.verdict, DishVerdict.orderAsIs);
      expect(salmon.why, greenWhyEn);
    });

    test('classify given two carb triggers joins both sentences in match '
        'order', () async {
      // Arrange
      const dish = Dish(
        id: 'dish-teriyaki-honey',
        name: 'Teriyaki Salmon',
        description: 'Glazed with teriyaki and served with honey drizzle',
        price: 60,
        options: [],
      );
      final menu = _menuOf([dish]);

      // Act
      final result = await _classify(menu);

      // Assert
      final analysed = result.dishes.single;
      final expected =
          '${carbModifiersEn['teriyaki']} ${carbModifiersEn['honey']}';
      expect(analysed.modification, expected);
    });

    test('classify given a dish never invents its dishId or name', () async {
      // Arrange
      final dish = _dishNamed('dish-original-id', 'Grilled halloumi');
      final menu = _menuOf([dish]);

      // Act
      final result = await _classify(menu);

      // Assert
      final analysed = result.dishes.single;
      expect(analysed.dishId, 'dish-original-id');
      expect(analysed.name, 'Grilled halloumi');
    });

    test(
      'classify given any menu returns an empty unclassified list',
      () async {
        // Arrange
        final menu = _menuOf([
          _dishNamed('dish-1', 'Spaghetti Carbonara'),
          _dishNamed('dish-2', 'Grilled halloumi'),
        ]);

        // Act
        final result = await _classify(menu);

        // Assert
        expect(result.unclassified, isEmpty);
      },
    );

    test('classify given an empty menu returns an empty dish list', () async {
      // Arrange
      final menu = _menuOf(const []);

      // Act
      final result = await _classify(menu);

      // Assert
      expect(result.dishes, isEmpty);
      expect(result.unclassified, isEmpty);
    });

    test(
      'classify given a menu stamps analysedAt from the injected clock',
      () async {
        // Arrange
        final fixedNow = DateTime.utc(2026, 3, 4, 5, 6);
        final menu = _menuOf([_dishNamed('dish-1', 'Grilled halloumi')]);

        // Act
        final result = await _classify(menu, now: fixedNow);

        // Assert
        expect(result.analysedAt, fixedNow);
      },
    );

    test('classify given any menu stamps the engine as rules with reason '
        'notConfigured', () async {
      // Arrange
      final menu = _menuOf([_dishNamed('dish-1', 'Grilled halloumi')]);

      // Act
      final result = await _classify(menu);

      // Assert
      expect(
        result.engine,
        const RulesEngine(reason: MenuAnalysisFailureReason.notConfigured),
      );
    });
  });
}
