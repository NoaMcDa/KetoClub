import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/theme_mode_controller.dart';

import '../fakes/fake_settings_store.dart';

void main() {
  group('ThemeModeController', () {
    test('mode is system before load', () {
      // Arrange / Act
      final controller = ThemeModeController(FakeSettingsStore());

      // Assert
      expect(controller.mode, equals(AppThemeMode.system));
      expect(controller.themeMode, equals(ThemeMode.system));
    });

    test('load applies a previously stored theme mode', () async {
      // Arrange
      final store = FakeSettingsStore(
        initial: const AppSettings(themeMode: AppThemeMode.dark),
      );
      final controller = ThemeModeController(store);

      // Act
      await controller.load();

      // Assert
      expect(controller.mode, equals(AppThemeMode.dark));
      expect(controller.themeMode, equals(ThemeMode.dark));
    });

    test('load leaves mode at system when none is stored', () async {
      // Arrange
      final controller = ThemeModeController(FakeSettingsStore());

      // Act
      await controller.load();

      // Assert
      expect(controller.mode, equals(AppThemeMode.system));
    });

    test('load never writes to the store — it only reads', () async {
      // Arrange: SettingsController is the sole writer of the theme mode
      // (its class doc, and ThemeModeController's own class doc, explain
      // why a second writer over the same on-disk value would be a split
      // brain).
      final store = FakeSettingsStore();
      final controller = ThemeModeController(store);

      // Act
      await controller.load();

      // Assert
      expect(store.writeCallCount, equals(0));
    });

    test('applyMode sets the mode and notifies listeners', () {
      // Arrange
      final controller = ThemeModeController(FakeSettingsStore());
      var notified = 0;
      controller.addListener(() => notified++);
      expect(notified, equals(0));

      // Act
      controller.applyMode(AppThemeMode.light);

      // Assert
      expect(controller.mode, equals(AppThemeMode.light));
      expect(controller.themeMode, equals(ThemeMode.light));
      expect(notified, equals(1));
    });

    test('applyMode never writes to the store', () {
      // Arrange
      final store = FakeSettingsStore();
      final controller = ThemeModeController(store);
      expect(controller.mode, equals(AppThemeMode.system));

      // Act
      controller.applyMode(AppThemeMode.dark);

      // Assert: this method is purely in-memory — see the class doc.
      expect(store.writeCallCount, equals(0));
    });

    test('applyMode with the same mode again does not notify twice', () {
      // Arrange
      final controller = ThemeModeController(FakeSettingsStore())
        ..applyMode(AppThemeMode.dark);
      var notified = 0;
      controller.addListener(() => notified++);
      expect(notified, equals(0));

      // Act
      controller.applyMode(AppThemeMode.dark);

      // Assert
      expect(notified, equals(0));
    });

    test('themeMode maps every AppThemeMode to its Flutter ThemeMode', () {
      // Arrange
      final controller = ThemeModeController(FakeSettingsStore());
      expect(controller.themeMode, equals(ThemeMode.system));

      // Act / Assert
      controller.applyMode(AppThemeMode.light);
      expect(controller.themeMode, equals(ThemeMode.light));

      controller.applyMode(AppThemeMode.dark);
      expect(controller.themeMode, equals(ThemeMode.dark));
    });
  });
}
