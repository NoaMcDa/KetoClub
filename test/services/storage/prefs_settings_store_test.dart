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

  group('AppSettings.backendUrl', () {
    test('round-trips through the store', () async {
      // Arrange
      final store = _buildStore();
      const settings = AppSettings(backendUrl: 'http://192.168.1.20:8000');

      // Act
      await store.write(settings);
      final result = await store.read();

      // Assert
      expect(result.backendUrl, equals('http://192.168.1.20:8000'));
      expect(result, equals(settings));
    });

    test('is null on a virgin store', () async {
      // Arrange
      final store = _buildStore();

      // Act
      final result = await store.read();

      // Assert
      expect(result.backendUrl, isNull);
    });

    test('a write without it clears a previously stored value', () async {
      // Arrange
      final store = _buildStore();
      await store.write(const AppSettings(backendUrl: 'http://localhost:8000'));

      // Act
      await store.write(const AppSettings());
      final result = await store.read();

      // Assert
      expect(result.backendUrl, isNull);
    });

    test('a stored value of the wrong type reads as defaults', () async {
      // Arrange: a hand-edited or older payload must not crash the app.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.ketoclub_settings':
            '{"filter":"greenAndYellow","estimationConsentGiven":false,'
            '"backendUrl":42}',
      });
      final store = PrefsSettingsStore(load: SharedPreferences.getInstance);

      // Act
      final result = await store.read();

      // Assert
      expect(result, equals(const AppSettings()));
    });

    test('copyWith leaves it alone unless it is passed', () {
      // Arrange
      const settings = AppSettings(backendUrl: 'http://localhost:8000');

      // Act
      final unchanged = settings.copyWith(languageTag: 'he');
      final cleared = settings.copyWith(backendUrl: null);
      final replaced = settings.copyWith(backendUrl: 'http://other:9000');

      // Assert
      expect(unchanged.backendUrl, equals('http://localhost:8000'));
      expect(cleared.backendUrl, isNull);
      expect(replaced.backendUrl, equals('http://other:9000'));
    });

    test('two settings differing only in it are not equal', () {
      // Arrange
      const a = AppSettings(backendUrl: 'http://localhost:8000');
      const b = AppSettings(backendUrl: 'http://localhost:9000');

      // Assert
      expect(a, isNot(equals(b)));
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });
  });
}
