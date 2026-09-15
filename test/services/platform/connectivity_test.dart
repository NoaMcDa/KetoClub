import 'package:connectivity_plus/connectivity_plus.dart' as plus;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/platform/connectivity.dart';

import '../../fakes/fake_connectivity.dart';

/// The method channel every `connectivity_plus` `Connectivity` instance
/// talks to (`MethodChannelConnectivity`, the plugin's default platform
/// implementation), regardless of the app's own platform. Mocking this
/// channel — rather than swapping out `plus.Connectivity` for a fake —
/// exercises [DeviceConnectivity] exactly as it runs in the app: a real
/// `connectivity_plus.Connectivity` over a real (mocked) platform channel,
/// the same approach `secure_key_store_test.dart` takes for `KeyStore`.
const MethodChannel _channel = MethodChannel(
  'dev.fluttercommunity.plus/connectivity',
);

/// Installs a channel handler that answers `check` with [results], the
/// wire shape (a list of result names) `connectivity_plus` sends.
void _installWorkingChannel(List<String> results) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'check') return results;
        throw MissingPluginException('Unhandled: ${call.method}');
      });
}

/// Installs a channel handler that fails every call, driving
/// [DeviceConnectivity]'s degrade-to-online path.
void _installFailingChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        throw PlatformException(code: 'UNAVAILABLE');
      });
}

/// Installs a channel handler with no registered handler at all — what a
/// build missing the plugin's platform implementation looks like.
void _installNoChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

/// A fresh [DeviceConnectivity] over a real `connectivity_plus.Connectivity`
/// talking to a freshly mocked channel.
DeviceConnectivity _buildDevice() => DeviceConnectivity(plus.Connectivity());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceConnectivity', () {
    test('isOnline returns true when the channel reports wifi', () async {
      // Arrange
      _installWorkingChannel(['wifi']);
      final connectivity = _buildDevice();

      // Act & Assert
      expect(await connectivity.isOnline(), isTrue);
    });

    test('isOnline returns true when the channel reports mobile', () async {
      // Arrange
      _installWorkingChannel(['mobile']);
      final connectivity = _buildDevice();

      // Act & Assert
      expect(await connectivity.isOnline(), isTrue);
    });

    test(
      'isOnline returns true when the channel reports more than one route',
      () async {
        // Arrange
        _installWorkingChannel(['wifi', 'vpn']);
        final connectivity = _buildDevice();

        // Act & Assert
        expect(await connectivity.isOnline(), isTrue);
      },
    );

    test('isOnline returns false when the channel reports none', () async {
      // Arrange
      _installWorkingChannel(['none']);
      final connectivity = _buildDevice();

      // Act & Assert
      expect(await connectivity.isOnline(), isFalse);
    });

    test('isOnline returns true — never throws — when the channel throws a '
        'PlatformException: "don\'t know" degrades to online', () async {
      // Arrange
      _installFailingChannel();
      final connectivity = _buildDevice();

      // Act & Assert
      expect(await connectivity.isOnline(), isTrue);
    });

    test('isOnline returns true when no platform implementation is registered '
        'for the channel at all', () async {
      // Arrange
      _installNoChannel();
      final connectivity = _buildDevice();

      // Act & Assert
      expect(await connectivity.isOnline(), isTrue);
    });

    test('isOnline never throws regardless of the channel result', () async {
      // Arrange
      _installFailingChannel();
      final connectivity = _buildDevice();

      // Act & Assert
      await expectLater(connectivity.isOnline(), completes);
    });
  });

  group('FakeConnectivity', () {
    test('isOnline defaults to true', () async {
      final connectivity = FakeConnectivity();

      expect(await connectivity.isOnline(), isTrue);
    });

    test('isOnline reflects a false value passed to the constructor', () async {
      final connectivity = FakeConnectivity(online: false);

      expect(await connectivity.isOnline(), isFalse);
    });

    test('isOnline reflects online being flipped after construction', () async {
      final connectivity = FakeConnectivity()..online = false;

      expect(await connectivity.isOnline(), isFalse);

      connectivity.online = true;

      expect(await connectivity.isOnline(), isTrue);
    });
  });
}
