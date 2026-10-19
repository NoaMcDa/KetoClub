import 'package:flutter/foundation.dart' show immutable;

/// The one Banto Premium product (ALG-18, issue #360): a monthly
/// subscription, set up under this id in App Store Connect and the Play
/// Console. The price the app shows is always the store's own localized
/// string ([Entitlement.localizedPrice]), never a figure written here.
const String premiumProductId = 'banto_premium_monthly';

/// Why the store could not do what was asked (ALG-18). Each reason has its
/// own copy on the paywall; none is shown as another.
enum EntitlementFailureReason {
  /// This build sells nothing: the web build and tests ([NullEntitlement]).
  notSold,

  /// Billing is not available on this device, or the store cannot be
  /// reached.
  storeUnavailable,

  /// The store does not know [premiumProductId] (not set up yet, or not in
  /// this storefront).
  productNotFound,

  /// The store answered with an error.
  storeError,

  /// The store did not answer in time.
  timedOut,
}

/// What a call to an [Entitlement] came to (ALG-18). Sealed, so every
/// caller handles every case; an [Entitlement] answers one of these and
/// never throws.
sealed class EntitlementResult {
  /// Const base constructor for the cases below.
  const new();
}

/// Premium is active: a purchase went through, or the store holds an active
/// subscription for this account.
final class PremiumActive extends EntitlementResult {
  /// Creates the result.
  const new();
}

/// The store holds no active subscription for this account: a restore or a
/// refresh found none, or a subscription lapsed.
final class PremiumInactive extends EntitlementResult {
  /// Creates the result.
  const new();
}

/// The person closed the store's purchase sheet without buying.
final class PurchaseCancelled extends EntitlementResult {
  /// Creates the result.
  const new();
}

/// The purchase is waiting on the store (Ask to Buy, a delayed payment);
/// Premium opens when the store approves it, through
/// [Entitlement.changes].
final class PurchasePending extends EntitlementResult {
  /// Creates the result.
  const new();
}

/// The store could not do what was asked, for [reason].
@immutable
final class EntitlementFailed extends EntitlementResult {
  /// Creates the result.
  const new(this.reason);

  /// Why.
  final EntitlementFailureReason reason;

  @override
  bool operator ==(Object other) =>
      other is EntitlementFailed && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'EntitlementFailed($reason)';
}

/// Whether this install holds Banto Premium, and the way to buy or restore
/// it (Banto, ALG-18, issue #360; architecture.md D26).
///
/// The gate lives on the device and reads the store's own record of the
/// purchase (StoreKit on iOS, Play Billing on Android) through one plugin,
/// behind this interface. There is no receipt-validation server and no
/// account: the backend learns nothing about a purchase.
///
/// **Never throws.** Every call answers an [EntitlementResult] (or a null
/// price), whatever the store does.
///
/// **No I/O until first use.** A constructor performs no plugin I/O
/// (`di_test` asserts it for the production graph); the store is first
/// reached by [refresh], [localizedPrice], [purchase] or [restore].
abstract interface class Entitlement {
  /// Whether this build sells Premium at all. False on the web build, which
  /// stays free (its quota is the backend's rate limit), and in tests built
  /// on [NullEntitlement]; nothing is gated then.
  bool get sellsPremium;

  /// Whether Premium is active, as last read from the store. False until a
  /// [refresh], [purchase] or [restore] says otherwise.
  bool get isPremium;

  /// Every change of [isPremium], as the new value. A broadcast stream;
  /// listening to it performs no I/O.
  Stream<bool> get changes;

  /// Reads the store's current record quietly (no sign-in prompt), and
  /// answers [PremiumActive] or [PremiumInactive], or why it could not.
  Future<EntitlementResult> refresh();

  /// The store's own localized price for [premiumProductId], such as
  /// "₪19.90", or null when the store cannot say (not reachable, product
  /// not set up, or a build that sells nothing).
  Future<String?> localizedPrice();

  /// Opens the store's purchase sheet for [premiumProductId].
  Future<EntitlementResult> purchase();

  /// Restores a purchase made on another device or before a reinstall:
  /// what the person's "Restore purchase" button calls.
  Future<EntitlementResult> restore();
}

/// The [Entitlement] of a build that sells nothing: the web build and
/// tests (ALG-18). Never premium, never sells, answers
/// [EntitlementFailureReason.notSold] to a purchase or a restore, and does
/// no I/O at all. With it nothing is gated, so the web build stays free.
final class NullEntitlement implements Entitlement {
  /// Creates the entitlement; it holds no state.
  const new();

  @override
  bool get sellsPremium => false;

  @override
  bool get isPremium => false;

  @override
  Stream<bool> get changes => const Stream<bool>.empty();

  @override
  Future<EntitlementResult> refresh() async => const PremiumInactive();

  @override
  Future<String?> localizedPrice() async => null;

  @override
  Future<EntitlementResult> purchase() async =>
      const EntitlementFailed(EntitlementFailureReason.notSold);

  @override
  Future<EntitlementResult> restore() async =>
      const EntitlementFailed(EntitlementFailureReason.notSold);
}
