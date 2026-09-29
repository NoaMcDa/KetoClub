import 'dart:convert';

import 'package:flutter/foundation.dart';

/// One `<a href>` on a page: where it points, resolved against the page's
/// own URL, and the text a reader sees on it.
@immutable
final class PageLink {
  /// Creates a link to [uri] labelled [text].
  const new({required this.uri, required this.text});

  /// The absolute target.
  final Uri uri;

  /// The link's visible text, whitespace collapsed.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is PageLink && other.uri == uri && other.text == text;

  @override
  int get hashCode => Object.hash(uri, text);

  @override
  String toString() => 'PageLink($uri, $text)';
}

/// Pure readings of one HTML page for the website menu source
/// (architecture.md D19; issue #181): its visible lines, links and JSON-LD
/// blocks, and the two signals that stop a read — an AI opt-out and a page
/// that renders only with JavaScript.
///
/// Regular expressions, not a DOM: a restaurant page is read once, for
/// text, and a parse error must never throw. No member performs I/O.
abstract final class WebsiteHtml {
  /// How much visible text a page with a script may have and still be
  /// judged JavaScript-only. The backend applies the same bound
  /// (`backend/app/services/website.py`).
  static const int jsOnlyTextChars = 50;

  /// The same bound when the page's own `<noscript>` asks for JavaScript.
  static const int jsOnlyNoscriptTextChars = 200;

