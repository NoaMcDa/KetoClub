// Flow test (FLOW_TEST_CONVENTIONS.md; Banto, ALG-05, issue #347): a
// profile with peanuts and sesame, picked on the first-run onboarding
// (ALG-02b), turns the menu screen into four states. The menu opens on
// everything but what to avoid, so the tahini salad (sesame named in the
// dish) is hidden until the Avoid tile is tapped; the nut cake (אגוזים:
// peanuts suspected) is to ask about; and the shared text never says
// "safe" or "בטוח". The effect spans the onboarding, Explore and the menu,
// which is why this is a flow and not a widget test.
//
// The whole app is pumped with `bantoMode: true`, so it runs under
// `flutter test` with no `--dart-define`. The classifier answers every
// dish green from the language model, as a keto-only analysis would: the
// four states are derived on the device from the profile, never sent.

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
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/status_badge.dart';
import 'package:ketoclub/widgets/verdict_counter_tiles.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Wolt venue page the user pastes.
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/banto-four-state-venue';

/// The [VenueRef] [_woltUrl] resolves to.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'banto-four-state-venue',
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

/// The nut cake: אגוזים reads as tree nuts likely and peanuts suspected.
final Dish _nutCake = _dish('cake', 'עוגת אגוזים');

/// A steak: nothing from the profile.
final Dish _steak = _dish('steak', 'סטייק אנטריקוט');

/// The menu the repository serves for [_ref].
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'מנות',
      dishes: <Dish>[_tahiniSalad, _nutCake, _steak],
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

/// "safe" as a word in English, "בטוח" anywhere in Hebrew.
final RegExp _safe = RegExp('(?<![A-Za-z])safe|בטוח', caseSensitive: false);

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

/// Picks [id] on the first-run onboarding.
Future<void> _pick(WidgetTester tester, RestrictionId id) async {
  final chip = find.byKey(restrictionOnboardingChipKey(id));
  await tester.scrollUntilVisible(
    chip,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tapAndSettle(tester, chip);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Banto four-state flow', () {
    testWidgets('a peanut and sesame profile hides avoid, asks about nuts '
        'and shares no "safe"', (tester) async {
      // Setup
      final fakes = FakeAppDependencies();
      fakes.repository.stub(_ref, MenuFetched(menu: _menu));
      fakes.classifier.respondWith(_analysis);
      await tester.pumpWidget(
        KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
      );
      await tester.pumpAndSettle();

      // Act: pick peanuts and sesame on the first-run onboarding.
      await _pick(tester, RestrictionId.peanuts);
      await _pick(tester, RestrictionId.sesame);
      await tester.scrollUntilVisible(
        find.byKey(restrictionOnboardingContinueKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tapAndSettle(tester, find.byKey(restrictionOnboardingContinueKey));

      // Act: on Explore, paste the link and open the venue.
      await enterText(tester, _woltUrl);
      await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

      // Assert: four tiles, the strict default hides what to avoid, and
      // the header counts replace the keto score.
      expect(_tile(_en.stateAskTile), findsOneWidget);
      expect(_tile(_en.stateAvoidTile), findsOneWidget);
      expect(find.text(_en.menuShowingNotAvoid), findsOneWidget);
      expect(find.text(_en.headerStateCountsStrict(1, 0, 1)), findsOneWidget);
      expect(find.byType(RulesCheckedChip), findsOneWidget);
      expect(find.text(_tahiniSalad.name), findsNothing);

      // Assert: the nut cake is to ask about; the steak reads "no trigger
      // found — ask the restaurant", never "safe".
      await tester.scrollUntilVisible(
        find.text(_nutCake.name),
        200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      expect(_pill(_en.stateAskBadge), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(_steak.name),
        200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      expect(_pill(_en.stateFitsStrictBadge), findsOneWidget);

      // Act: the Avoid tile reaches the hidden dish.
      await tester.scrollUntilVisible(
        _tile(_en.stateAvoidTile),
        -200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      await tapAndSettle(tester, _tile(_en.stateAvoidTile));

      // Assert: the tahini salad is to avoid, sesame named in Hebrew.
      expect(find.text(_tahiniSalad.name), findsOneWidget);
      expect(_pill(_en.stateAvoidBadge), findsOneWidget);
      expect(find.text('שומשום'), findsOneWidget);
      expect(find.text(_nutCake.name), findsNothing);

      // Act: share the menu.
      await tapAndSettle(tester, find.byTooltip(_en.actionMoreMenuOptions));
      await tapAndSettle(tester, find.text(_en.actionShareMenu));

      // Assert: the shared text lists the steak and the nut cake, leaves
      // the salad out, and never says "safe" or "בטוח".
      final shared = fakes.menuSharer.shareCalls.single.text;
      expect(shared, contains(_steak.name));
      expect(shared, contains(_nutCake.name));
      expect(shared, isNot(contains(_tahiniSalad.name)));
      expect(shared, contains('לא נמצא חשש'));
      expect(shared, isNot(matches(_safe)));
    });
  });
}
