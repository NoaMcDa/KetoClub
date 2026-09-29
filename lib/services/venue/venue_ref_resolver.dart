import 'package:ketoclub/models/venue.dart';

/// Bare tokens made only of ASCII digits: how a pasted 10bis restaurant
/// id is told apart from a pasted Wolt slug (see [VenueRefResolver]).
final RegExp _digitsOnly = RegExp(r'^[0-9]+$');

/// A bare Wolt slug: three or more lower-case ASCII alphanumerics or
/// hyphens, starting with an alphanumeric, and carrying at least one
/// hyphen. Issue #169: a bare single word like `pizza` used to be
/// accepted as a slug and offered as "Show the keto menu", which read as
/// KetoClub having a menu for anything you type. Requiring a hyphen means
/// the input has to look like a real slug (`vitrina-lilinblum`,
/// `hamosad-food`), not an English word.
final RegExp _hyphenatedSlug = RegExp(r'^[a-z0-9][a-z0-9-]*-[a-z0-9-]*$');

/// Turns what a user pasted into a [VenueRef] (architecture.md §6.5,
/// Tier A: paste a URL or ID, shipped before venue search).
///
/// Pure: no network call and no other I/O, so a paste can be resolved
/// the instant it lands in the search box. [resolve] accepts five
/// shapes:
///
/// - A Wolt venue URL in the documented
///   `wolt.com/{lang}/{country}/{city}/restaurant/{slug}` form (with or
///   without a scheme, and with any query string or fragment). The
///   locale and city segments vary across venues, so this looks for the
///   `restaurant` path segment itself rather than assuming a fixed path
///   depth, and reads the segment right after it as the slug.
/// - A bare Wolt slug, e.g. `vitrina-lilinblum` — the canonical real
///   slug used across this repo's docs. Only a hyphenated form is
///   accepted (issue #169): a single English word like `pizza` used to
///   resolve as a Wolt slug and offered "Show the keto menu", reading as
///   though KetoClub had a menu for the word itself. Requiring a hyphen
///   filters that out without needing an explicit platform prefix.
/// - A `10bis.co.il` restaurant URL. 10bis's own web app puts the
///   numeric restaurant id (the same id its `Restaurants/{id}/Menu` API
///   takes — `menu_api_research` §3.2) somewhere in the path after a
///   `restaurants` segment, with slug and action segments such as
///   `menu`/`delivery` in between (e.g.
///   `10bis.co.il/next/restaurants/menu/delivery/123456/some-slug`), so
///   this looks for the `restaurants` segment and then takes the first
///   purely-numeric segment after it, the same "find the landmark
///   segment, don't assume a fixed depth" approach as the Wolt case
///   above. `10bis.co.il` was unreachable from the build environment
///   (see the fixture note in `menu_api_research`), so this shape is
///   inferred from the documented API path rather than a recorded page;
///   re-verify against a real 10bis restaurant URL before release.
/// - A bare 10bis restaurant id, e.g. `123456`.
/// - Any other `http`/`https` URL, on a host with a dot in it and no
///   user info: a restaurant's own website (architecture.md D19; issue
///   #181). Its [VenueRef.platformId] is the URL normalised by
///   [normaliseWebsiteUrl]. Wolt and 10bis keep priority: a URL on either
///   host that is not a venue page is still null, never a website.
///
/// A bare token (anything that is not itself a recognisable URL) is told
/// apart by shape, not by an explicit platform prefix: a 10bis id is
/// always numeric and a Wolt slug never is (see `menu_api_research`), so
/// "digits-only" is an unambiguous test. Anything else non-empty is read
/// as a Wolt slug.
///
/// The resolved [VenueRef] for a 10bis input still carries
/// `MenuSource.tenbis`, which `MenuRepository` has no adapter for yet
/// and so still fails with `unsupportedSource` — recognising the URL is
/// this class's whole job; fetching from it is Phase 2 (architecture.md
/// §17, "What is NOT built yet").
///
/// [platformUrl] is [resolve]'s inverse: it derives the venue's own page
/// on its platform from an already-resolved [VenueRef], for the "open on
/// {platform}" action in the menu header (issue #53). It answers null for
/// a source [resolve] can produce but this class cannot yet turn back
/// into a URL (Tabit, Ontopo).
abstract final class VenueRefResolver {
  /// Returns null when [input] is not something KetoClub can read:
  /// empty or whitespace-only input, a URL that is not `http`/`https`,
  /// has no dotted host or carries user info, a Wolt or 10bis host
  /// with no landmark path segment (or a `10bis.co.il` URL with no
  /// numeric id after it), anything that would otherwise resolve to an
  /// empty [VenueRef.platformId], or a bare token that carries no hyphen
  /// (issue #169: not slug-shaped).
  static VenueRef? resolve(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final uri = _asUri(trimmed);
    if (uri != null) return _fromUri(uri);

    if (_digitsOnly.hasMatch(trimmed)) {
      return VenueRef(source: MenuSource.tenbis, platformId: trimmed);
    }
    if (_hyphenatedSlug.hasMatch(trimmed)) {
      return VenueRef(source: MenuSource.wolt, platformId: trimmed);
    }
    return null;
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

  /// Resolves an already-parsed [uri] by host: `wolt.com` (or a
  /// subdomain) goes to [_fromWoltUri], `10bis.co.il` (or a subdomain)
  /// to [_fromTenBisUri], and any other host to [_fromWebsiteUri] — a
  /// lookalike such as `wolt.com.evil.com` is neither host nor a true
  /// subdomain of it, so it is read as the website it is.
  static VenueRef? _fromUri(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host == 'wolt.com' || host.endsWith('.wolt.com')) {
      return _fromWoltUri(uri);
    }
    if (host == '10bis.co.il' || host.endsWith('.10bis.co.il')) {
      return _fromTenBisUri(uri);
    }
    return _fromWebsiteUri(uri);
  }

