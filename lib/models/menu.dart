import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/venue.dart';

/// Element-wise list equality, used by every `==` in this file.
///
/// Not shared with other model files: each keeps its own copy so it stays
/// self-contained (architecture.md §18.2).
bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One option group offered with a dish, e.g. a choice of side
/// (architecture.md §7).
@immutable
final class DishOption {
  /// Creates an option group labelled [name], offering [values].
  const new({required this.name, required this.values});

  /// Reads an option group written by [toJson].
  ///
  /// Returns null for any shape mismatch and never throws.
  static DishOption? tryFrom(Map<String, Object?> json) {
    final name = json['name'];
    final rawValues = json['values'];
    if (name is! String || name.isEmpty) return null;
    if (rawValues is! List<Object?>) return null;
    final values = <String>[];
    for (final value in rawValues) {
      if (value is! String) return null;
      values.add(value);
    }
    return DishOption(name: name, values: values);
  }

  /// The option group label, e.g. "Choice of side".
  final String name;

  /// The value labels offered, e.g. `["Potato purée", "Green salad"]`.
  ///
  /// Callers must not mutate the list passed to the constructor.
  final List<String> values;

  /// Writes a form [tryFrom] can read back.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'values': values,
  };

  @override
  bool operator ==(Object other) =>
      other is DishOption &&
      other.name == name &&
      _listEquals(other.values, values);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(values));

  @override
  String toString() => 'DishOption($name: $values)';
}

/// One menu item (architecture.md §7).
@immutable
final class Dish {
  /// Creates a dish. [description] should be `''`, never null, when the
  /// platform did not supply one. [imageUrl] is null when the platform
  /// supplied no photo, or one that could not be read — a missing or
  /// malformed image must never fail the whole fetch.
  const new({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.options,
    this.imageUrl,
  });

  /// Reads a dish written by [toJson].
  ///
  /// Returns null for any shape mismatch — including a negative
  /// [price] or a malformed option — and never throws. `imageUrl` is
  /// read tolerantly: absent (as in every entry cached before this
  /// field existed), null, non-String or empty all decode to a null
  /// [imageUrl], never to a failure of the whole entry.
  static Dish? tryFrom(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final rawDescription = json['description'];
    final rawPrice = json['price'];
    final rawOptions = json['options'];
    final rawImageUrl = json['imageUrl'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    if (rawDescription != null && rawDescription is! String) return null;
    final description = rawDescription is String ? rawDescription : '';
    if (rawPrice is! num || rawPrice < 0) return null;
    if (rawOptions is! List<Object?>) return null;
    final options = <DishOption>[];
    for (final rawOption in rawOptions) {
      if (rawOption is! Map<String, Object?>) return null;
      final option = DishOption.tryFrom(rawOption);
      if (option == null) return null;
      options.add(option);
    }
    return Dish(
      id: id,
      name: name,
      description: description,
      price: rawPrice.toDouble(),
      options: options,
      imageUrl: rawImageUrl is String && rawImageUrl.isNotEmpty
          ? rawImageUrl
          : null,
    );
  }

  /// The platform id, stable across refetches.
  final String id;

  /// The dish name, exactly as printed on the menu.
  final String name;

  /// The dish description. `''` when the platform supplied none, never
  /// null.
  final String description;

  /// The price in major units (ILS), already converted from the
  /// platform's own units (e.g. agorot).
  final double price;

  /// Option groups offered with the dish, e.g. a choice of side.
  ///
  /// Callers must not mutate the list passed to the constructor.
  final List<DishOption> options;

  /// The dish photo's URL, when the platform supplied one. Null when
  /// the source had none, or supplied a value that was not a non-empty
  /// String — this field is not rendered anywhere yet
  /// (architecture.md §17).
  final String? imageUrl;

  /// Writes a form [tryFrom] can read back.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'description': description,
    'price': price,
    'options': options.map((option) => option.toJson()).toList(),
    'imageUrl': imageUrl,
  };

  @override
  bool operator ==(Object other) =>
      other is Dish &&
      other.id == id &&
      other.name == name &&
      other.description == description &&
      other.price == price &&
      _listEquals(other.options, options) &&
      other.imageUrl == imageUrl;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    price,
    Object.hashAll(options),
    imageUrl,
  );

  @override
  String toString() => 'Dish($id: $name)';
}

/// One menu section, e.g. "Steaks" (architecture.md §7).
@immutable
final class MenuCategory {
  /// Creates a category named [name], containing [dishes].
  const new({required this.id, required this.name, required this.dishes});

