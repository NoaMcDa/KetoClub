// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §15, §18.4): the
// journey of opening a menu that carries a restaurant's own notice (issue
// #445) and seeing only real dishes as cards, with the notice kept one
// tap away behind a single quiet line.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/widgets/category_chips.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/restaurant_notices_row.dart';

import 'flow_support.dart';

/// The Wolt venue page the user pastes.
const String _woltUrl =
    'https://wolt.com/en/isr/ashdod/restaurant/burger-corner';

/// The [VenueRef] [_woltUrl] resolves to.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'burger-corner',
);

/// The notice category's heading, as the reported menu wrote it.
const String _noticeHeading = 'שימו לב! 💙';

/// The notice line's name.
const String _noticeName = 'מידע לאלרגנים! 💙';

/// The notice line's text.
const String _noticeText = 'למידע על אלרגנים יש ליצור קשר עם המסעדה!!';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// A menu whose first category holds only a zero-priced notice, followed
/// by two real dishes under "Burgers".
Menu _buildMenu() => Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const [
    MenuCategory(
      id: 'c0',
      name: _noticeHeading,
      dishes: [
        Dish(
          id: 'notice',
          name: _noticeName,
          description: _noticeText,
          price: 0,
          options: <DishOption>[],
        ),
      ],
    ),
    MenuCategory(
      id: 'c1',
      name: 'Burgers',
      dishes: [
        Dish(
          id: 'burger',
          name: 'Bunless Burger',
          description: '',
          price: 58,
          options: <DishOption>[],
        ),
        Dish(
          id: 'salad',
          name: 'Chicken Salad',
          description: '',
          price: 52,
          options: <DishOption>[],
        ),
      ],
    ),
  ],
);

/// The loaded menu's list, named explicitly because the screen holds
/// other scrollables too (see `menu_display_flow_test.dart`).
final Finder _menuList = find
    .descendant(
      of: find.descendant(
        of: find.byType(RefreshIndicator),
        matching: find.byType(ListView),
      ),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Menu notices flow', () {
    testWidgets('user opens a menu with a notice section and sees only real '
        'dishes, with the notice one tap away', (tester) async {
      // Setup: the repository answers the pasted venue with the menu; the
      // fake classifier gives every line a verdict, the notice included.
      final fakes = FakeAppDependencies();
      fakes.repository.stub(_ref, MenuFetched(menu: _buildMenu()));
      await pumpApp(tester, fakes);

      // Act: paste the link and open the venue.
      await enterText(tester, _woltUrl);
      await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

      // Assert: the list opens on a real dish. The notice category comes
      // first on the menu, so were it still drawn it would be here, above
      // the burger: no card, no section header and no category chip.
      expect(find.text('Bunless Burger'), findsOneWidget);
      expect(find.byType(DishCard), findsWidgets);
      expect(find.text(_noticeName), findsNothing);
      expect(find.text(_noticeHeading), findsNothing);
      expect(
        find.descendant(
          of: find.byType(CategoryChips),
          matching: find.text('Burgers'),
        ),
        findsOneWidget,
      );
      expect(find.text(_en.menuShowingAll(2)), findsOneWidget);

      // Act: the list is lazy, so scroll to the second dish.
      await tester.scrollUntilVisible(
        find.text('Chicken Salad'),
        200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();

      // Assert: the second dish is there and the notice still is not.
      expect(find.text('Chicken Salad'), findsOneWidget);
      expect(find.text(_noticeName), findsNothing);

      // Act: scroll back to the one quiet line that names the notice,
      // and open it.
      final noticesLine = find.text(_en.menuRestaurantNotices(1));
      await tester.scrollUntilVisible(noticesLine, -200, scrollable: _menuList);
      await tester.pumpAndSettle();
      expect(find.byType(RestaurantNoticesRow), findsOneWidget);
      await tapAndSettle(tester, noticesLine);

      // Assert: the restaurant's own words are shown, not as a dish card.
      expect(find.text(_noticeName), findsOneWidget);
      expect(find.text(_noticeText), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DishCard),
          matching: find.text(_noticeName),
        ),
        findsNothing,
      );
    });
  });
}
