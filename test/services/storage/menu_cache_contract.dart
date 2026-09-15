import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';

/// A minimal [Menu] for [ref], with no categories.
Menu _menuFor(VenueRef ref, {DateTime? fetchedAt}) => Menu(
  venueRef: ref,
  currency: 'ILS',
  fetchedAt: fetchedAt ?? DateTime.utc(2026),
  categories: const <MenuCategory>[],
);

/// Asserts the [MenuCache] contract against the implementation [build]
/// returns. Call this from each implementation's own test file —
/// including the fake — passing a factory that returns a fresh, empty
/// instance on every call (architecture.md §18.1, Liskov).
void runMenuCacheContract(String name, MenuCache Function() build) {
  // `wolt/x` and `tenbis/x` deliberately share a platformId: the cache
  // must key on the whole VenueRef, not just the platform id.
  const woltRef = VenueRef(source: MenuSource.wolt, platformId: 'x');
  const tenbisRef = VenueRef(source: MenuSource.tenbis, platformId: 'x');

  group('$name (MenuCache contract)', () {
    test('read returns null for a ref that was never written', () async {
      final cache = build();

      expect(await cache.read(woltRef), isNull);
    });

    test('read on an unknown ref never throws', () async {
      final cache = build();

      await expectLater(cache.read(woltRef), completes);
    });

    test(
      'write then read returns an entry equal to what was written',
      () async {
        final cache = build();
        final entry = CachedMenu(menu: _menuFor(woltRef));

        await cache.write(entry);

        expect(await cache.read(woltRef), equals(entry));
      },
    );

    test('write then read round-trips an entry carrying an analysis', () async {
      final cache = build();
      final entry = CachedMenu(
        menu: _menuFor(woltRef),
        analysis: MenuAnalysed(
          dishes: const <AnalysedDish>[],
          unclassified: const <String>['Mystery dish'],
          engine: const LlmEngine(model: 'test/model'),
          analysedAt: DateTime.utc(2026, 1, 1, 12),
        ),
      );

      await cache.write(entry);

      expect(await cache.read(woltRef), equals(entry));
    });

    test(
      'write then read round-trips an entry carrying a failed analysis',
      () async {
        final cache = build();
        final entry = CachedMenu(
          menu: _menuFor(woltRef),
          analysis: const MenuAnalysisFailed(
            reason: MenuAnalysisFailureReason.timeout,
            detail: 'gateway timed out',
          ),
        );

        await cache.write(entry);

        expect(await cache.read(woltRef), equals(entry));
      },
    );

    test('writing twice for one ref overwrites the first entry', () async {
      final cache = build();
      await cache.write(CachedMenu(menu: _menuFor(woltRef)));
      final second = CachedMenu(
        menu: _menuFor(woltRef, fetchedAt: DateTime.utc(2026, 2, 2)),
      );

      await cache.write(second);

      expect(await cache.read(woltRef), equals(second));
    });

    test(
      'two different VenueRefs sharing a platformId never collide',
      () async {
        final cache = build();
        final woltEntry = CachedMenu(menu: _menuFor(woltRef));
        final tenbisEntry = CachedMenu(menu: _menuFor(tenbisRef));

        await cache.write(woltEntry);
        await cache.write(tenbisEntry);

        expect(await cache.read(woltRef), equals(woltEntry));
        expect(await cache.read(tenbisRef), equals(tenbisEntry));
      },
    );

    test('clear empties every entry', () async {
      final cache = build();
      await cache.write(CachedMenu(menu: _menuFor(woltRef)));
      await cache.write(CachedMenu(menu: _menuFor(tenbisRef)));

      await cache.clear();

      expect(await cache.read(woltRef), isNull);
      expect(await cache.read(tenbisRef), isNull);
    });

    test('clear on an already-empty cache never throws', () async {
      final cache = build();

      await expectLater(cache.clear(), completes);
    });

    test('write never throws', () async {
      final cache = build();

      await expectLater(
        cache.write(CachedMenu(menu: _menuFor(woltRef))),
        completes,
      );
    });

    test('size is 0 for a freshly built cache', () async {
      final cache = build();

      expect(await cache.size(), equals(0));
    });

    test('size counts one entry after a single write', () async {
      final cache = build();

      await cache.write(CachedMenu(menu: _menuFor(woltRef)));

      expect(await cache.size(), equals(1));
    });

    test('size counts distinct VenueRefs, not distinct platformIds', () async {
      final cache = build();
      await cache.write(CachedMenu(menu: _menuFor(woltRef)));
      await cache.write(CachedMenu(menu: _menuFor(tenbisRef)));

      expect(await cache.size(), equals(2));
    });

    test(
      'size does not grow when a write overwrites an existing ref',
      () async {
        final cache = build();
        await cache.write(CachedMenu(menu: _menuFor(woltRef)));

        await cache.write(
          CachedMenu(menu: _menuFor(woltRef, fetchedAt: DateTime.utc(2027))),
        );

        expect(await cache.size(), equals(1));
      },
    );

    test('size is 0 after clear', () async {
      final cache = build();
      await cache.write(CachedMenu(menu: _menuFor(woltRef)));
      await cache.write(CachedMenu(menu: _menuFor(tenbisRef)));

      await cache.clear();

      expect(await cache.size(), equals(0));
    });

    test('size never throws', () async {
      final cache = build();

      await expectLater(cache.size(), completes);
    });
  });
}
