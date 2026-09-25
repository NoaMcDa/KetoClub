import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';

/// Normalises a 10bis `Restaurants/{id}/Menu` payload into a [Menu]
/// (architecture.md §6.1, §18.1, issue #45).
///
/// **The shape below is unverified — issue #44 is still open.**
/// The 10bis API is unreachable from this build environment, so this
/// mapper is written against a synthetic fixture
/// (`test/fixtures/tenbis_synthetic_menu.json`), built from
/// `menu_api_research` §3.2 and issue #44's own body text (which names
/// `categoriesList → dishList`, decimal prices, kosher flags,
/// `dishOptionsList`, and image fields), not a recorded response. Once #44
/// records a real payload, re-run this mapper's tests against it — a
/// mismatch there is the alarm architecture.md §15 asks for, not a
/// silent gap.
///
/// Unlike Wolt's three flat sibling collections joined by id, 10bis's
/// payload is nested exactly as `menu_api_research` describes it:
/// "categories -> dishes -> dish options". Every dish and every option
/// group lives directly inside its parent, so this mapper never needs
/// Wolt's id-lookup join.
///
/// Assumed shape (documented here because #44 has not recorded a real
/// one to point at instead):
///
/// ```json
/// {
///   "restaurantName": "Vitrina Lilinblum",
///   "categoriesList": [
///     {
///       "categoryName": "Steaks",
///       "dishList": [
///         {
///           "dishId": "1001",
///           "dishName": "Entrecôte 300g",
///           "dishDescription": "Served with potato purée",
///           "price": 142.0,
///           "kosher": false,
///           "dishOptionsList": [
///             {
///               "name": "Choice of Side",
///               "values": [{"name": "Potato Purée"}, {"name": "Salad"}]
///             }
///           ],
///           "dishImageUrl": "https://example.invalid/entrecote.jpg"
///         }
///       ]
///     }
///   ]
/// }
/// ```
///
/// Normalisation rules applied:
///
/// - `categoriesList` holds the menu's sections. 10bis has no stable
///   category id — `menu_api_research` never names one — so
///   [MenuCategory.id] is derived from `categoryName` by
///   [_slugifyCategoryName]: lower-cased, non letter/digit runs
///   collapsed to a single `-`, prefixed `cat_`. Two categories sharing
///   a name would collide onto the same id; that is accepted rather
///   than invented, because a made-up id would not survive a refetch
///   any more reliably. A category with an empty `dishList` is valid.
/// - Each category's `dishList` holds its dishes directly; there is no
///   separate top-level collection to join against.
/// - `dishId` is read tolerantly: a non-empty `String` or a `num` (10bis
///   uses numeric ids elsewhere, e.g. `restaurantId`) is accepted, the
///   `num` case converted with `.toString()`. Anything else fails the
///   dish.
/// - `price` is a decimal number already in major units (ILS) —
///   `menu_api_research` §3.2 notes 10bis returns "standard decimal
///   floats or numbers without sub-unit multiplication", unlike Wolt's
///   agorot integers — so it is read as-is, never divided.
/// - A missing or null `dishDescription` becomes `''`, never null, the
///   same leniency `WoltMenuMapper` applies to Wolt's `description`.
/// - `dishOptionsList` is read the same way `WoltMenuMapper` reads an
///   option group, but nested rather than id-joined: each entry needs a
///   non-empty `name` and a `values` list of maps each carrying a
///   non-empty `name`. A missing `dishOptionsList` (as opposed to a
///   present-but-empty one) is tolerated as no options, mirroring
///   Wolt's absent-`options` leniency.
/// - `dishImageUrl` becomes [Dish.imageUrl] when it is a non-empty
///   `String`, and null for anything else — absent, null, the wrong
///   type, or empty — the same rule `WoltMenuMapper` applies to Wolt's
///   `image`.
/// - A dish id already used by an earlier category is dropped from
///   every later category: first category wins, mirroring
///   `WoltMenuMapper`'s duplicate-id rule and for the same reason
///   (architecture.md §9.4 rules 3, 7).
/// - `kosher` and any other per-dish field (calories, allergens, a
///   dish number distinct from `dishId`, and so on) are read nowhere:
///   they are not part of [Dish].
/// - `currency` has never been observed in a 10bis payload
///   (`menu_api_research` §3.2 says nothing about one), so it is read
///   tolerantly at the top level and defaults to `'ILS'` — 10bis is an
///   Israel-only platform — when absent or not a non-empty `String`.
///   `WoltMenuMapper` applies the same default since Wolt's
///   consumer-assortment payload turned out to carry no currency either
///   (issue #168).
/// - [Menu.venueName] is read from a top-level `restaurantName` when it
///   is a non-empty `String`, and null otherwise. A missing or
///   malformed name is never a mapping failure.
/// - Unknown keys anywhere, including a top-level `_synthetic`, are
///   ignored: only the keys named above are ever read.
/// - An empty `categoriesList` is a valid, empty menu.
///
/// Anything else — a missing or wrong-typed `categoriesList`, or a
/// present-but-malformed entry inside `categoriesList[]`,
/// `dishList[]`, or `dishOptionsList[]` — is treated as a shape this
/// mapper does not know, so a schema drift is diagnosable rather than
/// silently producing an empty menu (architecture.md §8). This mapper
/// makes the same "one malformed entry fails the whole fetch" trade
/// `WoltMenuMapper` makes, and inherits the same open question about
/// whether that is too strict for a real payload's odd entry
/// (HANDOFF.md "Known limitations").
abstract final class TenBisMenuMapper {
  /// The default currency assumed when the payload carries none, because
  /// 10bis is an Israel-only platform and no observed payload names one.
  static const String _defaultCurrency = 'ILS';

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
    final rawCategories = json['categoriesList'];
    if (rawCategories is! List<Object?>) return null;

