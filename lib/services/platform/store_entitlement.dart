import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:ketoclub/services/platform/entitlement.dart';

/// Answers the store connection: `InAppPurchase.instance` in the app, a
/// fake in tests. Invoked on first use only, never by a constructor.
typedef StoreConnection = InAppPurchase Function();

/// The [Entitlement] of a phone build: Banto Premium bought and restored
/// through the App Store (StoreKit 2) or Google Play (Play Billing), over
/// the official `in_app_purchase` plugin (ALG-18, issue #360). This is the
/// one file that imports the plugin (`import_rules_test` pins it).
///
/// **No server, no account.** The store is the only record: [refresh] and
/// [restore] ask it for the purchases it holds as active right now — on iOS
/// StoreKit 2's current entitlements, on Android Play Billing's owned
/// purchases, neither of which prompts for a sign-in — and a subscription
/// that lapsed is simply absent from that answer. Nothing about a purchase
/// is sent to KetoClub's backend, and there is no receipt validation.
///
/// **No plugin I/O in the constructor.** The plugin's instance is fetched,
/// and its purchase stream listened to, on the first call that needs the
/// store, so `di.dart` can build this at start-up (`di_test` asserts it).
///
/// **Never throws.** A plugin error, a missing plugin, an unreachable store
/// and a store that never answers all become an [EntitlementFailed].
final class StoreEntitlement implements Entitlement {
  /// Creates the entitlement over [store], `InAppPurchase.instance` by
  /// default. [answerTimeout] bounds a restore, a refresh and a price
  /// lookup; [purchaseTimeout] bounds the wait for the store's purchase
  /// sheet, after which the purchase reads as pending.
  new({
    StoreConnection? store,
    this.answerTimeout = const Duration(seconds: 20),
    this.purchaseTimeout = const Duration(minutes: 10),
  }) : _connect = store ?? _pluginInstance;

  static InAppPurchase _pluginInstance() => InAppPurchase.instance;

  /// How long a restore, a refresh or a price lookup waits for the store.
  final Duration answerTimeout;

  /// How long a purchase waits for the store's answer before it reads as
  /// [PurchasePending].
  final Duration purchaseTimeout;

  final StoreConnection _connect;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  InAppPurchase? _store;
  StreamSubscription<List<PurchaseDetails>>? _updates;
  bool _premium = false;
  ProductDetails? _product;

  /// The restore waiting for the store's next batch of purchases.
  Completer<EntitlementResult>? _restoring;

  /// The purchase waiting for the store's answer about [premiumProductId].
  Completer<EntitlementResult>? _purchasing;

  /// The restore and the purchase in flight, so a second tap joins them.
  Future<EntitlementResult>? _restoreCall;
  Future<EntitlementResult>? _purchaseCall;

  @override
  bool get sellsPremium => true;

  @override
  bool get isPremium => _premium;

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  Future<EntitlementResult> refresh() => restore();

  @override
  Future<EntitlementResult> restore() {
    final inFlight = _restoreCall;
    if (inFlight != null) return inFlight;
    final call = _runRestore();
    _restoreCall = call;
    unawaited(call.whenComplete(() => _restoreCall = null));
    return call;
  }

  @override
  Future<EntitlementResult> purchase() {
    final inFlight = _purchaseCall;
    if (inFlight != null) return inFlight;
    final call = _runPurchase();
    _purchaseCall = call;
    unawaited(call.whenComplete(() => _purchaseCall = null));
    return call;
  }

  @override
  Future<String?> localizedPrice() async {
    final store = await _openAvailable();
    if (store == null) return null;
    final (:product, failure: _) = await _lookUp(store);
    return product?.price;
  }

  Future<EntitlementResult> _runRestore() async {
    final store = await _openAvailable();
    if (store == null) {
      return _failed(EntitlementFailureReason.storeUnavailable);
    }
    final waiting = Completer<EntitlementResult>();
    _restoring = waiting;
    try {
      await store.restorePurchases();
    } on Object {
      if (identical(_restoring, waiting)) {
        _restoring = null;
      }
      return _failed(EntitlementFailureReason.storeError);
    }
    return await waiting.future.timeout(
      answerTimeout,
      onTimeout: () {
        if (identical(_restoring, waiting)) {
          _restoring = null;
        }
        return _failed(EntitlementFailureReason.timedOut);
      },
    );
  }

