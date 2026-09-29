import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';

/// The pages of recent scans, in memory only, keyed by the [VenueRef] of
/// the menu the vision engine read from them (architecture.md §6.2, D15;
/// issue #89).
///
/// A scanned menu's honest source is its pages: the menu screen offers
/// "View pages" so the user can check the transcription against them. The
/// `Menu` is cached like any other, but the pages never are — a
/// [ScannedMenu] has no `toJson`, and this registry is never written to
/// Hive, preferences or a log. They are lost when the app restarts, after
/// which the menu reads like a pasted one.
///
/// Holds at most [capacity] scans; putting one more evicts the oldest, so
/// a session of scanning cannot hold an unbounded number of photographs
/// (each scan may be up to `maxScanPages` × `maxScanPageBytes`).
///
/// The Scan controller puts a scan here as it hands the read menu over
/// (issue #82); the menu screen reads it. Not a `ChangeNotifier`: the
/// pages are put before the menu screen that reads them is pushed.
final class ScannedPagesRegistry {
  /// Creates an empty registry holding at most [capacity] scans.
  new({this.capacity = defaultCapacity})
    : assert(capacity > 0, 'a registry must hold at least one scan');

  /// The [capacity] a registry gets when none is given.
  static const int defaultCapacity = 4;

  /// The most scans kept at once.
  final int capacity;

  // Insertion-ordered (a LinkedHashMap), so the first key is the oldest.
  final Map<VenueRef, ScannedMenu> _scans = <VenueRef, ScannedMenu>{};

  /// Keeps [scan] as the pages [ref]'s menu was read from, replacing any
  /// pages already kept for [ref] and evicting the oldest scan when this
  /// one would exceed [capacity].
  void put(VenueRef ref, ScannedMenu scan) {
    _scans
      ..remove(ref)
      ..[ref] = scan;
    while (_scans.length > capacity) {
      _scans.remove(_scans.keys.first);
    }
  }

  /// The pages [ref]'s menu was read from, or null when none are kept:
  /// the menu was pasted, was read in an earlier run of the app, or its
  /// pages were evicted or removed.
  ScannedMenu? get(VenueRef ref) => _scans[ref];

  /// Forgets the pages kept for [ref], if any.
  void remove(VenueRef ref) {
    _scans.remove(ref);
  }
}
