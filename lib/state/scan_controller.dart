import 'package:flutter/foundation.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/text/text_menu_source.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/platform/qr_scanner.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/venue/qr_payload_router.dart';
import 'package:ketoclub/state/scanned_pages_registry.dart';
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
/// menu and its analysis, puts the pages in the [ScannedPagesRegistry]
/// under that menu's reference (so the menu screen offers "View pages"),
/// and returns the [VenueRef] to open. The pages are never discarded by a
/// failure, so Retry is calling [analysePages] again; they live in memory
/// only and are never written to the cache.
///
/// **QR codes.** [scanQr] reads a table's QR code through the [QrScanner]
/// and classifies it with [QrPayloadRouter]; a venue is handed to the
/// caller to open, and the two outcomes with no menu behind them (a
/// platform not supported yet, a code that is not a menu link) are kept as
/// [qrNotice] for the screen to explain (issue #182).
///
/// Never throws — the repository, classifier and scanner do not, and
/// [TextMenuSource.parse] and [QrPayloadRouter.classify] are pure.
final class ScanController extends ChangeNotifier {
  /// Creates a controller that stores pasted and scanned menus in
  /// `repository` and stamps pasted ones with the time `clock` reports.
  /// [classifier] reads scanned pages (issue #89) under the options
  /// `settingsStore` gives: consent, the net-carb limit and the dietary
  /// toggles, the same ones the menu screen classifies with. The pages of
  /// a successful read are put in `pagesRegistry` (issue #89), when one is
  /// given, so the menu screen can show them.
  new({
    required this.classifier,
    required this._repository,
    required this._clock,
    required this._settingsStore,
    this._pagesRegistry,
    this.qrScanner = const NoQrScanner(),
  });

  /// Reads and classifies scanned pages in one request (architecture.md
  /// D15). Used by [analysePages]; the paste flow does not call it.
  final ScannedMenuClassifier classifier;

  /// Reads a table's QR code (issue #182). Used by [scanQr]; defaults to
  /// [NoQrScanner], which is unavailable, so a controller built without a
  /// scanner shows no QR action.
  final QrScanner qrScanner;

  final MenuRepository _repository;
  final Clock _clock;
  final SettingsStore _settingsStore;
  final ScannedPagesRegistry? _pagesRegistry;

  final List<ScannedPage> _pages = <ScannedPage>[];
  bool _analysing = false;
  MenuAnalysisFailureReason? _lastFailure;

  String _text = '';
  bool _emptyPaste = false;
  bool _isSubmitting = false;
  bool _disposed = false;
  bool _qrScanning = false;
  QrTarget? _qrNotice;

  /// The text currently in the paste field.
  String get text => _text;

  /// Replaces the pasted text, clearing a previous [emptyPaste] message
  /// because the user is editing what it complained about.
  set text(String value) {
    if (value == _text) return;
    _text = value;
    _emptyPaste = false;
    _qrNotice = null;
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

  /// Whether this build can scan a QR code, so the screen offers the
  /// action. False on web, where pasting the link already works.
  bool get qrAvailable => qrScanner.isAvailable;

  /// Whether [scanQr] is waiting on the camera.
  bool get qrScanning => _qrScanning;

  /// What the last [scanQr] found when it was not a venue: a
  /// [QrUnsupportedSource] (a platform KetoClub cannot read yet) or a
  /// [QrPhotographInstead] (a code with no menu link in it). Null before a
  /// scan, after a cancelled or venue scan, and once the user edits the
  /// pages or the paste.
  QrTarget? get qrNotice => _qrNotice;

  /// Opens the camera, reads one QR code and classifies it, returning the
  /// [QrVenue] to open, or null when there is nothing to open.
  ///
  /// Null covers a cancelled or denied camera (nothing else changes) and the
  /// two outcomes that carry a message, which are left in [qrNotice]. Clears
  /// the previous [qrNotice] first. A no-op while a scan is already open.
  Future<QrVenue?> scanQr() async {
    if (_qrScanning) return null;
    _qrScanning = true;
    _qrNotice = null;
    notifyListeners();

    final payload = await qrScanner.scan();
    QrVenue? venue;
    if (payload != null) {
      switch (QrPayloadRouter.classify(payload)) {
        case final QrVenue target:
          venue = target;
        case final QrTarget notice:
          _qrNotice = notice;
      }
    }
    _qrScanning = false;
    _notify();
    return venue;
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
      _qrNotice = null;
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
  /// screen reuses the analysis instead of classifying again. The pages
  /// that were read go into the pages registry under that reference, so
  /// the menu screen can offer them for checking; a failure puts nothing.
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
    // An unmodifiable copy: the registry keeps exactly the pages that were
    // read, even if the user edits the list afterwards.
    final scan = ScannedMenu(pages: _pages);
    final result = await classifier.classify(
      scan,
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
        _pagesRegistry?.put(ref, scan);
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
