import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';

/// Screen state for the Saved tab (architecture.md §6.6; issue #48).
///
/// Reads every cached menu through a [MenuRepository] and holds them
/// newest-fetched first. Removal is two-phase so the screen can offer an
/// undo without this class ever having to reconstruct a deleted
/// [CachedMenuEntry]'s full menu: [hide] takes an entry out of [entries]
/// immediately, and [restore] puts it back — both purely in memory,
/// touching no storage — while [commitRemoval] is the one call that
/// actually deletes from the repository, made once a caller decides the
/// undo window has passed.
///
/// Never throws — [MenuRepository] already returns values instead of
/// throwing, or promises not to (architecture.md §18.1).
final class SavedController extends ChangeNotifier {
  /// Creates a controller that lists and removes cached menus through a
  /// [MenuRepository].
  new(this._repository);

  final MenuRepository _repository;

  bool _isLoading = false;
  List<CachedMenuEntry> _entries = const <CachedMenuEntry>[];

  /// Whether [load] is currently reading the repository.
  bool get isLoading => _isLoading;

  /// Every cached menu not currently [hide]den, newest [CachedMenuEntry
  /// .fetchedAt] first.
  List<CachedMenuEntry> get entries => List.unmodifiable(_entries);

  /// Reads every cached menu from the repository, newest first.
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    final saved = await _repository.savedMenus();
    _entries = _sorted(saved);

    _isLoading = false;
    notifyListeners();
  }

  /// Takes the entry for [ref] out of [entries] without deleting it from
  /// storage, and returns it so a caller can offer an undo — see the
  /// class doc. Returns null, and changes nothing, when [ref] is not
  /// currently listed.
  CachedMenuEntry? hide(VenueRef ref) {
    final index = _entries.indexWhere((entry) => entry.ref == ref);
    if (index == -1) return null;
    final removed = _entries[index];
    _entries = List<CachedMenuEntry>.of(_entries)..removeAt(index);
    notifyListeners();
    return removed;
  }

  /// Puts [entry] — previously taken out by [hide] — back into [entries],
  /// keeping the newest-first order. The undo path for [hide].
  void restore(CachedMenuEntry entry) {
    _entries = _sorted([..._entries, entry]);
    notifyListeners();
  }

  /// Deletes [ref]'s cached menu through the repository. Called once an
  /// undo window has passed with no [restore] for it. Never throws.
  Future<void> commitRemoval(VenueRef ref) => _repository.remove(ref);

  /// [source] sorted by [CachedMenuEntry.fetchedAt], newest first.
  List<CachedMenuEntry> _sorted(List<CachedMenuEntry> source) =>
      List<CachedMenuEntry>.of(source)
        ..sort((a, b) => b.fetchedAt.compareTo(a.fetchedAt));
}
