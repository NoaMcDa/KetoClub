// Harness and fakes for the flow tests (FLOW_TEST_CONVENTIONS.md,
// architecture.md §18.4).
//
// **This file must stay in the same directory as the flow tests, and they must
// import it by bare filename.** `flutter drive` compiles a flow test as a web
// app entry point, and `org-dartlang-app:///` is rooted at that file's own
// directory, so any relative import escaping it — `../support/…`, or
// `../../test/fakes/…` — is unresolvable and the app fails to compile before a
// browser is ever involved. Only same-directory and `package:` imports work.
//
// That is why these fakes are here rather than reused from `test/fakes/`, which
// is otherwise the single home for them. The duplication is bounded: they
// implement the same interfaces from `lib/services/`, so a contract change
// breaks this file's compile rather than letting it drift quietly.
//
// A local check that catches a bad import here, without needing a browser:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/flows/<file>.dart -d web-server \
//     --browser-name=chrome --headless
// The compile happens while it waits for the browser, so the error appears even
// where a browser cannot start. `flutter build web --target=…` does NOT catch
// it: that resolves imports from the package root instead.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/app.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/services/location/location_service.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/platform/app_logger.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/platform/connectivity.dart';
import 'package:ketoclub/services/platform/external_link_opener.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/services/platform/page_picker.dart';
import 'package:ketoclub/services/storage/api_key_store.dart';
import 'package:ketoclub/services/storage/install_id_store.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/notes_store.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/state/app_dependencies.dart';
import 'package:ketoclub/state/scanned_pages_registry.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// Pumps the whole app over [fakes] and settles it.
///
/// A flow test drives the app through its UI and asserts on what a user can
/// see, never on a controller reached from the side.
Future<void> pumpApp(WidgetTester tester, FakeAppDependencies fakes) async {
  await tester.pumpWidget(KetoClubApp(dependencies: fakes.dependencies));
  await tester.pumpAndSettle();
}

/// Types [text] into the first text field on screen and settles.
Future<void> enterText(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(EditableText).first, text);
  await tester.pumpAndSettle();
}

