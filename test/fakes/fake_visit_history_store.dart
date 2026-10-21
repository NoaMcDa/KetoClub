import 'package:ketoclub/models/dish_confirmation.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';

/// One [FakeVisitHistoryStore.recordVisit] call's arguments.
typedef RecordedVisit = ({
  VenueRef ref,
  String? name,
  String? city,
  int? dishCount,
  double? score,
  int? greenCount,
  int? yellowCount,
  bool openedStrict,
  VisitSnapshot? snapshot,
});

/// A [VisitHistoryStore] backed by an in-memory map keyed by
/// [VenueRef.cacheKey], stamping visits with an injected [Clock] (a
/// `FakeClock` in every test).
final class FakeVisitHistoryStore implements VisitHistoryStore {
  /// Creates an empty history stamped by [clock].
  new(this.clock);

  /// The only source of "now" for [recordVisit].
  final Clock clock;

  final Map<String, VisitEntry> _entries = <String, VisitEntry>{};

  /// Every [recordVisit] call, in call order, with its arguments.
  final List<RecordedVisit> recordCalls = <RecordedVisit>[];

  /// Every [rename] call, in call order, with its arguments.
  final List<({VenueRef ref, String? name, String? city})> renameCalls =
      <({VenueRef ref, String? name, String? city})>[];

  /// Every [setConfirmations] call's ref, in call order (ALG-14).
  final List<VenueRef> confirmationCalls = <VenueRef>[];

  /// Every ref passed to [remove], in call order.
  final List<VenueRef> removedRefs = <VenueRef>[];

  /// How many times [clear] has been called.
  int clearCallCount = 0;

  /// Puts [entry] in the history as if it had been recorded, replacing any
  /// entry for the same ref. Records no call.
  void seed(VisitEntry entry) => _entries[entry.ref.cacheKey] = entry;

  @override
  Future<VisitEntry?> read(VenueRef ref) async => _entries[ref.cacheKey];

  @override
  Future<List<VisitEntry>> entries() async =>
      List<VisitEntry>.of(_entries.values);

  @override
  Future<void> recordVisit(
    VenueRef ref, {
    String? name,
    String? city,
    int? dishCount,
    double? score,
    int? greenCount,
    int? yellowCount,
    bool openedStrict = false,
    VisitSnapshot? snapshot,
  }) async {
    recordCalls.add((
      ref: ref,
      name: name,
      city: city,
      dishCount: dishCount,
      score: score,
      greenCount: greenCount,
      yellowCount: yellowCount,
      openedStrict: openedStrict,
      snapshot: snapshot,
    ));
    _entries[ref.cacheKey] = visitAfterOpening(
      _entries[ref.cacheKey],
      ref,
      clock.now(),
      name: name,
      city: city,
      dishCount: dishCount,
      score: score,
      greenCount: greenCount,
      yellowCount: yellowCount,
      openedStrict: openedStrict,
      snapshot: snapshot,
    );
  }

  /// Every [setWorkedFor] call's ref, in call order (#412).
  final List<VenueRef> workedCalls = <VenueRef>[];

  @override
  Future<void> setWorkedFor(VenueRef ref, Iterable<String> names) async {
    workedCalls.add(ref);
    final existing = _entries[ref.cacheKey];
    if (existing == null) return;
    _entries[ref.cacheKey] = existing.withWorkedFor(names);
  }

  @override
  Future<void> setConfirmations(
    VenueRef ref, {
    required List<DishConfirmation> confirmations,
    required List<ChangeConfirmation> changes,
  }) async {
    confirmationCalls.add(ref);
    final existing = _entries[ref.cacheKey];
    if (existing == null) return;
    _entries[ref.cacheKey] = existing.withConfirmations(
      confirmations: confirmations,
      changes: changes,
    );
  }

  @override
  Future<void> rename(
    VenueRef ref, {
    required String? name,
    required String? city,
  }) async {
    renameCalls.add((ref: ref, name: name, city: city));
    final existing = _entries[ref.cacheKey];
    if (existing == null) return;
    _entries[ref.cacheKey] = existing.renamed(name: name, city: city);
  }

  @override
  Future<void> remove(VenueRef ref) async {
    removedRefs.add(ref);
    _entries.remove(ref.cacheKey);
  }

  @override
  Future<void> clear() async {
    clearCallCount++;
    _entries.clear();
  }
}
