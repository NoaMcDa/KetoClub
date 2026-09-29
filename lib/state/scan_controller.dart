import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/text/text_menu_source.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/utils/constants.dart';

/// Why [ScanController.addPages] refused pages (issue #82).
enum ScanPageRejection {
  /// Adding the pages would pass `maxScanPages`.
  tooManyPages,

  /// A page is larger than `maxScanPageBytes`.
  pageTooLarge,
}

/// Screen state for the Scan tab (architecture.md D15, D18; issues #82,
/// #83): the paste field and the pages of a photographed or PDF menu.
///
/// **Paste.** Holds the pasted [text]; [submitPaste] turns it into a menu
/// with [TextMenuSource], stores it through the [MenuRepository] and hands
/// the caller the [VenueRef] to open, so the menu screen loads it like any
/// other venue. Classification is the menu screen's job, not this
/// controller's: a scan is a venue, and a venue is classified when it is
/// opened.
///
/// **Pages.** [addPages] collects up to `maxScanPages` pages of at most
/// `maxScanPageBytes` each — the bounds are enforced here, not by the
/// pickers, so the screen can say which one a page broke. [analysePages]
/// hands every page to the [ScannedMenuClassifier] in one call, stores the
/// menu and its analysis, and returns the [VenueRef] to open. The pages
/// are never discarded by a failure, so Retry is calling [analysePages]
/// again; they live in memory only and are never written to the cache.
///
/// Never throws — the repository and classifier do not, and
/// [TextMenuSource.parse] is pure.
final class ScanController extends ChangeNotifier {
  /// Creates a controller that stores pasted and scanned menus in
  /// `repository` and stamps pasted ones with the time `clock` reports.
  /// [classifier] reads scanned pages (issue #89) under the options
  /// `settingsStore` gives: consent, the net-carb limit and the dietary
  /// toggles, the same ones the menu screen classifies with.
  new({
    required this.classifier,
    required this._repository,
    required this._clock,
    required this._settingsStore,
  });

  /// Reads and classifies scanned pages in one request (architecture.md
  /// D15). Used by [analysePages]; the paste flow does not call it.
  final ScannedMenuClassifier classifier;

  final MenuRepository _repository;
  final Clock _clock;
  final SettingsStore _settingsStore;

  final List<ScannedPage> _pages = <ScannedPage>[];
  bool _analysing = false;
  MenuAnalysisFailureReason? _lastFailure;

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

  /// The pages collected so far, in the order added. Unmodifiable.
  List<ScannedPage> get pages => List<ScannedPage>.unmodifiable(_pages);

  /// Whether [maxScanPages] pages are already held, so nothing more can
  /// be added.
  bool get atPageCap => _pages.length >= maxScanPages;

  /// Whether [analysePages] is currently reading the pages.
  bool get analysing => _analysing;

  /// Why the last [analysePages] found no menu, or null before one has
  /// failed and again once a later attempt succeeds or the pages change.
  MenuAnalysisFailureReason? get lastFailure => _lastFailure;

  /// Whether the pages can be analysed now: at least one is held and no
  /// analysis is in flight.
  bool get canAnalysePages => _pages.isNotEmpty && !_analysing;

  /// Adds [more] after the pages already held, returning null when all of
  /// them fit.
  ///
  /// A page larger than `maxScanPageBytes` answers
  /// [ScanPageRejection.pageTooLarge]; a page that would take the count
  /// past `maxScanPages` answers [ScanPageRejection.tooManyPages]. Either
  /// way the pages before the offending one are kept and it and every one
  /// after it are not, so what the user picked first is what they get.
  /// Clears [lastFailure]: the pages it described have changed. A no-op
  /// while an analysis is in flight.
  ScanPageRejection? addPages(List<ScannedPage> more) {
    if (_analysing) return null;
    ScanPageRejection? rejection;
    var added = false;
    for (final page in more) {
      if (page.bytes.length > maxScanPageBytes) {
        rejection = ScanPageRejection.pageTooLarge;
        break;
      }
      if (_pages.length >= maxScanPages) {
        rejection = ScanPageRejection.tooManyPages;
        break;
      }
      _pages.add(page);
      added = true;
    }
    if (added) {
      _lastFailure = null;
      notifyListeners();
    }
    return rejection;
  }

  /// Removes the page at [index]; an out-of-range index and a call during
  /// an analysis do nothing. Clears [lastFailure].
  void removePageAt(int index) {
    if (_analysing || index < 0 || index >= _pages.length) return;
    _pages.removeAt(index);
    _lastFailure = null;
    notifyListeners();
  }

  /// Reads every page in one [classifier] call, stores the resulting menu
  /// and its analysis and returns the [VenueRef] to open, so the menu
  /// screen reuses the analysis instead of classifying again.
  ///
  /// Returns null, and sets [lastFailure], when the classifier could not
  /// read the pages; the pages are kept, so calling this again is Retry.
  /// Also null when there are no pages or an analysis is already running.
  Future<VenueRef?> analysePages() async {
    if (!canAnalysePages) return null;
    _analysing = true;
    _lastFailure = null;
    notifyListeners();

    final settings = await _settingsStore.read();
    final result = await classifier.classify(
      ScannedMenu(pages: _pages),
      options: ClassificationOptions(
        estimationConsentGiven: settings.estimationConsentGiven,
        netCarbLimitGrams: settings.netCarbLimitGrams,
        dietaryConstraints: ClassificationOptions.dietaryConstraintsFor(
          seedOilFree: settings.seedOilFree,
          dairyFree: settings.dairyFree,
          carnivoreOnly: settings.carnivoreOnly,
        ),
      ),
    );

    VenueRef? ref;
    switch (result) {
      case ScannedMenuRead(:final menu, :final analysis):
        ref = menu.venueRef;
        await _repository.store(menu);
        await _repository.saveAnalysis(ref, analysis);
      // TODO(NoaMcDa): #89 dependencies.scannedPages.put(ref, scan) once
      // the registry lands.
      case ScannedMenuFailed(:final reason):
        _lastFailure = reason;
    }
    _analysing = false;
    _notify();
    return ref;
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