/// The bottom-navigation destination labelled [label].
///
/// Scoped to the [NavigationBar] on purpose. `navSettings` and
/// `settingsTitle` are both the literal string "Settings", so a bare
/// `find.text('Settings')` matches two widgets whenever the Settings tab
/// is showing — the destination label and the app bar title — and a tap
/// on an ambiguous finder fails. Every flow test taps tabs through this.
Finder navDestination(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

/// Taps the widget [finder] resolves to and settles.
Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// An [AppDependencies] of in-memory fakes, with each one exposed so a flow
/// test can steer it before pumping and assert on it afterwards.
final class FakeAppDependencies {
  /// Creates a dependency set whose services are all in-memory fakes.
  new()
    : repository = FlowFakeMenuRepository(),
      classifier = FlowFakeMenuClassifier(),
      estimateClassifier = HeuristicMenuClassifier(clock: FlowFakeClock()),
      settingsStore = FlowFakeSettingsStore(),
      notesStore = FlowFakeNotesStore(),
      clock = FlowFakeClock(),
      logger = FlowFakeAppLogger(),
      connectivity = FlowFakeConnectivity(),
      externalLinkOpener = FlowFakeExternalLinkOpener(),
      menuSharer = FlowFakeMenuSharer(),
      locationService = FlowFakeLocationService(),
      venueSearchService = FlowFakeVenueSearchService(),
      scannedClassifier = FlowFakeScannedMenuClassifier(),
      pagePicker = FlowFakePagePicker(),
      scannedPages = ScannedPagesRegistry();

  /// The faked menu repository; script it with [FlowFakeMenuRepository.stub].
  final FlowFakeMenuRepository repository;

  /// The faked classifier; script it with
  /// [FlowFakeMenuClassifier.respondWith].
  final FlowFakeMenuClassifier classifier;

  /// The faked settings store.
  final FlowFakeSettingsStore settingsStore;

  /// The faked notes store; persists across a screen revisit the same way
  /// `PrefsNotesStore` does, so a flow can assert a note survives.
  final FlowFakeNotesStore notesStore;

  /// The faked clock, fixed so nothing in a flow test reads wall time.
  final FlowFakeClock clock;

  /// The faked logger.
  final FlowFakeAppLogger logger;

  /// The faked connectivity check; flip [FlowFakeConnectivity.online] to
  /// drive the persistent offline banner (issue #68).
  final FlowFakeConnectivity connectivity;

  /// The faked external link opener.
  final FlowFakeExternalLinkOpener externalLinkOpener;

  /// The faked menu sharer (issue #54).
  final FlowFakeMenuSharer menuSharer;

  /// The faked location service (issue #37); settable via
  /// [FlowFakeLocationService.result].
  final FlowFakeLocationService locationService;

  /// The faked venue search (issue #39); script it with
  /// [FlowFakeVenueSearchService.result].
  final FlowFakeVenueSearchService venueSearchService;

  /// The faked vision classifier behind the Scan tab (issue #89); script
  /// it with [FlowFakeScannedMenuClassifier.result].
  final FlowFakeScannedMenuClassifier scannedClassifier;

  /// The faked page picker behind the Scan tab (issue #82); script it
  /// with [FlowFakePagePicker.photos] and friends.
  final FlowFakePagePicker pagePicker;

  /// The in-memory scanned-pages registry (issue #89) — the real one, as
  /// it does no I/O, shared by the Scan tab and the menu screen.
  final ScannedPagesRegistry scannedPages;

  /// When set, [dependencies] wires this in place of [classifier].
  ///
  /// Every flow test that only needs to script "what the top-level
  /// classifier answered" uses [classifier] directly, matching the rest of
  /// this harness. A flow that must exercise real routing — the real
  /// `RoutingMenuClassifier` degrading to a real `HeuristicMenuClassifier`
  /// over a faked LLM engine and a faked `Connectivity`, rather than a
  /// classifier scripted with the finished answer — sets this instead
  /// (see `offline_analysis_flow_test.dart`,
  /// `consent_withheld_flow_test.dart` and
  /// `backend_unreachable_analysis_flow_test.dart`).
  MenuClassifier? classifierOverride;

  /// When set, [dependencies] wires this in place of [repository] — for a
  /// flow that must run the real `CachedMenuRepository` over a real
  /// platform adapter and a scripted HTTP client (see
  /// `direct_gemini_analysis_flow_test.dart`), rather than a repository
  /// scripted with the finished menu.
  MenuRepository? repositoryOverride;

  /// When set, [dependencies] wires this in place of [scannedClassifier]
  /// — for a scan flow that must run the real vision classifier or its
  /// router over a faked chat client (issue #84), the same way
  /// [classifierOverride] does for the text path.
  ScannedMenuClassifier? scannedClassifierOverride;

  /// When set, [dependencies] wires this in place of [pagePicker].
  PagePicker? pagePickerOverride;

  /// The user's own Gemini API key store, as `di.dart` provides it on iOS
  /// and Android (architecture.md D17). Null by default — the web build's
  /// value — so Settings shows no key section unless a flow sets one.
  ApiKeyStore? apiKeyStore;

  /// The engine behind "Estimate this list" (issue #42, D13): the real
  /// on-device rule engine over the same fixed time as [clock], exactly
  /// as `di.dart` wires it, so a flow sees real rules verdicts while
  /// [classifier] records that the router was never asked.
  final HeuristicMenuClassifier estimateClassifier;

  /// The dependency set to hand to the app widget.
  AppDependencies get dependencies => AppDependencies(
    menuRepository: repositoryOverride ?? repository,
    menuClassifier: classifierOverride ?? classifier,
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
    apiKeyStore: apiKeyStore,
    scannedMenuClassifier: scannedClassifierOverride ?? scannedClassifier,
    pagePicker: pagePickerOverride ?? pagePicker,
    scannedPages: scannedPages,
  );
}

/// An [ApiKeyStore] backed by an in-memory field — mirrors `test/fakes`'
/// `FakeApiKeyStore`, duplicated here for the reason this file's own top
/// doc comment gives.
final class FlowFakeApiKeyStore implements ApiKeyStore {
  /// Creates a store holding [seed], or empty when omitted.
  new({String? seed}) : _key = seed;

  String? _key;

  @override
  Future<String?> read() async => _key;

  @override
  Future<void> write(String key) async => _key = key;

  @override
  Future<void> delete() async => _key = null;

  @override
  Future<bool> hasKey() async => _key != null;
}

/// An [InstallIdStore] answering one fixed, well-formed id — mirrors
/// `test/fakes`' `FakeInstallIdStore`, duplicated here for the reason this
/// file's own top doc comment gives.
final class FlowFakeInstallIdStore implements InstallIdStore {
  /// The id every call answers: 32 lowercase hex characters, the shape
  /// the backend accepts.
  static const String fixedId = '0123456789abcdef0123456789abcdef';

  @override
  Future<String> id() async => fixedId;
}

/// A [MenuCache] that remembers nothing, so a real `CachedMenuRepository`
/// built over it goes to its adapter on every open.
final class FlowForgetfulMenuCache implements MenuCache {
  @override
  Future<CachedMenu?> read(VenueRef ref) async => null;

  @override
  Future<void> write(CachedMenu entry) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<int> size() async => 0;

  @override
  Future<List<CachedMenuEntry>> entries() async => const <CachedMenuEntry>[];

  @override
  Future<int> count() async => 0;

  @override
  Future<void> remove(VenueRef ref) async {}
}

/// A [MenuRepository] that answers from a scripted map.
final class FlowFakeMenuRepository implements MenuRepository {
  final Map<String, MenuFetchResult> _stubs = <String, MenuFetchResult>{};
  final Map<String, CachedMenu> _cached = <String, CachedMenu>{};

  /// Scripts [load] to answer [result] for [ref].
  void stub(VenueRef ref, MenuFetchResult result) {
    _stubs[ref.cacheKey] = result;
  }

  /// Seeds the entry [cached] reads back, so a flow can start with an
  /// analysis already saved beside its menu (issue #57).
  void seedCache(CachedMenu entry) {
    _cached[entry.menu.venueRef.cacheKey] = entry;
  }

  @override
  Future<MenuFetchResult> load(
    VenueRef ref, {
    bool forceRefresh = false,
  }) async {
    // A pasted menu is answered from the cache alone, as the real
    // repository does (architecture.md D18).
    if (ref.source == MenuSource.scan) {
      final scanned = _cached[ref.cacheKey];
      return scanned == null
          ? const MenuFetchFailed(reason: MenuFetchFailureReason.scanNotSaved)
          : MenuFetched(menu: scanned.menu, fromCache: true);
    }
    final stubbed = _stubs[ref.cacheKey];
    if (stubbed == null) {
      return const MenuFetchFailed(
        reason: MenuFetchFailureReason.unsupportedSource,
      );
    }
    // Mirrors CachedMenuRepository.load: a successful fetch is cached, so
    // a flow test that opens a venue and then visits Saved
    // (`saved_tab_flow_test.dart`) finds it there exactly as it would over
    // the real repository — a plain `MenuFetched` stub is enough; nothing
    // has to call `saveAnalysis` first just to seed the list. And, as the
    // real repository does (architecture.md §6.4), an analysis already
    // cached for the same dish text survives the refetch, so a flow that
    // seeds one (`net_carb_limit_flow_test.dart`) sees it reused rather
    // than silently dropped.
    if (stubbed case MenuFetched(menu: final fetched)) {
      final previous = _cached[ref.cacheKey];
      final sameMenu =
          previous != null &&
          TextNormaliser.menuFingerprint(previous.menu) ==
              TextNormaliser.menuFingerprint(fetched);
      _cached[ref.cacheKey] = CachedMenu(
        menu: fetched,
        analysis: sameMenu ? previous.analysis : null,
      );
    }
    return stubbed;
  }

  @override
  Future<void> store(Menu menu) async {
    _cached[menu.venueRef.cacheKey] = CachedMenu(
      menu: menu,
      analysis: _cached[menu.venueRef.cacheKey]?.analysis,
    );
  }

  @override
  Future<CachedMenu?> cached(VenueRef ref) async => _cached[ref.cacheKey];

  @override
  Future<void> saveAnalysis(VenueRef ref, MenuAnalysis analysis) async {
    final entry = _cached[ref.cacheKey];
    if (entry != null) {
      _cached[ref.cacheKey] = CachedMenu(menu: entry.menu, analysis: analysis);
    }
  }

  @override
  Future<void> clearCache() async => _cached.clear();

  @override
  Future<List<CachedMenuEntry>> savedMenus() async => [
    for (final entry in _cached.values)
      CachedMenuEntry(
        ref: entry.menu.venueRef,
        venueName: entry.menu.venueName,
        fetchedAt: entry.menu.fetchedAt,
        dishCount: entry.menu.allDishes.length,
        engine: switch (entry.analysis) {
          final MenuAnalysed analysed => analysed.engine,
          _ => null,
        },
      ),
  ];

  @override
  Future<int> cachedMenuCount() async => _cached.length;

  @override
  Future<void> remove(VenueRef ref) async => _cached.remove(ref.cacheKey);
}

/// A [MenuClassifier] that returns whatever was scripted, or an all-green
/// analysis derived from the menu it is given.
final class FlowFakeMenuClassifier implements MenuClassifier {
  MenuAnalysis? _scripted;

  /// Every menu this classifier was asked about, in order.
  final List<Menu> calls = <Menu>[];

  /// The options each call in [calls] carried, in the same order.
  final List<ClassificationOptions> optionCalls = <ClassificationOptions>[];

  /// Scripts [classify] to return [analysis] for every later call, and
  /// forgets the calls recorded so far, so a test can script mid-journey and
  /// then assert on what the app asked for afterwards.
  void respondWith(MenuAnalysis analysis) {
    _scripted = analysis;
    calls.clear();
    optionCalls.clear();
  }

  @override
  Future<MenuAnalysis> classify(
    Menu menu, {
    ClassificationOptions options = const ClassificationOptions(),
  }) async {
    calls.add(menu);
    optionCalls.add(options);
    final scripted = _scripted;
    if (scripted != null) return scripted;
    return MenuAnalysed(
      dishes: <AnalysedDish>[
        for (final dish in menu.allDishes)
          AnalysedDish(
            dishId: dish.id,
            name: dish.name,
            verdict: DishVerdict.orderAsIs,
            why: 'Nothing starchy turned up in this dish.',
          ),
      ],
      unclassified: const <String>[],
      engine: const RulesEngine(
        reason: MenuAnalysisFailureReason.notConfigured,
      ),
      analysedAt: DateTime.utc(2026),
      options: options.snapshot,
    );
  }
}

/// A [Connectivity] whose answer is settable — mirrors `test/fakes`'
/// `FakeConnectivity`, duplicated here for the reason this file's own top
/// doc comment gives.
final class FlowFakeConnectivity implements Connectivity {
  /// Creates a connectivity fake reporting [online].
  new({this.online = true});

  /// Settable so a flow can flip it mid-journey.
  bool online;

  @override
  Future<bool> isOnline() async => online;
}

/// A [SettingsStore] backed by one in-memory value.
final class FlowFakeSettingsStore implements SettingsStore {
  AppSettings _settings = const AppSettings();

  @override
  Future<AppSettings> read() async => _settings;

  @override
  Future<void> write(AppSettings settings) async => _settings = settings;
}

/// A [Clock] fixed at a constant, so no flow test reads wall time.
final class FlowFakeClock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026);
}

