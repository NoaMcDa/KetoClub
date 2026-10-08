import 'package:ketoclub/state/app_dependencies.dart';
import 'package:ketoclub/state/scanned_pages_registry.dart';

import 'fake_app_logger.dart';
import 'fake_clock.dart';
import 'fake_connectivity.dart';
import 'fake_external_link_opener.dart';
import 'fake_location_service.dart';
import 'fake_menu_classifier.dart';
import 'fake_menu_repository.dart';
import 'fake_menu_sharer.dart';
import 'fake_menu_store_client.dart';
import 'fake_notes_store.dart';
import 'fake_page_picker.dart';
import 'fake_qr_scanner.dart';
import 'fake_scanned_menu_classifier.dart';
import 'fake_settings_store.dart';
import 'fake_venue_search_service.dart';
import 'fake_visit_history_store.dart';

/// Builds an [AppDependencies] of fakes, for widget and flow tests.
///
/// Every field is exposed so a test can steer or assert on it. This is the
/// seam architecture.md §18.1 describes: a test gets the real app on top of
/// faked I/O, without a mocking library and without a service locator.
final class FakeAppDependencies {
  /// Creates a dependency set whose services are all in-memory fakes, with
  /// the clock fixed at [startedAt].
  new({DateTime? startedAt})
    : repository = FakeMenuRepository(),
      classifier = FakeMenuClassifier(),
      estimateClassifier = FakeMenuClassifier(),
      settingsStore = FakeSettingsStore(),
      notesStore = FakeNotesStore(),
      clock = FakeClock(startedAt ?? DateTime.utc(2026)),
      logger = FakeAppLogger(),
      connectivity = FakeConnectivity(),
      externalLinkOpener = FakeExternalLinkOpener(),
      menuSharer = FakeMenuSharer(),
      locationService = FakeLocationService(),
      venueSearchService = FakeVenueSearchService(),
      scannedMenuClassifier = FakeScannedMenuClassifier(),
      pagePicker = FakePagePicker(),
      qrScanner = FakeQrScanner(),
      scannedPages = ScannedPagesRegistry();

  /// The faked menu repository.
  final FakeMenuRepository repository;

  /// The faked classifier.
  final FakeMenuClassifier classifier;

  /// The faked rule engine behind "Estimate this list" (issue #42): a
  /// separate instance from [classifier], so a test can assert the
  /// explicit action never reached the router.
  final FakeMenuClassifier estimateClassifier;

  /// The faked settings store.
  final FakeSettingsStore settingsStore;

  /// The faked notes store.
  final FakeNotesStore notesStore;

  /// The faked clock; advance it to control cache freshness.
  final FakeClock clock;

  /// The faked logger; inspect its records.
  final FakeAppLogger logger;

  /// The faked connectivity check; flip [FakeConnectivity.online] to
  /// drive the persistent offline banner (issue #68).
  final FakeConnectivity connectivity;

  /// The faked external link opener; inspect
  /// [FakeExternalLinkOpener.openCalls].
  final FakeExternalLinkOpener externalLinkOpener;

  /// The faked menu sharer; inspect [FakeMenuSharer.shareCalls].
  final FakeMenuSharer menuSharer;

  /// The faked location service; script it by setting
  /// [FakeLocationService.result].
  final FakeLocationService locationService;

  /// The faked venue search (issue #39); script it with
  /// [FakeVenueSearchService.queueFound] and friends.
  final FakeVenueSearchService venueSearchService;

  /// The faked vision classifier behind the Scan tab (issue #89); script
  /// it with [FakeScannedMenuClassifier.respondWith].
  final FakeScannedMenuClassifier scannedMenuClassifier;

  /// The faked page picker behind the Scan tab (issue #82); script it
  /// with [FakePagePicker.queueTakePhoto] and friends.
  final FakePagePicker pagePicker;

  /// The faked QR scanner behind the Scan tab's "Scan QR code" action
  /// (issue #182); script it with [FakeQrScanner.queuePayload].
  final FakeQrScanner qrScanner;

  /// The in-memory scanned-pages registry (issue #89) — the real one, as
  /// it does no I/O; put a scan here to drive the menu header's "View
  /// pages".
  final ScannedPagesRegistry scannedPages;

  /// The faked visit history behind the Recent list (issue #307), stamped
  /// by [clock]; seed it with [FakeVisitHistoryStore.seed].
  late final FakeVisitHistoryStore visitHistory = FakeVisitHistoryStore(clock);

  /// The faked shared menu store (issue #312); inspect
  /// [FakeMenuStoreClient.uploads].
  final FakeMenuStoreClient menuStoreClient = FakeMenuStoreClient();

  /// The dependency set to hand to the app widget.
  AppDependencies get dependencies => AppDependencies(
    menuRepository: repository,
    menuClassifier: classifier,
    estimateClassifier: estimateClassifier,
    settingsStore: settingsStore,
    notesStore: notesStore,
    clock: clock,
    logger: logger,
    connectivity: connectivity,
    externalLinkOpener: externalLinkOpener,
    menuSharer: menuSharer,
    locationService: locationService,
    venueSearchService: venueSearchService,
    scannedMenuClassifier: scannedMenuClassifier,
    pagePicker: pagePicker,
    qrScanner: qrScanner,
    scannedPages: scannedPages,
    visitHistory: visitHistory,
    menuStoreClient: menuStoreClient,
  );
}
