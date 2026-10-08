import 'package:flutter/widgets.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_question_answerer.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/services/community/menu_store_client.dart';
import 'package:ketoclub/services/location/location_service.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/platform/app_info.dart';
import 'package:ketoclub/services/platform/app_logger.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/platform/connectivity.dart';
import 'package:ketoclub/services/platform/external_link_opener.dart';
import 'package:ketoclub/services/platform/image_downscaler.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/services/platform/page_picker.dart';
import 'package:ketoclub/services/platform/qr_scanner.dart';
import 'package:ketoclub/services/platform/scan_budget.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/services/storage/api_key_store.dart';
import 'package:ketoclub/services/storage/notes_store.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/state/scanned_pages_registry.dart';

/// The set of service interfaces the app is built on (architecture.md §18.1).
///
/// Holds interfaces only, never concrete implementations. `di.dart` fills it
/// for production; tests fill it with fakes, which is what lets a flow test run
/// the real app over faked I/O without a mocking library.
@immutable
class AppDependencies {
  /// Creates the dependency set the screens and controllers are built on.
  ///
  /// [screenBrightness] defaults to [NoOpScreenBrightness] rather than
  /// being required: it was added after every existing call site — every
  /// flow test's fake dependency set among them — was already written, and
  /// a caller with nothing to say about brightness should not have to say
  /// so. [apiKeyStore] defaults to null for the same reason, and because
  /// null is also the web build's real value.
  ///
  /// [scannedMenuClassifier] and [pagePicker] default for the same reason:
  /// they were added after those call sites, and a test that never scans
  /// should not have to build either. Their defaults do no I/O —
  /// [UnavailableScannedMenuClassifier] answers `notConfigured` and
  /// [NoPagePicker] answers as if cancelled. `di.dart` passes the real
  /// ones (issues #89 and #82).
  ///
  /// [qrScanner] and [navigatorKey] default the same way: [NoQrScanner]
  /// answers null with no plugin I/O and is unavailable, so the Scan tab
  /// hides its QR action, and a null key leaves the root navigator to
  /// `MaterialApp` (issue #182).
  ///
  /// [scanBudget] defaults to a budget over [NoImageDownscaler], which
  /// shrinks nothing and so does no decode; `di.dart` passes one over the
  /// real JPEG downscaler (issue #298).
  ///
  /// [menuQuestionAnswerer] defaults to null: a caller that never uses the
  /// question feature need not construct one, and `MenuController` hides the
  /// action when it is absent.
  ///
  /// [visitHistory] defaults to [NoVisitHistoryStore], which remembers
  /// nothing and does no I/O; `di.dart` passes the Hive-backed one (issue
  /// #307).
  ///
  /// [menuStoreClient] defaults to [NoMenuStoreClient], which sends nothing
  /// and does no I/O; `di.dart` passes the backend's (issue #312, D24).
  const new({
    required this.menuRepository,
    required this.menuClassifier,
    required this.estimateClassifier,
    required this.settingsStore,
    required this.notesStore,
    required this.clock,
    required this.logger,
    required this.connectivity,
    required this.externalLinkOpener,
    required this.menuSharer,
    required this.locationService,
    required this.venueSearchService,
    required this.scannedPages,
    this.screenBrightness = const NoOpScreenBrightness(),
    this.appInfo = const NoAppInfo(),
    this.apiKeyStore,
    this.scannedMenuClassifier = const UnavailableScannedMenuClassifier(),
    this.pagePicker = const NoPagePicker(),
    this.qrScanner = const NoQrScanner(),
    this.scanBudget = const ScanBudget(downscaler: NoImageDownscaler()),
    this.navigatorKey,
    this.menuQuestionAnswerer,
    this.visitHistory = const NoVisitHistoryStore(),
    this.menuStoreClient = const NoMenuStoreClient(),
  });

  /// Loads a venue's menu, cache first (architecture.md §6.1).
  final MenuRepository menuRepository;

  /// Classifies a whole menu in one call, LLM first and rules as the
  /// fallback (architecture.md §6.2).
  final MenuClassifier menuClassifier;

  /// The on-device rule engine alone, for the Discovery screen's explicit
  /// "Estimate this list" action (issue #42, D13) — never the router and
  /// never the language model, so estimating a list spends no AI request.
  /// `di.dart` hands it the same `HeuristicMenuClassifier` instance the
  /// router falls back to.
  final MenuClassifier estimateClassifier;

