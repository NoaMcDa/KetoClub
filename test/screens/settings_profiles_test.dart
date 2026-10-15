// Settings' "People on this device" group and the screens behind it
// (Banto; ALG-12, #354): add, rename, edit, share and delete a person,
// and import a shared profile only after saying it is health data.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/screens/profile_editor_screen.dart';
import 'package:ketoclub/screens/profile_import_screen.dart';
import 'package:ketoclub/screens/settings_profiles_section.dart';
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/locale_controller.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/state/theme_mode_controller.dart';
import 'package:ketoclub/utils/allergens/profile_transfer.dart';
import 'package:ketoclub/widgets/profile_name_dialog.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_app_info.dart';
import '../fakes/fake_external_link_opener.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_menu_sharer.dart';
import '../fakes/fake_settings_store.dart';

final AppLocalizations _en = AppLocalizationsEn();

/// Dana, holding milk.
final NamedProfile _dana = NamedProfile(
  id: 'p1',
  name: 'Dana',
  profile: DietaryProfile.empty.withEntry(RestrictionId.milk),
);

/// Pumps the Banto Settings screen over [store], sharing through [sharer].
Future<void> _pump(
  WidgetTester tester,
  FakeSettingsStore store, {
  FakeMenuSharer? sharer,
  bool bantoMode = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
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
          bantoMode: bantoMode,
          menuSharer: sharer,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Scrolls [finder] into view and taps it.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('Settings people group', () {
    testWidgets('is absent without bantoMode', (tester) async {
      // Act
      await _pump(tester, FakeSettingsStore(), bantoMode: false);

      // Assert
      expect(find.text(_en.settingsProfiles), findsNothing);
      expect(find.byKey(settingsProfilesAddKey), findsNothing);
    });

    testWidgets('lists "Me" and each person with their restrictions, and '
        'says it is health data', (tester) async {
      // Arrange
      final store = FakeSettingsStore(
        initial: AppSettings(otherProfiles: <NamedProfile>[_dana]),
      );

      // Act
      await _pump(tester, store);

      // Assert
      expect(find.text(_en.settingsProfiles), findsOneWidget);
      expect(find.text(_en.settingsProfilesNote), findsOneWidget);
      final me = find.byKey(settingsProfileRowKey(NamedProfile.primaryId));
      expect(
        find.descendant(of: me, matching: find.text(_en.profileDefaultName)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: me, matching: find.text(_en.profileKetoOnly)),
        findsOneWidget,
      );
      final dana = find.byKey(settingsProfileRowKey('p1'));
      expect(
        find.descendant(of: dana, matching: find.text('Dana')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dana, matching: find.text('Milk')),
        findsOneWidget,
      );
    });

    testWidgets('Add person asks for a name, then edits the new person', (
      tester,
    ) async {
      // Arrange
      final store = FakeSettingsStore();
      await _pump(tester, store);

      // Act: add Dana and give her milk.
      await _tap(tester, find.byKey(settingsProfilesAddKey));
      await tester.enterText(find.byKey(profileNameFieldKey), 'Dana');
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(profileNameSaveKey));
      expect(find.byType(ProfileEditorScreen), findsOneWidget);
      await _tap(tester, find.byKey(profileEditorAddKey));
      await _tap(tester, find.byKey(restrictionOptionKey(RestrictionId.milk)));

      // Assert
      expect(find.byKey(profileEditorRowKey(RestrictionId.milk)), findsOne);
      final stored = (await store.read()).otherProfiles.single;
      expect(stored.name, 'Dana');
      expect(stored.profile.contains(RestrictionId.milk), isTrue);
      expect((await store.read()).profile, DietaryProfile.empty);

      // Act: remove it again.
      await _tap(
        tester,
        find.byKey(profileEditorRemoveKey(RestrictionId.milk)),
      );

      // Assert
      expect(find.text(_en.profileKetoOnly), findsOneWidget);
      expect((await store.read()).otherProfiles.single.profile.isEmpty, isTrue);
    });

    testWidgets('a blank name cannot be saved', (tester) async {
      // Arrange
      await _pump(tester, FakeSettingsStore());

      // Act
      await _tap(tester, find.byKey(settingsProfilesAddKey));

      // Assert
      final save = tester.widget<FilledButton>(find.byKey(profileNameSaveKey));
      expect(save.onPressed, isNull);
    });

    testWidgets("the editor adds and removes a person's own word (ALG-17)", (
      tester,
    ) async {
      // Arrange
      final store = FakeSettingsStore(
        initial: AppSettings(otherProfiles: <NamedProfile>[_dana]),
      );
      await _pump(tester, store);
      await _tap(tester, find.byKey(settingsProfileRowKey('p1')));

      // Act
      await _tap(tester, find.byKey(profileEditorAddKey));
      final field = find.byKey(restrictionOwnFieldKey);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, 'kiwi');
      await _tap(tester, find.byKey(restrictionOwnAddKey));

      // Assert
      expect(find.byKey(profileEditorOwnTermRowKey('kiwi')), findsOneWidget);
      expect(
        (await store.read()).otherProfiles.single.profile.customTerms,
        <String>['kiwi'],
      );
      expect((await store.read()).profile, DietaryProfile.empty);

      // Act
      await _tap(tester, find.byKey(profileEditorOwnTermRemoveKey('kiwi')));

      // Assert
      expect(find.byKey(profileEditorOwnTermRowKey('kiwi')), findsNothing);
      expect(
        (await store.read()).otherProfiles.single.profile.customTerms,
        isEmpty,
      );
    });

    testWidgets('rename and delete a person', (tester) async {
      // Arrange
      final store = FakeSettingsStore(
        initial: AppSettings(
          otherProfiles: <NamedProfile>[_dana],
          activeProfileIds: const <String>['me', 'p1'],
        ),
      );
      await _pump(tester, store);
      await _tap(tester, find.byKey(settingsProfileRowKey('p1')));

      // Act: rename.
      await _tap(tester, find.byKey(profileEditorRenameKey));
      await tester.enterText(find.byKey(profileNameFieldKey), 'Dana (8)');
      await _tap(tester, find.byKey(profileNameSaveKey));

      // Assert
      expect(find.text('Dana (8)'), findsWidgets);
      expect((await store.read()).otherProfiles.single.name, 'Dana (8)');

      // Act: delete, confirming.
      await _tap(tester, find.byKey(profileEditorDeleteKey));
      expect(find.text(_en.profileDeleteTitle('Dana (8)')), findsOneWidget);
      await _tap(tester, find.byKey(profileDeleteConfirmKey));

      // Assert: back in Settings, Dana gone, the active set reset.
      expect(find.byType(ProfileEditorScreen), findsNothing);
      expect(find.byKey(settingsProfileRowKey('p1')), findsNothing);
      final read = await store.read();
      expect(read.otherProfiles, isEmpty);
      expect(read.activeProfileIds, AppSettings.defaultActiveProfileIds);
    });

    testWidgets("the user's own profile cannot be deleted", (tester) async {
      // Arrange
      await _pump(tester, FakeSettingsStore());

      // Act
      await _tap(
        tester,
        find.byKey(settingsProfileRowKey(NamedProfile.primaryId)),
      );

      // Assert
      expect(find.byType(ProfileEditorScreen), findsOneWidget);
      expect(find.byKey(profileEditorDeleteKey), findsNothing);
    });

    testWidgets('sharing says it is health data and shares only on yes', (
      tester,
    ) async {
      // Arrange
      final sharer = FakeMenuSharer();
      final store = FakeSettingsStore(
        initial: AppSettings(otherProfiles: <NamedProfile>[_dana]),
      );
      await _pump(tester, store, sharer: sharer);
      await _tap(tester, find.byKey(settingsProfileRowKey('p1')));

      // Act: cancel first.
      await _tap(tester, find.byKey(profileEditorExportKey));
      expect(find.text(_en.profileExportTitle), findsOneWidget);
      expect(find.text(_en.profileExportBody('Dana')), findsOneWidget);
      await _tap(tester, find.text(_en.actionCancel));

      // Assert
      expect(sharer.shareCalls, isEmpty);

      // Act: then agree.
      await _tap(tester, find.byKey(profileEditorExportKey));
      await _tap(tester, find.byKey(profileExportConfirmKey));

      // Assert
      final shared = ProfileTransfer.decode(sharer.shareCalls.single.text);
      expect(shared!.name, 'Dana');
      expect(shared.profile, _dana.profile);
    });

    testWidgets('with no share sheet, sharing copies the profile', (
      tester,
    ) async {
      // Arrange
      final store = FakeSettingsStore(
        initial: AppSettings(otherProfiles: <NamedProfile>[_dana]),
      );
      // The test host has no platform behind the clipboard; answer at once
      // and record what was copied.
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _pump(tester, store);
      await _tap(tester, find.byKey(settingsProfileRowKey('p1')));

      // Act
      await _tap(tester, find.byKey(profileEditorExportKey));
      await _tap(tester, find.byKey(profileExportConfirmKey));

      // Assert
      expect(find.text(_en.profileExportCopied), findsOneWidget);
      expect(ProfileTransfer.decode(copied!)!.profile, _dana.profile);
    });

    testWidgets('import says it is health data and saves only on Save', (
      tester,
    ) async {
      // Arrange
      final store = FakeSettingsStore();
      await _pump(tester, store);
      await _tap(tester, find.byKey(settingsProfilesImportKey));

      // Assert: the health-data wording comes first.
      expect(find.byType(ProfileImportScreen), findsOneWidget);
      expect(find.text(_en.profileImportBody), findsOneWidget);

      // Act: an unreadable paste.
      await tester.enterText(find.byKey(profileImportFieldKey), 'hello');
      await _tap(tester, find.byKey(profileImportReadKey));

      // Assert
      expect(find.byKey(profileImportInvalidKey), findsOneWidget);
      expect(find.byKey(profileImportSaveKey), findsNothing);

      // Act: a real one.
      await tester.enterText(
        find.byKey(profileImportFieldKey),
        ProfileTransfer.encode(name: 'Dana', profile: _dana.profile),
      );
      await _tap(tester, find.byKey(profileImportReadKey));

      // Assert: shown and asked about, nothing stored yet.
      expect(find.text(_en.profileImportAsk), findsOneWidget);
      expect(find.text('Milk'), findsOneWidget);
      expect((await store.read()).otherProfiles, isEmpty);

      // Act
      await _tap(tester, find.byKey(profileImportSaveKey));

      // Assert
      expect(find.byType(ProfileImportScreen), findsNothing);
      final stored = (await store.read()).otherProfiles.single;
      expect(stored.name, 'Dana');
      expect(stored.profile, _dana.profile);
      expect(find.byKey(settingsProfileRowKey(stored.id)), findsOneWidget);
    });

    testWidgets('an import with no name needs one before Save', (tester) async {
      // Arrange
      await _pump(tester, FakeSettingsStore());
      await _tap(tester, find.byKey(settingsProfilesImportKey));
      await tester.enterText(
        find.byKey(profileImportFieldKey),
        ProfileTransfer.encode(name: '', profile: _dana.profile),
      );
      await _tap(tester, find.byKey(profileImportReadKey));

      // Assert
      final save = find.byKey(profileImportSaveKey);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      // Act
      await tester.enterText(find.byKey(profileImportNameKey), 'Grandma');
      await tester.pumpAndSettle();

      // Assert
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    });
  });
}
