// "My order" on the menu screen (Banto, issue #418): each evaluated dish
// card's toggle, the floating "My order · N" pill (390px, RTL, two panes)
// and the order card it opens; the order outlives the menu's route; a keto
// screen, a keto-only profile and a screen with no order controller show
// none of it. Plain `flutter test` compiles the flag off, so each test
// passes `bantoMode` explicitly.

import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/menu_screen.dart';
import 'package:ketoclub/screens/order_card_screen.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/state/order_controller.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_connectivity.dart';
import '../fakes/fake_external_link_opener.dart';
import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_menu_sharer.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_screen_brightness.dart';
import '../fakes/fake_settings_store.dart';

final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _he = AppLocalizationsHe();

const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

final DietaryProfile _sesame = DietaryProfile.empty.withEntry(
  RestrictionId.sesame,
);

/// A dish named [name] with [id].
Dish _dish(String id, String name) => Dish(
  id: id,
  name: name,
  description: '',
  price: 10,
  options: const <DishOption>[],
);

/// A Hebrew menu: the eggplant salad (ask) and the tahini salad (avoid).
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'סלטים',
      dishes: <Dish>[
        _dish('eggplant', 'סלט חצילים'),
        _dish('tahini', 'סלט עם טחינה'),
      ],
    ),
  ],
);

MenuController _controller(DietaryProfile profile) {
  final repository = FakeMenuRepository()
    ..stub(_ref, MenuFetched(menu: _menu, fromCache: true));
  return MenuController(
    repository,
    FakeMenuClassifier(),
    FakeSettingsStore(initial: AppSettings(profile: profile)),
    FakeNotesStore(),
    CarbBudgetController(),
  );
}

