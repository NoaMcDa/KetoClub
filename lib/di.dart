import 'package:connectivity_plus/connectivity_plus.dart' as plus;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:ketoclub/services/classifier/classifier_router.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/classifier/llm_menu_classifier.dart';
import 'package:ketoclub/services/llm/backend_chat_client.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/tenbis/tenbis_adapter.dart';
import 'package:ketoclub/services/menu/wolt/wolt_adapter.dart';
import 'package:ketoclub/services/platform/app_logger.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/platform/connectivity.dart';
import 'package:ketoclub/services/platform/external_link_opener.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/services/storage/install_id_store.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/notes_store.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/app_dependencies.dart';
import 'package:screen_brightness/screen_brightness.dart' as plugin;
import 'package:shared_preferences/shared_preferences.dart';

/// The name of the Hive box holding cached menus and their analyses.
const String _menuCacheBoxName = 'menu_cache';

/// KetoClub's own backend, read at build time (`backend_plan.md` §4.1).
/// Empty when the app was built with no `--dart-define=KETOCLUB_BACKEND_URL=…`,
/// which is every build until issue #99 adds a Settings override. The chat
/// client needs it on every platform — AI analysis goes through the backend,
/// which holds the model key — while the menu proxy uses it only in a
/// browser (see [menuProxyBase]).
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
/// `di_test.dart` covers for Wolt.
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
  // Passed only to the chat client: the install id is sent nowhere but the
  // `X-KetoClub-Install-Id` header (`backend_plan.md` §3.4).
  final installIdStore = PrefsInstallIdStore(
    load: SharedPreferences.getInstance,
  );

  const heuristic = HeuristicMenuClassifier(clock: clock);
  final llm = LlmMenuClassifier(
    BackendChatClient(
      client: client,
      baseUrl: backendBaseUrl(_configuredBackendUrl),
      installIdStore: installIdStore,
    ),
    clock,
  );
  // `screen_brightness` has no web implementation; the no-op is a
  // deliberate composition choice for that platform, not a fallback from a
  // caught failure (screen_brightness.dart's own doc comment).
  final screenBrightness = kIsWeb
      ? const NoOpScreenBrightness()
      : DeviceScreenBrightness(plugin.ScreenBrightness());

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
      ],
      cache: HiveMenuCache(
        openBox: () async {
          await Hive.initFlutter();
          return await Hive.openBox<String>(_menuCacheBoxName);
        },
      ),
      clock: clock,
    ),
    menuClassifier: RoutingMenuClassifier(llm, heuristic, connectivity),
    settingsStore: PrefsSettingsStore(load: SharedPreferences.getInstance),
    notesStore: PrefsNotesStore(load: SharedPreferences.getInstance),
    clock: clock,
    logger: const DeveloperLogAppLogger(),
    // The same instance the classifier router already pre-checks with
    // (architecture.md §14 D10) — the persistent offline banner (issue
    // #68) reads it too, rather than opening a second platform channel.
    connectivity: connectivity,
    screenBrightness: screenBrightness,
    externalLinkOpener: const UrlLauncherLinkOpener(),
    menuSharer: const SharePlusMenuSharer(),
  );
}
