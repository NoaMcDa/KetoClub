import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/notes_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notes_store_contract.dart';

/// The method channel the default `SharedPreferencesStorePlatform`
/// (`MethodChannelSharedPreferencesStore`) talks to. Mocked directly, and
/// only by the tests that need it, so `SharedPreferences.getInstance`
/// resolves through a real (mocked) channel rather than the in-memory
/// store `SharedPreferences.setMockInitialValues` installs for every
/// later test in this file.
const MethodChannel _prefsChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

const VenueRef _venue = VenueRef(source: MenuSource.wolt, platformId: 'v1');

/// A fresh [PrefsNotesStore] whose loader is
/// `SharedPreferences.getInstance` over a freshly mocked, initially empty
/// store.
PrefsNotesStore _buildStore() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return PrefsNotesStore(load: SharedPreferences.getInstance);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  runNotesStoreContract('PrefsNotesStore', _buildStore);

  group('PrefsNotesStore', () {
    test('read returns null when the stored string is corrupt', () async {
      // Arrange
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.ketoclub_notes_wolt/v1': 'not valid json{',
      });
      final store = PrefsNotesStore(load: SharedPreferences.getInstance);

      // Act
      final result = await store.read(_venue, 'dish_1');

      // Assert
      expect(result, isNull);
    });

    test(
      'readAll returns empty when the stored JSON is shaped wrong',
      () async {
        // Arrange
        SharedPreferences.setMockInitialValues(<String, Object>{
          'flutter.ketoclub_notes_wolt/v1': '"just a string, not a map"',
        });
        final store = PrefsNotesStore(load: SharedPreferences.getInstance);

        // Act
        final result = await store.readAll(_venue);

        // Assert
        expect(result, isEmpty);
      },
    );

    test('a note entry that is not a string is skipped, not a crash', () async {
      // Arrange: a stored shape this store never writes itself, exercising
      // the per-entry type guard in _readMap.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.ketoclub_notes_wolt/v1': '{"dish_1":"ok","dish_2":42}',
      });
      final store = PrefsNotesStore(load: SharedPreferences.getInstance);

      // Act
      final result = await store.readAll(_venue);

      // Assert
      expect(result, equals(<String, String>{'dish_1': 'ok'}));
    });

    test(
      'write then read round-trips through a real preferences instance',
      () async {
        // Arrange
        final store = _buildStore();

        // Act
        await store.write(_venue, 'dish_1', 'Ask for no cheese.');
        final result = await store.read(_venue, 'dish_1');

        // Assert
        expect(result, equals('Ask for no cheese.'));
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('ketoclub_notes_wolt/v1'),
          contains('Ask for no cheese.'),
        );
      },
    );

    test('delete removes the underlying key once no notes remain', () async {
      // Arrange
      final store = _buildStore();
      await store.write(_venue, 'dish_1', 'Only note.');

      // Act
      await store.delete(_venue, 'dish_1');

      // Assert: no stray empty object left behind.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ketoclub_notes_wolt/v1'), isNull);
    });

    test('read returns null when the loader throws', () async {
      // Arrange
      final store = PrefsNotesStore(
        load: () =>
            Future<SharedPreferences>.error(PlatformException(code: 'boom')),
      );

      // Act
      final result = await store.read(_venue, 'dish_1');

      // Assert
      expect(result, isNull);
    });

    test('readAll returns empty when the loader throws no-plugin', () async {
      // Arrange
      final store = PrefsNotesStore(
        load: () => Future<SharedPreferences>.error(
          MissingPluginException('no shared_preferences plugin'),
        ),
      );

      // Act
      final result = await store.readAll(_venue);

      // Assert
      expect(result, isEmpty);
    });

    test('write completes without throwing when the loader throws', () async {
      // Arrange
      final store = PrefsNotesStore(
        load: () => Future<SharedPreferences>.error(
          MissingPluginException('no shared_preferences plugin'),
        ),
      );

      // Act & Assert
      await expectLater(store.write(_venue, 'dish_1', 'A note.'), completes);
    });

    test(
      'write completes without throwing when the platform rejects the value',
      () async {
        // Arrange: the load succeeds (a plain "getAll") but the persist
        // call fails, driving PrefsNotesStore.write's write-side catch.
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
        final store = PrefsNotesStore(load: SharedPreferences.getInstance);

        // Act & Assert
        await expectLater(store.write(_venue, 'dish_1', 'A note.'), completes);
      },
    );

    test(
      'the loader is invoked once across several read and write calls',
      () async {
        // Arrange
        SharedPreferences.setMockInitialValues(<String, Object>{});
        var loadCount = 0;
        final store = PrefsNotesStore(
          load: () {
            loadCount++;
            return SharedPreferences.getInstance();
          },
        );

        // Act
        await store.read(_venue, 'dish_1');
        await store.write(_venue, 'dish_1', 'Note.');
        await store.readAll(_venue);
        await store.delete(_venue, 'dish_1');

        // Assert
        expect(loadCount, equals(1));
      },
    );

    test('constructing the store performs no I/O', () async {
      // Arrange & Act
      var loadCalls = 0;
      PrefsNotesStore(
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
