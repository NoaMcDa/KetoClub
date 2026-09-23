import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/venue/venue_ref_resolver.dart';

/// Screen state for the paste-a-link entry screen (architecture.md §6.5
/// Tier A, §6.6).
///
/// Holds what the user typed or pasted and, whenever it resolves, the
/// [VenueRef] it points at. Resolution is delegated entirely to
/// [VenueRefResolver] — this controller does no parsing of its own.
///
/// It also reads [AppSettings.lastVenue] (issue #55) so the screen can
/// offer a "Continue with {venue}" row instead of opening it directly on
/// launch — a decision this class does not question, only serves. The
/// name shown for that row comes from the cached menu's own
/// `CachedMenuEntry.venueName` through [MenuRepository.savedMenus] when
/// one is on hand, falling back to the platform id otherwise — the same
/// fallback `SavedScreen` and `MenuScreen` already use for a venue Wolt
/// never named.
final class VenueSearchController extends ChangeNotifier {
  /// Creates a controller with an empty query, over [_settings] and
  /// [_repository] for [load].
  new(this._settings, this._repository);

  final SettingsStore _settings;
  final MenuRepository _repository;

  String _input = '';
  VenueRef? _resolved;
  VenueRef? _lastVenue;
  String? _lastVenueName;

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

  /// The most recently opened venue, from [AppSettings.lastVenue], once
  /// [load] has completed; null before that, and null when nothing has
  /// ever been opened (issue #55).
  VenueRef? get lastVenue => _lastVenue;

  /// The name to show for [lastVenue] in the "Continue with…" row: the
  /// cached menu's own venue name when one is saved for it, or its
  /// platform id otherwise. Null exactly when [lastVenue] is null.
  String? get lastVenueName => _lastVenueName;

  /// Records [value] and re-resolves. Notifies listeners.
  void setInput(String value) {
    _input = value;
    _resolved = VenueRefResolver.resolve(value);
    notifyListeners();
  }

  /// Reads [AppSettings.lastVenue] and, when set, the name to show for it
  /// (see the class doc). Notifies listeners once.
  Future<void> load() async {
    final lastVenue = (await _settings.read()).lastVenue;
    _lastVenue = lastVenue;
    _lastVenueName = lastVenue == null ? null : await _nameFor(lastVenue);
    notifyListeners();
  }

  /// The display name for [ref]: the cached menu's
  /// `CachedMenuEntry.venueName` when [ref] is saved, else
  /// [VenueRef.platformId].
  Future<String> _nameFor(VenueRef ref) async {
    final saved = await _repository.savedMenus();
    for (final entry in saved) {
      if (entry.ref == ref) return entry.venueName ?? ref.platformId;
    }
    return ref.platformId;
  }
}
