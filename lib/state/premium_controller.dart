import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ketoclub/services/platform/entitlement.dart';
import 'package:ketoclub/utils/banto_mode.dart';
import 'package:ketoclub/utils/premium_gates.dart';

/// App-lifetime state for Banto Premium (ALG-18, issue #360): whether it is
/// active, the store's price, and the purchase and restore the paywall and
/// Settings call. `KetoClubApp` owns one and provides it above every route,
/// so a gate on any screen reads the same answer.
///
/// The store is read once per app session, on the first gate or paywall
/// that needs it ([ensureChecked]), never at start-up: nothing here
/// performs I/O until a person reaches a gated action. A change the store
/// reports later (an approved pending purchase, a renewal) arrives through
/// [Entitlement.changes].
///
/// Never throws: the [Entitlement] answers results, never exceptions.
final class PremiumController extends ChangeNotifier {
  /// Creates the controller over [_entitlement]. With [bantoMode] off
  /// nothing is sold and nothing is gated, whatever the entitlement says.
  new(this._entitlement, {this.bantoMode = BantoMode.enabled}) {
    _changes = _entitlement.changes.listen((_) => _notify());
  }

  final Entitlement _entitlement;

  /// Whether this build shows Banto surfaces (D26's convention).
  final bool bantoMode;

  StreamSubscription<bool>? _changes;
  Future<void>? _check;
  Future<EntitlementResult>? _inFlight;
  String? _price;
  bool _busy = false;
  EntitlementResult? _lastResult;
  bool _disposed = false;

  /// Whether this build sells Premium: a Banto build with a store. False
  /// on web, which stays free.
  bool get sellsPremium => bantoMode && _entitlement.sellsPremium;

  /// Whether Premium is active, as last read from the store.
  bool get isPremium => _entitlement.isPremium;

  /// What the gates in [PremiumGates] decide with.
  PremiumAccess get access => PremiumAccess(
    bantoMode: bantoMode,
    sellsPremium: _entitlement.sellsPremium,
    premium: isPremium,
  );

  /// The store's own localized monthly price, or null until
  /// [loadPrice] has an answer (or when the store has none).
  String? get price => _price;

  /// Whether a purchase or a restore is in flight.
  bool get busy => _busy;

  /// What the last [purchase] or [restore] came to, for the paywall's
  /// message; null before either and after [clearResult].
  EntitlementResult? get lastResult => _lastResult;

  /// Reads the store's current record once per session, the first time a
  /// gate or the paywall needs it. A no-op when nothing is sold. Later
  /// calls answer the same future, so a person is never kept waiting on
  /// the store twice for one session.
  Future<void> ensureChecked() {
    if (!sellsPremium) return Future<void>.value();
    return _check ??= _entitlement.refresh().then((_) => _notify());
  }

  /// Asks the store for its localized price, for the paywall.
  Future<void> loadPrice() async {
    if (!sellsPremium) return;
    _price = await _entitlement.localizedPrice();
    _notify();
  }

  /// Opens the store's purchase sheet and answers how it ended.
  Future<EntitlementResult> purchase() => _run(_entitlement.purchase);

  /// Restores a purchase made on another device or before a reinstall.
  Future<EntitlementResult> restore() => _run(_entitlement.restore);

  /// Forgets [lastResult], when the paywall opens again.
  void clearResult() {
    if (_lastResult == null) return;
    _lastResult = null;
    _notify();
  }

  /// Runs [call] unless one is in flight already, which is then joined, so
  /// a double tap never opens the store twice.
  Future<EntitlementResult> _run(Future<EntitlementResult> Function() call) =>
      _inFlight ??= _runOnce(call).whenComplete(() => _inFlight = null);

  Future<EntitlementResult> _runOnce(
    Future<EntitlementResult> Function() call,
  ) async {
    _busy = true;
    _lastResult = null;
    _notify();
    final result = sellsPremium
        ? await call()
        : const EntitlementFailed(EntitlementFailureReason.notSold);
    _busy = false;
    _lastResult = result;
    _notify();
    return result;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes?.cancel());
    _changes = null;
    super.dispose();
  }
}
