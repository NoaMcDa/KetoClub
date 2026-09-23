import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/venue/venue_ref_resolver.dart';

import '../../fakes/fake_clock.dart';
import '../../fakes/fake_menu_cache.dart';
import '../../fakes/fake_platform_menu_adapter.dart';
import 'menu_repository_contract.dart';

/// Fixed instant every test's [FakeClock] starts at.
final DateTime _epoch = DateTime.utc(2026);

/// How long a cached menu is fresh for, in the repository under test.
/// Deliberately not the production `menuCacheTtl` default, so the
/// tests exercise the constructor parameter instead.
const Duration _freshFor = Duration(hours: 2);

const VenueRef _woltRef = VenueRef(source: MenuSource.wolt, platformId: 'x');
const VenueRef _tenbisRef = VenueRef(
  source: MenuSource.tenbis,
  platformId: 'x',
);

const MenuAnalysis _someAnalysis = MenuAnalysisFailed(
  reason: MenuAnalysisFailureReason.noDishesFound,
);

/// A minimal, valid [Menu] for [ref], fetched at [fetchedAt], with one
/// dish named [dishText] (used to drive the fingerprint comparison).
Menu _menuWith(VenueRef ref, DateTime fetchedAt, {String dishText = 'A'}) =>
    Menu(
      venueRef: ref,
      currency: 'ILS',
      fetchedAt: fetchedAt,
      categories: <MenuCategory>[
        MenuCategory(
          id: 'c1',
          name: 'Mains',
          dishes: <Dish>[
            Dish(
              id: 'd1',
              name: dishText,
              description: '',
              price: 10,
              options: const <DishOption>[],
            ),
          ],
        ),
      ],
    );

