import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/locale_controller.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/state/theme_mode_controller.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';

/// The English strings a test can read expected copy from, computed the
/// same way the widget under test does.
final AppLocalizations _en = AppLocalizationsEn();

/// The Hebrew strings for the one Locale('he') test.
final AppLocalizations _he = AppLocalizationsHe();

/// The `find.text` match for [label], scoped to the language section's
/// radio group ([languageRadioGroupKey]), so a label that happens to
/// match another section's (as `settingsLanguageSystem` and
/// `settingsAppearanceSystem` once did) can never make `find.text`
/// ambiguous.
Finder _languageOption(String label) => find.descendant(
  of: find.byKey(languageRadioGroupKey),
  matching: find.text(label),
);

/// The `find.text` match for [label], scoped to the appearance section's
/// radio group ([appearanceRadioGroupKey]); see [_languageOption].
Finder _appearanceOption(String label) => find.descendant(
  of: find.byKey(appearanceRadioGroupKey),
  matching: find.text(label),
);

/// Builds the [SettingsController] the widget under test is pumped over,
/// from fresh fakes unless the caller seeds one.
SettingsController _controllerFor({
  FakeSettingsStore? settingsStore,
  FakeMenuRepository? repository,
}) => SettingsController(
  settingsStore ?? FakeSettingsStore(),
  repository ?? FakeMenuRepository(),
);

/// Pumps the real [SettingsScreen] over a real [SettingsController] and a
/// real [LocaleController], inside a localised [MaterialApp] — the shape
/// every test in this file uses. A [LocaleController] is provided here
/// because the language section reaches one via `context.read` after a
/// successful [SettingsController.setLanguage] call, exactly as
/// `KetoClubApp` provides one above its `Navigator` in the real app. Does
/// not itself wait for [SettingsController.load] to settle; callers that
/// need loaded state call `tester.pumpAndSettle()` afterwards, exactly as
/// the app's own post-frame load is expected to resolve.
Future<void> _pump(
  WidgetTester tester,
  SettingsController controller, {
  Locale locale = const Locale('en'),
  LocaleController? localeController,
  ThemeModeController? themeModeController,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(value: controller),
          ChangeNotifierProvider<LocaleController>.value(
            value: localeController ?? LocaleController(FakeSettingsStore()),
          ),
          ChangeNotifierProvider<ThemeModeController>.value(
            value:
                themeModeController ?? ThemeModeController(FakeSettingsStore()),
          ),
        ],
        child: const SettingsScreen(),
      ),
    ),
  );
}

