import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';

import 'menu_cache_contract.dart';

/// The Hive box name every cache in this file opens. Each test calls
/// `Hive.init` with its own temporary directory in `setUp`, so reusing
/// one name never leaks state between tests.
const _boxName = 'menu_cache';

/// A minimal [Menu] for [ref], with no categories.
Menu _menuFor(VenueRef ref, {DateTime? fetchedAt}) => Menu(
  venueRef: ref,
  currency: 'ILS',
  fetchedAt: fetchedAt ?? DateTime.utc(2026),
  categories: const <MenuCategory>[],
);

/// Opens (or reuses) the shared test box.
Future<Box<String>> _openTestBox() => Hive.openBox<String>(_boxName);

/// A fresh [HiveMenuCache] over the shared test box.
HiveMenuCache _buildCache() => HiveMenuCache(openBox: _openTestBox);

void main() {
  const woltRef = VenueRef(source: MenuSource.wolt, platformId: 'x');
  const tenbisRef = VenueRef(source: MenuSource.tenbis, platformId: 'x');

  late Directory tempDir;

  setUp(() {
    // Arrange: a real, isolated Hive home per test so no state leaks
    // between tests and no plugin binding is required.
    tempDir = Directory.systemTemp.createTempSync('hive_menu_cache_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  runMenuCacheContract('HiveMenuCache', _buildCache);

  group('HiveMenuCache', () {
    test(
      'write then read round-trips an entry with an LlmEngine analysis',
      () async {
        // Arrange
        final cache = _buildCache();
        final entry = CachedMenu(
          menu: _menuFor(woltRef),
          analysis: MenuAnalysed(
            dishes: const <AnalysedDish>[],
            unclassified: const <String>['Mystery dish'],
            engine: const LlmEngine(model: 'test/model'),
            analysedAt: DateTime.utc(2026, 1, 1, 12),
          ),
        );

        // Act
        await cache.write(entry);
        final result = await cache.read(woltRef);

        // Assert
        expect(result, equals(entry));
      },
    );

    test(
      'write then read round-trips an entry with a RulesEngine analysis',
      () async {
        // Arrange
        final cache = _buildCache();
        final entry = CachedMenu(
          menu: _menuFor(woltRef),
          analysis: MenuAnalysed(
            dishes: const <AnalysedDish>[],
            unclassified: const <String>['Mystery dish'],
            engine: const RulesEngine(
              reason: MenuAnalysisFailureReason.offline,
            ),
            analysedAt: DateTime.utc(2026, 1, 1, 12),
          ),
        );

        // Act
        await cache.write(entry);
        final result = await cache.read(woltRef);

        // Assert
        expect(result, equals(entry));
      },
    );

    test('read on a corrupt entry returns a miss', () async {
      // Arrange
      final box = await _openTestBox();
      await box.put(woltRef.cacheKey, 'not valid json{');
      final cache = _buildCache();

      // Act
      final result = await cache.read(woltRef);

      // Assert
      expect(result, isNull);
    });

    test('read on a JSON entry shaped wrong returns a miss', () async {
      // Arrange
      final box = await _openTestBox();
      await box.put(woltRef.cacheKey, '"just a string, not a map"');
      final cache = _buildCache();

      // Act
      final result = await cache.read(woltRef);

      // Assert
      expect(result, isNull);
    });

    test('read returns null when opening the box throws', () async {
      // Arrange
      final cache = HiveMenuCache(
        openBox: () => Future<Box<String>>.error(HiveError('boom')),
      );

      // Act
      final result = await cache.read(woltRef);

      // Assert
      expect(result, isNull);
    });

    test('write does nothing when opening the box throws', () async {
      // Arrange
      final cache = HiveMenuCache(
        openBox: () => Future<Box<String>>.error(HiveError('boom')),
      );

      // Act & Assert
      await expectLater(
        cache.write(CachedMenu(menu: _menuFor(woltRef))),
        completes,
      );
    });

    test('clear does nothing when opening the box throws', () async {
      // Arrange
      final cache = HiveMenuCache(
        openBox: () => Future<Box<String>>.error(HiveError('boom')),
      );

      // Act & Assert
      await expectLater(cache.clear(), completes);
    });

    test('read, write and clear degrade once the box is closed underneath '
        'them', () async {
      // Arrange
      final closedBox = await _openTestBox();
      await closedBox.close();
      final cache = HiveMenuCache(openBox: () async => closedBox);

      // Act
      final readResult = await cache.read(woltRef);

      // Assert
      expect(readResult, isNull);
      await expectLater(
        cache.write(CachedMenu(menu: _menuFor(woltRef))),
        completes,
      );
      await expectLater(cache.clear(), completes);
    });

    test('size returns 0 when opening the box throws', () async {
      // Arrange
      final cache = HiveMenuCache(
        openBox: () => Future<Box<String>>.error(HiveError('boom')),
      );

      // Act
      final result = await cache.size();

      // Assert
      expect(result, equals(0));
    });

    test('size returns 0 once the box is closed underneath it', () async {
      // Arrange
      final closedBox = await _openTestBox();
      await closedBox.close();
      final cache = HiveMenuCache(openBox: () async => closedBox);

      // Act & Assert
      await expectLater(cache.size(), completion(equals(0)));
    });

    test('opens the box once across several operations', () async {
      // Arrange
      var openCount = 0;
      final cache = HiveMenuCache(
        openBox: () {
          openCount++;
          return _openTestBox();
        },
      );

      // Act
      await cache.read(woltRef);
      await cache.write(CachedMenu(menu: _menuFor(woltRef)));
      await cache.read(woltRef);
      await cache.write(CachedMenu(menu: _menuFor(tenbisRef)));
      await cache.clear();
      await cache.read(tenbisRef);

      // Assert
      expect(openCount, equals(1));
    });

    test("two caches over the same box see each other's writes", () async {
      // Arrange
      final writer = _buildCache();
      final reader = _buildCache();
      final entry = CachedMenu(menu: _menuFor(woltRef));

      // Act
      await writer.write(entry);
      final result = await reader.read(woltRef);

      // Assert
      expect(result, equals(entry));
    });
  });
}
