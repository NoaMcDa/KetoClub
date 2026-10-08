import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';
import 'package:ketoclub/state/saved_controller.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_visit_history_store.dart';

const VenueRef _woltRef = VenueRef(source: MenuSource.wolt, platformId: 'a');
const VenueRef _tenbisRef = VenueRef(
  source: MenuSource.tenbis,
  platformId: 'b',
);

/// A minimal, valid [Menu] for [ref] fetched at [fetchedAt], with one dish.
Menu _menuWith(VenueRef ref, DateTime fetchedAt) => Menu(
  venueRef: ref,
  currency: 'ILS',
  fetchedAt: fetchedAt,
  categories: const <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'Mains',
      dishes: <Dish>[
        Dish(id: 'd1', name: 'Steak', description: '', price: 40, options: []),
      ],
    ),
  ],
);

/// A visit to [ref] last opened at [openedAt], with an optional snapshot.
VisitEntry _visit(
  VenueRef ref,
  DateTime openedAt, {
  int? dishCount,
  double? score,
  int? greenCount,
  int? yellowCount,
}) => VisitEntry(
  ref: ref,
  firstOpenedAt: openedAt,
  lastOpenedAt: openedAt,
  openCount: 1,
  dishCount: dishCount,
  score: score,
  greenCount: greenCount,
  yellowCount: yellowCount,
);

