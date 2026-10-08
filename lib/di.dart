import 'package:connectivity_plus/connectivity_plus.dart' as plus;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show GlobalKey, NavigatorState;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:ketoclub/services/classifier/backend_menu_classifier.dart';
import 'package:ketoclub/services/classifier/backend_scanned_menu_classifier.dart';
import 'package:ketoclub/services/classifier/classifier_router.dart';
import 'package:ketoclub/services/classifier/fallback_classifiers.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/classifier/llm_menu_classifier.dart';
import 'package:ketoclub/services/classifier/llm_menu_question_answerer.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_classifier_router.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/services/classifier/vision_menu_classifier.dart';
import 'package:ketoclub/services/community/menu_store_client.dart';
import 'package:ketoclub/services/llm/backend_chat_client.dart';
import 'package:ketoclub/services/llm/fallback_chat_client.dart';
import 'package:ketoclub/services/llm/gemini_chat_client.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';
import 'package:ketoclub/services/location/geolocator_location_service.dart';
import 'package:ketoclub/services/menu/backend/backend_menu_adapter.dart';
import 'package:ketoclub/services/menu/fallback_menu_adapter.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/tenbis/tenbis_adapter.dart';
import 'package:ketoclub/services/menu/website/backend_website_fetcher.dart';
import 'package:ketoclub/services/menu/website/direct_website_fetcher.dart';
import 'package:ketoclub/services/menu/website/website_adapter.dart';
import 'package:ketoclub/services/menu/website/website_fetcher.dart';
import 'package:ketoclub/services/menu/wolt/wolt_adapter.dart';
import 'package:ketoclub/services/platform/app_info.dart';
import 'package:ketoclub/services/platform/app_logger.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/platform/connectivity.dart';
import 'package:ketoclub/services/platform/device_page_picker.dart';
import 'package:ketoclub/services/platform/external_link_opener.dart';
import 'package:ketoclub/services/platform/image_downscaler.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/services/platform/qr_scanner.dart';
import 'package:ketoclub/services/platform/scan_budget.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/services/storage/api_key_store.dart';
import 'package:ketoclub/services/storage/install_id_store.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/notes_store.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';
import 'package:ketoclub/services/venue/backend_venue_search_service.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
import 'package:ketoclub/services/venue/wolt/wolt_venue_search_service.dart';
import 'package:ketoclub/state/app_dependencies.dart';
import 'package:ketoclub/state/scanned_pages_registry.dart';
import 'package:ketoclub/widgets/mobile_qr_scanner.dart';
import 'package:screen_brightness/screen_brightness.dart' as plugin;
import 'package:shared_preferences/shared_preferences.dart';

/// The name of the Hive box holding cached menus and their analyses.
const String _menuCacheBoxName = 'menu_cache';

/// The name of the Hive box holding the cache keys of pinned menus, apart
/// from [_menuCacheBoxName] so the entries' stored shape never changes.
const String _menuCachePinsBoxName = 'menu_cache_pins';

/// The name of the Hive box holding the visit history behind the Recent list
/// (issue #307): one entry per menu opened on this device.
const String _menuHistoryBoxName = 'menu_history';

/// KetoClub's own backend, read at build time (`backend_plan.md` §4.1).
/// Empty when the app was built with no `--dart-define=KETOCLUB_BACKEND_URL=…`,
/// which is every build until issue #99 adds a Settings override.
///
/// **D25 amends D17: every platform, phones included, asks the backend
/// first when this is set** (issue #331). Menus arrive with their analysis
/// from its complete-result routes ([menuAdaptersFor]), a menu the app
/// already holds and a scan's pages are classified there
/// ([llmClassifierFor], [scannedClassifierFor]), venue search goes through
/// it ([venueSearchFor]) and so do menu questions ([chatClientFor]). Each
/// keeps the engine the app used before D25 as its fallback — on a phone
/// Wolt, 10bis and the user's own Gemini key; on web the raw proxy routes
/// ([menuProxyBase]) and the backend's chat route — so the backend stays an
/// accelerator, never a dependency (D11). With no address every selector
/// answers exactly the graph the app had before D25.
///
/// The shared menu store (D24) uses the same address on every platform
/// through [BackendMenuStoreClient]; with none configured that client
/// answers `notConfigured` without I/O, so a build with no backend still
/// sends nothing anywhere.
const String _configuredBackendUrl = String.fromEnvironment(
  'KETOCLUB_BACKEND_URL',
);

