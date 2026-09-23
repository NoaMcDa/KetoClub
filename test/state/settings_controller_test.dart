import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/settings_controller.dart';

import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';

void main() {
  group('SettingsController', () {
    late FakeSettingsStore settings;
    late FakeMenuRepository repository;
    late SettingsController controller;

    setUp(() {
      settings = FakeSettingsStore();
      repository = FakeMenuRepository();
      controller = SettingsController(settings, repository);
    });

    test('initial state before load has the defaults', () async {
      // Arrange: settings seeded before load() is ever called.
      await settings.write(
        const AppSettings(languageTag: 'he', estimationConsentGiven: true),
      );
      final freshController = SettingsController(settings, repository);

      // Act / Assert: nothing has been read yet.
      expect(freshController.consentGiven, isFalse);
      expect(freshController.languageTag, isNull);
      expect(freshController.filter, MenuFilter.all);
      expect(freshController.isBusy, isFalse);
    });

    test('load populates consentGiven languageTag and filter', () async {
      // Arrange
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

    test(
      'setThemeMode persists the mode without clobbering prior language',
      () async {
        // Arrange
        await controller.setLanguage('he');

        // Act
        await controller.setThemeMode(AppThemeMode.dark);

        // Assert: the language set first survives the mode write second.
        expect(controller.languageTag, 'he');
        expect(controller.themeMode, AppThemeMode.dark);
        expect((await settings.read()).languageTag, 'he');
        expect((await settings.read()).themeMode, AppThemeMode.dark);
      },
    );

    test('setThemeMode toggles isBusy true then false', () async {
      // Arrange
      final states = <bool>[];
      controller.addListener(() => states.add(controller.isBusy));

      // Act
      await controller.setThemeMode(AppThemeMode.light);

      // Assert
      expect(states, [true, false]);
    });

    test('initial themeMode before load defaults to system', () {
      // Assert
      expect(controller.themeMode, equals(AppThemeMode.system));
    });

    test('load populates themeMode', () async {
      // Arrange
      await settings.write(const AppSettings(themeMode: AppThemeMode.dark));

      // Act
      await controller.load();

      // Assert
      expect(controller.themeMode, equals(AppThemeMode.dark));
    });

    test('initial netCarbLimitGrams before load defaults to 6 g', () {
      // Assert
      expect(controller.netCarbLimitGrams, equals(6));
    });

    test('load populates netCarbLimitGrams', () async {
      // Arrange
      await settings.write(const AppSettings(netCarbLimitGrams: 10));

      // Act
      await controller.load();

      // Assert
      expect(controller.netCarbLimitGrams, equals(10));
    });

    test('setNetCarbLimit persists the limit without clobbering the '
        'other settings', () async {
      // Arrange
      await controller.setLanguage('he');
      await controller.setThemeMode(AppThemeMode.dark);

      // Act
      await controller.setNetCarbLimit(9);

      // Assert
      expect(controller.netCarbLimitGrams, equals(9));
      final stored = await settings.read();
      expect(stored.netCarbLimitGrams, equals(9));
      expect(stored.languageTag, equals('he'));
      expect(stored.themeMode, equals(AppThemeMode.dark));
    });

    test('setNetCarbLimit clamps below 2 g and above 25 g', () async {
      // Act
      await controller.setNetCarbLimit(1);

      // Assert
      expect(controller.netCarbLimitGrams, equals(2));
      expect((await settings.read()).netCarbLimitGrams, equals(2));

      // Act
      await controller.setNetCarbLimit(26);

      // Assert
      expect(controller.netCarbLimitGrams, equals(25));
      expect((await settings.read()).netCarbLimitGrams, equals(25));
    });

    test('setNetCarbLimit toggles isBusy true then false', () async {
      // Arrange
      final states = <bool>[];
      controller.addListener(() => states.add(controller.isBusy));

      // Act
      await controller.setNetCarbLimit(7);

      // Assert
      expect(states, [true, false]);
    });

    test('initial cachedMenuCount before load is 0', () {
      // Assert
      expect(controller.cachedMenuCount, equals(0));
    });

    test('load populates cachedMenuCount from the repository', () async {
      // Arrange: two distinct venues cached.
      const refA = VenueRef(source: MenuSource.wolt, platformId: 'a');
      const refB = VenueRef(source: MenuSource.wolt, platformId: 'b');
      final fetchedA = await repository.load(refA) as MenuFetched;
      final fetchedB = await repository.load(refB) as MenuFetched;
      repository
        ..seedCache(CachedMenu(menu: fetchedA.menu))
        ..seedCache(CachedMenu(menu: fetchedB.menu));

      // Act
      await controller.load();

      // Assert
      expect(controller.cachedMenuCount, equals(2));
    });

    test('clearCache delegates to the repository', () async {
      // Act
      await controller.clearCache();

      // Assert
      expect(repository.clearCacheCallCount, 1);
    });

    test('clearCache resets lastVenue and lastFilter without clobbering '
        'other settings (issue #55)', () async {
      // Arrange
      await settings.write(
        const AppSettings(
          languageTag: 'he',
          lastVenue: VenueRef(source: MenuSource.wolt, platformId: 'v1'),
          lastFilter: MenuFilter.redOnly,
        ),
      );
      await controller.load();

      // Act
      await controller.clearCache();

      // Assert
      final stored = await settings.read();
      expect(stored.lastVenue, isNull);
      expect(stored.lastFilter, isNull);
      expect(stored.languageTag, 'he');
    });

    test('clearCache refreshes cachedMenuCount to 0', () async {
      // Arrange
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'a');
      final fetched = await repository.load(ref) as MenuFetched;
      repository.seedCache(CachedMenu(menu: fetched.menu));
      await controller.load();
      expect(controller.cachedMenuCount, equals(1));

      // Act
      await controller.clearCache();

      // Assert
      expect(controller.cachedMenuCount, equals(0));
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
