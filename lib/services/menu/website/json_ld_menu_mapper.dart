import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/utils/constants.dart';

/// Reads schema.org menu markup out of a page's JSON-LD blocks
/// (architecture.md D19; issue #181): `Menu` → `MenuSection` →
/// `MenuItem`, and a `Restaurant`'s `hasMenu` link.
///
/// Pure and never throws: a block of any other shape yields nothing. The
/// research found this markup rare and often partial
/// (`docs/menu_sources_research.md` §3.2), so it is tried first because it
/// is cheap, not because it is expected to hit.
abstract final class JsonLdMenuMapper {
  /// The categories of every schema.org `Menu` in [blocks], or null when
  /// none holds a named item.
  ///
  /// Each `MenuSection` (nested ones flattened) is a category; items
  /// directly on a `Menu` go to a category named after the menu. Every
  /// dish gets `price: 0` — a site's price is unverified (D19) — and an id
  /// `j1..jN` in document order, at most [maxAnalysedDishes] of them.
  static List<MenuCategory>? categoriesFrom(List<Object?> blocks) {
    final categories = <MenuCategory>[];
    var dishCount = 0;

    void addCategory(String name, List<Object?> items) {
      final dishes = <Dish>[];
      for (final item in items) {
        if (dishCount >= maxAnalysedDishes) break;
        if (item is! Map<String, Object?>) continue;
        final dishName = _text(item['name']);
        if (dishName == null) continue;
        dishCount += 1;
        dishes.add(
          Dish(
            id: 'j$dishCount',
            name: dishName,
            description: _text(item['description']) ?? '',
            price: 0,
            options: const <DishOption>[],
          ),
        );
      }
      if (dishes.isEmpty) return;
      categories.add(
        MenuCategory(
          id: 'jsonld-${categories.length + 1}',
          name: name,
          dishes: dishes,
        ),
      );
    }

    void addSection(Map<String, Object?> section, String fallbackName) {
      final name = _text(section['name']) ?? fallbackName;
      addCategory(name, _list(section['hasMenuItem']));
      for (final child in _list(section['hasMenuSection'])) {
        if (child is Map<String, Object?>) addSection(child, name);
      }
    }

    for (final menu in _nodesOfType(blocks, 'Menu')) {
      final name = _text(menu['name']) ?? 'Menu';
      addCategory(name, _list(menu['hasMenuItem']));
      for (final section in _list(menu['hasMenuSection'])) {
        if (section is Map<String, Object?>) addSection(section, name);
      }
    }
    return categories.isEmpty ? null : categories;
  }

  /// The first menu page a `hasMenu` (or a `Menu`'s own `url`) points to,
  /// resolved against [base], or null when there is none.
  static Uri? menuUrlFrom(List<Object?> blocks, Uri base) {
    for (final node in _allNodes(blocks)) {
      for (final target in _list(node['hasMenu'])) {
        final url = target is Map<String, Object?>
            ? _text(target['url']) ?? _text(target['@id'])
            : _text(target);
        final resolved = _httpUri(url, base);
        if (resolved != null) return resolved;
      }
    }
    for (final menu in _nodesOfType(blocks, 'Menu')) {
      final resolved = _httpUri(_text(menu['url']), base);
      if (resolved != null) return resolved;
    }
    return null;
  }

  static Uri? _httpUri(String? value, Uri base) {
    if (value == null) return null;
    final Uri resolved;
    try {
      resolved = base.resolve(value);
    } on FormatException {
      return null;
    }
    final scheme = resolved.scheme;
    return scheme == 'http' || scheme == 'https' ? resolved : null;
  }

  /// Every JSON object anywhere in [blocks], `@graph` members included,
  /// outermost first.
  static Iterable<Map<String, Object?>> _allNodes(List<Object?> blocks) sync* {
    final pending = <Object?>[...blocks];
    for (var i = 0; i < pending.length; i++) {
      final next = pending[i];
      if (next is Map<String, Object?>) {
        yield next;
        pending.addAll(next.values);
      } else if (next is List<Object?>) {
        pending.addAll(next);
      }
    }
  }

  /// The objects whose `@type` is [type] or a list holding it, in
  /// document order.
  static List<Map<String, Object?>> _nodesOfType(
    List<Object?> blocks,
    String type,
  ) {
    final found = <Map<String, Object?>>[];
    void visit(Object? node) {
      if (node is List<Object?>) {
        node.forEach(visit);
      } else if (node is Map<String, Object?>) {
        if (_list(node['@type']).contains(type)) {
          found.add(node);
          return;
        }
        node.values.forEach(visit);
      }
    }

    blocks.forEach(visit);
    return found;
  }

  static List<Object?> _list(Object? value) => switch (value) {
    null => const <Object?>[],
    final List<Object?> list => list,
    final other => <Object?>[other],
  };

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
