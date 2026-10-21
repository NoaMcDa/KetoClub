/// "My order" (Banto, issue #418): the dishes a person picked on each
/// menu, kept in memory for as long as the app runs.
library;

import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/venue.dart';

/// The dishes added to "My order", per menu, in the order they were added.
///
/// App-scoped, not a field of the menu screen's `MenuController`: that
/// controller lives and dies with its route, so an order kept there would
/// be lost the moment the person went back to Explore and reopened the
/// menu, while the issue keeps it "per menu for the session". Keyed by
/// the [VenueRef], so each menu has its own order and opening another
/// menu neither shows nor clears this one's.
///
/// In memory only (D26 C1): nothing here is written to a store, the cache
/// or the visit history, and nothing is sent anywhere; the order is gone
/// when the app is closed. Holds dish ids, never dish text or a verdict:
/// the order card reads the menu and its evaluations afresh, so an order
/// can never show a state the menu no longer gives.
final class OrderController extends ChangeNotifier {
  final Map<VenueRef, List<String>> _orders = <VenueRef, List<String>>{};

  /// The dish ids added for [ref], oldest first; empty for none.
  List<String> dishIdsFor(VenueRef ref) =>
      List<String>.unmodifiable(_orders[ref] ?? const <String>[]);

  /// Whether the dish [dishId] is in [ref]'s order.
  bool contains(VenueRef ref, String dishId) =>
      _orders[ref]?.contains(dishId) ?? false;

  /// Adds the dish [dishId] to [ref]'s order, or removes it when it is
  /// already there.
  void toggle(VenueRef ref, String dishId) {
    if (contains(ref, dishId)) {
      remove(ref, dishId);
      return;
    }
    (_orders[ref] ??= <String>[]).add(dishId);
    notifyListeners();
  }

  /// Removes the dish [dishId] from [ref]'s order; a no-op when it is not
  /// there.
  void remove(VenueRef ref, String dishId) {
    final order = _orders[ref];
    if (order == null || !order.remove(dishId)) return;
    if (order.isEmpty) _orders.remove(ref);
    notifyListeners();
  }

  /// Empties [ref]'s order; a no-op when it is already empty.
  void clear(VenueRef ref) {
    if (_orders.remove(ref) == null) return;
    notifyListeners();
  }
}
