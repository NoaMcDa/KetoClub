import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// Turns pasted text into a [Menu] the existing classifiers read like any
/// other (architecture.md D18; issue #83).
///
/// Pure: no I/O, and [parse] never throws. Text is the one classifier
/// input (D5), so a pasted menu needs no engine of its own; it only needs
/// to become dishes. The rules, in the order they apply to each line:
///
/// - Lines are trimmed and blank ones dropped, though a blank line is
///   remembered, because it can end a section header.
/// - A trailing price (`45`, `45 ₪`, `₪45`, `45.90 NIS`, see
///   [pastedPriceSuffix]) is stripped, and a line that was only a price
///   disappears. Prices never reach a dish, so none can reach a prompt or
///   a card.
/// - A line ending in `:` is a section header.
/// - A line starting with `-`, `(` or a lowercase letter, straight after a
///   dish, is that dish's description continued (a wrapped line).
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

    final categories = <MenuCategory>[];
    var categoryId = _uncategorisedId;
    var categoryName = uncategorisedName;
    var dishes = <Dish>[];
    var headerCount = 0;
    var dishCount = 0;
    // Whether the previous kept line was a dish, so a wrapped line has
    // something to join: cleared by a blank line and by a header.
    var canContinue = false;

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

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) {
        canContinue = false;
        continue;
      }
      if (dishCount >= maxAnalysedDishes) break;

      final cleaned = line.replaceFirst(pastedPriceSuffix, '').trim();
      // Nothing left, or nothing but punctuation: not a dish.
      if (!_hasLetterOrDigit.hasMatch(cleaned)) continue;

      if (cleaned.endsWith(':')) {
        final name = cleaned.substring(0, cleaned.length - 1).trim();
        if (name.isNotEmpty) {
          startCategory(name);
          continue;
        }
      }

      if (canContinue && _continuesDish(cleaned)) {
        final last = dishes.removeLast();
        final part = cleaned.replaceFirst(_bulletStart, '');
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
        continue;
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

  static final RegExp _lineBreak = RegExp(r'\r\n|\r|\n');
  static final RegExp _digit = RegExp(r'\d');
  static final RegExp _hasLetterOrDigit = RegExp(
    r'[\p{L}\p{N}]',
    unicode: true,
  );
  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _lowercaseStart = RegExp(r'^\p{Ll}', unicode: true);
  static final RegExp _bulletStart = RegExp(r'^-+\s*');

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

  /// Whether [cleaned] reads as the wrapped tail of the dish above it.
  static bool _continuesDish(String cleaned) =>
      cleaned.startsWith('-') ||
      cleaned.startsWith('(') ||
      _lowercaseStart.hasMatch(cleaned);
}
