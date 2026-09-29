import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/text/text_menu_source.dart';
import 'package:ketoclub/services/menu/website/website_fetcher.dart';
import 'package:ketoclub/services/menu/website/website_html.dart';
import 'package:ketoclub/services/menu/website/website_menu_locator.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/hebrew_order.dart';

/// Reads a restaurant's menu from its own website (architecture.md D19;
/// issue #181): the third [MenuSource] after Wolt and 10bis, for the
/// dine-in restaurants neither lists.
///
/// [fetch] reads the pasted page through the [WebsiteFetcher] (the backend
/// on web, the site itself on a phone), then:
///
/// 1. A page that opts out of AI use in its `<meta>` tags is
///    [MenuFetchFailureReason.disallowedByRobots]; one that renders only
///    with JavaScript is [MenuFetchFailureReason.jsOnlyPage].
/// 2. [WebsiteMenuLocator.locate] finds the menu: JSON-LD markup becomes
///    the [Menu] directly; a menu link is fetched once (never a second
///    hop); otherwise the page's own text is read.
/// 3. Page text goes through [WebsiteMenuLocator.menuText] into the
///    paste path's [TextMenuSource.parse] (D18), so a site's prices are
///    dropped exactly as a paste's are.
/// 4. A PDF goes to the vision path as one `application/pdf` page — never
///    through a text layer, which reverses most Hebrew PDFs
///    (`docs/menu_sources_research.md` §3.2). The transcription and its
///    analysis come back from the same one request (D6), and the analysis
///    rides on [MenuFetched.analysis] so the repository caches it and the
///    menu screen does not ask the model twice.
///
/// Any text read from a page is rejected as
/// [MenuFetchFailureReason.menuNotFound] when [looksCharacterReversed]
/// says it is reversed Hebrew. Every dish has `price: 0`: a site's price
/// is unverified (M16), and the menu screen shows none for a website.
final class WebsiteMenuAdapter implements PlatformMenuAdapter {
  /// Creates the adapter. [readOptions] supplies the classification
  /// options a PDF is read under — the same ones the menu screen builds
  /// from Settings, so the cached analysis is reused rather than redone.
  new({
    required WebsiteFetcher fetcher,
    required ScannedMenuClassifier scannedClassifier,
    required Future<ClassificationOptions> Function() readOptions,
    required Clock clock,
  })
    // Private fields, public parameter names.
    // ignore: prefer_initializing_formals
    : _fetcher = fetcher,
       // Same reason: a private field, a public parameter name.
       // ignore: prefer_initializing_formals
       _scannedClassifier = scannedClassifier,
       // Same reason: a private field, a public parameter name.
       // ignore: prefer_initializing_formals
       _readOptions = readOptions,
       // Same reason: a private field, a public parameter name.
       // ignore: prefer_initializing_formals
       _clock = clock;

  final WebsiteFetcher _fetcher;
  final ScannedMenuClassifier _scannedClassifier;
  final Future<ClassificationOptions> Function() _readOptions;
  final Clock _clock;

  /// The currency a website menu is stored with: its prices are never
  /// read, and KetoClub serves Israeli venues.
  static const String _currency = 'ILS';

  static final RegExp _hebrew = RegExp('[א-ת]');

  @override
  MenuSource get source => MenuSource.website;

  @override
  bool canHandle(VenueRef ref) => ref.source == MenuSource.website;

  @override
  Future<MenuFetchResult> fetch(VenueRef ref) async {
    final url = Uri.tryParse(ref.platformId);
    if (!canHandle(ref) ||
        url == null ||
        (url.scheme != 'http' && url.scheme != 'https')) {
      return const MenuFetchFailed(
        reason: MenuFetchFailureReason.unsupportedSource,
      );
    }
    return switch (await _fetcher.fetch(url)) {
      WebsiteFetchFailed(:final reason, :final statusCode) => MenuFetchFailed(
        reason: reason,
        statusCode: statusCode,
      ),
      final WebsitePdf pdf => await _readPdf(ref, pdf),
      final WebsitePage page => await _fromPage(ref, page),
    };
  }

