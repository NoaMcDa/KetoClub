import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/platform/app_info.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceAppInfo', () {
    test('constructing reads nothing', () {
      // Arrange / Act / Assert: a const constructor cannot do I/O.
      expect(const DeviceAppInfo(), isA<AppInfo>());
    });

    test('load answers the platform version and build', () async {
      // Arrange
      PackageInfo.setMockInitialValues(
        appName: 'KetoClub',
        packageName: 'club.keto',
        version: '2.0.1',
        buildNumber: '77',
        buildSignature: '',
      );

      // Act
      final version = await const DeviceAppInfo().load();

      // Assert
      expect(version, const AppVersion(version: '2.0.1', buildNumber: '77'));
    });
  });

  group('NoAppInfo', () {
    test('load answers null', () async {
      // Act
      final version = await const NoAppInfo().load();

      // Assert
      expect(version, isNull);
    });
  });

  group('AppVersion', () {
    test('equal versions compare equal', () {
      // Arrange
      const a = AppVersion(version: '1', buildNumber: '2');
      const b = AppVersion(version: '1', buildNumber: '2');

      // Assert
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const AppVersion(version: '1', buildNumber: '3')));
    });
  });
}
