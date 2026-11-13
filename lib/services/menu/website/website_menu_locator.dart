import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/services/menu/website/json_ld_menu_mapper.dart';
import 'package:ketoclub/services/menu/website/website_html.dart';
import 'package:ketoclub/utils/constants.dart';

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
///    in `.pdf`. A menu-named PDF comes first, then a page whose own
///    address names the menu (`/menu/food`, `/dairy_menu/`), then a page
///    only its link text names (an events page linked as "תפריט בהתאמה",
///    #480), then any PDF, each group in page order. A page link must stay
///    on the same site (`www.` aside); a PDF may live elsewhere (menus are
///    often on a file host). A link back to the page itself is skipped.
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
      final addressNamed = _addressNamesMenu(link);
      final named = addressNamed || _textNamesMenu(link);
      if (!isPdf && !(named && _sameSite(link.uri, pageUrl))) continue;
      final score = isPdf ? (named ? 4 : 1) : (addressNamed ? 3 : 2);
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

  /// A line that is only a price: an optional `מחיר:`/`price:` label, an
  /// optional currency, the number, an optional currency (one source with
  /// a paste's, [priceCurrencySource]: `₪`, `ש"ח`, `שקלים`, `shkalim`).
  static final RegExp _priceOnly = RegExp(
    r'^(?:(?:מחיר|price)\s*:?\s*)?(?:'
    '$priceCurrencySource'
    r'\s*)?\d{1,4}(?:[.,]\d{1,2})?\s*(?:'
    '$priceCurrencySource'
    r')?$',
    caseSensitive: false,
  );
  static final RegExp _trailingPrice = RegExp(
    r'(?:\s+|\s*[-–—:.…|]+\s*)(?:(?:מחיר|price)\s*:?\s*)?(?:'
    '$priceCurrencySource'
    r'\s*)?\d{1,4}(?:[.,]\d{1,2})?(?:\s*'
    '$priceCurrencySource'
    r')?\s*$',
    caseSensitive: false,
  );

  /// Where a [_trailingPrice] match can start (#268; the Python port's
  /// `_SEPARATOR_RUN_START`). `firstMatch` tries every position, and on a
  /// long run of dashes or spaces each try scans the rest of the run:
  /// quadratic time or worse. The separator opens with whitespace or a
  /// dash-like mark, and a match starting inside a run of either also
  /// starts at the run's first character, so only run starts are tried.
  static final RegExp _separatorRunStart = RegExp(
    r'(?<!\s)\s|(?<![-–—:.…|])[-–—:.…|]',
  );

  /// One maximal run of whitespace, marks, digits or anything else. A
  /// match ends the line and spans at most fifteen of them (the separator
  /// 3, a `מחיר:` label and its spaces 4, a leading currency and space 2,
  /// whole part 1, fraction 2, currency and its space 2, trailing space
  /// 1; #480), so only the line's last [_priceRuns] runs are tried.
  static final RegExp _run = RegExp(r'\s+|[-–—:.…|]+|\d+|[^\d\s\-–—:.…|]+');
  static const int _priceRuns = 16;

  /// `_trailingPrice.firstMatch(line)`, in linear time (#268): the same
  /// match, found by trying only the starts it can have.
  static RegExpMatch? _trailingPriceIn(String line) {
    final runStarts = <int>[for (final run in _run.allMatches(line)) run.start];
    final first = runStarts.length < _priceRuns
        ? 0
        : runStarts[runStarts.length - _priceRuns];
    for (final start in _separatorRunStart.allMatches(line, first)) {
      final match = _trailingPrice.matchAsPrefix(line, start.start);
      if (match != null) return match as RegExpMatch;
    }
    return null;
  }

  /// A dietary tag on a line of its own (`מנה צמחונית`, `ללא גלוטן`,
  /// `vegan`, `GF`): dropped before a page is read, so it never shifts a
  /// dish's name into a header (#480).
  static final RegExp _dietaryTag = RegExp(
    r'^\(?(?:(?:מנה\s+)?(?:צמחונית|צמחוני|טבעונית|טבעוני|חריפה|חריף'
    r'|(?:ללא|נטול(?:ת)?)\s+גלוטן)|vegan|vegetarian|veggie|spicy|v|vg|gf|df'
    r'|gluten[\s-]free|dairy[\s-]free)\)?$',
    caseSensitive: false,
  );

  /// A street address with a number, which ends in a number like a priced
  /// dish does (`Tel Aviv, Dizengoff 99`, `רחוב הרצל 12`, #283): a street
  /// word, or a city before a comma.
  static final RegExp _address = RegExp(
    r'(?:^|[\s,(])(?:רחוב|רח[\x27׳"]|שד[\x27׳"]|שדרות|דרך|כיכר|סמטת)\s'
    r'|\b(?:st|street|ave|avenue|road|rd|blvd|boulevard)\b'
    r'|^(?:tel[\s-]aviv(?:[\s-]yafo)?|jerusalem|haifa|herzliya|ramat[\s-]gan'
    r'|givatayim|holon|bat[\s-]yam|petah[\s-]tikva|ra\x27?anana|kfar[\s-]saba'
    r'|netanya|rishon[\s-]le[\s-]?zion|rehovot|ashdod|ashkelon'
    r'|be\x27?er[\s-]sheva|eilat|modi\x27?in|hod[\s-]hasharon'
    r'|ramat[\s-]hasharon|תל[\s-]אביב(?:[\s-]יפו)?|ירושלים|חיפה|הרצליה'
    r'|רמת[\s-]גן|גבעתיים|חולון|בת[\s-]ים|פתח[\s-]תקו?וה|רעננה|כפר[\s-]סבא'
    r'|נתניה|ראשון[\s-]לציון|רחובות|אשדוד|אשקלון|באר[\s-]שבע|אילת|מודיעין'
    r'|הוד[\s-]השרון|רמת[\s-]השרון)\s*,',
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
    final lines = <String>[
      for (final line in WebsiteHtml.lines(html))
        if (!_dietaryTag.hasMatch(line)) line,
    ];
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
    final out = priceOnly < inline
        ? _fromInlinePrices(lines)
        : _priceFollowsName(lines)
        ? _fromNameThenPrice(lines)
        : _fromSeparatePrices(lines);
    return out.isEmpty ? null : out.join('\n');
  }

  /// The runs of lines between price-only lines: one more run than there
  /// are prices, the first before the first price, the last after the
  /// last.
  static List<List<String>> _runsBetweenPrices(List<String> lines) {
    final runs = <List<String>>[<String>[]];
    for (final line in lines) {
      if (_priceOnly.hasMatch(line)) {
        runs.add(<String>[]);
      } else {
        runs.last.add(line);
      }
    }
    return runs;
  }

  /// Whether the page sets each price straight under the dish's name, with
  /// the description after it (`name / 67 / description`, #480), rather
  /// than after the description: the line after a price is longer than
  /// the line before it for most prices.
  static bool _priceFollowsName(List<String> lines) {
    final runs = _runsBetweenPrices(lines);
    var after = 0;
    var before = 0;
    for (var i = 0; i + 1 < runs.length; i++) {
      if (runs[i].isEmpty || runs[i + 1].isEmpty) continue;
      final wordsBefore = runs[i].last.split(_whitespace).length;
      final wordsAfter = runs[i + 1].first.split(_whitespace).length;
      if (wordsAfter > wordsBefore) {
        after += 1;
      } else if (wordsAfter < wordsBefore) {
        before += 1;
      }
    }
    return after > before;
  }

  /// A page read as `name / price / description`: each price closes the
  /// line before it as a dish name; the first line after it is that
  /// dish's description; a short line between that and the next name is
  /// a section header, and any longer one joins the description. Nothing
  /// after the last dish's description is read.
  static List<String> _fromNameThenPrice(List<String> lines) {
    final out = <String>[];
    final runs = _runsBetweenPrices(lines);
    String? name;
    for (var i = 0; i < runs.length; i++) {
      final run = runs[i];
      final isLast = i == runs.length - 1;
      final description = <String>[];
      var rest = run;
      if (name != null && run.isNotEmpty) {
        description.add(run.first);
        rest = run.sublist(1);
      }
      String? next;
      String? header;
      if (!isLast && rest.isNotEmpty) {
        next = rest.last;
        final between = rest.sublist(0, rest.length - 1);
        if (between.isNotEmpty && _looksLikeHeader(between.last)) {
          header = between.last;
          description.addAll(between.sublist(0, between.length - 1));
        } else {
          description.addAll(between);
        }
      }
      final current = name;
      if (current != null) _emitDish(out, current, description);
      if (header != null) _emitHeader(out, header);
      name = next;
    }
    return out;
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
  /// "Sunday–Thursday 12–23" and "Tel 03-5551234" are not dishes, and must
  /// not read as a street address ("Tel Aviv, Dizengoff 99").
  static String? _inlineDishName(String line) {
    final match = _trailingPriceIn(line);
    if (match == null) return null;
    final rest = line.substring(0, match.start).trim();
    if (!_letter.hasMatch(rest) || _endsInDigit.hasMatch(rest)) return null;
    if (_address.hasMatch(rest)) return null;
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

  static bool _addressNamesMenu(PageLink link) {
    final address = _decodePath(link.uri.path).toLowerCase();
    return menuWords.any(address.contains);
  }

  static bool _textNamesMenu(PageLink link) {
    final text = link.text.toLowerCase();
    return menuWords.any(text.contains);
  }

  /// [path] percent-decoded as UTF-8, else byte by byte as `windows-1255`
  /// (older Hebrew sites encode `תפריט` as `%FA%F4%F8%E9%E8`). Never
  /// throws: [Uri.decodeFull] throws on bytes that are not UTF-8.
  static String _decodePath(String path) {
    try {
      return Uri.decodeFull(path);
    } on FormatException {
      return path.replaceAllMapped(_escape, (match) {
        final byte = int.parse(match.group(1)!, radix: 16);
        // The Hebrew letters of windows-1255 sit at 0xE0–0xFA.
        return String.fromCharCode(
          byte >= 0xE0 && byte <= 0xFA ? 0x05D0 + byte - 0xE0 : byte,
        );
      });
    }
  }

  static final RegExp _escape = RegExp('%([0-9A-Fa-f]{2})');

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