void main() {
  group('SavedController', () {
    late FakeMenuRepository repository;
    late FakeVisitHistoryStore history;
    late SavedController controller;

    /// Caches [ref]'s one-dish menu and records a visit to it, both at
    /// [at] — the state opening a menu leaves behind.
    void seedOpened(VenueRef ref, DateTime at, {MenuAnalysis? analysis}) {
      repository.seedCache(
        CachedMenu(menu: _menuWith(ref, at), analysis: analysis),
      );
      history.seed(_visit(ref, at));
    }

    setUp(() {
      repository = FakeMenuRepository();
      history = FakeVisitHistoryStore(FakeClock(DateTime.utc(2026)));
      controller = SavedController(repository, history);
    });

    test('entries is empty before load', () {
      expect(controller.entries, isEmpty);
      expect(controller.isLoading, isFalse);
    });

    test('load lists a visit joined with its cached menu', () async {
      // Arrange
      seedOpened(_woltRef, DateTime.utc(2026));

      // Act
      await controller.load();

      // Assert
      final entry = controller.entries.single;
      expect(entry.ref, _woltRef);
      expect(entry.isCached, isTrue);
      expect(entry.cached?.ref, _woltRef);
      expect(entry.dishCount, 1);
    });

    test('load does not list a cached menu with no visit', () async {
      // Arrange
      repository.seedCache(
        CachedMenu(menu: _menuWith(_woltRef, DateTime.utc(2026))),
      );

      // Act
      await controller.load();

      // Assert
      expect(controller.entries, isEmpty);
    });

    test('load lists a visit with no cached menu, with the snapshot '
        'counts', () async {
      // Arrange
      history.seed(
        _visit(
          _woltRef,
          DateTime.utc(2026),
          dishCount: 12,
          score: 6.5,
          greenCount: 4,
          yellowCount: 3,
        ),
      );

      // Act
      await controller.load();

      // Assert
      final entry = controller.entries.single;
      expect(entry.isCached, isFalse);
      expect(entry.cached, isNull);
      expect(entry.isPinned, isFalse);
      expect(entry.dishCount, 12);
      expect(entry.score, 6.5);
      expect(entry.greenCount, 4);
      expect(entry.yellowCount, 3);
      expect(entry.engine, isNull);
    });

    test('a cached analysis wins over the visit snapshot', () async {
      // Arrange
      repository.seedCache(
        CachedMenu(
          menu: _menuWith(_woltRef, DateTime.utc(2026)),
          analysis: MenuAnalysed(
            dishes: const <AnalysedDish>[
              AnalysedDish(
                dishId: 'd1',
                name: 'Steak',
                verdict: DishVerdict.orderAsIs,
                why: 'No starch.',
              ),
            ],
            unclassified: const <String>[],
            engine: const LlmEngine(model: 'test/model'),
            analysedAt: DateTime.utc(2026),
          ),
        ),
      );
      history.seed(
        _visit(
          _woltRef,
          DateTime.utc(2026),
          dishCount: 9,
          score: 2,
          greenCount: 0,
          yellowCount: 2,
        ),
      );

      // Act
      await controller.load();

      // Assert
      final entry = controller.entries.single;
      expect(entry.score, 10.0);
      expect(entry.greenCount, 1);
      expect(entry.yellowCount, 0);
      expect(entry.dishCount, 1);
      expect(entry.engine, const LlmEngine(model: 'test/model'));
    });

    test(
      'an unanalysed cached menu falls back to the snapshot score',
      () async {
        // Arrange
        repository.seedCache(
          CachedMenu(menu: _menuWith(_woltRef, DateTime.utc(2026))),
        );
        history.seed(
          _visit(
            _woltRef,
            DateTime.utc(2026),
            score: 5,
            greenCount: 1,
            yellowCount: 1,
          ),
        );

        // Act
        await controller.load();

        // Assert
        final entry = controller.entries.single;
        expect(entry.score, 5.0);
        expect(entry.greenCount, 1);
        expect(entry.yellowCount, 1);
      },
    );

    test('score and counts are null when neither side has them', () async {
      // Arrange
      seedOpened(_woltRef, DateTime.utc(2026));

      // Act
      await controller.load();

      // Assert
      final entry = controller.entries.single;
      expect(entry.score, isNull);
      expect(entry.greenCount, isNull);
      expect(entry.yellowCount, isNull);
    });

    test(
      'a scan with no cached copy is gone; a platform menu is not',
      () async {
        // Arrange
        const scanRef = VenueRef(source: MenuSource.scan, platformId: 'ff');
        history
          ..seed(_visit(scanRef, DateTime.utc(2026)))
          ..seed(_visit(_woltRef, DateTime.utc(2026, 1, 2)));

        // Act
        await controller.load();

        // Assert
        final byRef = {for (final e in controller.entries) e.ref: e};
        expect(byRef[scanRef]!.isGone, isTrue);
        expect(byRef[_woltRef]!.isGone, isFalse);
      },
    );

    test('load orders entries by when they were last opened, not '
        'fetched', () async {
      // Arrange: the wolt menu was fetched later but opened earlier.
      repository
        ..seedCache(
          CachedMenu(menu: _menuWith(_woltRef, DateTime.utc(2026, 1, 9))),
        )
        ..seedCache(
          CachedMenu(menu: _menuWith(_tenbisRef, DateTime.utc(2026))),
        );
      history
        ..seed(_visit(_woltRef, DateTime.utc(2026, 1, 3)))
        ..seed(_visit(_tenbisRef, DateTime.utc(2026, 1, 5)));

      // Act
      await controller.load();

      // Assert
      expect(controller.entries.map((e) => e.ref).toList(), [
        _tenbisRef,
        _woltRef,
      ]);
    });

    test('load toggles isLoading true then false', () async {
      // Arrange
      final states = <bool>[];
      controller.addListener(() => states.add(controller.isLoading));

      // Act
      await controller.load();

      // Assert
      expect(states, [true, false]);
    });

    test('with no history store, nothing is listed', () async {
      // Arrange
      repository.seedCache(
        CachedMenu(menu: _menuWith(_woltRef, DateTime.utc(2026))),
      );
      final bare = SavedController(repository);

      // Act
      await bare.load();

      // Assert
      expect(bare.entries, isEmpty);
    });

    test('hide removes the matching entry and returns it', () async {
      // Arrange
      seedOpened(_woltRef, DateTime.utc(2026));
      await controller.load();

      // Act
      final removed = controller.hide(_woltRef);

      // Assert
      expect(removed?.ref, _woltRef);
      expect(controller.entries, isEmpty);
    });

    test('hide touches neither the history nor the repository', () async {
      // Arrange
      seedOpened(_woltRef, DateTime.utc(2026));
      await controller.load();

      // Act
      controller.hide(_woltRef);

      // Assert
      expect(repository.removedRefs, isEmpty);
      expect(history.removedRefs, isEmpty);
    });

    test('hide returns null and changes nothing for an absent ref', () async {
      // Arrange
      seedOpened(_woltRef, DateTime.utc(2026));
      await controller.load();

      // Act
      final removed = controller.hide(_tenbisRef);

      // Assert
      expect(removed, isNull);
      expect(controller.entries, hasLength(1));
    });

    test(
      'restore puts a hidden entry back, keeping most-recent-first order',
      () async {
        // Arrange
        seedOpened(_woltRef, DateTime.utc(2026));
        seedOpened(_tenbisRef, DateTime.utc(2026, 1, 2));
        await controller.load();
        final removed = controller.hide(_tenbisRef)!;

        // Act
        controller.restore(removed);

        // Assert
        expect(controller.entries.map((e) => e.ref).toList(), [
          _tenbisRef,
          _woltRef,
        ]);
      },
    );

    test('commitRemoval removes from the history and the repository, once '
        'each', () async {
      // Arrange
      seedOpened(_woltRef, DateTime.utc(2026));
      await controller.load();
      controller.hide(_woltRef);

      // Act
      await controller.commitRemoval(_woltRef);

      // Assert
      expect(repository.removedRefs, [_woltRef]);
      expect(history.removedRefs, [_woltRef]);
      expect(await history.read(_woltRef), isNull);
      await controller.load();
      expect(controller.entries, isEmpty);
    });

    test('hide then restore removes nothing from either store', () async {
      // Arrange: a caller that restores never calls commitRemoval at all —
      // this asserts both stores are untouched by hide/restore alone.
      seedOpened(_woltRef, DateTime.utc(2026));
      await controller.load();
      final removed = controller.hide(_woltRef)!;

      // Act
      controller.restore(removed);

      // Assert
      expect(repository.removedRefs, isEmpty);
      expect(history.removedRefs, isEmpty);
      expect(await repository.cached(_woltRef), isNotNull);
      expect(await history.read(_woltRef), isNotNull);
    });

    test('setPinned flips the row at once and tells the repository', () async {
      // Arrange
      seedOpened(_woltRef, DateTime.utc(2026));
      await controller.load();
      expect(controller.entries.single.isPinned, isFalse);

      // Act
      await controller.setPinned(_woltRef, pinned: true);

      // Assert
      expect(controller.entries.single.isPinned, isTrue);
      expect(repository.pinCalls.single, (ref: _woltRef, pinned: true));
      await controller.load();
      expect(controller.entries.single.isPinned, isTrue);
    });

    test('setPinned false unpins', () async {
      // Arrange
      seedOpened(_woltRef, DateTime.utc(2026));
      await controller.load();
      await controller.setPinned(_woltRef, pinned: true);

      // Act
      await controller.setPinned(_woltRef, pinned: false);

      // Assert
      expect(controller.entries.single.isPinned, isFalse);
    });

    test('setPinned on an unlisted ref changes nothing', () async {
      // Act
      await controller.setPinned(_tenbisRef, pinned: true);

      // Assert
      expect(repository.pinCalls, isEmpty);
    });

    test('setPinned on an uncached entry is ignored', () async {
      // Arrange
      history.seed(_visit(_woltRef, DateTime.utc(2026)));
      await controller.load();
      var notified = 0;
      controller.addListener(() => notified++);

      // Act
      await controller.setPinned(_woltRef, pinned: true);

      // Assert
      expect(repository.pinCalls, isEmpty);
      expect(controller.entries.single.isPinned, isFalse);
      expect(notified, 0);
    });

    group('rename (issue #315)', () {
      const scanRef = VenueRef(source: MenuSource.scan, platformId: 'beef');

      test('writes the trimmed values to the store and rebuilds the '
          'row', () async {
        // Arrange
        seedOpened(scanRef, DateTime.utc(2026));
        await controller.load();
        var notified = 0;
        controller.addListener(() => notified++);

        // Act
        await controller.rename(scanRef, name: '  Café Noam ', city: ' Haifa ');

        // Assert
        expect(history.renameCalls.single.name, 'Café Noam');
        expect(history.renameCalls.single.city, 'Haifa');
        final entry = controller.entries.single;
        expect(entry.venueName, 'Café Noam');
        expect(entry.city, 'Haifa');
        expect(entry.isCached, isTrue);
        expect(entry.visit.openCount, 1);
        expect(notified, 1);
        expect((await history.read(scanRef))!.name, 'Café Noam');
      });

      test('an empty or blank value clears the field', () async {
        // Arrange
        history.seed(
          VisitEntry(
            ref: scanRef,
            name: 'Old',
            city: 'Lod',
            firstOpenedAt: DateTime.utc(2026),
            lastOpenedAt: DateTime.utc(2026),
            openCount: 1,
          ),
        );
        await controller.load();

        // Act
        await controller.rename(scanRef, name: '  ', city: '');

        // Assert
        expect(controller.entries.single.venueName, isNull);
        expect(controller.entries.single.city, isNull);
        expect((await history.read(scanRef))!.name, isNull);
      });

      test('keeps the row where it was in the list', () async {
        // Arrange
        seedOpened(_woltRef, DateTime.utc(2026, 1, 2));
        seedOpened(scanRef, DateTime.utc(2026));
        await controller.load();

        // Act
        await controller.rename(scanRef, name: 'Café Noam', city: null);

        // Assert
        expect(controller.entries.map((e) => e.ref), [_woltRef, scanRef]);
      });

      test('a gone scan row can be renamed', () async {
        // Arrange
        history.seed(_visit(scanRef, DateTime.utc(2026)));
        await controller.load();
        expect(controller.entries.single.isGone, isTrue);

        // Act
        await controller.rename(scanRef, name: 'Café Noam', city: 'Haifa');

        // Assert
        expect(controller.entries.single.venueName, 'Café Noam');
        expect(controller.entries.single.isGone, isTrue);
      });

      test('a ref that is not listed is still written to the store', () async {
        // Act
        await controller.rename(scanRef, name: 'Café Noam', city: null);

        // Assert
        expect(history.renameCalls, hasLength(1));
        expect(controller.entries, isEmpty);
      });
    });
  });
}