/// An [AppLogger] that records what it was told.
final class FlowFakeAppLogger implements AppLogger {
  /// Messages passed to [info].
  final List<String> infos = <String>[];

  /// Messages passed to [warn].
  final List<String> warnings = <String>[];

  @override
  void info(String message) => infos.add(message);

  @override
  void warn(String message, {Object? error}) => warnings.add(message);
}

/// An [ExternalLinkOpener] that records every call and never touches a
/// real platform channel (issue #53).
final class FlowFakeExternalLinkOpener implements ExternalLinkOpener {
  /// Every URI [open] was called with, in call order.
  final List<Uri> openCalls = <Uri>[];

  @override
  Future<bool> open(Uri uri) async {
    openCalls.add(uri);
    return true;
  }
}

/// A [MenuSharer] that records every call and never touches a real
/// platform channel (issue #54).
final class FlowFakeMenuSharer implements MenuSharer {
  /// Every call [shareText] received, in call order.
  final List<({String text, String? subject})> shareCalls =
      <({String text, String? subject})>[];

  @override
  Future<bool> shareText(String text, {String? subject}) async {
    shareCalls.add((text: text, subject: subject));
    return true;
  }
}

/// A [LocationService] whose answer is settable — mirrors `test/fakes`'
/// `FakeLocationService`, duplicated here for the reason this file's own
/// top doc comment gives.
final class FlowFakeLocationService implements LocationService {
  /// Creates a location fake reporting [result].
  new({
    this.result = const LocationFound(
      latitude: 32.0809,
      longitude: 34.7806,
      accuracyMetres: 20,
    ),
  });

