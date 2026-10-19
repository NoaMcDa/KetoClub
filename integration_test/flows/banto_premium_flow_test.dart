// Flow test (FLOW_TEST_CONVENTIONS.md; Banto, ALG-18, issue #360).
//
// 1. A free user with one restriction adds a second in Settings: the
//    paywall opens with the store's own price, the (scripted) store sells
//    Premium, the paywall closes itself and the second restriction is
//    added. The effect spans Settings, the picker, the paywall and the
//    store, which is why this is a flow and not a widget test.
//
// 2. A user whose Premium lapsed keeps two saved restrictions, more than
//    the free plan's one: Settings reads the lapse and lists both, the chef
//    card carries both, the menu evaluates both (one dish to ask about, one
//    to avoid, which the default filter folds away), and the waiter
//    question, the Waiter Card's chef card, the Why sheet and Recent's
//    post-meal check all open — and no paywall appears anywhere. Gating
//    safety is the research's complaint 4; nothing about a restriction
//    already saved may ever be locked.
//
// The whole app is pumped with `bantoMode: true`, so it runs under
// `flutter test` with no `--dart-define`. The store is a scripted fake
// defined here: no real purchase is made.

import 'dart:async';

import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/app.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/chef_card_screen.dart';
import 'package:ketoclub/screens/menu_screen.dart';
import 'package:ketoclub/screens/paywall_screen.dart';
import 'package:ketoclub/screens/settings_premium_section.dart';
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/screens/waiter_card_sheet.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/platform/entitlement.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/premium_gates.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';
import 'package:ketoclub/widgets/status_badge.dart';
import 'package:provider/provider.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The store's localized price, as the store would format it.
const String _price = '₪19.90';

/// A scripted store: sells Premium at [_price], starts premium or not, answers
/// a refresh with what it holds and a purchase with Premium. Records the
/// purchases it was asked for.
final class _FlowStore implements Entitlement {
  new({required this._premium, this.lapsed = false});

  /// Whether the store's answer to a refresh is "no active subscription",
  /// whatever [isPremium] said before: a subscription that lapsed.
  final bool lapsed;

  bool _premium;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  /// How many purchases were asked for.
  int purchases = 0;

  @override
  bool get sellsPremium => true;

  @override
  bool get isPremium => _premium;

  @override
  Stream<bool> get changes => _changes.stream;

  void _set(bool value) {
    if (_premium == value) return;
    _premium = value;
    _changes.add(value);
  }

  @override
  Future<EntitlementResult> refresh() async {
    if (lapsed) _set(false);
    return _premium ? const PremiumActive() : const PremiumInactive();
  }

  @override
  Future<EntitlementResult> restore() => refresh();

  @override
  Future<String?> localizedPrice() async => _price;

  @override
  Future<EntitlementResult> purchase() async {
    purchases++;
    _set(true);
    return const PremiumActive();
  }
}

/// The Wolt venue page the lapsed user pastes.
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/banto-premium-venue';

/// The [VenueRef] [_woltUrl] resolves to.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'banto-premium-venue',
);

/// The nut cake: אגוזים reads as peanuts suspected, so "ask".
const Dish _nutCake = Dish(
  id: 'cake',
  name: 'עוגת אגוזים',
  description: '',
  price: 30,
  options: <DishOption>[],
);

/// The tahini salad: sesame stated, so "avoid".
const Dish _tahini = Dish(
  id: 'tahini',
  name: 'סלט עם טחינה',
  description: '',
  price: 38,
  options: <DishOption>[],
);

/// The menu the repository serves for [_ref].
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[
    MenuCategory(id: 'c1', name: 'מנות', dishes: <Dish>[_nutCake, _tahini]),
  ],
);

/// Every dish green from the language model, as a keto-only analysis is.
final MenuAnalysed _analysis = MenuAnalysed(
  dishes: <AnalysedDish>[
    for (final dish in _menu.allDishes)
      AnalysedDish(
        dishId: dish.id,
        name: dish.name,
        verdict: DishVerdict.orderAsIs,
        why: 'Fits',
      ),
  ],
  unclassified: const <String>[],
  engine: const LlmEngine(model: 'flow-model'),
  analysedAt: DateTime.utc(2026),
);

