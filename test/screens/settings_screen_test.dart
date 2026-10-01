import 'dart:async';

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

import '../fakes/fake_api_key_store.dart';
import '../fakes/fake_app_info.dart';
import '../fakes/fake_external_link_opener.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';

/// The English strings a test can read expected copy from, computed the
/// same way the widget under test does.
final AppLocalizations _en = AppLocalizationsEn();

/// The Hebrew strings for the one Locale('he') test.
final AppLocalizations _he = AppLocalizationsHe();

/// The `find.text` match for [label], scoped to the language section's
/// segmented control ([languageRadioGroupKey]), so a label that happens to
/// match another section's (as `settingsLanguageSystem` and
/// `settingsAppearanceSystem` once did) can never make `find.text`
/// ambiguous.
Finder _languageOption(String label) => find.descendant(
  of: find.byKey(languageRadioGroupKey),
  matching: find.text(label),
);

/// The `find.text` match for [label], scoped to the appearance section's
/// segmented control ([appearanceRadioGroupKey]); see [_languageOption].
Finder _appearanceOption(String label) => find.descendant(
  of: find.byKey(appearanceRadioGroupKey),
  matching: find.text(label),
);

/// A [SettingsStore] whose [write] waits on [release], so a test can look
/// at the screen while the controller is busy writing.
final class _GatedSettingsStore implements SettingsStore {
  /// Completed by the test to let the pending write finish.
  final Completer<void> release = Completer<void>();

  @override
  Future<AppSettings> read() async => const AppSettings();

  @override
  Future<void> write(AppSettings settings) => release.future;
}

/// Builds the [SettingsController] the widget under test is pumped over,
/// from fresh fakes unless the caller seeds one.
///
/// [apiKeyStore] stands in for a phone build (architecture.md D17): with
/// one the screen shows the Gemini key section; without one — the web
/// build, and every other test here — it does not.
SettingsController _controllerFor({
  FakeSettingsStore? settingsStore,
  FakeMenuRepository? repository,
  FakeApiKeyStore? apiKeyStore,
}) => SettingsController(
  settingsStore ?? FakeSettingsStore(),
  repository ?? FakeMenuRepository(),
  apiKeyStore,
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
  FakeAppInfo? appInfo,
  FakeExternalLinkOpener? externalLinkOpener,
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
        child: SettingsScreen(
          appInfo: appInfo ?? FakeAppInfo(),
          externalLinkOpener: externalLinkOpener ?? FakeExternalLinkOpener(),
        ),
      ),
    ),
  );
}

/// Opens the "What leaves this device" disclosure ([consentDisclosureKey]),
/// which is collapsed by default (issue #255), so the consent body text is
/// built and a test can find it.
Future<void> _expandConsentDisclosure(WidgetTester tester) async {
  final disclosure = find.byKey(consentDisclosureKey);
  await tester.ensureVisible(disclosure);
  await tester.tap(disclosure);
  await tester.pumpAndSettle();
}

/// The vertical position of [finder]'s top edge, for asserting the order
/// of the screen's sections.
double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

