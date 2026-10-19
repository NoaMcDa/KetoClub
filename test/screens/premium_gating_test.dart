// The free plan's gates on the screens that add (Banto, ALG-18, issue
// #360), over the whole app with a scripted store: a gate that trips opens
// the paywall instead of failing silently, and adds nothing until Premium
// is active; Premium, the web build (which sells nothing) and a KetoClub
// build pass straight through.

import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/app.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/paywall_screen.dart';
import 'package:ketoclub/screens/profile_editor_screen.dart';
import 'package:ketoclub/screens/profile_import_screen.dart';
import 'package:ketoclub/screens/restriction_onboarding_screen.dart';
import 'package:ketoclub/screens/scan_screen.dart';
import 'package:ketoclub/screens/settings_premium_section.dart';
import 'package:ketoclub/screens/settings_profiles_section.dart';
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/screens/settings_trip_section.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/platform/entitlement.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/utils/premium_gates.dart';
import 'package:ketoclub/widgets/group_combine_sheet.dart';
import 'package:ketoclub/widgets/profile_name_dialog.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';

import '../fakes/fake_app_dependencies.dart';
import '../fakes/fake_entitlement.dart';

final AppLocalizations _en = AppLocalizationsEn();

final DietaryProfile _peanuts = DietaryProfile.empty.withEntry(
  RestrictionId.peanuts,
);

/// Pumps the Banto app over [fakes] with [settings] saved (past the
/// onboarding unless [onboarding]) and [entitlement] as the store.
Future<void> _pump(
  WidgetTester tester,
  FakeAppDependencies fakes, {
  required Entitlement entitlement,
  AppSettings settings = const AppSettings(),
  bool onboarding = false,
  bool bantoMode = true,
}) async {
  fakes.entitlement = entitlement;
  await fakes.settingsStore.write(
    settings.copyWith(onboardingSeen: !onboarding, helperToolSeen: true),
  );
  await tester.pumpWidget(
    KetoClubApp(dependencies: fakes.dependencies, bantoMode: bantoMode),
  );
  await tester.pumpAndSettle();
}

