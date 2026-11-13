import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';

/// Normalises a 10bis `NextApi/GetRestaurantMenu` payload into a [Menu]
/// (architecture.md §6.1, §18.1, issues #45, #468).
///
/// Written against a real recording,
/// `test/fixtures/tenbis_19156_menu.json` (#468, closing #44). 10bis
/// retired `api/v1.0/Restaurants/{id}/Menu` (it answers 404 for every
/// id), and the endpoint its own web app reads now wraps the menu in an
/// envelope:
///
/// ```json
/// {
///   "Errors": null,
///   "Success": true,
///   "Data": {
///     "resId": 19156,
///     "categoriesList": [
///       {
///         "categoryID": 987906,
///         "categoryName": "כריכים ",
///         "dishList": [
///           {
///             "dishId": 22610556,
///             "dishName": "פיקולי גאודה",
///             "dishDescription": "לחמנית חלה, חסה, עגבניה...",
///             "dishPrice": 29,
///             "dishImageUrl": "https://...cloudfront.net/...",
///             "choices": [
///               {
///                 "textBeforeChoosing": "תוספת סלט?",
///                 "isForced": false,
///                 "subs": [{"name": "סלט מיסטה", "price": 15}]
///               }
///             ]
///           }
///         ]
///       }
///     ]
///   },
///   "ShoppingCartGuid": "..."
/// }
/// ```
///
/// Normalisation rules applied:
///
/// - `Success: false` (10bis's answer to a malformed id, with an
///   `Errors` list such as `InvalidParameters`) and a `Data` whose
///   `categoriesList` is null (its answer to an id no restaurant has) are
///   [MenuFetchFailureReason.notFound], never `platformChanged`: 10bis
///   answers both with a 200.
/// - Otherwise `Data` must be an object holding a `categoriesList` list.
///   An empty list is a valid, empty menu.
/// - A category's id is `cat_` plus its numeric `categoryID`, written as
///   Dart's `num.toString` writes it. A category without a numeric
///   `categoryID` falls back to a slug of its `categoryName`
///   ([_slugifyCategoryName]). `categoryName` must be a non-empty
///   `String` and is kept as sent, trailing space included.
/// - `dishId` is a non-empty `String` or a `num` (10bis sends an int),
///   the `num` converted with `.toString()`.
/// - `dishPrice` is a non-negative number already in shekels, read
///   as-is, never divided.
/// - A missing or null `dishDescription` becomes `''`.
/// - `choices` becomes [Dish.options]: each entry needs a non-empty
///   `textBeforeChoosing` (the option group's name) and a `subs` list of
///   objects each carrying a non-empty `name`. A missing `choices` is no
///   options. A sub's `price`, `isForced` and `maxPicksAllowed` are not
///   part of [DishOption] and are read nowhere.
/// - `dishImageUrl` becomes [Dish.imageUrl] when it is a non-empty
///   `String` (10bis sends `''` for a dish without a photo), and null
///   otherwise.
/// - A dish id already used by an earlier category is dropped from every
///   later category: first category wins, as in `WoltMenuMapper`
///   (architecture.md §9.4 rules 3, 7).
/// - The payload names no currency and no restaurant: [Menu.currency] is
///   `'ILS'` (10bis is Israel-only) and [Menu.venueName] is null.
/// - Unknown keys anywhere are ignored.
///
/// Anything else — no `Data` object, a missing or wrong-typed
/// `categoriesList`, or a malformed entry inside it — is a shape this
/// mapper does not know, [MenuFetchFailureReason.platformChanged], so a
/// schema drift is diagnosable rather than silently producing an empty
/// menu (architecture.md §8). One malformed entry fails the whole fetch,
/// the same trade `WoltMenuMapper` makes.
///
/// `backend/app/platforms/tenbis_menu.py` is this mapper's Python port;
/// the `tenbis_menu` golden pins the two equal (D25).
abstract final class TenBisMenuMapper {
  /// The currency every 10bis menu is priced in: the platform is
  /// Israel-only and its payload names none.
  static const String _currency = 'ILS';

