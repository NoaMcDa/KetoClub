// MenuController.evaluatedRows (Banto; ALG-04b, related to #346): each
// analysed row evaluated on the device for the settings' profile.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';

import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_settings_store.dart';

/// The venue every test opens.
const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

/// A dish named [name] with [id].
Dish _dish(String id, String name) => Dish(
  id: id,
  name: name,
  description: '',
  price: 10,
  options: const <DishOption>[],
);

/// The menu every test opens: a tahini salad and a steak.
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'Mains',
      dishes: <Dish>[_dish('salad', 'Tahini salad'), _dish('steak', 'Steak')],
    ),
  ],
);

/// A green verdict for [dish].
AnalysedDish _green(Dish dish) => AnalysedDish(
  dishId: dish.id,
  name: dish.name,
  verdict: DishVerdict.orderAsIs,
  why: 'why',
);

/// A controller over [settings] whose repository serves [_menu] and whose
/// classifier answers green for every dish.
MenuController _controller(FakeSettingsStore settings) {
  final repository = FakeMenuRepository()..stub(_ref, MenuFetched(menu: _menu));
  final classifier = FakeMenuClassifier()
    ..respondWith(
      MenuAnalysed(
        dishes: <AnalysedDish>[
          for (final dish in _menu.allDishes) _green(dish),
        ],
        unclassified: const <String>[],
        engine: const LlmEngine(model: 'test-model'),
        analysedAt: DateTime.utc(2026),
      ),
    );
  return MenuController(
    repository,
    classifier,
    settings,
    FakeNotesStore(),
    CarbBudgetController(),
  );
}

void main() {
  group('MenuController.evaluatedRows', () {
    test('is empty before a menu is open', () {
      // Arrange
      final controller = _controller(FakeSettingsStore());

      // Act / Assert
      expect(controller.evaluatedRows, isEmpty);
    });

    test('with no profile, every row keeps its keto verdict', () async {
      // Arrange
      final controller = _controller(FakeSettingsStore());

      // Act
      await controller.open(_ref);
      final rows = controller.evaluatedRows;

      // Assert
      expect(rows.map((r) => r.row), controller.visibleRows);
      expect(rows.map((r) => r.evaluated.state), <DishState>[
        DishState.fits,
        DishState.fits,
      ]);
      expect(rows.every((r) => r.evaluated.concerns.isEmpty), isTrue);
    });

    test('evaluates every row against the settings profile', () async {
      // Arrange
      final settings = FakeSettingsStore(
        initial: AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
        ),
      );
      final controller = _controller(settings);

      // Act
      await controller.open(_ref);
      final rows = controller.evaluatedRows;

      // Assert: the tahini salad is avoided; the wire verdict is not.
      expect(rows.first.row.dish.id, 'salad');
      expect(rows.first.evaluated.state, DishState.avoid);
      expect(rows.first.evaluated.dish.verdict, DishVerdict.orderAsIs);
      expect(rows.last.evaluated.state, DishState.fits);
      expect(controller.greenCount, 2);
    });
  });
}