void main() {
  runMenuRepositoryContract(
    'CachedMenuRepository',
    () => CachedMenuRepository(
      adapters: [FakePlatformMenuAdapter()],
      cache: FakeMenuCache(),
      clock: FakeClock(_epoch),
    ),
    refItHandles: _woltRef,
    refItRejects: _tenbisRef,
  );

  group('CachedMenuRepository', () {
    late FakePlatformMenuAdapter adapter;
    late FakeMenuCache cache;
    late FakeClock clock;
    late CachedMenuRepository repository;

    setUp(() {
      adapter = FakePlatformMenuAdapter();
      cache = FakeMenuCache();
      clock = FakeClock(_epoch);
      repository = CachedMenuRepository(
        adapters: [adapter],
        cache: cache,
        clock: clock,
        freshFor: _freshFor,
      );
    });

    test('load fresh cache hit does not call the adapter', () async {
      // Arrange
      final menu = _menuWith(_woltRef, clock.now());
      await cache.write(CachedMenu(menu: menu));

      // Act
      final result = await repository.load(_woltRef);

      // Assert
      expect(result, equals(MenuFetched(menu: menu, fromCache: true)));
      expect(adapter.fetchCalls, isEmpty);
    });

    test(
      'load cached menu younger than freshFor by one tick stays fresh',
      () async {
        // Arrange
        final fetchedAt = clock.now();
        await cache.write(CachedMenu(menu: _menuWith(_woltRef, fetchedAt)));
        clock.advance(_freshFor - const Duration(milliseconds: 1));

        // Act
        final result = await repository.load(_woltRef);

        // Assert
        expect(adapter.fetchCalls, isEmpty);
        expect((result as MenuFetched).fromCache, isTrue);
      },
    );

    test('load cached menu exactly freshFor old triggers a refetch', () async {
      // Arrange
      final fetchedAt = clock.now();
      await cache.write(CachedMenu(menu: _menuWith(_woltRef, fetchedAt)));
      clock.advance(_freshFor);

      // Act
      final result = await repository.load(_woltRef);

      // Assert: exactly freshFor old is not "younger than freshFor".
      expect(adapter.fetchCalls, [_woltRef]);
      expect((result as MenuFetched).fromCache, isFalse);
    });

    test(
      'load cached menu one tick past freshFor triggers a refetch',
      () async {
        // Arrange
        final fetchedAt = clock.now();
        await cache.write(CachedMenu(menu: _menuWith(_woltRef, fetchedAt)));
        clock.advance(_freshFor + const Duration(milliseconds: 1));

        // Act
        final result = await repository.load(_woltRef);

        // Assert
        expect(adapter.fetchCalls, [_woltRef]);
        expect((result as MenuFetched).fromCache, isFalse);
      },
    );

    test('load adapter failure with a stale cached menu returns it with '
        'the staleReason', () async {
      // Arrange
      final staleMenu = _menuWith(_woltRef, clock.now());
      await cache.write(CachedMenu(menu: staleMenu));
      clock.advance(_freshFor + const Duration(hours: 1));
      adapter.queueFailed(MenuFetchFailureReason.offline);

      // Act
      final result = await repository.load(_woltRef);

      // Assert
      expect(
        result,
        equals(
          MenuFetched(
            menu: staleMenu,
            fromCache: true,
            staleReason: MenuFetchFailureReason.offline,
          ),
        ),
      );
    });

    test('load adapter failure with no cached menu returns the failure '
        'unchanged, status code included', () async {
      // Arrange
      adapter.queueFailed(
        MenuFetchFailureReason.platformChanged,
        statusCode: 500,
      );

      // Act
      final result = await repository.load(_woltRef);

      // Assert
      expect(
        result,
        equals(
          const MenuFetchFailed(
            reason: MenuFetchFailureReason.platformChanged,
            statusCode: 500,
          ),
        ),
      );
    });

    test('load with no adapter for the ref returns unsupportedSource without '
        'a network attempt', () async {
      // Act
      final result = await repository.load(_tenbisRef);

      // Assert
      expect(
        result,
        equals(
          const MenuFetchFailed(
            reason: MenuFetchFailureReason.unsupportedSource,
          ),
        ),
      );
      expect(adapter.fetchCalls, isEmpty);
    });

    test('load with a ref resolved from a pasted 10bis.co.il URL still '
        'returns unsupportedSource — recognising the URL is not the same '
        'as having an adapter for it', () async {
      // Arrange
      final ref = VenueRefResolver.resolve(
        'https://www.10bis.co.il/Restaurants/Menu/123456',
      );

      // Act
      final result = await repository.load(ref!);

      // Assert
      expect(
        result,
        equals(
          const MenuFetchFailed(
            reason: MenuFetchFailureReason.unsupportedSource,
          ),
        ),
      );
      expect(adapter.fetchCalls, isEmpty);
    });

    test('registering a second adapter routes to it with no repository '
        'change (architecture.md §18.1, Open/Closed)', () async {
      // Arrange: a second CachedMenuRepository instance with two
      // adapters registered, proving a new platform is purely a
      // registration — no change to CachedMenuRepository itself.
      final woltAdapter = FakePlatformMenuAdapter();
      final tenbisAdapter = FakePlatformMenuAdapter(source: MenuSource.tenbis);
      final multiRepository = CachedMenuRepository(
        adapters: [woltAdapter, tenbisAdapter],
        cache: cache,
        clock: clock,
        freshFor: _freshFor,
      );
      final tenbisMenu = _menuWith(_tenbisRef, clock.now());
      tenbisAdapter.queueFetched(tenbisMenu);

      // Act
      final result = await multiRepository.load(_tenbisRef);

      // Assert: the newly-registered adapter answered; the first
      // adapter, which cannot handle a tenbis ref, was never asked.
      expect(result, equals(MenuFetched(menu: tenbisMenu)));
      expect(tenbisAdapter.fetchCalls, [_tenbisRef]);
      expect(woltAdapter.fetchCalls, isEmpty);
    });

    test(
      'load with forceRefresh skips a fresh cache hit and still writes',
      () async {
        // Arrange: a menu that would otherwise be served from cache.
        final oldMenu = _menuWith(_woltRef, clock.now());
        await cache.write(CachedMenu(menu: oldMenu));
        final freshFetch = _menuWith(_woltRef, clock.now(), dishText: 'B');
        adapter.queueFetched(freshFetch);

        // Act
        final result = await repository.load(_woltRef, forceRefresh: true);

        // Assert
        expect(adapter.fetchCalls, [_woltRef]);
        expect(result, equals(MenuFetched(menu: freshFetch)));
        expect((await cache.read(_woltRef))?.menu, freshFetch);
      },
    );

    test('load with forceRefresh still falls back to a cached menu when the '
        'adapter fails', () async {
      // Arrange: the cached menu is still within freshFor, but
      // forceRefresh bypasses the early return so the adapter is asked
      // anyway.
      final menu = _menuWith(_woltRef, clock.now());
      await cache.write(CachedMenu(menu: menu));
      adapter.queueFailed(MenuFetchFailureReason.offline);

      // Act
      final result = await repository.load(_woltRef, forceRefresh: true);

      // Assert
      expect(
        result,
        equals(
          MenuFetched(
            menu: menu,
            fromCache: true,
            staleReason: MenuFetchFailureReason.offline,
          ),
        ),
      );
    });

    test("load keeps the existing analysis when the refetched menu's "
        'fingerprint is unchanged', () async {
      // Arrange
      final oldMenu = _menuWith(_woltRef, clock.now());
      await cache.write(CachedMenu(menu: oldMenu, analysis: _someAnalysis));
      final refetched = _menuWith(
        _woltRef,
        clock.now().add(const Duration(hours: 1)),
      );
      adapter.queueFetched(refetched);

      // Act
      await repository.load(_woltRef, forceRefresh: true);

      // Assert
      final entry = await cache.read(_woltRef);
      expect(entry?.analysis, equals(_someAnalysis));
      expect(entry?.menu, equals(refetched));
    });

    test("load keeps the existing analysis when the refetched menu's dish "
        "text differs only by whitespace — issue #49's acceptance "
        'criterion', () async {
      // Arrange
      final oldMenu = _menuWith(_woltRef, clock.now(), dishText: 'Steak');
      await cache.write(CachedMenu(menu: oldMenu, analysis: _someAnalysis));
      final refetched = _menuWith(
        _woltRef,
        clock.now().add(const Duration(hours: 1)),
        dishText: '  Steak  ',
      );
      adapter.queueFetched(refetched);

      // Act
      await repository.load(_woltRef, forceRefresh: true);

      // Assert
      final entry = await cache.read(_woltRef);
      expect(entry?.analysis, equals(_someAnalysis));
      expect(entry?.menu, equals(refetched));
    });

    test('load drops the existing analysis when the refetched menu gains '
        "a dish — issue #49's acceptance criterion", () async {
      // Arrange
      final oldMenu = _menuWith(_woltRef, clock.now());
      await cache.write(CachedMenu(menu: oldMenu, analysis: _someAnalysis));
      final refetched = Menu(
        venueRef: _woltRef,
        currency: 'ILS',
        fetchedAt: clock.now().add(const Duration(hours: 1)),
        categories: <MenuCategory>[
          ...oldMenu.categories,
          const MenuCategory(
            id: 'c2',
            name: 'Extras',
            dishes: <Dish>[
              Dish(
                id: 'd2',
                name: 'Extra dish',
                description: '',
                price: 5,
                options: <DishOption>[],
              ),
            ],
          ),
        ],
      );
      adapter.queueFetched(refetched);

      // Act
      await repository.load(_woltRef, forceRefresh: true);

      // Assert
      final entry = await cache.read(_woltRef);
      expect(entry?.analysis, isNull);
    });

    test("load drops the existing analysis when the refetched menu's "
        'fingerprint changes', () async {
      // Arrange
      final oldMenu = _menuWith(_woltRef, clock.now());
      await cache.write(CachedMenu(menu: oldMenu, analysis: _someAnalysis));
      final refetched = _menuWith(
        _woltRef,
        clock.now().add(const Duration(hours: 1)),
        dishText: 'Different dish',
      );
      adapter.queueFetched(refetched);

      // Act
      await repository.load(_woltRef, forceRefresh: true);

      // Assert
      final entry = await cache.read(_woltRef);
      expect(entry?.analysis, isNull);
    });

    test(
      'load returns the fetched menu even when the cache fails to write',
      () async {
        // Arrange
        cache.failOnWrite = true;

        // Act
        final result = await repository.load(_woltRef);

        // Assert
        expect(result, isA<MenuFetched>());
        expect((result as MenuFetched).fromCache, isFalse);
      },
    );

    test('cached returns the entry without calling the adapter', () async {
      // Arrange
      final menu = _menuWith(_woltRef, clock.now());
      await cache.write(CachedMenu(menu: menu));

      // Act
      final entry = await repository.cached(_woltRef);

      // Assert
      expect(entry?.menu, equals(menu));
      expect(adapter.fetchCalls, isEmpty);
    });

    test('saveAnalysis attaches the analysis to the cached menu', () async {
      // Arrange
      final menu = _menuWith(_woltRef, clock.now());
      await cache.write(CachedMenu(menu: menu));

      // Act
      await repository.saveAnalysis(_woltRef, _someAnalysis);

      // Assert
      final entry = await cache.read(_woltRef);
      expect(entry?.menu, equals(menu));
      expect(entry?.analysis, equals(_someAnalysis));
    });

    test('saveAnalysis creates no cache entry when none was cached', () async {
      // Act
      await repository.saveAnalysis(_woltRef, _someAnalysis);

      // Assert
      expect(await cache.read(_woltRef), isNull);
    });

    test('clearCache empties the cache', () async {
      // Arrange
      await cache.write(CachedMenu(menu: _menuWith(_woltRef, clock.now())));

      // Act
      await repository.clearCache();

      // Assert
      expect(await repository.cached(_woltRef), isNull);
      expect(cache.clearCallCount, 1);
    });
  });
}
