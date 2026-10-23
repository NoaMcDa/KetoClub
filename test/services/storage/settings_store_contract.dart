import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
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
        estimationConsentGiven: false,
        lastVenue: VenueRef(source: MenuSource.wolt, platformId: 'v1'),
        themeMode: AppThemeMode.dark,
        netCarbLimitGrams: 14,
        seedOilFree: true,
        dairyFree: true,
        lastFilter: MenuFilter.yellowOnly,
        disclosureSeen: true,
      );

      await store.write(settings);

      expect(await store.read(), equals(settings));
    });

    test('write then read round-trips every combination of the dietary '
        'toggles (issue #56)', () async {
      final store = build();

      for (final seedOil in <bool>[false, true]) {
        for (final dairy in <bool>[false, true]) {
          for (final carnivore in <bool>[false, true]) {
            final settings = AppSettings(
              seedOilFree: seedOil,
              dairyFree: dairy,
              carnivoreOnly: carnivore,
            );

            await store.write(settings);

            expect(await store.read(), equals(settings));
          }
        }
      }
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

    test(
      'write then read round-trips a dietary profile (issue #344)',
      () async {
        final store = build();
        final settings = AppSettings(
          languageTag: 'he',
          profile: DietaryProfile.empty
              .withEntry(RestrictionId.sesame)
              .withEntry(RestrictionId.lactose, exceptions: <String>['butter']),
        );

        await store.write(settings);

        expect(await store.read(), equals(settings));
      },
    );

    test('writing an empty profile after a full one clears it', () async {
      final store = build();

      await store.write(
        AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.fish),
        ),
      );
      await store.write(const AppSettings());

      expect((await store.read()).profile, DietaryProfile.empty);
    });

    test('read never throws', () async {
      final store = build();

      await expectLater(store.read(), completes);
    });

    test('write never throws', () async {
      final store = build();

      await expectLater(store.write(const AppSettings()), completes);
    });

    test('update applies the change to the latest stored settings, not to '
        'an older snapshot (issue #287)', () async {
      // Arrange: a snapshot is read, then consent is withdrawn elsewhere.
      final store = build();
      final snapshot = await store.read();
      await store.write(snapshot.copyWith(estimationConsentGiven: false));

      // Act: the snapshot's holder changes only its own field.
      final saved = await store.update(
        (latest) => latest.copyWith(disclosureSeen: true),
      );

      // Assert: the withdrawal survives, and update answers what it saved.
      final result = await store.read();
      expect(result.estimationConsentGiven, isFalse);
      expect(result.disclosureSeen, isTrue);
      expect(saved, equals(result));
    });

    test('two overlapping updates both land (issue #287)', () async {
      final store = build();
      const venue = VenueRef(source: MenuSource.wolt, platformId: 'v1');

      await Future.wait(<Future<AppSettings>>[
        store.update((latest) => latest.copyWith(lastVenue: venue)),
        store.update(
          (latest) => latest.copyWith(lastFilter: MenuFilter.greenOnly),
        ),
      ]);

      final result = await store.read();
      expect(result.lastVenue, equals(venue));
      expect(result.lastFilter, equals(MenuFilter.greenOnly));
    });

    test('update never throws when the change does not', () async {
      final store = build();

      await expectLater(store.update((latest) => latest), completes);
    });
  });
}
