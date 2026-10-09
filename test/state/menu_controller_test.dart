import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/menu_question.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/classifier_router.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_question_answerer.dart';
import 'package:ketoclub/services/classifier/menu_question_prompt.dart';
import 'package:ketoclub/services/classifier/menu_response_parser.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/services/classifier/vision_menu_classifier.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/venue_route.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_connectivity.dart';
import '../fakes/fake_llm_chat_client.dart';
import '../fakes/fake_menu_cache.dart';
import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_question_answerer.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_menu_store_client.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_platform_menu_adapter.dart';
import '../fakes/fake_settings_store.dart';
import '../fakes/fake_visit_history_store.dart';

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
      controller = MenuController(
        repository,
        classifier,
        settings,
        notes,
        CarbBudgetController(),
      );
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
      await controller.setFilter(MenuFilter.greenOnly);

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
      await controller.setFilter(MenuFilter.greenOnly);

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
      await controller.setFilter(MenuFilter.yellowOnly);

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
      await controller.setFilter(MenuFilter.redOnly);

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
      await controller.setFilter(MenuFilter.greenAndYellow);

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
        await controller.setFilter(MenuFilter.all);

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
      await controller.setFilter(MenuFilter.all);

      // Act
      final rows = controller.visibleRows;

      // Assert
      expect(controller.unclassifiedNames, ['Mystery']);
      expect(rows.single.analysis, isNull);
    });

    test('unclassifiedRows resolves names to menu dishes, one each, and '
        'keeps a name the menu lacks (issue #244)', () async {
      // Arrange: two dishes share a name; the model also named a third.
      final first = _dish('Mystery', id: 'first');
      final second = _dish('Mystery', id: 'second');
      repository.stub(_ref, MenuFetched(menu: _menuOf([first, second])));
      classifier.respondWith(
        MenuAnalysed(
          dishes: const <AnalysedDish>[],
          unclassified: const <String>['Mystery', 'Mystery', 'Invented'],
          engine: const RulesEngine(
            reason: MenuAnalysisFailureReason.notConfigured,
          ),
          analysedAt: clock.now(),
        ),
      );
      await controller.open(_ref);

      // Act
      final rows = controller.unclassifiedRows;

      // Assert
      expect(rows.map((row) => row.dish.name), [
        'Mystery',
        'Mystery',
        'Invented',
      ]);
      expect(rows[0].dish.id, 'first');
      expect(rows[1].dish.id, 'second');
      expect(rows[2].category, isEmpty);
      expect(rows.every((row) => row.analysis == null), isTrue);
    });

    test('unclassifiedRows is empty before any analysis (issue #244)', () {
      // Act & Assert
      expect(controller.unclassifiedRows, isEmpty);
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
      await controller.setFilter(MenuFilter.all);

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
      controller = MenuController(
        repository,
        classifier,
        settings,
        notes,
        CarbBudgetController(),
      );
      repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));

      // Act
      await controller.open(_ref);

      // Assert
      expect(controller.filter, MenuFilter.greenOnly);
    });

    test('open restores lastFilter over the default filter when set '
        '(issue #55)', () async {
      // Arrange
      settings = FakeSettingsStore(
        initial: const AppSettings(
          filter: MenuFilter.greenOnly,
          lastFilter: MenuFilter.redOnly,
        ),
      );
      controller = MenuController(
        repository,
        classifier,
        settings,
        notes,
        CarbBudgetController(),
      );
      repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));

      // Act
      await controller.open(_ref);

      // Assert
      expect(controller.filter, MenuFilter.redOnly);
    });

    test(
      'open falls back to the default filter when lastFilter is unset',
      () async {
        // Arrange
        settings = FakeSettingsStore(
          initial: const AppSettings(filter: MenuFilter.yellowOnly),
        );
        controller = MenuController(
          repository,
          classifier,
          settings,
          notes,
          CarbBudgetController(),
        );
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));

        // Act
        await controller.open(_ref);

        // Assert
        expect(controller.filter, MenuFilter.yellowOnly);
      },
    );

    test('open writes lastVenue on a successful open (issue #55)', () async {
      // Arrange
      repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));

      // Act
      await controller.open(_ref);

      // Assert
      expect((await settings.read()).lastVenue, equals(_ref));
    });

    test(
      'open does not write lastVenue when the fetch fails outright',
      () async {
        // Arrange
        repository.stub(
          _ref,
          const MenuFetchFailed(reason: MenuFetchFailureReason.offline),
        );

        // Act
        await controller.open(_ref);

        // Assert
        expect((await settings.read()).lastVenue, isNull);
      },
    );

    test('setFilter persists the choice as lastFilter through SettingsStore '
        '(issue #55)', () async {
      // Arrange
      repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
      await controller.open(_ref);

      // Act
      await controller.setFilter(MenuFilter.yellowOnly);

      // Assert
      expect((await settings.read()).lastFilter, MenuFilter.yellowOnly);
    });

    test('open passes estimationConsentGiven from SettingsStore into '
        'ClassificationOptions', () async {
      // Arrange
      settings = FakeSettingsStore();
      controller = MenuController(
        repository,
        classifier,
        settings,
        notes,
        CarbBudgetController(),
      );
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

    test('verdict counts and the score cover food only; the filtered list '
        'still shows the drink (D21)', () async {
      // Arrange: a steak and a pasta under Mains, a cola under a drinks
      // heading — all three placed, the cola green.
      final steak = _dish('Steak', id: 'steak');
      final pasta = _dish('Pasta', id: 'pasta');
      final cola = _dish('Diet Coke', id: 'cola');
      final menu = Menu(
        venueRef: _ref,
        currency: 'ILS',
        fetchedAt: clock.now(),
        categories: [
          MenuCategory(id: 'c1', name: 'Mains', dishes: [steak, pasta]),
          MenuCategory(id: 'c2', name: 'שתייה', dishes: [cola]),
        ],
      );
      repository.stub(_ref, MenuFetched(menu: menu));
      classifier.respondWith(
        MenuAnalysed(
          dishes: [
            _verdictFor(steak, DishVerdict.orderAsIs),
            _verdictFor(pasta, DishVerdict.nonKeto),
            _verdictFor(cola, DishVerdict.orderAsIs),
          ],
          unclassified: const <String>[],
          engine: const LlmEngine(model: 'test-model'),
          analysedAt: clock.now(),
        ),
      );
      await controller.open(_ref);

      // Act
      await controller.setFilter(MenuFilter.greenOnly);

      // Assert: one green of two food dishes, the cola uncounted but
      // still listed under the green filter; the raw total still counts
      // every dish on the menu.
      expect(controller.greenCount, 1);
      expect(controller.redCount, 1);
      expect(controller.ketoScoreOutOfTen, 5.0);
      expect(controller.totalDishCount, 3);
      expect(
        controller.visibleRows.map((row) => row.dish.id),
        containsAll(<String>['steak', 'cola']),
      );
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

    group('search (issue #51)', () {
      test('query defaults to blank, so visibleRows narrows nothing by '
          'it', () {
        // Assert
        expect(controller.query, '');
      });

      test('setQuery narrows visibleRows by a case-insensitive match on '
          'the dish name', () async {
        // Arrange
        final steak = _dish('Grilled Steak', id: 'steak');
        final salad = _dish('Greek Salad', id: 'salad');
        repository.stub(_ref, MenuFetched(menu: _menuOf([steak, salad])));
        await controller.open(_ref);

        // Act
        controller.setQuery('STEAK');

        // Assert
        expect(controller.visibleRows.map((row) => row.dish.id), ['steak']);
      });

      test('setQuery matches Hebrew text regardless of niqqud, on either side '
          "— TextNormaliser's own pipeline, not a copy of it", () async {
        // Arrange: the menu carries niqqud; the typed query does not.
        final dish = _dish('סטֵייק');
        repository.stub(_ref, MenuFetched(menu: _menuOf([dish])));
        await controller.open(_ref);

        // Act
        controller.setQuery('סטייק');

        // Assert
        expect(controller.visibleRows.map((row) => row.dish.id), ['d1']);
      });

      test(
        'setQuery matches text found only in the dish description',
        () async {
          // Arrange
          const dish = Dish(
            id: 'd1',
            name: 'Chef special',
            description: 'Served with a side of asparagus',
            price: 10,
            options: <DishOption>[],
          );
          repository.stub(_ref, MenuFetched(menu: _menuOf([dish])));
          await controller.open(_ref);

          // Act
          controller.setQuery('asparagus');

          // Assert
          expect(controller.visibleRows.map((row) => row.dish.id), ['d1']);
        },
      );

      test('setQuery combines with the active verdict filter — both must '
          'match for a dish to show', () async {
        // Arrange: two dishes with the same searchable name, different
        // verdicts.
        final greenFries = _dish('Fries', id: 'green-fries');
        final yellowFries = _dish('Fries', id: 'yellow-fries');
        final menu = _menuOf([greenFries, yellowFries]);
        repository.stub(_ref, MenuFetched(menu: menu));
        classifier.respondWith(
          MenuAnalysed(
            dishes: [
              _verdictFor(greenFries, DishVerdict.orderAsIs),
              _verdictFor(
                yellowFries,
                DishVerdict.modifiable,
                modification: 'x',
              ),
            ],
            unclassified: const <String>[],
            engine: const RulesEngine(
              reason: MenuAnalysisFailureReason.notConfigured,
            ),
            analysedAt: clock.now(),
          ),
        );
        await controller.open(_ref);
        await controller.setFilter(MenuFilter.greenOnly);
        expect(controller.filter, MenuFilter.greenOnly);

        // Act: both dishes match the query, but only one matches the
        // filter too.
        controller.setQuery('fries');

        // Assert
        expect(controller.visibleRows.map((row) => row.dish.id), [
          'green-fries',
        ]);
      });

      test("clearing the query (setQuery('')) restores every row the filter "
          'alone would keep', () async {
        // Arrange
        final steak = _dish('Grilled Steak', id: 'steak');
        final salad = _dish('Greek Salad', id: 'salad');
        repository.stub(_ref, MenuFetched(menu: _menuOf([steak, salad])));
        await controller.open(_ref);
        controller.setQuery('steak');
        expect(controller.visibleRows, hasLength(1));

        // Act
        controller.setQuery('');

        // Assert
        expect(controller.query, '');
        expect(controller.visibleRows.map((row) => row.dish.id).toSet(), {
          'steak',
          'salad',
        });
      });

      test('setQuery notifies listeners', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        await controller.open(_ref);
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);
        expect(notifyCount, 0);

        // Act
        controller.setQuery('steak');

        // Assert
        expect(notifyCount, 1);
      });

      test('visibleCategories lists only categories with a visible row, in '
          'menu order', () async {
        // Arrange: two categories, one of which the query removes
        // entirely.
        final steak = _dish('Steak', id: 'steak');
        final salad = _dish('Salad', id: 'salad');
        final menu = Menu(
          venueRef: _ref,
          currency: 'ILS',
          fetchedAt: DateTime.utc(2026),
          categories: [
            MenuCategory(id: 'c1', name: 'Mains', dishes: [steak]),
            MenuCategory(id: 'c2', name: 'Sides', dishes: [salad]),
          ],
        );
        repository.stub(_ref, MenuFetched(menu: menu));
        await controller.open(_ref);

        // Assert: both categories show with no query.
        expect(controller.visibleCategories, ['Mains', 'Sides']);

        // Act
        controller.setQuery('steak');

        // Assert: only the category with a matching row remains.
        expect(controller.visibleCategories, ['Mains']);
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
      settings = FakeSettingsStore();
      controller = MenuController(
        repository,
        classifier,
        settings,
        FakeNotesStore(),
        CarbBudgetController(),
      );
    });

    test('open passes the stored limit to the classifier', () async {
      // Arrange
      await settings.write(const AppSettings(netCarbLimitGrams: 9));

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
        CarbBudgetController(),
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
      await settings.write(const AppSettings(netCarbLimitGrams: 9));

      // Act
      final reopened = MenuController(
        repository,
        classifier,
        settings,
        FakeNotesStore(),
        CarbBudgetController(),
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
      await settings.write(const AppSettings(netCarbLimitGrams: 9));
      await controller.open(_ref);
      await settings.write(const AppSettings());

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
        // D16 (issue #167) flipped AppSettings's default to true; state
        // the withdrawal explicitly rather than relying on the default.
        await settings.write(const AppSettings(estimationConsentGiven: false));

        // Act
        await controller.open(_ref);

        // Assert
        expect(classifier.calls, hasLength(2));
        expect(classifier.calls.last.$2.estimationConsentGiven, isFalse);
      },
    );
  });

  group('MenuController reuse checks against the cached entry', () {
    final steak = _dish('Steak');
    final menu = _menuOf([steak]);

    /// An LLM analysis of [menu] recording [options], as a cache would
    /// hold it. Defaults to the current [MenuResponseParser.schemaVersion]
    /// so tests that assert cache reuse read as intended (the reuse gate
    /// checks the version too since issue #213).
    MenuAnalysed llmAnalysis({
      AnalysisOptionsSnapshot? options,
      int schemaVersion = MenuResponseParser.schemaVersion,
    }) => MenuAnalysed(
      dishes: [_verdictFor(steak, DishVerdict.orderAsIs)],
      unclassified: const <String>[],
      engine: const LlmEngine(model: 'served-model'),
      analysedAt: DateTime.utc(2026),
      options: options,
      schemaVersion: schemaVersion,
    );

    late FakeMenuRepository repository;
    late FakeMenuClassifier classifier;
    late FakeSettingsStore settings;
    late MenuController controller;

    setUp(() {
      repository = FakeMenuRepository()
        ..stub(_ref, MenuFetched(menu: menu, fromCache: true));
      classifier = FakeMenuClassifier();
      settings = FakeSettingsStore();
      controller = MenuController(
        repository,
        classifier,
        settings,
        FakeNotesStore(),
        CarbBudgetController(),
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
      await settings.write(const AppSettings(netCarbLimitGrams: 4));

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

  // Issue #56: the dietary toggles reach the classifier as prompt
  // fragments in ClassificationOptions.dietaryConstraints, and so ride
  // issue #57's options-snapshot comparison: a changed toggle re-analyses,
  // an unchanged one spends nothing. Driven through the real
  // CachedMenuRepository over a FakeMenuCache, like the group above.
  group('MenuController dietary toggles (issue #56)', () {
    final steak = _dish('Steak');
    final menu = _menuOf([steak]);

    late FakeMenuCache cache;
    late CachedMenuRepository repository;
    late FakeMenuClassifier classifier;
    late FakeSettingsStore settings;

    setUp(() {
      cache = FakeMenuCache();
      repository = CachedMenuRepository(
        adapters: [FakePlatformMenuAdapter()..queueFetched(menu)],
        cache: cache,
        // Same instant as the menu's fetchedAt, so every later open is a
        // fresh cache hit and the menu itself is not refetched.
        clock: FakeClock(DateTime.utc(2026)),
      );
      classifier = FakeMenuClassifier()
        ..derivedEngine = const LlmEngine(model: 'served-model');
      settings = FakeSettingsStore();
    });

    /// A fresh controller over the shared repository, as a new visit to
    /// the menu screen would build.
    MenuController newController() => MenuController(
      repository,
      classifier,
      settings,
      FakeNotesStore(),
      CarbBudgetController(),
    );

    test('open passes every toggle on as its prompt fragment, in the fixed '
        'order', () async {
      // Arrange
      await settings.write(
        const AppSettings(
          carnivoreOnly: true,
          seedOilFree: true,
          dairyFree: true,
        ),
      );

      // Act
      await newController().open(_ref);

      // Assert
      expect(
        classifier.calls.single.$2.dietaryConstraints,
        equals([
          seedOilFreePromptFragment,
          dairyFreePromptFragment,
          carnivoreOnlyPromptFragment,
        ]),
      );
    });

    test('open with every toggle off passes no dietary constraint', () async {
      // Act
      await newController().open(_ref);

      // Assert
      expect(classifier.calls.single.$2.dietaryConstraints, isEmpty);
    });

    test('unchanged toggles reuse the cached analysis on the next open, '
        'spending no classifier call', () async {
      // Arrange
      await settings.write(const AppSettings(dairyFree: true));
      final first = newController();
      await first.open(_ref);

      // Act
      final reopened = newController();
      await reopened.open(_ref);

      // Assert
      expect(classifier.calls, hasLength(1));
      expect(reopened.analysis, equals(first.analysis));
    });

    for (final (name, turnedOn) in <(String, AppSettings)>[
      ('seed-oil free', const AppSettings(seedOilFree: true)),
      ('dairy-free', const AppSettings(dairyFree: true)),
      ('carnivore only', const AppSettings(carnivoreOnly: true)),
    ]) {
      test('turning $name on re-analyses on the next open, and caches the '
          'new result with the toggle recorded', () async {
        // Arrange
        await newController().open(_ref);
        await settings.write(turnedOn);

        // Act
        await newController().open(_ref);

        // Assert
        expect(classifier.calls, hasLength(2));
        final constraints = classifier.calls.last.$2.dietaryConstraints;
        expect(constraints, hasLength(1));
        final cached = await cache.read(_ref);
        expect(
          (cached!.analysis! as MenuAnalysed).options?.dietaryConstraints,
          equals(constraints),
        );
      });
    }

    test('turning a toggle back off re-analyses rather than reusing the '
        'result made with it on', () async {
      // Arrange
      await settings.write(const AppSettings(carnivoreOnly: true));
      await newController().open(_ref);
      await settings.write(const AppSettings());

      // Act
      await newController().open(_ref);

      // Assert
      expect(classifier.calls, hasLength(2));
      expect(classifier.calls.last.$2.dietaryConstraints, isEmpty);
    });

    test('refresh with an unchanged fingerprint still reclassifies when a '
        'toggle changed since open', () async {
      // Arrange
      final controller = newController();
      await controller.open(_ref);
      await settings.write(const AppSettings(seedOilFree: true));

      // Act
      await controller.refresh();

      // Assert
      expect(classifier.calls, hasLength(2));
      expect(
        classifier.calls.last.$2.dietaryConstraints,
        equals([seedOilFreePromptFragment]),
      );
    });
  });

  // Issue #89: a scan is read and classified once, by the vision engine,
  // and handed to the menu screen through the cache — the Scan tab stores
  // the transcription and saves its analysis, then opens its ref. The
  // menu screen must reuse that analysis, never re-classify the pages'
  // transcription through the text path, until the reuse check itself
  // says otherwise.
  group('MenuController over a scanned menu (issue #89)', () {
    late CachedMenuRepository repository;
    late FakeMenuClassifier classifier;
    late FakeSettingsStore settings;
    late ScannedMenuRead read;

    setUp(() async {
      final clock = FakeClock(DateTime.utc(2026, 9, 29));
      repository = CachedMenuRepository(
        adapters: const [],
        cache: FakeMenuCache(),
        clock: clock,
      );
      classifier = FakeMenuClassifier();
      settings = FakeSettingsStore();
      final client = FakeLlmChatClient()
        ..fallback = ChatCompleted(
          content: File('test/fixtures/llm/llm_scanned_valid.json')
              .readAsStringSync(),
          model: 'vision-model',
        );
      final result = await VisionMenuClassifier(client: client, clock: clock)
          .classify(
            ScannedMenu(
              pages: <ScannedPage>[
                ScannedPage(
                  mimeType: ScannedPage.jpeg,
                  bytes: Uint8List.fromList(<int>[0xff, 0xd8]),
                ),
              ],
            ),
            options: const ClassificationOptions(estimationConsentGiven: true),
          );
      read = result as ScannedMenuRead;
      // The Scan tab's hand-off (issue #82).
      await repository.store(read.menu);
      await repository.saveAnalysis(read.menu.venueRef, read.analysis);
    });

    test('open reuses the vision analysis and never re-classifies', () async {
      // Arrange
      final controller = MenuController(
        repository,
        classifier,
        settings,
        FakeNotesStore(),
        CarbBudgetController(),
      );

      // Act
      await controller.open(read.menu.venueRef);

      // Assert
      expect(classifier.calls, isEmpty);
      expect(controller.menu, read.menu);
      expect(controller.analysis, read.analysis);
    });

    test('once consent is withdrawn, the text router judges the '
        'transcription with the rule engine, never the model', () async {
      // Arrange
      await settings.write(const AppSettings(estimationConsentGiven: false));
      final llm = FakeMenuClassifier();
      final controller = MenuController(
        repository,
        RoutingMenuClassifier(
          llm,
          HeuristicMenuClassifier(clock: FakeClock(DateTime.utc(2026))),
          FakeConnectivity(),
        ),
        settings,
        FakeNotesStore(),
        CarbBudgetController(),
      );

      // Act
      await controller.open(read.menu.venueRef);

      // Assert: every transcribed dish judged by the rules, none by the
      // model.
      expect(llm.calls, isEmpty);
      final analysis = controller.analysis! as MenuAnalysed;
      expect(
        analysis.engine,
        const RulesEngine(reason: MenuAnalysisFailureReason.consentWithheld),
      );
      expect(
        analysis.dishes.map((dish) => dish.dishId),
        read.menu.allDishes.map((dish) => dish.id),
      );
      final carbonara = analysis.dishes.firstWhere(
        (dish) => dish.name == 'Spaghetti Carbonara',
      );
      expect(carbonara.verdict, DishVerdict.nonKeto);
    });
  });

  // ── Carb budget (issue #215) ────────────────────────────────────────────

  group('MenuController carb budget (issue #215)', () {
    const steak = Dish(
      id: 'steak',
      name: 'Herb Butter Steak',
      description: '',
      price: 42,
      options: <DishOption>[],
    );
    const salad = Dish(
      id: 'salad',
      name: 'Caesar Salad',
      description: '',
      price: 28,
      options: <DishOption>[],
    );
    final menu = Menu(
      venueRef: _ref,
      currency: 'ILS',
      fetchedAt: DateTime.utc(2026),
      categories: const <MenuCategory>[
        MenuCategory(id: 'c1', name: 'Mains', dishes: [steak, salad]),
      ],
    );
    final analysisWithEstimates = MenuAnalysed(
      dishes: const [
        AnalysedDish(
          dishId: 'steak',
          name: 'Herb Butter Steak',
          verdict: DishVerdict.orderAsIs,
          why: 'Protein and fat.',
          netCarbsEstimate: 2,
        ),
        AnalysedDish(
          dishId: 'salad',
          name: 'Caesar Salad',
          verdict: DishVerdict.orderAsIs,
          why: 'Mostly greens.',
          netCarbsEstimate: 8,
        ),
      ],
      unclassified: const <String>[],
      engine: const LlmEngine(model: 'test-model'),
      analysedAt: DateTime.utc(2026),
      options: const AnalysisOptionsSnapshot(netCarbLimitGrams: 6),
      schemaVersion: MenuResponseParser.schemaVersion,
    );

    late FakeMenuRepository repository;
    late FakeMenuClassifier classifier;
    late FakeSettingsStore settings;
    late CarbBudgetController budget;
    late MenuController controller;

    setUp(() {
      repository = FakeMenuRepository()
        ..stub(_ref, MenuFetched(menu: menu))
        ..seedCache(CachedMenu(menu: menu, analysis: analysisWithEstimates));
      classifier = FakeMenuClassifier()
        ..derivedEngine = const LlmEngine(model: 'test-model');
      settings = FakeSettingsStore();
      budget = CarbBudgetController();
      controller = MenuController(
        repository,
        classifier,
        settings,
        FakeNotesStore(),
        budget,
      );
    });

    tearDown(() {
      budget.dispose();
      controller.dispose();
    });

    test('isBudgetAvailable is false before any analysis', () {
      expect(controller.isBudgetAvailable, isFalse);
    });

    test('isBudgetAvailable is true after an LLM analysis and false after a '
        'rules analysis', () async {
      await controller.open(_ref);
      // The cache holds an LLM analysis so isBudgetAvailable is true.
      expect(controller.isBudgetAvailable, isTrue);

      // Disable consent so the rules engine answers on the next open.
      await settings.write(const AppSettings(estimationConsentGiven: false));
      final rulesController = MenuController(
        FakeMenuRepository()..stub(_ref, MenuFetched(menu: menu)),
        FakeMenuClassifier(),
        settings,
        FakeNotesStore(),
        CarbBudgetController(),
      );
      addTearDown(rulesController.dispose);
      await rulesController.open(_ref);
      expect(rulesController.isBudgetAvailable, isFalse);
    });

    test(
      'setting a budget filters out dishes whose estimate exceeds it',
      () async {
        await controller.open(_ref);
        // Both dishes visible with no budget.
        expect(controller.visibleRows, hasLength(2));

        // Set a 5 g budget: only steak (2 g) survives; salad (8 g) is hidden.
        budget.setBudget(5);
        expect(controller.visibleRows, hasLength(1));
        expect(controller.visibleRows.single.dish.id, equals('steak'));
      },
    );

    test(
      'a dish without a netCarbsEstimate is never filtered out by the budget',
      () async {
        // Replace the analysis with one that has no estimate on the steak.
        final analysisNoEstimate = MenuAnalysed(
          dishes: const [
            AnalysedDish(
              dishId: 'steak',
              name: 'Herb Butter Steak',
              verdict: DishVerdict.orderAsIs,
              why: 'Protein.',
            ),
          ],
          unclassified: const <String>[],
          engine: const LlmEngine(model: 'test-model'),
          analysedAt: DateTime.utc(2026),
          options: const AnalysisOptionsSnapshot(netCarbLimitGrams: 6),
          schemaVersion: MenuResponseParser.schemaVersion,
        );
        final r = FakeMenuRepository()
          ..stub(
            _ref,
            MenuFetched(
              menu: Menu(
                venueRef: _ref,
                currency: 'ILS',
                fetchedAt: DateTime.utc(2026),
                categories: const [
                  MenuCategory(id: 'c1', name: 'Mains', dishes: [steak]),
                ],
              ),
            ),
          )
          ..seedCache(
            CachedMenu(
              menu: Menu(
                venueRef: _ref,
                currency: 'ILS',
                fetchedAt: DateTime.utc(2026),
                categories: const [
                  MenuCategory(id: 'c1', name: 'Mains', dishes: [steak]),
                ],
              ),
              analysis: analysisNoEstimate,
            ),
          );
        final c = MenuController(
          r,
          FakeMenuClassifier(),
          FakeSettingsStore(),
          FakeNotesStore(),
          budget,
        );
        addTearDown(c.dispose);
        await c.open(_ref);

        budget.setBudget(1); // Budget of 1g — would filter steak if estimated.
        expect(c.visibleRows, hasLength(1)); // Steak has no estimate → passes.
      },
    );

    test(
      'changing the budget notifies without calling the classifier',
      () async {
        await controller.open(_ref);
        final callsBefore = classifier.calls.length;
        var notified = 0;
        controller.addListener(() => notified++);

        budget.setBudget(10);

        expect(notified, equals(1));
        expect(classifier.calls, hasLength(callsBefore)); // No new call.
      },
    );

    test('budget composes with the verdict filter: both must match', () async {
      // Add a yellow dish with a high carb estimate.
      const pasta = Dish(
        id: 'pasta',
        name: 'Pasta',
        description: '',
        price: 35,
        options: <DishOption>[],
      );
      final mixedMenu = Menu(
        venueRef: _ref,
        currency: 'ILS',
        fetchedAt: DateTime.utc(2026),
        categories: const [
          MenuCategory(id: 'c1', name: 'Mains', dishes: [steak, salad, pasta]),
        ],
      );
      final mixedAnalysis = MenuAnalysed(
        dishes: const [
          AnalysedDish(
            dishId: 'steak',
            name: 'Herb Butter Steak',
            verdict: DishVerdict.orderAsIs,
            why: 'Protein.',
            netCarbsEstimate: 2,
          ),
          AnalysedDish(
            dishId: 'salad',
            name: 'Caesar Salad',
            verdict: DishVerdict.modifiable,
            why: 'Mostly greens.',
            modification: 'No croutons.',
            netCarbsEstimate: 8,
          ),
          AnalysedDish(
            dishId: 'pasta',
            name: 'Pasta',
            verdict: DishVerdict.nonKeto,
            why: 'Pasta.',
          ),
        ],
        unclassified: const <String>[],
        engine: const LlmEngine(model: 'test-model'),
        analysedAt: DateTime.utc(2026),
        options: const AnalysisOptionsSnapshot(netCarbLimitGrams: 6),
        schemaVersion: MenuResponseParser.schemaVersion,
      );
      final r = FakeMenuRepository()
        ..stub(_ref, MenuFetched(menu: mixedMenu))
        ..seedCache(CachedMenu(menu: mixedMenu, analysis: mixedAnalysis));
      final c = MenuController(
        r,
        FakeMenuClassifier(),
        FakeSettingsStore(),
        FakeNotesStore(),
        budget,
      );
      addTearDown(c.dispose);
      await c.open(_ref);

      // Filter to green-only AND set a 5 g budget.
      await c.setFilter(MenuFilter.greenOnly);
      budget.setBudget(5);

      // Only steak matches both: green and ≤ 5 g.
      expect(c.visibleRows, hasLength(1));
      expect(c.visibleRows.single.dish.id, equals('steak'));
    });

    test('setting the budget never triggers a new classifier call '
        '(no-persistence contract, issue #215)', () async {
      await controller.open(_ref);
      // Record the write count after open (open does one settings write
      // to persist lastVenue).
      final writesAfterOpen = settings.writeCallCount;

      budget.setBudget(42);

      // No new classifier call.
      expect(classifier.calls, isEmpty);
      // No new settings write — the budget is not persisted.
      expect(settings.writeCallCount, equals(writesAfterOpen));
    });
  });

  group('askQuestion (architecture.md §9.5; issue #214)', () {
    late FakeMenuRepository repository;
    late FakeMenuClassifier classifier;
    late FakeSettingsStore settings;
    late FakeNotesStore notes;
    late FakeMenuQuestionAnswerer answerer;
    late MenuController controller;

    /// Opens a menu via [controller] that yields a [MenuAnalysed] with an
    /// [LlmEngine], so [controller.isQuestionAvailable] is true.
    Future<void> openWithLlmAnalysis({List<Dish>? dishes}) async {
      final menuDishes = dishes ?? [_dish('steak', id: 'steak')];
      final menu = _menuOf(menuDishes);
      repository.stub(_ref, MenuFetched(menu: menu));
      classifier
        ..respondWith(
          MenuAnalysed(
            dishes: [
              for (final d in menuDishes) _verdictFor(d, DishVerdict.orderAsIs),
            ],
            unclassified: const <String>[],
            engine: const LlmEngine(model: 'test-model'),
            analysedAt: DateTime.utc(2026),
          ),
        )
        ..derivedEngine = const LlmEngine(model: 'test-model');
      await controller.open(_ref);
    }

    setUp(() {
      repository = FakeMenuRepository();
      classifier = FakeMenuClassifier();
      settings = FakeSettingsStore();
      notes = FakeNotesStore();
      answerer = FakeMenuQuestionAnswerer();
      controller = MenuController(
        repository,
        classifier,
        settings,
        notes,
        CarbBudgetController(),
        answerer,
      );
    });

    test('isQuestionAvailable is false before any open', () {
      expect(controller.isQuestionAvailable, isFalse);
    });

    test('isQuestionAvailable is true after an LLM analysis', () async {
      await openWithLlmAnalysis();

      expect(controller.isQuestionAvailable, isTrue);
    });

    test(
      'isQuestionAvailable is false when analysis used RulesEngine',
      () async {
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        classifier.derivedEngine = const RulesEngine(
          reason: MenuAnalysisFailureReason.notConfigured,
        );
        await controller.open(_ref);

        expect(controller.isQuestionAvailable, isFalse);
      },
    );

    test('isQuestionAvailable is false when analysis failed', () async {
      repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
      classifier.respondWith(
        const MenuAnalysisFailed(reason: MenuAnalysisFailureReason.timeout),
      );
      await controller.open(_ref);

      expect(controller.isQuestionAvailable, isFalse);
    });

    test('isQuestionAvailable is false when no answerer is wired', () async {
      // A controller with no answerer (the optional 6th argument omitted).
      final bare = MenuController(
        repository,
        classifier,
        settings,
        notes,
        CarbBudgetController(),
      );
      repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
      classifier.respondWith(
        MenuAnalysed(
          dishes: [_verdictFor(_dish('Steak'), DishVerdict.orderAsIs)],
          unclassified: const <String>[],
          engine: const LlmEngine(model: 'test-model'),
          analysedAt: DateTime.utc(2026),
        ),
      );
      await bare.open(_ref);

      expect(bare.isQuestionAvailable, isFalse);
    });

    test('questionState starts at idle', () {
      expect(controller.questionState, QuestionState.idle);
    });

    test(
      'askQuestion transitions loading → answered on a successful reply',
      () async {
        await openWithLlmAnalysis();
        answerer.enqueueAnswer('The steak is keto-friendly.');

        final states = <QuestionState>[];
        controller.addListener(() => states.add(controller.questionState));

        await controller.askQuestion('Which dish should I order?');

        expect(states, [QuestionState.loading, QuestionState.answered]);
        expect(controller.questionState, QuestionState.answered);
      },
    );

    test('askQuestion sets questionAnswer on success', () async {
      await openWithLlmAnalysis();
      answerer.enqueueAnswer('Steak is great.', dishIds: ['steak']);

      await controller.askQuestion('Best keto dish?');

      expect(controller.questionAnswer, isNotNull);
      expect(controller.questionAnswer!.answer, 'Steak is great.');
      expect(controller.questionAnswer!.referencedDishIds, ['steak']);
    });

    test(
      'askQuestion transitions loading → failed on a failure reply',
      () async {
        await openWithLlmAnalysis();
        answerer.enqueue(
          const MenuQuestionFailed(reason: MenuQuestionFailureReason.offline),
        );

        final states = <QuestionState>[];
        controller.addListener(() => states.add(controller.questionState));

        await controller.askQuestion('Is there a dairy-free option?');

        expect(states, [QuestionState.loading, QuestionState.failed]);
        expect(controller.questionState, QuestionState.failed);
        expect(controller.questionFailure, MenuQuestionFailureReason.offline);
      },
    );

    test('askQuestion clears questionAnswer on failure', () async {
      // First ask succeeds.
      await openWithLlmAnalysis();
      answerer.enqueueAnswer('Steak is fine.');
      await controller.askQuestion('First question?');
      expect(controller.questionAnswer, isNotNull);

      // Second ask fails.
      answerer.enqueue(
        const MenuQuestionFailed(reason: MenuQuestionFailureReason.timeout),
      );
      await controller.askQuestion('Second question?');

      expect(controller.questionAnswer, isNull);
      expect(controller.questionState, QuestionState.failed);
    });

    test('dismissQuestion resets to idle from answered', () async {
      await openWithLlmAnalysis();
      answerer.enqueueAnswer('Good choice.');
      await controller.askQuestion('Is this keto?');
      expect(controller.questionState, QuestionState.answered);

      controller.dismissQuestion();

      expect(controller.questionState, QuestionState.idle);
      expect(controller.questionAnswer, isNull);
    });

    test('dismissQuestion resets to idle from failed', () async {
      await openWithLlmAnalysis();
      answerer.enqueue(
        const MenuQuestionFailed(reason: MenuQuestionFailureReason.badResponse),
      );
      await controller.askQuestion('Can I eat this?');
      expect(controller.questionState, QuestionState.failed);

      controller.dismissQuestion();

      expect(controller.questionState, QuestionState.idle);
      expect(controller.questionFailure, isNull);
    });

    test('dismissQuestion when already idle is a no-op (no notification)', () {
      var notifyCount = 0;
      controller
        ..addListener(() => notifyCount++)
        ..dismissQuestion();

      expect(notifyCount, 0);
      expect(controller.questionState, QuestionState.idle);
    });

    test('askQuestion is a no-op when no menu is open', () async {
      // No controller.open() call, so _menu is null.
      await controller.askQuestion('What can I eat?');

      expect(answerer.calls, isEmpty);
      expect(controller.questionState, QuestionState.idle);
    });

    test(
      'askQuestion is a no-op when analysis is not a MenuAnalysed',
      () async {
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        classifier.respondWith(
          const MenuAnalysisFailed(reason: MenuAnalysisFailureReason.timeout),
        );
        await controller.open(_ref);

        await controller.askQuestion('What can I eat?');

        expect(answerer.calls, isEmpty);
        expect(controller.questionState, QuestionState.idle);
      },
    );

    test(
      'askQuestion is a no-op when analysis engine is RulesEngine',
      () async {
        repository.stub(_ref, MenuFetched(menu: _menuOf([_dish('Steak')])));
        classifier.derivedEngine = const RulesEngine(
          reason: MenuAnalysisFailureReason.notConfigured,
        );
        await controller.open(_ref);

        await controller.askQuestion('What can I eat?');

        expect(answerer.calls, isEmpty);
      },
    );

    test('askQuestion is a no-op when question is blank', () async {
      await openWithLlmAnalysis();

      await controller.askQuestion('   ');

      expect(answerer.calls, isEmpty);
      expect(controller.questionState, QuestionState.idle);
    });

    test(
      'askQuestion is a no-op when question exceeds menuQuestionMaxLength',
      () async {
        await openWithLlmAnalysis();

        await controller.askQuestion('x' * (menuQuestionMaxLength + 1));

        expect(answerer.calls, isEmpty);
        expect(controller.questionState, QuestionState.idle);
      },
    );

    test(
      'askQuestion accepts a question exactly at menuQuestionMaxLength',
      () async {
        await openWithLlmAnalysis();
        answerer.enqueueAnswer('Within limit.');

        await controller.askQuestion('a' * menuQuestionMaxLength);

        expect(answerer.calls, hasLength(1));
      },
    );

    test(
      'askQuestion is a no-op when a question is already in flight',
      () async {
        await openWithLlmAnalysis();
        // Do not enqueue a result so the first ask blocks.
        // The fake returns synchronously, so we test the guard directly.
        final gate = Completer<void>();
        // Use a slow answerer.
        late final MenuQuestionAnswerer slowAnswerer;
        slowAnswerer = _SlowQuestionAnswerer(gate.future);
        final ctrlr = MenuController(
          repository,
          classifier,
          settings,
          notes,
          CarbBudgetController(),
          slowAnswerer,
        );
        await ctrlr.open(_ref);

        // Start a question (not yet answered).
        final first = ctrlr.askQuestion('First?');
        await pumpEventQueue();
        expect(ctrlr.questionState, QuestionState.loading);

        // A second ask while loading is a no-op.
        await ctrlr.askQuestion('Second?');

        // Let the first question complete.
        gate.complete();
        await first;

        // Only one real ask happened.
        expect(ctrlr.questionState, QuestionState.failed);
      },
    );

    group('D8 — question never persisted or logged (architecture.md D8)', () {
      test('askQuestion does not write to SettingsStore', () async {
        await openWithLlmAnalysis();
        answerer.enqueueAnswer('Steak is fine.');
        final settingsBefore = await settings.read();

        await controller.askQuestion('Is steak keto?');

        expect(await settings.read(), equals(settingsBefore));
      });

      test('askQuestion does not write to the notes store', () async {
        await openWithLlmAnalysis();
        answerer.enqueueAnswer('Steak is fine.');

        await controller.askQuestion('Is steak keto?');

        // FakeNotesStore records writes; the question must not trigger one.
        expect(notes.writeCalls, isEmpty);
      });
    });
  });

  // ── Scanned pages (issue #300) ───────────────────────────────────────────

  group('MenuController scanned pages (issue #300)', () {
    const scanRef = VenueRef(source: MenuSource.scan, platformId: 'scan-1');
    late FakeMenuRepository repository;
    late FakeMenuClassifier classifier;
    late MenuController controller;

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

    /// A dish named [name] with id [id], printed on [page].
    Dish pagedDish(String name, String id, int? page) => Dish(
      id: id,
      name: name,
      description: '',
      price: 0,
      options: const <DishOption>[],
      page: page,
    );

    /// A menu for [ref] holding [dishes] under one category.
    Menu menuFor(VenueRef ref, List<Dish> dishes) => Menu(
      venueRef: ref,
      currency: 'ILS',
      fetchedAt: DateTime.utc(2026),
      categories: <MenuCategory>[
        MenuCategory(id: 'c1', name: 'Scanned menu', dishes: dishes),
      ],
    );

    final salad = pagedDish('Salad', 's', 2);
    final mystery = pagedDish('Mystery', 'm', null);
    final steak = pagedDish('Steak', 't', 1);
    final pasta = pagedDish('Pasta', 'p', 1);

    /// Opens a scan of [salad, mystery, steak, pasta] (pages 2, null, 1,
    /// 1), with steak green, pasta red and the rest yellow.
    Future<void> openFourDishScan() async {
      repository.stub(
        scanRef,
        MenuFetched(menu: menuFor(scanRef, [salad, mystery, steak, pasta])),
      );
      classifier.respondWith(
        MenuAnalysed(
          dishes: [
            _verdictFor(salad, DishVerdict.modifiable, modification: 'm'),
            _verdictFor(mystery, DishVerdict.modifiable, modification: 'm'),
            _verdictFor(steak, DishVerdict.orderAsIs),
            _verdictFor(pasta, DishVerdict.nonKeto),
          ],
          unclassified: const <String>[],
          engine: const LlmEngine(model: 'vision-model'),
          analysedAt: DateTime.utc(2026),
        ),
      );
      await controller.open(scanRef);
    }

    List<String> visibleNames() =>
        controller.visibleRows.map((row) => row.dish.name).toList();

    test('attributedPages lists distinct pages ascending and '
        'hasUnattributedDishes sees the null page', () async {
      // Act
      await openFourDishScan();

      // Assert
      expect(controller.attributedPages, [1, 2]);
      expect(controller.hasUnattributedDishes, isTrue);
      expect(controller.pageFilter, isNull);
    });

    test('visibleRows groups rows by page with the unknown page last, '
        'keeping menu order within a page', () async {
      // Act
      await openFourDishScan();

      // Assert
      expect(visibleNames(), ['Steak', 'Pasta', 'Salad', 'Mystery']);
      expect(controller.visibleRows.map((row) => row.dish.page), [
        1,
        1,
        2,
        null,
      ]);
    });

    test('setPageFilter keeps one page, the unknown page, or every '
        'page', () async {
      // Arrange
      await openFourDishScan();

      // Act / Assert
      controller.setPageFilter(1);
      expect(visibleNames(), ['Steak', 'Pasta']);

      controller.setPageFilter(scanPageUnknown);
      expect(visibleNames(), ['Mystery']);

      controller.setPageFilter(null);
      expect(visibleNames(), ['Steak', 'Pasta', 'Salad', 'Mystery']);
    });

    test('the page filter combines with a verdict filter', () async {
      // Arrange
      await openFourDishScan();

      // Act
      await controller.setFilter(MenuFilter.yellowOnly);
      controller.setPageFilter(2);

      // Assert
      expect(visibleNames(), ['Salad']);

      // Act: page 1 holds no yellow dish.
      controller.setPageFilter(1);

      // Assert
      expect(visibleNames(), isEmpty);
    });

    test('the page filter combines with a search query', () async {
      // Arrange
      await openFourDishScan();

      // Act
      controller
        ..setQuery('pa')
        ..setPageFilter(1);

      // Assert: "Pasta" is on page 1; nothing else on it matches "pa".
      expect(visibleNames(), ['Pasta']);

      // Act
      controller.setPageFilter(2);

      // Assert
      expect(visibleNames(), isEmpty);
    });

    test('a Wolt menu has no attributed pages and ignores a page '
        'filter', () async {
      // Arrange: pages set on a platform menu are not a scan's pages.
      final dishes = [salad, mystery, steak, pasta];
      repository.stub(_ref, MenuFetched(menu: menuFor(_ref, dishes)));
      await controller.open(_ref);
      final before = visibleNames();

      // Act
      controller.setPageFilter(1);

      // Assert
      expect(controller.attributedPages, isEmpty);
      expect(controller.hasUnattributedDishes, isFalse);
      expect(before, ['Salad', 'Mystery', 'Steak', 'Pasta']);
      expect(visibleNames(), before);
    });

    test('a one-page scan keeps menu order exactly', () async {
      // Arrange
      final dishes = [
        pagedDish('B', 'b', 1),
        pagedDish('A', 'a', 1),
        pagedDish('C', 'c', 1),
      ];
      repository.stub(scanRef, MenuFetched(menu: menuFor(scanRef, dishes)));

      // Act
      await controller.open(scanRef);

      // Assert
      expect(controller.attributedPages, [1]);
      expect(controller.hasUnattributedDishes, isFalse);
      expect(visibleNames(), ['B', 'A', 'C']);
    });

    test('a scan with no pages keeps menu order and offers no '
        'pages', () async {
      // Arrange
      final dishes = [pagedDish('B', 'b', null), pagedDish('A', 'a', null)];
      repository.stub(scanRef, MenuFetched(menu: menuFor(scanRef, dishes)));

      // Act
      await controller.open(scanRef);

      // Assert
      expect(controller.attributedPages, isEmpty);
      expect(controller.hasUnattributedDishes, isFalse);
      expect(visibleNames(), ['B', 'A']);
    });

    test('open of another ref resets pageFilter to null', () async {
      // Arrange
      await openFourDishScan();
      controller.setPageFilter(2);
      const otherRef = VenueRef(source: MenuSource.scan, platformId: 's2');
      repository.stub(
        otherRef,
        MenuFetched(menu: menuFor(otherRef, [steak, salad])),
      );

      // Act
      await controller.open(otherRef);

      // Assert
      expect(controller.pageFilter, isNull);
      expect(visibleNames(), ['Steak', 'Salad']);
    });

    test('setPageFilter notifies once per change and never on a '
        'no-op', () async {
      // Arrange
      await openFourDishScan();
      var notifications = 0;
      controller
        ..addListener(() => notifications++)
        // Act / Assert
        ..setPageFilter(null);
      expect(notifications, 0);

      controller.setPageFilter(1);
      expect(notifications, 1);

      controller.setPageFilter(1);
      expect(notifications, 1);

      controller.setPageFilter(scanPageUnknown);
      expect(notifications, 2);
      expect(controller.pageFilter, scanPageUnknown);
    });
  });

  // ── Visit history and menu upload (issue #312) ─────────────────────────

  group('MenuController visit history and menu upload (issue #312)', () {
    final steak = _dish('Steak');
    final salad = _dish('Salad', id: 'd2');

    late FakeMenuRepository repository;
    late FakeMenuClassifier classifier;
    late FakeSettingsStore settings;
    late FakeClock historyClock;
    late FakeVisitHistoryStore history;
    late FakeMenuStoreClient store;

    /// A controller over this group's fakes; a new one per open mirrors
    /// the app, which builds one per venue route.
    MenuController newController() => MenuController(
      repository,
      classifier,
      settings,
      FakeNotesStore(),
      CarbBudgetController(),
      null,
      history,
      store,
    );

    /// Opens [_ref] on a fresh controller, waits for its upload, and
    /// returns the controller.
    Future<MenuController> openOnce({VenueOpenHint? hint}) async {
      final controller = newController();
      await controller.open(_ref, hint: hint);
      await controller.lastUpload;
      return controller;
    }

    /// An entry for [_ref], last opened at [lastOpenedAt].
    VisitEntry visit({
      required DateTime lastOpenedAt,
      String? name,
      String? city,
    }) => VisitEntry(
      ref: _ref,
      name: name,
      city: city,
      firstOpenedAt: DateTime.utc(2025),
      lastOpenedAt: lastOpenedAt,
      openCount: 1,
    );

    /// Seeds the cache with an LLM analysis of [menu] made at [analysedAt]
    /// under the default settings, so the next open reuses it.
    void seedReusable(Menu menu, {required DateTime analysedAt}) {
      repository.seedCache(
        CachedMenu(
          menu: menu,
          analysis: MenuAnalysed(
            dishes: [
              for (final dish in menu.allDishes)
                _verdictFor(dish, DishVerdict.orderAsIs),
            ],
            unclassified: const <String>[],
            engine: const LlmEngine(model: 'cached-model'),
            analysedAt: analysedAt,
            options: ClassificationOptions.fromSettings(const AppSettings())
                .snapshot,
            schemaVersion: MenuResponseParser.schemaVersion,
          ),
        ),
      );
    }

    setUp(() {
      repository = FakeMenuRepository();
      classifier = FakeMenuClassifier();
      settings = FakeSettingsStore();
      historyClock = FakeClock(DateTime.utc(2026, 3));
      history = FakeVisitHistoryStore(historyClock);
      store = FakeMenuStoreClient();
    });

    test('a successful open records exactly one visit, with the dish '
        'count, the score and the verdict counts', () async {
      // Arrange
      final menu = _menuOf([steak, salad]);
      repository.stub(_ref, MenuFetched(menu: menu));
      classifier.respondWith(
        MenuAnalysed(
          dishes: [
            _verdictFor(steak, DishVerdict.orderAsIs),
            _verdictFor(salad, DishVerdict.modifiable, modification: 'No'),
          ],
          unclassified: const <String>[],
          engine: const LlmEngine(model: 'test-model'),
          analysedAt: DateTime.utc(2026),
        ),
      );

      // Act
      final controller = await openOnce();

      // Assert
      final call = history.recordCalls.single;
      expect(call.ref, _ref);
      expect(call.dishCount, 2);
      expect(call.greenCount, 1);
      expect(call.yellowCount, 1);
      expect(call.score, controller.ketoScoreOutOfTen);
      expect(call.score, isNotNull);
      expect((await history.read(_ref))!.openCount, 1);
    });

    test('a failed analysis records the visit with its dish count but no '
        'score or counts', () async {
      // Arrange
      repository.stub(_ref, MenuFetched(menu: _menuOf([steak])));
      classifier.respondWith(
        const MenuAnalysisFailed(
          reason: MenuAnalysisFailureReason.noDishesFound,
        ),
      );

      // Act
      await openOnce();

      // Assert
      final call = history.recordCalls.single;
      expect(call.dishCount, 1);
      expect(call.score, isNull);
      expect(call.greenCount, isNull);
      expect(call.yellowCount, isNull);
    });

    test('a failed fetch records nothing and uploads nothing', () async {
      // Arrange
      repository.stub(
        _ref,
        const MenuFetchFailed(reason: MenuFetchFailureReason.notFound),
      );

      // Act
      await openOnce(hint: const VenueOpenHint(name: 'Vitrina'));

      // Assert
      expect(history.recordCalls, isEmpty);
      expect(store.uploads, isEmpty);
    });

    test('refresh records nothing', () async {
      // Arrange
      repository.stub(_ref, MenuFetched(menu: _menuOf([steak])));
      final controller = await openOnce();

      // Act
      await controller.refresh();

      // Assert
      expect(history.recordCalls, hasLength(1));
    });

    test('the name the menu carries wins over the hint, and the city comes '
        'from the hint', () async {
      // Arrange
      final named = Menu(
        venueRef: _ref,
        venueName: 'Sunny Diner',
        currency: 'ILS',
        fetchedAt: DateTime.utc(2026),
        categories: <MenuCategory>[
          MenuCategory(id: 'c1', name: 'Mains', dishes: [steak]),
        ],
      );
      repository.stub(_ref, MenuFetched(menu: named));

      // Act
      final controller = await openOnce(
        hint: const VenueOpenHint(name: 'Vitrina', city: 'Tel Aviv'),
      );

      // Assert
      expect(history.recordCalls.single.name, 'Sunny Diner');
      expect(history.recordCalls.single.city, 'Tel Aviv');
      expect(controller.historyName, 'Sunny Diner');
      expect(controller.historyCity, 'Tel Aviv');
    });

    test('with no name on the menu the hint names the visit, and a later '
        'hint-less open keeps that name', () async {
      // Arrange
      repository.stub(_ref, MenuFetched(menu: _menuOf([steak])));
      await openOnce(
        hint: const VenueOpenHint(name: 'Vitrina', city: 'Tel Aviv'),
      );

      // Act
      final reopened = await openOnce();

      // Assert
      expect(history.recordCalls.first.name, 'Vitrina');
      expect(history.recordCalls.last.name, isNull);
      final entry = (await history.read(_ref))!;
      expect(entry.name, 'Vitrina');
      expect(entry.city, 'Tel Aviv');
      expect(entry.openCount, 2);
      expect(reopened.historyName, 'Vitrina');
      expect(reopened.historyCity, 'Tel Aviv');
    });

    test('historyName and historyCity are read before classification '
        'completes, and listeners hear of them', () async {
      // Arrange
      history.seed(
        visit(lastOpenedAt: DateTime.utc(2026), name: 'Vitrina', city: 'Haifa'),
      );
      repository.stub(_ref, MenuFetched(menu: _menuOf([steak])));
      final gate = Completer<void>();
      classifier.gate = gate.future;
      final controller = newController();
      final seen = <String?>[];
      controller.addListener(() => seen.add(controller.historyName));

      // Act
      final opening = controller.open(_ref);
      await pumpEventQueue();

      // Assert
      expect(controller.phase.isClassifying, isTrue);
      expect(controller.historyName, 'Vitrina');
      expect(controller.historyCity, 'Haifa');
      expect(seen, contains('Vitrina'));
      gate.complete();
      await opening;
    });

    test('a venue never opened before is uploaded, with the recorded name '
        'and city and no analysis for a rules result', () async {
      // Arrange: the fake classifier's default result is a rules one.
      repository.stub(_ref, MenuFetched(menu: _menuOf([steak])));

      // Act
      await openOnce(
        hint: const VenueOpenHint(name: 'Vitrina', city: 'Tel Aviv'),
      );

      // Assert
      final upload = store.uploads.single;
      expect(upload.ref, _ref);
      expect(upload.venueName, 'Vitrina');
      expect(upload.city, 'Tel Aviv');
      expect(upload.menu, _menuOf([steak]));
      expect(upload.analysis, isNull);
      expect(upload.toJson()['analysis'], isNull);
    });

    test('an LLM analysis rides along without the user options', () async {
      // Arrange
      repository.stub(_ref, MenuFetched(menu: _menuOf([steak])));
      classifier.derivedEngine = const LlmEngine(model: 'test-model');

      // Act
      final controller = await openOnce();

      // Assert
      final upload = store.uploads.single;
      expect(upload.analysis, controller.analysis);
      final body = upload.toJson();
      final analysis = body['analysis']! as Map<String, Object?>;
      expect(analysis.containsKey('options'), isFalse);
      expect(analysis['dishes'], isNotEmpty);
    });

    test('a known venue whose LLM analysis was made in this open is '
        'uploaded, named from the history', () async {
      // Arrange
      history.seed(visit(lastOpenedAt: DateTime.utc(2026, 2), name: 'Vitrina'));
      repository.stub(_ref, MenuFetched(menu: _menuOf([steak])));
      classifier.derivedEngine = const LlmEngine(model: 'test-model');

      // Act
      await openOnce();

      // Assert
      expect(classifier.calls, hasLength(1));
      expect(store.uploads.single.venueName, 'Vitrina');
      expect(store.uploads.single.analysis, isNotNull);
    });

    test('a known venue whose rules analysis was made in this open is not '
        'uploaded: a rules result is never reused', () async {
      // Arrange: the fake classifier's default result is a rules one.
      history.seed(visit(lastOpenedAt: DateTime.utc(2026, 2), name: 'Vitrina'));
      repository.stub(_ref, MenuFetched(menu: _menuOf([steak])));

      // Act
      await openOnce();

      // Assert
      expect(classifier.calls, hasLength(1));
      expect(store.uploads, isEmpty);
    });

    test('a rules-analysed venue uploads once, on its first open, with no '
        'analysis, and not on the second', () async {
      // Arrange
      repository.stub(_ref, MenuFetched(menu: _menuOf([steak])));

      // Act
      await openOnce();
      historyClock.advance(const Duration(minutes: 5));
      await openOnce();

      // Assert
      expect(classifier.calls, hasLength(2));
      expect(store.uploads, hasLength(1));
      expect(store.uploads.single.analysis, isNull);
      expect(history.recordCalls, hasLength(2));
    });

    test('a known venue reusing an analysis older than its last visit is '
        'not uploaded', () async {
      // Arrange
      final menu = _menuOf([steak]);
      repository.stub(_ref, MenuFetched(menu: menu));
      seedReusable(menu, analysedAt: DateTime.utc(2026));
      history.seed(visit(lastOpenedAt: DateTime.utc(2026, 2)));

      // Act
      await openOnce();

      // Assert
      expect(classifier.calls, isEmpty);
      expect(store.uploads, isEmpty);
      expect(history.recordCalls, hasLength(1));
    });

    test('a known venue reusing an analysis newer than its last visit is '
        'uploaded with that analysis', () async {
      // Arrange
      final menu = _menuOf([steak]);
      repository.stub(_ref, MenuFetched(menu: menu));
      seedReusable(menu, analysedAt: DateTime.utc(2026, 2));
      history.seed(visit(lastOpenedAt: DateTime.utc(2026)));

      // Act
      final controller = await openOnce();

      // Assert
      expect(classifier.calls, isEmpty);
      expect(store.uploads.single.analysis, controller.analysis);
    });

    test('with AI-analysis consent off nothing is uploaded, though the '
        'visit is recorded', () async {
      // Arrange
      await settings.write(const AppSettings(estimationConsentGiven: false));
      repository.stub(_ref, MenuFetched(menu: _menuOf([steak])));

      // Act
      await openOnce(hint: const VenueOpenHint(name: 'Vitrina'));

      // Assert
      expect(store.uploads, isEmpty);
      expect(history.recordCalls, hasLength(1));
    });

    test('an unconfigured store is never asked to upload', () async {
      // Arrange
      store.isConfigured = false;
      repository.stub(_ref, MenuFetched(menu: _menuOf([steak])));

      // Act
      await openOnce();

      // Assert
      expect(store.uploads, isEmpty);
    });

    /// An analysis of [menu] by [engine] under the default settings, made
    /// at [analysedAt], as KetoClub's backend answers with one (D25).
    MenuAnalysed arrivedAnalysis(
      Menu menu, {
      AnalysisEngine engine = const LlmEngine(model: 'server-model'),
      DateTime? analysedAt,
    }) => MenuAnalysed(
      dishes: [
        for (final dish in menu.allDishes)
          _verdictFor(dish, DishVerdict.orderAsIs),
      ],
      unclassified: const <String>[],
      engine: engine,
      analysedAt: analysedAt ?? DateTime.utc(2026, 3),
      options: ClassificationOptions.fromSettings(const AppSettings()).snapshot,
      schemaVersion: MenuResponseParser.schemaVersion,
    );

    /// Stubs [_ref] to fetch [menu] with [analysis] riding on the fetch,
    /// cached beside it as the real repository does.
    void stubArrived(Menu menu, MenuAnalysed analysis) {
      repository
        ..stub(_ref, MenuFetched(menu: menu, analysis: analysis))
        ..seedCache(CachedMenu(menu: menu, analysis: analysis));
    }

    test('a new venue whose model analysis arrived with the fetch is shown '
        'without classifying and is not uploaded: the backend stored it '
        '(issue #331)', () async {
      // Arrange
      final menu = _menuOf([steak]);
      final analysis = arrivedAnalysis(menu);
      stubArrived(menu, analysis);

      // Act
      final controller = await openOnce(
        hint: const VenueOpenHint(name: 'Vitrina', city: 'Tel Aviv'),
      );

      // Assert
      expect(controller.analysis, analysis);
      expect(classifier.calls, isEmpty);
      expect(store.uploads, isEmpty);
      expect(history.recordCalls, hasLength(1));
    });

    test('a known venue whose fresh analysis arrived with the fetch is not '
        'uploaded either (issue #331)', () async {
      // Arrange: the analysis is newer than the last visit.
      history.seed(visit(lastOpenedAt: DateTime.utc(2026)));
      final menu = _menuOf([steak]);
      stubArrived(
        menu,
        arrivedAnalysis(menu, analysedAt: DateTime.utc(2026, 2)),
      );

      // Act
      await openOnce();

      // Assert
      expect(classifier.calls, isEmpty);
      expect(store.uploads, isEmpty);
    });

    test(
      'a rules analysis that arrived with the fetch is classified again '
      'here, and a model analysis made here is uploaded (issue #331)',
      () async {
        // Arrange: the server's model failed, so it answered with rules.
        final menu = _menuOf([steak]);
        stubArrived(
          menu,
          arrivedAnalysis(
            menu,
            engine: const RulesEngine(
              reason: MenuAnalysisFailureReason.rateLimited,
            ),
          ),
        );
        classifier.derivedEngine = const LlmEngine(model: 'device-model');

        // Act
        final controller = await openOnce();

        // Assert
        expect(classifier.calls, hasLength(1));
        expect(store.uploads.single.analysis, controller.analysis);
      },
    );

    test('a rules analysis that arrived with the fetch and a rules result '
        'here upload nothing: the backend has the menu (issue #331)', () async {
      // Arrange
      final menu = _menuOf([steak]);
      stubArrived(
        menu,
        arrivedAnalysis(
          menu,
          engine: const RulesEngine(
            reason: MenuAnalysisFailureReason.rateLimited,
          ),
        ),
      );

      // Act
      await openOnce();

      // Assert: the fake classifier's default result is a rules one.
      expect(classifier.calls, hasLength(1));
      expect(store.uploads, isEmpty);
    });

    test('a refresh whose refetch carried a reusable analysis shows it '
        'without classifying again (issue #331)', () async {
      // Arrange: opened once, then the menu changed upstream.
      repository.stub(_ref, MenuFetched(menu: _menuOf([steak])));
      final controller = await openOnce();
      final changed = _menuOf([steak, salad]);
      final analysis = arrivedAnalysis(changed);
      stubArrived(changed, analysis);
      final callsBefore = classifier.calls.length;

      // Act
      await controller.refresh();

      // Assert
      expect(controller.analysis, analysis);
      expect(classifier.calls, hasLength(callsBefore));
    });

    test('a refresh whose refetch carried a rules analysis classifies again '
        '(issue #331)', () async {
      // Arrange
      repository.stub(_ref, MenuFetched(menu: _menuOf([steak])));
      final controller = await openOnce();
      final changed = _menuOf([steak, salad]);
      stubArrived(
        changed,
        arrivedAnalysis(
          changed,
          engine: const RulesEngine(reason: MenuAnalysisFailureReason.timeout),
        ),
      );
      final callsBefore = classifier.calls.length;

      // Act
      await controller.refresh();

      // Assert
      expect(classifier.calls, hasLength(callsBefore + 1));
    });

    test('lastUpload completes only once the upload has finished', () async {
      // Arrange
      repository.stub(_ref, MenuFetched(menu: _menuOf([steak])));
      final gate = Completer<void>();
      store.gate = gate;
      final controller = newController();
      expect(controller.lastUpload, completes);
      await controller.open(_ref);
      var finished = false;
      unawaited(controller.lastUpload.then((_) => finished = true));

      // Act and assert: held while the store is.
      await pumpEventQueue();
      expect(store.uploads, hasLength(1));
      expect(finished, isFalse);
      gate.complete();
      await controller.lastUpload;
      expect(finished, isTrue);
    });

    group('renameVisit (issue #315)', () {
      const scanRef = VenueRef(source: MenuSource.scan, platformId: 'abc');
      final scanMenu = Menu(
        venueRef: scanRef,
        currency: 'ILS',
        fetchedAt: DateTime.utc(2026),
        categories: <MenuCategory>[
          MenuCategory(id: 'c1', name: 'Mains', dishes: [steak]),
        ],
      );

      /// A scan opened on a fresh controller, its first upload awaited.
      Future<MenuController> openScan() async {
        repository.stub(scanRef, MenuFetched(menu: scanMenu));
        final controller = newController();
        await controller.open(scanRef);
        await controller.lastUpload;
        return controller;
      }

      test('canRename is true only for a scanned menu', () async {
        // Arrange
        repository.stub(_ref, MenuFetched(menu: _menuOf([steak])));
        final wolt = await openOnce();
        final scan = await openScan();

        // Assert
        expect(wolt.canRename, isFalse);
        expect(scan.canRename, isTrue);
        expect(newController().canRename, isFalse);
      });

      test('writes the trimmed name and city to the history and shows '
          'them', () async {
        // Arrange
        final controller = await openScan();
        var notified = 0;
        controller.addListener(() => notified++);

        // Act
        await controller.renameVisit(name: '  Café Noam ', city: ' Haifa  ');

        // Assert
        expect(history.renameCalls.single.ref, scanRef);
        expect(history.renameCalls.single.name, 'Café Noam');
        expect(history.renameCalls.single.city, 'Haifa');
        expect(controller.historyName, 'Café Noam');
        expect(controller.historyCity, 'Haifa');
        expect(notified, greaterThan(0));
        expect((await history.read(scanRef))!.name, 'Café Noam');
      });

      test('an empty or blank name or city is stored as null', () async {
        // Arrange
        final controller = await openScan();
        await controller.renameVisit(name: 'Café Noam', city: 'Haifa');

        // Act
        await controller.renameVisit(name: '   ', city: '');
        await controller.lastUpload;

        // Assert
        expect(history.renameCalls.last.name, isNull);
        expect(history.renameCalls.last.city, isNull);
        expect(controller.historyName, isNull);
        expect(controller.historyCity, isNull);
        expect(store.uploads.last.venueName, isNull);
        expect(store.uploads.last.city, isNull);
      });

      test('re-uploads the menu once under the new name and city', () async {
        // Arrange
        final controller = await openScan();
        expect(store.uploads, hasLength(1));

        // Act
        await controller.renameVisit(name: 'Café Noam', city: 'Haifa');
        await controller.lastUpload;

        // Assert
        expect(store.uploads, hasLength(2));
        final upload = store.uploads.last;
        expect(upload.ref, scanRef);
        expect(upload.venueName, 'Café Noam');
        expect(upload.city, 'Haifa');
        expect(upload.menu, scanMenu);
        expect(upload.analysis, isNull);
      });

      test('the re-upload carries an LLM analysis', () async {
        // Arrange
        classifier.derivedEngine = const LlmEngine(model: 'test-model');
        final controller = await openScan();

        // Act
        await controller.renameVisit(name: 'Café Noam', city: null);
        await controller.lastUpload;

        // Assert
        expect(store.uploads.last.analysis, controller.analysis);
        expect(store.uploads.last.analysis, isNotNull);
      });

      test(
        'without AI-analysis consent it renames but uploads nothing',
        () async {
          // Arrange
          await settings.write(
            const AppSettings(estimationConsentGiven: false),
          );
          final controller = await openScan();

          // Act
          await controller.renameVisit(name: 'Café Noam', city: 'Haifa');
          await controller.lastUpload;

          // Assert
          expect(store.uploads, isEmpty);
          expect(history.renameCalls, hasLength(1));
          expect(controller.historyName, 'Café Noam');
        },
      );

      test(
        'with an unconfigured store it renames but uploads nothing',
        () async {
          // Arrange
          store.isConfigured = false;
          final controller = await openScan();

          // Act
          await controller.renameVisit(name: 'Café Noam', city: 'Haifa');
          await controller.lastUpload;

          // Assert
          expect(store.uploads, isEmpty);
          expect(controller.historyName, 'Café Noam');
        },
      );

      test('with no menu loaded it renames but uploads nothing', () async {
        // Arrange: the fetch fails, so no menu is loaded.
        repository.stub(
          scanRef,
          const MenuFetchFailed(reason: MenuFetchFailureReason.notFound),
        );
        final controller = newController();
        await controller.open(scanRef);

        // Act
        await controller.renameVisit(name: 'Café Noam', city: 'Haifa');
        await controller.lastUpload;

        // Assert
        expect(history.renameCalls, hasLength(1));
        expect(controller.historyName, 'Café Noam');
        expect(store.uploads, isEmpty);
      });

      test('before open it does nothing', () async {
        // Arrange
        final controller = newController();

        // Act
        await controller.renameVisit(name: 'Café Noam', city: 'Haifa');

        // Assert
        expect(history.renameCalls, isEmpty);
        expect(controller.historyName, isNull);
        expect(store.uploads, isEmpty);
      });
    });

    test('a freshly scanned menu uploads on its first open and not on the '
        'next', () async {
      // Arrange: the Scan tab's hand-off, as the scanned-menu group does.
      final scanClock = FakeClock(DateTime.utc(2026, 9, 29));
      final scanRepository = CachedMenuRepository(
        adapters: const [],
        cache: FakeMenuCache(),
        clock: scanClock,
      );
      final client = FakeLlmChatClient()
        ..fallback = ChatCompleted(
          content: File('test/fixtures/llm/llm_scanned_valid.json')
              .readAsStringSync(),
          model: 'vision-model',
        );
      final read =
          await VisionMenuClassifier(client: client, clock: scanClock).classify(
            ScannedMenu(
              pages: <ScannedPage>[
                ScannedPage(
                  mimeType: ScannedPage.jpeg,
                  bytes: Uint8List.fromList(<int>[0xff, 0xd8]),
                ),
              ],
            ),
            options: const ClassificationOptions(estimationConsentGiven: true),
          ) as ScannedMenuRead;
      await scanRepository.store(read.menu);
      await scanRepository.saveAnalysis(read.menu.venueRef, read.analysis);
      final scanHistory = FakeVisitHistoryStore(scanClock);
      MenuController scanController() => MenuController(
        scanRepository,
        classifier,
        settings,
        FakeNotesStore(),
        CarbBudgetController(),
        null,
        scanHistory,
        store,
      );

      // Act
      final first = scanController();
      await first.open(read.menu.venueRef);
      await first.lastUpload;
      scanClock.advance(const Duration(minutes: 5));
      final second = scanController();
      await second.open(read.menu.venueRef);
      await second.lastUpload;

      // Assert
      expect(classifier.calls, isEmpty);
      expect(store.uploads, hasLength(1));
      expect(store.uploads.single.analysis, read.analysis);
      expect(scanHistory.recordCalls, hasLength(2));
    });
  });
}

/// A [MenuQuestionAnswerer] that blocks until a gate completes, then returns
/// [MenuQuestionFailed] with [MenuQuestionFailureReason.badResponse].
///
/// Used to hold a question in flight so the "no concurrent questions" guard
/// can be exercised.
final class _SlowQuestionAnswerer implements MenuQuestionAnswerer {
  /// Creates a slow answerer that waits for the given gate before responding.
  const new(this._gate);
  final Future<void> _gate;

  @override
  Future<MenuQuestionResult> ask(
    Menu menu,
    MenuAnalysed analysis,
    String question,
  ) async {
    await _gate;
    return const MenuQuestionFailed(
      reason: MenuQuestionFailureReason.badResponse,
    );
  }
}
