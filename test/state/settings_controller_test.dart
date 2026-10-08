import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';
import 'package:ketoclub/state/settings_controller.dart';

import '../fakes/fake_api_key_store.dart';
import '../fakes/fake_clock.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';
import '../fakes/fake_visit_history_store.dart';

/// A history that notes how many repository clears had happened when
/// [clear] ran, so a test can pin the order of the two clears. Every other
/// method is forwarded to a [FakeVisitHistoryStore].
final class _OrderRecordingHistory implements VisitHistoryStore {
  new(this.repository);

  final FakeMenuRepository repository;
  final FakeVisitHistoryStore inner = FakeVisitHistoryStore(
    FakeClock(DateTime.utc(2026)),
  );

  /// The repository's clear count at each [clear] call.
  final List<int> repositoryClearsAtClear = <int>[];

  @override
  Future<void> clear() {
    repositoryClearsAtClear.add(repository.clearCacheCallCount);
    return inner.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
        const AppSettings(languageTag: 'he', estimationConsentGiven: false),
      );
      final freshController = SettingsController(settings, repository);

      // Act / Assert: nothing has been read yet. consentGiven starts at
      // the D16 default (true, issue #167), languageTag/filter at
      // AppSettings defaults.
      expect(freshController.consentGiven, isTrue);
      expect(freshController.languageTag, isNull);
      expect(freshController.filter, MenuFilter.all);
      expect(freshController.isBusy, isFalse);
    });

    test('a fresh install (defaults) has consent on and the disclosure '
        'unseen (D16, issue #167)', () {
      // Act / Assert: no seeded settings, no load() — just the
      // controller's initial state.
      expect(controller.consentGiven, isTrue);
      expect(controller.disclosureSeen, isFalse);
    });

    test('load populates consentGiven languageTag and filter', () async {
      // Arrange
      await settings.write(
        const AppSettings(
          languageTag: 'he',
          filter: MenuFilter.greenOnly,
          estimationConsentGiven: false,
        ),
      );

      // Act
      await controller.load();

      // Assert: the seeded refusal wins over the D16 default (issue
      // #167).
      expect(controller.consentGiven, isFalse);
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

    test('load populates themeMode', () async {
      // Arrange
      await settings.write(const AppSettings(themeMode: AppThemeMode.dark));

      // Act
      await controller.load();

      // Assert
      expect(controller.themeMode, equals(AppThemeMode.dark));
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

    test('clearCache clears the visit history once, after the repository '
        '(issue #314)', () async {
      // Arrange
      final history = _OrderRecordingHistory(repository);
      final withHistory = SettingsController(
        settings,
        repository,
        null,
        history,
      );

      // Act
      await withHistory.clearCache();

      // Assert: one clear, made when the repository had cleared once.
      expect(history.inner.clearCallCount, 1);
      expect(history.repositoryClearsAtClear, [1]);
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

    group('acknowledgeDisclosure / declineDisclosure (D16, issue #167)', () {
      test('acknowledgeDisclosure persists disclosureSeen as true without '
          'changing consentGiven', () async {
        // Arrange: consent is at the D16 default of true.
        expect(controller.consentGiven, isTrue);
        expect(controller.disclosureSeen, isFalse);

        // Act
        await controller.acknowledgeDisclosure();

        // Assert
        expect(controller.disclosureSeen, isTrue);
        expect(controller.consentGiven, isTrue);
        final stored = await settings.read();
        expect(stored.disclosureSeen, isTrue);
        expect(stored.estimationConsentGiven, isTrue);
      });

      test(
        'acknowledgeDisclosure leaves a previously-set false consent '
        'as false — the banner is an acknowledgement, not a re-consent',
        () async {
          // Arrange
          await controller.setConsent(given: false);

          // Act
          await controller.acknowledgeDisclosure();

          // Assert
          expect(controller.consentGiven, isFalse);
          expect(controller.disclosureSeen, isTrue);
        },
      );

      test('declineDisclosure sets consent to false AND disclosureSeen to '
          'true in one write', () async {
        // Arrange
        expect(controller.consentGiven, isTrue);

        // Act
        await controller.declineDisclosure();

        // Assert
        expect(controller.consentGiven, isFalse);
        expect(controller.disclosureSeen, isTrue);
        final stored = await settings.read();
        expect(stored.estimationConsentGiven, isFalse);
        expect(stored.disclosureSeen, isTrue);
        expect(settings.writeCallCount, equals(1));
      });

      test('acknowledgeDisclosure toggles isBusy true then false', () async {
        // Arrange
        final states = <bool>[];
        controller.addListener(() => states.add(controller.isBusy));

        // Act
        await controller.acknowledgeDisclosure();

        // Assert
        expect(states, [true, false]);
      });

      test('declineDisclosure toggles isBusy true then false', () async {
        // Arrange
        final states = <bool>[];
        controller.addListener(() => states.add(controller.isBusy));

        // Act
        await controller.declineDisclosure();

        // Assert
        expect(states, [true, false]);
      });
    });
  });

  group('SettingsController dietary toggles (issue #56)', () {
    late FakeSettingsStore settings;
    late SettingsController controller;

    setUp(() {
      settings = FakeSettingsStore();
      controller = SettingsController(settings, FakeMenuRepository());
    });

    test('every toggle is off before load', () {
      // Assert
      expect(controller.seedOilFree, isFalse);
      expect(controller.dairyFree, isFalse);
      expect(controller.carnivoreOnly, isFalse);
    });

    test('load populates every toggle', () async {
      // Arrange
      await settings.write(
        const AppSettings(seedOilFree: true, dairyFree: true),
      );

      // Act
      await controller.load();

      // Assert
      expect(controller.seedOilFree, isTrue);
      expect(controller.dairyFree, isTrue);
      expect(controller.carnivoreOnly, isFalse);
    });

    test('setSeedOilFree persists the toggle without clobbering the other '
        'settings', () async {
      // Arrange
      await controller.setLanguage('he');
      await controller.setNetCarbLimit(9);

      // Act
      await controller.setSeedOilFree(enabled: true);

      // Assert
      expect(controller.seedOilFree, isTrue);
      final stored = await settings.read();
      expect(stored.seedOilFree, isTrue);
      expect(stored.dairyFree, isFalse);
      expect(stored.carnivoreOnly, isFalse);
      expect(stored.languageTag, equals('he'));
      expect(stored.netCarbLimitGrams, equals(9));
    });

    test('setDairyFree persists the toggle and leaves the others', () async {
      // Arrange
      await controller.setSeedOilFree(enabled: true);

      // Act
      await controller.setDairyFree(enabled: true);

      // Assert
      expect(controller.dairyFree, isTrue);
      final stored = await settings.read();
      expect(stored.dairyFree, isTrue);
      expect(stored.seedOilFree, isTrue);
      expect(stored.carnivoreOnly, isFalse);
    });

    test(
      'setCarnivoreOnly persists the toggle and leaves the others',
      () async {
        // Act
        await controller.setCarnivoreOnly(enabled: true);

        // Assert
        expect(controller.carnivoreOnly, isTrue);
        final stored = await settings.read();
        expect(stored.carnivoreOnly, isTrue);
        expect(stored.seedOilFree, isFalse);
        expect(stored.dairyFree, isFalse);
      },
    );

    test('each setter turns its toggle back off', () async {
      // Arrange
      await controller.setSeedOilFree(enabled: true);
      await controller.setDairyFree(enabled: true);
      await controller.setCarnivoreOnly(enabled: true);

      // Act
      await controller.setSeedOilFree(enabled: false);
      await controller.setDairyFree(enabled: false);
      await controller.setCarnivoreOnly(enabled: false);

      // Assert
      final stored = await settings.read();
      expect(stored.seedOilFree, isFalse);
      expect(stored.dairyFree, isFalse);
      expect(stored.carnivoreOnly, isFalse);
    });

    test('each setter toggles isBusy true then false', () async {
      // Arrange
      final states = <bool>[];
      controller.addListener(() => states.add(controller.isBusy));

      // Act
      await controller.setSeedOilFree(enabled: true);
      await controller.setDairyFree(enabled: true);
      await controller.setCarnivoreOnly(enabled: true);

      // Assert
      expect(states, [true, false, true, false, true, false]);
    });
  });

  group('SettingsController Gemini API key (architecture.md D17)', () {
    late FakeSettingsStore settings;
    late FakeMenuRepository repository;
    late FakeApiKeyStore keys;

    setUp(() {
      settings = FakeSettingsStore();
      repository = FakeMenuRepository();
      keys = FakeApiKeyStore();
    });

    test('with no key store (web) the key is unsupported and absent', () async {
      // Arrange
      final controller = SettingsController(settings, repository);

      // Act
      await controller.load();
      await controller.saveApiKey('AIza-key');
      await controller.deleteApiKey();

      // Assert: every key call is a silent no-op.
      expect(controller.supportsApiKey, isFalse);
      expect(controller.hasApiKey, isFalse);
    });

    test('with a key store (phone) the key is supported', () {
      // Arrange & Act
      final controller = SettingsController(settings, repository, keys);

      // Assert
      expect(controller.supportsApiKey, isTrue);
      expect(controller.hasApiKey, isFalse);
    });

    test('load reads whether a key is already saved', () async {
      // Arrange
      final controller = SettingsController(
        settings,
        repository,
        FakeApiKeyStore(seed: 'AIza-saved'),
      );

      // Act
      await controller.load();

      // Assert
      expect(controller.hasApiKey, isTrue);
    });

    test('saveApiKey writes the trimmed key and reports it saved', () async {
      // Arrange
      final controller = SettingsController(settings, repository, keys);

      // Act
      await controller.saveApiKey('  AIza-new  ');

      // Assert
      expect(await keys.read(), 'AIza-new');
      expect(controller.hasApiKey, isTrue);
    });

    test('saveApiKey ignores a blank key and writes nothing', () async {
      // Arrange
      final controller = SettingsController(settings, repository, keys);

      // Act
      await controller.saveApiKey('   ');

      // Assert
      expect(keys.writeCallCount, 0);
      expect(controller.hasApiKey, isFalse);
    });

    test('saveApiKey toggles isBusy true then false', () async {
      // Arrange
      final controller = SettingsController(settings, repository, keys);
      final states = <bool>[];
      controller.addListener(() => states.add(controller.isBusy));

      // Act
      await controller.saveApiKey('AIza-new');

      // Assert
      expect(states, [true, false]);
    });

    test('deleteApiKey removes the key and reports it absent', () async {
      // Arrange
      final keys = FakeApiKeyStore(seed: 'AIza-saved');
      final controller = SettingsController(settings, repository, keys);
      await controller.load();

      // Act
      await controller.deleteApiKey();

      // Assert
      expect(await keys.read(), isNull);
      expect(keys.deleteCallCount, 1);
      expect(controller.hasApiKey, isFalse);
    });

    test('no getter ever returns the key itself', () async {
      // Arrange
      const secret = 'AIza-secret-value';
      final controller = SettingsController(
        settings,
        repository,
        FakeApiKeyStore(seed: secret),
      );

      // Act
      await controller.load();

      // Assert: presence only.
      expect(controller.hasApiKey, isTrue);
      expect(controller.toString(), isNot(contains(secret)));
    });
  });
}
