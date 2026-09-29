// HTML here is written as adjacent string literals that concatenate into
// one document; markup needs no whitespace between tags, and adding it
// would change what these tests pin.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/website/website_adapter.dart';
import 'package:ketoclub/services/menu/website/website_fetcher.dart';

import '../../../fakes/fake_clock.dart';
import '../../../fakes/fake_scanned_menu_classifier.dart';
import '../platform_menu_adapter_contract.dart';

/// A synthetic page from `test/fixtures/website/` (issue #181).
String _fixture(String name) =>
    File('test/fixtures/website/$name').readAsStringSync();

const String _homeUrl = 'https://cafe-noir.example';
final Uri _home = Uri.parse(_homeUrl);
const VenueRef _ref = VenueRef(
  source: MenuSource.website,
  platformId: _homeUrl,
);
final DateTime _now = DateTime.utc(2026, 9, 29, 12);
final Uint8List _pdfBytes = Uint8List.fromList(utf8.encode('%PDF-1.7'));

/// A [WebsiteFetcher] answering a scripted result per URL, and
/// [MenuFetchFailureReason.notFound] for anything unscripted.
final class _ScriptedFetcher implements WebsiteFetcher {
  final Map<Uri, WebsiteFetchResult> results = <Uri, WebsiteFetchResult>{};
  final List<Uri> calls = <Uri>[];

  void page(Uri url, String html) =>
      results[url] = WebsitePage(html: html, finalUrl: url);

  @override
  Future<WebsiteFetchResult> fetch(Uri url) async {
    calls.add(url);
    return results[url] ??
        const WebsiteFetchFailed(
          reason: MenuFetchFailureReason.notFound,
          statusCode: 404,
        );
  }
}

const ClassificationOptions _options = ClassificationOptions(
  estimationConsentGiven: true,
  netCarbLimitGrams: 8,
);

WebsiteMenuAdapter _adapter(
  _ScriptedFetcher fetcher, {
  ScannedMenuClassifier? scanned,
}) => WebsiteMenuAdapter(
  fetcher: fetcher,
  scannedClassifier: scanned ?? FakeScannedMenuClassifier(),
  readOptions: () async => _options,
  clock: FakeClock(_now),
);

List<String> _dishNames(MenuFetchResult result) => [
  for (final category in (result as MenuFetched).menu.categories)
    for (final dish in category.dishes) dish.name,
];

MenuFetchFailureReason? _reason(MenuFetchResult result) =>
    result is MenuFetchFailed ? result.reason : null;

