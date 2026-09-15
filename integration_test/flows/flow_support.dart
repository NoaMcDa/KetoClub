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

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/app.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/platform/app_logger.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/storage/key_store.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/app_dependencies.dart';

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
      keyStore = FlowFakeKeyStore(),
      settingsStore = FlowFakeSettingsStore(),
      clock = FlowFakeClock(),
      logger = FlowFakeAppLogger();

  /// The faked menu repository; script it with [FlowFakeMenuRepository.stub].
  final FlowFakeMenuRepository repository;

  /// The faked classifier; script it with
  /// [FlowFakeMenuClassifier.respondWith].
  final FlowFakeMenuClassifier classifier;

  /// The faked key store.
  final FlowFakeKeyStore keyStore;

  /// The faked settings store.
  final FlowFakeSettingsStore settingsStore;

  /// The faked clock, fixed so nothing in a flow test reads wall time.
  final FlowFakeClock clock;

  /// The faked logger.
  final FlowFakeAppLogger logger;

  /// When set, [dependencies] wires this in place of [classifier].
  ///
  /// Every flow test that only needs to script "what the top-level
  /// classifier answered" uses [classifier] directly, matching the rest of
  /// this harness. A flow that must exercise real routing — the real
  /// `RoutingMenuClassifier` degrading to a real `HeuristicMenuClassifier`
  /// over a faked LLM engine and a faked `Connectivity`, rather than a
  /// classifier scripted with the finished answer — sets this instead
  /// (see `offline_analysis_flow_test.dart`).
  MenuClassifier? classifierOverride;

  /// The dependency set to hand to the app widget.
  AppDependencies get dependencies => AppDependencies(
    menuRepository: repository,
    menuClassifier: classifierOverride ?? classifier,
    keyStore: keyStore,
    settingsStore: settingsStore,
    clock: clock,
    logger: logger,
  );
}

/// A [MenuRepository] that answers from a scripted map.
final class FlowFakeMenuRepository implements MenuRepository {
  final Map<String, MenuFetchResult> _stubs = <String, MenuFetchResult>{};
  final Map<String, CachedMenu> _cached = <String, CachedMenu>{};

  /// Scripts [load] to answer [result] for [ref].
  void stub(VenueRef ref, MenuFetchResult result) {
    _stubs[ref.cacheKey] = result;
  }

  @override
  Future<MenuFetchResult> load(
    VenueRef ref, {
    bool forceRefresh = false,
  }) async {
    final stubbed = _stubs[ref.cacheKey];
    if (stubbed != null) return stubbed;
    return const MenuFetchFailed(
      reason: MenuFetchFailureReason.unsupportedSource,
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
}

/// A [MenuClassifier] that returns whatever was scripted, or an all-green
/// analysis derived from the menu it is given.
final class FlowFakeMenuClassifier implements MenuClassifier {
  MenuAnalysis? _scripted;

  /// Every menu this classifier was asked about, in order.
  final List<Menu> calls = <Menu>[];

  /// Scripts [classify] to return [analysis] for every later call, and
  /// forgets the calls recorded so far, so a test can script mid-journey and
  /// then assert on what the app asked for afterwards.
  void respondWith(MenuAnalysis analysis) {
    _scripted = analysis;
    calls.clear();
  }

  @override
  Future<MenuAnalysis> classify(
    Menu menu, {
    ClassificationOptions options = const ClassificationOptions(),
  }) async {
    calls.add(menu);
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
    );
  }
}

/// A [KeyStore] backed by a single nullable string.
final class FlowFakeKeyStore implements KeyStore {
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
