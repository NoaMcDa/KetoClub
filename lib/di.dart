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
import 'package:ketoclub/services/storage/key_store.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/app_dependencies.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The name of the Hive box holding cached menus and their analyses.
const String _menuCacheBoxName = 'menu_cache';

/// The KetoClub backend, supplied at build time:
///
/// ```sh
/// flutter run -d chrome \
///   --dart-define=KETOCLUB_BACKEND_URL=http://localhost:8000
/// ```
///
/// Empty by default, which is what mobile builds use: they reach Wolt
/// directly and need no server (`backend_plan.md` §2).
const String _backendUrl = String.fromEnvironment('KETOCLUB_BACKEND_URL');

/// The backend to route Wolt menu requests through, or null to call Wolt
/// directly.
///
/// A browser will not let the app read a menu from Wolt at all, because
/// Wolt sends no CORS headers (architecture.md §13, D9); a native HTTP
/// stack does not enforce CORS and has never needed help. So the proxy is
/// used when the app [runsInBrowser] *and* a backend was [configured],
/// and not otherwise.
///
/// A [configured] value that is not an absolute `http`/`https` URL yields
/// null rather than a malformed request: a mistyped define degrades to
/// the behaviour the app has without one, which is a working app on
/// mobile and an honest "open the phone app" on web.
///
/// Pure and top-level so `di_test` can cover every branch without a
/// `--dart-define`, which a unit test cannot set.
Uri? menuProxyBase({required bool runsInBrowser, required String configured}) {
  if (!runsInBrowser || configured.isEmpty) return null;
  final parsed = Uri.tryParse(configured);
  if (parsed == null || !parsed.isAbsolute) return null;
  if (parsed.scheme != 'http' && parsed.scheme != 'https') return null;
  return parsed;
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

  const heuristic = HeuristicMenuClassifier(clock: clock);
  final llm = LlmMenuClassifier(
    OpenRouterClient(client: client, keyStore: keyStore),
    clock,
  );

  return AppDependencies(
    menuRepository: CachedMenuRepository(
      adapters: [
        WoltMenuAdapter(
          client: client,
          proxyBase: menuProxyBase(
            runsInBrowser: kIsWeb,
            configured: _backendUrl,
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
    menuClassifier: RoutingMenuClassifier(llm, heuristic, keyStore),
    keyStore: keyStore,
    settingsStore: PrefsSettingsStore(load: SharedPreferences.getInstance),
    clock: clock,
    logger: const DeveloperLogAppLogger(),
  );
}
