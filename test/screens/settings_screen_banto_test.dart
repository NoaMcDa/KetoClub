// The "My restrictions" section of the Settings screen (Banto, ALG-02a,
// issue #344), built only with `bantoMode: true` (architecture.md D26).
// Every other Settings test pumps the screen with the build's default flag,
// off under plain `flutter test`, so they pin the KetoClub screen; this file
// pins both branches explicitly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/screens/chef_card_screen.dart';
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/locale_controller.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/state/theme_mode_controller.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_app_info.dart';
import '../fakes/fake_external_link_opener.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';

final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _he = AppLocalizationsHe();

/// Pumps the real [SettingsScreen] over a real [SettingsController] backed
/// by [store], with [bantoMode] passed explicitly, and lets the post-frame
/// load settle.
Future<void> _pump(
  WidgetTester tester,
  FakeSettingsStore store, {
  required bool bantoMode,
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
          bantoMode: bantoMode,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the picker from the section's "Add restriction" button.
Future<void> _openPicker(WidgetTester tester) async {
  final add = find.byKey(restrictionsAddKey);
  await tester.ensureVisible(add);
  await tester.tap(add);
  await tester.pumpAndSettle();
}

/// Opens the picker and taps [id]'s row.
Future<void> _pick(WidgetTester tester, RestrictionId id) async {
  await _openPicker(tester);
  final option = find.byKey(restrictionOptionKey(id));
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pumpAndSettle();
}

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

void main() {
  group('SettingsScreen with bantoMode: false', () {
    testWidgets('has no "My restrictions" section; appearance is still '
        'followed by the keto rules', (tester) async {
      // Act
      await _pump(tester, FakeSettingsStore(), bantoMode: false);

      // Assert
      expect(find.text(_en.settingsRestrictions), findsNothing);
      expect(find.text(_en.helperToolSentence), findsNothing);
      expect(find.byKey(restrictionsAddKey), findsNothing);
      expect(find.byKey(restrictionsEmptyKey), findsNothing);
      expect(
        _top(tester, find.text(_en.settingsAppearance)),
        lessThan(_top(tester, find.text(_en.settingsKetoRules))),
      );
    });

    testWidgets('shows nothing of a stored profile', (tester) async {
      // Arrange
      final store = FakeSettingsStore(
        initial: AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
        ),
      );

      // Act
      await _pump(tester, store, bantoMode: false);

      // Assert
      expect(find.text('Sesame'), findsNothing);
      expect(find.byKey(restrictionRowKey(RestrictionId.sesame)), findsNothing);
    });

    testWidgets('has no chef card button, even with a stored profile', (
      tester,
    ) async {
      // Arrange
      final store = FakeSettingsStore(
        initial: AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
        ),
      );

      // Act
      await _pump(tester, store, bantoMode: false);

      // Assert
      expect(find.byKey(restrictionsChefCardKey), findsNothing);
      expect(find.text(_en.chefCardShowButton), findsNothing);
    });
  });

  group('SettingsScreen with bantoMode: true', () {
    testWidgets('has no chef card button while the profile is empty', (
      tester,
    ) async {
      // Act
      await _pump(tester, FakeSettingsStore(), bantoMode: true);

      // Assert
      expect(find.byKey(restrictionsChefCardKey), findsNothing);
      expect(find.text(_en.chefCardShowButton), findsNothing);
    });

    testWidgets('the chef card button opens the card for the stored '
        'profile', (tester) async {
      // Arrange
      final store = FakeSettingsStore(
        initial: AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
        ),
      );
      await _pump(tester, store, bantoMode: true);
      final button = find.byKey(restrictionsChefCardKey);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(find.text(_en.chefCardShowButton), findsOneWidget);

      // Act
      await tester.tap(button);
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(ChefCardScreen), findsOneWidget);
      final line = ChefCardText.compose(
        DietaryProfile.empty.withEntry(RestrictionId.sesame),
        hebrew: false,
      )[1];
      expect(find.text(line), findsOneWidget);
    });

    testWidgets('removing the last restriction removes the button', (
      tester,
    ) async {
      // Arrange
      final store = FakeSettingsStore(
        initial: AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
        ),
      );
      await _pump(tester, store, bantoMode: true);
      final remove = find.byKey(restrictionRemoveKey(RestrictionId.sesame));
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();

      // Act
      await tester.tap(remove);
      await tester.pumpAndSettle();

      // Assert
      expect(find.byKey(restrictionsChefCardKey), findsNothing);
    });

    testWidgets('shows the section between appearance and the keto rules, '
        'with the helper sentence and the empty state', (tester) async {
      // Act
      await _pump(tester, FakeSettingsStore(), bantoMode: true);

      // Assert
      final label = find.text(_en.settingsRestrictions);
      expect(label, findsOneWidget);
      expect(find.text(_en.helperToolSentence), findsOneWidget);
      expect(find.text(_en.settingsRestrictionsEmpty), findsOneWidget);
      expect(find.text(_en.settingsRestrictionsAdd), findsOneWidget);
      expect(
        _top(tester, find.text(_en.settingsAppearance)),
        lessThan(_top(tester, label)),
      );
      expect(
        _top(tester, label),
        lessThan(_top(tester, find.text(_en.settingsKetoRules))),
      );
      // The keto rules stay as they were.
      expect(find.byKey(seedOilFreeSwitchKey), findsOneWidget);
    });

    testWidgets('the picker opens and keto is not in it', (tester) async {
      // Arrange
      await _pump(tester, FakeSettingsStore(), bantoMode: true);

      // Act
      await _openPicker(tester);

      // Assert
      expect(find.byType(RestrictionPickerSheet), findsOneWidget);
      expect(find.text(_en.restrictionPickerTitle), findsOneWidget);
      expect(
        find.byKey(restrictionOptionKey(RestrictionId.sesame)),
        findsOneWidget,
      );
      expect(
        find.byKey(restrictionOptionKey(RestrictionId.keto)),
        findsNothing,
      );
      expect(find.text('Keto'), findsNothing);
    });

    testWidgets('picking sesame adds an English row and stores it', (
      tester,
    ) async {
      // Arrange
      final store = FakeSettingsStore();
      await _pump(tester, store, bantoMode: true);

      // Act
      await _pick(tester, RestrictionId.sesame);

      // Assert
      final row = find.byKey(restrictionRowKey(RestrictionId.sesame));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('Sesame')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text(_en.restrictionKindAllergy),
        ),
        findsOneWidget,
      );
      expect(find.byKey(restrictionsEmptyKey), findsNothing);
      expect(
        (await store.read()).profile,
        DietaryProfile.empty.withEntry(RestrictionId.sesame),
      );
    });

    testWidgets('an added restriction is left out of the picker', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, FakeSettingsStore(), bantoMode: true);
      await _pick(tester, RestrictionId.sesame);

      // Act
      await _openPicker(tester);

      // Assert
      expect(
        find.byKey(restrictionOptionKey(RestrictionId.sesame)),
        findsNothing,
      );
      expect(
        find.byKey(restrictionOptionKey(RestrictionId.milk)),
        findsOneWidget,
      );
    });

    testWidgets('under Locale(he) picking sesame adds a Hebrew row, right '
        'to left', (tester) async {
      // Arrange
      await _pump(
        tester,
        FakeSettingsStore(),
        bantoMode: true,
        locale: const Locale('he'),
      );

      // Act
      await _pick(tester, RestrictionId.sesame);

      // Assert
      final row = find.byKey(restrictionRowKey(RestrictionId.sesame));
      expect(
        find.descendant(of: row, matching: find.text('שומשום')),
        findsOneWidget,
      );
      expect(find.text('Sesame'), findsNothing);
      expect(
        find.descendant(
          of: row,
          matching: find.text(_he.restrictionKindAllergy),
        ),
        findsOneWidget,
      );
      expect(find.text(_he.settingsRestrictions), findsOneWidget);
      expect(find.text(_he.helperToolSentence), findsOneWidget);
      final context = tester.element(row);
      expect(Directionality.of(context), TextDirection.rtl);
      // Mirrored: the remove button sits at the row's left edge under RTL.
      final remove = tester.getCenter(
        find.byKey(restrictionRemoveKey(RestrictionId.sesame)),
      );
      final name = tester.getCenter(find.text('שומשום'));
      expect(remove.dx, lessThan(name.dx));
      expect(tester.takeException(), isNull);
    });

    testWidgets('remove deletes the row and the stored entry', (tester) async {
      // Arrange
      final store = FakeSettingsStore(
        initial: AppSettings(
          profile: DietaryProfile.empty
              .withEntry(RestrictionId.sesame)
              .withEntry(RestrictionId.gluten),
        ),
      );
      await _pump(tester, store, bantoMode: true);
      expect(
        find.byKey(restrictionRowKey(RestrictionId.gluten)),
        findsOneWidget,
      );

      // Act
      await tester.tap(find.byKey(restrictionRemoveKey(RestrictionId.sesame)));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byKey(restrictionRowKey(RestrictionId.sesame)), findsNothing);
      expect(
        find.byKey(restrictionRowKey(RestrictionId.gluten)),
        findsOneWidget,
      );
      expect(
        (await store.read()).profile,
        DietaryProfile.empty.withEntry(RestrictionId.gluten),
      );
    });

    testWidgets('removing the last restriction brings back the empty state', (
      tester,
    ) async {
      // Arrange
      final store = FakeSettingsStore(
        initial: AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.vegan),
        ),
      );
      await _pump(tester, store, bantoMode: true);
      expect(find.byKey(restrictionsEmptyKey), findsNothing);

      // Act
      await tester.tap(find.byKey(restrictionRemoveKey(RestrictionId.vegan)));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byKey(restrictionsEmptyKey), findsOneWidget);
    });

    testWidgets('the remove button is labelled with the restriction', (
      tester,
    ) async {
      // Arrange
      final store = FakeSettingsStore(
        initial: AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.lactose),
        ),
      );

      // Act
      await _pump(tester, store, bantoMode: true);

      // Assert
      expect(
        find.byTooltip(_en.settingsRestrictionsRemove('Lactose')),
        findsOneWidget,
      );
      expect(find.text(_en.restrictionKindIntolerance), findsOneWidget);
    });

    testWidgets('dismissing the picker adds nothing', (tester) async {
      // Arrange
      final store = FakeSettingsStore();
      await _pump(tester, store, bantoMode: true);
      await _openPicker(tester);

      // Act: tap the barrier above the sheet.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(RestrictionPickerSheet), findsNothing);
      expect((await store.read()).profile, DietaryProfile.empty);
      expect(store.writeCallCount, 0);
    });

    testWidgets('the add button is gone once every restriction is added', (
      tester,
    ) async {
      // Arrange
      var profile = DietaryProfile.empty;
      for (final id in RestrictionId.values) {
        if (id != RestrictionId.keto) profile = profile.withEntry(id);
      }
      final store = FakeSettingsStore(initial: AppSettings(profile: profile));

      // Act
      await _pump(tester, store, bantoMode: true);

      // Assert
      expect(find.byKey(restrictionsAddKey), findsNothing);
    });
  });
}
