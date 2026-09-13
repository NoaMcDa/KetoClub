import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/settings_store.dart';

/// Asserts the [SettingsStore] contract against the implementation
/// [build] returns. Call this from each implementation's own test file —
/// including the fake — passing a factory that returns a fresh, virgin
/// instance on every call (architecture.md §18.1, Liskov).
void runSettingsStoreContract(String name, SettingsStore Function() build) {
  group('$name (SettingsStore contract)', () {
    test('read on a virgin store returns AppSettings defaults', () async {
      final store = build();

      expect(await store.read(), equals(const AppSettings()));
    });

    test('read on a virgin store never returns null', () async {
      final store = build();

      final result = await store.read();

      expect(result, isNotNull);
      expect(result, isA<AppSettings>());
    });

    test('write then read round-trips the written settings', () async {
      final store = build();
      const settings = AppSettings(
        languageTag: 'he',
        filter: MenuFilter.all,
        estimationConsentGiven: true,
        lastVenue: VenueRef(source: MenuSource.wolt, platformId: 'v1'),
      );

      await store.write(settings);

      expect(await store.read(), equals(settings));
    });

    test('write then read round-trips settings at their defaults', () async {
      final store = build();

      await store.write(const AppSettings());

      expect(await store.read(), equals(const AppSettings()));
    });

    test('write then write replaces the settings, not merges them', () async {
      final store = build();

      await store.write(const AppSettings(languageTag: 'he'));
      await store.write(const AppSettings(languageTag: 'en'));

      expect((await store.read()).languageTag, equals('en'));
    });

    test('read never throws', () async {
      final store = build();

      await expectLater(store.read(), completes);
    });

    test('write never throws', () async {
      final store = build();

      await expectLater(store.write(const AppSettings()), completes);
    });
  });
}
