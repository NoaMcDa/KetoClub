import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/services/menu/website/json_ld_menu_mapper.dart';
import 'package:ketoclub/services/menu/website/website_html.dart';

/// Where [WebsiteMenuLocator.locate] found a page's menu (D19).
@immutable
sealed class MenuLocation {
  /// Subclasses only.
  const new();
}

/// The page carries a schema.org menu with items: step 1.
final class JsonLdMenuFound extends MenuLocation {
  /// Creates a location holding [categories].
  const new(this.categories);

  /// The menu's sections and items, mapped by [JsonLdMenuMapper].
  final List<MenuCategory> categories;
}

/// The page links to its menu — a menu page or a PDF: step 2.
final class MenuLinkFound extends MenuLocation {
  /// Creates a location pointing at [uri].
  const new(this.uri);

  /// The menu page or PDF to fetch next.
  final Uri uri;

  /// Whether [uri] names a PDF.
  bool get isPdf => uri.path.toLowerCase().endsWith('.pdf');
}

/// Neither: the page's own text is all there is to read: step 3.
final class NoMenuLink extends MenuLocation {
  /// The one instance.
  const new();
}

/// Finds a restaurant page's menu (architecture.md D19; issue #181), and
/// reads a menu out of a page's text.
///
/// Pure: no I/O and nothing throws, so it runs the same on every platform
/// whichever way the page was fetched (the backend on web, directly on a
/// phone, D17). [locate] tries, in order:
///
/// 1. JSON-LD `Menu` / `MenuSection` / `MenuItem` markup with named items.
/// 2. A link to the menu: the JSON-LD `hasMenu` URL first, then the page's
///    own links whose address or text says "menu" or "תפריט", or that end
///    in `.pdf`. A menu-named PDF comes first, then a menu-named page, then
///    any PDF, each group in page order. A page link must stay on the same
///    site (`www.` aside); a PDF may live elsewhere (menus are often on a
///    file host). A link back to the page itself is skipped.
/// 3. Nothing: the caller reads the page itself with [menuText].
abstract final class WebsiteMenuLocator {
  /// Where [html], fetched from [pageUrl], keeps its menu.
  static MenuLocation locate(String html, Uri pageUrl) {
    final blocks = WebsiteHtml.jsonLdBlocks(html);
    final categories = JsonLdMenuMapper.categoriesFrom(blocks);
    if (categories != null) return JsonLdMenuFound(categories);

    final fromJsonLd = JsonLdMenuMapper.menuUrlFrom(blocks, pageUrl);
    if (fromJsonLd != null && !_samePage(fromJsonLd, pageUrl)) {
      return MenuLinkFound(fromJsonLd);
    }

    MenuLinkFound? best;
    var bestScore = 0;
    for (final link in WebsiteHtml.links(html, pageUrl)) {
      if (_samePage(link.uri, pageUrl)) continue;
      final isPdf = link.uri.path.toLowerCase().endsWith('.pdf');
      final named = _namesMenu(link);
      if (!isPdf && !(named && _sameSite(link.uri, pageUrl))) continue;
      final score = named && isPdf ? 3 : (named ? 2 : 1);
      if (score > bestScore) {
        best = MenuLinkFound(link.uri);
        bestScore = score;
      }
    }
    return best ?? const NoMenuLink();
  }

  /// The words that mark a link as the menu, in its address or its text.
  static const List<String> menuWords = <String>['menu', 'תפריט'];

  /// The fewest priced lines a page needs before its text is read as a
  /// menu: a homepage with one "from 45" line is not one.
  static const int minPricedLines = 3;

  static final RegExp _priceOnly = RegExp(
    r'^(?:₪\s*)?\d{1,4}(?:[.,]\d{1,2})?\s*(?:₪|NIS|ILS|ש["״]ח)?$',
    caseSensitive: false,
  );
  static final RegExp _trailingPrice = RegExp(
    r'(?:\s+|\s*[-–—:.…|]+\s*)(?:₪\s*)?\d{1,4}(?:[.,]\d{1,2})?'
    r'(?:\s*(?:₪|NIS|ILS|ש["״]ח))?\s*$',
    caseSensitive: false,
  );
  static final RegExp _letter = RegExp(r'\p{L}', unicode: true);
  static final RegExp _endsInDigit = RegExp(r'[\d\-–/]$');
  static final RegExp _bullet = RegExp(r'^[-•*·▪►]+\s*');
  static final RegExp _lowercaseStart = RegExp(r'^\p{Ll}', unicode: true);
  static final RegExp _whitespace = RegExp(r'\s+');

