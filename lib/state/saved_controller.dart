import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';

/// One row of the Recent list (issue #313): a menu opened on this device
/// ([visit], from the [VisitHistoryStore]) joined with its cached copy
/// ([cached], from the [MenuRepository]) when one is still on the device.
///
/// The visit decides whether the row exists and where it sits; the cache
/// only says how fresh it is. Every number the row shows prefers the
/// cached copy, which is the menu as it is now, and falls back to the
/// snapshot the visit took when the menu was last opened.
@immutable
final class RecentEntry {
  /// Creates a row for [visit], with [cached] when its menu is still
  /// cached on this device.
  const new({required this.visit, this.cached});

  /// The menu's entry in the visit history: which menu, under what name,
  /// when it was opened and the numbers it last had.
  final VisitEntry visit;

  /// The menu's cached copy, or null when none is on this device any more.
  final CachedMenuEntry? cached;

  /// Which menu, on which platform, this row is for.
  VenueRef get ref => visit.ref;

  /// The venue name to show: the one the visit recorded, else the cached
  /// menu's own, else null — the screen then falls back to the platform.
  String? get venueName => visit.name ?? cached?.venueName;

  /// The venue's city as the visit recorded it, or null when unknown.
  String? get city => visit.city;

  /// Whether a copy of the menu is still cached on this device.
  bool get isCached => cached != null;

  /// Whether the cached copy is kept past the cache window; always false
  /// when nothing is cached.
  bool get isPinned => cached?.pinned ?? false;

  /// Whether this is a scanned or pasted menu whose only copy has gone
  /// from the device: no platform can serve it again, so it cannot open.
  bool get isGone => !isCached && ref.source == MenuSource.scan;

  /// The keto score out of 10: the cached analysis's when it has one,
  /// else the visit's snapshot; null when neither has a score.
  double? get score => cached?.score ?? visit.score;

  /// How many dishes were placed green, from the same source as [score];
  /// null when that source has no count.
  int? get greenCount =>
      cached?.score != null ? cached?.greenCount : visit.greenCount;

  /// How many dishes were placed yellow, from the same source as [score];
  /// null when that source has no count.
  int? get yellowCount =>
      cached?.score != null ? cached?.yellowCount : visit.yellowCount;

  /// How many dishes the menu has: the cached copy's count, else the
  /// visit's snapshot; null when neither knows.
  int? get dishCount => cached?.dishCount ?? visit.dishCount;

  /// The engine behind the cached analysis, or null when nothing cached
  /// carries a completed one. The visit snapshot records no engine.
  AnalysisEngine? get engine => cached?.engine;

