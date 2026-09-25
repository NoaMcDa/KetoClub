import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';

/// Normalises a Wolt consumer-assortment payload into a [Menu]
/// (architecture.md §6.1, §18.1; issue #168).
///
/// Pure: no I/O, and [toMenu] never throws. The payload is three flat
/// sibling collections — `categories`, `items`, `options` — joined by id
/// rather than nested, so this mapper's job is the join and the unit
/// conversions below. `test/fixtures/wolt_hamosad_menu.json` is a real
/// recording of this shape. A change to Wolt's URL or headers belongs in
/// `wolt_adapter.dart`, not here.
///
/// Normalisation rules applied (architecture.md §6.1):
///
/// - **Currency.** The assortment payload carries no currency anywhere —
///   not at the top level, not in `compliance_info`, not per item
///   (`unit_info` and `unit_price` are null on every recorded item) — so
///   [Menu.currency] is `ILS`, the currency of every Wolt Israel venue,
///   which is the only market KetoClub serves. A non-empty top-level
///   `currency` string, should Wolt ever add one, wins over that default.
/// - Each category's `item_ids` are resolved against `items[]` by id. An
///   id with no matching item is skipped, not an error — Wolt can list
///   fewer items than a category references.
/// - **Subcategories** are flattened into their parent: a category's own
///   `item_ids` come first, then each entry of its `subcategories` in
///   order (recursively), all under the parent's name. [Menu] has one
///   level of categories, and a heading per subcategory would split one
///   Wolt section into several on a phone screen. Every recorded category
///   has an empty `subcategories` list, so the shape of an entry is
///   inferred rather than observed: an absent `subcategories` key, or an
///   entry that is not a map with an `item_ids` list, is skipped rather
///   than failing the whole menu.
/// - `price` is integer agorot; it is divided by 100 to get [Dish.price]
///   in major units.
/// - Each item's `options` are objects whose `option_id` points into the
///   top-level `options[]`. The group's value `name`s survive onto
///   [DishOption.values]; its label is the item-level `name` when that is
///   a non-empty string (it can differ per dish: "Toppings — served in the
///   dish only" on one burger for a group called "Burger toppings"), else
///   the group's own `name`. Ids, prices, `prerequisite_values` and
///   `multi_choice_config` are dropped: a dish's yellow-ness lives in the
///   option text, and a group that only appears after another choice is
///   still text the classifier should read. An `option_id` with no
///   matching group is skipped rather than failing the payload — one dish
///   missing one option group is not evidence Wolt changed its schema
///   (the real recording has two such references).
/// - A missing or null `description` becomes `''`, never null. A missing
///   item `options` list is treated as no options.
/// - `images[0].url` becomes [Dish.imageUrl] when it is a non-empty
///   String, and null for anything else — no `images`, an empty list, a
///   first entry that is not a map, or a `url` that is absent, the wrong
///   type or empty. A bad photo is never grounds to fail the whole fetch.
/// - **Disabled items** (a non-null `disabled_info`, e.g. sold out today)
///   are kept. A dish's keto verdict does not depend on whether it can be
///   ordered this minute, and a menu that silently loses dishes between
///   two opens reads as a bug; the field is not read at all.
/// - A dish `id` already used by an earlier category is dropped from
///   every later category: first category wins. Wolt can list one item
///   under two categories, and a duplicate id would break the LLM
///   parser's provenance rules (architecture.md §9.4 rules 3, 7).
/// - An empty `categories` list is a valid, empty menu.
/// - Unknown keys anywhere, including a top-level `_fixture_note`, are
///   ignored: only the keys named above are ever read.
/// - [Menu.venueName] is always null: the assortment payload does not
///   carry the venue's name. The Discovery screen already knows it when
///   the user arrived from a venue card.
///
/// Anything else — a missing or wrong-typed `categories`/`items`, or a
/// present-but-malformed entry inside `categories[]`, `items[]`,
/// `options[]` or an item's `options` — is treated as a shape this mapper
/// does not know, so a schema drift is diagnosable rather than silently
/// producing an empty menu (architecture.md §8).
abstract final class WoltMenuMapper {
  /// The currency every Wolt Israel venue prices in; see the class doc
  /// comment for why it is not read from the payload.
  static const String defaultCurrency = 'ILS';

