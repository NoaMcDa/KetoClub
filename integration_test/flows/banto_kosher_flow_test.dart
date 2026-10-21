// Flow test (FLOW_TEST_CONVENTIONS.md; Banto, issue #342): a kosher
// profile, picked on the first-run onboarding, reads a Hebrew Wolt menu by
// its components. Pork ribs and shrimp (named in the dish) and a
// cheeseburger (meat with cheese) are to avoid; salmon in a cream sauce is
// not flagged, since fish is no meat; and because kosher is a religious
// component, a dish with nothing found reads "No trigger found — ask the
// restaurant", never "fits" (which would read as "kosher"). The effect spans
// the onboarding, Explore and the menu, which is why this is a flow and not
// a widget test.
//
// The whole app is pumped with `bantoMode: true`, so it runs under
// `flutter test` with no `--dart-define`. The classifier answers every dish
// green from the language model, as a keto-only analysis would: the states
// are derived on the device from the profile, never sent.

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
import 'package:ketoclub/widgets/status_badge.dart';
import 'package:ketoclub/widgets/verdict_counter_tiles.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Wolt venue page the user pastes.
const String _woltUrl =
    'https://wolt.com/he/isr/tel-aviv/restaurant/banto-kosher-venue';

/// The [VenueRef] [_woltUrl] resolves to.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'banto-kosher-venue',
);

/// A dish named [name] with [id] and [description].
Dish _dish(String id, String name, String description) => Dish(
  id: id,
  name: name,
  description: description,
  price: 60,
  options: const <DishOption>[],
);

/// Pork named in the dish.
final Dish _porkRibs = _dish('ribs', 'צלעות חזיר', 'ברוטב ברביקיו');

/// Shrimp named in the dish.
final Dish _shrimp = _dish('shrimp', 'שרימפס בשום', 'מוקפצים בשמן זית');

/// Meat with cheese in one word.
final Dish _cheeseburger = _dish('burger', "צ'יזבורגר", 'קציצת בקר 200 גרם');

/// Fish with cream: not meat with dairy.
final Dish _salmon = _dish('salmon', 'סלמון ברוטב שמנת', 'עם אורז לבן');

/// The menu the repository serves for [_ref].
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'עיקריות',
      dishes: <Dish>[_porkRibs, _shrimp, _cheeseburger, _salmon],
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Banto kosher flow', () {
    testWidgets('a kosher profile avoids pork, shrimp and a cheeseburger, '
        'flags no fish in cream, and never says "fits"', (tester) async {
      // Setup
      final fakes = FakeAppDependencies();
      fakes.repository.stub(_ref, MenuFetched(menu: _menu));
      fakes.classifier.respondWith(_analysis);
      await tester.pumpWidget(
        KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
      );
      await tester.pumpAndSettle();

      // Act: pick kosher on the first-run onboarding, under its own
      // religious heading.
      final chip = find.byKey(
        restrictionOnboardingChipKey(RestrictionId.kosher),
      );
      await tester.scrollUntilVisible(
        chip,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text(_en.restrictionKindReligious), findsOneWidget);
      await tapAndSettle(tester, chip);
      await tester.scrollUntilVisible(
        find.byKey(restrictionOnboardingContinueKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tapAndSettle(tester, find.byKey(restrictionOnboardingContinueKey));

      // Act: on Explore, paste the link and open the venue.
      await enterText(tester, _woltUrl);
      await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

      // Assert: the strict wording — the menu opens on everything but what
      // to avoid, and one dish has no trigger.
      expect(_tile(_en.stateAvoidTile), findsOneWidget);
      expect(find.text(_en.menuShowingNotAvoid), findsOneWidget);
      expect(find.text(_en.headerStateCountsStrict(1, 0, 0)), findsOneWidget);
      expect(find.text(_porkRibs.name), findsNothing);
      expect(find.text(_shrimp.name), findsNothing);
      expect(find.text(_cheeseburger.name), findsNothing);

      // Assert: the salmon in cream is not flagged, and reads "no trigger
      // found — ask the restaurant".
      await tester.scrollUntilVisible(
        find.text(_salmon.name),
        200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      expect(_pill(_en.stateFitsStrictBadge), findsOneWidget);
      expect(_pill(_en.stateFitsBadge), findsNothing);

      // Act: the Avoid tile reaches the hidden dishes.
      await tester.scrollUntilVisible(
        _tile(_en.stateAvoidTile),
        -200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      await tapAndSettle(tester, _tile(_en.stateAvoidTile));

      // Assert: pork, shrimp and the cheeseburger are to avoid, each
      // flagged under kosher's Hebrew name; the salmon is not among them.
      for (final dish in <Dish>[_porkRibs, _shrimp, _cheeseburger]) {
        await tester.scrollUntilVisible(
          find.text(dish.name),
          200,
          scrollable: _menuList,
        );
        await tester.pumpAndSettle();
        expect(find.text(dish.name), findsOneWidget, reason: dish.name);
      }
      expect(_pill(_en.stateAvoidBadge), findsWidgets);
      expect(find.text('כשרות'), findsWidgets);
      expect(find.text(_salmon.name), findsNothing);
    });
  });
}
