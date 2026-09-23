import 'package:ketoclub/state/app_dependencies.dart';

import 'fake_app_logger.dart';
import 'fake_clock.dart';
import 'fake_connectivity.dart';
import 'fake_menu_classifier.dart';
import 'fake_menu_repository.dart';
import 'fake_notes_store.dart';
import 'fake_settings_store.dart';

/// Builds an [AppDependencies] of fakes, for widget and flow tests.
///
/// Every field is exposed so a test can steer or assert on it. This is the
/// seam architecture.md §18.1 describes: a test gets the real app on top of
/// faked I/O, without a mocking library and without a service locator.
final class FakeAppDependencies {
  /// Creates a dependency set whose services are all in-memory fakes, with
  /// the clock fixed at [startedAt].
  new({DateTime? startedAt})
    : repository = FakeMenuRepository(),
      classifier = FakeMenuClassifier(),
      settingsStore = FakeSettingsStore(),
      notesStore = FakeNotesStore(),
      clock = FakeClock(startedAt ?? DateTime.utc(2026)),
      logger = FakeAppLogger(),
      connectivity = FakeConnectivity();

  /// The faked menu repository.
  final FakeMenuRepository repository;

  /// The faked classifier.
  final FakeMenuClassifier classifier;

  /// The faked settings store.
  final FakeSettingsStore settingsStore;

  /// The faked notes store.
  final FakeNotesStore notesStore;

  /// The faked clock; advance it to control cache freshness.
  final FakeClock clock;

  /// The faked logger; inspect its records.
  final FakeAppLogger logger;

  /// The faked connectivity check; flip [FakeConnectivity.online] to
  /// drive the persistent offline banner (issue #68).
  final FakeConnectivity connectivity;

  /// The dependency set to hand to the app widget.
  AppDependencies get dependencies => AppDependencies(
    menuRepository: repository,
    menuClassifier: classifier,
    settingsStore: settingsStore,
    notesStore: notesStore,
    clock: clock,
    logger: logger,
    connectivity: connectivity,
  );
}
