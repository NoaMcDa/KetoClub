import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_store_contract.dart';

/// The method channel the default `SharedPreferencesStorePlatform`
/// (`MethodChannelSharedPreferencesStore`) talks to. Mocked directly, and
/// only by the very first test below, so `SharedPreferences.getInstance`
/// resolves through a real (mocked) channel rather than the in-memory
/// store `SharedPreferences.setMockInitialValues` installs for every
/// later test in this file.
const MethodChannel _prefsChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

/// A fresh [PrefsSettingsStore] whose loader is `SharedPreferences
/// .getInstance` over a freshly mocked, initially empty store.
PrefsSettingsStore _buildStore() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return PrefsSettingsStore(load: SharedPreferences.getInstance);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Runs first, and deliberately outside every group below: it is the
  // only test that must see the real (mocked) shared_preferences channel
  // rather than the in-memory store `SharedPreferences
  // .setMockInitialValues` swaps in for every other test in this file.
  test(
    'write completes without throwing when the platform rejects the value',
    () async {
      // Arrange: the load succeeds (a plain "getAll") but the persist
      // call fails, driving PrefsSettingsStore.write's second catch —
      // the one guarding the actual disk write, not the load.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_prefsChannel, (call) async {
            switch (call.method) {
              case 'getAll':
                return <String, Object>{};
              case 'setString':
                throw PlatformException(code: 'boom', message: 'disk full');
              default:
                throw MissingPluginException('Unhandled: ${call.method}');
            }
          });
      final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

      // Act & Assert
      await expectLater(store.write(const AppSettings()), completes);
    },
  );

  // Also runs before any `setMockInitialValues` call, for the same
  // reason as the test above — this one drives the write catch's other
  // branch, `on MissingPluginException`.
  test('write completes without throwing when no shared_preferences plugin '
      'is registered', () async {
    // Arrange
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_prefsChannel, (call) async {
          switch (call.method) {
            case 'getAll':
              return <String, Object>{};
            case 'setString':
              throw MissingPluginException('no plugin registered');
            default:
              throw MissingPluginException('Unhandled: ${call.method}');
          }
        });
    final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

    // Act & Assert
    await expectLater(store.write(const AppSettings()), completes);
  });

  runSettingsStoreContract('PrefsSettingsStore', _buildStore);

  group('PrefsSettingsStore', () {
    test('read returns defaults when the stored string is corrupt', () async {
      // Arrange
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.ketoclub_settings': 'not valid json{',
      });
      final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

      // Act
      final result = await store.read();

      // Assert
      expect(result, equals(const AppSettings()));
    });

    test(
      'read returns defaults when the stored JSON is shaped wrong',
      () async {
        // Arrange
        SharedPreferences.setMockInitialValues(<String, Object>{
          'flutter.ketoclub_settings': '"just a string, not a map"',
        });
        final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

        // Act
        final result = await store.read();

        // Assert
        expect(result, equals(const AppSettings()));
      },
    );

    test('an install that persisted greenAndYellow before issue #35 changed '
        'the default and the Settings control still loads it without a '
        'crash', () async {
      // Arrange: the exact JSON shape `PrefsSettingsStore` wrote before
      // `AppSettings`'s default filter changed from greenAndYellow to
      // all, and before the Settings screen's control dropped
      // greenAndYellow as a choice — `MenuFilter.tryParse` still knows
      // the name (models/analysis.dart), so this must decode cleanly
      // rather than falling back to today's defaults.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.ketoclub_settings':
            '{"languageTag":null,"filter":"greenAndYellow",'
            '"estimationConsentGiven":false,"lastVenue":null}',
      });
      final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

      // Act
      final result = await store.read();

      // Assert: the persisted value survives, not today's default.
      expect(result.filter, equals(MenuFilter.greenAndYellow));
      expect(result.languageTag, isNull);
      expect(result.estimationConsentGiven, isFalse);
      expect(result.lastVenue, isNull);
    });

    test(
      'write then read round-trips every field, including nullable ones',
      () async {
        // Arrange
        final store = _buildStore();
        const settings = AppSettings(
          languageTag: 'he',
          filter: MenuFilter.greenOnly,
          estimationConsentGiven: true,
          lastVenue: VenueRef(source: MenuSource.tabit, platformId: 'site-9'),
        );

        // Act
        await store.write(settings);
        final result = await store.read();

        // Assert
        expect(result, equals(settings));
        expect(result.languageTag, equals('he'));
        expect(result.lastVenue, equals(settings.lastVenue));
      },
    );

    test(
      'write then read round-trips languageTag and lastVenue as null',
      () async {
        // Arrange
        final store = _buildStore();
        await store.write(
          const AppSettings(languageTag: 'en', estimationConsentGiven: true),
        );

        // Act
        await store.write(const AppSettings());
        final result = await store.read();

        // Assert
        expect(result.languageTag, isNull);
        expect(result.lastVenue, isNull);
      },
    );

    test(
      'write then write replaces the settings rather than merging them',
      () async {
        // Arrange
        final store = _buildStore();
        await store.write(
          const AppSettings(
            languageTag: 'he',
            estimationConsentGiven: true,
            lastVenue: VenueRef(source: MenuSource.wolt, platformId: 'v1'),
          ),
        );

        // Act
        await store.write(const AppSettings(languageTag: 'en'));
        final result = await store.read();

        // Assert
        expect(result, equals(const AppSettings(languageTag: 'en')));
        expect(result.estimationConsentGiven, isFalse);
        expect(result.lastVenue, isNull);
      },
    );

    test('read returns defaults when the loader throws', () async {
      // Arrange
      final store = PrefsSettingsStore(
        load: () =>
            Future<SharedPreferences>.error(PlatformException(code: 'boom')),
      );

      // Act
      final result = await store.read();

      // Assert
      expect(result, equals(const AppSettings()));
    });

    test('read returns defaults when the loader throws no-plugin', () async {
      // Arrange
      final store = PrefsSettingsStore(
        load: () => Future<SharedPreferences>.error(
          MissingPluginException('no shared_preferences plugin'),
        ),
      );

      // Act
      final result = await store.read();

      // Assert
      expect(result, equals(const AppSettings()));
    });

    test('write completes without throwing when the loader throws', () async {
      // Arrange
      final store = PrefsSettingsStore(
        load: () => Future<SharedPreferences>.error(
          MissingPluginException('no shared_preferences plugin'),
        ),
      );

      // Act & Assert
      await expectLater(store.write(const AppSettings()), completes);
    });

    test(
      'the loader is invoked once across several read and write calls',
      () async {
        // Arrange
        SharedPreferences.setMockInitialValues(<String, Object>{});
        var loadCount = 0;
        final store = PrefsSettingsStore(
          load: () {
            loadCount++;
            return SharedPreferences.getInstance();
          },
        );

        // Act
        await store.read();
        await store.write(const AppSettings(languageTag: 'he'));
        await store.read();
        await store.write(const AppSettings(languageTag: 'en'));

        // Assert
        expect(loadCount, equals(1));
      },
    );

    test('read never returns null even on a virgin store', () async {
      // Arrange
      final store = _buildStore();

      // Act
      final result = await store.read();

      // Assert
      expect(result, isNotNull);
    });
  });
}
