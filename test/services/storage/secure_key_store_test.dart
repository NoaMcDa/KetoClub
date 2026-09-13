import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/storage/key_store.dart';

import 'key_store_contract.dart';

/// The method channel every `FlutterSecureStorage` instance talks to
/// (`MethodChannelFlutterSecureStorage`, the plugin's default platform
/// implementation), regardless of the app's own platform. Mocking this
/// channel — rather than swapping out `FlutterSecureStorage` for a fake —
/// exercises [SecureKeyStore] exactly as it runs in the app: a real
/// `FlutterSecureStorage` over a real (mocked) platform channel.
const MethodChannel _channel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// One call's decoded `{'key': ..., 'value': ...}` arguments.
Map<Object?, Object?> _argsOf(MethodCall call) =>
    call.arguments as Map<Object?, Object?>;

/// Installs a channel handler backed by [backing], round-tripping
/// read/write/delete/containsKey the way a real secure-storage plugin
/// would.
void _installWorkingChannel(Map<String, String> backing) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        final args = _argsOf(call);
        switch (call.method) {
          case 'write':
            backing[args['key']! as String] = args['value']! as String;
            return null;
          case 'read':
            return backing[args['key']! as String];
          case 'delete':
            backing.remove(args['key']! as String);
            return null;
          case 'containsKey':
            return backing.containsKey(args['key']! as String);
          default:
            throw MissingPluginException('Unhandled: ${call.method}');
        }
      });
}

/// Installs a channel handler that fails every call with [error], to
/// drive [SecureKeyStore]'s degrade path.
void _installFailingChannel(Exception Function() error) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async => throw error());
}

/// A fresh [SecureKeyStore] over a real [FlutterSecureStorage], talking
/// to a freshly mocked, initially empty channel.
SecureKeyStore _buildStore() {
  _installWorkingChannel(<String, String>{});
  return const SecureKeyStore(FlutterSecureStorage());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  runKeyStoreContract('SecureKeyStore', _buildStore);

  group('SecureKeyStore', () {
    test(
      'read returns null when the channel throws PlatformException',
      () async {
        // Arrange
        _installFailingChannel(
          () => PlatformException(code: 'boom', message: 'sk-should-not-leak'),
        );
        const store = SecureKeyStore(FlutterSecureStorage());

        // Act
        final result = await store.read();

        // Assert
        expect(result, isNull);
      },
    );

    test(
      'read returns null when the channel throws MissingPluginException',
      () async {
        // Arrange
        _installFailingChannel(MissingPluginException.new);
        const store = SecureKeyStore(FlutterSecureStorage());

        // Act
        final result = await store.read();

        // Assert
        expect(result, isNull);
      },
    );

    for (final MapEntry(key: label, value: errorOf)
        in <String, Exception Function()>{
          'PlatformException': () => PlatformException(code: 'boom'),
          'MissingPluginException': MissingPluginException.new,
        }.entries) {
      test('write completes without throwing when the channel throws '
          '$label', () async {
        // Arrange
        _installFailingChannel(errorOf);
        const store = SecureKeyStore(FlutterSecureStorage());

        // Act & Assert
        await expectLater(store.write('sk-live-abc123'), completes);
      });

      test('delete completes without throwing when the channel throws '
          '$label', () async {
        // Arrange
        _installFailingChannel(errorOf);
        const store = SecureKeyStore(FlutterSecureStorage());

        // Act & Assert
        await expectLater(store.delete(), completes);
      });

      test('hasKey returns false when the channel throws $label', () async {
        // Arrange
        _installFailingChannel(errorOf);
        const store = SecureKeyStore(FlutterSecureStorage());

        // Act
        final result = await store.hasKey();

        // Assert
        expect(result, isFalse);
      });
    }

    test('a channel error carrying a message never surfaces it as the read '
        'value', () async {
      // Arrange: a channel error that happens to echo something back
      // must still never surface as a value read() returns
      // (architecture.md §11) — the catch clause returns null, not the
      // exception's message.
      _installFailingChannel(
        () => PlatformException(
          code: 'boom',
          message: 'sk-live-should-never-surface',
        ),
      );
      const store = SecureKeyStore(FlutterSecureStorage());

      // Act
      final result = await store.read();

      // Assert
      expect(result, isNull);
    });
  });
}