  Future<EntitlementResult> _runPurchase() async {
    final store = await _openAvailable();
    if (store == null) {
      return _failed(EntitlementFailureReason.storeUnavailable);
    }
    final (:product, :failure) = await _lookUp(store);
    if (product == null) {
      return _failed(failure ?? EntitlementFailureReason.productNotFound);
    }
    final waiting = Completer<EntitlementResult>();
    _purchasing = waiting;
    try {
      final started = await store.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      if (!started) {
        if (identical(_purchasing, waiting)) {
          _purchasing = null;
        }
        return _failed(EntitlementFailureReason.storeError);
      }
    } on Object {
      if (identical(_purchasing, waiting)) {
        _purchasing = null;
      }
      return _failed(EntitlementFailureReason.storeError);
    }
    return await waiting.future.timeout(
      purchaseTimeout,
      onTimeout: () {
        if (identical(_purchasing, waiting)) {
          _purchasing = null;
        }
        return const PurchasePending();
      },
    );
  }

  /// The store, connected and listened to, when billing is available here;
  /// null otherwise.
  Future<InAppPurchase?> _openAvailable() async {
    final InAppPurchase store;
    try {
      store = _store ??= _connect();
      _updates ??= store.purchaseStream.listen(
        _onPurchases,
        onError: (Object _) => _onStreamError(),
      );
    } on Object {
      return null;
    }
    try {
      return await store.isAvailable().timeout(answerTimeout) ? store : null;
    } on Object {
      return null;
    }
  }

  /// [premiumProductId]'s details, from the store once and then remembered,
  /// or why there are none.
  Future<({ProductDetails? product, EntitlementFailureReason? failure})>
  _lookUp(InAppPurchase store) async {
    final known = _product;
    if (known != null) return (product: known, failure: null);
    final ProductDetailsResponse response;
    try {
      response = await store
          .queryProductDetails(const <String>{premiumProductId})
          .timeout(answerTimeout);
    } on TimeoutException {
      return (product: null, failure: EntitlementFailureReason.timedOut);
    } on Object {
      return (product: null, failure: EntitlementFailureReason.storeError);
    }
    for (final details in response.productDetails) {
      if (details.id == premiumProductId) {
        _product = details;
        return (product: details, failure: null);
      }
    }
    return (
      product: null,
      failure: response.error != null
          ? EntitlementFailureReason.storeError
          : EntitlementFailureReason.productNotFound,
    );
  }

  /// One batch from the store's purchase stream: a purchase's progress, a
  /// restore's answer, or a renewal the store delivered on its own.
  void _onPurchases(List<PurchaseDetails> batch) {
    var active = false;
    EntitlementResult? outcome;
    for (final details in batch) {
      if (details.productID != premiumProductId) continue;
      if (details.pendingCompletePurchase) unawaited(_complete(details));
      switch (details.status) {
        case PurchaseStatus.purchased || PurchaseStatus.restored:
          active = true;
          outcome = const PremiumActive();
        case PurchaseStatus.pending:
          outcome ??= const PurchasePending();
        case PurchaseStatus.canceled:
          outcome ??= const PurchaseCancelled();
        case PurchaseStatus.error:
          outcome ??= const EntitlementFailed(
            EntitlementFailureReason.storeError,
          );
      }
    }
    final restoring = _restoring;
    if (restoring != null) {
      // A restore's answer is the whole of what the store holds as active:
      // no entry for the product is a lapsed or never-bought subscription.
      _restoring = null;
      _setPremium(active);
      restoring.complete(
        active ? const PremiumActive() : const PremiumInactive(),
      );
    } else if (active) {
      _setPremium(true);
    }
    final purchasing = _purchasing;
    if (purchasing != null && outcome != null) {
      _purchasing = null;
      purchasing.complete(outcome);
    }
  }

  void _onStreamError() {
    const failed = EntitlementFailed(EntitlementFailureReason.storeError);
    final restoring = _restoring;
    _restoring = null;
    restoring?.complete(failed);
    final purchasing = _purchasing;
    _purchasing = null;
    purchasing?.complete(failed);
  }

  /// Finishes [details] with the store (StoreKit finishes the transaction;
  /// Play acknowledges the subscription, which it otherwise refunds after
  /// three days). A failure here leaves the purchase to be delivered again.
  Future<void> _complete(PurchaseDetails details) async {
    try {
      await _store?.completePurchase(details);
    } on Object {
      // Delivered again on the next launch's purchase stream.
    }
  }

  void _setPremium(bool value) {
    if (_premium == value) return;
    _premium = value;
    _changes.add(value);
  }

  /// Stops listening to the store and closes [changes]. The app keeps its
  /// entitlement for its whole life; tests call this.
  Future<void> dispose() async {
    await _updates?.cancel();
    _updates = null;
    await _changes.close();
  }

  static EntitlementResult _failed(EntitlementFailureReason reason) =>
      EntitlementFailed(reason);
}