  /// The page's menu as lines `TextMenuSource.parse` reads — a header per
  /// `Name:` line, a dish per line, its description on a `- ` line after
  /// it — or null when fewer than [minPricedLines] lines carry a price.
  ///
  /// Prices are how a menu is told apart from the rest of a page, and
  /// only the stretch from the first priced line to the last is read, so
  /// navigation above and contact details below never become dishes. A
  /// page whose prices sit on their own lines ("Caesar salad" /
  /// "romaine, parmesan" / "52") reads each price as closing a dish:
  /// the line before it is the description when there are two, and a
  /// third line before those is a section header. A page whose prices end
  /// the dish line ("Caesar salad 52") reads each priced line as a dish,
  /// and the lines after it as its description, except a short last line
  /// (three words, no comma) right before the next dish, which is a
  /// header. Nothing after the last priced dish is read: that is the
  /// page's footer. The prices themselves are dropped, as a paste's are
  /// (D18).
  static String? menuText(String html) {
    final lines = WebsiteHtml.lines(html);
    var priceOnly = 0;
    var inline = 0;
    for (final line in lines) {
      if (_priceOnly.hasMatch(line)) {
        priceOnly += 1;
      } else if (_inlineDishName(line) != null) {
        inline += 1;
      }
    }
    if (priceOnly + inline < minPricedLines) return null;
    final out = priceOnly >= inline
        ? _fromSeparatePrices(lines)
        : _fromInlinePrices(lines);
    return out.isEmpty ? null : out.join('\n');
  }

  static List<String> _fromSeparatePrices(List<String> lines) {
    final out = <String>[];
    var pending = <String>[];
    for (final line in lines) {
      if (!_priceOnly.hasMatch(line)) {
        pending.add(line);
        continue;
      }
      final block = pending;
      pending = <String>[];
      if (block.isEmpty) continue;
      if (block.length == 1) {
        _emitDish(out, block[0], const <String>[]);
      } else {
        if (block.length >= 3) _emitHeader(out, block[block.length - 3]);
        _emitDish(out, block[block.length - 2], <String>[block.last]);
      }
    }
    return out;
  }

  static List<String> _fromInlinePrices(List<String> lines) {
    final out = <String>[];
    var between = <String>[];
    var description = <String>[];
    var haveDish = false;
    String? name;

    void closeDish() {
      final current = name;
      if (current != null) _emitDish(out, current, description);
      name = null;
      description = <String>[];
    }

    for (final line in lines) {
      final dishName = _inlineDishName(line);
      if (dishName == null) {
        between.add(line);
        continue;
      }
      if (!haveDish) {
        if (between.isNotEmpty && _looksLikeHeader(between.last)) {
          _emitHeader(out, between.last);
        }
      } else if (between.length == 1 && _looksLikeHeader(between.single)) {
        closeDish();
        _emitHeader(out, between.single);
      } else if (between.length > 1) {
        description.addAll(between.sublist(0, between.length - 1));
        closeDish();
        _emitHeader(out, between.last);
      } else {
        description.addAll(between);
      }
      closeDish();
      name = dishName;
      haveDish = true;
      between = <String>[];
    }
    // Lines after the last priced dish are the page's footer (an address,
    // a phone number), never its description.
    closeDish();
    return out;
  }

  /// The dish name in [line] when it ends in a price, else null. The name
  /// must hold a letter and must not itself end in a digit or a dash, so
  /// "Sunday–Thursday 12–23" and "Tel 03-5551234" are not dishes.
  static String? _inlineDishName(String line) {
    final match = _trailingPrice.firstMatch(line);
    if (match == null) return null;
    final rest = line.substring(0, match.start).trim();
    if (!_letter.hasMatch(rest) || _endsInDigit.hasMatch(rest)) return null;
    return rest;
  }

  static bool _looksLikeHeader(String line) =>
      !line.contains(',') && line.split(_whitespace).length <= 3;

  static void _emitHeader(List<String> out, String line) {
    final name = _clean(line).replaceAll(RegExp(r':+$'), '').trim();
    if (_letter.hasMatch(name)) out.add('$name:');
  }

  static void _emitDish(List<String> out, String line, List<String> about) {
    var name = _clean(line);
    if (name.endsWith(':')) name = name.substring(0, name.length - 1).trim();
    if (!_letter.hasMatch(name)) return;
    // TextMenuSource reads a line starting in lower case as the previous
    // dish's description; a dish name is capitalised so it stays a dish.
    if (_lowercaseStart.hasMatch(name)) {
      name = name[0].toUpperCase() + name.substring(1);
    }
    out.add(name);
    final text = about.map(_clean).where(_letter.hasMatch).join(' ');
    if (text.isNotEmpty) out.add('- $text');
  }

  static String _clean(String line) =>
      line.replaceFirst(_bullet, '').replaceAll(_whitespace, ' ').trim();

  static bool _namesMenu(PageLink link) {
    final address = Uri.decodeFull(link.uri.path).toLowerCase();
    final text = link.text.toLowerCase();
    return menuWords.any(
      (word) => address.contains(word) || text.contains(word),
    );
  }

  static bool _sameSite(Uri a, Uri b) => _bareHost(a) == _bareHost(b);

  static String _bareHost(Uri uri) {
    final host = uri.host.toLowerCase();
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  static bool _samePage(Uri a, Uri b) =>
      _sameSite(a, b) &&
      _trimSlash(a.path) == _trimSlash(b.path) &&
      a.query == b.query;

  static String _trimSlash(String path) =>
      path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}
