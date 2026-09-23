import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/di.dart';
import 'package:ketoclub/services/classifier/classifier_router.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/platform/app_logger.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/platform/external_link_opener.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/services/storage/notes_store.dart';
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
      expect(dependencies.settingsStore, isA<PrefsSettingsStore>());
      expect(dependencies.notesStore, isA<PrefsNotesStore>());
      // The test VM is not web, so the kIsWeb branch picks the device
      // implementation, not NoOpScreenBrightness.
      expect(dependencies.screenBrightness, isA<DeviceScreenBrightness>());
      expect(dependencies.externalLinkOpener, isA<UrlLauncherLinkOpener>());
      expect(dependencies.menuSharer, isA<SharePlusMenuSharer>());
    });

    test('performs no plugin I/O while building the graph', () {
      // Assert: this test runs with no plugin binding, so a constructor that
      // touched a platform channel — Hive.initFlutter, SharedPreferences,
      // connectivity — would throw MissingPluginException here. Plugin work
      // belongs in a closure invoked on first use, not in a constructor.
      // main_test.dart and the launch flow test depend on this too.
      expect(buildDependencies, returnsNormally);
    });
  });

  group('backendBaseUrl', () {
    test('returns the parsed base for an http url', () {
      // Act
      final base = backendBaseUrl('http://localhost:8000');

      // Assert
      expect(base, equals(Uri.parse('http://localhost:8000')));
    });

    test('returns the parsed base for an https url with a path', () {
      // Act
      final base = backendBaseUrl('https://api.example.test/ketoclub/');

      // Assert
      expect(base, equals(Uri.parse('https://api.example.test/ketoclub/')));
    });

    test('returns null for an empty value', () {
      // Act
      final base = backendBaseUrl('');

      // Assert
      expect(base, isNull);
    });

    test('returns null for a malformed or relative value', () {
      // Act & Assert
      expect(backendBaseUrl('not a url'), isNull);
      expect(backendBaseUrl('localhost:8000'), isNull);
      expect(backendBaseUrl('/relative/path'), isNull);
      expect(backendBaseUrl('http://'), isNull);
    });

    test('returns null for a non-http(s) scheme', () {
      // Act
      final base = backendBaseUrl('ftp://localhost:8000');

      // Assert
      expect(base, isNull);
    });
  });

  group('menuProxyBase', () {
    test('returns the parsed base in a browser with a configured url', () {
      // Act
      final base = menuProxyBase(
        runsInBrowser: true,
        configured: 'http://localhost:8000',
      );

      // Assert
      expect(base, equals(Uri.parse('http://localhost:8000')));
    });

    test('returns null in a browser with no configured url', () {
      // Act
      final base = menuProxyBase(runsInBrowser: true, configured: '');

      // Assert
      expect(base, isNull);
    });

    test('returns null outside a browser even with a configured url', () {
      // Act: native HTTP has no CORS problem to route around, so a
      // mobile build never uses the proxy even if one is configured.
      final base = menuProxyBase(
        runsInBrowser: false,
        configured: 'http://localhost:8000',
      );

      // Assert
      expect(base, isNull);
    });

    test('returns null outside a browser with no configured url', () {
      // Act
      final base = menuProxyBase(runsInBrowser: false, configured: '');

      // Assert
      expect(base, isNull);
    });

    test('returns null for a malformed configured url', () {
      // Act & Assert: neither a relative path nor a schemeless host:port
      // is an address a request can be sent to.
      expect(
        menuProxyBase(runsInBrowser: true, configured: 'not a url'),
        isNull,
      );
      expect(
        menuProxyBase(runsInBrowser: true, configured: 'localhost:8000'),
        isNull,
      );
      expect(
        menuProxyBase(runsInBrowser: true, configured: '/relative/path'),
        isNull,
      );
    });

    test('returns null for a non-http(s) scheme', () {
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
