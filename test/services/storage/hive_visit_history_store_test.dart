import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';

import '../../fakes/fake_clock.dart';
import 'visit_history_store_contract.dart';

/// The Hive box name every store in this file opens. Each test calls
/// `Hive.init` with its own temporary directory in `setUp`, so reusing one
/// name never leaks state between tests.
const _boxName = 'menu_history';

/// Opens (or reuses) the shared test box.
Future<Box<String>> _openTestBox() => Hive.openBox<String>(_boxName);

/// A fresh [HiveVisitHistoryStore] over the shared test box.
HiveVisitHistoryStore _buildStore(FakeClock clock) =>
    HiveVisitHistoryStore(openBox: _openTestBox, clock: clock);

/// A store whose box can never be opened.
HiveVisitHistoryStore _brokenStore() => HiveVisitHistoryStore(
  openBox: () => Future<Box<String>>.error(HiveError('boom')),
  clock: FakeClock(DateTime.utc(2026)),
);

void main() {
  const woltRef = VenueRef(source: MenuSource.wolt, platformId: 'x');
  const tenbisRef = VenueRef(source: MenuSource.tenbis, platformId: 'y');

  late Directory tempDir;

  setUp(() {
    // Arrange: a real, isolated Hive home per test so no state leaks
    // between tests and no plugin binding is required.
    tempDir = Directory.systemTemp.createTempSync('hive_visit_history_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  runVisitHistoryStoreContract('HiveVisitHistoryStore', _buildStore);

  group('HiveVisitHistoryStore', () {
    test('entries skips a corrupt entry and keeps the rest', () async {
      // Arrange
      final store = _buildStore(FakeClock(DateTime.utc(2026)));
      await store.recordVisit(woltRef, name: 'Kept');
      final box = await _openTestBox();
      await box.put('wolt/broken', 'not valid json{');
      await box.put('wolt/wrong-shape', '"just a string"');
      await box.put('wolt/no-ref', jsonEncode(<String, Object?>{'a': 1}));

      // Act
      final entries = await store.entries();

      // Assert
      expect(entries, hasLength(1));
      expect(entries.single.name, 'Kept');
    });

    test('read on a corrupt entry returns a miss', () async {
      // Arrange
      final box = await _openTestBox();
      await box.put(woltRef.cacheKey, 'not valid json{');
      final store = _buildStore(FakeClock(DateTime.utc(2026)));

      // Act & Assert
      expect(await store.read(woltRef), isNull);
    });

    test('recordVisit over a corrupt entry starts a fresh one', () async {
      // Arrange
      final box = await _openTestBox();
      await box.put(woltRef.cacheKey, 'not valid json{');
      final store = _buildStore(FakeClock(DateTime.utc(2026)));

      // Act
      await store.recordVisit(woltRef, name: 'Fresh');

      // Assert
      final entry = (await store.read(woltRef))!;
      expect(entry.openCount, 1);
      expect(entry.name, 'Fresh');
    });

    test('a HiveError on open reads as a miss and never throws', () async {
      // Arrange
      final store = _brokenStore();

      // Act & Assert
      expect(await store.read(woltRef), isNull);
      expect(await store.entries(), isEmpty);
      await expectLater(store.recordVisit(woltRef, name: 'x'), completes);
      await expectLater(
        store.rename(woltRef, name: 'x', city: null),
        completes,
      );
      await expectLater(store.remove(woltRef), completes);
      await expectLater(store.clear(), completes);
    });

    test('every call degrades once the box is closed underneath it', () async {
      // Arrange
      final closed = await _openTestBox();
      await closed.close();
      final store = HiveVisitHistoryStore(
        openBox: () async => closed,
        clock: FakeClock(DateTime.utc(2026)),
      );

      // Act & Assert
      expect(await store.read(woltRef), isNull);
      expect(await store.entries(), isEmpty);
      await expectLater(store.recordVisit(woltRef), completes);
      await expectLater(
        store.rename(woltRef, name: null, city: null),
        completes,
      );
      await expectLater(store.remove(woltRef), completes);
      await expectLater(store.clear(), completes);
    });

    test('opens the box at most once', () async {
      // Arrange
      var opens = 0;
      final store = HiveVisitHistoryStore(
        openBox: () {
          opens++;
          return _openTestBox();
        },
        clock: FakeClock(DateTime.utc(2026)),
      );

      // Act
      await store.recordVisit(woltRef);
      await store.read(woltRef);
      await store.entries();

      // Assert
      expect(opens, 1);
    });

    test(
      'an entry survives an unknown field and a missing openCount',
      () async {
        // Arrange: written by some other build of the app.
        final box = await _openTestBox();
        await box.put(
          tenbisRef.cacheKey,
          jsonEncode(<String, Object?>{
            'source': 'tenbis',
            'platformId': 'y',
            'name': 'Old Build',
            'firstOpenedAt': '2026-01-01T00:00:00.000Z',
            'lastOpenedAt': '2026-01-02T00:00:00.000Z',
            'favouriteColour': 'green',
          }),
        );
        final store = _buildStore(FakeClock(DateTime.utc(2026, 2)));

        // Act
        final read = await store.read(tenbisRef);
        await store.recordVisit(tenbisRef);
        final after = await store.read(tenbisRef);

        // Assert
        expect(read!.name, 'Old Build');
        expect(read.openCount, 1);
        expect(after!.openCount, 2);
        expect(after.firstOpenedAt, DateTime.utc(2026));
        expect(after.lastOpenedAt, DateTime.utc(2026, 2));
      },
    );

    test('a value written survives a fresh store over the same box', () async {
      // Arrange
      await _buildStore(FakeClock(DateTime.utc(2026)))
          .recordVisit(woltRef, name: 'Vitrina', city: 'Tel Aviv', score: 7);

      // Act
      final read = await _buildStore(FakeClock(DateTime.utc(2027)))
          .read(woltRef);

      // Assert
      expect(
        read,
        VisitEntry(
          ref: woltRef,
          name: 'Vitrina',
          city: 'Tel Aviv',
          firstOpenedAt: DateTime.utc(2026),
          lastOpenedAt: DateTime.utc(2026),
          openCount: 1,
          score: 7,
        ),
      );
    });
  });

  group('NoVisitHistoryStore', () {
    test('remembers nothing', () async {
      // Arrange
      const store = NoVisitHistoryStore();

      // Act
      await store.recordVisit(woltRef, name: 'x');
      await store.rename(woltRef, name: 'y', city: null);
      await store.remove(woltRef);
      await store.clear();

      // Assert
      expect(await store.read(woltRef), isNull);
      expect(await store.entries(), isEmpty);
    });
  });
}
