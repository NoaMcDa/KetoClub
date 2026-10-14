/// The inputs of the declarations golden, `declarations.json` (Banto;
/// ALG-09, issue #351).
///
/// Data only, like `golden_corpus.dart`: dishes, each with an optional
/// category heading, built to hit each rule of
/// `lib/utils/allergens/declarations.dart` — Hebrew and English terms, the
/// symbols, a heading that declares for its dishes, the guards that make a
/// footnote or an offer no declaration, platform tags read through the same
/// table and the kosher tag. The shapes follow file 12 §4.4's observed
/// Wolt and 10bis pages.
library;

import 'package:ketoclub/models/menu.dart';

/// One golden case: a dish and the heading it sits under (null: none).
typedef DeclarationCase = ({String name, Dish dish, String? heading});

/// A dish named [name] with [description] and [tags], priced 0.
Dish _dish(
  String id,
  String name, {
  String description = '',
  List<String> tags = const <String>[],
}) => Dish(
  id: id,
  name: name,
  description: description,
  price: 0,
  options: const <DishOption>[],
  declaredTags: tags,
);

/// Every case the declarations golden records, in order.
final List<DeclarationCase> declarationCases = <DeclarationCase>[
  (
    name: 'he_name_vegan',
    dish: _dish('d1', 'סלט קינואה טבעוני'),
    heading: 'סלטים',
  ),
  (
    name: 'he_name_vegan_and_gluten_free',
    dish: _dish('d2', 'תבשיל קטניות- טבעוני/ללא גלוטן'),
    heading: 'מנות עיקריות',
  ),
  (
    name: 'he_heading_gluten_free_with_symbol',
    dish: _dish('d3', 'רול סלמון', description: 'סלמון, אבוקדו, מלפפון'),
    heading: 'סושי ללא גלוטן 🌾',
  ),
  (
    name: 'heading_symbol_only',
    dish: _dish('d4', 'Rice bowl'),
    heading: 'Specials 🌾',
  ),
  (
    name: 'en_symbol_and_description',
    dish: _dish('d5', 'Misi Masala Roti 🌱', description: 'Gluten Free'),
    heading: 'Vegan dishes',
  ),
  (
    name: 'he_footnote_offer_is_no_declaration',
    dish: _dish('d6', 'מג׳דרה', description: 'ניתן לקבל טבעוני'),
    heading: null,
  ),
  (
    name: 'en_offer_is_no_declaration',
    dish: _dish('d7', 'Burger', description: 'Vegan option available'),
    heading: 'Mains',
  ),
  (
    name: 'en_negation_is_no_declaration',
    dish: _dish('d8', 'Shakshuka', description: 'Not vegan; non-vegan base'),
    heading: null,
  ),
  (
    name: 'en_can_be_made_is_no_declaration',
    dish: _dish('d9', 'Pasta', description: 'Can be made gluten-free'),
    heading: null,
  ),
  (
    name: 'he_surcharge_is_no_declaration',
    dish: _dish('d10', 'פיצה', description: 'ללא גלוטן בתוספת 5 ש״ח'),
    heading: null,
  ),
  (
    name: 'he_on_request_is_no_declaration',
    dish: _dish('d11', 'שניצל', description: 'טבעוני לפי בקשה'),
    heading: null,
  ),
  (
    name: 'en_vegetarian',
    dish: _dish('d12', 'Vegetarian lasagna'),
    heading: 'Pasta',
  ),
  (
    name: 'he_vegetarian_feminine',
    dish: _dish('d13', 'פשטידה צמחונית'),
    heading: null,
  ),
  (
    name: 'en_dairy_free',
    dish: _dish('d14', 'Dairy-free ice cream'),
    heading: 'Desserts',
  ),
  (
    name: 'he_dairy_products_free',
    dish: _dish('d15', 'גלידה ללא מוצרי חלב'),
    heading: 'קינוחים',
  ),
  (
    name: 'en_lactose_free',
    dish: _dish('d16', 'Lactose free latte'),
    heading: null,
  ),
  (
    name: 'he_lactose_free',
    dish: _dish('d17', 'הפוך ללא לקטוז'),
    heading: 'שתייה חמה',
  ),
  (name: 'en_eggless', dish: _dish('d18', 'Eggless cake'), heading: null),
  (
    name: 'he_egg_free',
    dish: _dish('d19', 'עוגת שוקולד ללא ביצים'),
    heading: null,
  ),
  (name: 'en_gf_marker', dish: _dish('d20', 'Pancakes (GF)'), heading: null),
  (
    name: 'en_plant_based',
    dish: _dish('d21', 'Plant-based burger'),
    heading: null,
  ),
  (
    name: 'he_prefixed_terms',
    dish: _dish('d22', 'קציצות עדשים וטבעוני', description: 'ובלי גלוטן'),
    heading: null,
  ),
  (
    name: 'platform_tags_and_text',
    dish: _dish('d23', 'Vegan bowl', tags: <String>['VEGAN', 'GLUTEN_FREE']),
    heading: null,
  ),
  (
    name: 'platform_tags_repeat',
    dish: _dish('d24', 'Bowl', tags: <String>['vegan', 'Vegan']),
    heading: null,
  ),
  (
    name: 'platform_tag_negated',
    dish: _dish('d25', 'Bowl', tags: <String>['NON_VEGAN']),
    heading: null,
  ),
  (
    name: 'platform_tag_kosher',
    dish: _dish('d26', 'Bread basket', tags: <String>['kosher']),
    heading: null,
  ),
  (
    name: 'platform_tag_kosher_upper_and_hebrew',
    dish: _dish('d27', 'Bread', tags: <String>['KOSHER', 'כשר']),
    heading: null,
  ),
  (
    name: 'platform_tag_unknown',
    dish: _dish('d28', 'Bread', tags: <String>['spicy', 'popular']),
    heading: null,
  ),
  (name: 'nothing_declared', dish: _dish('d29', 'Entrecôte'), heading: null),
  (
    name: 'he_vegan_cheese_component',
    dish: _dish('d30', 'פיצה עם גבינה טבעונית'),
    heading: 'פיצות',
  ),
];
