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
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/platform/app_logger.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/notes_store.dart';
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
      settingsStore = FlowFakeSettingsStore(),
      notesStore = FlowFakeNotesStore(),
      clock = FlowFakeClock(),
      logger = FlowFakeAppLogger();

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

  /// The dependency set to hand to the app widget.
  AppDependencies get dependencies => AppDependencies(
    menuRepository: repository,
    menuClassifier: classifierOverride ?? classifier,
    settingsStore: settingsStore,
    notesStore: notesStore,
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
    // has to call `saveAnalysis` first just to seed the list.
    if (stubbed case MenuFetched(menu: final fetched)) {
      _cached[ref.cacheKey] = CachedMenu(menu: fetched);
    }
    return stubbed;
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
