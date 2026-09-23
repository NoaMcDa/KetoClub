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
        filter: MenuFilter.greenOnly,
        estimationConsentGiven: true,
        lastVenue: VenueRef(source: MenuSource.wolt, platformId: 'v1'),
        themeMode: AppThemeMode.dark,
        netCarbLimitGrams: 14,
        lastFilter: MenuFilter.yellowOnly,
      );

      await store.write(settings);

      expect(await store.read(), equals(settings));
    });

    test(
      'write then read round-trips every MenuFilter as lastFilter',
      () async {
        final store = build();

        for (final filter in MenuFilter.values) {
          await store.write(AppSettings(lastFilter: filter));

          expect((await store.read()).lastFilter, equals(filter));
        }
      },
    );

    test('write then read round-trips lastFilter as null when unset', () async {
      final store = build();

      await store.write(const AppSettings(lastFilter: MenuFilter.redOnly));
      await store.write(const AppSettings());

      expect((await store.read()).lastFilter, isNull);
    });

    test('write then read round-trips the net-carb limit bounds', () async {
      final store = build();

      for (final grams in <int>[2, 6, 25]) {
        await store.write(AppSettings(netCarbLimitGrams: grams));

        expect((await store.read()).netCarbLimitGrams, equals(grams));
      }
    });

    test('write then read round-trips every AppThemeMode value', () async {
      final store = build();

      for (final mode in AppThemeMode.values) {
        await store.write(AppSettings(themeMode: mode));

        expect((await store.read()).themeMode, equals(mode));
      }
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