  /// Settable so a flow can steer it mid-journey.
  LocationResult result;

  @override
  Future<LocationResult> current() async => result;

  @override
  Future<bool> openSettings({required bool servicesOff}) async => true;
}

/// A [NotesStore] backed by an in-memory map, keyed by [VenueRef.cacheKey]
/// then dish id — persists for the lifetime of one flow test the same way
/// `PrefsNotesStore` persists across a real app session.
final class FlowFakeNotesStore implements NotesStore {
  final Map<String, Map<String, String>> _notes =
      <String, Map<String, String>>{};

  @override
  Future<String?> read(VenueRef ref, String dishId) async =>
      _notes[ref.cacheKey]?[dishId];

  @override
  Future<void> write(VenueRef ref, String dishId, String note) async {
    (_notes[ref.cacheKey] ??= <String, String>{})[dishId] = note;
  }

  @override
  Future<void> delete(VenueRef ref, String dishId) async {
    _notes[ref.cacheKey]?.remove(dishId);
  }

  @override
  Future<Map<String, String>> readAll(VenueRef ref) async =>
      Map<String, String>.from(
        _notes[ref.cacheKey] ?? const <String, String>{},
      );
}

/// A [VenueSearchService] answering one settable [result] and recording
/// every query — mirrors `test/fakes`' `FakeVenueSearchService`,
/// duplicated here for the reason this file's own top doc comment gives.
final class FlowFakeVenueSearchService implements VenueSearchService {
  /// What every search answers; an empty list until a flow sets it.
  VenueSearchResult result = const VenuesFound(<Venue>[]);

