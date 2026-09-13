import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/di.dart';
import 'package:ketoclub/services/classifier/classifier_router.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/platform/app_logger.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/platform/cors_proxy_client.dart';
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

  group('menuHttpClient', () {
    late http.Client client;

    setUp(() {
      client = MockClient((_) async => http.Response('{}', 200));
    });

    test('returns the client itself when no proxy is configured', () {
      // Act
      final result = menuHttpClient(client, proxyUrl: '');

      // Assert
      expect(result, same(client));
    });

    test(
      'wraps the client in a CorsProxyClient when a proxy is configured',
      () {
        // Act
        final result = menuHttpClient(
          client,
          proxyUrl: 'http://localhost:8787/',
        );

        // Assert
        expect(result, isA<CorsProxyClient>());
        expect(
          (result as CorsProxyClient).proxiedUrl(Uri.https('a.example', '/m')),
          equals(
            Uri.parse('http://localhost:8787/?url=https%3A%2F%2Fa.example%2Fm'),
          ),
        );
      },
    );

    test('throws on a proxy value that is not an absolute URL', () {
      // Act & Assert: a mistyped define must fail loudly, never fall back
      // to the direct request whose failure the proxy exists to remove.
      expect(
        () => menuHttpClient(client, proxyUrl: 'localhost:8787'),
        throwsArgumentError,
      );
      expect(
        () => menuHttpClient(client, proxyUrl: 'not a url'),
        throwsArgumentError,
      );
    });
  });
}
