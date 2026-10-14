// The chef card for one dish (Banto, ALG-08b, issue #350): the page in
// the menu's language with the profile's strict lines, the dish, its
// questions and, when the kitchen threatens a strict entry, the
// cross-contact line; and the Waiter Card's action that opens it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/chef_card_screen.dart';
import 'package:ketoclub/screens/waiter_card_sheet.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/utils/allergens/kitchen_signals.dart';

import '../fakes/fake_menu_sharer.dart';
import '../fakes/fake_screen_brightness.dart';

final AppLocalizations _en = AppLocalizationsEn();

const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

final DietaryProfile _sesame = DietaryProfile.empty.withEntry(
  RestrictionId.sesame,
);

Dish _dish(String id, String name) => Dish(
  id: id,
  name: name,
  description: '',
  price: 30,
  options: const <DishOption>[],
);

/// The tahini salad: sesame stated in its name.
final Dish _salad = _dish('salad', 'סלט עם טחינה');

/// A menu holding [dishes].
Menu _menu(List<Dish> dishes) => Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(id: 'c', name: 'מנות', dishes: dishes),
  ],
);

/// [dish] green from the model.
AnalysedDish _green(Dish dish) => AnalysedDish(
  dishId: dish.id,
  name: dish.name,
  verdict: DishVerdict.orderAsIs,
  why: 'Nothing starchy.',
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final copied = <String>[];

  setUp(() {
    copied.clear();
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<Object?, Object?>;
            copied.add(args['text']! as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('ChefCardScreen for a dish', () {
    testWidgets('a Hebrew dish opens in Hebrew under an English app, with '
        'the sesame line, the dish, its question and the cross-contact '
        'line', (tester) async {
      // Arrange: the tahini on the menu is itself a sesame signal.
      final menu = _menu(<Dish>[_salad]);
      expect(
        ChefCardText.kitchenThreatensStrict(KitchenSignals.of(menu), _sesame),
        isTrue,
      );

      // Act
      await _pump(
        tester,
        ChefCardScreen(
          profile: _sesame,
          dish: _salad,
          analysed: _green(_salad),
          menu: menu,
        ),
      );

      // Assert
      expect(
        find.text(
          'יש לי אלרגיה לשומשום — נא לבדוק כל מרכיב, '
          'כולל רטבים, שמנים וקישוטים.',
        ),
        findsOneWidget,
      );
      expect(find.text('המנה שאני רוצה להזמין: סלט עם טחינה'), findsOneWidget);
      expect(find.text('אפשר להכין את המנה בלי שומשום?'), findsOneWidget);
      expect(
        find.text(ChefCardText.compose(_sesame, hebrew: true).last),
        findsOneWidget,
      );
      expect(find.text(_en.helperToolSentence), findsOneWidget);
    });

    testWidgets('the toggle re-composes the dish card in English', (
      tester,
    ) async {
      // Arrange
      await _pump(
        tester,
        ChefCardScreen(
          profile: _sesame,
          dish: _salad,
          analysed: _green(_salad),
          menu: _menu(<Dish>[_salad]),
        ),
      );

      // Act
      await tester.tap(find.text(_en.settingsLanguageEnglish));
      await tester.pumpAndSettle();

      // Assert: the dish keeps its printed name; the question follows.
      expect(find.text('The dish I would like: סלט עם טחינה'), findsOneWidget);
      expect(find.text('Can this be made without sesame?'), findsOneWidget);
      expect(find.text('אפשר להכין את המנה בלי שומשום?'), findsNothing);
    });

    testWidgets('closes with thanks when no kitchen signal threatens the '
        'profile', (tester) async {
      // Arrange: a steak on a menu with no sesame, fryer or bakery.
      final steak = _dish('steak', 'סטייק אנטריקוט');
      final menu = _menu(<Dish>[steak]);
      expect(
        ChefCardText.kitchenThreatensStrict(KitchenSignals.of(menu), _sesame),
        isFalse,
      );

      // Act
      await _pump(
        tester,
        ChefCardScreen(
          profile: _sesame,
          dish: steak,
          analysed: _green(steak),
          menu: menu,
        ),
      );

      // Assert: no sesame concern, so no question; plain thanks.
      expect(find.text('תודה.'), findsOneWidget);
      expect(
        find.text(ChefCardText.compose(_sesame, hebrew: true).last),
        findsNothing,
      );
    });

    testWidgets('Copy and Share carry the whole dish card', (tester) async {
      // Arrange
      final sharer = FakeMenuSharer();
      final menu = _menu(<Dish>[_salad]);
      await _pump(
        tester,
        ChefCardScreen(
          profile: _sesame,
          dish: _salad,
          analysed: _green(_salad),
          menu: menu,
          menuSharer: sharer,
        ),
      );
      final expected = ChefCardText.asText(
        ChefCardText.composeForDish(
          _sesame,
          dishName: _salad.name,
          modification: null,
          questions: const <String>['אפשר להכין את המנה בלי שומשום?'],
          crossContact: true,
          hebrew: true,
        ),
      );

      // Act
      await tester.ensureVisible(find.text(_en.waiterCardCopyButton));
      await tester.tap(find.text(_en.waiterCardCopyButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(chefCardShareKey));
      await tester.pumpAndSettle();

      // Assert
      expect(copied, <String>[expected]);
      expect(sharer.shareCalls.single.text, expected);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('the Waiter Card chef card action', () {
    testWidgets('opens the chef card for the dish above the Waiter Card', (
      tester,
    ) async {
      // Arrange
      final brightness = FakeScreenBrightness();
      final menu = _menu(<Dish>[_salad]);
      await _pump(
        tester,
        Scaffold(
          body: WaiterCardSheet(
            row: DishRow(dish: _salad, category: 'מנות'),
            screenBrightness: brightness,
            script: 'אפשר להכין את המנה בלי שומשום?',
            chefCard: (_) => ChefCardScreen(
              profile: _sesame,
              dish: _salad,
              analysed: _green(_salad),
              menu: menu,
            ),
          ),
        ),
      );

      // Act
      await tester.tap(find.byKey(waiterCardChefCardKey));
      await tester.pumpAndSettle();

      // Assert: the chef card is open; the Waiter Card's brightness was
      // raised once and is not restored under it.
      expect(find.byType(ChefCardScreen), findsOneWidget);
      expect(find.text(_en.chefCardTitle), findsOneWidget);
      expect(find.text('המנה שאני רוצה להזמין: סלט עם טחינה'), findsOneWidget);
      expect(brightness.raiseCount, 1);
      expect(brightness.restoreCount, 0);
    });

    testWidgets('is left out without a chef card', (tester) async {
      // Act
      await _pump(
        tester,
        Scaffold(
          body: WaiterCardSheet(
            row: DishRow(dish: _salad, category: 'מנות'),
            script: 'שאלה?',
          ),
        ),
      );

      // Assert
      expect(find.byKey(waiterCardChefCardKey), findsNothing);
      expect(find.text(_en.waiterCardChefCard), findsNothing);
    });
  });
}
