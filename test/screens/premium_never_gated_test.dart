// What the free plan never gates (Banto, ALG-18, issue #360), each pinned
// for a person on the free plan who holds more than it allows — what a
// lapsed subscription leaves behind. Every saved restriction stays listed,
// evaluated on every menu and removable; the profile's chef card, a
// person's chef card, a trip's briefing and the helper copy all open; no
// paywall appears. Only adding is ever gated (premium_gating_test.dart);
// the waiter questions, the Waiter Card's chef card, the Why sheet and the
// post-meal check are walked in banto_premium_flow_test.dart, and
// premium_gate_usage_test.dart keeps Premium out of their code.

import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/app.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/trip_destination.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/chef_card_screen.dart';
import 'package:ketoclub/screens/menu_screen.dart';
import 'package:ketoclub/screens/paywall_screen.dart';
import 'package:ketoclub/screens/profile_editor_screen.dart';
import 'package:ketoclub/screens/settings_profiles_section.dart';
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/screens/settings_trip_section.dart';
import 'package:ketoclub/screens/trip_briefing_screen.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/widgets/helper_tool_sheet.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_app_dependencies.dart';
import '../fakes/fake_entitlement.dart';

final AppLocalizations _en = AppLocalizationsEn();

/// Three saved restrictions: two more than the free plan allows.
final DietaryProfile _three = DietaryProfile.empty
    .withEntry(RestrictionId.peanuts)
    .withEntry(RestrictionId.sesame)
    .withEntry(RestrictionId.milk);

/// A store that sells Premium to a person who does not hold it.
FakeEntitlement _lapsed() => FakeEntitlement();

Future<FakeAppDependencies> _pump(
  WidgetTester tester,
  AppSettings settings,
) async {
  final fakes = FakeAppDependencies()..entitlement = _lapsed();
  await fakes.settingsStore.write(settings.copyWith(onboardingSeen: true));
  await tester.pumpWidget(
    KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
  );
  await tester.pumpAndSettle();
  return fakes;
}

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

