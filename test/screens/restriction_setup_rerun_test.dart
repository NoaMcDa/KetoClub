// "Run the setup again" in Settings -> My restrictions (Banto, issue
// #421): it reopens the first-run "What do you avoid?" screen pre-filled
// with the current profile. Continue replaces the profile, with the free
// plan's gate for a second restriction; Skip leaves it unchanged. Every
// test passes `bantoMode` explicitly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/screens/paywall_screen.dart';
import 'package:ketoclub/screens/restriction_onboarding_screen.dart';
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/locale_controller.dart';
import 'package:ketoclub/state/premium_controller.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/state/theme_mode_controller.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_app_info.dart';
import '../fakes/fake_entitlement.dart';
import '../fakes/fake_external_link_opener.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';

final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _he = AppLocalizationsHe();

/// Pumps Settings over [store], with a [PremiumController] over [premium]
/// when given.
Future<void> _pump(
  WidgetTester tester,
  FakeSettingsStore store, {
  required bool bantoMode,
  Locale locale = const Locale('en'),
  FakeEntitlement? premium,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = premium == null
      ? null
      : PremiumController(premium, bantoMode: true);
  if (controller != null) addTearDown(controller.dispose);
  final app = MaterialApp(
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
  );
  // Above the navigator, as the app provides it, so a pushed route sees it.
  await tester.pumpWidget(
    controller == null
        ? app
        : ChangeNotifierProvider<PremiumController>.value(
            value: controller,
            child: app,
          ),
  );
  await tester.pumpAndSettle();
}

Future<void> _rerun(WidgetTester tester) async {
  final row = find.byKey(restrictionsRerunKey);
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

bool _chipSelected(WidgetTester tester, RestrictionId id) => tester
    .widget<FilterChip>(find.byKey(restrictionOnboardingChipKey(id)))
    .selected;

DietaryProfile _profileOf(List<RestrictionId> ids) =>
    ids.fold(DietaryProfile.empty, (profile, id) => profile.withEntry(id));

void main() {
  group('Run the setup again', () {
    testWidgets('is in My restrictions in a Banto build, for an empty '
        'profile too', (tester) async {
      await _pump(tester, FakeSettingsStore(), bantoMode: true);

      expect(find.byKey(restrictionsRerunKey), findsOneWidget);
      expect(find.text(_en.settingsRestrictionsRerun), findsOneWidget);
    });

    testWidgets('is labelled in Hebrew', (tester) async {
      await _pump(
        tester,
        FakeSettingsStore(),
        bantoMode: true,
        locale: const Locale('he'),
      );

      expect(find.text(_he.settingsRestrictionsRerun), findsOneWidget);
    });

    testWidgets('is absent from the KetoClub build', (tester) async {
      await _pump(tester, FakeSettingsStore(), bantoMode: false);

      expect(find.byKey(restrictionsRerunKey), findsNothing);
    });

    testWidgets('opens the onboarding with the current profile chosen', (
      tester,
    ) async {
      final store = FakeSettingsStore(
        initial: AppSettings(
          profile: _profileOf([RestrictionId.sesame, RestrictionId.lactose]),
          onboardingSeen: true,
        ),
      );
      await _pump(tester, store, bantoMode: true);

      await _rerun(tester);

      expect(find.text(_en.restrictionOnboardingTitle), findsOneWidget);
      expect(_chipSelected(tester, RestrictionId.sesame), isTrue);
      expect(_chipSelected(tester, RestrictionId.lactose), isTrue);
      expect(_chipSelected(tester, RestrictionId.peanuts), isFalse);
    });

    testWidgets('Continue replaces the profile, keeping the exceptions of '
        'what stays, the own words and the order', (tester) async {
      final store = FakeSettingsStore(
        initial: AppSettings(
          profile: DietaryProfile.empty
              .withEntry(RestrictionId.sesame, exceptions: ['tahini'])
              .withEntry(RestrictionId.lactose)
              .withCustomTerm('mango'),
          onboardingSeen: true,
          helperToolSeen: true,
        ),
      );
      await _pump(tester, store, bantoMode: true);
      await _rerun(tester);

      // Drop lactose, add peanuts.
      await _tap(
        tester,
        find.byKey(restrictionOnboardingChipKey(RestrictionId.lactose)),
      );
      await _tap(
        tester,
        find.byKey(restrictionOnboardingChipKey(RestrictionId.peanuts)),
      );
      await _tap(tester, find.byKey(restrictionOnboardingContinueKey));

      // Back on Settings, which shows the new profile.
      expect(find.byType(RestrictionOnboardingScreen), findsNothing);
      final saved = (await store.read()).profile;
      expect(saved.entries.map((entry) => entry.restrictionId), <RestrictionId>[
        RestrictionId.sesame,
        RestrictionId.custom,
        RestrictionId.peanuts,
      ]);
      expect(saved.entryFor(RestrictionId.sesame)!.exceptions, ['tahini']);
      expect(saved.customTerms, ['mango']);
      expect(
        find.byKey(restrictionRowKey(RestrictionId.peanuts)),
        findsOneWidget,
      );
      expect(
        find.byKey(restrictionRowKey(RestrictionId.lactose)),
        findsNothing,
      );
    });

    testWidgets('Skip leaves the profile exactly as it was', (tester) async {
      final profile = DietaryProfile.empty
          .withEntry(RestrictionId.sesame, exceptions: ['tahini'])
          .withEntry(RestrictionId.lactose);
      final store = FakeSettingsStore(
        initial: AppSettings(profile: profile, onboardingSeen: true),
      );
      await _pump(tester, store, bantoMode: true);
      await _rerun(tester);
      // A change made on the screen is not saved by Skip.
      await _tap(
        tester,
        find.byKey(restrictionOnboardingChipKey(RestrictionId.lactose)),
      );

      await _tap(tester, find.byKey(restrictionOnboardingSkipKey));

      expect(find.byType(RestrictionOnboardingScreen), findsNothing);
      expect((await store.read()).profile, profile);
    });

    testWidgets('Continue with nothing chosen empties the profile', (
      tester,
    ) async {
      final store = FakeSettingsStore(
        initial: AppSettings(
          profile: _profileOf([RestrictionId.sesame]),
          onboardingSeen: true,
        ),
      );
      await _pump(tester, store, bantoMode: true);
      await _rerun(tester);
      await _tap(
        tester,
        find.byKey(restrictionOnboardingChipKey(RestrictionId.sesame)),
      );

      await _tap(tester, find.byKey(restrictionOnboardingContinueKey));

      expect((await store.read()).profile.isEmpty, isTrue);
      expect(find.byKey(restrictionsEmptyKey), findsOneWidget);
    });

    testWidgets('the free plan still gates a second restriction: the '
        'paywall opens and, left, the chip stays unchosen', (tester) async {
      final store = FakeSettingsStore(
        initial: AppSettings(
          profile: _profileOf([RestrictionId.sesame]),
          onboardingSeen: true,
        ),
      );
      await _pump(tester, store, bantoMode: true, premium: FakeEntitlement());
      await _rerun(tester);

      await _tap(
        tester,
        find.byKey(restrictionOnboardingChipKey(RestrictionId.lactose)),
      );

      expect(find.byType(PaywallScreen), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      expect(_chipSelected(tester, RestrictionId.lactose), isFalse);
      // The restriction already saved stays chosen, and saved.
      expect(_chipSelected(tester, RestrictionId.sesame), isTrue);
      await _tap(tester, find.byKey(restrictionOnboardingContinueKey));
      expect((await store.read()).profile.contains(RestrictionId.sesame), true);
      expect(
        (await store.read()).profile.contains(RestrictionId.lactose),
        isFalse,
      );
    });
  });

  group('SettingsController.replaceRestrictions', () {
    test('is a no-op, with no write, when nothing would change', () async {
      final store = FakeSettingsStore(
        initial: AppSettings(profile: _profileOf([RestrictionId.sesame])),
      );
      final controller = SettingsController(store, FakeMenuRepository());
      await controller.load();

      await controller.replaceRestrictions([RestrictionId.sesame]);

      expect(store.writeCallCount, 0);
    });

    test('leaves keto and the own words alone, and ignores either in the '
        'list', () async {
      final store = FakeSettingsStore(
        initial: AppSettings(
          profile: DietaryProfile.empty
              .withEntry(RestrictionId.keto)
              .withEntry(RestrictionId.sesame)
              .withCustomTerm('mango'),
        ),
      );
      final controller = SettingsController(store, FakeMenuRepository());
      await controller.load();

      await controller.replaceRestrictions([
        RestrictionId.keto,
        RestrictionId.custom,
        RestrictionId.peanuts,
      ]);

      final saved = (await store.read()).profile;
      expect(saved.entries.map((entry) => entry.restrictionId), <Object>[
        RestrictionId.keto,
        RestrictionId.custom,
        RestrictionId.peanuts,
      ]);
      expect(saved.customTerms, ['mango']);
    });
  });
}
