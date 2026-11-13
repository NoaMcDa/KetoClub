/// The rule engine on menu lines that only their heading or their option
/// groups explain (issues #472, #474, #475): drinks under a beer or juice
/// heading, non-edible lines and notices named as such, and upsell
/// option groups.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/utils/classification_rules.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/dish_kind.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// A fixed clock: the analysis time is not under test.
final class _FixedClock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026);
}

/// A dish named [name] priced [price], with [options].
Dish _dish(
  String id,
  String name, {
  double price = 30,
  List<DishOption> options = const [],
}) => Dish(id: id, name: name, description: '', price: price, options: options);

/// A menu of one category [heading] holding [dishes].
Menu _menu(String heading, List<Dish> dishes) => Menu(
  venueRef: const VenueRef(source: MenuSource.wolt, platformId: 'v'),
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: [MenuCategory(id: 'c', name: heading, dishes: dishes)],
);

/// The verdict of each dish of a one-category menu, by dish name.
Future<Map<String, DishVerdict>> _verdicts(
  String heading,
  List<String> names,
) async {
  final dishes = [
    for (final (index, name) in names.indexed) _dish('d$index', name),
  ];
  final result = await HeuristicMenuClassifier(
    clock: _FixedClock(),
  ).classify(_menu(heading, dishes)) as MenuAnalysed;
  return {for (final dish in result.dishes) dish.name: dish.verdict};
}

void main() {
  group('drinks under a beer or juice heading (issue #474)', () {
    test('a beer named by its brand is red under a beer heading', () async {
      final verdicts = await _verdicts('בירות', [
        'היינקן בקבוק 330 מ"ל',
        'פאולנר',
        'הרצל- שש אחוז כפרה',
      ]);
      expect(verdicts.values, everyElement(DishVerdict.nonKeto));
    });

    test('a fruit under a juice heading is red', () async {
      final verdicts = await _verdicts('מיצים טבעיים', [
        'תפוז',
        'תפוח פסיפלורה',
        'תפוזים סחוט במקום',
      ]);
      expect(verdicts.values, everyElement(DishVerdict.nonKeto));
    });

    test('wine, water, spirits and a zero drink stay as they are', () async {
      final verdicts = await _verdicts('בירות ויין', [
        'יין אדום יבש',
        'מים מינרלים',
        'וודקה',
        'בירה זירו',
      ]);
      expect(verdicts.values, everyElement(DishVerdict.orderAsIs));
    });

    test('a food word in the heading decides nothing', () async {
      final verdicts = await _verdicts('Beers & Burgers', ['Hazy IPA']);
      expect(verdicts['Hazy IPA'], DishVerdict.orderAsIs);
    });

    test('Fuze tea, Tropit, lemonade of the house and flavoured water '
        'are red under any heading', () async {
      final verdicts = await _verdicts('שתייה קלה', [
        'פיוז טי אפרסק',
        'פיוזטי',
        'טרופית',
        'לימונדת הבית',
        'מים בטעם ענבים',
        'גולדסטאר',
        'Fuze tea peach',
      ]);
      expect(verdicts.values, everyElement(DishVerdict.nonKeto));
    });

    test('headingDrinkBase names the heading in its language', () {
      expect(
        headingDrinkBase(category: 'Beers', dish: _dish('a', 'Blue Moon')),
        'beer',
      );
      expect(
        headingDrinkBase(category: 'מיצים', dish: _dish('a', 'רימון')),
        'מיץ',
      );
      expect(
        headingDrinkBase(category: 'עיקריות', dish: _dish('a', 'סטייק')),
        isNull,
      );
    });
  });

  group('non-edible lines and notices (issue #472)', () {
    DishKind kind(String heading, String name, {double price = 5}) =>
        dishKindOf(
          category: heading,
          dish: _dish('a', name, price: price),
        );

    test('cutlery, candles and cards are extras under any heading', () {
      for (final name in [
        'סכו"ם חד"פ 🍴',
        'סכו״ם | צ׳ופסטיקס',
        'מזלג חד"פ',
        'כף חד"פ',
        "סט צ'ופסטיקס ומפית",
        'נר מספר 5',
        'נר HAPPY BIRTHDAY',
        'כרטיס ברכה Thank You',
        'Cutlery',
        'Birthday candles',
        'Sparklers',
      ]) {
        expect(kind('Mains', name), DishKind.extra, reason: name);
      }
    });

    test('a real dish that only sounds like one stays food', () {
      expect(kind('Mains', 'קציצות בטעם של ברכה'), DishKind.food);
      expect(kind('Mains', 'Candlelight dinner for two'), DishKind.food);
    });

    test('the headings real menus use are read', () {
      expect(categoryKindOf('הודעות חשובות 💚'), DishKind.notice);
      expect(categoryKindOf('💗 לתשומת לבכם 💗'), DishKind.notice);
      expect(categoryKindOf('Notices'), DishKind.notice);
      expect(categoryKindOf('נרות יום הולדת'), DishKind.extra);
      expect(categoryKindOf('ברכה להזמנה 💌'), DishKind.extra);
      expect(categoryKindOf('מספר סועדים'), DishKind.extra);
    });

    test('a notice named in its plural or feminine form, at no price', () {
      expect(
        kind('Mains', 'הערה חשובה! נשים בהיריון', price: 0),
        DishKind.notice,
      );
      expect(kind('Mains', 'אלרגנים', price: 0), DishKind.notice);
    });
  });

  group('upsell option groups (issue #475)', () {
    test('a paid-extras group adds no instruction', () {
      expect(
        ClassificationRules.matchDish(
          _dish(
            'a',
            'שמנת קשיו',
            options: const [
              DishOption(
                name: 'תוספות בתשלום',
                values: ['קוקוט ויניגרט פסיפלורה', 'מנת לחם (4 פרוסות)'],
              ),
            ],
          ),
        ).instructions,
        isEmpty,
      );
    });

    test('an add-a-drink group adds no instruction', () {
      for (final name in ['תרצו להוסיף שתייה?', 'Add a drink?']) {
        expect(
          ClassificationRules.matchDish(
            _dish(
              'a',
              'Grilled chicken',
              options: [
                DishOption(name: name, values: const ['Coca-Cola', 'Fanta']),
              ],
            ),
          ).instructions,
          isEmpty,
          reason: name,
        );
      }
    });

    test('a discount group adds no instruction', () {
      expect(
        ClassificationRules.matchDish(
          _dish(
            'a',
            'Tuna salad',
            options: const [
              DishOption(
                name: 'A small discount 😉',
                values: ['Arnold Palmer | half iced tea half lemonade'],
              ),
            ],
          ),
        ).instructions,
        isEmpty,
      );
    });

    test('a required choice of side still counts', () {
      expect(
        ClassificationRules.matchDish(
          _dish(
            'a',
            'סטייק',
            options: const [
              DishOption(name: 'בחרו תוספת', values: ["צ'יפס", 'סלט']),
            ],
          ),
        ).instructions,
        [carbModifiersHe["צ'יפס"]],
      );
      expect(TextNormaliser.isAddOnOptionGroup('בחרו תוספת'), isFalse);
      expect(TextNormaliser.isAddOnOptionGroup('Choice of side'), isFalse);
      expect(TextNormaliser.isAddOnOptionGroup('תוספות'), isFalse);
    });
  });
}
