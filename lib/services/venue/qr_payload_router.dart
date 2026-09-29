import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/venue/venue_ref_resolver.dart';

/// Where a scanned QR code's text goes (architecture.md §6.6; issue #182).
sealed class QrTarget {
  const new();
}

/// A menu KetoClub can open: a Wolt or 10bis venue page, or any other web
/// page or PDF, which is read as a restaurant website (D19). [ref] is what
/// the menu screen loads.
@immutable
final class QrVenue extends QrTarget {
  /// Creates the target for [ref].
  const new(this.ref);

  /// The venue to open.
  final VenueRef ref;

  @override
  bool operator ==(Object other) => other is QrVenue && other.ref == ref;

  @override
  int get hashCode => ref.hashCode;
}

/// A code that names a platform KetoClub cannot read yet. [name] is the
/// platform's display name, for the copy that says so.
@immutable
final class QrUnsupportedSource extends QrTarget {
  /// Creates the target for the platform called [name].
  const new(this.name);

  /// The platform's display name, such as `Tabit`.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is QrUnsupportedSource && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// A code with no menu behind it that KetoClub can follow: a social profile
/// or link-in-bio page, plain text, or a URL that names no venue. The
/// useful advice is to photograph the menu itself.
@immutable
final class QrPhotographInstead extends QrTarget {
  /// Creates the target; it holds no state.
  const new();

  @override
  bool operator ==(Object other) => other is QrPhotographInstead;

  @override
  int get hashCode => (QrPhotographInstead).hashCode;
}

/// Decides where a decoded QR payload goes (issue #182). Pure: no network
/// call and no other I/O, so the answer is there the instant a code is
/// read, and the whole table of kinds is testable without a camera.
///
/// What a table QR resolves to in Israel is a short list
/// (`docs/menu_sources_research.md` §3.6); each kind lands as follows.
///
/// - A Wolt or 10bis venue page, a restaurant's own site, a PDF (on
///   `static.rest.co.il` or anywhere), a Wix site's menu page and an
///   Israeli QR-menu SaaS page (tafryt, C-MENU, OurMenu, qrmenu.co.il):
///   [QrVenue], through [VenueRefResolver.resolve]. Wolt and 10bis reach
///   their adapters, everything else the website adapter, which fetches a
///   `.pdf` and hands it to the vision path as one page.
/// - A Tabit ordering page: [QrUnsupportedSource], since no Tabit adapter
///   exists (issue #176 tracks it).
/// - Instagram, Linktree, any payload that is not a URL, and a URL that is
///   not a venue page: [QrPhotographInstead].
abstract final class QrPayloadRouter {
  /// Classifies [payload], the text a QR code decoded to. Never throws.
  static QrTarget classify(String payload) {
    final trimmed = payload.trim();
    // A URL has no whitespace in it; "Table 12" or a sentence containing a
    // dotted word is text, not a link.
    if (trimmed.isEmpty || _whitespace.hasMatch(trimmed)) {
      return const QrPhotographInstead();
    }
    final uri = VenueRefResolver.parseUrl(trimmed);
    if (uri == null) return const QrPhotographInstead();

    final host = uri.host.toLowerCase();
    // Tabit is not supported until its adapter exists (issue #176).
    if (_isTabit(host, uri.path.toLowerCase())) {
      return const QrUnsupportedSource(_tabitName);
    }
    if (_onAnyHost(host, _photographHosts)) {
      return const QrPhotographInstead();
    }
    final ref = VenueRefResolver.resolve(trimmed);
    return ref == null ? const QrPhotographInstead() : QrVenue(ref);
  }

  static final RegExp _whitespace = RegExp(r'\s');

  static const String _tabitName = 'Tabit';

  /// Hosts Tabit serves its ordering pages from: the Israeli site, the
  /// cloud host (Tabit Pay's `pay.tabit.cloud` among them) and the US
  /// mirror.
  static const List<String> _tabitHosts = <String>[
    'tabitisrael.co.il',
    'tabit.cloud',
    'tabit.us',
  ];

  /// Social profiles and link-in-bio pages, none of which is a menu.
  static const List<String> _photographHosts = <String>[
    'instagram.com',
    'instagr.am',
    'linktr.ee',
  ];

  static bool _isTabit(String host, String path) =>
      _onAnyHost(host, _tabitHosts) ||
      host.contains('tabit-order') ||
      path.contains('tabit-order');

  /// Whether [host] is one of [hosts] or a subdomain of one.
  static bool _onAnyHost(String host, List<String> hosts) => hosts.any(
    (candidate) => host == candidate || host.endsWith('.$candidate'),
  );
}