/// The two saved restrictions of the lapsed user.
final DietaryProfile _peanutsAndSesame = DietaryProfile.empty
    .withEntry(RestrictionId.peanuts)
    .withEntry(RestrictionId.sesame);

/// The state pill reading [label].
Finder _pill(String label) => find.descendant(
  of: find.byType(StateBadge),
  matching: find.text(label.toUpperCase()),
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

/// Pops the topmost route of the app's navigator: the chef card, the
/// Waiter Card or the Why sheet, whichever is on top.
Future<void> _popTop(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await tester.pumpAndSettle();
}

/// Scrolls the Settings page until [finder] is on screen, then taps it.
Future<void> _tapInSettings(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tapAndSettle(tester, finder);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Banto Premium flow', () {
    testWidgets('a free user adds a second restriction: paywall, purchase, '
        'added', (tester) async {
      // Setup: one restriction, the free plan's limit, past the onboarding.
      final fakes = FakeAppDependencies();
      final store = _FlowStore(premium: false);
      fakes.entitlement = store;
      await fakes.settingsStore.write(
        AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.peanuts),
          onboardingSeen: true,
          helperToolSeen: true,
        ),
      );
      await tester.pumpWidget(
        KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
      );
      await tester.pumpAndSettle();

      // Act: Settings, "Add restriction", sesame.
      await tapAndSettle(tester, navDestination(_en.navSettings));
      expect(find.text(_en.settingsPremiumFree(freeScansPerMonth)), findsOne);
      await _tapInSettings(tester, find.byKey(restrictionsAddKey));
      final sesame = find.byKey(restrictionOptionKey(RestrictionId.sesame));
      await tester.ensureVisible(sesame);
      await tester.pumpAndSettle();
      await tapAndSettle(tester, sesame);

      // Assert: the paywall, saying why, with the store's price and the
      // line that nothing saved is locked; sesame is not added yet.
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.text(_en.paywallReasonRestrictions), findsOneWidget);
      expect(find.text(_en.paywallPrice(_price)), findsOneWidget);
      expect(find.text(_en.paywallNeverLocked), findsOneWidget);
      expect(
        (await fakes.settingsStore.read()).profile.contains(
          RestrictionId.sesame,
        ),
        isFalse,
      );

      // Act: subscribe.
      await _tapInSettings(tester, find.byKey(paywallBuyKey));

      // Assert: the paywall closed itself, sesame is added and saved, and
      // Settings says Premium is active.
      expect(store.purchases, 1);
      expect(find.byType(PaywallScreen), findsNothing);
      expect(
        find.byKey(restrictionRowKey(RestrictionId.sesame)),
        findsOneWidget,
      );
      final saved = (await fakes.settingsStore.read()).profile;
      expect(saved.contains(RestrictionId.peanuts), isTrue);
      expect(saved.contains(RestrictionId.sesame), isTrue);
      expect(find.text(_en.settingsPremiumActive), findsOneWidget);
    });

    testWidgets('a lapsed user keeps every saved restriction evaluated, and '
        'no safety surface is ever locked', (tester) async {
      // Setup: two saved restrictions, Premium bought once and lapsed.
      final fakes = FakeAppDependencies();
      final store = _FlowStore(premium: true, lapsed: true);
      fakes.entitlement = store;
      await fakes.settingsStore.write(
        AppSettings(
          profile: _peanutsAndSesame,
          onboardingSeen: true,
          helperToolSeen: true,
        ),
      );
      fakes.repository.stub(_ref, MenuFetched(menu: _menu));
      fakes.classifier.respondWith(_analysis);
      await tester.pumpWidget(
        KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
      );
      await tester.pumpAndSettle();

      // Act: Settings reads the store, which says the subscription lapsed.
      await tapAndSettle(tester, navDestination(_en.navSettings));

      // Assert: the free plan, and both saved restrictions still listed.
      expect(find.byKey(settingsPremiumRowKey), findsOneWidget);
      expect(find.text(_en.settingsPremiumFree(freeScansPerMonth)), findsOne);
      expect(store.isPremium, isFalse);
      for (final id in <RestrictionId>[
        RestrictionId.peanuts,
        RestrictionId.sesame,
      ]) {
        expect(find.byKey(restrictionRowKey(id)), findsOneWidget);
      }

      // Act: the profile's chef card.
      await _tapInSettings(tester, find.byKey(restrictionsChefCardKey));

      // Assert: it carries a line for each saved restriction.
      expect(find.byType(ChefCardScreen), findsOneWidget);
      for (final line in ChefCardText.compose(
        _peanutsAndSesame,
        hebrew: false,
      )) {
        expect(
          find.descendant(
            of: find.byType(ChefCardScreen),
            matching: find.text(line),
          ),
          findsOneWidget,
          reason: line,
        );
      }
      expect(find.byType(PaywallScreen), findsNothing);
      await _popTop(tester);

      // Act: Explore, then the menu from a pasted link.
      await tapAndSettle(tester, navDestination(_en.navExplore));
      await enterText(tester, _woltUrl);
      await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

      // Assert: both saved restrictions are evaluated — the nut cake is
      // to ask about (peanuts) and the tahini salad to avoid (sesame).
      expect(find.text(_nutCake.name), findsOneWidget);
      expect(_pill(_en.stateAskBadge), findsOneWidget);
      final menu = Provider.of<MenuController>(
        tester.element(find.byType(MenuScreen)),
        listen: false,
      );
      expect(menu.profile, _peanutsAndSesame);
      final cake = menu.evaluationFor(_nutCake.id)!;
      final tahini = menu.evaluationFor(_tahini.id)!;
      expect(cake.state, DishState.ask);
      expect(
        cake.concerns.map((c) => c.restrictionId),
        contains(RestrictionId.peanuts),
      );
      expect(tahini.state, DishState.avoid);
      expect(
        tahini.concerns.map((c) => c.restrictionId),
        contains(RestrictionId.sesame),
      );

      // Act: the cake's waiter question, then its Waiter Card.
      await tester.scrollUntilVisible(
        find.text(_en.dishCardAskQuestion),
        200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.text(_en.dishCardAskQuestion));
      await tester.scrollUntilVisible(
        find.text(_en.dishCardFullScreen),
        200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.text(_en.dishCardFullScreen));

      // Assert: the Waiter Card opens, and from it the dish's chef card.
      expect(find.byType(WaiterCardSheet), findsOneWidget);
      await tester.ensureVisible(find.byKey(waiterCardChefCardKey));
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.byKey(waiterCardChefCardKey));
      expect(find.byType(ChefCardScreen), findsOneWidget);
      expect(find.byType(PaywallScreen), findsNothing);
      await _popTop(tester);
      await _popTop(tester);
      expect(find.byType(WaiterCardSheet), findsNothing);

      // Act: the Why sheet.
      final why = find.byKey(dishWhyKey).first;
      await tester.ensureVisible(why);
      await tester.pumpAndSettle();
      await tapAndSettle(tester, why);

      // Assert: it opens.
      expect(find.text(_en.whySheetTitle), findsOneWidget);
      expect(find.byType(PaywallScreen), findsNothing);
      await _popTop(tester);

      // Act: back to Explore, then Recent's post-meal check.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapAndSettle(tester, navDestination(_en.navSaved));
      await tapAndSettle(tester, find.text(_en.confirmPromptOpen));

      // Assert: the prompt asks about the saved restrictions; nothing was
      // ever locked, and nothing was bought.
      expect(find.text(_en.confirmSave), findsOneWidget);
      expect(find.byType(PaywallScreen), findsNothing);
      expect(store.purchases, 0);
    });
  });
}
