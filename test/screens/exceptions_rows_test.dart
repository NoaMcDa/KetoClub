// Tapping a restriction row opens the exceptions sheet, in Settings' "My
// restrictions" and in the profile editor for another person (Banto, issue
// #417); the row then shows its exceptions in one muted line.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/screens/profile_editor_screen.dart';
import 'package:ketoclub/screens/settings_profiles_section.dart';
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/locale_controller.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/state/theme_mode_controller.dart';
import 'package:ketoclub/widgets/exceptions_sheet.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_app_info.dart';
import '../fakes/fake_external_link_opener.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';

final AppLocalizations _he = AppLocalizationsHe();

/// Pumps the Banto Settings screen over [store] in [locale].
Future<void> _pump(
  WidgetTester tester,
  FakeSettingsStore store, {
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
          bantoMode: true,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('Settings restriction rows', () {
    testWidgets('a row opens the sheet; saving writes the exceptions and '
        'the row shows them', (tester) async {
      // Arrange
      final store = FakeSettingsStore(
        initial: AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.treeNuts),
        ),
      );
      await _pump(tester, store);
      expect(find.textContaining('Except'), findsNothing);

      // Act
      await _tap(tester, find.byKey(restrictionRowKey(RestrictionId.treeNuts)));
      expect(find.byKey(exceptionsSheetKey), findsOneWidget);
      await _tap(tester, find.byKey(exceptionSuggestionKey('almond')));
      await _tap(tester, find.byKey(exceptionSuggestionKey('hazelnut')));
      await _tap(tester, find.byKey(exceptionsSaveKey));

      // Assert
      expect(find.byKey(exceptionsSheetKey), findsNothing);
      expect(find.text('Except almond, hazelnut'), findsOneWidget);
      expect(
        (await store.read()).profile
            .entryFor(RestrictionId.treeNuts)!
            .exceptions,
        <String>['almond', 'hazelnut'],
      );
    });

    testWidgets('dismissing the sheet changes nothing', (tester) async {
      // Arrange
      final store = FakeSettingsStore(
        initial: AppSettings(
          profile: DietaryProfile.empty.withEntry(
            RestrictionId.treeNuts,
            exceptions: <String>['almond'],
          ),
        ),
      );
      await _pump(tester, store);
      await _tap(tester, find.byKey(restrictionRowKey(RestrictionId.treeNuts)));

      // Act
      await tester.tap(find.byTooltip('Remove almond'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Except almond'), findsOneWidget);
      expect(
        (await store.read()).profile
            .entryFor(RestrictionId.treeNuts)!
            .exceptions,
        <String>['almond'],
      );
    });

    testWidgets('speaks Hebrew under a Hebrew UI', (tester) async {
      // Arrange
      final store = FakeSettingsStore(
        initial: AppSettings(
          profile: DietaryProfile.empty.withEntry(
            RestrictionId.treeNuts,
            exceptions: <String>['שקדים'],
          ),
        ),
      );
      await _pump(tester, store, locale: const Locale('he'));

      // Assert
      expect(find.text(_he.exceptionsRowLine('שקדים')), findsOneWidget);
    });
  });

  group('Profile editor restriction rows', () {
    testWidgets("a row sets another person's exceptions and leaves the "
        "user's own", (tester) async {
      // Arrange
      final store = FakeSettingsStore(
        initial: AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.treeNuts),
          otherProfiles: <NamedProfile>[
            NamedProfile(
              id: 'p1',
              name: 'Dana',
              profile: DietaryProfile.empty.withEntry(RestrictionId.treeNuts),
            ),
          ],
        ),
      );
      await _pump(tester, store);
      await _tap(tester, find.byKey(settingsProfileRowKey('p1')));
      expect(find.byType(ProfileEditorScreen), findsOneWidget);

      // Act
      await _tap(
        tester,
        find.byKey(profileEditorRowKey(RestrictionId.treeNuts)),
      );
      await tester.enterText(find.byKey(exceptionsFieldKey), 'cashew');
      await _tap(tester, find.byKey(exceptionsAddKey));
      await _tap(tester, find.byKey(exceptionsSaveKey));

      // Assert
      expect(find.text('Except cashew'), findsOneWidget);
      final saved = await store.read();
      expect(
        saved.otherProfiles.single.profile
            .entryFor(RestrictionId.treeNuts)!
            .exceptions,
        <String>['cashew'],
      );
      expect(
        saved.profile.entryFor(RestrictionId.treeNuts)!.exceptions,
        isEmpty,
      );
    });
  });
}