/// Pumps the menu screen at [size] and returns its controller, showing
/// every dish (a strict profile opens on everything but avoid); [order]
/// null provides no order controller at all.
Future<MenuController> _pump(
  WidgetTester tester, {
  required OrderController? order,
  bool bantoMode = true,
  DietaryProfile? profile,
  Size size = const Size(390, 844),
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = _controller(profile ?? _sesame);
  final screen = ChangeNotifierProvider<MenuController>.value(
    value: controller,
    child: MenuScreen(
      ref: _ref,
      screenBrightness: FakeScreenBrightness(),
      connectivity: FakeConnectivity(),
      externalLinkOpener: FakeExternalLinkOpener(),
      menuSharer: FakeMenuSharer(),
      bantoMode: bantoMode,
    ),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<CarbBudgetController>.value(
      value: CarbBudgetController(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: order == null
            ? screen
            : ChangeNotifierProvider<OrderController>.value(
                value: order,
                child: screen,
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await controller.setFilter(MenuFilter.all);
  await tester.pumpAndSettle();
  return controller;
}

/// A window tall enough for both dish cards below the header.
const Size _tall = Size(800, 1600);

/// The order toggle on the card of the dish named [name].
Finder _toggleOf(String name) => find.descendant(
  of: find.ancestor(of: find.text(name), matching: find.byType(DishCard)),
  matching: find.byKey(dishOrderToggleKey),
);

void main() {
  group('the order toggle and pill', () {
    testWidgets('each evaluated dish has an "Add to my order" toggle with a '
        'screen-reader label, and no pill shows before one is added', (
      tester,
    ) async {
      // Arrange
      final handle = tester.ensureSemantics();

      // Act: tall enough for both cards (a ListView builds lazily).
      await _pump(tester, order: OrderController(), size: _tall);

      // Assert
      expect(find.byKey(dishOrderToggleKey), findsNWidgets(2));
      expect(find.bySemanticsLabel(_en.orderAdd), findsNWidgets(2));
      expect(find.byKey(menuOrderPillKey), findsNothing);
      handle.dispose();
    });

    testWidgets('adding two dishes shows "My order · 2" and the toggle then '
        'reads "Remove from my order"', (tester) async {
      // Arrange
      final handle = tester.ensureSemantics();
      final order = OrderController();
      await _pump(tester, order: order, size: _tall);

      // Act
      await tester.tap(_toggleOf('סלט עם טחינה'));
      await tester.pumpAndSettle();
      await tester.tap(_toggleOf('סלט חצילים'));
      await tester.pumpAndSettle();

      // Assert
      expect(order.dishIdsFor(_ref), <String>['tahini', 'eggplant']);
      expect(find.text(_en.orderPill(2)), findsOneWidget);
      expect(find.bySemanticsLabel(_en.orderPillSemantic(2)), findsOneWidget);
      expect(find.bySemanticsLabel(_en.orderRemove), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('in Hebrew (RTL) at 390px the pill sits at the bottom, '
        'centred, inside the screen', (tester) async {
      // Arrange
      final order = OrderController()..toggle(_ref, 'eggplant');

      // Act
      await _pump(tester, order: order, locale: const Locale('he'));

      // Assert
      expect(tester.takeException(), isNull);
      final pill = find.byKey(menuOrderPillKey);
      expect(find.text(_he.orderPill(1)), findsOneWidget);
      final rect = tester.getRect(pill);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(390));
      expect(rect.center.dx, closeTo(195, 1));
      expect(rect.bottom, lessThanOrEqualTo(844 - 16));
    });

    testWidgets('in two panes the pill is centred on the dish list, not on '
        'the side pane', (tester) async {
      // Arrange
      final order = OrderController()..toggle(_ref, 'eggplant');

      // Act
      await _pump(tester, order: order, size: const Size(1200, 900));

      // Assert: the side pane is the leading 380px; the dish list the rest.
      final dishes = tester.getRect(find.byType(RefreshIndicator));
      final pill = tester.getRect(find.byKey(menuOrderPillKey));
      expect(dishes.left, greaterThan(380));
      expect(pill.center.dx, closeTo(dishes.center.dx, 1));
    });

    testWidgets('the pill opens the order card with both dishes and one '
        'allergy note; removing there updates the pill', (tester) async {
      // Arrange
      final order = OrderController()
        ..toggle(_ref, 'eggplant')
        ..toggle(_ref, 'tahini');
      await _pump(tester, order: order);

      // Act
      await tester.tap(find.byKey(menuOrderPillKey));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(OrderCardScreen), findsOneWidget);
      expect(find.byKey(orderCardSectionKey('eggplant')), findsOneWidget);
      expect(find.byKey(orderCardSectionKey('tahini')), findsOneWidget);
      expect(find.byKey(orderCardAllergyKey), findsOneWidget);

      // Act
      await tester.tap(find.byKey(orderCardRemoveKey('tahini')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.waiterCardDone));
      await tester.pumpAndSettle();

      // Assert
      expect(order.dishIdsFor(_ref), <String>['eggplant']);
      expect(find.text(_en.orderPill(1)), findsOneWidget);
    });

    testWidgets('Clear order on the card hides the pill', (tester) async {
      // Arrange
      final order = OrderController()..toggle(_ref, 'eggplant');
      await _pump(tester, order: order);
      await tester.tap(find.byKey(menuOrderPillKey));
      await tester.pumpAndSettle();

      // Act
      await tester.ensureVisible(find.byKey(orderCardClearKey));
      await tester.tap(find.byKey(orderCardClearKey));
      await tester.pumpAndSettle();

      // Assert
      expect(order.dishIdsFor(_ref), isEmpty);
      expect(find.byKey(menuOrderPillKey), findsNothing);
    });

    testWidgets('the order outlives the menu route: a fresh screen for the '
        'same menu shows the pill again', (tester) async {
      // Arrange
      final order = OrderController();
      await _pump(tester, order: order);
      await tester.tap(_toggleOf('סלט חצילים'));
      await tester.pumpAndSettle();

      // Act: a new screen and controller, as reopening the venue builds.
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, order: order);

      // Assert
      expect(find.text(_en.orderPill(1)), findsOneWidget);
    });
  });

  group('where the order is not offered', () {
    testWidgets('a keto-only profile under Banto has no toggle and no pill', (
      tester,
    ) async {
      // Arrange
      final order = OrderController()..toggle(_ref, 'eggplant');

      // Act
      await _pump(tester, order: order, profile: DietaryProfile.empty);

      // Assert
      expect(find.byKey(dishOrderToggleKey), findsNothing);
      expect(find.byKey(menuOrderPillKey), findsNothing);
    });

    testWidgets('the keto build has no toggle and no pill', (tester) async {
      // Arrange
      final order = OrderController()..toggle(_ref, 'eggplant');

      // Act
      await _pump(tester, order: order, bantoMode: false);

      // Assert
      expect(find.byKey(dishOrderToggleKey), findsNothing);
      expect(find.byKey(menuOrderPillKey), findsNothing);
    });

    testWidgets('with no order controller provided there is no toggle', (
      tester,
    ) async {
      // Act
      await _pump(tester, order: null);

      // Assert
      expect(find.byKey(dishOrderToggleKey), findsNothing);
      expect(find.byKey(menuOrderPillKey), findsNothing);
    });
  });
}
