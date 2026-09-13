import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';

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
}