void main() {
  group('SettingsScreen', () {
    testWidgets('build shows the consent disclosure and its checkbox', (
      tester,
    ) async {
      // Arrange
      final controller = _controllerFor();

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.settingsConsentTitle), findsOneWidget);
      expect(find.text(_en.settingsConsentBody), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsOneWidget);
    });

    testWidgets('the consent section comes before every other section', (
      tester,
    ) async {
      // Arrange
      final controller = _controllerFor();

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      final consentTop = tester.getTopLeft(find.text(_en.settingsConsentTitle));
      final languageTop = tester.getTopLeft(find.text(_en.settingsLanguage));
      expect(consentTop.dy, lessThan(languageTop.dy));
    });

    testWidgets('build offers no field to enter a credential', (tester) async {
      // Arrange
      final controller = _controllerFor();

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert: the model key lives on KetoClub's server, never here.
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('the consent checkbox calls setConsent and the flag persists', (
      tester,
    ) async {
      // Arrange
      final settingsStore = FakeSettingsStore();
      final controller = _controllerFor(settingsStore: settingsStore);
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Act
      final accept = find.text(_en.settingsConsentAccept);
      await tester.ensureVisible(accept);
      await tester.tap(accept);
      await tester.pumpAndSettle();

      // Assert
      expect(controller.consentGiven, isTrue);
      final stored = await settingsStore.read();
      expect(stored.estimationConsentGiven, isTrue);
    });

    testWidgets('choosing English sets the language tag to en', (tester) async {
      // Arrange
      final settingsStore = FakeSettingsStore();
      final controller = _controllerFor(settingsStore: settingsStore);
      final localeController = LocaleController(settingsStore);
      await _pump(tester, controller, localeController: localeController);
      await tester.pumpAndSettle();

      // Act
      final english = _languageOption(_en.settingsLanguageEnglish);
      await tester.ensureVisible(english);
      await tester.tap(english);
      await tester.pumpAndSettle();

      // Assert
      expect(controller.languageTag, equals('en'));
      expect((await settingsStore.read()).languageTag, equals('en'));
      // The app-level controller picks the change up without a second
      // write to the store (issue #8 — see LocaleController's class doc).
      expect(localeController.locale, equals(const Locale('en')));
      expect(settingsStore.writeCallCount, equals(1));
    });

    testWidgets('choosing Hebrew sets the language tag to he', (tester) async {
      // Arrange
      final settingsStore = FakeSettingsStore();
      final controller = _controllerFor(settingsStore: settingsStore);
      final localeController = LocaleController(settingsStore);
      await _pump(tester, controller, localeController: localeController);
      await tester.pumpAndSettle();

      // Act
      final hebrew = _languageOption(_en.settingsLanguageHebrew);
      await tester.ensureVisible(hebrew);
      await tester.tap(hebrew);
      await tester.pumpAndSettle();

      // Assert
      expect(controller.languageTag, equals('he'));
      expect((await settingsStore.read()).languageTag, equals('he'));
      expect(localeController.locale, equals(const Locale('he')));
      expect(settingsStore.writeCallCount, equals(1));
    });

    testWidgets(
      'choosing "match my device" clears a previously set language tag',
      (tester) async {
        // Arrange
        final settingsStore = FakeSettingsStore(
          initial: const AppSettings(languageTag: 'he'),
        );
        final controller = _controllerFor(settingsStore: settingsStore);
        final localeController = LocaleController(settingsStore);
        await _pump(tester, controller, localeController: localeController);
        await tester.pumpAndSettle();

        // Act
        final system = _languageOption(_en.settingsLanguageSystem);
        await tester.ensureVisible(system);
        await tester.tap(system);
        await tester.pumpAndSettle();

        // Assert
        expect(controller.languageTag, isNull);
        expect((await settingsStore.read()).languageTag, isNull);
        expect(localeController.locale, isNull);
      },
    );

    testWidgets('choosing Dark sets the theme mode and applies it', (
      tester,
    ) async {
      // Arrange
      final settingsStore = FakeSettingsStore();
      final controller = _controllerFor(settingsStore: settingsStore);
      final themeModeController = ThemeModeController(settingsStore);
      await _pump(tester, controller, themeModeController: themeModeController);
      await tester.pumpAndSettle();

      // Act
      final dark = _appearanceOption(_en.settingsAppearanceDark);
      await tester.ensureVisible(dark);
      await tester.tap(dark);
      await tester.pumpAndSettle();

      // Assert
      expect(controller.themeMode, equals(AppThemeMode.dark));
      expect((await settingsStore.read()).themeMode, equals(AppThemeMode.dark));
      // The app-level controller picks the change up without a second
      // write to the store (mirrors the language section's own test).
      expect(themeModeController.mode, equals(AppThemeMode.dark));
    });

    testWidgets('choosing Light sets the theme mode and applies it', (
      tester,
    ) async {
      // Arrange
      final settingsStore = FakeSettingsStore();
      final controller = _controllerFor(settingsStore: settingsStore);
      final themeModeController = ThemeModeController(settingsStore);
      await _pump(tester, controller, themeModeController: themeModeController);
      await tester.pumpAndSettle();

      // Act
      final light = _appearanceOption(_en.settingsAppearanceLight);
      await tester.ensureVisible(light);
      await tester.tap(light);
      await tester.pumpAndSettle();

      // Assert
      expect(controller.themeMode, equals(AppThemeMode.light));
      expect(themeModeController.mode, equals(AppThemeMode.light));
    });

    testWidgets(
      'choosing "match my device" restores the theme mode to system',
      (tester) async {
        // Arrange
        final settingsStore = FakeSettingsStore(
          initial: const AppSettings(themeMode: AppThemeMode.dark),
        );
        final controller = _controllerFor(settingsStore: settingsStore);
        final themeModeController = ThemeModeController(settingsStore)
          ..applyMode(AppThemeMode.dark);
        await _pump(
          tester,
          controller,
          themeModeController: themeModeController,
        );
        await tester.pumpAndSettle();

        // Act
        final system = _appearanceOption(_en.settingsAppearanceSystem);
        await tester.ensureVisible(system);
        await tester.tap(system);
        await tester.pumpAndSettle();

        // Assert
        expect(controller.themeMode, equals(AppThemeMode.system));
        expect(
          (await settingsStore.read()).themeMode,
          equals(AppThemeMode.system),
        );
        expect(themeModeController.mode, equals(AppThemeMode.system));
      },
    );

    testWidgets('choosing each filter persists it', (tester) async {
      // The four values on offer match exactly what the menu screen's own
      // verdict counter tiles can produce (issue #35); greenAndYellow is
      // no longer one of the choices here, though it still decodes safely
      // for an install that persisted it before this change.
      for (final testCase in <({String label, MenuFilter filter})>[
        (label: _en.tileGreenLabel, filter: MenuFilter.greenOnly),
        (label: _en.tileYellowLabel, filter: MenuFilter.yellowOnly),
        (label: _en.tileRedLabel, filter: MenuFilter.redOnly),
        (label: _en.filterAll, filter: MenuFilter.all),
      ]) {
        // Arrange
        final settingsStore = FakeSettingsStore();
        final controller = _controllerFor(settingsStore: settingsStore);
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Act
        final segment = find.text(testCase.label);
        await tester.ensureVisible(segment);
        await tester.tap(segment);
        await tester.pumpAndSettle();

        // Assert
        expect(controller.filter, equals(testCase.filter));
        expect((await settingsStore.read()).filter, equals(testCase.filter));
      }
    });

    testWidgets(
      'an install with a persisted greenAndYellow filter opens Settings '
      'without crashing, even though no segment offers that choice any '
      'more',
      (tester) async {
        // Arrange: a filter value no longer reachable from this control
        // (issue #35), but still a legal, previously-persisted one.
        final settingsStore = FakeSettingsStore(
          initial: const AppSettings(filter: MenuFilter.greenAndYellow),
        );
        final controller = _controllerFor(settingsStore: settingsStore);

        // Act
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Assert: the screen renders — no exception, and the stored value
        // is unchanged since the user has not touched the control.
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(controller.filter, equals(MenuFilter.greenAndYellow));
      },
    );

    group('saved menus block (issue #61)', () {
      /// Seeds [repository] with one cached menu for a fresh [VenueRef],
      /// so the count section has something to show besides zero.
      Future<void> seedOneMenu(FakeMenuRepository repository) async {
        const ref = VenueRef(source: MenuSource.wolt, platformId: 'x');
        final fetched = await repository.load(ref) as MenuFetched;
        repository.seedCache(CachedMenu(menu: fetched.menu));
      }

      testWidgets('build shows 0 menus cached with nothing saved', (
        tester,
      ) async {
        // Act
        await _pump(tester, _controllerFor());
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_en.settingsCacheSummary(0)), findsOneWidget);
      });

      testWidgets('build shows the seeded count', (tester) async {
        // Arrange
        final repository = FakeMenuRepository();
        await seedOneMenu(repository);
        final controller = _controllerFor(repository: repository);

        // Act
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_en.settingsCacheSummary(1)), findsOneWidget);
      });

      testWidgets(
        'tapping Clear opens a confirmation dialog that clears nothing '
        'by itself',
        (tester) async {
          // Arrange
          final repository = FakeMenuRepository();
          await seedOneMenu(repository);
          final controller = _controllerFor(repository: repository);
          await _pump(tester, controller);
          await tester.pumpAndSettle();

          // Act
          final clearCache = find.text(_en.settingsClearCache);
          await tester.ensureVisible(clearCache);
          await tester.tap(clearCache);
          await tester.pumpAndSettle();

          // Assert
          expect(find.text(_en.settingsClearCacheConfirmTitle), findsOneWidget);
          expect(find.text(_en.settingsClearCacheConfirmBody), findsOneWidget);
          expect(repository.clearCacheCallCount, equals(0));
        },
      );

      testWidgets('cancelling the confirmation dialog clears nothing', (
        tester,
      ) async {
        // Arrange
        final repository = FakeMenuRepository();
        await seedOneMenu(repository);
        final controller = _controllerFor(repository: repository);
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Act
        final clearCache = find.text(_en.settingsClearCache);
        await tester.ensureVisible(clearCache);
        await tester.tap(clearCache);
        await tester.pumpAndSettle();
        await tester.tap(find.text(_en.actionCancel));
        await tester.pumpAndSettle();

        // Assert
        expect(repository.clearCacheCallCount, equals(0));
        expect(find.text(_en.settingsCacheCleared), findsNothing);
        expect(find.text(_en.settingsCacheSummary(1)), findsOneWidget);
      });

      testWidgets('confirming the dialog calls the repository, shows '
          'settingsCacheCleared and updates the count to 0', (tester) async {
        // Arrange
        final repository = FakeMenuRepository();
        await seedOneMenu(repository);
        final controller = _controllerFor(repository: repository);
        await _pump(tester, controller);
        await tester.pumpAndSettle();
        expect(find.text(_en.settingsCacheCleared), findsNothing);

        // Act
        final clearCache = find.text(_en.settingsClearCache);
        await tester.ensureVisible(clearCache);
        await tester.tap(clearCache);
        await tester.pumpAndSettle();
        await tester.tap(find.text(_en.settingsClearCacheConfirmAction));
        await tester.pumpAndSettle();

        // Assert
        expect(repository.clearCacheCallCount, equals(1));
        expect(find.text(_en.settingsCacheCleared), findsOneWidget);
        expect(find.text(_en.settingsCacheSummary(0)), findsOneWidget);
      });
    });

    group('net carb limit stepper (issue #57)', () {
      /// The enabled state of the stepper button keyed [key].
      bool enabled(WidgetTester tester, Key key) =>
          tester.widget<IconButton>(find.byKey(key)).onPressed != null;

      /// Taps the stepper button keyed [key] after scrolling it into view.
      Future<void> tapStepper(WidgetTester tester, Key key) async {
        await tester.ensureVisible(find.byKey(key));
        await tester.tap(find.byKey(key));
        await tester.pumpAndSettle();
      }

      testWidgets('build shows the section, its explanation and "6 g" by '
          'default', (tester) async {
        // Act
        await _pump(tester, _controllerFor());
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_en.settingsNetCarbLimit), findsOneWidget);
        expect(find.text(_en.settingsNetCarbLimitBody), findsOneWidget);
        expect(find.text('6 g'), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(netCarbLimitValueKey)).data,
          equals(_en.settingsNetCarbLimitValue(6)),
        );
      });

      testWidgets('the section sits under Appearance and above the default '
          'filter', (tester) async {
        // Act
        await _pump(tester, _controllerFor());
        await tester.pumpAndSettle();

        // Assert
        final appearanceY = tester
            .getTopLeft(find.text(_en.settingsAppearance))
            .dy;
        final limitY = tester
            .getTopLeft(find.text(_en.settingsNetCarbLimit))
            .dy;
        final filterY = tester.getTopLeft(find.text(_en.settingsFilter)).dy;
        expect(limitY, greaterThan(appearanceY));
        expect(limitY, lessThan(filterY));
      });

      testWidgets('plus and minus step the limit by one gram and persist '
          'it', (tester) async {
        // Arrange
        final store = FakeSettingsStore();
        final controller = _controllerFor(settingsStore: store);
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Act
        await tapStepper(tester, netCarbLimitIncreaseKey);
        await tapStepper(tester, netCarbLimitIncreaseKey);

        // Assert
        expect(find.text('8 g'), findsOneWidget);
        expect((await store.read()).netCarbLimitGrams, equals(8));

        // Act
        await tapStepper(tester, netCarbLimitDecreaseKey);

        // Assert
        expect(find.text('7 g'), findsOneWidget);
        expect((await store.read()).netCarbLimitGrams, equals(7));
      });

      testWidgets('minus is disabled at 2 g, so the limit stays at 2 g', (
        tester,
      ) async {
        // Arrange: one gram above the floor.
        final store = FakeSettingsStore(
          initial: const AppSettings(netCarbLimitGrams: 3),
        );
        await _pump(tester, _controllerFor(settingsStore: store));
        await tester.pumpAndSettle();
        expect(enabled(tester, netCarbLimitDecreaseKey), isTrue);

        // Act: step down to the floor, then try once more.
        await tapStepper(tester, netCarbLimitDecreaseKey);
        await tapStepper(tester, netCarbLimitDecreaseKey);

        // Assert
        expect(find.text('2 g'), findsOneWidget);
        expect(enabled(tester, netCarbLimitDecreaseKey), isFalse);
        expect(enabled(tester, netCarbLimitIncreaseKey), isTrue);
        expect((await store.read()).netCarbLimitGrams, equals(2));
      });

      testWidgets('plus is disabled at 25 g, so the limit stays at 25 g', (
        tester,
      ) async {
        // Arrange: one gram below the ceiling.
        final store = FakeSettingsStore(
          initial: const AppSettings(netCarbLimitGrams: 24),
        );
        await _pump(tester, _controllerFor(settingsStore: store));
        await tester.pumpAndSettle();
        expect(enabled(tester, netCarbLimitIncreaseKey), isTrue);

        // Act: step up to the ceiling, then try once more.
        await tapStepper(tester, netCarbLimitIncreaseKey);
        await tapStepper(tester, netCarbLimitIncreaseKey);

        // Assert
        expect(find.text('25 g'), findsOneWidget);
        expect(enabled(tester, netCarbLimitIncreaseKey), isFalse);
        expect(enabled(tester, netCarbLimitDecreaseKey), isTrue);
        expect((await store.read()).netCarbLimitGrams, equals(25));
      });

      testWidgets('both buttons carry a localized tooltip', (tester) async {
        // Act
        await _pump(tester, _controllerFor());
        await tester.pumpAndSettle();

        // Assert
        expect(
          tester
              .widget<IconButton>(find.byKey(netCarbLimitDecreaseKey))
              .tooltip,
          equals(_en.settingsNetCarbLimitDecrease),
        );
        expect(
          tester
              .widget<IconButton>(find.byKey(netCarbLimitIncreaseKey))
              .tooltip,
          equals(_en.settingsNetCarbLimitIncrease),
        );
      });

      testWidgets('under Locale(he) the value reads in Hebrew', (tester) async {
        // Act
        await _pump(tester, _controllerFor(), locale: const Locale('he'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_he.settingsNetCarbLimit), findsOneWidget);
        expect(find.text(_he.settingsNetCarbLimitValue(6)), findsOneWidget);
      });
    });

    group('Your keto rules toggles (issue #56)', () {
      /// The [SwitchListTile] keyed [key].
      SwitchListTile tile(WidgetTester tester, Key key) =>
          tester.widget<SwitchListTile>(find.byKey(key));

      /// Taps the switch keyed [key] after scrolling it into view.
      Future<void> tapSwitch(WidgetTester tester, Key key) async {
        await tester.ensureVisible(find.byKey(key));
        await tester.tap(find.byKey(key));
        await tester.pumpAndSettle();
      }

      testWidgets('build shows the section, its three rules and their '
          'hints, every switch off by default', (tester) async {
        // Act
        await _pump(tester, _controllerFor());
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_en.settingsKetoRules), findsOneWidget);
        expect(find.text(_en.settingsKetoRulesBody), findsOneWidget);
        expect(find.text(_en.settingsSeedOilFree), findsOneWidget);
        expect(find.text(_en.settingsSeedOilFreeHint), findsOneWidget);
        expect(find.text(_en.settingsDairyFree), findsOneWidget);
        expect(find.text(_en.settingsDairyFreeHint), findsOneWidget);
        expect(find.text(_en.settingsCarnivoreOnly), findsOneWidget);
        expect(find.text(_en.settingsCarnivoreOnlyHint), findsOneWidget);
        expect(tile(tester, seedOilFreeSwitchKey).value, isFalse);
        expect(tile(tester, dairyFreeSwitchKey).value, isFalse);
        expect(tile(tester, carnivoreOnlySwitchKey).value, isFalse);
      });

      testWidgets('the section sits under the net carb limit and above the '
          'default filter', (tester) async {
        // Act
        await _pump(tester, _controllerFor());
        await tester.pumpAndSettle();

        // Assert
        final limitY = tester
            .getTopLeft(find.text(_en.settingsNetCarbLimit))
            .dy;
        final rulesY = tester.getTopLeft(find.text(_en.settingsKetoRules)).dy;
        final filterY = tester.getTopLeft(find.text(_en.settingsFilter)).dy;
        expect(rulesY, greaterThan(limitY));
        expect(rulesY, lessThan(filterY));
      });

      testWidgets('load shows a stored toggle as on', (tester) async {
        // Arrange
        final store = FakeSettingsStore(
          initial: const AppSettings(dairyFree: true),
        );

        // Act
        await _pump(tester, _controllerFor(settingsStore: store));
        await tester.pumpAndSettle();

        // Assert
        expect(tile(tester, dairyFreeSwitchKey).value, isTrue);
        expect(tile(tester, seedOilFreeSwitchKey).value, isFalse);
        expect(tile(tester, carnivoreOnlySwitchKey).value, isFalse);
      });

      testWidgets('tapping seed-oil free calls the controller and persists '
          'only that toggle', (tester) async {
        // Arrange
        final store = FakeSettingsStore();
        final controller = _controllerFor(settingsStore: store);
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Act
        await tapSwitch(tester, seedOilFreeSwitchKey);

        // Assert
        expect(controller.seedOilFree, isTrue);
        expect(tile(tester, seedOilFreeSwitchKey).value, isTrue);
        final stored = await store.read();
        expect(stored.seedOilFree, isTrue);
        expect(stored.dairyFree, isFalse);
        expect(stored.carnivoreOnly, isFalse);
      });

      testWidgets('tapping dairy-free calls the controller and persists '
          'only that toggle', (tester) async {
        // Arrange
        final store = FakeSettingsStore();
        final controller = _controllerFor(settingsStore: store);
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Act
        await tapSwitch(tester, dairyFreeSwitchKey);

        // Assert
        expect(controller.dairyFree, isTrue);
        final stored = await store.read();
        expect(stored.dairyFree, isTrue);
        expect(stored.seedOilFree, isFalse);
        expect(stored.carnivoreOnly, isFalse);
      });

      testWidgets('tapping carnivore only calls the controller and persists '
          'only that toggle', (tester) async {
        // Arrange
        final store = FakeSettingsStore();
        final controller = _controllerFor(settingsStore: store);
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Act
        await tapSwitch(tester, carnivoreOnlySwitchKey);

        // Assert
        expect(controller.carnivoreOnly, isTrue);
        final stored = await store.read();
        expect(stored.carnivoreOnly, isTrue);
        expect(stored.seedOilFree, isFalse);
        expect(stored.dairyFree, isFalse);
      });

      testWidgets('tapping a switch that is on turns it off again', (
        tester,
      ) async {
        // Arrange
        final store = FakeSettingsStore(
          initial: const AppSettings(carnivoreOnly: true),
        );
        await _pump(tester, _controllerFor(settingsStore: store));
        await tester.pumpAndSettle();

        // Act
        await tapSwitch(tester, carnivoreOnlySwitchKey);

        // Assert
        expect(tile(tester, carnivoreOnlySwitchKey).value, isFalse);
        expect((await store.read()).carnivoreOnly, isFalse);
      });

      testWidgets('under Locale(he) the section renders in Hebrew', (
        tester,
      ) async {
        // Act
        await _pump(tester, _controllerFor(), locale: const Locale('he'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_he.settingsKetoRules), findsOneWidget);
        expect(find.text(_he.settingsKetoRulesBody), findsOneWidget);
        expect(find.text(_he.settingsSeedOilFree), findsOneWidget);
        expect(find.text(_he.settingsSeedOilFreeHint), findsOneWidget);
        expect(find.text(_he.settingsDairyFree), findsOneWidget);
        expect(find.text(_he.settingsDairyFreeHint), findsOneWidget);
        expect(find.text(_he.settingsCarnivoreOnly), findsOneWidget);
        expect(find.text(_he.settingsCarnivoreOnlyHint), findsOneWidget);
        expect(find.text(_en.settingsKetoRules), findsNothing);
      });
    });

    testWidgets('build under Locale(he) renders the Hebrew title', (
      tester,
    ) async {
      // Act
      await _pump(tester, _controllerFor(), locale: const Locale('he'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_he.settingsTitle), findsOneWidget);
      expect(find.text(_he.settingsConsentTitle), findsOneWidget);
    });

    group('right-to-left (architecture.md §8.3)', () {
      testWidgets(
        'under Locale(he) the screen renders under RTL directionality and '
        'mirrors the net-carb stepper: minus sits right of plus',
        (tester) async {
          // Act
          await _pump(tester, _controllerFor(), locale: const Locale('he'));
          await tester.pumpAndSettle();

          // Assert: real layout mirroring, not only Hebrew strings under
          // an LTR frame — the same claim `waiter_card_sheet_test.dart`
          // and `venue_card_test.dart` already pin for their own screens.
          // Under LTR the stepper reads minus, value, plus, left to
          // right; under RTL `Row` reverses that order, so the minus
          // button (first in source order) ends up to the right of plus
          // (last in source order) rather than to its left.
          final context = tester.element(find.byType(SettingsScreen));
          expect(Directionality.of(context), TextDirection.rtl);
          final decrease = tester.getCenter(
            find.byKey(netCarbLimitDecreaseKey),
          );
          final increase = tester.getCenter(
            find.byKey(netCarbLimitIncreaseKey),
          );
          expect(decrease.dx, greaterThan(increase.dx));
          expect(tester.takeException(), isNull);
        },
      );
    });
  });
}
