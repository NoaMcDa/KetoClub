import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';

/// A [MenuRepository] backed by in-memory maps, for controller tests.
///
/// By default [load] synthesises an empty menu for whatever [VenueRef] it is
/// asked for, so the venueRef-provenance invariant holds without a test having
/// to build one. Use [stub] to script a specific outcome per ref, or
/// [stubAll] for every ref.
///
/// Set [loadGate] to hold every [load] open until that future completes,
/// so a test can see how many loads are in flight at once;
/// [maxConcurrentLoads] records the most there ever were (issue #42).
final class FakeMenuRepository implements MenuRepository {
  /// Creates a repository with nothing cached and nothing scripted.
  new();

  final Map<String, MenuFetchResult> _stubs = <String, MenuFetchResult>{};
  final Map<String, CachedMenu> _cached = <String, CachedMenu>{};

  /// The result every ref gets when no per-ref [stub] applies.
  MenuFetchResult? stubAll;

  /// Every `(ref, forceRefresh)` pair [load] was called with, in order.
  final List<({VenueRef ref, bool forceRefresh})> loadCalls =
      <({VenueRef ref, bool forceRefresh})>[];

  /// Every `(ref, analysis)` pair [saveAnalysis] was called with, in order.
  final List<({VenueRef ref, MenuAnalysis analysis})> savedAnalyses =
      <({VenueRef ref, MenuAnalysis analysis})>[];

  /// When non-null, every [load] waits for this future — after being
  /// recorded in [loadCalls] — before it answers.
  Future<void>? loadGate;

  /// How many [load] calls are waiting on [loadGate] right now.
  int concurrentLoads = 0;

  /// The largest [concurrentLoads] has ever been.
  int maxConcurrentLoads = 0;

  /// How many times [clearCache] has been called.
  int clearCacheCallCount = 0;

  /// Every [VenueRef] passed to [remove], in order.
  final List<VenueRef> removedRefs = <VenueRef>[];

  /// When non-null, [savedMenus] waits for this future before it answers
  /// — the same shape `FakeMenuClassifier.gate` uses, so a test can look
  /// at the screen while `SavedController.load` is still in flight
  /// (issue #63).
  Future<void>? savedMenusGate;

  /// Scripts [load] to answer [result] for [ref].
  void stub(VenueRef ref, MenuFetchResult result) {
    _stubs[ref.cacheKey] = result;
  }

  /// Seeds the cache [cached] reads from.
  void seedCache(CachedMenu entry) {
    _cached[entry.menu.venueRef.cacheKey] = entry;
  }

  @override
  Future<MenuFetchResult> load(
    VenueRef ref, {
    bool forceRefresh = false,
  }) async {
    loadCalls.add((ref: ref, forceRefresh: forceRefresh));
    final gate = loadGate;
    if (gate != null) {
      concurrentLoads++;
      if (concurrentLoads > maxConcurrentLoads) {
        maxConcurrentLoads = concurrentLoads;
      }
      await gate;
      concurrentLoads--;
    }
    final stubbed = _stubs[ref.cacheKey] ?? stubAll;
    if (stubbed != null) return stubbed;
    return MenuFetched(
      menu: Menu(
        venueRef: ref,
        currency: 'ILS',
        fetchedAt: DateTime.utc(2026),
        categories: const <MenuCategory>[],
      ),
    );
  }

  @override
  Future<CachedMenu?> cached(VenueRef ref) async => _cached[ref.cacheKey];

  @override
  Future<void> saveAnalysis(VenueRef ref, MenuAnalysis analysis) async {
    savedAnalyses.add((ref: ref, analysis: analysis));
    final entry = _cached[ref.cacheKey];
    if (entry != null) {
      _cached[ref.cacheKey] = CachedMenu(menu: entry.menu, analysis: analysis);
    }
  }

  @override
  Future<void> clearCache() async {
    clearCacheCallCount++;
    _cached.clear();
  }

  @override
  Future<List<CachedMenuEntry>> savedMenus() async {
    final pending = savedMenusGate;
    if (pending != null) await pending;
    return [
      for (final cached in _cached.values)
        CachedMenuEntry(
          ref: cached.menu.venueRef,
          venueName: cached.menu.venueName,
          fetchedAt: cached.menu.fetchedAt,
          dishCount: cached.menu.allDishes.length,
          engine: switch (cached.analysis) {
            final MenuAnalysed analysed => analysed.engine,
            _ => null,
          },
        ),
    ];
  }

  @override
  Future<int> cachedMenuCount() async => _cached.length;

  @override
  Future<void> remove(VenueRef ref) async {
    removedRefs.add(ref);
    _cached.remove(ref.cacheKey);
  }
}
