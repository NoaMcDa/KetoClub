import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';

/// The result of asking a [PlatformMenuAdapter] for one venue's menu
/// (architecture.md §6.1, §10).
///
/// Not constructed directly; use [MenuFetched] or [MenuFetchFailed].
@immutable
sealed class MenuFetchResult {
  /// Subclasses only.
  const new();
}

/// A menu was obtained, either freshly fetched or served from cache.
@immutable
final class MenuFetched extends MenuFetchResult {
  /// Creates a fetched result carrying [menu]. [fromCache] marks a cached
  /// menu served instead of a fresh fetch; [staleReason] must be null
  /// unless [fromCache] is true.
  const new({required this.menu, this.fromCache = false, this.staleReason});

  /// The menu, fresh or cached.
  final Menu menu;

  /// Whether [menu] was served from cache instead of freshly fetched.
  final bool fromCache;

  /// Why fresh data could not be had, when a cached menu is served
  /// instead.
  ///
  /// Non-null only when [fromCache] is true (architecture.md §10, row 1).
  final MenuFetchFailureReason? staleReason;

  @override
  bool operator ==(Object other) =>
      other is MenuFetched &&
      other.menu == menu &&
      other.fromCache == fromCache &&
      other.staleReason == staleReason;

  @override
  int get hashCode => Object.hash(menu, fromCache, staleReason);

  @override
  String toString() =>
      'MenuFetched(${menu.venueRef.cacheKey}, fromCache: $fromCache)';
}

/// A menu could not be obtained at all: no fresh fetch succeeded and no
/// cached menu was available to fall back to.
@immutable
final class MenuFetchFailed extends MenuFetchResult {
  /// Creates a failed result for [reason]. [statusCode] is present for
  /// [MenuFetchFailureReason.platformChanged], so a schema drift is
  /// diagnosable from the failure copy.
  const new({required this.reason, this.statusCode});

  /// Why the fetch failed.
  final MenuFetchFailureReason reason;

  /// The HTTP status code that triggered [reason], when there is one.
  final int? statusCode;

  @override
  bool operator ==(Object other) =>
      other is MenuFetchFailed &&
      other.reason == reason &&
      other.statusCode == statusCode;

  @override
  int get hashCode => Object.hash(reason, statusCode);

  @override
  String toString() => 'MenuFetchFailed($reason)';
}

/// Fetches and normalises menus from one restaurant platform
/// (architecture.md §6.1).
///
/// One implementation per [MenuSource]. Does two things and only two: an
/// HTTP fetch (or the token dance a platform needs), and normalisation of
/// the platform's payload into the shared [Menu] model. Nothing in this
/// interface throws across its boundary.
abstract interface class PlatformMenuAdapter {
  /// The platform this adapter reads from. Stable across calls.
  MenuSource get source;

  /// Whether this adapter can fetch [ref].
  ///
  /// True only when `ref.source` equals [source]. Never throws.
  bool canHandle(VenueRef ref);

  /// Fetches the menu for [ref].
  ///
  /// Never throws: a network error, a non-2xx response, or an
  /// unexpectedly shaped body are all reported as a [MenuFetchFailed]
  /// result rather than an exception. A returned [MenuFetched] carries a
  /// menu whose [Menu.venueRef] equals [ref] — an adapter may not return
  /// someone else's menu.
  Future<MenuFetchResult> fetch(VenueRef ref);
}
