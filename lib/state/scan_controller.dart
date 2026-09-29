import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/text/text_menu_source.dart';
import 'package:ketoclub/services/platform/clock.dart';

/// Screen state for the Scan tab's paste field (architecture.md D18;
/// issue #83).
///
/// Holds the pasted [text]; [submitPaste] turns it into a menu with
/// [TextMenuSource], stores it through the [MenuRepository] and hands the
/// caller the [VenueRef] to open, so the menu screen loads it like any
/// other venue. Classification is the menu screen's job, not this
/// controller's: a scan is a venue, and a venue is classified when it is
/// opened.
///
/// Never throws — the repository does not, and [TextMenuSource.parse] is
/// pure.
final class ScanController extends ChangeNotifier {
  /// Creates a controller that stores pasted menus in `repository` and
  /// stamps them with the time `clock` reports. [classifier] reads
  /// scanned pages (issue #89); the paste flow never calls it.
  new({
    required this.classifier,
    required this._repository,
    required this._clock,
  });

  /// Reads and classifies scanned pages in one request (architecture.md
  /// D15). Held for the scan flow (issues #82, #89); the paste flow does
  /// not use it.
  final ScannedMenuClassifier classifier;

  final MenuRepository _repository;
  final Clock _clock;

  String _text = '';
  bool _emptyPaste = false;
  bool _isSubmitting = false;
  bool _disposed = false;

  /// The text currently in the paste field.
  String get text => _text;

  /// Replaces the pasted text, clearing a previous [emptyPaste] message
  /// because the user is editing what it complained about.
  set text(String value) {
    if (value == _text) return;
    _text = value;
    _emptyPaste = false;
    notifyListeners();
  }

  /// Whether the Analyse button may be pressed: there is text other than
  /// whitespace and no submit is in flight.
  bool get canAnalyse => _text.trim().isNotEmpty && !_isSubmitting;

  /// Whether the last [submitPaste] found no dish in [text].
  bool get emptyPaste => _emptyPaste;

  /// Whether [submitPaste] is currently storing a menu.
  bool get isSubmitting => _isSubmitting;

  /// Parses [text] into a menu, stores it and returns its reference, or
  /// returns null and sets [emptyPaste] when no dish could be read from it
  /// (or the text is blank). [uncategorisedName] names the category that
  /// holds dishes before any header — see [TextMenuSource.parse].
  Future<VenueRef?> submitPaste({String? uncategorisedName}) async {
    if (!canAnalyse) return null;
    final menu = uncategorisedName == null
        ? TextMenuSource.parse(_text, now: _clock.now())
        : TextMenuSource.parse(
            _text,
            now: _clock.now(),
            uncategorisedName: uncategorisedName,
          );
    if (menu == null) {
      _emptyPaste = true;
      notifyListeners();
      return null;
    }
    _isSubmitting = true;
    notifyListeners();
    await _repository.store(menu);
    _isSubmitting = false;
    _emptyPaste = false;
    _notify();
    return menu.venueRef;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
