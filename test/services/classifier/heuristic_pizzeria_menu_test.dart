// The rule engine over a pizzeria's menu as Wolt lists it.
//
// The menu below is a cut of `dominos-pizza-ashdod-city`, whose Discovery
// card read "29 dishes as-is": one or two dishes of each shape that was
// wrongly green, with the real headings, names, descriptions and option
// groups, beside the dishes that were already right. It is built inline,
// not recorded: the full payload is 300 KB and only these shapes matter.

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/utils/dish_kind.dart';
import 'package:ketoclub/utils/verdict_counts.dart';

import '../../fakes/fake_clock.dart';

Dish _dish(
  String id,
  String name, {
  String description = '',
  List<DishOption> options = const <DishOption>[],
}) => Dish(
  id: id,
  name: name,
  description: description,
  price: 40,
  options: options,
);

/// The choice of dough on a family-size "MIX" pizza.
const DishOption _familyDough = DishOption(
  name: '\u202Bבחרו סוג בצק - MIX',
  values: <String>['בצק קלאסי', 'בצק קלאסי דק', 'צ׳יזי קראסט מוצרלה'],
);

/// The choice of dough on a personal "MIX" pizza.
const DishOption _personalDough = DishOption(
  name: 'בצק - אישית',
  values: <String>['בצק קלאסי'],
);

final Menu _pizzeria = Menu(
  venueRef: const VenueRef(
    source: MenuSource.wolt,
    platformId: 'dominos-pizza-ashdod-city',
  ),
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026, 11, 11),
  categories: <MenuCategory>[
    MenuCategory(
      id: 'mix',
      name: "\u{1F953} Domino's Mix",
      dishes: <Dish>[
        _dish(
          'mix-beef-family',
          '\u202Bבקרנה MIX משפחתית',
          description: "פרוסות חזה בקר, כדורי בייבי מוצרלה, גבינת פרמז'ן",
          options: const <DishOption>[_familyDough],
        ),
        _dish(
          'mix-carnivore-family',
          '\u202Bקרניבור MIX משפחתית',
          description: "פפרוני, קבנוס וחזה בקר. שמנו מעל: רוטב צ'יפוטלה",
          options: const <DishOption>[_familyDough],
        ),
        _dish(
          'mix-greek-personal',
          '\u202Bגריק MIX אישית',
          description: 'קוביות עגבניות, בצל סגול, זיתי קלמטה וגבינה בולגרית',
          options: const <DishOption>[_personalDough],
        ),
      ],
    ),
    MenuCategory(
      id: 'sides',
      name: '\u{1F32D} ליד הפיצה',
      dishes: <Dish>[
        _dish(
          'mozzarella-fingers',
          'אצבעות מוצרלה',
          description: 'אצבעות בצק וגבינה 100% מוצרלה + דיפ עגבניות ושום',
        ),
        _dish(
          'wings',
          'דומינו׳ס ווינגס',
          description: 'יחידות חצאי כנפיים מעולות ברוטב לבחירה',
          options: const <DishOption>[
            DishOption(
              name: 'בחרו רטבים לכנפיים',
              values: <String>['רוטב סוויט צ׳ילי אריזונה', 'ללא רוטב'],
            ),
          ],
        ),
        _dish(
          'chicken-chunks',
          "צ'יקן צ'אנקס",
          description: '4 יח׳ נתחי פילה עוף אפויים מצופים בפירורי לחם',
        ),
      ],
    ),
    MenuCategory(
      id: 'dips',
      name: '\u202Bדיפים ורטבים \u{1F36F}',
      dishes: <Dish>[
        _dish('dip-garlic', 'דיפ עגבניות שום'),
        _dish('dip-aioli', 'דיפ איולי שיפקה'),
        _dish('dip-hot', 'דיפ חריף'),
      ],
    ),
    MenuCategory(
      id: 'desserts',
      name: '\u202Bקינוחים \u{1F9C1}',
      dishes: <Dish>[
        _dish('fondant', 'פונדנט שוקולד', description: 'עוגת שוקולד חמה'),
      ],
    ),
    MenuCategory(
      id: 'ice-cream',
      name: '\u202Bגלידות \u{1F366}',
      dishes: <Dish>[
        _dish(
          'pint-vanilla',
          'פיינט וניל - 500 מ״ל',
          description: 'גלידת וניל משובחת',
        ),
      ],
    ),
  ],
);

void main() {
  group('HeuristicMenuClassifier over a pizzeria menu', () {
    late MenuAnalysed analysis;
    late Map<String, DishVerdict> verdicts;

    setUp(() async {
      final classifier = HeuristicMenuClassifier(
        clock: FakeClock(DateTime.utc(2026, 11, 11)),
      );
      analysis = await classifier.classify(_pizzeria) as MenuAnalysed;
      verdicts = <String, DishVerdict>{
        for (final dish in analysis.dishes) dish.dishId: dish.verdict,
      };
    });

    test('counts one dish as-is — the wings — where it counted ten', () {
      // Act
      final counts = VerdictCounts.of(_pizzeria, analysis);
      // Assert: before the fix the three pizzas, the dough fingers, the
      // three dips, the fondant and the ice cream were all green too.
      expect(counts.green, 1);
      expect(verdicts['wings'], DishVerdict.orderAsIs);
      expect(counts.yellow, 0);
      expect(counts.red, 7);
    });

    test('a pizza named by its toppings is red, and says dough is why', () {
      // Act
      final pizza = analysis.dishes.firstWhere(
        (dish) => dish.dishId == 'mix-beef-family',
      );
      // Assert
      expect(pizza.verdict, DishVerdict.nonKeto);
      expect(pizza.why, contains('בצק'));
      expect(verdicts['mix-carnivore-family'], DishVerdict.nonKeto);
      expect(verdicts['mix-greek-personal'], DishVerdict.nonKeto);
    });

    test('dough fingers, a cake and an ice cream are red', () {
      // Assert
      expect(verdicts['mozzarella-fingers'], DishVerdict.nonKeto);
      expect(verdicts['fondant'], DishVerdict.nonKeto);
      expect(verdicts['pint-vanilla'], DishVerdict.nonKeto);
    });

    test('the dips are extras: still classified, never counted', () {
      // Act
      final kinds = dishKindsOf(_pizzeria);
      // Assert
      for (final id in <String>['dip-garlic', 'dip-aioli', 'dip-hot']) {
        expect(kinds[id], DishKind.extra, reason: id);
        expect(verdicts[id], DishVerdict.orderAsIs, reason: id);
      }
    });
  });
}