void main() {
  group('SettingsScreen', () {
    testWidgets('the consent body is collapsed by default, with the checkbox '
        'visible (issue #255)', (tester) async {
      // Arrange
      final controller = _controllerFor();

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.settingsAiPrivacy), findsOneWidget);
      expect(find.text(_en.settingsConsentTitle), findsOneWidget);
      expect(find.text(_en.settingsConsentBody), findsNothing);
      expect(find.text(_en.settingsConsentAccept), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsOneWidget);
    });

    testWidgets('opening the disclosure shows the consent body and keeps '
        'the checkbox', (tester) async {
      // Arrange
      final controller = _controllerFor();
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Act
      await _expandConsentDisclosure(tester);

      // Assert
      expect(find.text(_en.settingsConsentBody), findsOneWidget);
      expect(find.text(_en.settingsConsentAccept), findsOneWidget);
    });

    testWidgets(
      'sections run Language, Appearance, keto rules, net carb limit, '
      'default filter, AI & privacy, Recent menus '
      '(issue #255)',
      (tester) async {
        // Arrange
        final controller = _controllerFor();

        // Act
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Assert
        final tops = [
          _en.settingsLanguage,
          _en.settingsAppearance,
          _en.settingsKetoRules,
          _en.settingsNetCarbLimit,
          _en.settingsFilter,
          _en.settingsAiPrivacy,
          _en.settingsCacheSection,
        ].map((label) => _top(tester, find.text(label))).toList();
        for (var i = 1; i < tops.length; i++) {
          expect(tops[i], greaterThan(tops[i - 1]));
        }
      },
    );

    testWidgets('the drinks guide moved to Explore: Settings has no drinks '
        'row (issue #257)', (tester) async {
      // Arrange
      final controller = _controllerFor();

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.byIcon(Icons.local_bar), findsNothing);
      expect(find.text(_en.drinksGuideTitle.toUpperCase()), findsNothing);
    });

    testWidgets('the cache group carries the "Recent menus" label above '
        'its count (issue #255)', (tester) async {
      // Arrange
      final controller = _controllerFor();

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      final label = find.text(_en.settingsCacheSection);
      expect(label, findsOneWidget);
      expect(
        _top(tester, label),
        lessThan(_top(tester, find.text(_en.settingsCacheSummary(0)))),
      );
    });

    testWidgets(
      'the consent checkbox starts checked on a fresh install (D16, issue '
      '#167) and unticking it persists false',
      (tester) async {
        // Arrange: a virgin store — the D16 default of true kicks in.
        final settingsStore = FakeSettingsStore();
        final controller = _controllerFor(settingsStore: settingsStore);
        await _pump(tester, controller);
        await tester.pumpAndSettle();
        expect(controller.consentGiven, isTrue);

        // Act: untick the checkbox.
        final accept = find.text(_en.settingsConsentAccept);
        await tester.ensureVisible(accept);
        await tester.tap(accept);
        await tester.pumpAndSettle();

        // Assert
        expect(controller.consentGiven, isFalse);
        final stored = await settingsStore.read();
        expect(stored.estimationConsentGiven, isFalse);
      },
    );

    testWidgets(
      'an install that persisted a refusal keeps its refusal, and the '
      'checkbox is unticked (D16, issue #167)',
      (tester) async {
        // Arrange
        final settingsStore = FakeSettingsStore(
          initial: const AppSettings(estimationConsentGiven: false),
        );
        final controller = _controllerFor(settingsStore: settingsStore);

        // Act
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Assert
        expect(controller.consentGiven, isFalse);
      },
    );

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

    testWidgets('language and appearance are one-row segmented controls '
        'showing the stored choice (issue #256)', (tester) async {
      // Arrange
      final controller = _controllerFor(
        settingsStore: FakeSettingsStore(
          initial: const AppSettings(
            languageTag: 'he',
            themeMode: AppThemeMode.dark,
          ),
        ),
      );

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      final language = tester.widget<SegmentedButton<String?>>(
        find.descendant(
          of: find.byKey(languageRadioGroupKey),
          matching: find.byType(SegmentedButton<String?>),
        ),
      );
      final appearance = tester.widget<SegmentedButton<AppThemeMode>>(
        find.descendant(
          of: find.byKey(appearanceRadioGroupKey),
          matching: find.byType(SegmentedButton<AppThemeMode>),
        ),
      );
      expect(language.selected, equals(<String?>{'he'}));
      expect(appearance.selected, equals(<AppThemeMode>{AppThemeMode.dark}));
      expect(find.byType(RadioListTile<String?>), findsNothing);
      expect(find.byType(RadioListTile<AppThemeMode>), findsNothing);
    });

    testWidgets('"match my device" shows as selected when no language is '
        'stored (issue #256)', (tester) async {
      // Arrange
      final controller = _controllerFor();

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert: a null segment value is a real selection, not "none".
      final language = tester.widget<SegmentedButton<String?>>(
        find.byType(SegmentedButton<String?>),
      );
      expect(language.selected, equals(<String?>{null}));
    });

    testWidgets('language and appearance cannot be changed while the '
        'screen is busy (issue #256)', (tester) async {
      // Arrange
      final store = _GatedSettingsStore();
      final controller = SettingsController(store, FakeMenuRepository());
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Act: start a write and look before it finishes.
      final pending = controller.setConsent(given: true);
      await tester.pump();

      // Assert
      expect(controller.isBusy, isTrue);
      expect(
        tester
            .widget<SegmentedButton<String?>>(
              find.byType(SegmentedButton<String?>),
            )
            .onSelectionChanged,
        isNull,
      );
      expect(
        tester
            .widget<SegmentedButton<AppThemeMode>>(
              find.byType(SegmentedButton<AppThemeMode>),
            )
            .onSelectionChanged,
        isNull,
      );
      store.release.complete();
      await pending;
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedButton<String?>>(
              find.byType(SegmentedButton<String?>),
            )
            .onSelectionChanged,
        isNotNull,
      );
    });

    testWidgets(
      'in Hebrew at 390px no label wraps or breaks mid-word (issue #256)',
      (tester) async {
        // Arrange: a phone-sized, Hebrew screen, the longest labels.
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = _controllerFor();

        // Act
        await _pump(tester, controller, locale: const Locale('he'));
        await tester.pumpAndSettle();

        // Assert: the test font (Ahem) is far wider than a real one, so the
        // fit itself is not assertable here; what is, is that the control
        // never squeezes a label (no wrap, no mid-word break), because it
        // sizes to its content and falls back to a sideways scroll.
        // A single-line label is one line tall; a wrapped one is taller.
        for (final label in [
          _he.settingsLanguageSystem,
          _he.settingsLanguageEnglish,
          _he.settingsLanguageHebrew,
          _he.settingsAppearanceSystem,
          _he.settingsAppearanceLight,
          _he.settingsAppearanceDark,
        ]) {
          expect(tester.getSize(find.text(label)).height, lessThan(24));
        }
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

  group('SettingsScreen Gemini API key (architecture.md D17)', () {
    testWidgets('web: no key section, and the via-server disclosure', (
      tester,
    ) async {
      // Arrange
      final controller = _controllerFor();

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.settingsKeySection), findsNothing);
      expect(find.byKey(apiKeyFieldKey), findsNothing);
      await _expandConsentDisclosure(tester);
      expect(find.text(_en.settingsConsentBody), findsOneWidget);
      expect(find.text(_en.settingsConsentBodyDirect), findsNothing);
    });

    testWidgets('phone: the key section and the direct-to-Google '
        'disclosure', (tester) async {
      // Arrange
      final controller = _controllerFor(apiKeyStore: FakeApiKeyStore());

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.settingsKeySection), findsOneWidget);
      expect(find.text(_en.settingsKeyBody), findsOneWidget);
      expect(find.text(_en.settingsKeyAbsent), findsOneWidget);
      expect(find.byKey(apiKeySaveKey), findsOneWidget);
      expect(find.byKey(apiKeyDeleteKey), findsNothing);
      await _expandConsentDisclosure(tester);
      expect(find.text(_en.settingsConsentBodyDirect), findsOneWidget);
      expect(find.text(_en.settingsConsentBody), findsNothing);
    });

    testWidgets('phone: the key section sits in AI & privacy, after the '
        'consent checkbox and before Recent menus (issue #255)', (
      tester,
    ) async {
      // Arrange
      final controller = _controllerFor(apiKeyStore: FakeApiKeyStore());

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      final consent = _top(tester, find.text(_en.settingsConsentAccept));
      final key = _top(tester, find.text(_en.settingsKeySection));
      final cache = _top(tester, find.text(_en.settingsCacheSection));
      expect(_top(tester, find.text(_en.settingsAiPrivacy)), lessThan(consent));
      expect(key, greaterThan(consent));
      expect(key, lessThan(cache));
    });

    testWidgets('the key field is obscured and never prefilled', (
      tester,
    ) async {
      // Arrange
      const secret = 'AIza-already-saved';
      final controller = _controllerFor(
        apiKeyStore: FakeApiKeyStore(seed: secret),
      );

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      final field = tester.widget<TextField>(find.byKey(apiKeyFieldKey));
      expect(field.obscureText, isTrue);
      expect(field.controller!.text, isEmpty);
      expect(find.text(secret), findsNothing);
      expect(find.text(_en.settingsKeyPresent), findsOneWidget);
    });

    testWidgets('saving stores the trimmed key, clears the field and '
        'offers Remove', (tester) async {
      // Arrange
      final keys = FakeApiKeyStore();
      final controller = _controllerFor(apiKeyStore: keys);
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Act
      await tester.ensureVisible(find.byKey(apiKeyFieldKey));
      await tester.enterText(find.byKey(apiKeyFieldKey), '  AIza-typed  ');
      // Below the fold on the default 800×600 surface once the content
      // column is capped (issue #221).
      await tester.ensureVisible(find.byKey(apiKeySaveKey));
      await tester.tap(find.byKey(apiKeySaveKey));
      await tester.pumpAndSettle();

      // Assert
      expect(await keys.read(), 'AIza-typed');
      final field = tester.widget<TextField>(find.byKey(apiKeyFieldKey));
      expect(field.controller!.text, isEmpty);
      expect(find.text(_en.settingsKeyPresent), findsOneWidget);
      expect(find.byKey(apiKeyDeleteKey), findsOneWidget);
    });

    testWidgets('saving a blank field stores nothing', (tester) async {
      // Arrange
      final keys = FakeApiKeyStore();
      final controller = _controllerFor(apiKeyStore: keys);
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Act
      await tester.ensureVisible(find.byKey(apiKeyFieldKey));
      await tester.enterText(find.byKey(apiKeyFieldKey), '   ');
      await tester.ensureVisible(find.byKey(apiKeySaveKey));
      await tester.tap(find.byKey(apiKeySaveKey));
      await tester.pumpAndSettle();

      // Assert
      expect(keys.writeCallCount, 0);
      expect(find.text(_en.settingsKeyAbsent), findsOneWidget);
    });

    testWidgets('Remove deletes the saved key', (tester) async {
      // Arrange
      final keys = FakeApiKeyStore(seed: 'AIza-saved');
      final controller = _controllerFor(apiKeyStore: keys);
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Act
      await tester.ensureVisible(find.byKey(apiKeyDeleteKey));
      await tester.tap(find.byKey(apiKeyDeleteKey));
      await tester.pumpAndSettle();

      // Assert
      expect(await keys.read(), isNull);
      expect(find.text(_en.settingsKeyAbsent), findsOneWidget);
      expect(find.byKey(apiKeyDeleteKey), findsNothing);
    });

    testWidgets('renders the key section in Hebrew', (tester) async {
      // Arrange
      final controller = _controllerFor(apiKeyStore: FakeApiKeyStore());

      // Act
      await _pump(tester, controller, locale: const Locale('he'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_he.settingsAiPrivacy), findsOneWidget);
      expect(find.text(_he.settingsKeySection), findsOneWidget);
      await _expandConsentDisclosure(tester);
      expect(find.text(_he.settingsConsentBodyDirect), findsOneWidget);
    });
  });

  group('About section (issue #258)', () {
    testWidgets('shows the version and build after the first frame', (
      tester,
    ) async {
      // Arrange
      final appInfo = FakeAppInfo();
      await _pump(tester, _controllerFor(), appInfo: appInfo);

      // Act
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(aboutVersionKey));

      // Assert
      expect(appInfo.loadCalls, 1);
      expect(find.text(_en.settingsAboutSection), findsOneWidget);
      expect(
        find.text(_en.settingsAboutVersionValue('1.2.3', '45')),
        findsOneWidget,
      );
    });

    testWidgets('does not read the version while building', (tester) async {
      // Arrange
      final appInfo = FakeAppInfo();

      // Act: one frame only, no post-frame work awaited.
      await _pump(tester, _controllerFor(), appInfo: appInfo);

      // Assert: the load is scheduled after the first frame, then runs.
      await tester.pumpAndSettle();
      expect(appInfo.loadCalls, 1);
    });

    testWidgets('shows no version text when the platform cannot say', (
      tester,
    ) async {
      // Arrange
      final appInfo = FakeAppInfo(answer: null);
      await _pump(tester, _controllerFor(), appInfo: appInfo);

      // Act
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(aboutVersionKey));

      // Assert
      expect(find.text(_en.settingsAboutVersion), findsOneWidget);
      expect(find.textContaining('build'), findsNothing);
    });

    testWidgets('licences row opens the licence page', (tester) async {
      // Arrange
      await _pump(tester, _controllerFor());
      await tester.pumpAndSettle();

      // Act
      await tester.ensureVisible(find.byKey(aboutLicencesKey));
      await tester.tap(find.byKey(aboutLicencesKey));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(LicensePage), findsOneWidget);
    });

    testWidgets('privacy row reveals the web consent text', (tester) async {
      // Arrange
      await _pump(tester, _controllerFor());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(aboutPrivacyKey));
      expect(find.text(_en.settingsConsentBody), findsNothing);

      // Act
      await tester.tap(find.byKey(aboutPrivacyKey));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.settingsConsentBody), findsOneWidget);
    });

    testWidgets('privacy row reveals the direct text on a phone', (
      tester,
    ) async {
      // Arrange
      final controller = _controllerFor(apiKeyStore: FakeApiKeyStore());
      await _pump(tester, controller);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(aboutPrivacyKey));

      // Act
      await tester.tap(find.byKey(aboutPrivacyKey));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.settingsConsentBodyDirect), findsOneWidget);
    });

    testWidgets('report row opens the issue tracker', (tester) async {
      // Arrange
      final opener = FakeExternalLinkOpener();
      await _pump(tester, _controllerFor(), externalLinkOpener: opener);
      await tester.pumpAndSettle();

      // Act
      await tester.ensureVisible(find.byKey(aboutReportKey));
      await tester.tap(find.byKey(aboutReportKey));
      await tester.pumpAndSettle();

      // Assert
      expect(opener.openCalls, [reportProblemUri]);
      expect(find.text(_en.settingsAboutLinkFailed), findsNothing);
    });

    testWidgets('report row says so when the link cannot open', (tester) async {
      // Arrange
      final opener = FakeExternalLinkOpener()..answer = false;
      await _pump(tester, _controllerFor(), externalLinkOpener: opener);
      await tester.pumpAndSettle();

      // Act
      await tester.ensureVisible(find.byKey(aboutReportKey));
      await tester.tap(find.byKey(aboutReportKey));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.settingsAboutLinkFailed), findsOneWidget);
    });

    testWidgets('renders the About group in Hebrew', (tester) async {
      // Arrange
      await _pump(tester, _controllerFor(), locale: const Locale('he'));

      // Act
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(aboutReportKey));

      // Assert
      expect(find.text(_he.settingsAboutSection), findsOneWidget);
      expect(find.text(_he.settingsAboutReport), findsOneWidget);
      expect(
        find.text(_he.settingsAboutVersionValue('1.2.3', '45')),
        findsOneWidget,
      );
    });
  });
}
