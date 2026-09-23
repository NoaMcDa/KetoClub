import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// Loads a venue's menu, cache first, from whichever platform owns it
/// (architecture.md §6.1).
///
/// This is the only menu-facing service a controller talks to: it owns the
/// adapter registry, decides when a cached menu is too old, and keeps the
/// analysis that was computed from a menu next to it.
///
/// No method throws. Every outcome is a sealed [MenuFetchResult], because a
/// venue that cannot be read is an ordinary thing that happens at a restaurant
/// table and the UI has copy for each reason (architecture.md §10).
abstract interface class MenuRepository {
  /// Returns the menu for [ref], preferring a cached copy that is still fresh.
  ///
  /// With [forceRefresh] the cache is bypassed on the way in but still written
  /// on the way out. When the network fails and a stale cached menu exists, the
  /// result is [MenuFetched] with `fromCache: true` and a `staleReason` naming
  /// why fresh data could not be had — the user sees their menu *and* learns it
  /// may be out of date, which two separate results could not express.
  ///
  /// Returns [MenuFetchFailed] with `unsupportedSource` when no registered
  /// adapter handles [ref]. Never throws.
  Future<MenuFetchResult> load(VenueRef ref, {bool forceRefresh = false});

  /// The cached menu and analysis for [ref], fresh or stale, or null on a miss.
  ///
  /// Reads only; never fetches. Never throws — a corrupt entry is a miss.
  Future<CachedMenu?> cached(VenueRef ref);

  /// Stores [analysis] against the menu already cached for [ref].
  ///
  /// A no-op when no menu is cached, since an analysis is only meaningful
  /// beside the menu it was computed from. Never throws.
  Future<void> saveAnalysis(VenueRef ref, MenuAnalysis analysis);

  /// Forgets every cached menu and analysis. Never throws.
  Future<void> clearCache();

  /// A summary of every menu currently cached, in no particular order —
  /// issue #48's Saved tab is the caller and sorts this itself. Reads
  /// only, through the cache; never touches the network. Never throws.
  Future<List<CachedMenuEntry>> savedMenus();

  /// Removes [ref]'s cached menu and analysis, leaving every other cached
  /// menu untouched. A no-op, not a throw, when nothing is cached for
  /// [ref]. Never throws.
  Future<void> remove(VenueRef ref);
}

/// Cache-first [MenuRepository] (architecture.md §6.1, §6.4, §10).
///
/// Owns the adapter registry: [load] picks the first registered
/// [PlatformMenuAdapter] whose [PlatformMenuAdapter.canHandle] answers a
/// [VenueRef], and fails with [MenuFetchFailureReason.unsupportedSource]
/// — without reading the cache or touching the network — when none does.
///
/// A cached menu younger than [freshFor] is served without a network
/// call. Once it goes stale, the adapter is asked again; if that fetch
/// fails and a stale menu is still on hand, it is served anyway with its
/// staleness explained (`fromCache: true`, `staleReason` set) rather than
/// failing outright — architecture.md §10's "No connection. Showing the
/// cached menu from {date}." row. A refetch that changes no dish text
/// (by [TextNormaliser.menuFingerprint]) keeps the analysis already
/// cached for the old menu; a refetch that changes it discards the
/// analysis, since it described dishes no longer on the menu.
@immutable
final class CachedMenuRepository implements MenuRepository {
  /// Creates a repository over [adapters], caching in [cache] and
  /// stamping freshness from [clock]. [freshFor] defaults to
  /// [menuCacheTtl].
  new({
    required List<PlatformMenuAdapter> adapters,
    required this.cache,
    required this.clock,
    this.freshFor = menuCacheTtl,
  }) : _adapters = List.unmodifiable(adapters);

  /// The registered adapters, one per platform, in registration order.
  final List<PlatformMenuAdapter> _adapters;

  /// Where fetched menus and their analyses are stored between calls.
  final MenuCache cache;

  /// Supplies "now" for the freshness comparison against
  /// [Menu.fetchedAt] (architecture.md §18.4 — no real clock in tests).
  final Clock clock;

  /// How long a cached menu is served without a network call.
  final Duration freshFor;

  @override
  Future<MenuFetchResult> load(
    VenueRef ref, {
    bool forceRefresh = false,
  }) async {
    final adapter = _adapterFor(ref);
    if (adapter == null) {
      return const MenuFetchFailed(
        reason: MenuFetchFailureReason.unsupportedSource,
      );
    }

    final cached = await cache.read(ref);
    if (!forceRefresh && cached != null && _isFresh(cached.menu)) {
      return MenuFetched(menu: cached.menu, fromCache: true);
    }

    final result = await adapter.fetch(ref);
    switch (result) {
      case MenuFetched(menu: final fetched):
        await cache.write(_merge(previous: cached, fetched: fetched));
        return MenuFetched(menu: fetched);
      case MenuFetchFailed(:final reason):
        if (cached != null) {
          return MenuFetched(
            menu: cached.menu,
            fromCache: true,
            staleReason: reason,
          );
        }
        return result;
    }
  }

  @override
  Future<CachedMenu?> cached(VenueRef ref) => cache.read(ref);

  @override
  Future<void> saveAnalysis(VenueRef ref, MenuAnalysis analysis) async {
    final entry = await cache.read(ref);
    if (entry == null) return;
    await cache.write(CachedMenu(menu: entry.menu, analysis: analysis));
  }

  @override
  Future<void> clearCache() => cache.clear();

  @override
  Future<List<CachedMenuEntry>> savedMenus() => cache.entries();

  @override
  Future<void> remove(VenueRef ref) => cache.remove(ref);

  /// The first registered adapter that handles [ref], or null when none
  /// does.
  PlatformMenuAdapter? _adapterFor(VenueRef ref) {
    for (final adapter in _adapters) {
      if (adapter.canHandle(ref)) return adapter;
    }
    return null;
  }

  /// Whether [menu] is still within [freshFor] of [clock]'s current
  /// time. Strictly less-than, so a menu exactly [freshFor] old — not
  /// "younger than [freshFor]" per the doc comment above — is treated as
  /// stale and refetched rather than served once more from cache.
  bool _isFresh(Menu menu) => clock.now().difference(menu.fetchedAt) < freshFor;

  /// Builds the entry to write after a successful fetch of [fetched],
  /// carrying [previous]'s analysis forward when the refetched menu's
  /// dish text fingerprints the same, and dropping it otherwise
  /// (architecture.md §6.4).
  CachedMenu _merge({required CachedMenu? previous, required Menu fetched}) {
    if (previous == null) return CachedMenu(menu: fetched);
    final unchanged =
        TextNormaliser.menuFingerprint(previous.menu) ==
        TextNormaliser.menuFingerprint(fetched);
    return CachedMenu(
      menu: fetched,
      analysis: unchanged ? previous.analysis : null,
    );
  }
}
