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
    ));
    final now = clock.now();
    final existing = _entries[ref.cacheKey];
    _entries[ref.cacheKey] = VisitEntry(
      ref: ref,
      name: name ?? existing?.name,
      city: city ?? existing?.city,
      firstOpenedAt: existing?.firstOpenedAt ?? now,
      lastOpenedAt: now,
      openCount: (existing?.openCount ?? 0) + 1,
      dishCount: dishCount ?? existing?.dishCount,
      score: score ?? existing?.score,
      greenCount: greenCount ?? existing?.greenCount,
      yellowCount: yellowCount ?? existing?.yellowCount,
      openedStrict: openedStrict || (existing?.openedStrict ?? false),
      confirmations: existing?.confirmations ?? const <DishConfirmation>[],
      changeConfirmations:
          existing?.changeConfirmations ?? const <ChangeConfirmation>[],
    );
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
    _entries[ref.cacheKey] = VisitEntry(
      ref: existing.ref,
      name: name,
      city: city,
      firstOpenedAt: existing.firstOpenedAt,
      lastOpenedAt: existing.lastOpenedAt,
      openCount: existing.openCount,
      dishCount: existing.dishCount,
      score: existing.score,
      greenCount: existing.greenCount,
      yellowCount: existing.yellowCount,
      openedStrict: existing.openedStrict,
      confirmations: existing.confirmations,
      changeConfirmations: existing.changeConfirmations,
    );
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
