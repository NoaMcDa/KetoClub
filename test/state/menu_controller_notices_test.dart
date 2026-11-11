import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/state/menu_controller.dart';

import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_settings_store.dart';

/// The venue every test opens.
const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

/// The notice heading of the menu issue #445 was reported on.
const String _noticeHeading = 'שימו לב! 💙';

/// A [Dish] named [name], priced [price].
Dish _dish(
  String name, {
  required String id,
  String description = '',
  double price = 10,
}) => Dish(
  id: id,
  name: name,
  description: description,
  price: price,
  options: const <DishOption>[],
);

/// The allergen notice of issue #445: a zero-priced line nobody can order.
final Dish _allergenNotice = _dish(
  'מידע לאלרגנים! 💙',
  id: 'notice',
  description: 'למידע על אלרגנים יש ליצור קשר עם המסעדה!!',
  price: 0,
);

/// A [Menu] for [_ref] holding [categories], in order.
Menu _menu(Map<String, List<Dish>> categories) => Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    for (final entry in categories.entries)
      MenuCategory(id: 'c-${entry.key}', name: entry.key, dishes: entry.value),
  ],
);

/// A green verdict for [dish].
AnalysedDish _green(Dish dish) => AnalysedDish(
  dishId: dish.id,
  name: dish.name,
  verdict: DishVerdict.orderAsIs,
  why: 'why',
);

