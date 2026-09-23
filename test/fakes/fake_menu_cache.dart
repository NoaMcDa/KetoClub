import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';

/// A [MenuCache] backed by an in-memory map, keyed by
/// [VenueRef.cacheKey].
///
/// [failOnRead] and [failOnWrite] make it behave like a broken cache
/// without ever throwing: a read misses and a write is dropped, so a
/// repository's degradation path can be exercised.
final class FakeMenuCache implements MenuCache {
  /// Creates an empty cache.
  new();

  final Map<String, CachedMenu> _entries = <String, CachedMenu>{};

  /// When true, every [read] misses regardless of what was written.
  bool failOnRead = false;

  /// When true, every [write] is dropped instead of stored.
  bool failOnWrite = false;

  /// How many times [clear] has been called.
  int clearCallCount = 0;

  @override
  Future<CachedMenu?> read(VenueRef ref) async {
    if (failOnRead) return null;
    return _entries[ref.cacheKey];
  }

  @override
  Future<void> write(CachedMenu entry) async {
    if (failOnWrite) return;
    _entries[entry.menu.venueRef.cacheKey] = entry;
  }

  @override
  Future<void> clear() async {
    clearCallCount++;
    _entries.clear();
  }

  @override
  Future<int> size() async => _entries.length;

  @override
  Future<int> count() async => _entries.length;

  @override
  Future<void> remove(VenueRef ref) async {
    _entries.remove(ref.cacheKey);
  }

  @override
  Future<List<CachedMenuEntry>> entries() async => [
    for (final cached in _entries.values)
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
