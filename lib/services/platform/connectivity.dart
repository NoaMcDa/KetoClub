/// Whether the device currently appears to have a network route, used as a
/// pre-flight hint before `RoutingMenuClassifier` spends a request to
/// KetoClub's server (architecture.md §6.2, §14 D10 — reinstated in
/// Phase 1).
library;

import 'package:connectivity_plus/connectivity_plus.dart' as plus;

/// Reports whether the device currently appears to have a route to the
/// network (architecture.md §14 D10).
///
/// **A hint, never a verdict.** [isOnline] answering `true` does not
/// guarantee the next network call will succeed: a captive portal, a Wi-Fi
/// network with no upstream route, and a merely-unreachable host all read as
/// "online" here. A caller that skips a network attempt on a `false` reading
/// must still treat that attempt failing anyway exactly as if this check had
/// never run — this interface only ever saves an attempt that could not have
/// worked, it never overrides what a real attempt's outcome means.
/// "Don't know" (a broken plugin, an unsupported platform) also reads as
/// `true`: a broken [Connectivity] degrades to always attempting the call,
/// the behaviour every caller already had before this abstraction existed,
/// rather than silently blocking every analysis.
abstract interface class Connectivity {
  /// Whether the device currently appears to have a route to the network.
  ///
  /// Never throws.
  Future<bool> isOnline();
}

/// A [Connectivity] backed by `connectivity_plus`.
///
/// The plugin handle passed to the constructor is already built, not yet
/// touched: `connectivity_plus`'s `Connectivity()` constructor only
/// assembles a singleton wrapper and never opens a platform channel, so
/// `di.dart` may construct it directly while assembling the dependency
/// graph.
/// Every channel call happens inside [isOnline], never from this
/// constructor.
final class DeviceConnectivity implements Connectivity {
  /// Creates a connectivity check over the given `connectivity_plus` handle.
  ///
  /// Positional and private: Dart cannot express a private named
  /// initializing formal, so the choice was positional or a suppressed lint
  /// — see `RoutingMenuClassifier` for the same call.
  const new(this._probe);

  final plus.Connectivity _probe;

  @override
  Future<bool> isOnline() async {
    try {
      final results = await _probe.checkConnectivity();
      return results.any((result) => result != plus.ConnectivityResult.none);
      // A broken channel or an unsupported platform reads as "online" (see
      // the interface's doc comment): "don't know" degrades to always
      // attempting the call, never to blocking every analysis.
    } on Exception {
      return true;
    }
  }
}