/// KetoClub's backend address parsed from [configured], or null when there
/// is none (`backend_plan.md` §4.1).
///
/// Only an absolute `http` or `https` URI with a host is accepted; a blank,
/// malformed or non-http(s) value is treated the same as "not configured"
/// rather than risking a request to a nonsense address. A null result is
/// what makes [BackendChatClient] answer `notConfigured` without any I/O.
///
/// A pure, top-level function rather than a private helper so
/// `di_test.dart` can cover every branch without a `--dart-define` of its
/// own.
Uri? backendBaseUrl(String configured) {
  if (configured.isEmpty) return null;
  final uri = Uri.tryParse(configured);
  if (uri == null || !uri.isAbsolute || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}

/// Whether the *direct* [WoltMenuAdapter], `TenBisAdapter` and
/// `WoltVenueSearchService` should route through KetoClub's raw proxy
/// routes instead of calling the platform directly, and at what address
/// (`backend_plan.md` §3.3, §4.1, issue #122).
///
/// Since D25 those are the fallbacks behind the backend's complete-result
/// routes ([menuAdaptersFor], [venueSearchFor]) and, with no backend, the
/// only adapters. Only a browser needs the raw proxy — native HTTP has no
/// CORS problem to route around, so a phone's fallback reads the platform
/// itself — and only when [configured] is a usable [backendBaseUrl].
///
/// A pure, top-level function rather than a private helper so
/// `di_test.dart` can cover every branch without a `--dart-define` of its
/// own.
Uri? menuProxyBase({required bool runsInBrowser, required String configured}) =>
    runsInBrowser ? backendBaseUrl(configured) : null;

/// How a restaurant's own website is fetched (architecture.md D19): through
/// KetoClub's backend when [proxyBase] is set — the web build with a
/// backend, see [menuProxyBase] — and straight from the site otherwise.
/// On a phone that is the rule (D17); in a browser with no backend the
/// direct fetch meets the site's cross-origin block and says so
/// (`blockedByBrowser`). Constructing either performs no I/O.
///
/// A pure, top-level function so `di_test.dart` can cover both branches.
WebsiteFetcher websiteFetcherFor({
  required http.Client client,
  required Uri? proxyBase,
  required InstallIdStore installIdStore,
}) => proxyBase != null
    ? BackendWebsiteFetcher(
        client: client,
        proxyBase: proxyBase,
        installIdStore: installIdStore,
      )
    : DirectWebsiteFetcher(client: client);

/// Where the user's own Gemini API key is kept, or null when this build
/// has none (architecture.md D17).
///
/// Off the web — iOS and Android — the app calls Gemini directly with a
/// key the user pastes into Settings, kept in the platform's secure
/// storage. In a browser the backend holds the key (D12), so there is no
/// store, and so no key field in Settings. Constructing the store touches
/// no platform channel.
///
/// A pure, top-level function rather than a private helper so
/// `di_test.dart` can cover both branches, as with [menuProxyBase].
ApiKeyStore? apiKeyStoreFor({required bool runsInBrowser}) =>
    runsInBrowser ? null : const SecureApiKeyStore();

/// The chat client the device's own model engines send through: the
/// `LlmMenuClassifier` and `VisionMenuClassifier` that the backend's
/// classifiers fall back to, and that are the only engines with no backend
/// (architecture.md §9, D12, D17, D25).
///
/// With an [apiKeyStore] — iOS and Android, see [apiKeyStoreFor] — it is
/// a [GeminiChatClient] calling Google directly with the user's key, and
/// [backendBase] is ignored: the backend was already asked first, by the
/// classifier in front of this engine. Without one — the web build — it is
/// a [BackendChatClient] posting to [backendBase], which answers
/// `notConfigured` without I/O when that is null. Keying the choice on
/// the store, not on the platform again, is what keeps "the key field
/// Settings shows" and "the client that reads the key" from disagreeing.
LlmChatClient deviceChatClientFor({
  required http.Client client,
  required ApiKeyStore? apiKeyStore,
  required Uri? backendBase,
  required InstallIdStore installIdStore,
}) => apiKeyStore != null
    ? GeminiChatClient(client: client, apiKeyStore: apiKeyStore)
    : BackendChatClient(
        client: client,
        baseUrl: backendBase,
        installIdStore: installIdStore,
      );

/// The chat client a caller with nothing in front of it sends through —
/// the menu question answerer (architecture.md §9.5, D25).
///
/// It prefers KetoClub's backend when one is configured, and the phone's
/// own Gemini key is the fallback: on a phone with both, a
/// [FallbackChatClient] over a [BackendChatClient] and the
/// [deviceChatClientFor] client. Everywhere else it is the
/// [deviceChatClientFor] client itself: the web build already goes
/// through the backend, and a phone with no backend calls Google
/// directly (D17).
LlmChatClient chatClientFor({
  required http.Client client,
  required ApiKeyStore? apiKeyStore,
  required Uri? backendBase,
  required InstallIdStore installIdStore,
}) {
  final device = deviceChatClientFor(
    client: client,
    apiKeyStore: apiKeyStore,
    backendBase: backendBase,
    installIdStore: installIdStore,
  );
  if (apiKeyStore == null || backendBase == null) return device;
  return FallbackChatClient(
    primary: BackendChatClient(
      client: client,
      baseUrl: backendBase,
      installIdStore: installIdStore,
    ),
    fallback: device,
  );
}

/// The engine in the language-model slot of the menu screen's
/// `RoutingMenuClassifier` (architecture.md §6.2, D25).
///
/// With a [backendBase] it is a [FallbackMenuClassifier] asking a
/// [BackendMenuClassifier] there first and [device] — the
/// `LlmMenuClassifier` the app used before D25 — when the backend could
/// not answer. Without one it is [device] alone. Either way it sits behind
/// the router, which checks consent and connectivity before anything
/// leaves the device. Constructing it performs no I/O.
MenuClassifier llmClassifierFor({
  required Uri? backendBase,
  required http.Client client,
  required InstallIdStore installIdStore,
  required MenuClassifier device,
}) => backendBase == null
    ? device
    : FallbackMenuClassifier(
        primary: BackendMenuClassifier(
          client: client,
          baseUrl: backendBase,
          installIdStore: installIdStore,
        ),
        fallback: device,
      );

/// The engine in the vision slot of the Scan tab's
/// `RoutingScannedMenuClassifier` (architecture.md D15, D25).
///
/// With a [backendBase] it is a [FallbackScannedMenuClassifier] asking a
/// [BackendScannedMenuClassifier] there first and [device] — the
/// `VisionMenuClassifier` the app used before D25 — when the backend could
/// not answer. Without one it is [device] alone. Either way it sits behind
/// the router, which checks consent and connectivity before a page leaves
/// the device. Constructing it performs no I/O.
ScannedMenuClassifier scannedClassifierFor({
  required Uri? backendBase,
  required http.Client client,
  required InstallIdStore installIdStore,
  required ScannedMenuClassifier device,
}) => backendBase == null
    ? device
    : FallbackScannedMenuClassifier(
        primary: BackendScannedMenuClassifier(
          client: client,
          baseUrl: backendBase,
          installIdStore: installIdStore,
        ),
        fallback: device,
      );

/// The venue search the Discovery screen uses (architecture.md D13, D25).
///
/// With a [backendBase] it is a [FallbackVenueSearchService] asking a
/// [BackendVenueSearchService] there first and [direct] — the
/// `WoltVenueSearchService` the app used before D25 — when the backend
/// could not answer. Without one it is [direct] alone. Constructing it
/// sends nothing.
VenueSearchService venueSearchFor({
  required Uri? backendBase,
  required http.Client client,
  required InstallIdStore installIdStore,
  required VenueSearchService direct,
}) => backendBase == null
    ? direct
    : FallbackVenueSearchService(
        primary: BackendVenueSearchService(
          client: client,
          baseUrl: backendBase,
          installIdStore: installIdStore,
        ),
        fallback: direct,
      );

/// How long a [BackendMenuAdapter] waits for a menu and its analysis.
///
/// A cold analysis of a 20-dish menu was measured at 33.5 s through the
/// backend (architecture.md §17.1, #165), and the backend's own Gemini
/// call may take up to 110 s, so the fetch is given the same two minutes
/// as a direct model call (`llmRequestTimeout`'s value).
const Duration backendMenuTimeout = Duration(seconds: 120);

/// The menu adapters the menu screen's repository reads through
/// (architecture.md §6.1, D25), one per entry of [direct] and in its order.
///
/// With a [backendBase] each is a [FallbackMenuAdapter] asking a
/// [BackendMenuAdapter] for the same source first — the menu and its
/// analysis in one request, under the options [readOptions] answers — and
/// the [direct] adapter when the backend could not serve it. The backend
/// is asked only while those options carry the user's AI-analysis
/// consent: its routes analyse what they read, so without it the device
/// reads the menu its own way. Without a [backendBase] the answer is
/// [direct] itself. Constructing any of them performs no I/O.
List<PlatformMenuAdapter> menuAdaptersFor({
  required Uri? backendBase,
  required http.Client client,
  required InstallIdStore installIdStore,
  required Future<ClassificationOptions> Function() readOptions,
  required List<PlatformMenuAdapter> direct,
}) {
  if (backendBase == null) return direct;
  Future<bool> consentGiven() async =>
      (await readOptions()).estimationConsentGiven;
  return <PlatformMenuAdapter>[
    for (final adapter in direct)
      FallbackMenuAdapter(
        primary: BackendMenuAdapter(
          client: client,
          baseUrl: backendBase,
          installIdStore: installIdStore,
          source: adapter.source,
          readOptions: readOptions,
          timeout: backendMenuTimeout,
        ),
        fallback: adapter,
        usePrimary: consentGiven,
      ),
  ];
}

/// The QR scanner behind the Scan tab's "Scan QR code" action (issue #182),
/// or one that says it is unavailable when this build has no camera scanner.
///
/// In a browser the answer is [NoQrScanner]: pasting the URL already works
/// there, and the Scan tab hides the action. Everywhere else it is a
/// [MobileQrScanner] that shows its camera page on the navigator behind
/// [navigatorKey], which the app also gives `MaterialApp`. Constructing
/// either performs no plugin I/O; the camera opens only when a scan runs.
///
/// A pure, top-level function so `di_test.dart` can cover both branches.
QrScanner qrScannerFor({
  required bool runsInBrowser,
  required GlobalKey<NavigatorState> navigatorKey,
}) => runsInBrowser
    ? const NoQrScanner()
    : MobileQrScanner(navigatorKey: navigatorKey);

/// Composition root (architecture.md §18.1).
///
/// This is the only file under lib/ that may construct a concrete service,
/// an `http.Client`, a storage box, or a plugin wrapper. Everything it builds
/// is handed to the app as an [AppDependencies] of interfaces.
///
/// Tests build the app widget with their own [AppDependencies] made of fakes
/// and never go through this function.
///
/// **No constructor called here may perform plugin I/O.** This function runs
/// from `main()` and from widget tests that have no plugin binding, so anything
/// needing a platform channel is passed as a closure and invoked on first use —
/// see the Hive opener and the preferences loader below. Keeping this
/// synchronous is what lets `di_test.dart`, `main_test.dart` and the launch
/// flow test all call it, and `di_test` asserts that it stays that way.
AppDependencies buildDependencies() {
  final client = http.Client();
  const clock = SystemClock();
  final connectivity = DeviceConnectivity(plus.Connectivity());
  // Passed to every client of KetoClub's own backend: the install id is
  // sent nowhere but the `X-KetoClub-Install-Id` header on a request to it
  // (`backend_plan.md` §3.4), which rate-limits its routes by it. With no
  // backend configured nothing reads it.
  final installIdStore = PrefsInstallIdStore(
    load: SharedPreferences.getInstance,
  );
  // KetoClub's backend, on every platform (D25 amending D17); null when
  // this build has none, which makes every selector below answer the
  // graph the app had before D25.
  final backendBase = backendBaseUrl(_configuredBackendUrl);

  // iOS and Android: the user's own Gemini key, read by the direct
  // client and written by Settings (architecture.md D17). Web: null.
  final apiKeyStore = apiKeyStoreFor(runsInBrowser: kIsWeb);

  const logger = DeveloperLogAppLogger();
  const heuristic = HeuristicMenuClassifier(clock: clock);
  // One chat client for the device's own engines that reach the model:
  // the text classifier and the scan path's vision classifier (issue
  // #89). With a backend they are the fallback behind its classifiers;
  // without one, the engines themselves. Each is one request per call
  // (D6).
  final deviceChatClient = deviceChatClientFor(
    client: client,
    apiKeyStore: apiKeyStore,
    backendBase: backendBase,
    installIdStore: installIdStore,
  );
  final llm = llmClassifierFor(
    backendBase: backendBase,
    client: client,
    installIdStore: installIdStore,
    device: LlmMenuClassifier(deviceChatClient, clock),
  );
  // The question answerer (architecture.md D6, §9.5): one request per
  // explicit user question, never automatic, through the backend first
  // when there is one.
  final menuQuestionAnswerer = LlmMenuQuestionAnswerer(
    chatClientFor(
      client: client,
      apiKeyStore: apiKeyStore,
      backendBase: backendBase,
      installIdStore: installIdStore,
    ),
  );
  final settingsStore = PrefsSettingsStore(load: SharedPreferences.getInstance);
  // The options the menu screen builds from Settings, read on use: the
  // backend's menu routes and a website's PDF read classify under them, so
  // the analysis either caches is one the menu screen reuses.
  Future<ClassificationOptions> readOptions() async =>
      ClassificationOptions.fromSettings(await settingsStore.read());
  // The scan path (issue #89, D15): consent and the connectivity
  // pre-check in front of the vision engine — the backend's first when
  // there is one (D25). No rules fallback: a photograph has no text for
  // the rule engine. Constructing any of it does no I/O. A website's PDF
  // menu is read through it too (D19).
  final scannedMenuClassifier = RoutingScannedMenuClassifier(
    vision: scannedClassifierFor(
      backendBase: backendBase,
      client: client,
      installIdStore: installIdStore,
      device: VisionMenuClassifier(client: deviceChatClient, clock: clock),
    ),
    connectivity: connectivity,
  );
  final proxyBase = menuProxyBase(
    runsInBrowser: kIsWeb,
    configured: _configuredBackendUrl,
  );
  // `screen_brightness` has no web implementation; the no-op is a
  // deliberate composition choice for that platform, not a fallback from a
  // caught failure (screen_brightness.dart's own doc comment).
  final screenBrightness = kIsWeb
      ? const NoOpScreenBrightness()
      : DeviceScreenBrightness(plugin.ScreenBrightness());

  // The QR camera pushes a page on the app's own navigator, so the scanner
  // and `MaterialApp` share this key (issue #182). Web has no camera
  // scanner: pasting the URL already works there.
  final navigatorKey = GlobalKey<NavigatorState>();
  final qrScanner = qrScannerFor(
    runsInBrowser: kIsWeb,
    navigatorKey: navigatorKey,
  );

  // The adapters the app reads a platform with itself: straight to the
  // platform on a phone, through the raw proxy routes in a browser with a
  // backend (D11). With a backend they are the fallbacks (D25).
  final directAdapters = <PlatformMenuAdapter>[
    WoltMenuAdapter(client: client, proxyBase: proxyBase),
    TenBisAdapter(client: client, proxyBase: proxyBase),
    // Any other restaurant URL (D19). A PDF menu is read by the vision
    // path under the options the menu screen would build, so the
    // analysis it caches is the one the screen reuses.
    WebsiteMenuAdapter(
      fetcher: websiteFetcherFor(
        client: client,
        proxyBase: proxyBase,
        installIdStore: installIdStore,
      ),
      scannedClassifier: scannedMenuClassifier,
      readOptions: readOptions,
      clock: clock,
    ),
  ];
  // One cache for both repositories below, so a menu the quick score read
  // is the menu screen's too, and the reverse.
  final menuCache = HiveMenuCache(
    openBox: () async {
      await Hive.initFlutter();
      return await Hive.openBox<String>(_menuCacheBoxName);
    },
    openPinBox: () async {
      await Hive.initFlutter();
      return await Hive.openBox<String>(_menuCachePinsBoxName);
    },
  );
  final menuRepository = CachedMenuRepository(
    adapters: menuAdaptersFor(
      backendBase: backendBase,
      client: client,
      installIdStore: installIdStore,
      readOptions: readOptions,
      direct: directAdapters,
    ),
    cache: menuCache,
    clock: clock,
  );
  // Discovery's quick score reads menus through the direct adapters only,
  // so it never asks the backend to classify (D13, D21, D25). With no
  // backend the two repositories are one.
  final estimateMenuRepository = backendBase == null
      ? menuRepository
      : CachedMenuRepository(
          adapters: directAdapters,
          cache: menuCache,
          clock: clock,
        );

  return AppDependencies(
    menuRepository: menuRepository,
    estimateMenuRepository: estimateMenuRepository,
    menuClassifier: RoutingMenuClassifier(llm, heuristic, connectivity),
    // The rule engine on its own, for the quick score — the automatic run
    // when a result list arrives and the explicit "Quick score the rest"
    // tap alike (issue #42, D13, D21): neither may reach the router or the
    // language model.
    estimateClassifier: heuristic,
    menuQuestionAnswerer: menuQuestionAnswerer,
    settingsStore: settingsStore,
    notesStore: PrefsNotesStore(load: SharedPreferences.getInstance),
    clock: clock,
    logger: logger,
    // The same instance the classifier router already pre-checks with
    // (architecture.md §14 D10) — the persistent offline banner (issue
    // #68) reads it too, rather than opening a second platform channel.
    connectivity: connectivity,
    screenBrightness: screenBrightness,
    externalLinkOpener: const UrlLauncherLinkOpener(),
    // Reads the version lazily, after Settings' first frame (issue #258).
    appInfo: const DeviceAppInfo(),
    menuSharer: const SharePlusMenuSharer(),
    // Every geolocator call defaults to the real plugin inside
    // GeolocatorLocationService itself, so no arguments are needed here
    // (its own doc comment) — this is also why `di.dart` needs no import
    // of `package:geolocator`.
    locationService: GeolocatorLocationService(),
    // Through the backend first when there is one (D25); the direct Wolt
    // search behind it follows the menu adapters' routing rule (issue
    // #39). The constructors send nothing and draw no randomness.
    venueSearchService: venueSearchFor(
      backendBase: backendBase,
      client: client,
      installIdStore: installIdStore,
      direct: WoltVenueSearchService(
        client: client,
        installIdStore: installIdStore,
        proxyBase: proxyBase,
      ),
    ),
    apiKeyStore: apiKeyStore,
    scannedMenuClassifier: scannedMenuClassifier,
    // In memory only; the pages never reach Hive (issue #89).
    scannedPages: ScannedPagesRegistry(),
    // The device picker builds no plugin state until a page is picked
    // (issue #82), so this stays free of plugin I/O at start-up.
    pagePicker: DevicePagePicker(),
    // Opens no camera until a scan is asked for (issue #182).
    qrScanner: qrScanner,
    // Pure Dart and const: decodes nothing until a scan is over budget
    // (issue #298).
    scanBudget: const ScanBudget(downscaler: JpegImageDownscaler()),
    navigatorKey: navigatorKey,
    // Opened on first use, like the menu cache's boxes; the history never
    // leaves the device through this store (issue #307, D8).
    visitHistory: HiveVisitHistoryStore(
      openBox: () async {
        await Hive.initFlutter();
        return await Hive.openBox<String>(_menuHistoryBoxName);
      },
      clock: clock,
    ),
    // On every platform, phones included (D24 amending D17; see
    // [_configuredBackendUrl]): the menu store is the backend's alone.
    // Sends only with the user's AI-analysis consent (MenuController.open),
    // never a personal setting, and nothing at all when no backend is
    // configured. The constructor reads no install id and sends nothing.
    menuStoreClient: BackendMenuStoreClient(
      client: client,
      baseUrl: backendBase,
      installIdStore: installIdStore,
      logger: logger,
    ),
    // Whether menus, scans and searches go to the backend first (D25);
    // the consent and scan disclosures follow it (issue #330).
    backendConfigured: backendBase != null,
  );
}
