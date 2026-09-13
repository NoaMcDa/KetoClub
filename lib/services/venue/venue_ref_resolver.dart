import 'package:ketoclub/models/venue.dart';

/// Bare tokens made only of ASCII digits: how a pasted 10bis restaurant
/// id is told apart from a pasted Wolt slug (see [VenueRefResolver]).
final RegExp _digitsOnly = RegExp(r'^[0-9]+$');

/// Turns what a user pasted into a [VenueRef] (architecture.md §6.5,
/// Tier A: paste a URL or ID, shipped before venue search).
///
/// Pure: no network call and no other I/O, so a paste can be resolved
/// the instant it lands in the search box. [resolve] accepts three
/// shapes:
///
/// - A Wolt venue URL in the documented
///   `wolt.com/{lang}/{country}/{city}/restaurant/{slug}` form (with or
///   without a scheme, and with any query string or fragment). The
///   locale and city segments vary across venues, so this looks for the
///   `restaurant` path segment itself rather than assuming a fixed path
///   depth, and reads the segment right after it as the slug.
/// - A bare Wolt slug, e.g. `vitrina-lilinblum` — the canonical real
///   slug used across this repo's docs.
/// - A bare 10bis restaurant id, e.g. `123456`.
///
/// A bare token (anything that is not itself a recognisable URL) is told
/// apart by shape, not by an explicit platform prefix: a 10bis id is
/// always numeric and a Wolt slug never is (see `menu_api_research`), so
/// "digits-only" is an unambiguous test. Anything else non-empty is read
/// as a Wolt slug.
abstract final class VenueRefResolver {
  /// Returns null when [input] is not something KetoClub can read:
  /// empty or whitespace-only input, a URL on a host other than
  /// `wolt.com`, a `wolt.com` URL with no `restaurant` path segment, or
  /// anything that would otherwise resolve to an empty
  /// [VenueRef.platformId].
  static VenueRef? resolve(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final uri = _asUri(trimmed);
    if (uri != null) return _fromUri(uri);

    if (_digitsOnly.hasMatch(trimmed)) {
      return VenueRef(source: MenuSource.tenbis, platformId: trimmed);
    }
    return VenueRef(source: MenuSource.wolt, platformId: trimmed);
  }

  /// Parses [trimmed] as an absolute URI.
  ///
  /// A scheme-qualified string (`https://wolt.com/...`) parses directly.
  /// A bare `domain/path` string (`wolt.com/...`, no scheme) does not —
  /// [Uri.tryParse] reads it as a relative reference with no host — so
  /// this adds `https://` first when the text before the first `/`
  /// looks like a domain (it contains a `.`), then retries. Returns null
  /// when [trimmed] does not look like a URL at all, so a bare slug or
  /// id falls through to the token path in [resolve].
  static Uri? _asUri(String trimmed) {
    final direct = Uri.tryParse(trimmed);
    if (direct != null && direct.host.isNotEmpty) return direct;

    final firstSlash = trimmed.indexOf('/');
    if (firstSlash <= 0) return null;
    if (!trimmed.substring(0, firstSlash).contains('.')) return null;
    return Uri.tryParse('https://$trimmed');
  }

  /// Resolves an already-parsed [uri]: null unless its host is
  /// `wolt.com` (or a subdomain of it) and its path holds a `restaurant`
  /// segment followed by a non-empty slug.
  static VenueRef? _fromUri(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host != 'wolt.com' && !host.endsWith('.wolt.com')) return null;

    final segments = uri.pathSegments;
    final restaurantIndex = segments.indexOf('restaurant');
    if (restaurantIndex == -1 || restaurantIndex + 1 >= segments.length) {
      return null;
    }
    final slug = segments[restaurantIndex + 1];
    if (slug.isEmpty) return null;
    return VenueRef(source: MenuSource.wolt, platformId: slug);
  }
}
