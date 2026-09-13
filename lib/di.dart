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
import 'package:ketoclub/services/platform/cors_proxy_client.dart';
import 'package:ketoclub/services/storage/key_store.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/app_dependencies.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The name of the Hive box holding cached menus and their analyses.
const String _menuCacheBoxName = 'menu_cache';

/// The CORS-forwarding proxy that restaurant-platform requests go through,
/// from `--dart-define=KETOCLUB_MENU_PROXY_URL=...` (architecture.md §13).
///
/// Empty, the default, means requests go straight to the platform. That
/// works natively and is refused in a browser, which is why
/// `tool/run_web.sh` sets this to the local proxy `tool/cors_proxy.dart`
/// serves. A deployed web build needs the same thing from a hosted proxy.
/// The OpenRouter client never goes through it: OpenRouter permits
/// browser-origin calls.
const String menuProxyUrl = String.fromEnvironment('KETOCLUB_MENU_PROXY_URL');

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
  final menuClient = menuHttpClient(client, proxyUrl: menuProxyUrl);
  const clock = SystemClock();
  const keyStore = SecureKeyStore(FlutterSecureStorage());

  const heuristic = HeuristicMenuClassifier(clock: clock);
  final llm = LlmMenuClassifier(
    OpenRouterClient(client: client, keyStore: keyStore),
    clock,
  );

  return AppDependencies(
    menuRepository: CachedMenuRepository(
      adapters: [
        WoltMenuAdapter(
          client: menuClient,
          // Behind a proxy a browser reaches Wolt like a native client
          // does, so only a bare web build is blocked (architecture.md §13).
          directFromBrowser: kIsWeb && menuProxyUrl.isEmpty,
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
    menuClassifier: RoutingMenuClassifier(llm, heuristic, keyStore),
    keyStore: keyStore,
    settingsStore: PrefsSettingsStore(load: SharedPreferences.getInstance),
    clock: clock,
    logger: const DeveloperLogAppLogger(),
  );
}

/// The client the restaurant-platform adapters send through: [client]
/// itself when [proxyUrl] is empty, otherwise a [CorsProxyClient] over it
/// (architecture.md §13).
///
/// A non-empty [proxyUrl] that is not an absolute URL throws, since the
/// value comes from a build-time define and a silently ignored typo would
/// present as the very CORS failure the proxy exists to remove.
http.Client menuHttpClient(http.Client client, {required String proxyUrl}) {
  if (proxyUrl.isEmpty) return client;
  final proxy = Uri.tryParse(proxyUrl);
  if (proxy == null || !proxy.hasScheme || proxy.host.isEmpty) {
    throw ArgumentError.value(
      proxyUrl,
      'proxyUrl',
      'KETOCLUB_MENU_PROXY_URL must be an absolute URL such as '
          'http://127.0.0.1:8787/',
    );
  }
  return CorsProxyClient(inner: client, proxy: proxy);
}
