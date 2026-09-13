import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/menu_controller.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';

/// The venue every test opens, unless a test builds its own.
const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

/// A minimal, valid [Dish] named [name].
Dish _dish(String name, {String id = 'd1'}) => Dish(
  id: id,
  name: name,
  description: '',
  price: 10,
  options: const <DishOption>[],
);

/// A minimal, valid [Menu] for [_ref], fetched at [fetchedAt], containing
/// [dishes] under one category.
Menu _menuOf(List<Dish> dishes, {DateTime? fetchedAt}) => Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: fetchedAt ?? DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(id: 'c1', name: 'Mains', dishes: dishes),
  ],
);

/// A verdict for [dish] with [verdict], defaulting its explanation, and
/// requiring [modification] only when [verdict] is
/// [DishVerdict.modifiable].
AnalysedDish _verdictFor(
  Dish dish,
  DishVerdict verdict, {
  String? modification,
}) => AnalysedDish(
  dishId: dish.id,
  name: dish.name,
  verdict: verdict,
  why: 'why',
  modification: modification,
);

void main() {
  group('MenuController', () {
    late FakeMenuRepository repository;
    late FakeMenuClassifier classifier;
    late FakeSettingsStore settings;
    late FakeClock clock;
    late MenuController controller;

    setUp(() {
      repository = FakeMenuRepository();
      classifier = FakeMenuClassifier();
      settings = FakeSettingsStore();
      clock = FakeClock(DateTime.utc(2026));
      controller = MenuController(repository, classifier, settings);
    });

    test(
      'open on success sets menu analysis and engine and toggles isLoading',
      () async {
        // Arrange
        final green = _dish('Steak');
        final menu = _menuOf([green]);
        repository.stub(_ref, MenuFetched(menu: menu));
        final analysis = MenuAnalysed(
          dishes: [_verdictFor(green, DishVerdict.orderAsIs)],
          unclassified: const <String>[],
          engine: const LlmEngine(model: 'test-model'),
          analysedAt: clock.now(),
        );
        classifier.respondWith(analysis);
        final loadingDuringOpen = <bool>[];
        controller.addListener(
          () => loadingDuringOpen.add(controller.isLoading),
        );

        // Act
        final future = controller.open(_ref);
        // The first notify (isLoading -> true) fires synchronously before
        // the first await suspends this test's own execution.
        expect(controller.isLoading, isTrue);
        await future;

        // Assert
        expect(loadingDuringOpen, [true, false]);
        expect(controller.isLoading, isFalse);
        expect(controller.menu, equals(menu));
        expect(controller.analysis, equals(analysis));
        expect(controller.engine, equals(const LlmEngine(model: 'test-model')));
        expect(
          repository.savedAnalyses,
          equals([(ref: _ref, analysis: analysis)]),
        );
      },
    );

    test('open on a failed fetch leaves menu null and sets fetchFailure '
        'and fetchStatusCode', () async {
      // Arrange
      repository.stub(
        _ref,
        const MenuFetchFailed(
          reason: MenuFetchFailureReason.notFound,
          statusCode: 404,
        ),
      );

      // Act
      await controller.open(_ref);

      // Assert
      expect(controller.menu, isNull);
      expect(controller.analysis, isNull);
      expect(controller.fetchFailure, MenuFetchFailureReason.notFound);
      expect(controller.fetchStatusCode, 404);
      expect(classifier.calls, isEmpty);
      expect(repository.savedAnalyses, isEmpty);
    });

    test('open when fetch succeeds but analysis fails still shows the '
        'raw menu', () async {
      // Arrange
      final menu = _menuOf([_dish('Steak')]);
      repository.stub(_ref, MenuFetched(menu: menu));
      const failure = MenuAnalysisFailed(
        reason: MenuAnalysisFailureReason.unauthorised,
      );
      classifier.respondWith(failure);

      // Act
      await controller.open(_ref);

      // Assert
      expect(controller.menu, equals(menu));
      expect(controller.analysis, equals(failure));
      expect(controller.engine, isNull);
      expect(controller.fetchFailure, isNull);
      expect(repository.savedAnalyses, isEmpty);
    });

    test('open on a cached result exposes isFromCache staleReason and '
        'cachedAt from Menu.fetchedAt', () async {
      // Arrange
      final fetchedAt = DateTime.utc(2025, 12);
      final menu = _menuOf([_dish('Steak')], fetchedAt: fetchedAt);
      repository.stub(
        _ref,
        MenuFetched(
          menu: menu,
          fromCache: true,
          staleReason: MenuFetchFailureReason.offline,
        ),
      );

      // Act
      await controller.open(_ref);

      // Assert
      expect(controller.isFromCache, isTrue);
      expect(controller.staleReason, MenuFetchFailureReason.offline);
      expect(controller.cachedAt, equals(fetchedAt));
    });

    test('cachedAt for a freshly fetched menu is null', () async {
      // Arrange
      final menu = _menuOf([_dish('Steak')]);
      repository.stub(_ref, MenuFetched(menu: menu));

      // Act
      await controller.open(_ref);

      // Assert
      expect(controller.isFromCache, isFalse);
      expect(controller.cachedAt, isNull);
    });

    test('visibleRows under greenOnly keeps only orderAsIs dishes', () async {
      // Arrange
      final green = _dish('Steak', id: 'green');
      final yellow = _dish('Fries', id: 'yellow');
      final red = _dish('Pasta', id: 'red');
      final unclassified = _dish('Mystery', id: 'unclassified');
      final menu = _menuOf([green, yellow, red, unclassified]);
      repository.stub(_ref, MenuFetched(menu: menu));
      classifier.respondWith(
        MenuAnalysed(
          dishes: [
            _verdictFor(green, DishVerdict.orderAsIs),
            _verdictFor(yellow, DishVerdict.modifiable, modification: 'x'),
            _verdictFor(red, DishVerdict.nonKeto),
          ],
          unclassified: const <String>['Mystery'],
          engine: const RulesEngine(
            reason: MenuAnalysisFailureReason.notConfigured,
          ),
          analysedAt: clock.now(),
        ),
      );
      await controller.open(_ref);

      // Act
      controller.setFilter(MenuFilter.greenOnly);

      // Assert
      expect(controller.visibleRows.map((row) => row.dish.id), ['green']);
      expect(controller.redRows.map((row) => row.dish.id), ['red']);
    });

    test(
      'visibleRows under greenAndYellow keeps orderAsIs and modifiable',
      () async {
        // Arrange
        final green = _dish('Steak', id: 'green');
        final yellow = _dish('Fries', id: 'yellow');
        final red = _dish('Pasta', id: 'red');
        final menu = _menuOf([green, yellow, red]);
        repository.stub(_ref, MenuFetched(menu: menu));
        classifier.respondWith(
          MenuAnalysed(
            dishes: [
              _verdictFor(green, DishVerdict.orderAsIs),
              _verdictFor(yellow, DishVerdict.modifiable, modification: 'x'),
              _verdictFor(red, DishVerdict.nonKeto),
            ],
            unclassified: const <String>[],
            engine: const RulesEngine(
              reason: MenuAnalysisFailureReason.notConfigured,
            ),
            analysedAt: clock.now(),
          ),
        );
        await controller.open(_ref);

        // Act
        controller.setFilter(MenuFilter.greenAndYellow);

        // Assert
        expect(controller.visibleRows.map((row) => row.dish.id).toSet(), {
          'green',
          'yellow',
        });
        expect(controller.redRows, isNotEmpty);
      },
    );

    test(
      'visibleRows under all adds unclassified dishes but never red ones',
      () async {
        // Arrange
        final green = _dish('Steak', id: 'green');
        final red = _dish('Pasta', id: 'red');
        final unclassified = _dish('Mystery', id: 'unclassified');
        final menu = _menuOf([green, red, unclassified]);
        repository.stub(_ref, MenuFetched(menu: menu));
        classifier.respondWith(
          MenuAnalysed(
            dishes: [
              _verdictFor(green, DishVerdict.orderAsIs),
              _verdictFor(red, DishVerdict.nonKeto),
            ],
            unclassified: const <String>['Mystery'],
            engine: const RulesEngine(
              reason: MenuAnalysisFailureReason.notConfigured,
            ),
            analysedAt: clock.now(),
          ),
        );
        await controller.open(_ref);

        // Act
        controller.setFilter(MenuFilter.all);

        // Assert
        expect(controller.visibleRows.map((row) => row.dish.id).toSet(), {
          'green',
          'unclassified',
        });
        expect(
          controller.visibleRows
              .firstWhere((row) => row.dish.id == 'unclassified')
              .analysis,
          isNull,
        );
        expect(
          controller.visibleRows.any((row) => row.dish.id == 'red'),
          isFalse,
        );
        expect(controller.redRows.map((row) => row.dish.id), ['red']);
      },
    );

    test('unclassifiedNames lists a dish analysis skipped with a null '
        'DishRow analysis', () async {
      // Arrange
      final seen = _dish('Mystery', id: 'seen');
      final menu = _menuOf([seen]);
      repository.stub(_ref, MenuFetched(menu: menu));
      classifier.respondWith(
        MenuAnalysed(
          dishes: const <AnalysedDish>[],
          unclassified: const <String>['Mystery'],
          engine: const RulesEngine(
            reason: MenuAnalysisFailureReason.notConfigured,
          ),
          analysedAt: clock.now(),
        ),
      );
      await controller.open(_ref);
      controller.setFilter(MenuFilter.all);

      // Act
      final rows = controller.visibleRows;

      // Assert
      expect(controller.unclassifiedNames, ['Mystery']);
      expect(rows.single.analysis, isNull);
    });

    test('setFilter notifies listeners and does not call the repository '
        'again', () async {
      // Arrange
      repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
      await controller.open(_ref);
      final loadCallsBefore = repository.loadCalls.length;
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);
      expect(notifyCount, 0);

      // Act
      controller.setFilter(MenuFilter.all);

      // Assert
      expect(controller.filter, MenuFilter.all);
      expect(notifyCount, 1);
      expect(repository.loadCalls.length, loadCallsBefore);
    });

    test('open reads the default filter from SettingsStore', () async {
      // Arrange
      settings = FakeSettingsStore(
        initial: const AppSettings(filter: MenuFilter.greenOnly),
      );
      controller = MenuController(repository, classifier, settings);
      repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));

      // Act
      await controller.open(_ref);

      // Assert
      expect(controller.filter, MenuFilter.greenOnly);
    });

    test('open passes estimationConsentGiven from SettingsStore into '
        'ClassificationOptions', () async {
      // Arrange
      settings = FakeSettingsStore(
        initial: const AppSettings(estimationConsentGiven: true),
      );
      controller = MenuController(repository, classifier, settings);
      repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));

      // Act
      await controller.open(_ref);

      // Assert
      expect(classifier.calls, hasLength(1));
      expect(
        classifier.calls.single.$2,
        equals(const ClassificationOptions(estimationConsentGiven: true)),
      );
    });

    test(
      'open notifies listeners exactly twice on a full round trip',
      () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        // Act
        await controller.open(_ref);

        // Assert
        expect(notifyCount, 2);
      },
    );

    test('open notifies listeners exactly twice on a failed fetch', () async {
      // Arrange
      repository.stub(
        _ref,
        const MenuFetchFailed(reason: MenuFetchFailureReason.offline),
      );
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      // Act
      await controller.open(_ref);

      // Assert
      expect(notifyCount, 2);
    });

    test(
      'visibleRows returns every dish unjudged when the analysis failed',
      () async {
        // Arrange: a menu that fetched fine but could not be classified.
        final menu = _menuOf([_dish('Entrecote'), _dish('Pizza', id: 'd2')]);
        repository.stub(_ref, MenuFetched(menu: menu));
        classifier.respondWith(
          const MenuAnalysisFailed(
            reason: MenuAnalysisFailureReason.badResponse,
          ),
        );

        // Act
        await controller.open(_ref);

        // Assert: a filter selects verdicts, and there are none to select, so
        // applying it would hand the user an empty menu. §6.6 forbids letting
        // a failed analysis cost the menu itself.
        expect(controller.filter, MenuFilter.greenAndYellow);
        expect(controller.visibleRows, hasLength(2));
        expect(controller.visibleRows.every((r) => r.analysis == null), isTrue);
        expect(controller.menu, isNotNull);
      },
    );

    test('visibleRows and redRows before any open are empty, not a crash', () {
      // Arrange: nothing opened yet.

      // Act
      final visible = controller.visibleRows;
      final red = controller.redRows;
      final unclassified = controller.unclassifiedNames;

      // Assert
      expect(visible, isEmpty);
      expect(red, isEmpty);
      expect(unclassified, isEmpty);
      expect(controller.engine, isNull);
    });
  });
}
