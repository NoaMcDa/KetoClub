import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/locale_controller.dart';

import '../fakes/fake_settings_store.dart';

void main() {
  group('LocaleController', () {
    test('locale is null before load', () {
      // Arrange / Act
      final controller = LocaleController(FakeSettingsStore());

      // Assert
      expect(controller.locale, isNull);
    });

    test('load applies a previously stored language tag', () async {
      // Arrange
      final store = FakeSettingsStore(
        initial: const AppSettings(languageTag: 'he'),
      );
      final controller = LocaleController(store);

      // Act
      await controller.load();

      // Assert
      expect(controller.locale, equals(const Locale('he')));
    });

    test('load leaves locale null when no tag is stored', () async {
      // Arrange
      final controller = LocaleController(FakeSettingsStore());

      // Act
      await controller.load();

      // Assert: null means "follow the device locale".
      expect(controller.locale, isNull);
    });

    test('load never writes to the store — it only reads', () async {
      // Arrange: SettingsController is the sole writer of the language tag
      // (its class doc, and LocaleController's own class doc, explain why
      // a second writer over the same on-disk value would be a split
      // brain).
      final store = FakeSettingsStore();
      final controller = LocaleController(store);

      // Act
      await controller.load();

      // Assert
      expect(store.writeCallCount, equals(0));
    });

    test('applyTag sets the locale and notifies listeners', () {
      // Arrange
      final controller = LocaleController(FakeSettingsStore());
      var notified = 0;
      controller.addListener(() => notified++);
      expect(notified, equals(0));

      // Act
      controller.applyTag('en');

      // Assert
      expect(controller.locale, equals(const Locale('en')));
      expect(notified, equals(1));
    });

    test('applyTag(null) clears a previously applied locale', () {
      // Arrange
      final controller = LocaleController(FakeSettingsStore())..applyTag('he');
      expect(controller.locale, equals(const Locale('he')));

      // Act
      controller.applyTag(null);

      // Assert
      expect(controller.locale, isNull);
    });

    test('applyTag never writes to the store', () {
      // Arrange
      final store = FakeSettingsStore();
      final controller = LocaleController(store);
      expect(controller.locale, isNull);

      // Act
      controller.applyTag('he');

      // Assert: this method is purely in-memory — see the class doc.
      expect(store.writeCallCount, equals(0));
    });

    test('applyTag with the same tag again does not notify twice', () {
      // Arrange
      final controller = LocaleController(FakeSettingsStore())..applyTag('en');
      var notified = 0;
      controller.addListener(() => notified++);
      expect(notified, equals(0));

      // Act
      controller.applyTag('en');

      // Assert
      expect(notified, equals(0));
    });
  });
}