void main() {
  testWidgets('every saved restriction stays listed and removable, with the '
      'helper sentence', (tester) async {
    final fakes = await _pump(
      tester,
      AppSettings(profile: _three, helperToolSeen: true),
    );
    await _go(tester, settingsRoutePath);

    expect(find.text(_en.helperToolSentence), findsWidgets);
    for (final entry in _three.entries) {
      expect(
        find.byKey(restrictionRowKey(entry.restrictionId)),
        findsOneWidget,
      );
    }
    expect(find.byKey(restrictionsAddKey), findsOneWidget);

    await _tap(tester, find.byKey(restrictionRemoveKey(RestrictionId.milk)));

    expect(find.byType(PaywallScreen), findsNothing);
    final saved = (await fakes.settingsStore.read()).profile;
    expect(saved.contains(RestrictionId.milk), isFalse);
    expect(saved.contains(RestrictionId.peanuts), isTrue);
  });

  testWidgets("the profile's chef card carries every saved restriction", (
    tester,
  ) async {
    await _pump(tester, AppSettings(profile: _three, helperToolSeen: true));
    await _go(tester, settingsRoutePath);

    await _tap(tester, find.byKey(restrictionsChefCardKey));

    expect(find.byType(PaywallScreen), findsNothing);
    expect(find.byType(ChefCardScreen), findsOneWidget);
    for (final line in ChefCardText.compose(_three, hebrew: false)) {
      expect(find.text(line), findsOneWidget, reason: line);
    }
  });

  testWidgets('the helper copy still comes with a first restriction', (
    tester,
  ) async {
    await _pump(tester, const AppSettings());
    await _go(tester, settingsRoutePath);

    await _tap(tester, find.byKey(restrictionsAddKey));
    await _tap(tester, find.byKey(restrictionOptionKey(RestrictionId.eggs)));

    expect(find.byType(PaywallScreen), findsNothing);
    expect(find.byKey(helperToolSheetKey), findsOneWidget);
    expect(find.text(_en.helperToolTitle), findsOneWidget);
  });

  testWidgets('a person already saved keeps their editor, their entries and '
      'their chef card', (tester) async {
    final fakes = await _pump(
      tester,
      AppSettings(
        helperToolSeen: true,
        otherProfiles: <NamedProfile>[
          NamedProfile(id: 'p1', name: 'Dana', profile: _three),
        ],
      ),
    );
    await _go(tester, settingsRoutePath);

    await _tap(tester, find.byKey(settingsProfileRowKey('p1')));
    expect(find.byType(ProfileEditorScreen), findsOneWidget);
    for (final entry in _three.entries) {
      expect(
        find.byKey(profileEditorRowKey(entry.restrictionId)),
        findsOneWidget,
      );
    }
    await _tap(
      tester,
      find.byKey(profileEditorRemoveKey(RestrictionId.sesame)),
    );
    final dana = (await fakes.settingsStore.read()).otherProfiles.single;
    expect(dana.profile.contains(RestrictionId.sesame), isFalse);

    await _tap(tester, find.byKey(profileEditorChefCardKey));
    expect(find.byType(ChefCardScreen), findsOneWidget);
    expect(find.byType(PaywallScreen), findsNothing);
  });

  testWidgets('a trip already on keeps its briefing and turns off in one '
      'tap', (tester) async {
    final fakes = await _pump(
      tester,
      AppSettings(
        profile: _three,
        helperToolSeen: true,
        tripDestination: TripDestination.france,
      ),
    );
    await _go(tester, settingsRoutePath);

    await _tap(tester, find.byKey(settingsTripActiveKey));
    expect(find.byType(TripBriefingScreen), findsOneWidget);
    expect(find.byType(PaywallScreen), findsNothing);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    await _tap(tester, find.byKey(settingsTripOffKey));
    expect(find.byType(PaywallScreen), findsNothing);
    expect((await fakes.settingsStore.read()).tripDestination, isNull);
  });

  testWidgets('a menu is evaluated for every saved restriction', (
    tester,
  ) async {
    const ref = VenueRef(source: MenuSource.wolt, platformId: 'lapsed');
    Dish dish(String id, String name) => Dish(
      id: id,
      name: name,
      description: '',
      price: 40,
      options: const <DishOption>[],
    );
    final menu = Menu(
      venueRef: ref,
      currency: 'ILS',
      fetchedAt: DateTime.utc(2026),
      categories: <MenuCategory>[
        MenuCategory(
          id: 'c',
          name: 'Mains',
          dishes: <Dish>[
            dish('satay', 'Peanut satay'),
            dish('tahini', 'Tahini salad'),
            dish('cheese', 'Cheese plate'),
          ],
        ),
      ],
    );
    final fakes = FakeAppDependencies()..entitlement = _lapsed();
    fakes.repository.stub(ref, MenuFetched(menu: menu));
    fakes.classifier.respondWith(
      MenuAnalysed(
        dishes: <AnalysedDish>[
          for (final d in menu.allDishes)
            AnalysedDish(
              dishId: d.id,
              name: d.name,
              verdict: DishVerdict.orderAsIs,
              why: 'Fits',
            ),
        ],
        unclassified: const <String>[],
        engine: const LlmEngine(model: 'test-model'),
        analysedAt: DateTime.utc(2026),
      ),
    );
    await fakes.settingsStore.write(
      AppSettings(profile: _three, onboardingSeen: true, helperToolSeen: true),
    );
    await tester.pumpWidget(
      KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
    );
    await tester.pumpAndSettle();

    await _go(tester, '/venue/wolt/lapsed');

    final controller = Provider.of<MenuController>(
      tester.element(find.byType(MenuScreen)),
      listen: false,
    );
    expect(controller.profile, _three);
    final expected = <String, RestrictionId>{
      'satay': RestrictionId.peanuts,
      'tahini': RestrictionId.sesame,
      'cheese': RestrictionId.milk,
    };
    for (final MapEntry(key: id, value: restriction) in expected.entries) {
      final evaluated = controller.evaluationFor(id);
      expect(evaluated, isNotNull, reason: id);
      expect(
        evaluated!.concerns.map((c) => c.restrictionId),
        contains(restriction),
        reason: id,
      );
    }
    expect(find.byType(PaywallScreen), findsNothing);
  });
}