  /// Normalises [json] into a [Menu] for [ref], stamped [fetchedAt].
  ///
  /// Returns [MenuFetchFailed] with [MenuFetchFailureReason.notFound]
  /// when 10bis says there is no such restaurant, and with
  /// [MenuFetchFailureReason.platformChanged] when [json] does not have
  /// the shape documented on this class. Never throws.
  static MenuFetchResult toMenu(
    Map<String, Object?> json, {
    required VenueRef ref,
    required DateTime fetchedAt,
  }) {
    if (isNotFound(json)) {
      return const MenuFetchFailed(reason: MenuFetchFailureReason.notFound);
    }
    final menu = _tryBuildMenu(json, ref: ref, fetchedAt: fetchedAt);
    if (menu == null) {
      return const MenuFetchFailed(
        reason: MenuFetchFailureReason.platformChanged,
      );
    }
    return MenuFetched(menu: menu);
  }

  /// Whether [json] is 10bis saying it has no such restaurant: an
  /// explicit `Success: false`, or a `Data` object whose
  /// `categoriesList` is null (see the class doc comment).
  static bool isNotFound(Map<String, Object?> json) {
    if (json['Success'] == false) return true;
    final data = json['Data'];
    return data is Map<String, Object?> &&
        data.containsKey('categoriesList') &&
        data['categoriesList'] == null;
  }

  static Menu? _tryBuildMenu(
    Map<String, Object?> json, {
    required VenueRef ref,
    required DateTime fetchedAt,
  }) {
    final data = json['Data'];
    if (data is! Map<String, Object?>) return null;
    final rawCategories = data['categoriesList'];
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
      currency: _currency,
      fetchedAt: fetchedAt,
      categories: categories,
    );
  }

  /// Builds one `categoriesList[]` entry into a [MenuCategory]. Dish ids
  /// already claimed via [usedDishIds] are dropped: first category wins.
  /// Returns null when [raw] does not have the
  /// `{categoryName, dishList: [...]}` shape.
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
    final categoryId = raw['categoryID'];
    return MenuCategory(
      id: categoryId is num
          ? 'cat_$categoryId'
          : _slugifyCategoryName(categoryName),
      name: categoryName,
      dishes: dishes,
    );
  }

  /// Builds one `dishList[]` entry into a [Dish], or null when [raw]
  /// does not have the `{dishId, dishName, dishPrice, ...}` shape.
  static Dish? _tryBuildDish(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final id = _tryReadDishId(raw['dishId']);
    final name = raw['dishName'];
    final rawDescription = raw['dishDescription'];
    final rawPrice = raw['dishPrice'];
    final rawChoices = raw['choices'];
    final rawImage = raw['dishImageUrl'];
    if (id == null) return null;
    if (name is! String || name.isEmpty) return null;
    if (rawDescription != null && rawDescription is! String) return null;
    if (rawPrice is! num || rawPrice < 0) return null;
    if (rawChoices != null && rawChoices is! List<Object?>) return null;

    final options = <DishOption>[];
    if (rawChoices is List<Object?>) {
      for (final rawChoice in rawChoices) {
        final option = _tryBuildOptionGroup(rawChoice);
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
      // A missing or empty image is never a mapping failure; see the
      // class doc comment.
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

  /// Builds one `choices[]` entry into a [DishOption], or null when
  /// [raw] does not have the `{textBeforeChoosing, subs: [{name}]}`
  /// shape.
  static DishOption? _tryBuildOptionGroup(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final name = raw['textBeforeChoosing'];
    final rawSubs = raw['subs'];
    if (name is! String || name.isEmpty) return null;
    if (rawSubs is! List<Object?>) return null;
    final values = <String>[];
    for (final rawSub in rawSubs) {
      if (rawSub is! Map<String, Object?>) return null;
      final subName = rawSub['name'];
      if (subName is! String || subName.isEmpty) return null;
      values.add(subName);
    }
    return DishOption(name: name, values: values);
  }

  /// Derives a [MenuCategory.id] from [name], for a category that carries
  /// no numeric `categoryID`.
  ///
  /// Lower-cases [name], collapses every run of characters that are not
  /// an ASCII letter/digit or a Hebrew letter into a single `-`, trims
  /// leading and trailing `-`, and prefixes the result `cat_`. Falls
  /// back to `cat_` plus [name]'s hash code when that leaves nothing —
  /// e.g. a name made entirely of punctuation — so the id is never
  /// empty. Two such categories sharing a name collide onto the same id.
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
