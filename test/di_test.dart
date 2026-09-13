import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/di.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/platform/app_logger.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/state/app_dependencies.dart';

void main() {
  group('buildDependencies', () {
    test('returns an AppDependencies for the production app', () {
      // Act
      final dependencies = buildDependencies();

      // Assert
      expect(dependencies, isA<AppDependencies>());
    });

    test('builds the production implementation of every service', () {
      // Act
      final dependencies = buildDependencies();

      // Assert
      expect(dependencies.menuRepository, isA<CachedMenuRepository>());
      expect(dependencies.menuClassifier, isA<HeuristicMenuClassifier>());
      expect(dependencies.clock, isA<SystemClock>());
      expect(dependencies.logger, isA<DeveloperLogAppLogger>());
    });

    test('performs no plugin I/O while building the graph', () {
      // Assert: this test runs with no plugin binding, so a constructor that
      // touched a platform channel — Hive.initFlutter, SharedPreferences,
      // secure storage — would throw MissingPluginException here. Plugin work
      // belongs in a closure invoked on first use, not in a constructor.
      // main_test.dart and the launch flow test depend on this too.
      expect(buildDependencies, returnsNormally);
    });
  });
}
