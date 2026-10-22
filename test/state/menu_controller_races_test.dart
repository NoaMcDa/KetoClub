import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/state/menu_controller.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_settings_store.dart';
import '../fakes/fake_visit_history_store.dart';

/// The venue most tests open.
const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

/// A second venue, opened over [_ref] to supersede its load.
const VenueRef _other = VenueRef(source: MenuSource.wolt, platformId: 'v2');

/// A one-dish menu for [ref], its dish named [name].
Menu _menu(VenueRef ref, String name) => Menu(
  venueRef: ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'Mains',
      dishes: <Dish>[
        Dish(
          id: 'd1',
          name: name,
          description: '',
          price: 10,
          options: const <DishOption>[],
        ),
      ],
    ),
  ],
);

/// An analysis placing the one dish of a [_menu] named [name] green,
/// stamped [model] so two results can be told apart.
MenuAnalysed _analysis(String name, String model) => MenuAnalysed(
  dishes: <AnalysedDish>[
    AnalysedDish(
      dishId: 'd1',
      name: name,
      verdict: DishVerdict.orderAsIs,
      why: 'why',
    ),
  ],
  unclassified: const <String>[],
  engine: LlmEngine(model: model),
  analysedAt: DateTime.utc(2026),
);

void main() {
  group('MenuController load races (issue #287)', () {
    late FakeMenuRepository repository;
    late FakeMenuClassifier classifier;
    late FakeSettingsStore settings;
    late FakeVisitHistoryStore history;
    late MenuController controller;

    setUp(() {
      repository = FakeMenuRepository()
        ..stub(_ref, MenuFetched(menu: _menu(_ref, 'Steak')))
        ..stub(_other, MenuFetched(menu: _menu(_other, 'Salmon')));
      classifier = FakeMenuClassifier();
      settings = FakeSettingsStore();
      history = FakeVisitHistoryStore(FakeClock(DateTime.utc(2026)));
      controller = MenuController(
        repository,
        classifier,
        settings,
        FakeNotesStore(),
        CarbBudgetController(),
        null,
        history,
      );
    });

    test('Back while the menu is fetched: the load finishes into nothing, '
        'with no notification, last venue or visit', () async {
      // Arrange: the fetch is held open.
      final fetch = Completer<void>();
      repository.loadGate = fetch.future;
      final opening = controller.open(_ref);
      await pumpEventQueue();
      var notified = 0;
      controller.addListener(() => notified++);
      expect(controller.phase, LoadPhase.fetching);

      // Act: the screen goes away, then the fetch answers.
      controller.dispose();
      fetch.complete();
      await opening;

      // Assert: no "used after being disposed" throw, and nothing written.
      expect(notified, 0);
      expect(classifier.calls, isEmpty);
      expect((await settings.read()).lastVenue, isNull);
      expect(history.recordCalls, isEmpty);
    });

    test('Back while the menu is classified: the result is neither shown, '
        'saved nor recorded', () async {
      // Arrange
      final engine = Completer<void>();
      classifier
        ..gate = engine.future
        ..respondWith(_analysis('Steak', 'm1'));
      final opening = controller.open(_ref);
      await pumpEventQueue();
      expect(controller.phase, LoadPhase.classifying);

      // Act
      controller.dispose();
      engine.complete();
      await opening;

      // Assert
      expect(repository.savedAnalyses, isEmpty);
      expect(history.recordCalls, isEmpty);
    });

    test('a load superseded by a later open cannot overwrite its menu or '
        'end its progress state', () async {
      // Arrange: the first venue's fetch is held, then a second venue is
      // opened over it and its fetch held too.
      final first = Completer<void>();
      repository.loadGate = first.future;
      final openingFirst = controller.open(_ref);
      await pumpEventQueue();
      final second = Completer<void>();
      repository.loadGate = second.future;
      final openingSecond = controller.open(_other);
      await pumpEventQueue();

      // Act: the first answers last.
      second.complete();
      await openingSecond;
      first.complete();
      await openingFirst;

      // Assert: the second venue's menu stands.
      expect(controller.menu?.venueRef, _other);
      expect(controller.phase, LoadPhase.idle);
      expect((await settings.read()).lastVenue, _other);
      expect(history.recordCalls.map((call) => call.ref), [_other]);
      expect(classifier.calls, hasLength(1));
    });

    test('a classification superseded by a later open is dropped, however '
        'late it answers', () async {
      // Arrange: the first open's classification is held.
      final slow = Completer<void>();
      classifier.gate = slow.future;
      final openingFirst = controller.open(_ref);
      await pumpEventQueue();
      final fast = Completer<void>();
      classifier.gate = fast.future;
      final openingSecond = controller.open(_ref);
      await pumpEventQueue();

      // Act: the newer call answers first, the older one after it.
      classifier.respondWith(_analysis('Steak', 'newer'));
      fast.complete();
      await openingSecond;
      classifier.respondWith(_analysis('Steak', 'older'));
      slow.complete();
      await openingFirst;

      // Assert
      expect(controller.engine, const LlmEngine(model: 'newer'));
      expect(
        repository.savedAnalyses.map((saved) => saved.analysis),
        <MenuAnalysis>[_analysis('Steak', 'newer')],
      );
      expect(controller.phase, LoadPhase.idle);
    });

    test('an engine announcing itself for a superseded load does not move '
        "the newer load's phase", () async {
      // Arrange: the first open's options are kept to announce late, and
      // a second open is classifying with no engine announced yet.
      final slow = Completer<void>();
      classifier.gate = slow.future;
      final openingFirst = controller.open(_ref);
      await pumpEventQueue();
      final staleOptions = classifier.calls.single.$2;
      final fast = Completer<void>();
      classifier.gate = fast.future;
      final openingSecond = controller.open(_ref);
      await pumpEventQueue();
      expect(controller.phase, LoadPhase.classifying);

      // Act
      staleOptions.onEngineStarted?.call(ClassifyingEngine.rules);

      // Assert
      expect(controller.phase, LoadPhase.classifying);
      fast.complete();
      slow.complete();
      await Future.wait(<Future<void>>[openingFirst, openingSecond]);
    });

    test('refresh while a load runs is a no-op: no second fetch or model '
        'call', () async {
      // Arrange: an open is classifying.
      final engine = Completer<void>();
      classifier.gate = engine.future;
      final opening = controller.open(_ref);
      await pumpEventQueue();
      expect(controller.isLoading, isTrue);

      // Act
      await controller.refresh();

      // Assert
      expect(repository.loadCalls, hasLength(1));
      expect(classifier.calls, hasLength(1));
      expect(controller.isLoading, isTrue);
      engine.complete();
      await opening;
      expect(controller.phase, LoadPhase.idle);
    });

    test('reanalyse while a load runs is a no-op', () async {
      // Arrange: a loaded menu, then a refresh classifying it again.
      await controller.open(_ref);
      repository.stub(_ref, MenuFetched(menu: _menu(_ref, 'Ribeye')));
      final engine = Completer<void>();
      classifier.gate = engine.future;
      final refreshing = controller.refresh();
      await pumpEventQueue();
      expect(controller.phase.isClassifying, isTrue);

      // Act
      await controller.reanalyse();

      // Assert
      expect(classifier.calls, hasLength(2));
      engine.complete();
      await refreshing;
      expect(controller.phase, LoadPhase.idle);
    });

    test('a retry after a failed fetch clears the failure at once and shows '
        'the load', () async {
      // Arrange: a failed open.
      repository.stub(
        _ref,
        const MenuFetchFailed(reason: MenuFetchFailureReason.offline),
      );
      await controller.open(_ref);
      expect(controller.fetchFailure, MenuFetchFailureReason.offline);
      repository.stub(_ref, MenuFetched(menu: _menu(_ref, 'Steak')));
      final fetch = Completer<void>();
      repository.loadGate = fetch.future;

      // Act
      final retrying = controller.open(_ref, forceRefresh: true);

      // Assert: from the first synchronous moment.
      expect(controller.fetchFailure, isNull);
      expect(controller.fetchStatusCode, isNull);
      expect(controller.isLoading, isTrue);
      fetch.complete();
      await retrying;
      expect(controller.menu, isNotNull);
    });
  });
}
