import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/di.dart';
import 'package:ketoclub/services/classifier/classifier_router.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/platform/app_logger.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/services/storage/key_store.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/app_dependencies.dart';

void main() {
  group('buildDependencies', () {
    test('returns an AppDependencies for the production app', () {
      // Act
      final dependencies = buildDependencies();

      // Assert
      expect(dependencies, isA<AppDependencies>());
    });

    test('builds the production implementation of every service', () {
      // Act
      final dependencies = buildDependencies();

      // Assert
      expect(dependencies.menuRepository, isA<CachedMenuRepository>());
      expect(dependencies.menuClassifier, isA<RoutingMenuClassifier>());
      expect(dependencies.clock, isA<SystemClock>());
      expect(dependencies.logger, isA<DeveloperLogAppLogger>());
      expect(dependencies.keyStore, isA<SecureKeyStore>());
      expect(dependencies.settingsStore, isA<PrefsSettingsStore>());
      // The test VM is not web, so the kIsWeb branch picks the device
      // implementation, not NoOpScreenBrightness.
      expect(dependencies.screenBrightness, isA<DeviceScreenBrightness>());
    });

    test('performs no plugin I/O while building the graph', () {
      // Assert: this test runs with no plugin binding, so a constructor that
      // touched a platform channel — Hive.initFlutter, SharedPreferences,
      // secure storage — would throw MissingPluginException here. Plugin work
      // belongs in a closure invoked on first use, not in a constructor.
      // main_test.dart and the launch flow test depend on this too.
      expect(buildDependencies, returnsNormally);
    });
  });
}