/// Replaces the route stack with [path].
Future<void> _go(WidgetTester tester, String path) async {
  tester
      .state<NavigatorState>(find.byType(Navigator).first)
      .pushReplacementNamed(path);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Settings, "Add restriction", then [id] in the picker.
Future<void> _addInSettings(WidgetTester tester, RestrictionId id) async {
  await _go(tester, settingsRoutePath);
  await _tap(tester, find.byKey(restrictionsAddKey));
  await _tap(tester, find.byKey(restrictionOptionKey(id)));
}

/// Leaves the paywall without buying.
Future<void> _leavePaywall(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await tester.pumpAndSettle();
}

Future<DietaryProfile> _saved(FakeAppDependencies fakes) async =>
    (await fakes.settingsStore.read()).profile;

void main() {
  group('a second restriction', () {
    testWidgets('on the free plan opens the paywall and adds nothing until '
        'Premium', (tester) async {
      final fakes = FakeAppDependencies();
      final store = FakeEntitlement();
      await _pump(
        tester,
        fakes,
        entitlement: store,
        settings: AppSettings(profile: _peanuts),
      );

      await _addInSettings(tester, RestrictionId.sesame);

      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.text(_en.paywallReasonRestrictions), findsOneWidget);
      expect(store.calls, contains(EntitlementCall.refresh));

      await _leavePaywall(tester);
      expect(find.byType(PaywallScreen), findsNothing);
      expect((await _saved(fakes)).contains(RestrictionId.sesame), isFalse);
      expect(find.byKey(restrictionRowKey(RestrictionId.sesame)), findsNothing);
    });

    testWidgets('the first one is free: no paywall', (tester) async {
      final fakes = FakeAppDependencies();
      await _pump(tester, fakes, entitlement: FakeEntitlement());

      await _addInSettings(tester, RestrictionId.peanuts);

      expect(find.byType(PaywallScreen), findsNothing);
      expect((await _saved(fakes)).contains(RestrictionId.peanuts), isTrue);
    });

    testWidgets('with Premium it is added at once', (tester) async {
      final fakes = FakeAppDependencies();
      await _pump(
        tester,
        fakes,
        entitlement: FakeEntitlement(premium: true),
        settings: AppSettings(profile: _peanuts),
      );

      await _addInSettings(tester, RestrictionId.sesame);

      expect(find.byType(PaywallScreen), findsNothing);
      expect((await _saved(fakes)).contains(RestrictionId.sesame), isTrue);
    });

    testWidgets('on web, which sells nothing, it is added at once and '
        'Settings has no Premium section', (tester) async {
      final fakes = FakeAppDependencies();
      await _pump(
        tester,
        fakes,
        entitlement: const NullEntitlement(),
        settings: AppSettings(profile: _peanuts),
      );

      await _addInSettings(tester, RestrictionId.sesame);

      expect(find.byType(PaywallScreen), findsNothing);
      expect((await _saved(fakes)).contains(RestrictionId.sesame), isTrue);
      expect(find.byKey(settingsPremiumRowKey), findsNothing);
    });

    testWidgets('in a KetoClub build nothing is sold or shown', (tester) async {
      final fakes = FakeAppDependencies();
      await _pump(
        tester,
        fakes,
        entitlement: FakeEntitlement(),
        bantoMode: false,
      );
      await _go(tester, settingsRoutePath);

      expect(find.byKey(settingsPremiumRowKey), findsNothing);
      expect(find.text(_en.premiumTitle), findsNothing);
    });

    testWidgets('on the onboarding, a second chip opens the paywall and '
        'stays unchosen without Premium', (tester) async {
      final fakes = FakeAppDependencies();
      await _pump(
        tester,
        fakes,
        entitlement: FakeEntitlement(),
        onboarding: true,
      );

      await _tap(
        tester,
        find.byKey(restrictionOnboardingChipKey(RestrictionId.peanuts)),
      );
      expect(find.byType(PaywallScreen), findsNothing);
      await _tap(
        tester,
        find.byKey(restrictionOnboardingChipKey(RestrictionId.sesame)),
      );
      expect(find.byType(PaywallScreen), findsOneWidget);

      await _leavePaywall(tester);
      final chip = tester.widget<FilterChip>(
        find.byKey(restrictionOnboardingChipKey(RestrictionId.sesame)),
      );
      expect(chip.selected, isFalse);
    });

    testWidgets('for another person, a second restriction opens the '
        'paywall', (tester) async {
      final fakes = FakeAppDependencies();
      await _pump(
        tester,
        fakes,
        entitlement: FakeEntitlement(),
        settings: AppSettings(
          otherProfiles: <NamedProfile>[
            NamedProfile(id: 'p1', name: 'Dana', profile: _peanuts),
          ],
        ),
      );
      await _go(tester, settingsRoutePath);
      await _tap(tester, find.byKey(settingsProfileRowKey('p1')));
      await _tap(tester, find.byKey(profileEditorAddKey));
      await _tap(tester, find.byKey(restrictionOptionKey(RestrictionId.soy)));

      expect(find.byType(PaywallScreen), findsOneWidget);
      await _leavePaywall(tester);
      final dana = (await fakes.settingsStore.read()).otherProfiles.single;
      expect(dana.profile.contains(RestrictionId.soy), isFalse);
    });
  });

  group('group profiles', () {
    testWidgets('adding a person opens the paywall; after a purchase the '
        'name is asked', (tester) async {
      final fakes = FakeAppDependencies();
      await _pump(tester, fakes, entitlement: FakeEntitlement());
      await _go(tester, settingsRoutePath);

      await _tap(tester, find.byKey(settingsProfilesAddKey));
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.text(_en.paywallReasonGroup), findsOneWidget);

      await _tap(tester, find.byKey(paywallBuyKey));
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.byKey(profileNameFieldKey), findsOneWidget);
    });

    testWidgets('importing a person opens the paywall', (tester) async {
      final fakes = FakeAppDependencies();
      await _pump(tester, fakes, entitlement: FakeEntitlement());
      await _go(tester, settingsRoutePath);

      await _tap(tester, find.byKey(settingsProfilesImportKey));
      expect(find.byType(PaywallScreen), findsOneWidget);
      await _leavePaywall(tester);
      expect(find.byType(ProfileImportScreen), findsNothing);
    });

    group('checking several people on a menu', () {
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'group');
      final menu = Menu(
        venueRef: ref,
        currency: 'ILS',
        fetchedAt: DateTime.utc(2026),
        categories: const <MenuCategory>[
          MenuCategory(
            id: 'c',
            name: 'Mains',
            dishes: <Dish>[
              Dish(
                id: 'd',
                name: 'Steak',
                description: '',
                price: 80,
                options: <DishOption>[],
              ),
            ],
          ),
        ],
      );

      Future<void> openMenu(
        WidgetTester tester,
        FakeAppDependencies fakes,
      ) async {
        fakes.repository.stub(ref, MenuFetched(menu: menu));
        await _go(tester, '/venue/wolt/group');
      }

      testWidgets('checking a second person opens the paywall and keeps the '
          'saved choice', (tester) async {
        final fakes = FakeAppDependencies();
        await _pump(
          tester,
          fakes,
          entitlement: FakeEntitlement(),
          settings: AppSettings(
            profile: _peanuts,
            otherProfiles: <NamedProfile>[
              NamedProfile(id: 'p1', name: 'Dana', profile: _peanuts),
            ],
          ),
        );
        await openMenu(tester, fakes);

        await _tap(tester, find.byKey(groupCombineControlKey));
        await _tap(tester, find.byKey(groupCombineOptionKey('p1')));
        await _tap(tester, find.byKey(groupCombineApplyKey));

        expect(find.byType(PaywallScreen), findsOneWidget);
        await _leavePaywall(tester);
        expect(
          (await fakes.settingsStore.read()).activeProfileIds,
          AppSettings.defaultActiveProfileIds,
        );
      });

      testWidgets('a group already saved is applied again with no '
          'paywall', (tester) async {
        final fakes = FakeAppDependencies();
        await _pump(
          tester,
          fakes,
          entitlement: FakeEntitlement(),
          settings: AppSettings(
            profile: _peanuts,
            otherProfiles: <NamedProfile>[
              NamedProfile(id: 'p1', name: 'Dana', profile: _peanuts),
            ],
            activeProfileIds: const <String>['me', 'p1'],
          ),
        );
        await openMenu(tester, fakes);

        await _tap(tester, find.byKey(groupCombineControlKey));
        await _tap(tester, find.byKey(groupCombineApplyKey));

        expect(find.byType(PaywallScreen), findsNothing);
        expect((await fakes.settingsStore.read()).activeProfileIds, <String>[
          'me',
          'p1',
        ]);
      });
    });
  });

  group('trip mode', () {
    testWidgets('picking a destination opens the paywall', (tester) async {
      final fakes = FakeAppDependencies();
      await _pump(tester, fakes, entitlement: FakeEntitlement());
      await _go(tester, settingsRoutePath);

      await _tap(tester, find.byKey(settingsTripPickKey));
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.text(_en.paywallReasonTrip), findsOneWidget);
      await _leavePaywall(tester);
      expect(find.text(_en.tripPickerTitle), findsNothing);
      expect((await fakes.settingsStore.read()).tripDestination, isNull);
    });

    testWidgets('with Premium the destination picker opens', (tester) async {
      final fakes = FakeAppDependencies();
      await _pump(tester, fakes, entitlement: FakeEntitlement(premium: true));
      await _go(tester, settingsRoutePath);

      await _tap(tester, find.byKey(settingsTripPickKey));
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.text(_en.tripPickerTitle), findsOneWidget);
    });
  });

  group('scans', () {
    Future<void> paste(WidgetTester tester) async {
      await _go(tester, scanRoutePath);
      await _tap(tester, find.text(_en.scanScreenModePaste));
      await tester.enterText(find.byType(TextField), 'Steak\nSalad');
      await tester.pumpAndSettle();
    }

    testWidgets("past the month's free count, Analyse opens the paywall and "
        'reads nothing', (tester) async {
      final fakes = FakeAppDependencies(startedAt: DateTime.utc(2026, 10, 5));
      await _pump(
        tester,
        fakes,
        entitlement: FakeEntitlement(),
        settings: const AppSettings(
          scanMonth: '2026-10',
          scanCount: freeScansPerMonth,
        ),
      );
      await paste(tester);
      expect(find.text(_en.scanFreeScansLeft(0, freeScansPerMonth)), findsOne);

      await _tap(tester, find.text(_en.scanAnalyse));

      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(
        find.text(_en.paywallReasonScans(freeScansPerMonth)),
        findsOneWidget,
      );
      await _leavePaywall(tester);
      expect(find.byType(ScanScreen), findsOneWidget);
      expect((await fakes.settingsStore.read()).scanCount, freeScansPerMonth);
    });

    testWidgets('within the count, the scan is read and counted', (
      tester,
    ) async {
      final fakes = FakeAppDependencies(startedAt: DateTime.utc(2026, 10, 5));
      await _pump(
        tester,
        fakes,
        entitlement: FakeEntitlement(),
        settings: const AppSettings(scanMonth: '2026-10', scanCount: 4),
      );
      await paste(tester);
      expect(find.text(_en.scanFreeScansLeft(1, freeScansPerMonth)), findsOne);

      await _tap(tester, find.text(_en.scanAnalyse));

      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.byType(ScanScreen), findsNothing);
      expect((await fakes.settingsStore.read()).scanCount, 5);
    });

    testWidgets("last month's count does not carry over", (tester) async {
      final fakes = FakeAppDependencies(startedAt: DateTime.utc(2026, 11, 2));
      await _pump(
        tester,
        fakes,
        entitlement: FakeEntitlement(),
        settings: const AppSettings(scanMonth: '2026-10', scanCount: 9),
      );
      await paste(tester);
      expect(
        find.text(_en.scanFreeScansLeft(freeScansPerMonth, freeScansPerMonth)),
        findsOne,
      );
      await _tap(tester, find.text(_en.scanAnalyse));
      expect(find.byType(PaywallScreen), findsNothing);
    });

    testWidgets('with Premium, or on web, there is no count and no '
        'paywall', (tester) async {
      for (final entitlement in <Entitlement>[
        FakeEntitlement(premium: true),
        const NullEntitlement(),
      ]) {
        final fakes = FakeAppDependencies(startedAt: DateTime.utc(2026, 10, 5));
        await _pump(
          tester,
          fakes,
          entitlement: entitlement,
          settings: const AppSettings(scanMonth: '2026-10', scanCount: 50),
        );
        await paste(tester);
        expect(find.byKey(scanFreeScansLeftKey), findsNothing);
        await _tap(tester, find.text(_en.scanAnalyse));
        expect(find.byType(PaywallScreen), findsNothing);
        expect(find.byType(ScanScreen), findsNothing);
      }
    });
  });

  group('the Settings row', () {
    testWidgets('shows the plan and restores', (tester) async {
      final fakes = FakeAppDependencies();
      final store = FakeEntitlement()..queueRestore(const PremiumActive());
      await _pump(tester, fakes, entitlement: store);
      await _go(tester, settingsRoutePath);

      expect(
        find.text(_en.settingsPremiumFree(freeScansPerMonth)),
        findsOneWidget,
      );
      await _tap(tester, find.byKey(settingsPremiumRestoreKey));
      expect(find.text(_en.settingsPremiumActive), findsOneWidget);
      expect(find.text(_en.paywallActive), findsOneWidget);

      await _tap(tester, find.byKey(settingsPremiumRowKey));
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.byKey(paywallReasonKey), findsNothing);
    });
  });

  group("the profile editor gate reads that person's profile", () {
    testWidgets('an empty person takes a first restriction freely', (
      tester,
    ) async {
      final fakes = FakeAppDependencies();
      await _pump(
        tester,
        fakes,
        entitlement: FakeEntitlement(),
        settings: AppSettings(
          profile: _peanuts,
          otherProfiles: const <NamedProfile>[
            NamedProfile(id: 'p1', name: 'Dana'),
          ],
        ),
      );
      await _go(tester, settingsRoutePath);
      await _tap(tester, find.byKey(settingsProfileRowKey('p1')));
      expect(find.byType(ProfileEditorScreen), findsOneWidget);
      await _tap(tester, find.byKey(profileEditorAddKey));
      await _tap(tester, find.byKey(restrictionOptionKey(RestrictionId.soy)));

      expect(find.byType(PaywallScreen), findsNothing);
      final dana = (await fakes.settingsStore.read()).otherProfiles.single;
      expect(dana.profile.contains(RestrictionId.soy), isTrue);
    });
  });
}
