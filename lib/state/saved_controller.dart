import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';
import 'package:ketoclub/utils/allergens/group_evaluator.dart';
import 'package:ketoclub/utils/banto_mode.dart';
import 'package:ketoclub/utils/profile_wording.dart';
import 'package:ketoclub/utils/visit_profile.dart';

/// What a Recent row shows in place of the keto score (Banto, issue #411).
enum RecentRowKind {
  /// Today's row: the keto score and the green and yellow counts. Every
  /// row of a build without Banto, or under a keto-only profile.
  keto,

  /// The four state counts the menu had for the profile as it is now.
  states,

  /// The profile is not the one the menu was last counted for (or it was
  /// never counted for one): no numbers, a hint to open the menu again.
  recheck,
}

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

  /// Whether the post-meal prompt can list this row's dishes: the cached
  /// menu is still on the device, or the visit kept its strict dishes
  /// (Banto, #411).
  bool get canAskStaff => isCached || visit.strictDishes != null;

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
  ///
  /// With a [SettingsStore] and `load(bantoMode: true)` the list is read for
  /// the profile the device holds (Banto, #411, #412): per-profile counts,
  /// a "re-check" hint, and the "Worked for me" mark and filter. Without
  /// either, the list is exactly the keto list.
  new(
    this._repository, [
    this._history = const NoVisitHistoryStore(),
    this._settings,
  ]);

  final MenuRepository _repository;

  /// Where the active profiles are read from (Banto); null reads none.
  final SettingsStore? _settings;

  /// The menus opened on this device (issue #307): what [entries] lists.
  final VisitHistoryStore _history;

  bool _isLoading = false;
  List<RecentEntry> _entries = const <RecentEntry>[];

  /// The people the device reads menus for, and how the union of their
  /// profiles words a verdict; both are the keto defaults until [load] reads
  /// the settings under Banto.
  List<NamedProfile> _people = const <NamedProfile>[];
  ProfileWording _wording = ProfileWording.ketoOnly;
  String? _fingerprint;
  bool _workedOnly = false;

  /// Whether [load] is currently reading the history and the cache.
  bool get isLoading => _isLoading;

  /// Every listed menu not currently [hide]den, most recently opened
  /// ([VisitEntry.lastOpenedAt]) first; with [workedOnly], only those
  /// marked as having worked for the people the device reads menus for.
  List<RecentEntry> get entries => List.unmodifiable(
    workedOnly ? _entries.where(isWorkedFor).toList() : _entries,
  );

  /// How the profile the device holds words a verdict (Banto, #411);
  /// [ProfileWording.ketoOnly] without Banto or with an empty profile.
  ProfileWording get wording => _wording;

  /// Whether the list is read for a profile with a restriction besides
  /// keto: what swaps the keto badge for the state counts and offers the
  /// "Worked for me" mark.
  bool get readsProfile => _wording.usesStates;

  /// What [entry]'s row shows in place of the keto score (Banto, #411).
  RecentRowKind rowKindFor(RecentEntry entry) {
    if (!readsProfile) return RecentRowKind.keto;
    final visit = entry.visit;
    return visit.hasStates && visit.profileFingerprint == _fingerprint
        ? RecentRowKind.states
        : RecentRowKind.recheck;
  }

  /// The people [entry]'s venue "worked for" among those the device reads
  /// menus for, by name, in the order they were marked (Banto, #412);
  /// empty without a profile.
  List<String> workedForOf(RecentEntry entry) => readsProfile
      ? markedAmong(entry.visit.workedFor, _people)
      : const <String>[];

  /// Whether [entry]'s venue is marked as having worked for anyone the
  /// device reads menus for.
  bool isWorkedFor(RecentEntry entry) => workedForOf(entry).isNotEmpty;

  /// Whether any listed menu carries a mark: what shows the filter chip.
  bool get hasWorkedMarks => _entries.any(isWorkedFor);

  /// Whether the list is narrowed to the marked menus. A filter only: it
  /// never orders or counts anything (D27).
  bool get workedOnly => _workedOnly && readsProfile && hasWorkedMarks;

  /// Narrows the list to the marked menus, or shows all again.
  void setWorkedOnly({required bool value}) {
    if (_workedOnly == value) return;
    _workedOnly = value;
    notifyListeners();
  }

  /// Marks (or unmarks) the venue [ref] as having worked for the people
  /// the device reads menus for (Banto, #412); other people's marks stay.
  /// Written to the visit history, then the row is rebuilt from it. Does
  /// nothing without a profile. Never throws.
  Future<void> setWorked(VenueRef ref, {required bool worked}) async {
    if (!readsProfile) return;
    final names = <String>[for (final p in _people) workedForNameOf(p)];
    final current = await _history.read(ref);
    if (current == null) return;
    await _history.setWorkedFor(ref, <String>[
      for (final name in current.workedFor)
        if (!names.contains(name)) name,
      if (worked) ...names,
    ]);
    final updated = await _history.read(ref);
    final index = _entries.indexWhere((entry) => entry.ref == ref);
    if (updated == null || index == -1) return;
    _entries = List<RecentEntry>.of(_entries)
      ..[index] = RecentEntry(visit: updated, cached: _entries[index].cached);
    notifyListeners();
  }

  /// Reads the visit history and the cache, and joins them by [VenueRef]:
  /// one [RecentEntry] per visit, most recently opened first.
  ///
  /// With [bantoMode] and a settings store it also reads the profiles the
  /// device reads menus for (Banto, #411), so the rows speak that profile.
  Future<void> load({bool bantoMode = BantoMode.enabled}) async {
    _isLoading = true;
    notifyListeners();

    await _readProfile(bantoMode: bantoMode);
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

  /// Reads the active profiles into [wording] and the fingerprint rows are
  /// compared with; the keto defaults without Banto or a settings store.
  Future<void> _readProfile({required bool bantoMode}) async {
    final settings = _settings;
    if (!bantoMode || settings == null) {
      _people = const <NamedProfile>[];
      _wording = ProfileWording.ketoOnly;
      _fingerprint = null;
      return;
    }
    final read = await settings.read();
    _people = read.activeProfiles;
    final profile = GroupEvaluator.union(<DietaryProfile>[
      for (final person in _people) person.profile,
    ]);
    _wording = ProfileWording.of(profile, bantoMode: true);
    _fingerprint = profileFingerprintOf(profile);
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
        visit: current.visit.renamed(name: cleanName, city: cleanCity),
        cached: current.cached,
      );
    notifyListeners();
  }

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