  /// Normalises [json] into a [Menu] for [ref], stamped [fetchedAt].
  ///
  /// Returns [MenuFetchFailed] with
  /// [MenuFetchFailureReason.platformChanged] when [json] does not have
  /// the shape documented on this class. Never throws.
  static MenuFetchResult toMenu(
    Map<String, Object?> json, {
    required VenueRef ref,
    required DateTime fetchedAt,
  }) {
    final menu = _tryBuildMenu(json, ref: ref, fetchedAt: fetchedAt);
    if (menu == null) {
      return const MenuFetchFailed(
        reason: MenuFetchFailureReason.platformChanged,
      );
    }
    return MenuFetched(menu: menu);
  }

  static Menu? _tryBuildMenu(
    Map<String, Object?> json, {
    required VenueRef ref,
    required DateTime fetchedAt,
  }) {
    final rawCurrency = json['currency'];
    final rawCategories = json['categories'];
    final rawItems = json['items'];
    final rawOptions = json['options'];
    if (rawCategories is! List<Object?>) return null;
    if (rawItems is! List<Object?>) return null;
    if (rawOptions != null && rawOptions is! List<Object?>) return null;

    final optionGroups = <String, DishOption>{};
    if (rawOptions is List<Object?>) {
      for (final rawOption in rawOptions) {
        final entry = _tryBuildOptionGroup(rawOption);
        if (entry == null) return null;
        optionGroups[entry.key] = entry.value;
      }
    }

    final itemsById = <String, Dish>{};
    for (final rawItem in rawItems) {
      final dish = _tryBuildItem(rawItem, optionGroups: optionGroups);
      if (dish == null) return null;
      itemsById[dish.id] = dish;
    }

    final usedDishIds = <String>{};
    final categories = <MenuCategory>[];
    for (final rawCategory in rawCategories) {
      final category = _tryBuildCategory(
        rawCategory,
        itemsById: itemsById,
        usedDishIds: usedDishIds,
      );
      if (category == null) return null;
      categories.add(category);
    }

    return Menu(
      venueRef: ref,
      currency: rawCurrency is String && rawCurrency.isNotEmpty
          ? rawCurrency
          : defaultCurrency,
      fetchedAt: fetchedAt,
      categories: categories,
    );
  }