void main() {
  runPlatformMenuAdapterContract(
    'WebsiteMenuAdapter',
    () =>
        _adapter(_ScriptedFetcher()..page(_home, _fixture('jsonld_menu.html'))),
    refItHandles: _ref,
    refItRejects: const VenueRef(source: MenuSource.wolt, platformId: 'a-b'),
  );

  group('WebsiteMenuAdapter (issue #181)', () {
    test('is the website source', () {
      final adapter = _adapter(_ScriptedFetcher());
      expect(adapter.source, MenuSource.website);
      expect(adapter.canHandle(_ref), isTrue);
    });

    test('a ref that is not an http(s) URL is unsupported', () async {
      final fetcher = _ScriptedFetcher();
      for (final id in ['not a url', 'ftp://cafe.example/m', 'http://[x']) {
        final result = await _adapter(fetcher)
            .fetch(VenueRef(source: MenuSource.website, platformId: id));
        expect(_reason(result), MenuFetchFailureReason.unsupportedSource);
      }
      expect(fetcher.calls, isEmpty);
    });

    test('a fetch failure is passed through with its status', () async {
      final fetcher = _ScriptedFetcher();
      for (final reason in [
        MenuFetchFailureReason.disallowedByRobots,
        MenuFetchFailureReason.jsOnlyPage,
        MenuFetchFailureReason.websiteUnreachable,
        MenuFetchFailureReason.websiteTooLarge,
        MenuFetchFailureReason.websiteRateLimited,
        MenuFetchFailureReason.backendUnreachable,
        MenuFetchFailureReason.blockedByBrowser,
      ]) {
        fetcher.results[_home] = WebsiteFetchFailed(
          reason: reason,
          statusCode: 503,
        );
        final result = await _adapter(fetcher).fetch(_ref);
        expect(result, MenuFetchFailed(reason: reason, statusCode: 503));
      }
    });

    test('a JSON-LD menu becomes the menu, unpriced and stamped', () async {
      // Arrange
      final fetcher = _ScriptedFetcher()
        ..page(_home, _fixture('jsonld_menu.html'));

      // Act
      final result = await _adapter(fetcher).fetch(_ref);

      // Assert
      expect(_dishNames(result), [
        'Caesar salad',
        'Entrecote steak',
        'Spaghetti carbonara',
      ]);
      final menu = (result as MenuFetched).menu;
      expect(menu.venueRef, _ref);
      expect(menu.fetchedAt, _now);
      expect(menu.currency, 'ILS');
      expect(menu.allDishes.every((dish) => dish.price == 0), isTrue);
      expect(result.analysis, isNull);
      expect(fetcher.calls, [_home]);
    });

    test('a /menu link is followed once and its text read', () async {
      // Arrange
      final menuPage = Uri.parse('$_homeUrl/food/menu/');
      final fetcher = _ScriptedFetcher()
        ..page(_home, _fixture('menu_link.html'))
        ..page(menuPage, _fixture('menu_page_separate_prices.html'));

      // Act
      final result = await _adapter(fetcher).fetch(_ref);

      // Assert: the Hebrew menu page's dishes, under Hebrew sections.
      expect(_dishNames(result), [
        'סלט קיסר',
        'סלט יווני',
        'אנטריקוט',
        'פסטה ברוטב שמנת',
      ]);
      final menu = (result as MenuFetched).menu;
      expect(menu.categories.map((c) => c.name), ['סלטים', 'עיקריות']);
      expect(menu.allDishes.first.description, 'חסה, פרמזן וקרוטונים');
      expect(menu.allDishes.every((dish) => dish.price == 0), isTrue);
      expect(menu.venueRef, _ref);
      // The menu page's own nav link back to /menu is never followed.
      expect(fetcher.calls, [_home, menuPage]);
    });

    test('a Hebrew תפריט link is followed', () async {
      final menuPage = Uri.parse('$_homeUrl/page-3');
      final fetcher = _ScriptedFetcher()
        ..page(_home, _fixture('hebrew_menu_link.html'))
        ..page(menuPage, _fixture('menu_page_inline_prices.html'));

      final result = await _adapter(fetcher).fetch(_ref);

      expect(_dishNames(result), [
        'Caesar salad',
        'Soup of the day',
        'Grilled salmon',
        'Burger & fries',
      ]);
      expect((result as MenuFetched).menu.categories.map((c) => c.name), [
        'Starters',
        'Mains',
      ]);
    });

    test('a linked page with JSON-LD is mapped', () async {
      final menuPage = Uri.parse('$_homeUrl/food/menu/');
      final fetcher = _ScriptedFetcher()
        ..page(_home, _fixture('menu_link.html'))
        ..page(menuPage, _fixture('jsonld_menu.html'));

      final result = await _adapter(fetcher).fetch(_ref);

      expect(_dishNames(result).first, 'Caesar salad');
    });

    group('a PDF menu', () {
      test('goes to the vision path as one application/pdf page', () async {
        // Arrange
        final pdfUrl = Uri.parse(
          'https://files.example-cdn.com/cafe-noir/Menu-2026.pdf?v=3',
        );
        final fetcher = _ScriptedFetcher()
          ..page(_home, _fixture('pdf_link.html'))
          ..results[pdfUrl] = WebsitePdf(bytes: _pdfBytes, finalUrl: pdfUrl);
        final scanned = FakeScannedMenuClassifier();

        // Act
        final result = await _adapter(fetcher, scanned: scanned).fetch(_ref);

        // Assert: one call, one PDF page, the Settings options.
        expect(scanned.calls, hasLength(1));
        final (scan, options) = scanned.calls.single;
        expect(scan.pages.single.mimeType, ScannedPage.pdf);
        expect(scan.pages.single.bytes, _pdfBytes);
        expect(options, _options);
        // The transcription is re-addressed to the website, and its
        // analysis rides along so nothing classifies it twice.
        final fetched = result as MenuFetched;
        expect(fetched.menu.venueRef, _ref);
        expect(fetched.menu.fetchedAt, _now);
        expect(_dishNames(result), ['Scanned dish 1']);
        expect(fetched.analysis, isA<MenuAnalysed>());
        expect(fetched.analysis!.dishes.single.dishId, 'v1');
      });

      test('pasted directly is read the same way', () async {
        final fetcher = _ScriptedFetcher()
          ..results[_home] = WebsitePdf(bytes: _pdfBytes, finalUrl: _home);

        final result = await _adapter(fetcher).fetch(_ref);

        expect((result as MenuFetched).analysis, isNotNull);
      });

      test('that cannot be read is websitePdfUnread', () async {
        final fetcher = _ScriptedFetcher()
          ..results[_home] = WebsitePdf(bytes: _pdfBytes, finalUrl: _home);
        final scanned = FakeScannedMenuClassifier()
          ..respondWith(
            const ScannedMenuFailed(
              reason: MenuAnalysisFailureReason.consentWithheld,
            ),
          );

        final result = await _adapter(fetcher, scanned: scanned).fetch(_ref);

        expect(_reason(result), MenuFetchFailureReason.websitePdfUnread);
      });
    });

    group('no menu', () {
      test('a page with no link and no priced text is menuNotFound', () async {
        final fetcher = _ScriptedFetcher()
          ..page(_home, _fixture('no_menu.html'));

        final result = await _adapter(fetcher).fetch(_ref);

        expect(_reason(result), MenuFetchFailureReason.menuNotFound);
      });

      test('a page that is itself the menu is read with no link', () async {
        final fetcher = _ScriptedFetcher()
          ..page(_home, _fixture('menu_page_inline_prices.html'));

        final result = await _adapter(fetcher).fetch(_ref);

        expect(_dishNames(result), hasLength(4));
      });

      test("a dead link with no text of the page's own is the link's "
          'failure', () async {
        final fetcher = _ScriptedFetcher()
          ..page(_home, _fixture('menu_link.html'));

        final result = await _adapter(fetcher).fetch(_ref);

        expect(
          result,
          const MenuFetchFailed(
            reason: MenuFetchFailureReason.notFound,
            statusCode: 404,
          ),
        );
      });

      test("a dead link falls back to the page's own menu text", () async {
        final html =
            '<a href="/menu">Menu</a>'
            '${_fixture('menu_page_inline_prices.html')}';
        final fetcher = _ScriptedFetcher()..page(_home, html);

        final result = await _adapter(fetcher).fetch(_ref);

        expect(_dishNames(result), hasLength(4));
      });

      test('a linked page with no menu text is menuNotFound', () async {
        final menuPage = Uri.parse('$_homeUrl/food/menu/');
        final fetcher = _ScriptedFetcher()
          ..page(_home, _fixture('menu_link.html'))
          ..page(menuPage, _fixture('no_menu.html'));

        final result = await _adapter(fetcher).fetch(_ref);

        expect(_reason(result), MenuFetchFailureReason.menuNotFound);
      });
    });

    group('refusals read from the page itself', () {
      test('a noai meta tag is disallowedByRobots', () async {
        final fetcher = _ScriptedFetcher()
          ..page(
            _home,
            '<meta name="robots" content="noai">'
            '${_fixture('menu_page_inline_prices.html')}',
          );

        final result = await _adapter(fetcher).fetch(_ref);

        expect(_reason(result), MenuFetchFailureReason.disallowedByRobots);
      });

      test('a JavaScript-only page is jsOnlyPage, linked or not', () async {
        const shell = '<div id="root"></div><script src="/a.js"></script>';
        final menuPage = Uri.parse('$_homeUrl/food/menu/');
        final direct = _ScriptedFetcher()..page(_home, shell);
        final linked = _ScriptedFetcher()
          ..page(_home, _fixture('menu_link.html'))
          ..page(menuPage, shell);

        expect(
          _reason(await _adapter(direct).fetch(_ref)),
          MenuFetchFailureReason.jsOnlyPage,
        );
        expect(
          _reason(await _adapter(linked).fetch(_ref)),
          MenuFetchFailureReason.jsOnlyPage,
        );
      });

      test('character-reversed Hebrew text is rejected, never shown', () async {
        // "שמן" and "לחם" backwards: words that start with ן and ם.
        const reversed = '<p>ןמש תיז 52</p><p>םחל יתיב 18</p><p>קיסר 40</p>';
        final fetcher = _ScriptedFetcher()..page(_home, reversed);

        final result = await _adapter(fetcher).fetch(_ref);

        expect(_reason(result), MenuFetchFailureReason.menuNotFound);
      });

      test('a reversed description in JSON-LD is rejected too', () async {
        const html =
            '<script type="application/ld+json">{"@type": "Menu", '
            '"hasMenuItem": [{"name": "Salad", "description": "ןמש"}]}'
            '</script>';
        final fetcher = _ScriptedFetcher()..page(_home, html);

        final result = await _adapter(fetcher).fetch(_ref);

        expect(_reason(result), MenuFetchFailureReason.menuNotFound);
      });
    });
  });

  group('MenuFetched.analysis', () {
    test('takes part in equality', () {
      final menu = Menu(
        venueRef: _ref,
        currency: 'ILS',
        fetchedAt: _now,
        categories: const <MenuCategory>[],
      );
      final analysed = MenuAnalysed(
        dishes: const <AnalysedDish>[],
        unclassified: const <String>[],
        engine: const LlmEngine(model: 'm'),
        analysedAt: _now,
      );
      expect(
        MenuFetched(menu: menu, analysis: analysed),
        isNot(MenuFetched(menu: menu)),
      );
      expect(
        MenuFetched(menu: menu, analysis: analysed).hashCode,
        MenuFetched(menu: menu, analysis: analysed).hashCode,
      );
    });
  });
}