  Future<MenuFetchResult> _fromPage(VenueRef ref, WebsitePage page) async {
    if (WebsiteHtml.reservesAi(page.html)) return _optedOut;
    final location = WebsiteMenuLocator.locate(page.html, page.finalUrl);
    // JSON-LD is data in the page source: readable however the page is
    // rendered, so it is taken before the JavaScript-only test.
    if (location is JsonLdMenuFound) {
      return _menuFrom(ref, location.categories);
    }
    if (WebsiteHtml.isJavaScriptOnly(page.html)) return _jsOnly;
    if (location is MenuLinkFound) {
      final linked = await _followLink(ref, location.uri);
      if (linked is MenuFetched) return linked;
      // The linked page had nothing readable: this page's own text is the
      // last resort, and the link's failure the better explanation.
      return _fromText(ref, page.html) ?? linked;
    }
    return _fromText(ref, page.html) ??
        const MenuFetchFailed(reason: MenuFetchFailureReason.menuNotFound);
  }

  /// The one hop a menu link is worth: a PDF goes to vision, a page is
  /// read for JSON-LD or text but never followed further.
  Future<MenuFetchResult> _followLink(VenueRef ref, Uri uri) async {
    switch (await _fetcher.fetch(uri)) {
      case WebsiteFetchFailed(:final reason, :final statusCode):
        return MenuFetchFailed(reason: reason, statusCode: statusCode);
      case final WebsitePdf pdf:
        return await _readPdf(ref, pdf);
      case final WebsitePage page:
        if (WebsiteHtml.reservesAi(page.html)) return _optedOut;
        final location = WebsiteMenuLocator.locate(page.html, page.finalUrl);
        if (location is JsonLdMenuFound) {
          return _menuFrom(ref, location.categories);
        }
        if (WebsiteHtml.isJavaScriptOnly(page.html)) return _jsOnly;
        return _fromText(ref, page.html) ??
            const MenuFetchFailed(reason: MenuFetchFailureReason.menuNotFound);
    }
  }

  static const MenuFetchFailed _optedOut = MenuFetchFailed(
    reason: MenuFetchFailureReason.disallowedByRobots,
  );

  static const MenuFetchFailed _jsOnly = MenuFetchFailed(
    reason: MenuFetchFailureReason.jsOnlyPage,
  );

  /// The menu in [html]'s own text, or null when it holds none.
  MenuFetchResult? _fromText(VenueRef ref, String html) {
    final text = WebsiteMenuLocator.menuText(html);
    if (text == null) return null;
    final parsed = TextMenuSource.parse(
      text,
      now: _clock.now(),
      uncategorisedName: _hebrew.hasMatch(text)
          ? websiteCategoryNameHe
          : websiteCategoryNameEn,
    );
    if (parsed == null) return null;
    return _menuFrom(ref, parsed.categories);
  }

  MenuFetchResult _menuFrom(VenueRef ref, List<MenuCategory> categories) {
    for (final category in categories) {
      for (final dish in category.dishes) {
        if (looksCharacterReversed(dish.name) ||
            looksCharacterReversed(dish.description)) {
          return const MenuFetchFailed(
            reason: MenuFetchFailureReason.menuNotFound,
          );
        }
      }
    }
    return MenuFetched(menu: _stamp(ref, categories));
  }

  Future<MenuFetchResult> _readPdf(VenueRef ref, WebsitePdf pdf) async {
    final scan = ScannedMenu(
      pages: <ScannedPage>[
        ScannedPage(mimeType: ScannedPage.pdf, bytes: pdf.bytes),
      ],
    );
    final result = await _scannedClassifier.classify(
      scan,
      options: await _readOptions(),
    );
    return switch (result) {
      ScannedMenuRead(:final menu, :final analysis) => MenuFetched(
        menu: _stamp(ref, menu.categories),
        analysis: analysis,
      ),
      ScannedMenuFailed() => const MenuFetchFailed(
        reason: MenuFetchFailureReason.websitePdfUnread,
      ),
    };
  }

  Menu _stamp(VenueRef ref, List<MenuCategory> categories) => Menu(
    venueRef: ref,
    currency: _currency,
    fetchedAt: _clock.now(),
    categories: categories,
  );
}
