import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/utils/constants.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_menu_cache.dart';
import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_platform_menu_adapter.dart';
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
    late FakeNotesStore notes;
    late FakeClock clock;
    late MenuController controller;

    setUp(() {
      repository = FakeMenuRepository();
      classifier = FakeMenuClassifier();
      settings = FakeSettingsStore();
      notes = FakeNotesStore();
      clock = FakeClock(DateTime.utc(2026));
      controller = MenuController(repository, classifier, settings, notes);
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

        // Assert: fetching, then classifying, then done (issue #65).
        expect(loadingDuringOpen, [true, true, false]);
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
        reason: MenuAnalysisFailureReason.noDishesFound,
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
      expect(controller.fetchedAt, equals(fetchedAt));
    });

    test('cachedAt for a freshly fetched menu is null, but fetchedAt is '
        'still set from Menu.fetchedAt', () async {
      // Arrange
      final fetchedAt = DateTime.utc(2026, 3, 1, 12);
      final menu = _menuOf([_dish('Steak')], fetchedAt: fetchedAt);
      repository.stub(_ref, MenuFetched(menu: menu));

      // Act
      await controller.open(_ref);

      // Assert: cachedAt is only for a stale-served menu, but the source
      // line ("Wolt · 4 min ago") needs a timestamp on a fresh fetch too.
      expect(controller.isFromCache, isFalse);
      expect(controller.cachedAt, isNull);
      expect(controller.fetchedAt, equals(fetchedAt));
    });

    test('fetchedAt and venueName are null before anything is opened', () {
      // Assert
      expect(controller.fetchedAt, isNull);
      expect(controller.venueName, isNull);
    });

    test('venueName reflects Menu.venueName, including when the platform '
        'did not supply one', () async {
      // Arrange: the fixture menu built by _menuOf never sets venueName.
      final menu = _menuOf([_dish('Steak')]);
      repository.stub(_ref, MenuFetched(menu: menu));

      // Act
      await controller.open(_ref);

      // Assert
      expect(controller.venueName, isNull);
    });

    test('venueName is exposed when the menu carries one', () async {
      // Arrange
      final menu = Menu(
        venueRef: _ref,
        currency: 'ILS',
        fetchedAt: DateTime.utc(2026),
        categories: const <MenuCategory>[],
        venueName: 'Sunny Diner',
      );
      repository.stub(_ref, MenuFetched(menu: menu));

      // Act
      await controller.open(_ref);

      // Assert
      expect(controller.venueName, equals('Sunny Diner'));
    });

    test('verdict counts and ketoScoreOutOfTen are all zero-ish before '
        'any open', () {
      // Assert
      expect(controller.greenCount, 0);
      expect(controller.yellowCount, 0);
      expect(controller.redCount, 0);
      expect(controller.unclassifiedCount, 0);
      expect(controller.totalDishCount, 0);
      expect(controller.ketoScoreOutOfTen, isNull);
    });

    test('verdict counts and ketoScoreOutOfTen reflect a MenuAnalysed '
        'result, not the active filter', () async {
      // Arrange: two green, one yellow, one red, one unclassified — the
      // filter is narrowed to greenOnly afterwards to prove the counts
      // are unaffected by it.
      final green1 = _dish('Steak', id: 'green1');
      final green2 = _dish('Chicken', id: 'green2');
      final yellow = _dish('Fries', id: 'yellow');
      final red = _dish('Pasta', id: 'red');
      final unclassified = _dish('Mystery', id: 'unclassified');
      final menu = _menuOf([green1, green2, yellow, red, unclassified]);
      repository.stub(_ref, MenuFetched(menu: menu));
      classifier.respondWith(
        MenuAnalysed(
          dishes: [
            _verdictFor(green1, DishVerdict.orderAsIs),
            _verdictFor(green2, DishVerdict.orderAsIs),
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
      expect(controller.greenCount, 2);
      expect(controller.yellowCount, 1);
      expect(controller.redCount, 1);
      expect(controller.unclassifiedCount, 1);
      expect(controller.totalDishCount, 5);
      // score = 10 * (2 + 0.5 * 1) / (2 + 1 + 1) = 6.25 -> 6.3
      expect(controller.ketoScoreOutOfTen, equals(6.3));
    });

    test('verdict counts are all zero when analysis failed, even though '
        'the raw menu is still there', () async {
      // Arrange
      final menu = _menuOf([_dish('Steak'), _dish('Pizza', id: 'd2')]);
      repository.stub(_ref, MenuFetched(menu: menu));
      classifier.respondWith(
        const MenuAnalysisFailed(reason: MenuAnalysisFailureReason.badResponse),
      );

      // Act
      await controller.open(_ref);

      // Assert
      expect(controller.totalDishCount, 2);
      expect(controller.greenCount, 0);
      expect(controller.yellowCount, 0);
      expect(controller.redCount, 0);
      expect(controller.unclassifiedCount, 0);
      expect(controller.ketoScoreOutOfTen, isNull);
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
    });

    test('visibleRows under yellowOnly keeps only modifiable dishes', () async {
      // Arrange: issue #29's "With changes" tile.
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
      controller.setFilter(MenuFilter.yellowOnly);

      // Assert
      expect(controller.visibleRows.map((row) => row.dish.id), ['yellow']);
    });

    test('visibleRows under redOnly keeps only nonKeto dishes — issue #29 '
        "replaces the old always-shown collapsed group with this tile's own "
        'filter state', () async {
      // Arrange
      final green = _dish('Steak', id: 'green');
      final red = _dish('Pasta', id: 'red');
      final menu = _menuOf([green, red]);
      repository.stub(_ref, MenuFetched(menu: menu));
      classifier.respondWith(
        MenuAnalysed(
          dishes: [
            _verdictFor(green, DishVerdict.orderAsIs),
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
      controller.setFilter(MenuFilter.redOnly);

      // Assert
      expect(controller.visibleRows.map((row) => row.dish.id), ['red']);
    });

    test('visibleRows under greenAndYellow keeps orderAsIs and modifiable — '
        'unreachable from either filter control now, but still a valid, '
        'correctly-handled value for a filter already persisted before '
        'issue #29', () async {
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
    });

    test(
      'visibleRows under all adds unclassified and red dishes alike — '
      'issue #29 draws no distinction between verdicts under "all"',
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
          'red',
          'unclassified',
        });
        expect(
          controller.visibleRows
              .firstWhere((row) => row.dish.id == 'unclassified')
              .analysis,
          isNull,
        );
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
      controller = MenuController(repository, classifier, settings, notes);
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
      controller = MenuController(repository, classifier, settings, notes);
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

    test('open notifies listeners exactly three times on a full round trip '
        'with a classifier that announces no engine — fetching, '
        'classifying, done (issue #65)', () async {
      // Arrange
      repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      // Act
      await controller.open(_ref);

      // Assert
      expect(notifyCount, 3);
    });

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
        expect(controller.filter, MenuFilter.all);
        expect(controller.visibleRows, hasLength(2));
        expect(controller.visibleRows.every((r) => r.analysis == null), isTrue);
        expect(controller.menu, isNotNull);
      },
    );

    test('visibleRows before any open is empty, not a crash', () {
      // Arrange: nothing opened yet.

      // Act
      final visible = controller.visibleRows;
      final unclassified = controller.unclassifiedNames;

      // Assert
      expect(visible, isEmpty);
      expect(unclassified, isEmpty);
      expect(controller.engine, isNull);
    });

    group('refresh (issue #49)', () {
      test('refresh before any open is a no-op: no repository call and no '
          'notification', () async {
        // Arrange
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        // Act
        await controller.refresh();

        // Assert
        expect(repository.loadCalls, isEmpty);
        expect(notifyCount, 0);
        expect(controller.menu, isNull);
      });

      test('refresh with an unchanged dish-text fingerprint keeps the '
          'existing analysis and calls the classifier zero times', () async {
        // Arrange: open with one menu and a scripted analysis.
        final dish = _dish('Steak');
        final firstFetchedAt = DateTime.utc(2026);
        repository.stub(
          _ref,
          MenuFetched(menu: _menuOf([dish], fetchedAt: firstFetchedAt)),
        );
        final firstAnalysis = MenuAnalysed(
          dishes: [_verdictFor(dish, DishVerdict.orderAsIs)],
          unclassified: const <String>[],
          engine: const LlmEngine(model: 'test-model'),
          analysedAt: clock.now(),
        );
        classifier.respondWith(firstAnalysis);
        await controller.open(_ref);
        expect(classifier.calls, hasLength(1));

        // Arrange: a refetch whose dish text is identical (only fetchedAt
        // moves forward) — the normalised fingerprint does not change.
        final secondFetchedAt = DateTime.utc(2026, 1, 2);
        repository.stub(
          _ref,
          MenuFetched(menu: _menuOf([dish], fetchedAt: secondFetchedAt)),
        );

        // Act
        await controller.refresh();

        // Assert: no second classifier call, the old analysis is kept
        // verbatim, and only fetchedAt moved forward.
        expect(classifier.calls, hasLength(1));
        expect(controller.analysis, same(firstAnalysis));
        expect(controller.fetchedAt, equals(secondFetchedAt));
        expect(
          repository.loadCalls.last,
          equals((ref: _ref, forceRefresh: true)),
        );
      });

      test('refresh with an unchanged fingerprint still reclassifies when '
          'the net-carb limit changed since open (issue #57)', () async {
        // Arrange: open under the default limit; the fake records it.
        final dish = _dish('Steak');
        repository.stub(_ref, MenuFetched(menu: _menuOf([dish])));
        await controller.open(_ref);
        expect(classifier.calls, hasLength(1));

        // Arrange: the user raises the limit, then pulls to refresh an
        // unchanged menu.
        await settings.write(const AppSettings(netCarbLimitGrams: 12));

        // Act
        await controller.refresh();

        // Assert
        expect(classifier.calls, hasLength(2));
        expect(classifier.calls.last.$2.netCarbLimitGrams, equals(12));
        expect(controller.netCarbLimitGrams, equals(12));
      });

      test('refresh with a changed dish-text fingerprint reclassifies and '
          'persists the new analysis', () async {
        // Arrange
        final oldDish = _dish('Steak');
        repository.stub(_ref, MenuFetched(menu: _menuOf([oldDish])));
        final oldAnalysis = MenuAnalysed(
          dishes: [_verdictFor(oldDish, DishVerdict.orderAsIs)],
          unclassified: const <String>[],
          engine: const LlmEngine(model: 'test-model'),
          analysedAt: clock.now(),
        );
        classifier.respondWith(oldAnalysis);
        await controller.open(_ref);

        // Arrange: a refetch with a different dish name — a changed
        // fingerprint — and a new scripted analysis to match it.
        final newDish = _dish('Chicken');
        repository.stub(_ref, MenuFetched(menu: _menuOf([newDish])));
        final newAnalysis = MenuAnalysed(
          dishes: [_verdictFor(newDish, DishVerdict.orderAsIs)],
          unclassified: const <String>[],
          engine: const LlmEngine(model: 'test-model'),
          analysedAt: clock.now(),
        );
        classifier.respondWith(newAnalysis);

        // Act
        await controller.refresh();

        // Assert: a second classifier call over the new menu, and the new
        // analysis both shown and persisted.
        expect(classifier.calls, hasLength(2));
        expect(classifier.calls.last.$1, equals(_menuOf([newDish])));
        expect(controller.analysis, equals(newAnalysis));
        expect(
          repository.savedAnalyses.last,
          equals((ref: _ref, analysis: newAnalysis)),
        );
      });

      test('refresh on a failed fetch keeps the previously shown menu and '
          'analysis, and surfaces the reason as staleReason', () async {
        // Arrange
        final dish = _dish('Steak');
        final menu = _menuOf([dish]);
        repository.stub(_ref, MenuFetched(menu: menu));
        final analysis = MenuAnalysed(
          dishes: [_verdictFor(dish, DishVerdict.orderAsIs)],
          unclassified: const <String>[],
          engine: const LlmEngine(model: 'test-model'),
          analysedAt: clock.now(),
        );
        classifier.respondWith(analysis);
        await controller.open(_ref);

        // Arrange: the refresh's fetch fails outright (no adapter success,
        // nothing cached to fall back to).
        repository.stub(
          _ref,
          const MenuFetchFailed(reason: MenuFetchFailureReason.offline),
        );

        // Act
        await controller.refresh();

        // Assert: the menu and analysis already on screen are untouched.
        expect(controller.menu, equals(menu));
        expect(controller.analysis, equals(analysis));
        expect(controller.staleReason, MenuFetchFailureReason.offline);
        expect(controller.isFromCache, isTrue);
        expect(classifier.calls, hasLength(1));
      });

      test('refresh toggles isLoading and notifies listeners exactly '
          'twice', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        await controller.open(_ref);
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);
        final loadingDuringRefresh = <bool>[];
        controller.addListener(
          () => loadingDuringRefresh.add(controller.isLoading),
        );

        // Act
        final future = controller.refresh();
        expect(controller.isLoading, isTrue);
        await future;

        // Assert
        expect(notifyCount, 2);
        expect(loadingDuringRefresh, [true, false]);
        expect(controller.isLoading, isFalse);
      });

      test('refresh on a fetch that falls back to a stale cached menu — '
          'the ordinary path load itself takes on an adapter failure — '
          'still reclassifies when the served menu changed and updates '
          'isFromCache/staleReason from the result', () async {
        // Arrange
        final oldDish = _dish('Steak');
        repository.stub(_ref, MenuFetched(menu: _menuOf([oldDish])));
        classifier.respondWith(
          MenuAnalysed(
            dishes: [_verdictFor(oldDish, DishVerdict.orderAsIs)],
            unclassified: const <String>[],
            engine: const LlmEngine(model: 'test-model'),
            analysedAt: clock.now(),
          ),
        );
        await controller.open(_ref);

        // Arrange: load() itself served a stale cached menu with a
        // different dish (e.g. cached before the network failed) — the
        // fromCache/staleReason branch of MenuFetched, not
        // MenuFetchFailed.
        final newDish = _dish('Chicken');
        repository.stub(
          _ref,
          MenuFetched(
            menu: _menuOf([newDish]),
            fromCache: true,
            staleReason: MenuFetchFailureReason.offline,
          ),
        );
        final newAnalysis = MenuAnalysed(
          dishes: [_verdictFor(newDish, DishVerdict.orderAsIs)],
          unclassified: const <String>[],
          engine: const LlmEngine(model: 'test-model'),
          analysedAt: clock.now(),
        );
        classifier.respondWith(newAnalysis);

        // Act
        await controller.refresh();

        // Assert
        expect(controller.isFromCache, isTrue);
        expect(controller.staleReason, MenuFetchFailureReason.offline);
        expect(controller.analysis, equals(newAnalysis));
      });
    });

    group('load phase (issue #65)', () {
      /// Every [LoadPhase] [controller] notifies with, in order.
      List<LoadPhase> recordPhases() {
        final phases = <LoadPhase>[];
        controller.addListener(() => phases.add(controller.phase));
        return phases;
      }

      test('phase is idle before anything is opened', () {
        // Assert
        expect(controller.phase, LoadPhase.idle);
        expect(controller.isLoading, isFalse);
      });

      test('open with a classifier that announces no engine moves through '
          'fetching and classifying back to idle', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        final phases = recordPhases();

        // Act
        await controller.open(_ref);

        // Assert
        expect(phases, [
          LoadPhase.fetching,
          LoadPhase.classifying,
          LoadPhase.idle,
        ]);
      });

      test('open moves to classifyingLlm when the AI engine announces '
          'itself', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        classifier.announces = const [ClassifyingEngine.llm];
        final phases = recordPhases();

        // Act
        await controller.open(_ref);

        // Assert
        expect(phases, [
          LoadPhase.fetching,
          LoadPhase.classifying,
          LoadPhase.classifyingLlm,
          LoadPhase.idle,
        ]);
      });

      test('open moves to classifyingRules when only the rules engine '
          'announces itself', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        classifier.announces = const [ClassifyingEngine.rules];
        final phases = recordPhases();

        // Act
        await controller.open(_ref);

        // Assert
        expect(phases, [
          LoadPhase.fetching,
          LoadPhase.classifying,
          LoadPhase.classifyingRules,
          LoadPhase.idle,
        ]);
      });

      test('open reads an AI call that fell back as classifyingLlm then '
          'classifyingRules', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        classifier.announces = const [
          ClassifyingEngine.llm,
          ClassifyingEngine.rules,
        ];
        final phases = recordPhases();

        // Act
        await controller.open(_ref);

        // Assert
        expect(phases, [
          LoadPhase.fetching,
          LoadPhase.classifying,
          LoadPhase.classifyingLlm,
          LoadPhase.classifyingRules,
          LoadPhase.idle,
        ]);
      });

      test('the same engine announced twice notifies only once', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        classifier.announces = const [
          ClassifyingEngine.rules,
          ClassifyingEngine.rules,
        ];
        final phases = recordPhases();

        // Act
        await controller.open(_ref);

        // Assert
        expect(
          phases.where((phase) => phase == LoadPhase.classifyingRules),
          hasLength(1),
        );
      });

      test('while the engine runs the menu is shown unjudged and isLoading '
          'is true', () async {
        // Arrange: the previous venue's analysis must not linger on the
        // new menu while it is being classified.
        final menu = _menuOf([_dish('Steak')]);
        repository.stub(_ref, MenuFetched(menu: menu));
        await controller.open(_ref);
        expect(controller.analysis, isA<MenuAnalysed>());
        final gate = Completer<void>();
        classifier
          ..announces = const [ClassifyingEngine.llm]
          ..gate = gate.future;

        // Act
        final future = controller.open(_ref);
        await pumpEventQueue();

        // Assert
        expect(controller.phase, LoadPhase.classifyingLlm);
        expect(controller.isLoading, isTrue);
        expect(controller.menu, equals(menu));
        expect(controller.analysis, isNull);
        expect(controller.visibleRows, hasLength(1));

        gate.complete();
        await future;
        expect(controller.phase, LoadPhase.idle);
        expect(controller.analysis, isA<MenuAnalysed>());
      });

      test('open on a failed fetch never enters a classifying phase', () async {
        // Arrange
        repository.stub(
          _ref,
          const MenuFetchFailed(reason: MenuFetchFailureReason.offline),
        );
        final phases = recordPhases();

        // Act
        await controller.open(_ref);

        // Assert
        expect(phases, [LoadPhase.fetching, LoadPhase.idle]);
      });

      test('open hands the classifier an onEngineStarted listener', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));

        // Act
        await controller.open(_ref);

        // Assert
        expect(classifier.calls.single.$2.onEngineStarted, isNotNull);
      });

      test('an announcement arriving after the load finished is ignored '
          'and does not notify', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        await controller.open(_ref);
        final lateListener = classifier.calls.single.$2.onEngineStarted!;
        final phases = recordPhases();

        // Act
        lateListener(ClassifyingEngine.llm);

        // Assert
        expect(controller.phase, LoadPhase.idle);
        expect(phases, isEmpty);
      });

      test('refresh with a changed fingerprint moves through the '
          'classifying phases', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        await controller.open(_ref);
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Salmon')])));
        classifier.announces = const [ClassifyingEngine.rules];
        final phases = recordPhases();

        // Act
        await controller.refresh();

        // Assert
        expect(phases, [
          LoadPhase.fetching,
          LoadPhase.classifying,
          LoadPhase.classifyingRules,
          LoadPhase.idle,
        ]);
      });

      test('refresh with an unchanged fingerprint never enters a '
          'classifying phase', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        await controller.open(_ref);
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        final phases = recordPhases();

        // Act
        await controller.refresh();

        // Assert
        expect(phases, [LoadPhase.fetching, LoadPhase.idle]);
      });

      test('isClassifying is true for exactly the three classifying '
          'phases', () {
        // Act
        final classifying = LoadPhase.values.where((p) => p.isClassifying);

        // Assert
        expect(classifying, [
          LoadPhase.classifying,
          LoadPhase.classifyingLlm,
          LoadPhase.classifyingRules,
        ]);
      });
    });

    group('reanalyse (issue #68)', () {
      test('reanalyse before any open is a no-op: no repository call, no '
          'classifier call, and no notification', () async {
        // Arrange
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        // Act
        await controller.reanalyse();

        // Assert
        expect(repository.loadCalls, isEmpty);
        expect(classifier.calls, isEmpty);
        expect(notifyCount, 0);
      });

      test('reanalyse re-runs the classifier on the loaded menu without a '
          'second repository.load call', () async {
        // Arrange
        final dish = _dish('Steak');
        repository.stub(_ref, MenuFetched(menu: _menuOf([dish])));
        classifier.respondWith(
          const MenuAnalysisFailed(reason: MenuAnalysisFailureReason.timeout),
        );
        await controller.open(_ref);
        expect(classifier.calls, hasLength(1));
        final loadCallsBefore = repository.loadCalls.length;

        // Arrange: the retry succeeds this time.
        final newAnalysis = MenuAnalysed(
          dishes: [_verdictFor(dish, DishVerdict.orderAsIs)],
          unclassified: const <String>[],
          engine: const LlmEngine(model: 'test-model'),
          analysedAt: clock.now(),
        );
        classifier.respondWith(newAnalysis);

        // Act
        await controller.reanalyse();

        // Assert: reclassified, no new fetch, and the fresh analysis is
        // both shown and persisted.
        expect(repository.loadCalls.length, equals(loadCallsBefore));
        expect(classifier.calls, hasLength(2));
        expect(classifier.calls.last.$1, equals(_menuOf([dish])));
        expect(controller.analysis, equals(newAnalysis));
        expect(
          repository.savedAnalyses.last,
          equals((ref: _ref, analysis: newAnalysis)),
        );
      });

      test('reanalyse reads the current settings, so a changed net-carb '
          'limit reaches the classifier (issue #57)', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        await controller.open(_ref);
        await settings.write(const AppSettings(netCarbLimitGrams: 15));

        // Act
        await controller.reanalyse();

        // Assert
        expect(classifier.calls.last.$2.netCarbLimitGrams, equals(15));
      });

      test('reanalyse does not persist a still-failed analysis', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        classifier.respondWith(
          const MenuAnalysisFailed(
            reason: MenuAnalysisFailureReason.badResponse,
          ),
        );
        await controller.open(_ref);

        // Act
        await controller.reanalyse();

        // Assert
        expect(controller.analysis, isA<MenuAnalysisFailed>());
        expect(repository.savedAnalyses, isEmpty);
      });

      test('reanalyse toggles isLoading and notifies listeners exactly '
          'twice', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        await controller.open(_ref);
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);
        final loadingDuringReanalyse = <bool>[];
        controller.addListener(
          () => loadingDuringReanalyse.add(controller.isLoading),
        );

        // Act
        final future = controller.reanalyse();
        expect(controller.isLoading, isTrue);
        await future;

        // Assert
        expect(notifyCount, 2);
        expect(loadingDuringReanalyse, [true, false]);
        expect(controller.isLoading, isFalse);
      });
    });

    group('personal notes (issue #52)', () {
      test('noteFor returns null before anything is opened', () {
        // Assert
        expect(controller.noteFor('d1'), isNull);
      });

      test('open loads any notes already stored for that venue', () async {
        // Arrange
        await notes.write(_ref, 'd1', 'Ask for no cheese.');
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));

        // Act
        await controller.open(_ref);

        // Assert
        expect(controller.noteFor('d1'), equals('Ask for no cheese.'));
      });

      test('setNote writes through the store and updates noteFor '
          'immediately', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        await controller.open(_ref);

        // Act
        await controller.setNote(
          'd1',
          'Waitstaff happily substituted '
              'cauliflower.',
        );

        // Assert
        expect(
          controller.noteFor('d1'),
          equals('Waitstaff happily substituted cauliflower.'),
        );
        expect(
          await notes.read(_ref, 'd1'),
          equals('Waitstaff happily substituted cauliflower.'),
        );
      });

      test('setNote trims the note before storing it', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        await controller.open(_ref);

        // Act
        await controller.setNote('d1', '  spaced out note  ');

        // Assert
        expect(controller.noteFor('d1'), equals('spaced out note'));
      });

      test('setNote notifies listeners', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        await controller.open(_ref);
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        // Act
        await controller.setNote('d1', 'A note.');

        // Assert
        expect(notifyCount, 1);
      });

      test('setNote with a blank note clears it instead of storing an '
          'empty string', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        await controller.open(_ref);
        await controller.setNote('d1', 'First.');

        // Act
        await controller.setNote('d1', '   ');

        // Assert
        expect(controller.noteFor('d1'), isNull);
        expect(await notes.read(_ref, 'd1'), isNull);
      });

      test('clearNote removes the note through the store and from '
          'noteFor', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        await controller.open(_ref);
        await controller.setNote('d1', 'A note.');

        // Act
        await controller.clearNote('d1');

        // Assert
        expect(controller.noteFor('d1'), isNull);
        expect(await notes.read(_ref, 'd1'), isNull);
      });

      test('clearNote on a dish with no note is a no-op, including no '
          'notify', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        await controller.open(_ref);
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        // Act
        await controller.clearNote('never_noted');

        // Assert
        expect(notifyCount, 0);
        expect(notes.deleteCalls, isEmpty);
      });

      test('setNote and clearNote before any open are no-ops, not a '
          'crash', () async {
        // Act & Assert
        await expectLater(controller.setNote('d1', 'x'), completes);
        await expectLater(controller.clearNote('d1'), completes);
        expect(controller.noteFor('d1'), isNull);
        expect(notes.writeCalls, isEmpty);
      });

      test('notes are scoped per venue: opening a second venue does not '
          "carry the first venue's notes over", () async {
        // Arrange
        const otherRef = VenueRef(source: MenuSource.wolt, platformId: 'v2');
        repository
          ..stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])))
          ..stub(otherRef, MenuFetched(menu: _menuOf([_dish('Fish')])));
        await controller.open(_ref);
        await controller.setNote('d1', 'For venue one.');

        // Act
        await controller.open(otherRef);

        // Assert
        expect(controller.noteFor('d1'), isNull);
      });
    });
  });

  // Issue #29 adds MenuFilter.yellowOnly and MenuFilter.redOnly. Placed
  // here rather than in a `services/storage` test file (this file's own
  // ownership boundary for this issue) because `MenuController.open`
  // reads exactly this decoding path through its `SettingsStore` — a
  // regression here is a regression in what this controller reads on
  // every launch.
  group('AppSettings filter decoding (issue #29)', () {
    Map<String, Object?> settingsJson(String filter) => <String, Object?>{
      'languageTag': null,
      'filter': filter,
      'estimationConsentGiven': false,
      'lastVenue': null,
    };

    test('every current MenuFilter name, old and new, round-trips through '
        'AppSettings.tryFrom', () {
      for (final filter in MenuFilter.values) {
        // Act
        final decoded = AppSettings.tryFrom(settingsJson(filter.name));

        // Assert
        expect(decoded?.filter, filter, reason: 'for ${filter.name}');
      }
    });

    test('a filter name AppSettings.tryFrom does not recognise degrades to '
        'null rather than throwing — the case a stored value from a future '
        'or corrupted format would hit', () {
      // Act
      final decoded = AppSettings.tryFrom(settingsJson('somethingUnknown'));

      // Assert: PrefsSettingsStore.read() treats a null tryFrom result as
      // "use defaults" (architecture.md §6.4), so this is what keeps a
      // stored value it no longer recognises from crashing the app.
      expect(decoded, isNull);
    });
  });

  // Issue #57: the cached analysis records the options it was made with,
  // and a mismatch on open re-analyses. Driven through the real
  // CachedMenuRepository over a FakeMenuCache, so the analysis the second
  // open finds is the one the first open actually persisted.
  group('MenuController options invalidation (issue #57)', () {
    final steak = _dish('Steak');
    final menu = _menuOf([steak]);

    late FakeMenuCache cache;
    late FakePlatformMenuAdapter adapter;
    late CachedMenuRepository repository;
    late FakeMenuClassifier classifier;
    late FakeSettingsStore settings;
    late MenuController controller;

    setUp(() {
      cache = FakeMenuCache();
      adapter = FakePlatformMenuAdapter()..queueFetched(menu);
      repository = CachedMenuRepository(
        adapters: [adapter],
        cache: cache,
        // Same instant as the menu's fetchedAt, so the second open is a
        // fresh cache hit and the menu itself is not refetched.
        clock: FakeClock(DateTime.utc(2026)),
      );
      classifier = FakeMenuClassifier()
        ..derivedEngine = const LlmEngine(model: 'served-model');
      settings = FakeSettingsStore(
        initial: const AppSettings(estimationConsentGiven: true),
      );
      controller = MenuController(
        repository,
        classifier,
        settings,
        FakeNotesStore(),
      );
    });

    test('open passes the stored limit to the classifier', () async {
      // Arrange
      await settings.write(
        const AppSettings(estimationConsentGiven: true, netCarbLimitGrams: 9),
      );

      // Act
      await controller.open(_ref);

      // Assert
      expect(classifier.calls.single.$2.netCarbLimitGrams, equals(9));
      expect(classifier.calls.single.$2.estimationConsentGiven, isTrue);
    });

    test('an unchanged limit reuses the cached analysis on the next open, '
        'spending no classifier call', () async {
      // Arrange
      await controller.open(_ref);
      final first = controller.analysis;

      // Act
      final reopened = MenuController(
        repository,
        classifier,
        settings,
        FakeNotesStore(),
      );
      await reopened.open(_ref);

      // Assert
      expect(classifier.calls, hasLength(1));
      expect(reopened.analysis, equals(first));
      expect(
        (reopened.analysis! as MenuAnalysed).options,
        equals(const AnalysisOptionsSnapshot(netCarbLimitGrams: 6)),
      );
    });

    test('a changed limit re-analyses on the next open under the new '
        'limit, and caches the new result with it', () async {
      // Arrange
      await controller.open(_ref);
      await settings.write(
        const AppSettings(estimationConsentGiven: true, netCarbLimitGrams: 9),
      );

      // Act
      final reopened = MenuController(
        repository,
        classifier,
        settings,
        FakeNotesStore(),
      );
      await reopened.open(_ref);

      // Assert
      expect(classifier.calls, hasLength(2));
      expect(classifier.calls.last.$2.netCarbLimitGrams, equals(9));
      expect(reopened.netCarbLimitGrams, equals(9));
      final cached = await cache.read(_ref);
      expect(
        (cached!.analysis! as MenuAnalysed).options?.netCarbLimitGrams,
        equals(9),
      );
    });

    test('changing the limit back reuses nothing stale: the 9 g result is '
        'replaced when the user returns to 6 g', () async {
      // Arrange
      await settings.write(
        const AppSettings(estimationConsentGiven: true, netCarbLimitGrams: 9),
      );
      await controller.open(_ref);
      await settings.write(const AppSettings(estimationConsentGiven: true));

      // Act
      await controller.open(_ref);

      // Assert
      expect(classifier.calls, hasLength(2));
      expect(
        classifier.calls.last.$2.netCarbLimitGrams,
        equals(defaultNetCarbLimitGrams),
      );
    });

    test('a rules-engine result is never reused: the heuristic is free and '
        'the LLM may be reachable now', () async {
      // Arrange
      classifier.derivedEngine = const RulesEngine(
        reason: MenuAnalysisFailureReason.offline,
      );
      await controller.open(_ref);

      // Act
      await controller.open(_ref);

      // Assert
      expect(classifier.calls, hasLength(2));
    });

    test(
      'a cached LLM result is not reused once consent is withdrawn',
      () async {
        // Arrange
        await controller.open(_ref);
        await settings.write(const AppSettings());

        // Act
        await controller.open(_ref);

        // Assert
        expect(classifier.calls, hasLength(2));
        expect(classifier.calls.last.$2.estimationConsentGiven, isFalse);
      },
    );

    test('netCarbLimitGrams is the default before any analysis', () {
      // Assert
      expect(controller.netCarbLimitGrams, equals(defaultNetCarbLimitGrams));
    });
  });

  group('MenuController reuse checks against the cached entry', () {
    final steak = _dish('Steak');
    final menu = _menuOf([steak]);

    /// An LLM analysis of [menu] recording [options], as a cache would
    /// hold it.
    MenuAnalysed llmAnalysis({AnalysisOptionsSnapshot? options}) =>
        MenuAnalysed(
          dishes: [_verdictFor(steak, DishVerdict.orderAsIs)],
          unclassified: const <String>[],
          engine: const LlmEngine(model: 'served-model'),
          analysedAt: DateTime.utc(2026),
          options: options,
        );

    late FakeMenuRepository repository;
    late FakeMenuClassifier classifier;
    late FakeSettingsStore settings;
    late MenuController controller;

    setUp(() {
      repository = FakeMenuRepository()
        ..stub(_ref, MenuFetched(menu: menu, fromCache: true));
      classifier = FakeMenuClassifier();
      settings = FakeSettingsStore(
        initial: const AppSettings(estimationConsentGiven: true),
      );
      controller = MenuController(
        repository,
        classifier,
        settings,
        FakeNotesStore(),
      );
    });

    test('an analysis cached before issue #57, with no options, is reused '
        'at the default limit it was made under', () async {
      // Arrange
      final legacy = llmAnalysis();
      repository.seedCache(CachedMenu(menu: menu, analysis: legacy));

      // Act
      await controller.open(_ref);

      // Assert
      expect(classifier.calls, isEmpty);
      expect(controller.analysis, equals(legacy));
      expect(controller.netCarbLimitGrams, equals(defaultNetCarbLimitGrams));
    });

    test('an analysis cached before issue #57 is re-analysed once the '
        'user has chosen another limit', () async {
      // Arrange
      repository.seedCache(CachedMenu(menu: menu, analysis: llmAnalysis()));
      await settings.write(
        const AppSettings(estimationConsentGiven: true, netCarbLimitGrams: 4),
      );

      // Act
      await controller.open(_ref);

      // Assert
      expect(classifier.calls, hasLength(1));
      expect(classifier.calls.single.$2.netCarbLimitGrams, equals(4));
    });

    test('an analysis of different dish text is re-analysed even when its '
        'options match', () async {
      // Arrange: the cache holds an analysis of an older menu.
      repository.seedCache(
        CachedMenu(
          menu: _menuOf([_dish('Pasta', id: 'old')]),
          analysis: llmAnalysis(
            options: const AnalysisOptionsSnapshot(netCarbLimitGrams: 6),
          ),
        ),
      );

      // Act
      await controller.open(_ref);

      // Assert
      expect(classifier.calls, hasLength(1));
    });

    test('a cached failed analysis is never reused', () async {
      // Arrange
      repository.seedCache(
        CachedMenu(
          menu: menu,
          analysis: const MenuAnalysisFailed(
            reason: MenuAnalysisFailureReason.timeout,
          ),
        ),
      );

      // Act
      await controller.open(_ref);

      // Assert
      expect(classifier.calls, hasLength(1));
    });
  });
}
