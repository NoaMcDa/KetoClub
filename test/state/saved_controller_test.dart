import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/state/saved_controller.dart';

import '../fakes/fake_menu_repository.dart';

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

void main() {
  group('SavedController', () {
    late FakeMenuRepository repository;
    late SavedController controller;

    setUp(() {
      repository = FakeMenuRepository();
      controller = SavedController(repository);
    });

    test('entries is empty before load', () {
      expect(controller.entries, isEmpty);
      expect(controller.isLoading, isFalse);
    });

    test('load populates entries from the repository', () async {
      // Arrange
      repository.seedCache(
        CachedMenu(menu: _menuWith(_woltRef, DateTime.utc(2026))),
      );

      // Act
      await controller.load();

      // Assert
      expect(controller.entries, hasLength(1));
      expect(controller.entries.single.ref, _woltRef);
    });

    test('load exposes the score and counts of an analysed entry', () async {
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

      // Act
      await controller.load();

      // Assert
      final entry = controller.entries.single;
      expect(entry.score, 10.0);
      expect(entry.greenCount, 1);
      expect(entry.yellowCount, 0);
    });

    test('load leaves score null for an entry with no analysis', () async {
      // Arrange
      repository.seedCache(
        CachedMenu(menu: _menuWith(_woltRef, DateTime.utc(2026))),
      );

      // Act
      await controller.load();

      // Assert
      expect(controller.entries.single.score, isNull);
      expect(controller.entries.single.greenCount, 0);
    });

    test('load sorts entries newest-fetched first', () async {
      // Arrange
      repository
        ..seedCache(CachedMenu(menu: _menuWith(_woltRef, DateTime.utc(2026))))
        ..seedCache(
          CachedMenu(menu: _menuWith(_tenbisRef, DateTime.utc(2026, 1, 2))),
        );

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

    test('hide removes the matching entry and returns it', () async {
      // Arrange
      repository.seedCache(
        CachedMenu(menu: _menuWith(_woltRef, DateTime.utc(2026))),
      );
      await controller.load();

      // Act
      final removed = controller.hide(_woltRef);

      // Assert
      expect(removed?.ref, _woltRef);
      expect(controller.entries, isEmpty);
    });

    test('hide does not touch the repository', () async {
      // Arrange
      repository.seedCache(
        CachedMenu(menu: _menuWith(_woltRef, DateTime.utc(2026))),
      );
      await controller.load();

      // Act
      controller.hide(_woltRef);

      // Assert
      expect(repository.removedRefs, isEmpty);
    });

    test('hide returns null and changes nothing for an absent ref', () async {
      // Arrange
      repository.seedCache(
        CachedMenu(menu: _menuWith(_woltRef, DateTime.utc(2026))),
      );
      await controller.load();

      // Act
      final removed = controller.hide(_tenbisRef);

      // Assert
      expect(removed, isNull);
      expect(controller.entries, hasLength(1));
    });

    test(
      'restore puts a hidden entry back, keeping newest-first order',
      () async {
        // Arrange
        repository
          ..seedCache(CachedMenu(menu: _menuWith(_woltRef, DateTime.utc(2026))))
          ..seedCache(
            CachedMenu(menu: _menuWith(_tenbisRef, DateTime.utc(2026, 1, 2))),
          );
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

    test('commitRemoval deletes through the repository', () async {
      // Arrange
      repository.seedCache(
        CachedMenu(menu: _menuWith(_woltRef, DateTime.utc(2026))),
      );
      await controller.load();
      controller.hide(_woltRef);

      // Act
      await controller.commitRemoval(_woltRef);

      // Assert
      expect(repository.removedRefs, [_woltRef]);
    });

    test(
      'commitRemoval after restore is never called leaves the cache',
      () async {
        // Arrange: a caller that restores never calls commitRemoval at all —
        // this asserts the repository is untouched by hide/restore alone.
        repository.seedCache(
          CachedMenu(menu: _menuWith(_woltRef, DateTime.utc(2026))),
        );
        await controller.load();
        final removed = controller.hide(_woltRef)!;
        controller.restore(removed);

        // Assert
        expect(repository.removedRefs, isEmpty);
        expect(await repository.cached(_woltRef), isNotNull);
      },
    );

    test('setPinned flips the row at once and tells the repository', () async {
      // Arrange
      repository.seedCache(
        CachedMenu(menu: _menuWith(_woltRef, DateTime.utc(2026))),
      );
      await controller.load();
      expect(controller.entries.single.pinned, isFalse);

      // Act
      await controller.setPinned(_woltRef, pinned: true);

      // Assert
      expect(controller.entries.single.pinned, isTrue);
      expect(repository.pinCalls.single, (ref: _woltRef, pinned: true));
      await controller.load();
      expect(controller.entries.single.pinned, isTrue);
    });

    test('setPinned false unpins', () async {
      // Arrange
      repository.seedCache(
        CachedMenu(menu: _menuWith(_woltRef, DateTime.utc(2026))),
      );
      await controller.load();
      await controller.setPinned(_woltRef, pinned: true);

      // Act
      await controller.setPinned(_woltRef, pinned: false);

      // Assert
      expect(controller.entries.single.pinned, isFalse);
    });

    test('setPinned on an unlisted ref changes nothing', () async {
      // Act
      await controller.setPinned(_tenbisRef, pinned: true);

      // Assert
      expect(repository.pinCalls, isEmpty);
    });
  });
}