  static final RegExp _comment = RegExp('<!--.*?-->', dotAll: true);
  static final RegExp _invisible = RegExp(
    r'<(script|style|noscript|template|svg|head|nav|footer)\b[^>]*>.*?</\1\s*>',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _scriptsOnly = RegExp(
    r'<(script|style|noscript|template|svg)\b[^>]*>.*?</\1\s*>',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _noscript = RegExp(
    r'<noscript\b[^>]*>(.*?)</noscript\s*>',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _blockTag = RegExp(
    '</?(p|div|li|ul|ol|h[1-6]|tr|table|tbody|thead|section|article|main|'
    'header|aside|br|dd|dt|dl|figure|figcaption|blockquote|pre|hr|form|'
    r'option|label|button)\b[^>]*>',
    caseSensitive: false,
  );
  static final RegExp _cellTag = RegExp(
    r'</?(td|th)\b[^>]*>',
    caseSensitive: false,
  );
  static final RegExp _tag = RegExp('<[^>]+>');
  static final RegExp _spaces = RegExp(r'[ \t\f\v ‎‏]+');
  static final RegExp _lineBreak = RegExp(r'\r\n|\r|\n');
  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _anchor = RegExp(
    r'<a\b([^>]*)>(.*?)</a\s*>',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _meta = RegExp(r'<meta\b[^>]*>', caseSensitive: false);
  static final RegExp _attribute = RegExp(
    r'''([a-zA-Z:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
  );
  static final RegExp _jsonLd = RegExp(
    r'''<script\b[^>]*type\s*=\s*["']?application/ld\+json["']?[^>]*>(.*?)</script\s*>''',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _entity = RegExp('&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);');

  static const Map<String, String> _namedEntities = <String, String>{
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
    'ndash': '–',
    'mdash': '—',
    'hellip': '…',
    'rsquo': '’',
    'lsquo': '‘',
    'rdquo': '”',
    'ldquo': '“',
    'bull': '•',
    'middot': '·',
    'shekel': '₪',
  };

  /// The page's visible text as trimmed, non-blank lines in reading order.
  ///
  /// Drops comments, `<head>`, scripts, styles, templates, SVG, `<nav>` and
  /// `<footer>`; starts a new line at every block element and joins table
  /// cells with a space, so a row reads "Dish 52" as one line.
  static List<String> lines(String html) {
    final withoutHidden = html
        .replaceAll(_comment, ' ')
        .replaceAll(_invisible, '\n');
    final broken = withoutHidden
        .replaceAll(_blockTag, '\n')
        .replaceAll(_cellTag, ' ')
        .replaceAll(_tag, ' ');
    return <String>[
      for (final raw in decodeEntities(broken).split(_lineBreak))
        if (raw.replaceAll(_spaces, ' ').trim() case final line
            when line.isNotEmpty)
          line,
    ];
  }

  /// [text] with HTML character references decoded; an unknown named
  /// reference is left as written.
  static String decodeEntities(String text) =>
      text.replaceAllMapped(_entity, (match) {
        final body = match.group(1) ?? '';
        if (body.startsWith('#')) {
          final hex = body.startsWith('#x') || body.startsWith('#X');
          final code = int.tryParse(
            hex ? body.substring(2) : body.substring(1),
            radix: hex ? 16 : 10,
          );
          if (code == null || code <= 0 || code > 0x10FFFF) return ' ';
          return String.fromCharCode(code);
        }
        return _namedEntities[body.toLowerCase()] ?? match.group(0)!;
      });

  /// Whether the page renders its content only with JavaScript: almost no
  /// visible text beside an executable script, or a `<noscript>` asking
  /// for JavaScript with little text left. Such a page is out of scope for
  /// #181. A JSON-LD block is data, not a script, so it never counts.
  static bool isJavaScriptOnly(String html) {
    final withoutHidden = html
        .replaceAll(_comment, ' ')
        .replaceAll(_scriptsOnly, ' ');
    final text = decodeEntities(withoutHidden.replaceAll(_tag, ' '))
        .replaceAll(_whitespace, ' ')
        .trim();
    final code = html.replaceAll(_jsonLd, ' ').toLowerCase();
    if (code.contains('<script') && text.length < jsOnlyTextChars) {
      return true;
    }
    for (final match in _noscript.allMatches(html)) {
      if ((match.group(1) ?? '').toLowerCase().contains('javascript')) {
        return text.length < jsOnlyNoscriptTextChars;
      }
    }
    return false;
  }

  /// Whether the page opts out of AI use in its own `<meta>` tags:
  /// `robots` (or `ketoclubbot`) with `noai`, or `tdm-reservation` = 1.
  static bool reservesAi(String html) {
    for (final match in _meta.allMatches(html)) {
      final attributes = _attributesOf(match.group(0) ?? '');
      final name = (attributes['name'] ?? '').trim().toLowerCase();
      final content = (attributes['content'] ?? '').trim().toLowerCase();
      if ((name == 'robots' || name == 'ketoclubbot') &&
          content.split(',').map((part) => part.trim()).contains('noai')) {
        return true;
      }
      if (name == 'tdm-reservation' && content == '1') return true;
    }
    return false;
  }

  /// Every JSON-LD block on the page, decoded; a block that is not valid
  /// JSON is skipped.
  static List<Object?> jsonLdBlocks(String html) => <Object?>[
    for (final match in _jsonLd.allMatches(html))
      if (_tryDecode(match.group(1) ?? '') case final Object decoded) decoded,
  ];

  /// Every `http`/`https` link on the page, resolved against [base], in
  /// page order. Fragment-only and `javascript:`/`mailto:`/`tel:` links
  /// are dropped.
  static List<PageLink> links(String html, Uri base) {
    final found = <PageLink>[];
    for (final match in _anchor.allMatches(html)) {
      final href = _attributesOf('<a ${match.group(1) ?? ''}>')['href'];
      if (href == null || href.trim().isEmpty || href.startsWith('#')) {
        continue;
      }
      final Uri target;
      try {
        target = base.resolve(decodeEntities(href.trim())).removeFragment();
      } on FormatException {
        continue;
      }
      if (target.scheme != 'http' && target.scheme != 'https') continue;
      final text = decodeEntities((match.group(2) ?? '').replaceAll(_tag, ' '))
          .replaceAll(_whitespace, ' ')
          .trim();
      found.add(PageLink(uri: target, text: text));
    }
    return found;
  }

  static Map<String, String> _attributesOf(String tag) => <String, String>{
    for (final match in _attribute.allMatches(tag))
      (match.group(1) ?? '').toLowerCase():
          match.group(2) ?? match.group(3) ?? match.group(4) ?? '',
  };

  static Object? _tryDecode(String source) {
    try {
      return jsonDecode(source.trim());
    } on FormatException {
      return null;
    }
  }
}