  /// Every position [nearby] was asked about, in call order.
  final List<({double latitude, double longitude})> nearbyCalls =
      <({double latitude, double longitude})>[];

  /// Every query [byName] was asked for, in call order.
  final List<String> byNameCalls = <String>[];

  @override
  Future<VenueSearchResult> nearby({
    required double latitude,
    required double longitude,
    required String language,
  }) async {
    nearbyCalls.add((latitude: latitude, longitude: longitude));
    return result;
  }

  @override
  Future<VenueSearchResult> byName(
    String query, {
    required String language,
    double? latitude,
    double? longitude,
  }) async {
    byNameCalls.add(query);
    if (query.trim().isEmpty) return const VenuesFound(<Venue>[]);
    return result;
  }
}

/// A [ScannedMenuClassifier] answering one settable [result] and recording
/// every call — mirrors `test/fakes`' `FakeScannedMenuClassifier`,
/// duplicated here for the reason this file's own top doc comment gives.
final class FlowFakeScannedMenuClassifier implements ScannedMenuClassifier {
  /// What every call answers; `notConfigured` — the shipped placeholder's
  /// answer — until a flow sets it.
  ScannedMenuResult result = const ScannedMenuFailed(
    reason: MenuAnalysisFailureReason.notConfigured,
  );

  /// Every scan this classifier was asked about, in order.
  final List<ScannedMenu> calls = <ScannedMenu>[];

  /// The options each call in [calls] carried, in the same order.
  final List<ClassificationOptions> optionCalls = <ClassificationOptions>[];

  @override
  Future<ScannedMenuResult> classify(
    ScannedMenu scan, {
    required ClassificationOptions options,
  }) async {
    calls.add(scan);
    optionCalls.add(options);
    return result;
  }
}

/// A [PagePicker] answering settable lists and counting calls — mirrors
/// `test/fakes`' `FakePagePicker`, duplicated here for the reason this
/// file's own top doc comment gives. Every list starts empty, which reads
/// as a cancelled picker.
final class FlowFakePagePicker implements PagePicker {
  /// What every [takePhoto] answers.
  List<ScannedPage> photos = const <ScannedPage>[];

  /// What every [pickImages] answers.
  List<ScannedPage> images = const <ScannedPage>[];

  /// What every [pickPdf] answers.
  List<ScannedPage> pdf = const <ScannedPage>[];

  /// The name of every method called, in call order.
  final List<String> calls = <String>[];

  @override
  Future<List<ScannedPage>> takePhoto() async {
    calls.add('takePhoto');
    return photos;
  }

  @override
  Future<List<ScannedPage>> pickImages() async {
    calls.add('pickImages');
    return images;
  }

  @override
  Future<List<ScannedPage>> pickPdf() async {
    calls.add('pickPdf');
    return pdf;
  }
}