  /// Non-secret settings: language, default filter, consent, last venue.
  final SettingsStore settingsStore;

  /// Personal, on-device notes per dish (issue #52, architecture.md D8).
  /// Never read by [menuClassifier] and never sent anywhere — see
  /// [NotesStore]'s own doc comment for that boundary.
  final NotesStore notesStore;

  /// The only source of the current time, so tests control it.
  final Clock clock;

  /// Structured logging; never receives a credential or an upstream error
  /// body.
  final AppLogger logger;

  /// Whether the device currently appears to have a route to the network
  /// (architecture.md §14 D10). A hint, never a verdict — see
  /// [Connectivity]'s own doc comment — used both by the classifier
  /// router and by the persistent offline banner (issue #68).
  final Connectivity connectivity;

  /// Raises and restores the screen brightness while the Waiter Card is
  /// open (architecture.md §6.3). A no-op on platforms with no brightness
  /// API of their own, such as web.
  final ScreenBrightness screenBrightness;

  /// Reads the app's own version for the About section of Settings (issue
  /// #258). Defaults to [NoAppInfo], which answers null with no plugin I/O.
  final AppInfo appInfo;

  /// Opens a venue's own page on its platform outside KetoClub (issue #53).
  final ExternalLinkOpener externalLinkOpener;

  /// Shares the classified menu's green and yellow dishes as plain text
  /// through the platform's own share sheet (issue #54).
  final MenuSharer menuSharer;

  /// Reads the device's current position for nearby search
  /// (architecture.md §6.5, issue #37), for the Discovery screen's
  /// location button (issue #40).
  final LocationService locationService;

  /// Finds venues near a position or by name (issue #39,
  /// `phase2_discovery_research.md` §5). One call per user action; never
  /// fanned out over venues.
  final VenueSearchService venueSearchService;

  /// The user's own Gemini API key, on iOS and Android only
  /// (architecture.md D17): there the app calls Gemini directly, and
  /// Settings shows a key field over this store. Null on web, which
  /// reaches Gemini through KetoClub's backend (D12) and so has no key and
  /// no key field. The classifier's chat client holds the same instance.
  final ApiKeyStore? apiKeyStore;

  /// Reads photographed or PDF menu pages and classifies them in one
  /// request (architecture.md §6.2, D15; issue #89). A sibling of
  /// [menuClassifier], because a scan has no `Menu` until it is read.
  final ScannedMenuClassifier scannedMenuClassifier;

  /// Collects menu pages from the camera, the photo library or a PDF for
  /// the Scan tab (issue #82).
  final PagePicker pagePicker;

  /// Reads a table's QR code with the camera for the Scan tab's "Scan QR
  /// code" action (issue #182). Unavailable on web, where pasting the URL
  /// already works.
  final QrScanner qrScanner;

  /// Fits a scan's pages into one vision request before the Scan tab
  /// sends them (issue #298).
  final ScanBudget scanBudget;

  /// The app's root navigator, when a service has to push a page of its own
  /// (the QR camera, issue #182). `MaterialApp` uses it as its
  /// `navigatorKey`, so the same key `di.dart` gave the scanner reaches the
  /// navigator the screens are on. Null when nothing needs it.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// The pages of recent scans, in memory only, so the menu screen can
  /// show a scanned menu's pages beside its transcription (issue #89).
  /// The Scan tab puts them; the menu screen reads them. One instance for
  /// the app's lifetime, so it is required rather than defaulted: a
  /// default would be a different registry for each caller.
  final ScannedPagesRegistry scannedPages;

  /// Answers one free-text question about a menu that has already been
  /// analysed (architecture.md §9.5; issue #214). Null when the question
  /// feature is not wired — `MenuController` hides the action in that case.
  final MenuQuestionAnswerer? menuQuestionAnswerer;

  /// The menus opened on this device, for the Recent list (issue #307,
  /// architecture.md D8): a list kept on the device, like pins and notes,
  /// that never leaves it through this store.
  final VisitHistoryStore visitHistory;

  /// Contributes each newly seen menu, and its AI analysis, to KetoClub's
  /// shared menu store on the backend (issue #312, D24), with the user's
  /// AI-analysis consent. Sends no personal setting: see `MenuUpload`.
  final MenuStoreClient menuStoreClient;
}
