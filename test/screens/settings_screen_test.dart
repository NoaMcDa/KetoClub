import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_key_store.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';

/// The English strings a test can read expected copy from, computed the
/// same way the widget under test does.
final AppLocalizations _en = AppLocalizationsEn();

/// The Hebrew strings for the one Locale('he') test.
final AppLocalizations _he = AppLocalizationsHe();

/// A distinctive value used by the tests that save a key, chosen so it
/// cannot appear anywhere else in the rendered tree by coincidence.
const String _secretKey = 'sk-or-v1-zzz-not-a-real-key-zzz';

/// Builds the [SettingsController] the widget under test is pumped over,
/// from fresh fakes unless the caller seeds one.
SettingsController _controllerFor({
  FakeKeyStore? keyStore,
  FakeSettingsStore? settingsStore,
  FakeMenuRepository? repository,
}) => SettingsController(
  keyStore ?? FakeKeyStore(),
  settingsStore ?? FakeSettingsStore(),
  repository ?? FakeMenuRepository(),
);

/// Pumps the real [SettingsScreen] over a real [SettingsController],
/// inside a localised [MaterialApp] — the shape every test in this file
/// uses. Does not itself wait for [SettingsController.load] to settle;
/// callers that need loaded state call `tester.pumpAndSettle()`
/// afterwards, exactly as the app's own post-frame load is expected to
/// resolve.
Future<void> _pump(
  WidgetTester tester,
  SettingsController controller, {
  Locale locale = const Locale('en'),
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: ChangeNotifierProvider<SettingsController>.value(
        value: controller,
        child: const SettingsScreen(),
      ),
    ),
  );
}

