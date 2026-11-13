/// The rule engine's false reds (issue #273) and false greens (issue
/// #274): keto-safe dishes the vocabulary used to hide, and carb dishes
/// it used to call order-as-is.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/utils/classification_rules.dart';
import 'package:ketoclub/utils/constants.dart';

/// Asserts [result] is green: no base and no waiter sentence.
void _expectGreen(RuleMatch result) {
  expect(result.isNonKeto, isFalse, reason: '$result');
  expect(result.instructions, isEmpty, reason: '$result');
}

/// Asserts [result] is red, labelled [label] when one is given.
void _expectRed(RuleMatch result, {String? label}) {
  expect(result.isNonKeto, isTrue, reason: '$result');
  if (label != null) expect(result.baseLabel, label);
}

/// Asserts [result] is yellow with exactly [sentences].
void _expectYellow(RuleMatch result, List<String?> sentences) {
  expect(result.isNonKeto, isFalse, reason: '$result');
  expect(result.instructions, sentences);
}

/// A dish for the name-scoped checks (issues #273, #274).
Dish _dishNamed(String name, {String description = ''}) => Dish(
  id: 'd',
  name: name,
  description: description,
  price: 10,
  options: const [],
);

void main() {
  group('ClassificationRules — false reds (issue #273)', () {
    test('lemon or lime juice is a seasoning, not a drink', () {
      _expectGreen(
        ClassificationRules.match('Grilled salmon, olive oil, lemon juice'),
      );
      _expectGreen(ClassificationRules.match('Ceviche with fresh lime juice'));
      _expectGreen(ClassificationRules.match('דג עם מיץ לימון'));
      _expectGreen(ClassificationRules.match('סלמון עם מיץ ליים ושמן זית'));
    });

    test('a juice in a dressing is a seasoning, not a drink', () {
      _expectGreen(
        ClassificationRules.match('Green salad with orange juice dressing'),
      );
      _expectGreen(ClassificationRules.match('Tomato salad, juice dressing'));
      _expectGreen(ClassificationRules.match('סלט ירוק ברוטב מיץ תפוזים'));
      _expectGreen(ClassificationRules.match('עוף במרינדה מיץ ענבים'));
    });

    test('a glass of juice is still red', () {
      _expectRed(ClassificationRules.match('Fresh orange juice'));
      _expectRed(ClassificationRules.match('Apple juice'));
      _expectRed(ClassificationRules.match('מיץ תפוזים סחוט'));
      _expectRed(ClassificationRules.match('מיץ ענבים'));
    });

    test('bare קריספי is not a red base', () {
      _expectGreen(ClassificationRules.match('סלמון עם עור קריספי'));
      _expectGreen(ClassificationRules.match('בייקון קריספי'));
      _expectGreen(ClassificationRules.match('Salmon with crispy skin'));
      _expectGreen(ClassificationRules.match('Crispy bacon'));
    });

    test('crispy chicken is the breaded dish, crispy skin is not', () {
      _expectRed(ClassificationRules.match('Crispy chicken burger'));
      _expectRed(ClassificationRules.match("קריספי צ'יקן בלחמנייה רכה"));
      _expectRed(ClassificationRules.match('חזה עוף קריספי'));
      _expectGreen(ClassificationRules.match('Crispy chicken skin'));
    });

    test('truffle-parmesan fries are the carb itself, so red', () {
      // The real hamosad dish: once bare קריספי stopped making it red, a
      // fries dish was told to swap its chips.
      _expectRed(
        ClassificationRules.matchDish(
          _dishNamed(
            "צ'יפס פרמז'ן כמהין",
            description: "קריספי צ'יפס מוקפץ בשמן כמהין פלפל שחור ופרמז'ן",
          ),
        ),
        label: "צ'יפס",
      );
      _expectRed(
        ClassificationRules.matchDish(
          _dishNamed(
            'Truffle parmesan fries',
            description: 'Crispy fries, truffle oil and parmesan',
          ),
        ),
        label: 'fries',
      );
    });

    test('a topping is not a filling, but a real filling still is', () {
      _expectYellow(
        ClassificationRules.matchDish(
          _dishNamed('Pita', description: 'Grilled chicken, garlic, parmesan'),
        ),
        [carbModifiersEn['pita']],
      );
      _expectYellow(
        ClassificationRules.matchDish(
          _dishNamed('פיתה', description: 'פלפל קלוי ושום'),
        ),
        [carbModifiersHe['פיתה']],
      );
    });

    test("a cheese after צ'יפס is a topping, before it a parmesan crisp", () {
      _expectYellow(ClassificationRules.match("המבורגר עם צ'יפס פרמזן"), [
        carbModifiersHe['המבורגר'],
        carbModifiersHe["צ'יפס"],
      ]);
      expect(ClassificationRules.match("עוף עם צ'יפס גבינה").instructions, [
        carbModifiersHe["צ'יפס"],
      ]);
      _expectGreen(ClassificationRules.match("סלט עם פרמזן צ'יפס"));
      _expectGreen(ClassificationRules.match("סלט עם גבינה צ'יפס"));
      _expectGreen(ClassificationRules.match('Salad with parmesan chips'));
    });

    test("a vegetable still rescues צ'יפס from either side", () {
      _expectGreen(ClassificationRules.match("עוף עם צ'יפס קישואים"));
      _expectGreen(ClassificationRules.match("עוף עם קייל צ'יפס"));
    });

    test('a crispy coating is still red, in both languages', () {
      _expectRed(ClassificationRules.match('Chicken in a crispy coating'));
      _expectRed(ClassificationRules.match('עוף בציפוי קריספי'));
    });

    test('a keto substitute anywhere in the name rescues pizza', () {
      _expectGreen(ClassificationRules.match('Pizza with cauliflower crust'));
      _expectGreen(ClassificationRules.match('פיצה על בסיס כרובית'));
      _expectGreen(
        ClassificationRules.matchDish(
          _dishNamed(
            'Pizza with cauliflower crust',
            description: 'Tomato, mozzarella and basil',
          ),
        ),
      );
      _expectGreen(
        ClassificationRules.matchDish(
          _dishNamed(
            'פיצה על בסיס כרובית',
            description: 'עגבניות, מוצרלה ובזיליקום',
          ),
        ),
      );
    });

    test('a keto name rescues a base the description names', () {
      _expectGreen(
        ClassificationRules.matchDish(
          _dishNamed('Keto margherita', description: 'Thin pizza, basil'),
        ),
      );
      _expectGreen(
        ClassificationRules.matchDish(
          _dishNamed('מרגריטה קטו', description: 'פיצה דקה, בזיליקום'),
        ),
      );
    });

    test('the name-wide guard never reads the description', () {
      _expectRed(
        ClassificationRules.matchDish(
          _dishNamed(
            'Margherita',
            description: 'Classic pizza. Cauliflower crust on request',
          ),
        ),
      );
      _expectRed(
        ClassificationRules.matchDish(
          _dishNamed(
            'מרגריטה',
            description: 'פיצה קלאסית. בסיס כרובית לפי בקשה',
          ),
        ),
      );
    });

    test('a bare vegetable far from the base still rescues nothing', () {
      _expectYellow(
        ClassificationRules.match('Chicken with rice and roasted cauliflower'),
        [carbModifiersEn['rice']],
      );
      _expectYellow(ClassificationRules.match('עוף עם אורז לבן וירקות'), [
        carbModifiersHe['אורז'],
      ]);
      _expectRed(ClassificationRules.match('Pasta with zucchini'));
      _expectRed(ClassificationRules.match('פסטה ברוטב שמנת ופטריות'));
    });

    test('pasta has the same keto-substitute guard as noodles', () {
      _expectGreen(ClassificationRules.match('Zucchini pasta'));
      _expectGreen(ClassificationRules.match('Shirataki pasta'));
      _expectGreen(ClassificationRules.match('Zucchini noodles'));
      _expectGreen(ClassificationRules.match('פסטת קישואים'));
      _expectGreen(ClassificationRules.match('פסטה שיראטקי'));
      _expectGreen(ClassificationRules.match('נודלס קישואים'));
    });

    test('חלבה with a מ prefix is מחלבה, a dairy', () {
      _expectGreen(ClassificationRules.match('גבינה מחלבה'));
      _expectGreen(ClassificationRules.match('גבינות מהחלבה של הכפר'));
      _expectGreen(ClassificationRules.match('Cheese from the village dairy'));
    });

    test('halva itself is still red, with its common particles', () {
      _expectRed(ClassificationRules.match('פרפה חלבה'), label: 'חלבה');
      _expectRed(ClassificationRules.match('פרפה וניל וחלבה'), label: 'חלבה');
      _expectRed(ClassificationRules.match('עוגיות בחלבה'));
      _expectRed(ClassificationRules.match('Halva parfait'));
    });

    test('בלילה ("at night") is not a base; בבלילה ("in batter") is', () {
      _expectGreen(ClassificationRules.match('מרק חם שמוגש בלילה'));
      _expectGreen(ClassificationRules.match('Hot soup served at night'));
      _expectRed(ClassificationRules.match('דג בבלילה'), label: 'בלילה');
      _expectRed(ClassificationRules.match('Battered fish'));
    });

    test('beer cooked into a dish is not the drink', () {
      _expectGreen(ClassificationRules.match('Beer-braised short rib'));
      _expectGreen(ClassificationRules.match('Short rib braised in stout'));
      _expectGreen(ClassificationRules.match('צלע בקר מבושלת בבירה'));
      _expectGreen(ClassificationRules.match('אסאדו ברוטב בירה'));
    });

    test('a port wine reduction is yellow, not red', () {
      _expectYellow(ClassificationRules.match('Port wine reduction'), [
        carbModifiersEn['port wine reduction'],
      ]);
      _expectYellow(
        ClassificationRules.match('Duck breast, port wine reduction'),
        [carbModifiersEn['port wine reduction']],
      );
      _expectYellow(ClassificationRules.match('חזה ברווז ברוטב יין פורט'), [
        carbModifiersHe['רוטב יין פורט'],
      ]);
    });

    test('a glass of beer or port is still red', () {
      _expectRed(ClassificationRules.match('Draft beer'));
      _expectRed(ClassificationRules.match('Glass of port wine'));
      _expectRed(ClassificationRules.match('בירה מהחבית'));
    });

    test('corn-fed names the feed, not a side of corn', () {
      _expectGreen(ClassificationRules.match('Corn-fed chicken'));
      _expectGreen(ClassificationRules.match('עוף מוזן תירס'));
    });

    test('baby corn is still a trap', () {
      _expectYellow(ClassificationRules.match('Baby corn stir fry'), [
        carbModifiersEn['corn'],
      ]);
      _expectYellow(ClassificationRules.match('סלט עם תירס'), [
        carbModifiersHe['תירס'],
      ]);
    });

    test('rice vinegar is a vinegar', () {
      _expectGreen(
        ClassificationRules.match('Cucumber salad with rice vinegar dressing'),
      );
      _expectGreen(ClassificationRules.match('סלט מלפפונים ברוטב חומץ אורז'));
    });

    test('rice itself is still yellow', () {
      _expectYellow(ClassificationRules.match('Chicken with rice'), [
        carbModifiersEn['rice'],
      ]);
      _expectYellow(ClassificationRules.match('עוף עם אורז'), [
        carbModifiersHe['אורז'],
      ]);
    });
  });

  group('ClassificationRules — false greens (issue #274)', () {
    test('English bases match their regular plurals and compounds', () {
      const dishes = <String, String>{
        'Steamed dumplings': 'dumpling',
        'New York cheesecake': 'cheesecake',
        'Vanilla cupcakes': 'cupcake',
        'Fish tacos': 'taco',
        'Beef burritos': 'burrito',
        'Butter croissants': 'croissant',
        'Sesame bagels': 'bagel',
        'Glazed donuts': 'donut',
        'Walnut brownies': 'brownie',
        'Oatmeal cookies': 'cookie',
        'Sweet crepes': 'crepe',
        'Beef empanadas': 'empanada',
        'Potato croquettes': 'croquette',
        'Cheese blintzes': 'blintz',
      };
      for (final entry in dishes.entries) {
        _expectRed(ClassificationRules.match(entry.key), label: entry.value);
      }
    });

    test('a plural keeps its singular guard and label', () {
      _expectGreen(ClassificationRules.match('Cauliflower pizzas'));
      _expectGreen(ClassificationRules.match('Zucchini noodles'));
      _expectGreen(ClassificationRules.match('Egg muffins with spinach'));
      _expectRed(ClassificationRules.match('Pizzas'), label: 'pizza');
      _expectRed(ClassificationRules.match('Noodles'), label: 'noodles');
    });

    test('a plural is never a substring match', () {
      _expectGreen(ClassificationRules.match('Grilled tartare'));
      _expectGreen(ClassificationRules.match('Caked salt crust fish'));
    });

    test('Hebrew construct forms of cake and cookie are red', () {
      _expectRed(ClassificationRules.match('עוגת שוקולד'), label: 'עוגה');
      _expectRed(ClassificationRules.match('עוגת גבינה'), label: 'עוגה');
      _expectRed(
        ClassificationRules.match("עוגיית שוקולד צ'יפס"),
        label: 'עוגיה',
      );
      _expectRed(ClassificationRules.match('עוגות הבית'));
      _expectRed(ClassificationRules.match('Carrot cake'), label: 'cake');
      _expectRed(ClassificationRules.match('Chocolate chip cookie'));
    });

    test('the plural pitas and tortillas carry their sentence', () {
      _expectYellow(ClassificationRules.match('שווארמה בפיתות'), [
        carbModifiersHe['פיתה'],
      ]);
      _expectYellow(ClassificationRules.match('עוף בטורטיות'), [
        carbModifiersHe['טורטייה'],
      ]);
      _expectYellow(ClassificationRules.match('Shawarma in pita'), [
        carbModifiersEn['pita'],
      ]);
    });

    test('pitas or tortillas named alone are the carb itself', () {
      _expectRed(
        ClassificationRules.matchDish(_dishNamed('פיתות')),
        label: 'פיתות',
      );
      _expectRed(
        ClassificationRules.matchDish(_dishNamed('טורטיות')),
        label: 'טורטיות',
      );
    });

    test('lentil soup is red', () {
      _expectRed(ClassificationRules.match('Lentil soup'));
      _expectRed(ClassificationRules.match('מרק עדשים'));
    });

    test('cranberry sauce is yellow with one sentence', () {
      _expectYellow(ClassificationRules.match('Turkey with cranberry sauce'), [
        carbModifiersEn['cranberry sauce'],
      ]);
      _expectYellow(ClassificationRules.match('הודו עם רוטב חמוציות'), [
        carbModifiersHe['רוטב חמוציות'],
      ]);
    });

    test('hash browns and onion rings are a removable side', () {
      _expectYellow(ClassificationRules.match('Eggs with hash browns'), [
        carbModifiersEn['hash browns'],
      ]);
      _expectYellow(ClassificationRules.match('ביצים עם האש בראון'), [
        carbModifiersHe['האש בראון'],
      ]);
      _expectYellow(ClassificationRules.match('Steak with onion rings'), [
        carbModifiersEn['onion rings'],
      ]);
      _expectYellow(ClassificationRules.match('סטייק עם טבעות בצל'), [
        carbModifiersHe['טבעות בצל'],
      ]);
    });

    test('hash browns, onion rings or naan named alone are red', () {
      for (final name in [
        'Hash browns',
        'האש בראון',
        'Onion rings',
        'טבעות בצל',
        'Naan',
        'נאן',
        'Flatbread',
      ]) {
        _expectRed(ClassificationRules.matchDish(_dishNamed(name)));
      }
    });

    test('naan and flatbread carry a dish like a pita', () {
      _expectYellow(ClassificationRules.match('Butter chicken with naan'), [
        carbModifiersEn['naan'],
      ]);
      _expectYellow(ClassificationRules.match('עוף בחמאה עם נאן'), [
        carbModifiersHe['נאן'],
      ]);
      _expectYellow(ClassificationRules.match('Lamb on flatbread'), [
        carbModifiersEn['flatbread'],
      ]);
      _expectYellow(ClassificationRules.match('טלה על לחם שטוח'), [
        carbModifiersHe['לחם'],
      ]);
    });

    test('nachos are red', () {
      _expectRed(ClassificationRules.match('Loaded nachos'));
      _expectRed(ClassificationRules.match("נאצ'וס עם גבינה"));
    });

    test('sushi and nigiri are rice dishes, sashimi is not', () {
      _expectRed(ClassificationRules.match('Salmon sushi'));
      _expectRed(ClassificationRules.match('Salmon nigiri'));
      _expectRed(ClassificationRules.match('Spicy tuna maki'));
      _expectRed(ClassificationRules.match('סושי סלמון'));
      _expectRed(ClassificationRules.match('ניגירי סלמון'));
      _expectGreen(ClassificationRules.match('Salmon sashimi'));
      _expectGreen(ClassificationRules.match('סשימי סלמון'));
    });

    test('sushi-grade fish is raw fish', () {
      _expectGreen(ClassificationRules.match('Sushi-grade tuna tartare'));
      _expectGreen(ClassificationRules.match('טונה באיכות סושי'));
    });

    test('tiramisu and crème brûlée are red', () {
      _expectRed(ClassificationRules.match('Tiramisu'));
      _expectRed(ClassificationRules.match('טירמיסו'));
      _expectRed(ClassificationRules.match('Crème brûlée'));
      _expectRed(ClassificationRules.match('Creme brulee'));
      _expectRed(ClassificationRules.match('קרם ברולה'));
    });

    test('fried and popcorn chicken are red', () {
      _expectRed(ClassificationRules.match('Korean fried chicken'));
      _expectRed(ClassificationRules.match('Popcorn chicken'));
      _expectRed(ClassificationRules.match("פרייד צ'יקן"));
      _expectRed(ClassificationRules.match('עוף פופקורן'));
    });

    test('pan-, stir- and air-fried chicken carry no breading', () {
      _expectGreen(ClassificationRules.match('Pan-fried chicken breast'));
      _expectGreen(ClassificationRules.match('Stir-fried chicken'));
      _expectGreen(ClassificationRules.match('Air-fried chicken wings'));
    });

    test('French toast is red, not a yellow toast', () {
      _expectRed(ClassificationRules.match('French toast'));
      _expectRed(ClassificationRules.match("פרנץ' טוסט"));
      _expectRed(ClassificationRules.match('טוסט צרפתי'));
    });

    test("Fish 'n' Chips is battered fish, not a chips swap", () {
      _expectRed(
        ClassificationRules.match("Fish 'n' Chips"),
        label: 'battered fish',
      );
      _expectRed(ClassificationRules.match("פיש נ' צ'יפס"), label: 'דג מצופה');
    });

    test('Hebrew mirrors of the plural and compound bases are red', () {
      for (final text in [
        'כופתאות בשר',
        'כיסונים מאודים',
        "צ'יזקייק ניו יורק",
        'קאפקייקס וניל',
        'טאקו דג',
        'בראוני שוקולד',
        'קרואסונים חמאה',
        'בייגלים',
        'דונאטס',
        'אמפנדות בשר',
        'קרוקטים',
        'קרפים מתוקים',
        'סופגניות ריבה',
      ]) {
        _expectRed(ClassificationRules.match(text));
      }
    });
  });
}
