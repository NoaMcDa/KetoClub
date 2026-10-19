import 'dart:async';

import 'package:ketoclub/services/platform/entitlement.dart';

/// Which [FakeEntitlement] method a recorded call was.
enum EntitlementCall {
  /// [FakeEntitlement.refresh].
  refresh,

  /// [FakeEntitlement.localizedPrice].
  localizedPrice,

  /// [FakeEntitlement.purchase].
  purchase,

  /// [FakeEntitlement.restore].
  restore,
}

/// A scripted store [Entitlement] for tests (ALG-18).
///
/// It sells Premium unless built with `sellsPremium: false` and starts
/// without it unless built with `premium: true`. With nothing queued a
/// working store is what it behaves like: [purchase] activates Premium,
/// [restore] and [refresh] answer what [isPremium] already is, and
/// [localizedPrice] answers [price]. [queuePurchase], [queueRestore] and
/// [queueRefresh] script one answer each, in order; an answer of
/// [PremiumActive] or [PremiumInactive] also sets [isPremium], as the
/// store's own answer would, and reports the change on [changes]. Every
/// call is recorded in [calls].
final class FakeEntitlement implements Entitlement {
  /// Creates the store.
  new({this.sellsPremium = true, this._premium = false, this.price = '₪19.90'});

  @override
  final bool sellsPremium;

  /// What [localizedPrice] answers; null for a store with no price.
  String? price;

  bool _premium;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();
  final List<EntitlementResult> _purchases = <EntitlementResult>[];
  final List<EntitlementResult> _restores = <EntitlementResult>[];
  final List<EntitlementResult> _refreshes = <EntitlementResult>[];

  /// Every call made, in call order.
  final List<EntitlementCall> calls = <EntitlementCall>[];

  @override
  bool get isPremium => _premium;

  @override
  Stream<bool> get changes => _changes.stream;

  /// Sets [isPremium] as a store-side change would (an approved pending
  /// purchase, a lapse), reporting it on [changes].
  void setPremium({required bool active}) {
    if (_premium == active) return;
    _premium = active;
    _changes.add(active);
  }

  /// Queues [result] as the next [purchase]'s answer.
  void queuePurchase(EntitlementResult result) => _purchases.add(result);

  /// Queues [result] as the next [restore]'s answer.
  void queueRestore(EntitlementResult result) => _restores.add(result);

  /// Queues [result] as the next [refresh]'s answer.
  void queueRefresh(EntitlementResult result) => _refreshes.add(result);

  @override
  Future<EntitlementResult> refresh() async => _answer(
    EntitlementCall.refresh,
    _refreshes,
    () => _premium ? const PremiumActive() : const PremiumInactive(),
  );

  @override
  Future<String?> localizedPrice() async {
    calls.add(EntitlementCall.localizedPrice);
    return sellsPremium ? price : null;
  }

  @override
  Future<EntitlementResult> purchase() async => _answer(
    EntitlementCall.purchase,
    _purchases,
    () => sellsPremium
        ? const PremiumActive()
        : const EntitlementFailed(EntitlementFailureReason.notSold),
  );

  @override
  Future<EntitlementResult> restore() async =>
      _answer(EntitlementCall.restore, _restores, _current);

  EntitlementResult _current() {
    if (!sellsPremium) {
      return const EntitlementFailed(EntitlementFailureReason.notSold);
    }
    return _premium ? const PremiumActive() : const PremiumInactive();
  }

  EntitlementResult _answer(
    EntitlementCall call,
    List<EntitlementResult> queue,
    EntitlementResult Function() fallback,
  ) {
    calls.add(call);
    final result = queue.isEmpty ? fallback() : queue.removeAt(0);
    switch (result) {
      case PremiumActive():
        setPremium(active: true);
      case PremiumInactive():
        setPremium(active: false);
      case PurchaseCancelled() || PurchasePending() || EntitlementFailed():
        break;
    }
    return result;
  }
}
