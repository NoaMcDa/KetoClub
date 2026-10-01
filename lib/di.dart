import 'package:connectivity_plus/connectivity_plus.dart' as plus;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show GlobalKey, NavigatorState;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:ketoclub/services/classifier/classifier_router.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/classifier/llm_menu_classifier.dart';
import 'package:ketoclub/services/classifier/llm_menu_question_answerer.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_classifier_router.dart';
import 'package:ketoclub/services/classifier/vision_menu_classifier.dart';
import 'package:ketoclub/services/llm/backend_chat_client.dart';
import 'package:ketoclub/services/llm/gemini_chat_client.dart';
import 'package:ketoclub/services/llm/llm_chat_client.dart';
import 'package:ketoclub/services/location/geolocator_location_service.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
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
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/services/platform/qr_scanner.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/services/storage/api_key_store.dart';
import 'package:ketoclub/services/storage/install_id_store.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/notes_store.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
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

/// KetoClub's own backend, read at build time (`backend_plan.md` §4.1).
/// Empty when the app was built with no `--dart-define=KETOCLUB_BACKEND_URL=…`,
/// which is every build until issue #99 adds a Settings override. Only the
/// web build reads it: there AI analysis goes through the backend, which
/// holds the model key, and so do menus (see [menuProxyBase]). iOS and
/// Android call Wolt and Gemini directly and ignore it (architecture.md
/// D17, see [chatClientFor]).
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

/// Whether [WoltMenuAdapter] or `TenBisAdapter` should route through
/// KetoClub's own backend instead of calling the platform directly, and
/// at what address (`backend_plan.md` §3.3, §4.1, issue #122). Both
/// adapters share this one value, the same registration-order pairing
/// `di_test.dart` covers for Wolt. `WoltVenueSearchService` (issue #39)
/// shares it too: Wolt's discovery endpoints have the same CORS lock.
///
/// The proxy is used only in a browser — native HTTP has no CORS problem
/// to route around, so a mobile build reads menus straight from the
/// platform — and only when [configured] is a usable [backendBaseUrl].
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

/// The chat client the LLM classifier sends its one request per menu
/// through (architecture.md §9, D12, D17).
///
/// With an [apiKeyStore] — iOS and Android, see [apiKeyStoreFor] — it is
/// a [GeminiChatClient] calling Google directly with the user's key, and
/// [backendBase] is ignored even when set. Without one — the web build —
/// it is a [BackendChatClient] posting to [backendBase], which answers
/// `notConfigured` without I/O when that is null. Keying the choice on
/// the store, not on the platform again, is what keeps "the key field
/// Settings shows" and "the client that reads the key" from disagreeing.
LlmChatClient chatClientFor({
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
  // Passed to the chat client and the venue search: the install id is
  // sent nowhere but the `X-KetoClub-Install-Id` header on a request to
  // KetoClub's own backend (`backend_plan.md` §3.4), which rate-limits
  // both the chat route and the discovery routes by it. Only the web build
  // makes such requests; on a phone the id is never read.
  final installIdStore = PrefsInstallIdStore(
    load: SharedPreferences.getInstance,
  );

  // iOS and Android: the user's own Gemini key, read by the direct
  // client and written by Settings (architecture.md D17). Web: null.
  final apiKeyStore = apiKeyStoreFor(runsInBrowser: kIsWeb);

  const heuristic = HeuristicMenuClassifier(clock: clock);
  // One chat client for both engines that reach the model: the text
  // classifier, the scan path's vision classifier (issue #89), and the
  // menu question answerer (issue #214). Each is one request per call,
  // against the same quota (D6).
  final chatClient = chatClientFor(
    client: client,
    apiKeyStore: apiKeyStore,
    backendBase: backendBaseUrl(_configuredBackendUrl),
    installIdStore: installIdStore,
  );
  final llm = LlmMenuClassifier(chatClient, clock);
  // The question answerer shares the same chat client (architecture.md D6,
  // §9.5). One request per explicit user question, never automatic.
  final menuQuestionAnswerer = LlmMenuQuestionAnswerer(chatClient);
  final settingsStore = PrefsSettingsStore(load: SharedPreferences.getInstance);
  // The scan path (issue #89, D15): consent and the connectivity
  // pre-check in front of the vision engine, which sends the pages over
  // the same chat client as the text classifier. No rules fallback: a
  // photograph has no text for the rule engine. Constructing either does
  // no I/O. A website's PDF menu is read through it too (D19).
  final scannedMenuClassifier = RoutingScannedMenuClassifier(
    vision: VisionMenuClassifier(client: chatClient, clock: clock),
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

  return AppDependencies(
    menuRepository: CachedMenuRepository(
      adapters: [
        WoltMenuAdapter(
          client: client,
          proxyBase: menuProxyBase(
            runsInBrowser: kIsWeb,
            configured: _configuredBackendUrl,
          ),
        ),
        TenBisAdapter(
          client: client,
          proxyBase: menuProxyBase(
            runsInBrowser: kIsWeb,
            configured: _configuredBackendUrl,
          ),
        ),
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
          readOptions: () async =>
              ClassificationOptions.fromSettings(await settingsStore.read()),
          clock: clock,
        ),
      ],
      cache: HiveMenuCache(
        openBox: () async {
          await Hive.initFlutter();
          return await Hive.openBox<String>(_menuCacheBoxName);
        },
        openPinBox: () async {
          await Hive.initFlutter();
          return await Hive.openBox<String>(_menuCachePinsBoxName);
        },
      ),
      clock: clock,
    ),
    menuClassifier: RoutingMenuClassifier(llm, heuristic, connectivity),
    // The rule engine on its own, for "Estimate this list" (issue #42,
    // D13): the explicit action must never reach the language model.
    estimateClassifier: heuristic,
    menuQuestionAnswerer: menuQuestionAnswerer,
    settingsStore: settingsStore,
    notesStore: PrefsNotesStore(load: SharedPreferences.getInstance),
    clock: clock,
    logger: const DeveloperLogAppLogger(),
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
    // Same routing rule as the menu adapters (issue #39): through the
    // backend in a browser when one is configured, straight to Wolt
    // otherwise. The constructor sends nothing and draws no randomness.
    venueSearchService: WoltVenueSearchService(
      client: client,
      installIdStore: installIdStore,
      proxyBase: menuProxyBase(
        runsInBrowser: kIsWeb,
        configured: _configuredBackendUrl,
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
    navigatorKey: navigatorKey,
  );
}