  /// This row with its cached copy's pin replaced by [pinned]; unchanged
  /// when nothing is cached.
  RecentEntry withPinned({required bool pinned}) {
    final current = cached;
    if (current == null) return this;
    return RecentEntry(
      visit: visit,
      cached: current.withPinned(pinned: pinned),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RecentEntry && other.visit == visit && other.cached == cached;

  @override
  int get hashCode => Object.hash(visit, cached);

  @override
  String toString() => 'RecentEntry(${ref.cacheKey}, cached: $isCached)';
}

/// Screen state for the Recent tab (architecture.md §6.6; issues #48,
/// #313).
///
/// Lists every menu in the [VisitHistoryStore], most recently opened
/// first, each joined with its cached copy from the [MenuRepository] when
/// there still is one. A cached menu with no visit is not listed: the
/// history, not the cache, is what the user opened.
///
/// Removal is two-phase so the screen can offer an undo without this
/// class ever having to reconstruct a deleted entry: [hide] takes an entry
/// out of [entries] immediately, and [restore] puts it back — both purely
/// in memory, touching no storage — while [commitRemoval] is the one call
/// that actually deletes, from the history and the cache, made once a
/// caller decides the undo window has passed.
///
/// Never throws — [MenuRepository] and [VisitHistoryStore] already return
/// values instead of throwing, or promise not to (architecture.md §18.1).
final class SavedController extends ChangeNotifier {
  /// Creates a controller that lists the menus in [_history] beside their
  /// cached copies in [_repository]. The optional [VisitHistoryStore]
  /// defaults to [NoVisitHistoryStore], which remembers nothing, so the
  /// list is then always empty (issue #307).
  new(this._repository, [this._history = const NoVisitHistoryStore()]);

  final MenuRepository _repository;

  /// The menus opened on this device (issue #307): what [entries] lists.
  final VisitHistoryStore _history;

  bool _isLoading = false;
  List<RecentEntry> _entries = const <RecentEntry>[];

  /// Whether [load] is currently reading the history and the cache.
  bool get isLoading => _isLoading;

  /// Every listed menu not currently [hide]den, most recently opened
  /// ([VisitEntry.lastOpenedAt]) first.
  List<RecentEntry> get entries => List.unmodifiable(_entries);

  /// Reads the visit history and the cache, and joins them by [VenueRef]:
  /// one [RecentEntry] per visit, most recently opened first.
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    final visits = await _history.entries();
    final saved = await _repository.savedMenus();
    final cachedByKey = <String, CachedMenuEntry>{
      for (final entry in saved) entry.ref.cacheKey: entry,
    };
    _entries = _sorted([
      for (final visit in visits)
        RecentEntry(visit: visit, cached: cachedByKey[visit.ref.cacheKey]),
    ]);

    _isLoading = false;
    notifyListeners();
  }

  /// Takes the entry for [ref] out of [entries] without deleting it from
  /// storage, and returns it so a caller can offer an undo — see the
  /// class doc. Returns null, and changes nothing, when [ref] is not
  /// currently listed.
  RecentEntry? hide(VenueRef ref) {
    final index = _entries.indexWhere((entry) => entry.ref == ref);
    if (index == -1) return null;
    final removed = _entries[index];
    _entries = List<RecentEntry>.of(_entries)..removeAt(index);
    notifyListeners();
    return removed;
  }

  /// Puts [entry] — previously taken out by [hide] — back into [entries],
  /// keeping the most-recently-opened-first order. The undo path for
  /// [hide].
  void restore(RecentEntry entry) {
    _entries = _sorted([..._entries, entry]);
    notifyListeners();
  }

  /// Keeps or stops keeping [ref]'s cached menu past the cache window
  /// ([MenuRepository.pin]). The row flips at once, then the repository
  /// is told; does nothing when [ref] is not currently listed or has no
  /// cached copy to keep. Never throws.
  Future<void> setPinned(VenueRef ref, {required bool pinned}) async {
    final index = _entries.indexWhere((entry) => entry.ref == ref);
    if (index == -1 || !_entries[index].isCached) return;
    _entries = List<RecentEntry>.of(_entries)
      ..[index] = _entries[index].withPinned(pinned: pinned);
    notifyListeners();
    await _repository.pin(ref, pinned: pinned);
  }

  /// Names the scanned menu [ref] [name] in [city] (issue #315): both are
  /// trimmed and an empty one becomes null, which clears it. The history
  /// is written first, then the row in [entries] is rebuilt with the new
  /// values; the row's place in the list does not move. A row that is not
  /// currently listed is still renamed in the history. Never throws.
  Future<void> rename(
    VenueRef ref, {
    required String? name,
    required String? city,
  }) async {
    final cleanName = _blankToNull(name);
    final cleanCity = _blankToNull(city);
    await _history.rename(ref, name: cleanName, city: cleanCity);
    final index = _entries.indexWhere((entry) => entry.ref == ref);
    if (index == -1) return;
    final current = _entries[index];
    _entries = List<RecentEntry>.of(_entries)
      ..[index] = RecentEntry(
        visit: _renamed(current.visit, name: cleanName, city: cleanCity),
        cached: current.cached,
      );
    notifyListeners();
  }

  /// [visit] with its name and city replaced, as the store now holds it.
  static VisitEntry _renamed(
    VisitEntry visit, {
    required String? name,
    required String? city,
  }) => VisitEntry(
    ref: visit.ref,
    name: name,
    city: city,
    firstOpenedAt: visit.firstOpenedAt,
    lastOpenedAt: visit.lastOpenedAt,
    openCount: visit.openCount,
    dishCount: visit.dishCount,
    score: visit.score,
    greenCount: visit.greenCount,
    yellowCount: visit.yellowCount,
  );

  /// [value] trimmed, or null when nothing is left of it.
  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// Forgets [ref]'s menu: its entry in the visit history and its cached
  /// copy, each removed once. Called once an undo window has passed with
  /// no [restore] for it. Never throws.
  Future<void> commitRemoval(VenueRef ref) async {
    await _history.remove(ref);
    await _repository.remove(ref);
  }

  /// [source] sorted by [VisitEntry.lastOpenedAt], most recent first.
  List<RecentEntry> _sorted(List<RecentEntry> source) =>
      List<RecentEntry>.of(source)
        ..sort((a, b) => b.visit.lastOpenedAt.compareTo(a.visit.lastOpenedAt));
}
