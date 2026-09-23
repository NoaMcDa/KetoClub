// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §18.4; issue #58):
// choosing Dark in the Appearance section actually re-themes the app, not
// only the persisted value. Unlike the language section's own flow
// coverage (exercised via `settings_screen_test.dart` and
// `tab_navigation_flow_test.dart`), this is worth a dedicated flow test
// because the effect lives one layer up, in `KetoClubApp`'s own
// `ThemeModeController` — a widget test over `SettingsScreen` alone
// cannot see `MaterialApp.themeMode` change.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/screens/settings_screen.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// The `find.text` match for [label], scoped to the appearance section's
/// own radio group (`settings_screen.dart`'s `appearanceRadioGroupKey`),
/// so a label the language and appearance sections happen to share can
/// never make this finder ambiguous.
Finder _appearanceOption(String label) => find.descendant(
  of: find.byKey(appearanceRadioGroupKey),
  matching: find.text(label),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Appearance flow', () {
    testWidgets('choosing Dark in Settings re-themes the running app to dark', (
      tester,
    ) async {
      // Setup: the app on top of in-memory fakes, starting in the
      // default (system) appearance.
      final fakes = FakeAppDependencies();
      await pumpApp(tester, fakes);

      // Act: go to Settings and choose Dark.
      await tapAndSettle(tester, navDestination(_en.navSettings));
      final dark = _appearanceOption(_en.settingsAppearanceDark);
      await tester.ensureVisible(dark);
      await tapAndSettle(tester, dark);

      // Assert: the running app itself is dark now, read from a screen
      // widget still on the tree — the Settings screen the user is
      // looking at, not a controller reached from the side.
      final afterContext = tester.element(find.byType(SettingsScreen));
      expect(Theme.of(afterContext).brightness, Brightness.dark);
    });

    testWidgets(
      'choosing Dark persists it, so the choice survives a fresh launch',
      (tester) async {
        // Setup
        final fakes = FakeAppDependencies();
        await pumpApp(tester, fakes);

        // Act: choose Dark, then rebuild the app fresh over the same
        // (now-written) settings store — simulating a relaunch, since
        // `KetoClubApp`'s `ThemeModeController` reads the store anew in
        // its own `initState`.
        await tapAndSettle(tester, navDestination(_en.navSettings));
        final dark = _appearanceOption(_en.settingsAppearanceDark);
        await tester.ensureVisible(dark);
        await tapAndSettle(tester, dark);
        await pumpApp(tester, fakes);

        // Assert: the relaunched app opens dark, before the user touches
        // anything — read from the Settings screen once reached again,
        // the same as above.
        await tapAndSettle(tester, navDestination(_en.navSettings));
        final context = tester.element(find.byType(SettingsScreen));
        expect(Theme.of(context).brightness, Brightness.dark);
      },
    );
  });
}
