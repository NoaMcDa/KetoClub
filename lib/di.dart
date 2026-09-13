import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/wolt/wolt_adapter.dart';
import 'package:ketoclub/services/platform/app_logger.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/state/app_dependencies.dart';

/// The name of the Hive box holding cached menus and their analyses.
const String _menuCacheBoxName = 'menu_cache';

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
/// see the Hive opener below. Keeping this synchronous is what lets
/// `di_test.dart`, `main_test.dart` and the launch flow test all call it.
AppDependencies buildDependencies() {
  final client = http.Client();
  const clock = SystemClock();

  return AppDependencies(
    menuRepository: CachedMenuRepository(
      adapters: [WoltMenuAdapter(client: client)],
      cache: HiveMenuCache(
        openBox: () async {
          await Hive.initFlutter();
          return await Hive.openBox<String>(_menuCacheBoxName);
        },
      ),
      clock: clock,
    ),
    menuClassifier: const HeuristicMenuClassifier(clock: clock),
    clock: clock,
    logger: const DeveloperLogAppLogger(),
  );
}
