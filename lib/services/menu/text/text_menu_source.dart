import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// Turns pasted text into a [Menu] the existing classifiers read like any
/// other (architecture.md D18; issue #83).
///
/// Pure: no I/O, and [parse] never throws. Text is the one classifier
/// input (D5), so a pasted menu needs no engine of its own; it only needs
/// to become dishes. Each line is first cleaned:
///
/// - Lines are trimmed and blank ones dropped, though a blank line is
///   remembered, because it can end a section header.
/// - A WhatsApp sender prefix (`[12/11/2026, 14:02] Dana: `,
///   [pastedChatPrefix]) is removed (#479).
/// - A line wrapped in `*…*` or `_…_` (WhatsApp bold or italic) loses the
///   markers and is "emphasised"; `*…*` inside a line loses its markers.
/// - A leading bullet is removed and remembered: a dash (`-`, `–`, `—`),
///   a number (`1.`, `2)`), or any run of symbols (`•`, `*`, `▪️`, `🔸`)
///   (#282).
/// - A price is stripped: a trailing one ([pastedPriceSuffix]: `45`,
///   `45 ₪`, `48 ש"ח`, `(128)`, `........ 48`, `48/56`), a leading one
///   ([pastedPricePrefix]: `45 Pasta`, `₪38 Omelette`) and a size's one
///   ([pastedSizedPrice]). A line that was only a price disappears. Prices
///   never reach a dish, so none can reach a prompt or a card. A line that
///   lost a price is "priced".
///
/// Then each line is, in this order:
///
/// - A section header when it ends in `:`, or is emphasised and unpriced.
/// - The previous dish's description continued (a wrapped line), straight
///   after a dish, when it starts with `(`; or with a dash, unless the
///   dish above was itself bulleted (then the dashes are a list); or with
///   a lowercase letter, unless the dish above did too (then the paste is
///   an all-lowercase list). A line with any other bullet never is.
/// - When the paste is priced (at least [_minPricedLines] priced lines,
///   and at least half as many as unpriced ones), an unpriced, unbulleted line
///   straight after a priced dish is that dish's description, unless it is
///   a short all-capitals Latin line (`MAINS`), which is a header; and an
///   unpriced short line (at most [pastedHeaderMaxWords] words, no digits)
///   whose next line is priced is a header (#479). A paste without prices
///   never reaches this rule.
/// - A short line (at most [pastedHeaderMaxWords] words, no digits) that
///   stands alone, with a blank line (or the start of the text) before it
///   and a blank line and then more text after it, is a section header
///   too. Standing alone matters: the last dish of a group is also
///   followed by a blank line, but has a dish right above it. When every
///   line of the paste is separated from the next by a blank one, this
///   rule is off, since otherwise every dish would read as a header.
/// - Every other line is a dish: `price: 0`, no options, id `p1..pN` in
///   line order. At most [maxAnalysedDishes] dishes are kept.
///
/// The result is `null` when no dish survived. Its [VenueRef] is
/// `scan/<hex of TextNormaliser.menuFingerprint>`, so pasting the same
/// dishes again is the same cache entry and the same prompt.
abstract final class TextMenuSource {
  /// The menu [text] describes, stamped [now], or null when it holds no
  /// dish.
  ///
  /// Dishes that appear before any header go into a category named
  /// [uncategorisedName]; a caller shows that name to the user, so a
  /// caller with a locale passes a localised one.
  static Menu? parse(
    String text, {
    required DateTime now,
    String uncategorisedName = 'Pasted menu',
  }) {
    final lines = text.split(_lineBreak).map((line) => line.trim()).toList();
    final blankRuleOn = _hasAdjacentLines(lines);
    final read = [for (final line in lines) _read(line)];
    var pricedCount = 0;
    var unpricedCount = 0;
    for (final line in read) {
      if (line == null) continue;
      if (line.priced) {
        pricedCount += 1;
      } else if (!line.text.endsWith(':')) {
        unpricedCount += 1;
      }
    }
    final pricedPaste =
        pricedCount >= _minPricedLines && pricedCount * 2 >= unpricedCount;

    final categories = <MenuCategory>[];
    var categoryId = _uncategorisedId;
    var categoryName = uncategorisedName;
    var dishes = <Dish>[];
    var headerCount = 0;
    var dishCount = 0;
    // Whether the previous kept line was a dish, so a wrapped line has
    // something to join: cleared by a blank line and by a header.
    var canContinue = false;
    // The line that made the current dish, which decides what may join it.
    _Line? dishLine;

    void startCategory(String name) {
      if (dishes.isNotEmpty) {
        categories.add(
          MenuCategory(id: categoryId, name: categoryName, dishes: dishes),
        );
        dishes = <Dish>[];
      }
      headerCount += 1;
      categoryId = '$_uncategorisedId-$headerCount';
      categoryName = name;
      canContinue = false;
    }

    void describe(String part) {
      final last = dishes.removeLast();
      dishes.add(
        Dish(
          id: last.id,
          name: last.name,
          description: last.description.isEmpty
              ? part
              : '${last.description} $part',
          price: 0,
          options: const <DishOption>[],
        ),
      );
    }

    for (var i = 0; i < lines.length; i++) {
      if (lines[i].isEmpty) {
        canContinue = false;
        continue;
      }
      if (dishCount >= maxAnalysedDishes) break;

      // Nothing left, or nothing but punctuation: not a dish.
      final line = read[i];
      if (line == null) continue;
      final cleaned = line.text;

      if (cleaned.endsWith(':')) {
        final name = cleaned.substring(0, cleaned.length - 1).trim();
        if (name.isNotEmpty) {
          startCategory(name);
          continue;
        }
      }
      if (line.emphasised && !line.priced) {
        startCategory(cleaned);
        continue;
      }

      final above = dishLine;
      if (canContinue && above != null && _continues(line, above)) {
        describe(cleaned);
        continue;
      }

      if (pricedPaste && !line.priced && line.bullet == _Bullet.none) {
        final short =
            !_digit.hasMatch(cleaned) &&
            cleaned.split(_whitespace).length <= pastedHeaderMaxWords;
        if (canContinue && above != null && above.priced) {
          if (short && _isCapitalsOnly(cleaned)) {
            startCategory(cleaned);
          } else {
            describe(cleaned);
          }
          continue;
        }
        if (short && _nextIsPriced(read, i)) {
          startCategory(cleaned);
          continue;
        }
      }

      if (blankRuleOn && _isShortHeader(cleaned, lines, i)) {
        startCategory(cleaned);
        continue;
      }

      dishCount += 1;
      dishes.add(
        Dish(
          id: 'p$dishCount',
          name: cleaned,
          description: '',
          price: 0,
          options: const <DishOption>[],
        ),
      );
      canContinue = true;
      dishLine = line;
    }
    if (dishes.isNotEmpty) {
      categories.add(
        MenuCategory(id: categoryId, name: categoryName, dishes: dishes),
      );
    }
    if (categories.isEmpty) return null;

    final provisional = Menu(
      venueRef: const VenueRef(source: MenuSource.scan, platformId: 'pending'),
      currency: _currency,
      fetchedAt: now,
      categories: categories,
    );
    final fingerprint = TextNormaliser.menuFingerprint(provisional);
    return Menu(
      venueRef: VenueRef(
        source: MenuSource.scan,
        platformId: fingerprint.toRadixString(16).padLeft(8, '0'),
      ),
      currency: _currency,
      fetchedAt: now,
      categories: categories,
    );
  }

