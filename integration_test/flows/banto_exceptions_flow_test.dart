// Flow test (FLOW_TEST_CONVENTIONS.md; Banto, issue #417): a tree-nut
// profile, picked on the first-run onboarding, flags a dish whose only
// match is "almond"; adding the exception "almond" from the restriction's
// row in Settings stops flagging that dish on the menu, while a walnut
// dish stays to avoid, and the exception is saved on the device. The
// effect spans the onboarding, Settings and the menu, which is why this is
// a flow and not a widget test.
//
// The whole app is pumped with `bantoMode: true`, so it runs under
// `flutter test` with no `--dart-define`. The classifier answers every dish
// green, as a keto-only analysis would: the states are derived on the
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
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/widgets/exceptions_sheet.dart';
import 'package:ketoclub/widgets/status_badge.dart';
import 'package:ketoclub/widgets/verdict_counter_tiles.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Wolt venue page the user pastes.
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/banto-exceptions-venue';

/// The [VenueRef] [_woltUrl] resolves to.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'banto-exceptions-venue',
);

/// A dish named [name] with [id].
Dish _dish(String id, String name) => Dish(
  id: id,
  name: name,
  description: '',
  price: 55,
  options: const <DishOption>[],
);

/// Almond is the only tree nut it names.
final Dish _almondChicken = _dish('chicken', 'Almond crusted chicken');

/// Walnut is a tree nut too, and is never excepted.
final Dish _walnutBrownie = _dish('brownie', 'Walnut brownie');

/// Nothing from the profile.
final Dish _steak = _dish('steak', 'Grilled steak');

/// The menu the repository serves for [_ref].
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'Mains',
      dishes: <Dish>[_almondChicken, _walnutBrownie, _steak],
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
        why: 'Nothing starchy.',
      ),
  ],
  unclassified: const <String>[],
  engine: const LlmEngine(model: 'flow-model'),
  analysedAt: DateTime.utc(2026),
);

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

/// The state pill reading [label].
Finder _pill(String label) => find.descendant(
  of: find.byType(StateBadge),
  matching: find.text(label.toUpperCase()),
);

/// Scrolls [finder] into view in the first scrollable and taps it.
Future<void> _scrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tapAndSettle(tester, finder);
}

/// Pastes the venue link on Explore and opens the menu.
Future<void> _openVenue(WidgetTester tester) async {
  await enterText(tester, _woltUrl);
  await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Banto exceptions flow', () {
    testWidgets('an almond exception stops flagging the almond dish and '
        'leaves the walnut one', (tester) async {
      // Setup
      final fakes = FakeAppDependencies();
      fakes.repository.stub(_ref, MenuFetched(menu: _menu));
      fakes.classifier.respondWith(_analysis);
      await tester.pumpWidget(
        KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
      );
      await tester.pumpAndSettle();

      // Act: pick tree nuts on the first-run onboarding, then open the
      // venue.
      await _scrollAndTap(
        tester,
        find.byKey(restrictionOnboardingChipKey(RestrictionId.treeNuts)),
      );
      await _scrollAndTap(tester, find.byKey(restrictionOnboardingContinueKey));
      await _openVenue(tester);

      // Assert: both nut dishes are to avoid and hidden; the steak has no
      // trigger.
      expect(find.text(_en.headerStateCountsStrict(1, 0, 0)), findsOneWidget);
      expect(find.text(_almondChicken.name), findsNothing);
      expect(find.text(_walnutBrownie.name), findsNothing);
      expect(find.text(_steak.name), findsOneWidget);

      // Act: back to Settings, and add "almond" to tree nuts' exceptions.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapAndSettle(tester, navDestination(_en.navSettings));
      await _scrollAndTap(
        tester,
        find.byKey(restrictionRowKey(RestrictionId.treeNuts)),
      );

      // Assert: the sheet explains it, with the strict line for an allergy.
      expect(find.text(_en.exceptionsExplain), findsOneWidget);
      expect(find.text(_en.exceptionsStrictNote), findsOneWidget);

      // Act
      await tapAndSettle(tester, find.byKey(exceptionSuggestionKey('almond')));
      await tapAndSettle(tester, find.byKey(exceptionsSaveKey));

      // Assert: the row says so, and the device kept it.
      expect(find.text(_en.exceptionsRowLine('almond')), findsOneWidget);
      final saved = await fakes.settingsStore.read();
      expect(
        saved.profile.entryFor(RestrictionId.treeNuts)!.exceptions,
        <String>['almond'],
      );

      // Act: open the same menu again.
      await tapAndSettle(tester, navDestination(_en.navExplore));
      await _openVenue(tester);

      // Assert: the almond dish is no longer flagged and reads "no trigger
      // found", never "safe"; the walnut dish is still to avoid.
      expect(find.text(_en.headerStateCountsStrict(2, 0, 0)), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(_almondChicken.name),
        200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      expect(find.text(_almondChicken.name), findsOneWidget);
      expect(_pill(_en.stateFitsStrictBadge), findsWidgets);
      expect(find.text(_walnutBrownie.name), findsNothing);
      await tester.scrollUntilVisible(
        _tile(_en.stateAvoidTile),
        -200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      await tapAndSettle(tester, _tile(_en.stateAvoidTile));
      await tester.scrollUntilVisible(
        find.text(_walnutBrownie.name),
        200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      expect(find.text(_walnutBrownie.name), findsOneWidget);
      expect(_pill(_en.stateAvoidBadge), findsOneWidget);
      expect(find.text(_almondChicken.name), findsNothing);
    });
  });
}
