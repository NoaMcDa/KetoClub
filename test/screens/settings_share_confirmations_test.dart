// The "Share what the staff told you" toggle under AI & privacy (Banto,
// ALG-14, issue #409): a consent of its own, off by default, shown only in
// a Banto build with a backend, saying exactly what is sent; turning it on
// is stored under its own key and named in the privacy disclosure.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/locale_controller.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/state/theme_mode_controller.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_app_info.dart';
import '../fakes/fake_external_link_opener.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';

final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _he = AppLocalizationsHe();

/// Pumps the real [SettingsScreen] over a real [SettingsController] backed
/// by [store].
Future<void> _pump(
  WidgetTester tester,
  FakeSettingsStore store, {
  bool bantoMode = true,
  bool backendConfigured = true,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>(
            create: (_) => SettingsController(store, FakeMenuRepository()),
          ),
          ChangeNotifierProvider<LocaleController>(
            create: (_) => LocaleController(FakeSettingsStore()),
          ),
          ChangeNotifierProvider<ThemeModeController>(
            create: (_) => ThemeModeController(FakeSettingsStore()),
          ),
        ],
        child: SettingsScreen(
          appInfo: FakeAppInfo(),
          externalLinkOpener: FakeExternalLinkOpener(),
          backendConfigured: backendConfigured,
          bantoMode: bantoMode,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('off by default, with the sentence saying what is sent', (
    tester,
  ) async {
    // Act
    await _pump(tester, FakeSettingsStore());

    // Assert
    final toggle = find.byKey(shareConfirmationsToggleKey);
    await tester.ensureVisible(toggle);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.text(_en.settingsShareConfirmations), findsOneWidget);
    expect(find.text(_en.settingsShareConfirmationsBody), findsOneWidget);
  });

  testWidgets('turning it on stores it and names it in the disclosure', (
    tester,
  ) async {
    // Arrange
    final store = FakeSettingsStore();
    await _pump(tester, store);

    // Act
    final toggle = find.byKey(shareConfirmationsToggleKey);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(consentDisclosureKey));
    await tester.tap(find.byKey(consentDisclosureKey));
    await tester.pumpAndSettle();

    // Assert: its own key, nothing else changed.
    final stored = await store.read();
    expect(stored.shareConfirmations, isTrue);
    expect(stored.estimationConsentGiven, isTrue);
    expect(stored.toJson()['shareConfirmations'], isTrue);
    expect(find.byKey(consentSharedNoteKey), findsOneWidget);
    expect(find.text(_en.whatLeavesDeviceSharedConfirmations), findsWidgets);

    // Act: off again.
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    // Assert: the key is gone, as a keto record has none.
    expect(
      (await store.read()).toJson().containsKey('shareConfirmations'),
      isFalse,
    );
    expect(find.byKey(consentSharedNoteKey), findsNothing);
  });

  testWidgets('in Hebrew', (tester) async {
    // Act
    await _pump(tester, FakeSettingsStore(), locale: const Locale('he'));

    // Assert
    await tester.ensureVisible(find.byKey(shareConfirmationsToggleKey));
    expect(find.text(_he.settingsShareConfirmations), findsOneWidget);
    expect(find.text(_he.settingsShareConfirmationsBody), findsOneWidget);
  });

  testWidgets('no toggle in a keto build or without a backend', (tester) async {
    await _pump(tester, FakeSettingsStore(), bantoMode: false);
    expect(
      find.byKey(shareConfirmationsToggleKey, skipOffstage: false),
      findsNothing,
    );

    await _pump(tester, FakeSettingsStore(), backendConfigured: false);
    expect(
      find.byKey(shareConfirmationsToggleKey, skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('the About privacy text names it while it is on', (tester) async {
    // Arrange
    await _pump(
      tester,
      FakeSettingsStore(initial: const AppSettings(shareConfirmations: true)),
    );

    // Act
    await tester.ensureVisible(find.byKey(aboutPrivacyKey));
    await tester.tap(find.byKey(aboutPrivacyKey));
    await tester.pumpAndSettle();

    // Assert
    expect(find.text(_en.whatLeavesDeviceSharedConfirmations), findsOneWidget);
  });
}
