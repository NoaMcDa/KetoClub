import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/storage_key.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';

import '../../fakes/fake_clock.dart';

/// A website ref whose URL is [length] characters long, ASCII only.
VenueRef _websiteOfLength(int length, {String tag = 'a'}) {
  const prefix = 'https://cafe.co.il/menu?q=';
  return VenueRef(
    source: MenuSource.website,
    platformId: prefix + tag * (length - prefix.length),
  );
}

/// The UTF-8 length of [key]: what Hive writes in its one length byte.
int _bytes(String key) => utf8.encode(key).length;

/// A minimal [Menu] for [ref], with no categories.
Menu _menuFor(VenueRef ref) => Menu(
  venueRef: ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[],
);

void main() {
  group('storageKeyFor (issue #280)', () {
    test('keeps every short key exactly as it was', () {
      final refs = <VenueRef, String>{
        const VenueRef(
          source: MenuSource.wolt,
          platformId: 'vitrina-lilinblum',
        ): 'wolt/vitrina-lilinblum',
        const VenueRef(source: MenuSource.tenbis, platformId: '123456'):
            'tenbis/123456',
        const VenueRef(source: MenuSource.scan, platformId: '9f3a00c1'):
            'scan/9f3a00c1',
        const VenueRef(
          source: MenuSource.website,
          platformId: 'https://cafe.co.il/menu?a=1',
        ): 'website/https://cafe.co.il/menu?a=1',
      };
      for (final MapEntry(key: ref, value: key) in refs.entries) {
        expect(storageKeyFor(ref), key, reason: '$ref');
        expect(storageKeyFor(ref), ref.cacheKey);
      }
    });

    test('keeps a key of exactly $maxStorageKeyBytes bytes unchanged', () {
      // 'website/' is 8 bytes, so a 247-character URL is a 255-byte key.
      final ref = _websiteOfLength(maxStorageKeyBytes - 8);

      expect(_bytes(ref.cacheKey), maxStorageKeyBytes);
      expect(storageKeyFor(ref), ref.cacheKey);
    });

    test('hashes a key one byte over the bound', () {
      final ref = _websiteOfLength(maxStorageKeyBytes - 7);

      final key = storageKeyFor(ref);

      expect(_bytes(ref.cacheKey), maxStorageKeyBytes + 1);
      expect(key, startsWith('website/#sha256:'));
      expect(_bytes(key), lessThanOrEqualTo(maxStorageKeyBytes));
    });

    test('never builds a key over $maxStorageKeyBytes UTF-8 bytes, '
        'whatever the length', () {
      for (var length = 30; length <= 2000; length += 7) {
        final key = storageKeyFor(_websiteOfLength(length));
        expect(_bytes(key), lessThanOrEqualTo(maxStorageKeyBytes));
      }
    });

    test('counts bytes, not characters: a Hebrew id under 255 characters '
        'but over 255 bytes is hashed', () {
      // 150 Hebrew letters: 150 UTF-16 units (Hive's assert lets it pass)
      // but 300 UTF-8 bytes (its one length byte does not).
      final ref = VenueRef(source: MenuSource.wolt, platformId: 'ש' * 150);

      final key = storageKeyFor(ref);

      expect(ref.cacheKey.length, lessThan(maxStorageKeyBytes));
      expect(_bytes(ref.cacheKey), greaterThan(maxStorageKeyBytes));
      expect(key, startsWith('wolt/#sha256:'));
      expect(_bytes(key), lessThanOrEqualTo(maxStorageKeyBytes));
    });

    test('is stable, and tells two long URLs apart', () {
      final first = _websiteOfLength(400);
      final second = _websiteOfLength(400, tag: 'b');

      expect(storageKeyFor(first), storageKeyFor(_websiteOfLength(400)));
      expect(storageKeyFor(first), isNot(storageKeyFor(second)));
    });
  });

  group('Hive boxes keyed by a venue (issue #280)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('storage_key_test_');
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
    });

    HiveMenuCache buildCache() => HiveMenuCache(
      openBox: () => Hive.openBox<String>('menu_cache'),
      openPinBox: () => Hive.openBox<String>('menu_cache_pins'),
    );

    test('a website menu with a 400-character URL is cached, pinned and '
        'listed, and every key stays within the bound', () async {
      // Arrange: before the fix Hive refused the key (debug) or corrupted
      // the box (release), so the write never landed.
      final longRef = _websiteOfLength(400);
      const shortRef = VenueRef(source: MenuSource.wolt, platformId: 'x');
      final cache = buildCache();

      // Act
      await cache.write(CachedMenu(menu: _menuFor(longRef)));
      await cache.write(CachedMenu(menu: _menuFor(shortRef)));
      await cache.pin(longRef);

      // Assert
      expect((await cache.read(longRef))?.menu.venueRef, longRef);
      expect((await cache.read(shortRef))?.menu.venueRef, shortRef);
      expect(await cache.isPinned(longRef), isTrue);
      final entries = await cache.entries();
      expect(
        entries.singleWhere((entry) => entry.ref == longRef).pinned,
        isTrue,
      );
      final keys = <Object?>[
        ...(await Hive.openBox<String>('menu_cache')).keys,
        ...(await Hive.openBox<String>('menu_cache_pins')).keys,
      ];
      for (final key in keys) {
        expect(_bytes(key! as String), lessThanOrEqualTo(maxStorageKeyBytes));
      }
      // A short key on disk is unchanged.
      expect(keys, contains('wolt/x'));
    });

    test('every menu cached after a long-URL one survives a reopen', () async {
      // Arrange
      final longRef = _websiteOfLength(300);
      final later = <VenueRef>[
        for (var i = 0; i < 3; i++)
          VenueRef(source: MenuSource.wolt, platformId: 'later-$i'),
      ];
      final cache = buildCache();
      await cache.write(CachedMenu(menu: _menuFor(longRef)));
      for (final ref in later) {
        await cache.write(CachedMenu(menu: _menuFor(ref)));
      }

      // Act: the next launch.
      await Hive.close();
      final reopened = buildCache();

      // Assert
      expect((await reopened.read(longRef))?.menu.venueRef, longRef);
      for (final ref in later) {
        expect((await reopened.read(ref))?.menu.venueRef, ref);
      }
    });

    test('remove forgets a long-URL menu and its pin', () async {
      final longRef = _websiteOfLength(500);
      final cache = buildCache();
      await cache.write(CachedMenu(menu: _menuFor(longRef)));
      await cache.pin(longRef);

      await cache.remove(longRef);

      expect(await cache.read(longRef), isNull);
      expect(await cache.isPinned(longRef), isFalse);
    });

    test('the visit history records, reads and removes a long-URL visit '
        'under a bounded key', () async {
      // Arrange
      final longRef = _websiteOfLength(400);
      final store = HiveVisitHistoryStore(
        openBox: () => Hive.openBox<String>('menu_history'),
        clock: FakeClock(DateTime.utc(2026)),
      );

      // Act
      await store.recordVisit(longRef, name: 'Cafe');

      // Assert
      expect((await store.read(longRef))?.name, 'Cafe');
      final box = await Hive.openBox<String>('menu_history');
      for (final key in box.keys) {
        expect(_bytes(key as String), lessThanOrEqualTo(maxStorageKeyBytes));
      }
      await store.remove(longRef);
      expect(await store.read(longRef), isNull);
    });
  });
}
