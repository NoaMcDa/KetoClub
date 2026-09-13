import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/venue/venue_ref_resolver.dart';

/// Screen state for the paste-a-link entry screen (architecture.md §6.5
/// Tier A, §6.6).
///
/// Holds what the user typed or pasted and, whenever it resolves, the
/// [VenueRef] it points at. Resolution is delegated entirely to
/// [VenueRefResolver] — this controller does no parsing of its own — so
/// it needs no network and no other I/O (architecture.md §18.1).
final class VenueSearchController extends ChangeNotifier {
  /// Creates a controller with an empty query.
  new();

  String _input = '';
  VenueRef? _resolved;

  /// What the user has typed or pasted.
  String get input => _input;

  /// The reference [input] resolves to, or null when it does not resolve.
  VenueRef? get resolved => _resolved;

  /// True when [input] is non-empty but does not resolve to anything
  /// readable.
  ///
  /// Empty input is deliberately not invalid: it is nothing typed yet, and
  /// flagging an error before the user has typed anything would be wrong.
  bool get isInvalid => _input.isNotEmpty && _resolved == null;

  /// Records [value] and re-resolves. Notifies listeners.
  void setInput(String value) {
    _input = value;
    _resolved = VenueRefResolver.resolve(value);
    notifyListeners();
  }
}