    final usedDishIds = <String>{};
    final categories = <MenuCategory>[];
    for (final rawCategory in rawCategories) {
      final category = _tryBuildCategory(rawCategory, usedDishIds);
      if (category == null) return null;
      categories.add(category);
    }

    return Menu(
      venueRef: ref,
      currency: _readCurrency(json),
      fetchedAt: fetchedAt,
      categories: categories,
      venueName: _tryReadVenueName(json),
    );
  }

  /// The menu's currency, read tolerantly from a top-level `currency`,
  /// defaulting to [_defaultCurrency] when absent or not a non-empty
  /// `String` (see the class doc comment).
  static String _readCurrency(Map<String, Object?> json) {
    final currency = json['currency'];
    if (currency is String && currency.isNotEmpty) return currency;
    return _defaultCurrency;
  }

  /// The venue's display name, read from a top-level `restaurantName`,
  /// or null when it is absent or not a non-empty `String`.
  static String? _tryReadVenueName(Map<String, Object?> json) {
    final name = json['restaurantName'];
    if (name is String && name.isNotEmpty) return name;
    return null;
  }

  /// Builds one `categoriesList[]` entry into a [MenuCategory], deriving
  /// its id from `categoryName` (see [_slugifyCategoryName]) and reading
  /// its dishes from a nested `dishList`. Dish ids already claimed via
  /// [usedDishIds] are dropped: first category wins. Returns null when
  /// [raw] does not have the `{categoryName, dishList: [...]}` shape.
  static MenuCategory? _tryBuildCategory(Object? raw, Set<String> usedDishIds) {
    if (raw is! Map<String, Object?>) return null;
    final categoryName = raw['categoryName'];
    final rawDishes = raw['dishList'];
    if (categoryName is! String || categoryName.isEmpty) return null;
    if (rawDishes is! List<Object?>) return null;

    final dishes = <Dish>[];
    for (final rawDish in rawDishes) {
      final dish = _tryBuildDish(rawDish);
      if (dish == null) return null;
      // A dish id already used by an earlier category is dropped here:
      // first category wins (see the class doc comment).
      if (!usedDishIds.add(dish.id)) continue;
      dishes.add(dish);
    }
    return MenuCategory(
      id: _slugifyCategoryName(categoryName),
      name: categoryName,
      dishes: dishes,
    );
  }

  /// Builds one `dishList[]` entry into a [Dish], or null when [raw]
  /// does not have the `{dishId, dishName, price, ...}` shape.
  static Dish? _tryBuildDish(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final id = _tryReadDishId(raw['dishId']);
    final name = raw['dishName'];
    final rawDescription = raw['dishDescription'];
    final rawPrice = raw['price'];
    final rawOptions = raw['dishOptionsList'];
    final rawImage = raw['dishImageUrl'];
    if (id == null) return null;
    if (name is! String || name.isEmpty) return null;
    if (rawDescription != null && rawDescription is! String) return null;
    if (rawPrice is! num || rawPrice < 0) return null;
    if (rawOptions != null && rawOptions is! List<Object?>) return null;

    final options = <DishOption>[];
    if (rawOptions is List<Object?>) {
      for (final rawOption in rawOptions) {
        final option = _tryBuildOptionGroup(rawOption);
        if (option == null) return null;
        options.add(option);
      }
    }

    return Dish(
      id: id,
      name: name,
      description: rawDescription is String ? rawDescription : '',
      price: rawPrice.toDouble(),
      options: options,
      // A missing or malformed image is never a mapping failure; see
      // the class doc comment.
      imageUrl: rawImage is String && rawImage.isNotEmpty ? rawImage : null,
    );
  }

  /// Reads a raw `dishId` value as a non-empty [String], accepting
  /// either a `String` or a `num` (converted with `.toString()`); null
  /// for anything else, including an empty `String`.
  static String? _tryReadDishId(Object? raw) {
    if (raw is String) return raw.isEmpty ? null : raw;
    if (raw is num) return raw.toString();
    return null;
  }

  /// Builds one `dishOptionsList[]` entry into a [DishOption], or null
  /// when [raw] does not have the `{name, values: [{name, ...}]}`
  /// shape — the same shape `WoltMenuMapper` reads for an option group,
  /// nested here rather than id-joined.
  static DishOption? _tryBuildOptionGroup(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final name = raw['name'];
    final rawValues = raw['values'];
    if (name is! String || name.isEmpty) return null;
    if (rawValues is! List<Object?>) return null;
    final values = <String>[];
    for (final rawValue in rawValues) {
      if (rawValue is! Map<String, Object?>) return null;
      final valueName = rawValue['name'];
      if (valueName is! String || valueName.isEmpty) return null;
      values.add(valueName);
    }
    return DishOption(name: name, values: values);
  }

  /// Derives a stable [MenuCategory.id] from [name], since 10bis names
  /// no stable category id anywhere `menu_api_research` documents.
  ///
  /// Lower-cases [name], collapses every run of characters that are not
  /// an ASCII letter/digit or a Hebrew letter into a single `-`, trims
  /// leading and trailing `-`, and prefixes the result `cat_`. Falls
  /// back to `cat_` plus [name]'s hash code when that leaves nothing —
  /// e.g. a name made entirely of punctuation — so the id is never
  /// empty. Two categories sharing a name collide onto the same id;
  /// that is accepted rather than papered over with a random id that
  /// would not survive a refetch (see the class doc comment).
  static String _slugifyCategoryName(String name) {
    final lower = name.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final isAsciiAlphaNumeric =
          (rune >= 0x30 && rune <= 0x39) || (rune >= 0x61 && rune <= 0x7a);
      final isHebrewLetter = rune >= 0x0590 && rune <= 0x05ff;
      buffer.writeCharCode(isAsciiAlphaNumeric || isHebrewLetter ? rune : 0x2d);
    }
    final collapsed = buffer
        .toString()
        .replaceAll(RegExp('-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final slug = collapsed.isEmpty
        ? name.hashCode.toRadixString(16)
        : collapsed;
    return 'cat_$slug';
  }
}