  /// Builds one entry of the top-level `options[]` id-lookup table from
  /// one raw option-group object, or null when [raw] does not have the
  /// `{id, name, values: [{name, ...}]}` shape. `type`, `default_value`
  /// and each value's `id`/`price` are read nowhere: they are not part of
  /// [DishOption].
  static MapEntry<String, DishOption>? _tryBuildOptionGroup(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final id = raw['id'];
    final name = raw['name'];
    final rawValues = raw['values'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    if (rawValues is! List<Object?>) return null;
    final values = <String>[];
    for (final rawValue in rawValues) {
      if (rawValue is! Map<String, Object?>) return null;
      final valueName = rawValue['name'];
      if (valueName is! String || valueName.isEmpty) return null;
      values.add(valueName);
    }
    return MapEntry(id, DishOption(name: name, values: values));
  }

  /// Builds one `items[]` entry into a [Dish], or null when [raw] does
  /// not have the `{id, name, price, ...}` shape. `price` is converted
  /// from agorot to major units here, the one unit conversion Wolt needs.
  static Dish? _tryBuildItem(
    Object? raw, {
    required Map<String, DishOption> optionGroups,
  }) {
    if (raw is! Map<String, Object?>) return null;
    final id = raw['id'];
    final name = raw['name'];
    final rawDescription = raw['description'];
    final rawPrice = raw['price'];
    final rawItemOptions = raw['options'] ?? <Object?>[];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    if (rawDescription != null && rawDescription is! String) return null;
    if (rawPrice is! num || rawPrice < 0) return null;
    if (rawItemOptions is! List<Object?>) return null;
    final options = <DishOption>[];
    for (final rawItemOption in rawItemOptions) {
      if (rawItemOption is! Map<String, Object?>) return null;
      final optionId = rawItemOption['option_id'];
      if (optionId is! String) return null;
      final group = optionGroups[optionId];
      // An option_id with no matching group is skipped, not an error;
      // see the leniency note in the class doc comment above.
      if (group == null) continue;
      final label = rawItemOption['name'];
      options.add(
        label is String && label.isNotEmpty && label != group.name
            ? DishOption(name: label, values: group.values)
            : group,
      );
    }
    return Dish(
      id: id,
      name: name,
      description: rawDescription is String ? rawDescription : '',
      price: rawPrice / 100,
      options: options,
      // A missing or malformed image is never a mapping failure; see
      // the class doc comment.
      imageUrl: _tryReadImageUrl(raw['images']),
    );
  }

  /// The first entry of an item's `images` list's `url`, or null when
  /// there is no usable one. Never fails the mapping.
  static String? _tryReadImageUrl(Object? rawImages) {
    if (rawImages is! List<Object?> || rawImages.isEmpty) return null;
    final first = rawImages.first;
    if (first is! Map<String, Object?>) return null;
    final url = first['url'];
    return url is String && url.isNotEmpty ? url : null;
  }

  /// Builds one `categories[]` entry into a [MenuCategory], resolving its
  /// `item_ids` — then its subcategories' — against [itemsById] and
  /// dropping any id already claimed by an earlier category via
  /// [usedDishIds]. Returns null when [raw] does not have the
  /// `{id, name, item_ids: [...]}` shape.
  static MenuCategory? _tryBuildCategory(
    Object? raw, {
    required Map<String, Dish> itemsById,
    required Set<String> usedDishIds,
  }) {
    if (raw is! Map<String, Object?>) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    final itemIds = _tryReadItemIds(raw['item_ids']);
    if (itemIds == null) return null;
    final dishes = <Dish>[];
    for (final itemId in [...itemIds, ..._subcategoryItemIds(raw)]) {
      final dish = itemsById[itemId];
      // An item_id with no matching entry in items[] is skipped, not an
      // error (architecture.md §6.1).
      if (dish == null) continue;
      // A dish id already used by an earlier category is dropped here:
      // first category wins.
      if (!usedDishIds.add(dish.id)) continue;
      dishes.add(dish);
    }
    return MenuCategory(id: id, name: name, dishes: dishes);
  }

  /// [raw] as a list of item id strings, or null when it is not a list
  /// or holds anything but strings.
  static List<String>? _tryReadItemIds(Object? raw) {
    if (raw is! List<Object?>) return null;
    final ids = <String>[];
    for (final id in raw) {
      if (id is! String) return null;
      ids.add(id);
    }
    return ids;
  }

  /// Every item id under [category]'s `subcategories`, depth first and in
  /// order. Tolerant by design (see the class doc comment): an absent or
  /// malformed `subcategories` list, or a malformed entry in it,
  /// contributes nothing rather than failing the mapping.
  static List<String> _subcategoryItemIds(Map<String, Object?> category) {
    final rawSubcategories = category['subcategories'];
    if (rawSubcategories is! List<Object?>) return const <String>[];
    final ids = <String>[];
    for (final rawSubcategory in rawSubcategories) {
      if (rawSubcategory is! Map<String, Object?>) continue;
      final itemIds = _tryReadItemIds(rawSubcategory['item_ids']);
      if (itemIds == null) continue;
      ids
        ..addAll(itemIds)
        ..addAll(_subcategoryItemIds(rawSubcategory));
    }
    return ids;
  }
}
