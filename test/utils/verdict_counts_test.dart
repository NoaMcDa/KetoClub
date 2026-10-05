import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/utils/verdict_counts.dart';

Dish _dish(String id, String name) => Dish(
  id: id,
  name: name,
  description: '',
  price: 40,
  options: const <DishOption>[],
);

AnalysedDish _placed(
  Dish dish,
  DishVerdict verdict, {
  bool hiddenCarb = false,
}) => AnalysedDish(
  dishId: dish.id,
  name: dish.name,
  verdict: verdict,
  why: 'why',
  modification: verdict == DishVerdict.modifiable ? 'swap' : null,
  hiddenCarbs: hiddenCarb
      ? const <HiddenCarb>[
          HiddenCarb(
            source: 'croutons',
            certainty: HiddenCarbCertainty.suspected,
            waiterQuestion: 'Are there croutons?',
          ),
        ]
      : const <HiddenCarb>[],
);

MenuAnalysed _analysis(List<AnalysedDish> dishes) => MenuAnalysed(
  dishes: dishes,
  unclassified: const <String>[],
  engine: const LlmEngine(model: 'm'),
  analysedAt: DateTime.utc(2026),
);

Menu _menu(List<MenuCategory> categories) => Menu(
  venueRef: const VenueRef(source: MenuSource.wolt, platformId: 'x'),
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: categories,
);

void main() {
  final steak = _dish('steak', 'Steak');
  final schnitzel = _dish('schnitzel', 'Schnitzel with fries');
  final pasta = _dish('pasta', 'Pasta');
  final salad = _dish('salad', 'Caesar salad');
  final cola = _dish('cola', 'Cola');
  final water = _dish('water', 'Mineral water');
  final ketchup = _dish('ketchup', 'Ketchup');
  final notice = _dish('notice', 'Dear customers');

  final menu = _menu([
    MenuCategory(id: 'mains', name: 'Mains', dishes: [steak, schnitzel, pasta]),
    MenuCategory(id: 'salads', name: 'Salads', dishes: [salad]),
    MenuCategory(id: 'drinks', name: 'שתייה', dishes: [cola, water]),
    MenuCategory(id: 'sauces', name: 'רטבים', dishes: [ketchup]),
    MenuCategory(id: 'notice', name: 'לקוחות יקרים', dishes: [notice]),
  ]);

  group('VerdictCounts.of', () {
    test('counts food dishes by verdict and leaves drinks, extras and '
        'notices out (D21)', () {
      // Arrange: every non-food line placed, in every verdict, so a leak
      // of any of them would change a number.
      final analysis = _analysis([
        _placed(steak, DishVerdict.orderAsIs),
        _placed(schnitzel, DishVerdict.modifiable),
        _placed(pasta, DishVerdict.nonKeto),
        _placed(salad, DishVerdict.modifiable, hiddenCarb: true),
        _placed(cola, DishVerdict.nonKeto),
        _placed(water, DishVerdict.orderAsIs),
        _placed(ketchup, DishVerdict.modifiable),
        _placed(notice, DishVerdict.orderAsIs),
      ]);

      // Act
      final counts = VerdictCounts.of(menu, analysis);

      // Assert
      expect(
        counts,
        const VerdictCounts(green: 1, yellow: 2, hiddenCarbYellow: 1, red: 1),
      );
      expect(counts.otherYellow, 1);
      expect(counts.total, 4);
      // 10 * (1 + 0.5 * 1 + 0.25 * 1) / 4 = 4.375 -> 4.4
      expect(counts.score, 4.4);
    });

    test('a dish the menu does not hold counts as food', () {
      final analysis = _analysis([
        _placed(_dish('ghost', 'Not on the menu'), DishVerdict.orderAsIs),
      ]);
      expect(
        VerdictCounts.of(menu, analysis),
        const VerdictCounts(green: 1, yellow: 0, hiddenCarbYellow: 0, red: 0),
      );
    });

    test('a menu whose only placed dishes are drinks has no score', () {
      final analysis = _analysis([
        _placed(cola, DishVerdict.nonKeto),
        _placed(water, DishVerdict.orderAsIs),
      ]);
      final counts = VerdictCounts.of(menu, analysis);
      expect(counts, VerdictCounts.zero);
      expect(counts.score, isNull);
    });

    test('an empty analysis is zero', () {
      expect(VerdictCounts.of(menu, _analysis(const [])), VerdictCounts.zero);
      expect(VerdictCounts.zero.score, isNull);
    });
  });

  group('VerdictCounts', () {
    test('is a value: equal by its four counts', () {
      const a = VerdictCounts(green: 1, yellow: 2, hiddenCarbYellow: 1, red: 3);
      const b = VerdictCounts(green: 1, yellow: 2, hiddenCarbYellow: 1, red: 3);
      const c = VerdictCounts(green: 1, yellow: 2, hiddenCarbYellow: 0, red: 3);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a.toString(), contains('hiddenCarbYellow: 1'));
    });

    test('rejects more hidden-carb yellows than yellows', () {
      expect(
        () => VerdictCounts(green: 0, yellow: 1, hiddenCarbYellow: 2, red: 0),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
