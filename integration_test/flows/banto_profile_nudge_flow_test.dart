// Flow test (FLOW_TEST_CONVENTIONS.md; Banto, issue #421): someone who skips
// the first-run "What do you avoid?" screen lands on a keto-only profile and
// is asked once, on each of Explore and the menu, what they avoid. Skipping,
// then dismissing the notice on Explore leaves the menu's own notice; adding
// sesame from the menu's notice turns the menu into four states (the tahini
// salad, read as keto a moment before, now carries the Avoid pill) and the
// notice goes. The effect spans the onboarding, Explore, the
// menu, the picker and the stored settings, which is why this is a flow and
// not a widget test.
//
// The whole app is pumped with `bantoMode: true`, so it runs under
// `flutter test` with no `--dart-define`. The classifier answers every dish
// green, as a keto-only analysis would: the four states are derived on the
// device from the profile, never sent.

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
import 'package:ketoclub/screens/restriction_onboarding_screen.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/widgets/helper_tool_sheet.dart';
import 'package:ketoclub/widgets/profile_nudge.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';
import 'package:ketoclub/widgets/status_badge.dart';
import 'package:ketoclub/widgets/verdict_counter_tiles.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Wolt venue page the user pastes.
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/banto-nudge-venue';

/// The [VenueRef] [_woltUrl] resolves to.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'banto-nudge-venue',
);

/// A dish named [name] with [id].
Dish _dish(String id, String name) => Dish(
  id: id,
  name: name,
  description: '',
  price: 40,
  options: const <DishOption>[],
);

/// The tahini salad: sesame stated in the dish name.
final Dish _tahiniSalad = _dish('salad', 'סלט עם טחינה');

/// A steak: nothing from the profile.
final Dish _steak = _dish('steak', 'סטייק אנטריקוט');

/// The menu the repository serves for [_ref].
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(id: 'c1', name: 'מנות', dishes: <Dish>[_tahiniSalad, _steak]),
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
        why: 'Nothing starchy.',
      ),
  ],
  unclassified: const <String>[],
  engine: const LlmEngine(model: 'flow-model'),
  analysedAt: DateTime.utc(2026),
);

/// The notice on [surface].
Finder _nudge(ProfileNudgeSurface surface) =>
    find.byKey(profileNudgeKey(surface));

/// The loaded menu's list (see menu_display_flow_test.dart).
final Finder _menuList = find
    .descendant(
      of: find.descendant(
        of: find.byType(RefreshIndicator),
        matching: find.byType(ListView),
      ),
      matching: find.byType(Scrollable),
    )
    .first;

/// The counter tile labelled [label].
Finder _tile(String label) => find.descendant(
  of: find.byType(VerdictCounterTiles),
  matching: find.text(label.toUpperCase()),
);

/// Scrolls the notice's action labelled [label] into view and taps it.
Future<void> _tapAction(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tapAndSettle(tester, find.text(label));
}

/// The state pill reading [label].
Finder _pill(String label) => find.descendant(
  of: find.byType(StateBadge),
  matching: find.text(label.toUpperCase()),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Banto profile nudge flow', () {
    testWidgets('skip the setup, get asked on Explore and the menu, add '
        'sesame from the menu, and the menu re-evaluates', (tester) async {
      // Setup
      final fakes = FakeAppDependencies();
      fakes.repository.stub(_ref, MenuFetched(menu: _menu));
      fakes.classifier.respondWith(_analysis);
      await tester.pumpWidget(
        KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
      );
      await tester.pumpAndSettle();

      // Act: skip the first-run onboarding.
      final skip = find.byKey(restrictionOnboardingSkipKey);
      await tapAndSettle(tester, skip);

      // Assert: Explore asks once, above the list.
      expect(_nudge(ProfileNudgeSurface.discovery), findsOneWidget);
      expect(find.text(_en.profileNudgeMessage), findsOneWidget);

      // Act: dismiss it on Explore.
      await _tapAction(tester, _en.profileNudgeDismiss);

      // Assert: gone there, remembered for Explore alone.
      expect(_nudge(ProfileNudgeSurface.discovery), findsNothing);
      final stored = await fakes.settingsStore.read();
      expect(stored.discoveryNudgeDismissed, isTrue);
      expect(stored.menuNudgeDismissed, isFalse);

      // Act: open the venue from a pasted link.
      await enterText(tester, _woltUrl);
      await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

      // Assert: the menu asks above the dishes, and the salad is still
      // read as keto: three tiles, no Avoid.
      expect(_nudge(ProfileNudgeSurface.menu), findsOneWidget);
      expect(find.text(_tahiniSalad.name), findsOneWidget);
      expect(_tile(_en.stateAvoidTile), findsNothing);

      // Act: add sesame from the notice.
      await _tapAction(tester, _en.profileNudgeChoose);
      final sesame = find.byKey(restrictionOptionKey(RestrictionId.sesame));
      await tester.ensureVisible(sesame);
      await tester.pumpAndSettle();
      await tapAndSettle(tester, sesame);
      await tapAndSettle(tester, find.byKey(helperToolOkKey));

      // The tiles sit above the dishes: scroll back up to them.
      await tester.scrollUntilVisible(
        _tile(_en.stateAvoidTile),
        -200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();

      // Assert: the notice is gone, the menu names the profile and is read
      // in four states: the open filter still lists everything, the salad
      // now carries the Avoid pill and the steak "no trigger found".
      expect(_nudge(ProfileNudgeSurface.menu), findsNothing);
      expect(_tile(_en.stateAvoidTile), findsOneWidget);
      expect(find.text(_tahiniSalad.name), findsOneWidget);
      expect(_pill(_en.stateAvoidBadge), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(_steak.name),
        200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      expect(find.text(_steak.name), findsOneWidget);
      expect(_pill(_en.stateFitsStrictBadge), findsOneWidget);
      final saved = await fakes.settingsStore.read();
      expect(saved.profile.contains(RestrictionId.sesame), isTrue);
      expect(saved.onboardingSeen, isTrue);
    });
  });
}