  /// Resolves a restaurant website [uri] (D19): null unless
  /// [normaliseWebsiteUrl] accepts it.
  static VenueRef? _fromWebsiteUri(Uri uri) {
    final normalised = normaliseWebsiteUrl(uri);
    if (normalised == null) return null;
    return VenueRef(source: MenuSource.website, platformId: normalised);
  }

  /// The form a website URL is stored in (D19), or null when [uri] is not
  /// one: not `http`/`https`, a host with no dot (`localhost`), or user
  /// info in the URL.
  ///
  /// Lower-cases the scheme and host, drops the fragment, a default port
  /// and one trailing `/`, and keeps the path and query as given, so the
  /// same page pasted twice is the same cache entry.
  static String? normaliseWebsiteUrl(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    final host = uri.host.toLowerCase();
    if (!host.contains('.') || host.startsWith('.') || host.endsWith('.')) {
      return null;
    }
    if (uri.userInfo.isNotEmpty) return null;
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return Uri(
      scheme: scheme,
      host: host,
      port: uri.hasPort ? uri.port : null,
      path: path,
      query: uri.hasQuery ? uri.query : null,
    ).toString();
  }

  /// The host of a website [ref] (`cafe.co.il`), which the screens show in
  /// place of a platform's brand (D19), or null for any other source.
  static String? websiteHost(VenueRef ref) {
    if (ref.source != MenuSource.website) return null;
    final host = Uri.tryParse(ref.platformId)?.host ?? '';
    return host.isEmpty ? null : host;
  }

  /// Resolves a `wolt.com` [uri]: null unless its path holds a
  /// `restaurant` segment followed by a non-empty slug.
  static VenueRef? _fromWoltUri(Uri uri) {
    final segments = uri.pathSegments;
    final restaurantIndex = segments.indexOf('restaurant');
    if (restaurantIndex == -1 || restaurantIndex + 1 >= segments.length) {
      return null;
    }
    final slug = segments[restaurantIndex + 1];
    if (slug.isEmpty) return null;
    return VenueRef(source: MenuSource.wolt, platformId: slug);
  }

  /// Resolves a `10bis.co.il` [uri]: null unless its path holds a
  /// `restaurants` segment (case-insensitive, matching the API's own
  /// `Restaurants` casing) followed somewhere later by a purely-numeric
  /// segment, the restaurant id. Intermediate segments such as `menu`,
  /// `delivery` or a name slug are skipped over rather than assumed
  /// absent, the same tolerance [_fromWoltUri] gives the locale and
  /// city segments in a Wolt URL.
  static VenueRef? _fromTenBisUri(Uri uri) {
    final segments = uri.pathSegments;
    final restaurantsIndex = segments.indexWhere(
      (segment) => segment.toLowerCase() == 'restaurants',
    );
    if (restaurantsIndex == -1) return null;
    for (var i = restaurantsIndex + 1; i < segments.length; i++) {
      if (_digitsOnly.hasMatch(segments[i])) {
        return VenueRef(source: MenuSource.tenbis, platformId: segments[i]);
      }
    }
    return null;
  }

  /// Wolt's own venue page for [slug] (issue #53):
  /// `https://wolt.com/en/isr/tel-aviv/restaurant/{slug}`.
  ///
  /// The locale and city segments are Wolt's own path shape, not a
  /// KetoClub encoding of anything — [_fromWoltUri] reads any locale and
  /// any city back the same way, so hard-coding `en` and `tel-aviv` here
  /// costs nothing at read time. **The city segment is unverified**:
  /// `wolt.com` was unreachable from the build environment (the same
  /// limitation this class's own doc comment already records for the
  /// 10bis shape below), so this assumes Wolt redirects a URL with the
  /// wrong city to the venue's real city rather than 404ing on it. This
  /// is unconfirmed; the user should verify it against a real Wolt link
  /// before release.
  static Uri _woltUrl(String slug) =>
      Uri.https('wolt.com', '/en/isr/tel-aviv/restaurant/$slug');

  /// 10bis's own venue page for [id] (issue #53):
  /// `https://www.10bis.co.il/next/restaurants/menu/delivery/{id}`, the
  /// same `menu/delivery` shape [_fromTenBisUri] already tolerates when
  /// reading a pasted 10bis URL back. Unverified for the same reason
  /// [_woltUrl] gives for Wolt's city segment — see also this class's own
  /// doc comment on the 10bis URL shape.
  static Uri _tenBisUrl(String id) =>
      Uri.https('www.10bis.co.il', '/next/restaurants/menu/delivery/$id');

  /// The venue's own page on the platform [ref] names, for an "open on
  /// {platform}" action in the menu header (issue #53) — or null when
  /// [VenueRef.source] has no known URL form (Tabit, Ontopo, and a scan,
  /// which has no platform page at all).
  ///
  /// Pure, like [resolve]: no I/O, so a caller can decide whether to show
  /// the button the instant a menu loads. Round-trips through [resolve]
  /// for every source this answers non-null for —
  /// `resolve(platformUrl(ref).toString())` gives back a [VenueRef] equal
  /// to [ref] — which this class's tests assert directly, since a broken
  /// link the header ships is worse than no button at all.
  static Uri? platformUrl(VenueRef ref) => switch (ref.source) {
    MenuSource.wolt => _woltUrl(ref.platformId),
    MenuSource.tenbis => _tenBisUrl(ref.platformId),
    // A website's own page is the URL it was pasted as (D19).
    MenuSource.website => Uri.tryParse(ref.platformId),
    MenuSource.tabit || MenuSource.ontopo || MenuSource.scan => null,
  };
}
