import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/storage_key.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';

final class _Clock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 11, 12);
}

Menu _menu(VenueRef ref) => Menu(
  venueRef: ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[],
);

void main() {
  final longRef = VenueRef(
    source: MenuSource.website,
    platformId: 'https://cafe.co.il/menu?utm_source=ig&fbclid=${'a' * 300}',
  );
  const shortRef = VenueRef(source: MenuSource.wolt, platformId: 'hamosad');

  group('storageKeyFor (issue #280)', () {
    test('keeps a short key unchanged', () {
      expect(storageKeyFor(shortRef), equals(shortRef.cacheKey));
    });

    test('bounds a long key to the Hive limit, stable and distinct', () {
      final key = storageKeyFor(longRef);

      expect(utf8.encode(key).length, lessThanOrEqualTo(maxStorageKeyBytes));
      expect(storageKeyFor(longRef), equals(key));
      expect(
        storageKeyFor(
          VenueRef(
            source: MenuSource.website,
            platformId: '${longRef.platformId}b',
          ),
        ),
        isNot(equals(key)),
      );
    });

    test('measures bytes, not characters', () {
      final hebrew = VenueRef(
        source: MenuSource.website,
        platformId: 'https://a.co.il/${'ק' * 130}',
      );

      expect(
        utf8.encode(storageKeyFor(hebrew)).length,
        lessThanOrEqualTo(maxStorageKeyBytes),
      );
    });
  });

  test('timestamps are stored in UTC and keep the instant (issue #284)', () {
    // A local time with an offset: written without one, it would read back
    // shifted in another time zone.
    final local = DateTime.parse('2026-11-12T10:00:00+02:00');
    final menu = Menu(
      venueRef: shortRef,
      currency: 'ILS',
      fetchedAt: local,
      categories: const <MenuCategory>[],
    );

    final json = menu.toJson();
    final back = Menu.tryFrom(json);

    expect(json['fetchedAt'], endsWith('Z'));
    expect(back!.fetchedAt.isAtSameMomentAs(local), isTrue);
  });

  group('real boxes', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('storage_key_test_');
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
    });

    test('the menu cache stores, reads and pins a long website ref '
        '(issue #280)', () async {
      final cache = HiveMenuCache(
        openBox: () => Hive.openBox<String>('c'),
        openPinBox: () => Hive.openBox<String>('p'),
      );

      await cache.write(CachedMenu(menu: _menu(longRef)));
      await cache.pin(longRef);

      expect((await cache.read(longRef))?.menu.venueRef, equals(longRef));
      expect(await cache.isPinned(longRef), isTrue);
    });

    test('the visit history records and removes a long website ref '
        '(issue #280)', () async {
      final store = HiveVisitHistoryStore(
        openBox: () => Hive.openBox<String>('h'),
        clock: _Clock(),
      );

      await store.recordVisit(longRef);

      expect((await store.entries()).map((e) => e.ref), [longRef]);
      await store.remove(longRef);
      expect(await store.entries(), isEmpty);
    });

    test('a failed box open is retried on the next call and never throws '
        '(issue #284)', () async {
      var attempts = 0;
      final cache = HiveMenuCache(
        openBox: () {
          attempts++;
          if (attempts == 1) {
            throw const FileSystemException('disk unavailable');
          }
          return Hive.openBox<String>('retry');
        },
      );

      await cache.write(CachedMenu(menu: _menu(shortRef)));
      expect(await cache.read(shortRef), isNull);
      await cache.write(CachedMenu(menu: _menu(shortRef)));

      expect(attempts, 2);
      expect(await cache.read(shortRef), isNotNull);
    });
  });
}