void main() {
  group('MenuController and a menu notice (issue #445)', () {
    late FakeMenuRepository repository;
    late FakeMenuClassifier classifier;
    late MenuController controller;

    final steak = _dish('Steak', id: 'steak');
    final salad = _dish('Salad', id: 'salad');

    setUp(() {
      repository = FakeMenuRepository();
      classifier = FakeMenuClassifier();
      controller = MenuController(
        repository,
        classifier,
        FakeSettingsStore(),
        FakeNotesStore(),
        CarbBudgetController(),
      );
    });

    /// Opens [menu] on [controller].
    Future<void> open(Menu menu) {
      repository.stub(_ref, MenuFetched(menu: menu));
      return controller.open(_ref);
    }

    test('a line under a notice heading is not a row, has no category chip '
        'and is not counted as a dish', () async {
      // Arrange: a notice-only category ahead of the real dishes. The fake
      // classifier gives every line a verdict, the notice included.
      final menu = _menu({
        _noticeHeading: [_allergenNotice],
        'Mains': [steak, salad],
      });

      // Act
      await open(menu);

      // Assert
      expect(controller.analysis, isA<MenuAnalysed>());
      expect(controller.visibleRows.map((row) => row.dish.id), [
        'steak',
        'salad',
      ]);
      expect(controller.visibleCategories, ['Mains']);
      expect(controller.totalDishCount, 2);
    });

    test('restaurantNotices holds the notice, in menu order', () async {
      // Arrange
      final closing = _dish('Closed on Sunday', id: 'closing', price: 0);
      final menu = _menu({
        _noticeHeading: [_allergenNotice],
        'Mains': [steak],
        'Dear customers': [closing],
      });

      // Act
      await open(menu);

      // Assert
      expect(controller.restaurantNotices, [_allergenNotice, closing]);
    });

    test('a notice listed under two categories appears once', () async {
      // Arrange
      final menu = _menu({
        _noticeHeading: [_allergenNotice],
        'Please note': [_allergenNotice],
        'Mains': [steak],
      });

      // Act
      await open(menu);

      // Assert
      expect(controller.restaurantNotices, [_allergenNotice]);
    });

    test('a zero-priced line named by a notice word is a notice under an '
        'ordinary heading too', () async {
      // Arrange: "Please note" at a price of zero, filed under Mains.
      final note = _dish('Please note', id: 'note', price: 0);
      final menu = _menu({
        'Mains': [steak, note],
      });

      // Act
      await open(menu);

      // Assert: the category keeps its chip, for the real dish.
      expect(controller.restaurantNotices, [note]);
      expect(controller.visibleRows.map((row) => row.dish.id), ['steak']);
      expect(controller.visibleCategories, ['Mains']);
    });

    test('a mixed category keeps its real dishes under every filter', () async {
      // Arrange: the notice is given a green verdict like the steak.
      final menu = _menu({
        'Mains': [steak],
        _noticeHeading: [_allergenNotice],
      });
      classifier.respondWith(
        MenuAnalysed(
          dishes: [_green(steak), _green(_allergenNotice)],
          unclassified: const <String>[],
          engine: const LlmEngine(model: 'test-model'),
          analysedAt: DateTime.utc(2026),
        ),
      );
      await open(menu);

      // Act
      await controller.setFilter(MenuFilter.greenOnly);

      // Assert: green-only shows the steak, never the green notice.
      expect(controller.visibleRows.map((row) => row.dish.id), ['steak']);
      expect(controller.greenCount, 1);
    });

    test('a search that matches the notice text finds no row', () async {
      // Arrange
      final menu = _menu({
        _noticeHeading: [_allergenNotice],
        'Mains': [steak],
      });
      await open(menu);

      // Act
      controller.setQuery('אלרגנים');

      // Assert
      expect(controller.visibleRows, isEmpty);
      expect(controller.visibleCategories, isEmpty);
    });

    test('a failed analysis still lists every dish but no notice', () async {
      // Arrange
      final menu = _menu({
        _noticeHeading: [_allergenNotice],
        'Mains': [steak, salad],
      });
      classifier.respondWith(
        const MenuAnalysisFailed(reason: MenuAnalysisFailureReason.badResponse),
      );

      // Act
      await open(menu);

      // Assert
      expect(controller.analysis, isA<MenuAnalysisFailed>());
      expect(controller.visibleRows.map((row) => row.dish.id), [
        'steak',
        'salad',
      ]);
      expect(controller.restaurantNotices, [_allergenNotice]);
    });

    test('an unclassified name that is a notice is not an unclassified '
        'dish; a real one still is', () async {
      // Arrange: the model placed the steak and gave up on the other two.
      final menu = _menu({
        _noticeHeading: [_allergenNotice],
        'Mains': [steak, salad],
      });
      classifier.respondWith(
        MenuAnalysed(
          dishes: [_green(steak)],
          unclassified: [_allergenNotice.name, salad.name],
          engine: const LlmEngine(model: 'test-model'),
          analysedAt: DateTime.utc(2026),
        ),
      );

      // Act
      await open(menu);

      // Assert
      expect(controller.unclassifiedRows.map((row) => row.dish.id), ['salad']);
      expect(controller.unclassifiedNames, ['Salad']);
      expect(controller.unclassifiedCount, 1);
    });

    test('an unclassified name the menu does not hold keeps its bare '
        'row', () async {
      // Arrange
      final menu = _menu({
        'Mains': [steak],
      });
      classifier.respondWith(
        MenuAnalysed(
          dishes: [_green(steak)],
          unclassified: const ['Mystery dish'],
          engine: const LlmEngine(model: 'test-model'),
          analysedAt: DateTime.utc(2026),
        ),
      );

      // Act
      await open(menu);

      // Assert
      expect(controller.unclassifiedNames, ['Mystery dish']);
      expect(controller.unclassifiedCount, 1);
    });

    test('a menu with no notice is listed exactly as before', () async {
      // Arrange
      final menu = _menu({
        'Mains': [steak],
        'Salads': [salad],
      });

      // Act
      await open(menu);

      // Assert
      expect(controller.restaurantNotices, isEmpty);
      expect(controller.visibleCategories, ['Mains', 'Salads']);
      expect(controller.totalDishCount, 2);
    });

    test('there is no notice before a menu is loaded', () {
      // Assert
      expect(controller.restaurantNotices, isEmpty);
      expect(controller.totalDishCount, 0);
    });
  });
}
