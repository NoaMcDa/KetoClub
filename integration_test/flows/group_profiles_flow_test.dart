// Flow test (FLOW_TEST_CONVENTIONS.md; Banto, ALG-12, issue #354): two
// profiles on one device, one with milk and one keto. The user picks milk
// on the first-run onboarding, adds Dana in Settings (no restriction, so
// keto), opens a menu and combines the two. A cheese omelette is avoid for
// the user and fits Dana, and the card shows the strictest — avoid — with
// both names; the header counts what fits everyone. The effect spans the
// onboarding, Settings, Explore and the menu, which is why this is a flow
// and not a widget test.
//
// The whole app is pumped with `bantoMode: true`, so it runs under
// `flutter test` with no `--dart-define`. The classifier answers every
// dish green from the language model; the states are derived on the
// device, once per person, and no profile is sent.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/app.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/menu_group.dart';
import 'package:ketoclub/screens/restriction_onboarding_screen.dart';
import 'package:ketoclub/screens/settings_profiles_section.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/widgets/group_breakdown_line.dart';
import 'package:ketoclub/widgets/group_combine_sheet.dart';
import 'package:ketoclub/widgets/profile_name_dialog.dart';
import 'package:ketoclub/widgets/status_badge.dart';
import 'package:ketoclub/widgets/verdict_counter_tiles.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Wolt venue page the user pastes.
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/banto-group-venue';

/// The [VenueRef] [_woltUrl] resolves to.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'banto-group-venue',
);

/// The cheese omelette: milk stated in the dish name.
const Dish _omelette = Dish(
  id: 'omelette',
  name: 'Cheese omelette',
  description: '',
  price: 48,
  options: <DishOption>[],
);

/// A tomato salad: nothing for either profile.
const Dish _salad = Dish(
  id: 'salad',
  name: 'Tomato salad',
  description: '',
  price: 32,
  options: <DishOption>[],
);

/// The menu the repository serves for [_ref].
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'Breakfast',
      dishes: <Dish>[_omelette, _salad],
    ),
  ],
);

/// Every dish green, from the language model.
final MenuAnalysed _analysis = MenuAnalysed(
  dishes: <AnalysedDish>[
    for (final dish in _menu.allDishes)
      AnalysedDish(
        dishId: dish.id,
        name: dish.name,
        verdict: DishVerdict.orderAsIs,
        why: 'Eggs and vegetables.',
      ),
  ],
  unclassified: const <String>[],
  engine: const LlmEngine(model: 'flow-model'),
  analysedAt: DateTime.utc(2026),
);

/// The counter tile labelled [label].
Finder _tile(String label) => find.descendant(
  of: find.byType(VerdictCounterTiles),
  matching: find.text(label.toUpperCase()),
);

/// Scrolls the first scrollable until [finder] is built, then taps it.
Future<void> _scrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tapAndSettle(tester, finder);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Banto group profiles flow', () {
    testWidgets('milk and keto: the cheese omelette is avoid for one, fits '
        'the other, and avoid is shown', (tester) async {
      // Setup
      final fakes = FakeAppDependencies();
      fakes.repository.stub(_ref, MenuFetched(menu: _menu));
      fakes.classifier.respondWith(_analysis);
      await tester.pumpWidget(
        KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
      );
      await tester.pumpAndSettle();

      // Act: the user's own profile holds milk.
      await _scrollAndTap(
        tester,
        find.byKey(restrictionOnboardingChipKey(RestrictionId.milk)),
      );
      await _scrollAndTap(tester, find.byKey(restrictionOnboardingContinueKey));

      // Act: in Settings, add Dana with no restriction (keto).
      await tapAndSettle(tester, navDestination(_en.navSettings));
      await _scrollAndTap(tester, find.byKey(settingsProfilesAddKey));
      await tester.enterText(find.byKey(profileNameFieldKey), 'Dana');
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.byKey(profileNameSaveKey));
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Act: on Explore, paste the link and open the venue.
      await tapAndSettle(tester, navDestination(_en.navExplore));
      await enterText(tester, _woltUrl);
      await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

      // Assert: read for the user alone; the omelette is hidden as avoid.
      expect(find.text(_en.menuProfileSummary('Me')), findsOneWidget);
      expect(find.byType(GroupBreakdownLine), findsNothing);

      // Act: combine Dana in.
      await tapAndSettle(tester, find.byKey(groupCombineControlKey));
      await tapAndSettle(tester, find.byKey(groupCombineOptionKey('p1')));
      await tapAndSettle(tester, find.byKey(groupCombineApplyKey));

      // Assert: read for both; the salad fits everyone.
      expect(find.text(_en.menuProfileSummary('Me, Dana')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(menuGroupFitsKey)).data,
        _en.groupFitsEveryoneStrict(1),
      );

      // Act: the Avoid tile reaches the omelette.
      await tapAndSettle(tester, _tile(_en.stateAvoidTile));

      // Assert: the strictest state, and whose it is.
      expect(find.text(_omelette.name), findsOneWidget);
      expect(find.text(_salad.name), findsNothing);
      expect(
        find.descendant(
          of: find.byType(StateBadge),
          matching: find.text(_en.stateAvoidBadge.toUpperCase()),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(find.byKey(groupBreakdownKey)).data,
        '${_en.groupBreakdownEntry('Me', _en.stateAvoidBadge)} · '
        '${_en.groupBreakdownEntry('Dana', _en.stateFitsBadge)}',
      );

      // Assert: one analysis for the menu, never one per person; combining
      // re-evaluated on the device.
      expect(fakes.classifier.calls, hasLength(1));
    });
  });
}
