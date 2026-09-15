import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/settings_controller.dart';

import '../fakes/fake_key_store.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';

void main() {
  group('SettingsController', () {
    late FakeKeyStore keyStore;
    late FakeSettingsStore settings;
    late FakeMenuRepository repository;
    late SettingsController controller;

    setUp(() {
      keyStore = FakeKeyStore();
      settings = FakeSettingsStore();
      repository = FakeMenuRepository();
      controller = SettingsController(keyStore, settings, repository);
    });

    test('initial state before load has no key and defaults', () {
      // Arrange: keyStore seeded before load() is ever called.
      final seeded = FakeKeyStore(seed: 'sk-existing');
      final freshController = SettingsController(seeded, settings, repository);

      // Act / Assert: nothing has been read yet.
      expect(freshController.hasKey, isFalse);
      expect(freshController.consentGiven, isFalse);
      expect(freshController.languageTag, isNull);
      expect(freshController.filter, MenuFilter.all);
      expect(freshController.isBusy, isFalse);
    });

    test('load populates hasKey consentGiven languageTag and filter', () async {
      // Arrange
      await keyStore.write('sk-abc123');
      await settings.write(
        const AppSettings(
          languageTag: 'he',
          filter: MenuFilter.greenOnly,
          estimationConsentGiven: true,
        ),
      );

      // Act
      await controller.load();

      // Assert
      expect(controller.hasKey, isTrue);
      expect(controller.consentGiven, isTrue);
      expect(controller.languageTag, 'he');
      expect(controller.filter, MenuFilter.greenOnly);
    });

    test('load toggles isBusy true then false', () async {
      // Arrange
      final states = <bool>[];
      controller.addListener(() => states.add(controller.isBusy));

      // Act
      await controller.load();

      // Assert
      expect(states, [true, false]);
      expect(controller.isBusy, isFalse);
    });

    test('load notifies listeners exactly twice', () async {
      // Arrange
      var count = 0;
      controller.addListener(() => count++);

      // Act
      await controller.load();

      // Assert
      expect(count, 2);
    });

    test('saveKey with a non-empty key writes it and flips hasKey', () async {
      // Act
      await controller.saveKey('sk-new-key');

      // Assert
      expect(keyStore.writeCallCount, 1);
      expect(controller.hasKey, isTrue);
    });

    test(
      'saveKey with an empty key does not write and hasKey stays false',
      () async {
        // Act
        await controller.saveKey('');

        // Assert
        expect(keyStore.writeCallCount, 0);
        expect(controller.hasKey, isFalse);
      },
    );

    test('saveKey with a whitespace-only key does not write and hasKey stays '
        'false', () async {
      // Act
      await controller.saveKey('   \t  ');

      // Assert
      expect(keyStore.writeCallCount, 0);
      expect(controller.hasKey, isFalse);
    });

    test('saveKey trims surrounding whitespace before writing', () async {
      // Act
      await controller.saveKey('  sk-trimmed  ');

      // Assert
      expect(await keyStore.read(), 'sk-trimmed');
    });

    test('deleteKey clears the stored key and hasKey goes false', () async {
      // Arrange
      await controller.saveKey('sk-to-delete');
      expect(controller.hasKey, isTrue);

      // Act
      await controller.deleteKey();

      // Assert
      expect(keyStore.deleteCallCount, 1);
      expect(controller.hasKey, isFalse);
      expect(await keyStore.read(), isNull);
    });

    test('no public member or toString ever returns the stored key', () async {
      // Arrange
      const secret = 'sk-super-secret-value';

      // Act
      await controller.saveKey(secret);
      await controller.load();

      // Assert: every exposed value and toString is checked for the
      // secret substring (architecture.md §11 — the key is never
      // exposed by this controller, only its presence is).
      expect(controller.hasKey, isTrue);
      expect(controller.hasKey.toString(), isNot(contains(secret)));
      expect(controller.isBusy.toString(), isNot(contains(secret)));
      expect(controller.consentGiven.toString(), isNot(contains(secret)));
      expect(controller.languageTag?.toString() ?? '', isNot(contains(secret)));
      expect(controller.filter.toString(), isNot(contains(secret)));
      expect(controller.toString(), isNot(contains(secret)));
    });

    test(
      'setConsent persists consent without clobbering a prior filter',
      () async {
        // Arrange
        await controller.setFilter(MenuFilter.greenOnly);

        // Act
        await controller.setConsent(given: true);

        // Assert: the filter set first survives the consent write second.
        expect(controller.filter, MenuFilter.greenOnly);
        expect(controller.consentGiven, isTrue);
        expect((await settings.read()).filter, MenuFilter.greenOnly);
        expect((await settings.read()).estimationConsentGiven, isTrue);
      },
    );

    test(
      'setLanguage persists language without clobbering prior consent',
      () async {
        // Arrange
        await controller.setConsent(given: true);

        // Act
        await controller.setLanguage('he');

        // Assert: the consent set first survives the language write second.
        expect(controller.consentGiven, isTrue);
        expect(controller.languageTag, 'he');
        expect((await settings.read()).estimationConsentGiven, isTrue);
        expect((await settings.read()).languageTag, 'he');
      },
    );

    test(
      'setFilter persists filter without clobbering prior language',
      () async {
        // Arrange
        await controller.setLanguage('en');

        // Act
        await controller.setFilter(MenuFilter.all);

        // Assert: the language set first survives the filter write second.
        expect(controller.languageTag, 'en');
        expect(controller.filter, MenuFilter.all);
        expect((await settings.read()).languageTag, 'en');
        expect((await settings.read()).filter, MenuFilter.all);
      },
    );

    test('setLanguage with null clears a previously set tag', () async {
      // Arrange
      await controller.setLanguage('he');
      expect(controller.languageTag, 'he');

      // Act
      await controller.setLanguage(null);

      // Assert
      expect(controller.languageTag, isNull);
      expect((await settings.read()).languageTag, isNull);
    });

    test('clearCache delegates to the repository', () async {
      // Act
      await controller.clearCache();

      // Assert
      expect(repository.clearCacheCallCount, 1);
    });

    test('setConsent toggles isBusy true then false', () async {
      // Arrange
      final states = <bool>[];
      controller.addListener(() => states.add(controller.isBusy));

      // Act
      await controller.setConsent(given: true);

      // Assert
      expect(states, [true, false]);
    });

    test('clearCache notifies listeners exactly twice', () async {
      // Arrange
      var count = 0;
      controller.addListener(() => count++);

      // Act
      await controller.clearCache();

      // Assert
      expect(count, 2);
    });
  });
}
