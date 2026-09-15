import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:screen_brightness/screen_brightness.dart' as plugin;

/// The method channel every `screen_brightness` `ScreenBrightness` instance
/// talks to, regardless of the app's own platform. Mocking this channel —
/// rather than swapping out `plugin.ScreenBrightness` for a fake — exercises
/// [DeviceScreenBrightness] exactly as it runs in the app, the same approach
/// `connectivity_test.dart` takes for `DeviceConnectivity`.
const MethodChannel _channel = MethodChannel(
  'github.com/aaassseee/screen_brightness',
);

/// Installs a channel handler that answers every call successfully.
void _installWorkingChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        switch (call.method) {
          case 'setApplicationScreenBrightness':
          case 'resetApplicationScreenBrightness':
            return null;
          default:
            throw MissingPluginException('Unhandled: ${call.method}');
        }
      });
}

/// Installs a channel handler that fails every call, driving
/// [DeviceScreenBrightness]'s swallow-and-continue path.
void _installFailingChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        throw PlatformException(code: '-1', message: 'boom');
      });
}

/// A fresh [DeviceScreenBrightness] over a real `screen_brightness`
/// singleton talking to a freshly mocked channel.
DeviceScreenBrightness _buildDevice() =>
    DeviceScreenBrightness(plugin.ScreenBrightness());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceScreenBrightness', () {
    test('raise never throws when the channel answers normally', () async {
      // Arrange
      _installWorkingChannel();
      final brightness = _buildDevice();

      // Act & Assert
      await expectLater(brightness.raise(), completes);
    });

    test('restore never throws when the channel answers normally', () async {
      // Arrange
      _installWorkingChannel();
      final brightness = _buildDevice();

      // Act & Assert
      await expectLater(brightness.restore(), completes);
    });

    test('raise never throws when the channel fails', () async {
      // Arrange
      _installFailingChannel();
      final brightness = _buildDevice();

      // Act & Assert
      await expectLater(brightness.raise(), completes);
    });

    test('restore never throws when the channel fails', () async {
      // Arrange
      _installFailingChannel();
      final brightness = _buildDevice();

      // Act & Assert
      await expectLater(brightness.restore(), completes);
    });

    test(
      'raise never throws when no platform implementation is registered',
      () async {
        // Arrange
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, null);
        final brightness = _buildDevice();

        // Act & Assert
        await expectLater(brightness.raise(), completes);
      },
    );
  });

  group('NoOpScreenBrightness', () {
    test('raise completes without touching a channel', () async {
      const brightness = NoOpScreenBrightness();

      await expectLater(brightness.raise(), completes);
    });

    test('restore completes without touching a channel', () async {
      const brightness = NoOpScreenBrightness();

      await expectLater(brightness.restore(), completes);
    });
  });
}