  /// The id of the category holding dishes that precede any header; each
  /// header's own category is this with `-N` appended.
  static const String _uncategorisedId = 'pasted';

  /// The currency of a pasted menu: it carries none, and KetoClub only
  /// serves Israel, as `WoltMenuMapper` also assumes. No price is ever
  /// shown for a scan, so this is only ever stored.
  static const String _currency = 'ILS';

  /// The fewest priced lines that make a paste "priced", so that its
  /// unpriced lines read as descriptions and headers (#479). The website
  /// locator asks for as many before it reads a page as a menu.
  static const int _minPricedLines = 3;

  static final RegExp _lineBreak = RegExp(r'\r\n|\r|\n');
  static final RegExp _digit = RegExp(r'\d');
  static final RegExp _hasLetterOrDigit = RegExp(
    r'[\p{L}\p{N}]',
    unicode: true,
  );
  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _space = RegExp(r'^\s$');
  static final RegExp _lowercaseStart = RegExp(r'^\p{Ll}', unicode: true);
  static final RegExp _lowercase = RegExp(r'\p{Ll}', unicode: true);
  static final RegExp _latinCapital = RegExp('[A-Z]');
  static final RegExp _dashBullet = RegExp(r'^[-–—]+\s*');
  static final RegExp _numberBullet = RegExp(r'^\d{1,2}[.)]\s+');
  static final RegExp _emphasis = RegExp(
    r'^([*_])([^*_\s](?:[^*_]*[^*_\s])?)\1$',
  );
  static final RegExp _innerBold = RegExp(r'\*([^*\s](?:[^*]*[^*\s])?)\*');

  /// The characters a line may start with that are not a bullet: an
  /// opening bracket or quote, and the shekel sign of a leading price.
  static const String _notBullets = '(["\'״׳“”„‘’«₪';