void main() {
  group('SettingsScreen', () {
    testWidgets('build with no key shows settingsKeyAbsent', (tester) async {
      // Arrange
      final controller = _controllerFor();

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.settingsKeyAbsent), findsOneWidget);
      expect(find.text(_en.settingsKeyDelete), findsNothing);
    });

    testWidgets('build with no key hides the delete action', (tester) async {
      // Arrange
      final controller = _controllerFor();

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(
        find.widgetWithText(OutlinedButton, _en.settingsKeyDelete),
        findsNothing,
      );
    });

    testWidgets('saveKey with a typed key calls through to the KeyStore', (
      tester,
    ) async {
      // Arrange
      final keyStore = FakeKeyStore();
      final controller = _controllerFor(keyStore: keyStore);
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Act
      await tester.enterText(find.byType(TextField), _secretKey);
      await tester.tap(find.widgetWithText(FilledButton, _en.settingsKeySave));
      await tester.pumpAndSettle();

      // Assert
      expect(keyStore.writeCallCount, equals(1));
      expect(await keyStore.read(), equals(_secretKey));
    });

    testWidgets('saving a key flips the status to settingsKeyPresent', (
      tester,
    ) async {
      // Arrange
      final controller = _controllerFor();
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Act
      await tester.enterText(find.byType(TextField), _secretKey);
      await tester.tap(find.widgetWithText(FilledButton, _en.settingsKeySave));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.settingsKeyPresent), findsOneWidget);
      expect(find.text(_en.settingsKeyAbsent), findsNothing);
    });

    testWidgets('the key field is obscured', (tester) async {
      // Arrange
      final controller = _controllerFor();

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isTrue);
    });

    testWidgets(
      'a saved key never appears as text anywhere in the widget tree',
      (tester) async {
        // Arrange
        final keyStore = FakeKeyStore();
        final controller = _controllerFor(keyStore: keyStore);
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Act
        await tester.enterText(find.byType(TextField), _secretKey);
        await tester.tap(
          find.widgetWithText(FilledButton, _en.settingsKeySave),
        );
        await tester.pumpAndSettle();

        // Assert: the key really was stored (this is not a no-op save)…
        expect(await keyStore.read(), equals(_secretKey));
        // …yet the plaintext is nowhere in the rendered tree, and the
        // field itself was cleared after the save completed.
        expect(find.text(_secretKey), findsNothing);
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, isEmpty);
      },
    );

    testWidgets('deleteKey removes the key and flips the status back', (
      tester,
    ) async {
      // Arrange
      final keyStore = FakeKeyStore(seed: _secretKey);
      final controller = _controllerFor(keyStore: keyStore);
      await _pump(tester, controller);
      await tester.pumpAndSettle();
      expect(find.text(_en.settingsKeyPresent), findsOneWidget);

      // Act
      await tester.tap(
        find.widgetWithText(OutlinedButton, _en.settingsKeyDelete),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(keyStore.deleteCallCount, equals(1));
      expect(find.text(_en.settingsKeyAbsent), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, _en.settingsKeyDelete),
        findsNothing,
      );
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
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Act
      final english = find.text(_en.settingsLanguageEnglish);
      await tester.ensureVisible(english);
      await tester.tap(english);
      await tester.pumpAndSettle();

      // Assert
      expect(controller.languageTag, equals('en'));
      expect((await settingsStore.read()).languageTag, equals('en'));
    });

    testWidgets('choosing Hebrew sets the language tag to he', (tester) async {
      // Arrange
      final settingsStore = FakeSettingsStore();
      final controller = _controllerFor(settingsStore: settingsStore);
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Act
      final hebrew = find.text(_en.settingsLanguageHebrew);
      await tester.ensureVisible(hebrew);
      await tester.tap(hebrew);
      await tester.pumpAndSettle();

      // Assert
      expect(controller.languageTag, equals('he'));
      expect((await settingsStore.read()).languageTag, equals('he'));
    });

    testWidgets(
      'choosing "match my device" clears a previously set language tag',
      (tester) async {
        // Arrange
        final settingsStore = FakeSettingsStore(
          initial: const AppSettings(languageTag: 'he'),
        );
        final controller = _controllerFor(settingsStore: settingsStore);
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Act
        final system = find.text(_en.settingsLanguageSystem);
        await tester.ensureVisible(system);
        await tester.tap(system);
        await tester.pumpAndSettle();

        // Assert
        expect(controller.languageTag, isNull);
        expect((await settingsStore.read()).languageTag, isNull);
      },
    );

    testWidgets('choosing each filter persists it', (tester) async {
      for (final testCase in <({String label, MenuFilter filter})>[
        (label: _en.filterGreenOnly, filter: MenuFilter.greenOnly),
        (label: _en.filterAll, filter: MenuFilter.all),
        (label: _en.filterGreenAndYellow, filter: MenuFilter.greenAndYellow),
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
      'clearing the cache calls the repository and shows settingsCacheCleared',
      (tester) async {
        // Arrange
        final repository = FakeMenuRepository();
        final controller = _controllerFor(repository: repository);
        await _pump(tester, controller);
        await tester.pumpAndSettle();
        expect(find.text(_en.settingsCacheCleared), findsNothing);

        // Act
        final clearCache = find.text(_en.settingsClearCache);
        await tester.ensureVisible(clearCache);
        await tester.tap(clearCache);
        await tester.pumpAndSettle();

        // Assert
        expect(repository.clearCacheCallCount, equals(1));
        expect(find.text(_en.settingsCacheCleared), findsOneWidget);
      },
    );

    testWidgets('build under Locale(he) renders the Hebrew title', (
      tester,
    ) async {
      // Act
      await _pump(tester, _controllerFor(), locale: const Locale('he'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_he.settingsTitle), findsOneWidget);
      expect(find.text(_he.settingsKeySection), findsOneWidget);
    });

    testWidgets('build shows the backend section', (tester) async {
      // Arrange
      final controller = _controllerFor();

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.settingsBackendSection), findsOneWidget);
      expect(find.text(_en.settingsBackendBody), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, _en.settingsBackendSave),
        findsOneWidget,
      );
    });

    testWidgets('build with no stored address hides the clear action', (
      tester,
    ) async {
      // Arrange
      final controller = _controllerFor();

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(
        find.widgetWithText(OutlinedButton, _en.settingsBackendClear),
        findsNothing,
      );
    });

    testWidgets('a stored address is prefilled and clearable', (tester) async {
      // Arrange: unlike the key, this value is not a secret, so the field
      // shows it — editing an address you cannot see would be needless
      // work.
      final settingsStore = FakeSettingsStore();
      await settingsStore.write(
        const AppSettings(backendUrl: 'http://192.168.1.20:8000'),
      );
      final controller = _controllerFor(settingsStore: settingsStore);

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('http://192.168.1.20:8000'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, _en.settingsBackendClear),
        findsOneWidget,
      );
    });

    testWidgets('typing an address and saving stores it', (tester) async {
      // Arrange
      final settingsStore = FakeSettingsStore();
      final controller = _controllerFor(settingsStore: settingsStore);
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Act
      // The backend field is the last on the screen; the key field is the
      // other one, and it is obscured.
      await tester.enterText(
        find.byType(TextField).last,
        'http://localhost:8000',
      );
      await tester.tap(
        find.widgetWithText(FilledButton, _en.settingsBackendSave),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(
        (await settingsStore.read()).backendUrl,
        equals('http://localhost:8000'),
      );
    });

    testWidgets('clearing the address empties the field too', (tester) async {
      // Arrange
      final settingsStore = FakeSettingsStore();
      await settingsStore.write(
        const AppSettings(backendUrl: 'http://192.168.1.20:8000'),
      );
      final controller = _controllerFor(settingsStore: settingsStore);
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Act
      await tester.tap(
        find.widgetWithText(OutlinedButton, _en.settingsBackendClear),
      );
      await tester.pumpAndSettle();

      // Assert
      expect((await settingsStore.read()).backendUrl, isNull);
      expect(find.text('http://192.168.1.20:8000'), findsNothing);
    });
  });
}