  /// Reads a category written by [toJson].
  ///
  /// Returns null for any shape mismatch, including a malformed dish,
  /// and never throws.
  static MenuCategory? tryFrom(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final rawDishes = json['dishes'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    if (rawDishes is! List<Object?>) return null;
    final dishes = <Dish>[];
    for (final rawDish in rawDishes) {
      if (rawDish is! Map<String, Object?>) return null;
      final dish = Dish.tryFrom(rawDish);
      if (dish == null) return null;
      dishes.add(dish);
    }
    return MenuCategory(id: id, name: name, dishes: dishes);
  }

  /// The platform id of this category.
  final String id;

  /// The category name, exactly as printed on the menu.
  final String name;

  /// The dishes in this category, in menu order.
  ///
  /// Callers must not mutate the list passed to the constructor.
  final List<Dish> dishes;

  /// Writes a form [tryFrom] can read back.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'dishes': dishes.map((dish) => dish.toJson()).toList(),
  };

  @override
  bool operator ==(Object other) =>
      other is MenuCategory &&
      other.id == id &&
      other.name == name &&
      _listEquals(other.dishes, dishes);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(dishes));

  @override
  String toString() => 'MenuCategory($id: $name, ${dishes.length} dishes)';
}

/// A menu fetched from one platform for one venue (architecture.md §7).
@immutable
final class Menu {
  /// Creates a menu for [venueRef], fetched at [fetchedAt]. [venueName]
  /// is optional: not every platform payload names the venue it belongs
  /// to (see `WoltMenuMapper`), and a menu with no name is still a valid
  /// menu.
  const new({
    required this.venueRef,
    required this.currency,
    required this.fetchedAt,
    required this.categories,
    this.venueName,
  });

  /// Reads a menu written by [toJson].
  ///
  /// Returns null for any shape mismatch, including a malformed
  /// [VenueRef], category, or timestamp, and never throws. `venueName`
  /// is read tolerantly: absent (as in every entry cached before this
  /// field existed) or null both decode to a null [venueName], and only
  /// a present-but-non-string value fails the whole entry.
  static Menu? tryFrom(Map<String, Object?> json) {
    final rawVenueRef = json['venueRef'];
    final currency = json['currency'];
    final rawFetchedAt = json['fetchedAt'];
    final rawCategories = json['categories'];
    final rawVenueName = json['venueName'];
    if (rawVenueRef is! Map<String, Object?>) return null;
    final venueRef = VenueRef.tryFrom(rawVenueRef);
    if (venueRef == null) return null;
    if (currency is! String || currency.isEmpty) return null;
    if (rawFetchedAt is! String) return null;
    final fetchedAt = DateTime.tryParse(rawFetchedAt);
    if (fetchedAt == null) return null;
    if (rawCategories is! List<Object?>) return null;
    if (rawVenueName != null && rawVenueName is! String) return null;
    final categories = <MenuCategory>[];
    for (final rawCategory in rawCategories) {
      if (rawCategory is! Map<String, Object?>) return null;
      final category = MenuCategory.tryFrom(rawCategory);
      if (category == null) return null;
      categories.add(category);
    }
    return Menu(
      venueRef: venueRef,
      currency: currency,
      fetchedAt: fetchedAt,
      categories: categories,
      venueName: rawVenueName is String ? rawVenueName : null,
    );
  }

  /// How to fetch this menu again.
  final VenueRef venueRef;

  /// The currency dish prices are in, e.g. "ILS".
  final String currency;

  /// When this menu was fetched from the platform.
  final DateTime fetchedAt;

  /// The menu's sections, in menu order.
  ///
  /// Callers must not mutate the list passed to the constructor.
  final List<MenuCategory> categories;

  /// The restaurant's name, when the platform payload named it. Null
  /// when the source did not carry a name — the menu screen's header
  /// falls back to the pasted reference in that case, never to a
  /// placeholder guessed here.
  final String? venueName;

  /// Every dish in the menu, flattened, category order preserved.
  Iterable<Dish> get allDishes =>
      categories.expand((category) => category.dishes);

  /// The name of the category containing the dish with id [dishId], or
  /// null when this menu has no such dish.
  String? categoryNameOf(String dishId) {
    for (final category in categories) {
      for (final dish in category.dishes) {
        if (dish.id == dishId) return category.name;
      }
    }
    return null;
  }

  /// Writes a form [tryFrom] can read back.
  Map<String, Object?> toJson() => <String, Object?>{
    'venueRef': venueRef.toJson(),
    'currency': currency,
    'fetchedAt': fetchedAt.toIso8601String(),
    'categories': categories.map((category) => category.toJson()).toList(),
    'venueName': venueName,
  };

  @override
  bool operator ==(Object other) =>
      other is Menu &&
      other.venueRef == venueRef &&
      other.currency == currency &&
      other.fetchedAt == fetchedAt &&
      _listEquals(other.categories, categories) &&
      other.venueName == venueName;

  @override
  int get hashCode => Object.hash(
    venueRef,
    currency,
    fetchedAt,
    Object.hashAll(categories),
    venueName,
  );

  @override
  String toString() =>
      'Menu(${venueRef.cacheKey}, ${venueName ?? '?'}, '
      '${categories.length} categories)';
}
