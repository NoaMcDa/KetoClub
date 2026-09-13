import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/di.dart';
import 'package:ketoclub/services/classifier/classifier_router.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/platform/app_logger.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/storage/key_store.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
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
      expect(dependencies.menuClassifier, isA<RoutingMenuClassifier>());
      expect(dependencies.clock, isA<SystemClock>());
      expect(dependencies.logger, isA<DeveloperLogAppLogger>());
      expect(dependencies.keyStore, isA<SecureKeyStore>());
      expect(dependencies.settingsStore, isA<PrefsSettingsStore>());
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

  group('menuProxyBase', () {
    const configured = 'http://localhost:8000';

    test('is null off the web, however the app was configured', () {
      // Arrange: a native HTTP stack does not enforce CORS, so mobile has
      // never needed the backend and must not start depending on one.

      // Act
      final base = menuProxyBase(
        runsInBrowser: false,
        configured: configured,
      );

      // Assert
      expect(base, isNull);
    });

    test('is null in a browser with no backend configured', () {
      // Act
      final base = menuProxyBase(runsInBrowser: true, configured: '');

      // Assert
      expect(base, isNull);
    });

    test('is the configured backend in a browser', () {
      // Act
      final base = menuProxyBase(runsInBrowser: true, configured: configured);

      // Assert
      expect(base, equals(Uri.parse(configured)));
    });

    test('keeps a base that carries a path', () {
      // Act
      final base = menuProxyBase(
        runsInBrowser: true,
        configured: 'https://api.example.com/keto',
      );

      // Assert
      expect(base, equals(Uri.parse('https://api.example.com/keto')));
    });

    test('is null for a value that is not an absolute URL', () {
      // Arrange: a mistyped define degrades to the behaviour the app has
      // without one, rather than sending a malformed request.

      // Act
      final base = menuProxyBase(
        runsInBrowser: true,
        configured: 'localhost:8000',
      );

      // Assert
      expect(base, isNull);
    });

    test('is null for a scheme that is not http or https', () {
      // Act
      final base = menuProxyBase(
        runsInBrowser: true,
        configured: 'ftp://localhost:8000',
      );

      // Assert
      expect(base, isNull);
    });
  });
}
