// What other people were told by the staff, from the backend to the menu
// screen (Banto, ALG-14, issue #409): BackendMenuAdapter reads the
// optional `confirmations` list only with Banto on, the menu cache keeps
// it (written only when present), and the repository passes it through
// fresh and cached.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dish_confirmation.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/shared_confirmation.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/menu/backend/backend_menu_adapter.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';

import '../../fakes/fake_clock.dart';
import '../../fakes/fake_install_id_store.dart';
import '../../fakes/fake_menu_cache.dart';
import '../../fakes/fake_platform_menu_adapter.dart';

const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'hamosad');

final DateTime _fetchedAt = DateTime.utc(2026, 10, 15, 12);

Menu _menu() => Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: _fetchedAt,
  categories: const <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'Mains',
      dishes: <Dish>[
        Dish(
          id: 'd1',
          name: 'סלט חצילים',
          description: '',
          price: 42,
          options: <DishOption>[],
        ),
      ],
    ),
  ],
);

/// The wire list: four people were told there is no sesame in d1.
final List<Object?> _wire = <Object?>[
  <String, Object?>{
    'dishFingerprint': dishFingerprint('d1'),
    'restrictionId': 'sesame',
    'present': 0,
    'absent': 4,
    'first': '2026-10-01',
    'last': '2026-10-12',
  },
];

final SharedConfirmations _shared = SharedConfirmations.tryFrom(_wire)!;

BackendMenuAdapter _adapter(Object? body, {required bool bantoMode}) =>
    BackendMenuAdapter(
      client: MockClient(
        (request) async => http.Response.bytes(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'menu': _menu().toJson(),
              'analysis': null,
              'fromCache': false,
              'fetchedAt': _fetchedAt.toIso8601String(),
              'confirmations': ?body,
            }),
          ),
          200,
        ),
      ),
      baseUrl: Uri.parse('http://localhost:8000'),
      installIdStore: FakeInstallIdStore(installId: 'install'),
      source: MenuSource.wolt,
      readOptions: () async => const ClassificationOptions(),
      bantoMode: bantoMode,
    );

void main() {
  group('BackendMenuAdapter reads confirmations', () {
    test('with Banto on, the counts ride on the result', () async {
      // Act
      final result = await _adapter(_wire, bantoMode: true).fetch(_ref);

      // Assert
      final shared = (result as MenuFetched).sharedConfirmations;
      expect(shared, _shared);
      expect(shared!.forDish('d1').single.restrictionId, RestrictionId.sesame);
    });

    test('with Banto off, the key is never read', () async {
      // Act
      final result = await _adapter(_wire, bantoMode: false).fetch(_ref);

      // Assert
      expect((result as MenuFetched).sharedConfirmations, isNull);
    });

    test('absent or unreadable is none, and the menu still reads', () async {
      for (final body in <Object?>[
        null,
        'counts',
        <Object?>[],
        <Object?>[1],
      ]) {
        // Act
        final result = await _adapter(body, bantoMode: true).fetch(_ref);

        // Assert
        expect(result, isA<MenuFetched>());
        expect((result as MenuFetched).sharedConfirmations, isNull);
        expect(result.menu.allDishes.single.id, 'd1');
      }
    });
  });

  group('CachedMenu keeps the counts', () {
    test('written only when present', () {
      // Arrange
      final without = CachedMenu(menu: _menu());
      final with_ = CachedMenu(menu: _menu(), sharedConfirmations: _shared);

      // Assert: an entry without counts is the bytes it was before.
      expect(without.toJson().keys, ['menu', 'analysis']);
      expect(with_.toJson()['sharedConfirmations'], _shared.toJson());
      expect(CachedMenu.tryFrom(with_.toJson()), with_);
      expect(CachedMenu.tryFrom(with_.toJson())?.hashCode, with_.hashCode);
      expect(CachedMenu.tryFrom(without.toJson()), without);
    });

    test('unreadable counts never fail the entry', () {
      // Arrange
      final json = CachedMenu(menu: _menu()).toJson()
        ..['sharedConfirmations'] = 'broken';

      // Act
      final read = CachedMenu.tryFrom(json);

      // Assert
      expect(read?.menu, _menu());
      expect(read?.sharedConfirmations, isNull);
    });

    test('kept beside an analysis', () {
      // Arrange
      final entry = CachedMenu(
        menu: _menu(),
        analysis: MenuAnalysed(
          dishes: const <AnalysedDish>[],
          unclassified: const <String>['סלט חצילים'],
          engine: const LlmEngine(model: 'test-model'),
          analysedAt: _fetchedAt,
        ),
        sharedConfirmations: _shared,
      );

      // Act
      final read = CachedMenu.tryFrom(entry.toJson());

      // Assert
      expect(read?.sharedConfirmations, _shared);
    });
  });

  group('CachedMenuRepository passes the counts through', () {
    late FakeMenuCache cache;
    late FakePlatformMenuAdapter adapter;
    late CachedMenuRepository repository;

    setUp(() {
      cache = FakeMenuCache();
      adapter = FakePlatformMenuAdapter();
      repository = CachedMenuRepository(
        adapters: <PlatformMenuAdapter>[adapter],
        cache: cache,
        clock: FakeClock(_fetchedAt.add(const Duration(minutes: 5))),
      );
    });

    test('fresh, cached and stale', () async {
      // Arrange
      adapter.queueResult(
        MenuFetched(menu: _menu(), sharedConfirmations: _shared),
      );

      // Act
      final fresh = await repository.load(_ref);
      final cached = await repository.load(_ref);
      adapter.queueFailed(MenuFetchFailureReason.offline);
      final stale = await repository.load(_ref, forceRefresh: true);

      // Assert
      expect((fresh as MenuFetched).sharedConfirmations, _shared);
      expect((cached as MenuFetched).fromCache, isTrue);
      expect(cached.sharedConfirmations, _shared);
      expect((stale as MenuFetched).sharedConfirmations, _shared);
    });

    test('a fresh answer without counts means none now', () async {
      // Arrange
      adapter
        ..queueResult(MenuFetched(menu: _menu(), sharedConfirmations: _shared))
        ..queueResult(MenuFetched(menu: _menu()));
      await repository.load(_ref);

      // Act
      final refreshed = await repository.load(_ref, forceRefresh: true);

      // Assert
      expect((refreshed as MenuFetched).sharedConfirmations, isNull);
      expect((await repository.cached(_ref))?.sharedConfirmations, isNull);
    });

    test('saving an analysis keeps the counts', () async {
      // Arrange
      adapter.queueResult(
        MenuFetched(menu: _menu(), sharedConfirmations: _shared),
      );
      await repository.load(_ref);

      // Act
      await repository.saveAnalysis(
        _ref,
        MenuAnalysed(
          dishes: const <AnalysedDish>[],
          unclassified: const <String>['סלט חצילים'],
          engine: const LlmEngine(model: 'test-model'),
          analysedAt: _fetchedAt,
        ),
      );

      // Assert
      expect((await repository.cached(_ref))?.sharedConfirmations, _shared);
    });

    test('MenuFetched compares the counts', () {
      // Arrange
      final a = MenuFetched(menu: _menu(), sharedConfirmations: _shared);
      final b = MenuFetched(menu: _menu(), sharedConfirmations: _shared);

      // Assert
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(MenuFetched(menu: _menu())));
    });
  });
}
