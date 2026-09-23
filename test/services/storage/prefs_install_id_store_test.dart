import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/storage/install_id_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'install_id_store_contract.dart';

/// The method channel the default `SharedPreferencesStorePlatform`
/// (`MethodChannelSharedPreferencesStore`) talks to. Mocked directly, and
/// only by the tests that need it, so `SharedPreferences.getInstance`
/// resolves through a real (mocked) channel rather than the in-memory
/// store `SharedPreferences.setMockInitialValues` installs for every
/// later test in this file.
const MethodChannel _prefsChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

/// The shared_preferences key an install ID is stored under, prefixed the
/// way the plugin's own storage namespaces every key.
const String _prefsKey = 'flutter.ketoclub_install_id';

/// A fresh [PrefsInstallIdStore] whose loader is
/// `SharedPreferences.getInstance` over a freshly mocked, initially empty
/// store.
PrefsInstallIdStore _buildStore() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return PrefsInstallIdStore(load: SharedPreferences.getInstance);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  runInstallIdStoreContract('PrefsInstallIdStore', _buildStore);

  group('PrefsInstallIdStore', () {
    test('id generates and persists an ID on first call', () async {
      // Arrange
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = _buildStore();

      // Act
      final id = await store.id();

      // Assert: the same preferences instance now carries what was
      // returned, so a fresh instance over it reads it back.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ketoclub_install_id'), equals(id));
    });

    test(
      'a fresh instance over the same preferences reads the same id',
      () async {
        // Arrange
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final first = PrefsInstallIdStore(load: SharedPreferences.getInstance);
        final firstId = await first.id();

        // Act: a second store instance, same underlying preferences.
        final second = PrefsInstallIdStore(load: SharedPreferences.getInstance);
        final secondId = await second.id();

        // Assert
        expect(secondId, equals(firstId));
      },
    );

    test('two installs with empty prefs each get different ids', () async {
      // Arrange
      final storeA = _buildStore();
      final idA = await storeA.id();

      // Act: a second, independently-empty install.
      final storeB = _buildStore();
      final idB = await storeB.id();

      // Assert
      expect(idB, isNot(equals(idA)));
    });

    test('a corrupt stored value is replaced by a fresh valid one', () async {
      // Arrange
      SharedPreferences.setMockInitialValues(<String, Object>{
        _prefsKey: 'not-32-hex-chars',
      });
      final store = _buildStore();

      // Act
      final id = await store.id();

      // Assert
      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(id, isNot(equals('not-32-hex-chars')));
    });

    test(
      'an uppercase stored value counts as corrupt and is replaced',
      () async {
        // Arrange: the store only ever writes lowercase, so an uppercase
        // value could only arrive from something else touching the key.
        SharedPreferences.setMockInitialValues(<String, Object>{
          _prefsKey: 'A1B2C3D4E5F60718293A4B5C6D7E8F90',
        });
        final store = _buildStore();

        // Act
        final id = await store.id();

        // Assert
        expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
      },
    );

    test('id returns a valid id when the loader throws', () async {
      // Arrange
      final store = PrefsInstallIdStore(
        load: () =>
            Future<SharedPreferences>.error(PlatformException(code: 'boom')),
      );

      // Act
      final id = await store.id();

      // Assert
      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('id returns a valid id when the loader throws no-plugin', () async {
      // Arrange
      final store = PrefsInstallIdStore(
        load: () => Future<SharedPreferences>.error(
          MissingPluginException('no shared_preferences plugin'),
        ),
      );

      // Act
      final id = await store.id();

      // Assert
      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test(
      'id completes without throwing when the platform rejects the write',
      () async {
        // Arrange: the load succeeds (a plain "getAll") but the persist
        // call fails, driving PrefsInstallIdStore.id's write-side catch.
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
        final store = PrefsInstallIdStore(load: SharedPreferences.getInstance);

        // Act
        final id = await store.id();

        // Assert
        expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
      },
    );

    test('the loader is invoked once across several id calls', () async {
      // Arrange
      SharedPreferences.setMockInitialValues(<String, Object>{});
      var loadCount = 0;
      final store = PrefsInstallIdStore(
        load: () {
          loadCount++;
          return SharedPreferences.getInstance();
        },
      );

      // Act
      await store.id();
      await store.id();
      await store.id();

      // Assert
      expect(loadCount, equals(1));
    });

    test('constructing the store performs no I/O', () async {
      // Arrange & Act: the loader is never invoked just by construction.
      var loadCalls = 0;
      PrefsInstallIdStore(
        load: () {
          loadCalls++;
          return SharedPreferences.getInstance();
        },
      );

      // Assert
      expect(loadCalls, equals(0));
    });
  });
}
