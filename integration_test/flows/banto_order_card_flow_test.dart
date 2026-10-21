// Flow test (FLOW_TEST_CONVENTIONS.md; Banto, issue #418): a person with a
// sesame profile opens a Hebrew Wolt menu, adds two dishes to "My order"
// from their cards, and the floating "My order · 2" pill opens the order
// card: both dishes by their printed names, the burger's question about
// its bun in Hebrew, and the sesame allergy note once — not once per dish.
// The effect spans Explore, the menu's cards, the pill and the full-screen
// card, which is why this is a flow and not a widget test.
//
// The menu's two dishes are copied verbatim (id, name, description,
// category) from the recorded Hebrew Wolt payload,
// `test/fixtures/wolt_hamosad_menu.json`: a flow test also runs on the
// web, where it cannot read a file, so the dishes are inline here and
// `order_card_text_test.dart` reads the recording itself.
//
// The whole app is pumped with `bantoMode: true`, so it runs under
// `flutter test` with no `--dart-define`. The classifier answers every
// dish green from the language model: the questions are the device's own.

import 'package:flutter/material.dart';
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
import 'package:ketoclub/screens/menu_screen.dart';
import 'package:ketoclub/screens/order_card_screen.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/widgets/dish_card.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Wolt venue page the user pastes.
const String _woltUrl = 'https://wolt.com/en/isr/tel-aviv/restaurant/hamosad';

/// The [VenueRef] [_woltUrl] resolves to.
const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'hamosad');

/// "המבורגר טראמפ", as recorded: a bun (בלחמנייה), so sesame is asked.
const Dish _burger = Dish(
  id: '61ecfdac853cef6ba4d5e3ee',
  name: 'המבורגר טראמפ',
  description:
      'שף דן יושע\n'
      'קציצת בקר עסיסית שנטחנת כל בוקר מנתחים מובחרים, בלחמנייה רכה עם חסה '
      'אמריקאית, עגבנייה, איולי וויסקי תוצרת הבית, ביצת עין, אווז צלוי '
      'וטבעת בצל קריספית בטמפורה\n'
      '*ביצת עין עשויה במשלוחים\n'
      '\n'
      '100% בשר בקר ישראלי מובחר מפרות הולשטיין, בלנד נתחים טריים ומיושנים '
      'שנטחנים במקום ליצירת קציצה עסיסית, עמוקה ומדויקת בטעם.',
  price: 62,
  options: <DishOption>[],
);

/// "צ'יפס", as recorded.
const Dish _fries = Dish(
  id: '61ecfdac853cef6ba4d5e3f6',
  name: "צ'יפס",
  description: "קריספי צ'יפס של המוסד",
  price: 19,
  options: <DishOption>[],
);

/// The menu the repository serves for [_ref].
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[
    MenuCategory(
      id: 'burgers',
      name: '\u202Bהמבורגר שף 🍔',
      dishes: <Dish>[_burger],
    ),
    MenuCategory(id: 'snacks', name: 'נשנושים', dishes: <Dish>[_fries]),
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

/// The burger's question, in the menu's language.
const String _bunQuestion = "בתפריט כתוב 'בלחמנייה' — האם יש בזה שומשום?";

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

/// The "Add to my order" toggle on [dish]'s card.
Finder _toggleOf(Dish dish) => find.descendant(
  of: find.ancestor(of: find.text(dish.name), matching: find.byType(DishCard)),
  matching: find.byKey(dishOrderToggleKey),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Banto order card flow', () {
    testWidgets('two dishes added from a Hebrew Wolt menu under a sesame '
        'profile show on one order card with one allergy note', (tester) async {
      // Setup
      final fakes = FakeAppDependencies();
      fakes.repository.stub(_ref, MenuFetched(menu: _menu));
      fakes.classifier.respondWith(_analysis);
      await fakes.settingsStore.write(
        AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
        ),
      );
      await tester.pumpWidget(
        KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
      );
      await tester.pumpAndSettle();

      // Act: on Explore, paste the link and open the venue.
      await enterText(tester, _woltUrl);
      await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

      // Act: add the burger and the fries to the order.
      for (final dish in <Dish>[_burger, _fries]) {
        await tester.scrollUntilVisible(
          _toggleOf(dish),
          200,
          scrollable: _menuList,
        );
        await tester.pumpAndSettle();
        await tapAndSettle(tester, _toggleOf(dish));
      }

      // Assert: the pill counts both.
      expect(find.text(_en.orderPill(2)), findsOneWidget);

      // Act: open the order card.
      await tapAndSettle(tester, find.byKey(menuOrderPillKey));

      // Assert: both dishes as printed, the burger's question in Hebrew,
      // and the sesame note once.
      final card = find.byType(OrderCardScreen);
      expect(card, findsOneWidget);
      Finder onCard(Finder finder) =>
          find.descendant(of: card, matching: finder);
      expect(onCard(find.text(_burger.name)), findsOneWidget);
      expect(onCard(find.text(_fries.name)), findsOneWidget);
      expect(onCard(find.text(_bunQuestion)), findsOneWidget);
      expect(onCard(find.byKey(orderCardAllergyKey)), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(orderCardAllergyKey)).data,
        startsWith('יש לי אלרגיה לשומשום.'),
      );
      final texts = tester
          .widgetList<Text>(onCard(find.byType(Text)))
          .map((widget) => widget.data ?? '');
      expect(
        texts.where((text) => text.contains('יש לי אלרגיה')),
        hasLength(1),
      );
    });
  });
}
