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
/// directly (architecture.md §13, D11).
///
/// Two sources, and the rule between them is what makes Settings useful:
///
/// * [overridden] is what the user typed in Settings. It wins on **every**
///   platform, because the reason to type one is to point a phone at a
///   backend running on a machine across the room — a rule that only
///   applied in a browser would make that impossible.
/// * [configured] is the compile-time `KETOCLUB_BACKEND_URL`. It applies
///   only when the app [runsInBrowser], since a native HTTP stack does not
///   enforce CORS and has never needed the help.
///
/// A value that is not an absolute `http`/`https` URL yields null rather
/// than a malformed request, so a mistyped define or a half-typed setting
/// degrades to the behaviour the app has without one: a working app on
/// mobile, and an honest "open the phone app" on web.
///
/// Pure and top-level so `di_test` can cover every branch without a
/// `--dart-define`, which a unit test cannot set.
Uri? menuProxyBase({
  required bool runsInBrowser,
  required String configured,
  String? overridden,
}) {
  final chosen = switch (overridden?.trim()) {
    final String typed when typed.isNotEmpty => typed,
    _ => runsInBrowser ? configured : '',
  };
  if (chosen.isEmpty) return null;
  final parsed = Uri.tryParse(chosen);
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
  // Built once and shared: the adapter reads the backend URL from it on
  // every fetch, and it memoises the preferences instance itself.
  final settingsStore = PrefsSettingsStore(load: SharedPreferences.getInstance);

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
          // Read per fetch, not once here: buildDependencies() must stay
          // synchronous and free of plugin I/O, and a backend URL typed
          // into Settings should take effect without a restart.
          resolveProxyBase: () async => menuProxyBase(
            runsInBrowser: kIsWeb,
            configured: _backendUrl,
            overridden: (await settingsStore.read()).backendUrl,
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
    settingsStore: settingsStore,
    clock: clock,
    logger: const DeveloperLogAppLogger(),
  );
}
