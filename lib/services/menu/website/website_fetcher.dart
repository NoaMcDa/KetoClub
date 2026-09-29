import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/failures.dart';

/// What one [WebsiteFetcher.fetch] produced (architecture.md D19).
@immutable
sealed class WebsiteFetchResult {
  /// Subclasses only.
  const new();
}

/// An HTML page, decoded to text.
final class WebsitePage extends WebsiteFetchResult {
  /// Creates a page whose markup is [html], read from [finalUrl].
  const new({required this.html, required this.finalUrl});

  /// The page's markup.
  final String html;

  /// Where the page was read from once redirects were followed: the base
  /// its relative links resolve against.
  final Uri finalUrl;
}

/// A PDF document, as bytes: read by the vision path, never through a
/// text layer (D19).
final class WebsitePdf extends WebsiteFetchResult {
  /// Creates a PDF holding [bytes], read from [finalUrl].
  const new({required this.bytes, required this.finalUrl});

  /// The document's raw bytes.
  final Uint8List bytes;

  /// Where the document was read from once redirects were followed.
  final Uri finalUrl;
}

/// The document could not be fetched, for [reason].
final class WebsiteFetchFailed extends WebsiteFetchResult {
  /// Creates a failure for [reason], with the site's [statusCode] when
  /// one explains it.
  const new({required this.reason, this.statusCode});

  /// Why nothing was fetched.
  final MenuFetchFailureReason reason;

  /// The HTTP status behind [reason], when there is one.
  final int? statusCode;

  @override
  String toString() => 'WebsiteFetchFailed($reason)';
}

/// Fetches one page of a restaurant's website, politely (architecture.md
/// D19; issue #181).
///
/// Two implementations with the same rules: `DirectWebsiteFetcher` on
/// iOS and Android, which fetch sites themselves (D17), and
/// `BackendWebsiteFetcher` on web, where a browser cannot read another
/// site (D11). Either way the request is logged out, names KetoClub in its
/// User-Agent (where the platform lets it), honours `robots.txt` and the
/// `noai`/TDM opt-out headers, and is size-capped. Never throws.
abstract interface class WebsiteFetcher {
  /// Fetches [url] as an HTML page or a PDF.
  Future<WebsiteFetchResult> fetch(Uri url);
}