  /// [raw], a trimmed line, cleaned as the class docs describe, or null
  /// when nothing but punctuation is left of it.
  static _Line? _read(String raw) {
    var text = raw.replaceFirst(pastedChatPrefix, '');
    var emphasised = false;
    final emphasis = _emphasis.firstMatch(text);
    if (emphasis != null) {
      text = emphasis.group(2)!;
      emphasised = true;
    }
    text = text.replaceAllMapped(_innerBold, (match) => match.group(1)!);
    var bullet = _Bullet.none;
    final dash = _dashBullet.firstMatch(text);
    final number = dash == null ? _numberBullet.firstMatch(text) : null;
    if (dash != null) {
      text = text.substring(dash.end);
      bullet = _Bullet.dash;
    } else if (number != null) {
      text = text.substring(number.end);
      bullet = _Bullet.other;
    } else {
      final runes = text.runes.toList();
      var start = 0;
      while (start < runes.length && _isBulletRune(runes[start])) {
        start += 1;
      }
      if (start > 0) {
        text = String.fromCharCodes(runes.skip(start)).trim();
        bullet = _Bullet.other;
      }
    }
    final withoutSuffix = text.replaceFirst(pastedPriceSuffix, '').trim();
    final withoutPrefix = withoutSuffix.replaceFirst(pastedPricePrefix, '');
    final cleaned = withoutPrefix.replaceAll(pastedSizedPrice, '').trim();
    if (!_hasLetterOrDigit.hasMatch(cleaned)) return null;
    return _Line(
      text: cleaned,
      priced: withoutSuffix != text.trim() || withoutPrefix != withoutSuffix,
      bullet: bullet,
      emphasised: emphasised,
    );
  }

  /// Whether [rune] is part of a leading bullet: not a letter, a number,
  /// whitespace or one of [_notBullets].
  static bool _isBulletRune(int rune) {
    final char = String.fromCharCode(rune);
    return !_hasLetterOrDigit.hasMatch(char) &&
        !_space.hasMatch(char) &&
        !_notBullets.contains(char);
  }

  /// Whether [line] reads as the wrapped tail of the dish [above] made.
  static bool _continues(_Line line, _Line above) {
    switch (line.bullet) {
      case _Bullet.other:
        return false;
      case _Bullet.dash:
        return above.bullet == _Bullet.none;
      case _Bullet.none:
        if (line.text.startsWith('(')) return true;
        return _lowercaseStart.hasMatch(line.text) &&
            !_lowercaseStart.hasMatch(above.text);
    }
  }

  /// Whether [text] holds a Latin capital and no lowercase letter: a
  /// heading set in capitals (`MAINS`).
  static bool _isCapitalsOnly(String text) =>
      _latinCapital.hasMatch(text) && !_lowercase.hasMatch(text);

  /// Whether the next line after [index] that was read is priced.
  static bool _nextIsPriced(List<_Line?> read, int index) {
    for (var i = index + 1; i < read.length; i++) {
      final next = read[i];
      if (next != null) return next.priced;
    }
    return false;
  }

  /// Whether at least two non-blank lines sit next to each other. A paste
  /// with none is double-spaced throughout, so a blank line after a line
  /// says nothing about that line being a header.
  static bool _hasAdjacentLines(List<String> lines) {
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].isNotEmpty && lines[i - 1].isNotEmpty) return true;
    }
    return false;
  }

  /// Whether [cleaned], the price-free text of line [index], is short,
  /// digit-free, alone on its line group and followed by a blank line and
  /// then more text: a header introduces something, so a last line never
  /// is one.
  static bool _isShortHeader(String cleaned, List<String> lines, int index) {
    if (_digit.hasMatch(cleaned)) return false;
    if (index > 0 && lines[index - 1].isNotEmpty) return false;
    if (cleaned.split(_whitespace).length > pastedHeaderMaxWords) return false;
    final next = index + 1;
    if (next >= lines.length || lines[next].isNotEmpty) return false;
    for (var i = next + 1; i < lines.length; i++) {
      if (lines[i].isNotEmpty) return true;
    }
    return false;
  }
}

/// How a pasted line started (#282).
enum _Bullet {
  /// No bullet.
  none,

  /// A dash: a description under a plain dish, a list item under another.
  dash,

  /// A number or a symbol: always a list item.
  other,
}

/// One pasted line after [TextMenuSource] cleaned it.
final class _Line {
  const new({
    required this.text,
    required this.priced,
    required this.bullet,
    required this.emphasised,
  });

  /// The line with its sender prefix, bullet, emphasis and price removed.
  final String text;

  /// Whether a price was stripped from it.
  final bool priced;

  /// How it started.
  final _Bullet bullet;

  /// Whether it was wrapped in `*…*` or `_…_`.
  final bool emphasised;
}
