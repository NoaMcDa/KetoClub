// HTML here is written as adjacent string literals that concatenate into
// one document; markup needs no whitespace between tags, and adding it
// would change what these tests pin.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/menu/website/website_html.dart';

final Uri _base = Uri.parse('https://cafe.example/he/');

void main() {
  group('WebsiteHtml.lines', () {
    test('breaks at blocks, joins cells and drops what a reader never '
        'sees', () {
      const html =
          '<head><title>T</title></head><nav>Home</nav><!-- note -->'
          '<h2>Starters</h2><table><tr><td>Caesar</td><td>52</td></tr>'
          '</table><script>var x = "<p>no</p>";</script>'
          '<p>Fish &amp; chips&nbsp;&#8362;&#x20AA;</p><footer>Tel</footer>';

      expect(WebsiteHtml.lines(html), <String>[
        'Starters',
        'Caesar 52',
        'Fish & chips ₪₪',
      ]);
    });

    test('decodes entities, leaving unknown ones and bad numbers alone', () {
      expect(
        WebsiteHtml.decodeEntities('&unknown; &#0; &lsquo;x&rsquo;'),
        '&unknown;   ‘x’',
      );
    });
  });

  group('WebsiteHtml.isJavaScriptOnly', () {
    test('a bare app shell is JavaScript-only', () {
      expect(
        WebsiteHtml.isJavaScriptOnly(
          '<div id="root"></div><script src="/app.js"></script>',
        ),
        isTrue,
      );
    });

    test('a noscript plea with little text is JavaScript-only', () {
      expect(
        WebsiteHtml.isJavaScriptOnly(
          '<noscript>Please enable JavaScript.</noscript><p>Loading</p>',
        ),
        isTrue,
      );
    });

    test('a rendered page is not, scripts or no scripts', () {
      final menu = List.filled(40, '<p>Caesar salad 52</p>').join();
      expect(
        WebsiteHtml.isJavaScriptOnly('$menu<script>track()</script>'),
        isFalse,
      );
      expect(WebsiteHtml.isJavaScriptOnly('<p>Closed today.</p>'), isFalse);
      expect(
        WebsiteHtml.isJavaScriptOnly('$menu<noscript>javascript</noscript>'),
        isFalse,
      );
    });
  });

  group('WebsiteHtml.reservesAi', () {
    test('robots noai, our own name and tdm-reservation opt out', () {
      for (final html in [
        '<meta name="robots" content="noindex, noai">',
        "<meta name='KetoClubBot' content='noai'>",
        '<meta content="1" name="tdm-reservation">',
      ]) {
        expect(WebsiteHtml.reservesAi(html), isTrue, reason: html);
      }
    });

    test('ordinary meta tags do not', () {
      expect(
        WebsiteHtml.reservesAi(
          '<meta charset="utf-8"><meta name=robots content=index>'
          '<meta name="tdm-reservation" content="0">',
        ),
        isFalse,
      );
    });
  });

  group('WebsiteHtml.jsonLdBlocks', () {
    test('decodes each block and skips the malformed one', () {
      const html =
          '<script type="application/ld+json">{"@type":"Menu"}</script>'
          "<script type='application/ld+json'>{ nope</script>"
          '<script>{"@type":"Ignored"}</script>';

      expect(WebsiteHtml.jsonLdBlocks(html), <Object?>[
        <String, Object?>{'@type': 'Menu'},
      ]);
    });
  });

  group('WebsiteHtml.links', () {
    test('resolves relative links and keeps only http(s) targets', () {
      const html =
          '<a href="menu">Menu</a><a class="x" href=\'/files/m.pdf#p2\'>'
          '<b>PDF</b></a><a href="#top">Top</a><a href="mailto:a@b.c">M</a>'
          '<a href="tel:035551234">T</a><a href="javascript:void(0)">J</a>'
          '<a name="no-href">N</a><a href="https://other.example/x?a=1&amp;b=2">'
          'Other</a><a href="http://[bad">Bad</a>';

      expect(WebsiteHtml.links(html, _base), <PageLink>[
        PageLink(uri: Uri.parse('https://cafe.example/he/menu'), text: 'Menu'),
        PageLink(
          uri: Uri.parse('https://cafe.example/files/m.pdf'),
          text: 'PDF',
        ),
        PageLink(
          uri: Uri.parse('https://other.example/x?a=1&b=2'),
          text: 'Other',
        ),
      ]);
    });

    test('PageLink has value semantics', () {
      final a = PageLink(uri: _base, text: 'x');
      expect(a, PageLink(uri: _base, text: 'x'));
      expect(a.hashCode, PageLink(uri: _base, text: 'x').hashCode);
      expect(a.toString(), contains('PageLink'));
    });
  });
}
