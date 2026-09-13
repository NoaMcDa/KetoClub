import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';

/// Normalises a Wolt `menu/data` payload into a [Menu]
/// (architecture.md §6.1, §18.1).
///
/// Pure: no I/O, and [toMenu] never throws. Wolt's payload is three flat
/// sibling collections — `categories`, `items`, `options` — joined by id
/// rather than nested, so this mapper's job is entirely the join and the
/// unit conversions in the table below. A change to Wolt's URL or headers
/// belongs in `wolt_adapter.dart`, not here.
///
/// Normalisation rules applied (architecture.md §6.1):
///
/// - `currency` is copied verbatim onto [Menu.currency].
/// - Each category's `item_ids` are resolved against `items[]` by id. An
///   id with no matching item is skipped, not an error — Wolt can list
///   fewer items than a category references.
/// - `price` is integer agorot; it is divided by 100 to get [Dish.price]
///   in major units.
/// - Each item's `options` are option-group id strings, resolved against
///   the top-level `options[]` by id. Only the group's `name` and each
///   value's `name` survive onto [DishOption]; ids and per-value prices
///   are dropped, because a dish's yellow-ness often lives in the option
///   text, not its price. Symmetrically with the item/category join, an
///   option id with no matching group is skipped rather than failing the
///   whole payload — this mapper extends the documented item/category
///   leniency to this second join for the same reason: one dish missing
///   one option group is not evidence Wolt changed its schema.
/// - A missing or null `description` becomes `''`, never null. A missing
///   `options` list on an item (as opposed to a present-but-empty one) is
///   also tolerated and treated as no options, for the same "an absent
///   thing is not evidence of drift" reasoning as the two joins above.
/// - A dish `id` already used by an earlier category is dropped from
///   every later category: first category wins. Wolt can list one item
///   under two categories, and a duplicate id would break the LLM
///   parser's provenance rules (architecture.md §9.4 rules 3, 7).
/// - An empty `categories` list is a valid, empty menu.
/// - Unknown keys anywhere, including a top-level `_fixture_note`, are
///   ignored: only the keys named above are ever read.
///
/// Anything else — a missing or wrong-typed `currency`/`categories`/
/// `items`, or a present-but-malformed entry inside `categories[]`,
/// `items[]`, or `options[]` — is treated as a shape this mapper does not
/// know, so a schema drift is diagnosable rather than silently producing
/// an empty menu (architecture.md §8).
abstract final class WoltMenuMapper {
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
    final currency = json['currency'];
    final rawCategories = json['categories'];
    final rawItems = json['items'];
    final rawOptions = json['options'];
    if (currency is! String || currency.isEmpty) return null;
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
      currency: currency,
      fetchedAt: fetchedAt,
      categories: categories,
    );
  }

  /// Builds one entry of the top-level `options[]` id-lookup table from
  /// one raw option-group object, or null when [raw] does not have the
  /// `{id, name, values: [{name, ...}]}` shape. `type` and each value's
  /// `id`/`price` are read nowhere: they are not part of [DishOption].
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
    final rawOptionIds = raw['options'] ?? <Object?>[];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    if (rawDescription != null && rawDescription is! String) return null;
    if (rawPrice is! num || rawPrice < 0) return null;
    if (rawOptionIds is! List<Object?>) return null;
    final options = <DishOption>[];
    for (final rawOptionId in rawOptionIds) {
      if (rawOptionId is! String) return null;
      final option = optionGroups[rawOptionId];
      // An option id with no matching group is skipped, not an error;
      // see the leniency note in the class doc comment above.
      if (option != null) options.add(option);
    }
    return Dish(
      id: id,
      name: name,
      description: rawDescription is String ? rawDescription : '',
      price: rawPrice / 100,
      options: options,
    );
  }

  /// Builds one `categories[]` entry into a [MenuCategory], resolving its
  /// `item_ids` against [itemsById] and dropping any id already claimed
  /// by an earlier category via [usedDishIds]. Returns null when [raw]
  /// does not have the `{id, name, item_ids: [...]}` shape.
  static MenuCategory? _tryBuildCategory(
    Object? raw, {
    required Map<String, Dish> itemsById,
    required Set<String> usedDishIds,
  }) {
    if (raw is! Map<String, Object?>) return null;
    final id = raw['id'];
    final name = raw['name'];
    final rawItemIds = raw['item_ids'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    if (rawItemIds is! List<Object?>) return null;
    final dishes = <Dish>[];
    for (final rawItemId in rawItemIds) {
      if (rawItemId is! String) return null;
      final dish = itemsById[rawItemId];
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
}
