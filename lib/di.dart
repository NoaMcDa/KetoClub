import 'package:connectivity_plus/connectivity_plus.dart' as plus;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:ketoclub/services/classifier/classifier_router.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/classifier/llm_menu_classifier.dart';
import 'package:ketoclub/services/llm/open_router_client.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/wolt/wolt_adapter.dart';
import 'package:ketoclub/services/platform/app_logger.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/platform/connectivity.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/services/storage/key_store.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/app_dependencies.dart';
import 'package:screen_brightness/screen_brightness.dart' as plugin;
import 'package:shared_preferences/shared_preferences.dart';

/// The name of the Hive box holding cached menus and their analyses.
const String _menuCacheBoxName = 'menu_cache';

/// KetoClub's own backend, read at build time (`backend_plan.md` §4.1).
/// Empty when the app was built with no `--dart-define=KETOCLUB_BACKEND_URL=…`,
/// which is every build until issue #99 adds a Settings override — mobile
/// builds in particular never set this, since native HTTP has no CORS
/// problem to route around.
const String _configuredBackendUrl = String.fromEnvironment(
  'KETOCLUB_BACKEND_URL',
);

/// Whether [WoltMenuAdapter] should route through KetoClub's own backend
/// instead of calling Wolt directly, and at what address
/// (`backend_plan.md` §3.3, §4.1).
///
/// The proxy is used only in a browser — native HTTP has no CORS problem
/// to route around, and D1's "client-only" claim would be muddied by a
/// mobile build silently depending on a backend it does not need — and
/// only when [configured] parses as an absolute `http` or `https` URI; a
/// blank, malformed or non-http(s) value is treated the same as "not
/// configured" rather than risking a request to a nonsense address.
///
/// A pure, top-level function rather than a private helper so
/// `di_test.dart` can cover every branch without a `--dart-define` of its
/// own.
Uri? menuProxyBase({required bool runsInBrowser, required String configured}) {
  if (!runsInBrowser || configured.isEmpty) return null;
  final uri = Uri.tryParse(configured);
  if (uri == null || !uri.isAbsolute || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}

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
  const keyStore = SecureKeyStore(FlutterSecureStorage());
  final connectivity = DeviceConnectivity(plus.Connectivity());

  const heuristic = HeuristicMenuClassifier(clock: clock);
  final llm = LlmMenuClassifier(
    OpenRouterClient(client: client, keyStore: keyStore),
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
      ],
      cache: HiveMenuCache(
        openBox: () async {
          await Hive.initFlutter();
          return await Hive.openBox<String>(_menuCacheBoxName);
        },
      ),
      clock: clock,
    ),
    menuClassifier: RoutingMenuClassifier(
      llm,
      heuristic,
      keyStore,
      connectivity,
    ),
    keyStore: keyStore,
    settingsStore: PrefsSettingsStore(load: SharedPreferences.getInstance),
    clock: clock,
    logger: const DeveloperLogAppLogger(),
    screenBrightness: screenBrightness,
  );
}
