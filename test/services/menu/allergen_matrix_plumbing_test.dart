// The restaurant's allergen matrix from the backend to the menu screen
// (Banto; ALG-16, related to #358): BackendMenuAdapter reads the optional
// `allergenMatrix` only with Banto on, the menu cache keeps it (written only
// when present), and the repository passes it through fresh and cached.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/models/allergen_matrix.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
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
          name: 'שקשוקה',
          description: '',
          price: 52,
          options: <DishOption>[],
        ),
      ],
    ),
  ],
);

final AllergenMatrix _matrix = AllergenMatrix(
  source: MatrixSource.restaurant,
  validFrom: DateTime.utc(2026, 10),
  rows: const <AllergenMatrixRow>[
    AllergenMatrixRow(
      name: 'שקשוקה',
      aliases: <String>['Shakshuka'],
      cells: <RestrictionId, MatrixCell>{
        RestrictionId.eggs: MatrixCell.contains,
      },
    ),
  ],
);

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
              'allergenMatrix': ?body,
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
  group('BackendMenuAdapter reads allergenMatrix', () {
    test('with Banto on, the matrix rides on the result', () async {
      // Act
      final result = await _adapter(
        _matrix.toJson(),
        bantoMode: true,
      ).fetch(_ref);

      // Assert
      expect((result as MenuFetched).allergenMatrix, _matrix);
    });

    test('with Banto off, the key is never read', () async {
      // Act
      final result = await _adapter(
        _matrix.toJson(),
        bantoMode: false,
      ).fetch(_ref);

      // Assert
      expect((result as MenuFetched).allergenMatrix, isNull);
    });

    test(
      'absent or unreadable is no matrix, and the menu still reads',
      () async {
        for (final body in <Object?>[null, 'matrix', <String, Object?>{}]) {
          // Act
          final result = await _adapter(body, bantoMode: true).fetch(_ref);

          // Assert
          expect(result, isA<MenuFetched>());
          expect((result as MenuFetched).allergenMatrix, isNull);
          expect(result.menu.allDishes.single.name, 'שקשוקה');
        }
      },
    );
  });

  group('CachedMenu keeps the matrix', () {
    test('written only when present', () {
      // Arrange
      final without = CachedMenu(menu: _menu());
      final with_ = CachedMenu(menu: _menu(), allergenMatrix: _matrix);

      // Assert: an entry without one is the bytes it was before.
      expect(without.toJson().keys, ['menu', 'analysis']);
      expect(with_.toJson()['allergenMatrix'], _matrix.toJson());
      expect(CachedMenu.tryFrom(with_.toJson()), with_);
      expect(CachedMenu.tryFrom(without.toJson()), without);
    });

    test('an unreadable matrix never fails the entry', () {
      // Arrange
      final json = CachedMenu(menu: _menu()).toJson()
        ..['allergenMatrix'] = 'broken';

      // Act
      final read = CachedMenu.tryFrom(json);

      // Assert
      expect(read?.menu, _menu());
      expect(read?.allergenMatrix, isNull);
    });

    test('the Hive cache round-trips it', () async {
      // Arrange
      final tempDir = Directory.systemTemp.createTempSync('hive_matrix_');
      Hive.init(tempDir.path);
      addTearDown(Hive.deleteFromDisk);
      final cache = HiveMenuCache(
        openBox: () => Hive.openBox<String>('menu_cache'),
        openPinBox: () => Hive.openBox<String>('menu_cache_pins'),
      );
      final entry = CachedMenu(menu: _menu(), allergenMatrix: _matrix);

      // Act
      await cache.write(entry);

      // Assert
      expect(await cache.read(_ref), entry);
    });
  });

  group('CachedMenuRepository passes the matrix through', () {
    late FakeMenuCache cache;
    late FakePlatformMenuAdapter adapter;
    late CachedMenuRepository repository;
    late FakeClock clock;

    setUp(() {
      cache = FakeMenuCache();
      adapter = FakePlatformMenuAdapter();
      clock = FakeClock(_fetchedAt.add(const Duration(minutes: 5)));
      repository = CachedMenuRepository(
        adapters: <PlatformMenuAdapter>[adapter],
        cache: cache,
        clock: clock,
      );
    });

    test('fresh, cached and stale', () async {
      // Arrange
      adapter.queueResult(MenuFetched(menu: _menu(), allergenMatrix: _matrix));

      // Act
      final fresh = await repository.load(_ref);
      final cached = await repository.load(_ref);
      adapter.queueFailed(MenuFetchFailureReason.offline);
      final stale = await repository.load(_ref, forceRefresh: true);

      // Assert
      expect((fresh as MenuFetched).allergenMatrix, _matrix);
      expect((cached as MenuFetched).fromCache, isTrue);
      expect(cached.allergenMatrix, _matrix);
      expect(
        (stale as MenuFetched).staleReason,
        MenuFetchFailureReason.offline,
      );
      expect(stale.allergenMatrix, _matrix);
    });

    test('a fresh answer without one means none today', () async {
      // Arrange
      adapter
        ..queueResult(MenuFetched(menu: _menu(), allergenMatrix: _matrix))
        ..queueResult(MenuFetched(menu: _menu()));
      await repository.load(_ref);

      // Act
      final refreshed = await repository.load(_ref, forceRefresh: true);

      // Assert
      expect((refreshed as MenuFetched).allergenMatrix, isNull);
      expect((await repository.cached(_ref))?.allergenMatrix, isNull);
    });

    test('saving an analysis keeps the matrix', () async {
      // Arrange
      adapter.queueResult(MenuFetched(menu: _menu(), allergenMatrix: _matrix));
      await repository.load(_ref);

      // Act
      await repository.saveAnalysis(
        _ref,
        MenuAnalysed(
          dishes: const <AnalysedDish>[],
          unclassified: const <String>['שקשוקה'],
          engine: const LlmEngine(model: 'test-model'),
          analysedAt: _fetchedAt,
        ),
      );

      // Assert
      final entry = await repository.cached(_ref);
      expect(entry?.analysis, isNotNull);
      expect(entry?.allergenMatrix, _matrix);
    });
  });
}
