import 'package:flutter/widgets.dart' show GlobalKey, NavigatorState;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ketoclub/di.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/classifier_router.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_classifier_router.dart';
import 'package:ketoclub/services/community/menu_store_client.dart';
import 'package:ketoclub/services/llm/backend_chat_client.dart';
import 'package:ketoclub/services/llm/gemini_chat_client.dart';
import 'package:ketoclub/services/location/geolocator_location_service.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/website/backend_website_fetcher.dart';
import 'package:ketoclub/services/menu/website/direct_website_fetcher.dart';
import 'package:ketoclub/services/platform/app_info.dart';
import 'package:ketoclub/services/platform/app_logger.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/platform/connectivity.dart';
import 'package:ketoclub/services/platform/device_page_picker.dart';
import 'package:ketoclub/services/platform/external_link_opener.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/services/platform/qr_scanner.dart';
import 'package:ketoclub/services/platform/scan_budget.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/services/storage/api_key_store.dart';
import 'package:ketoclub/services/storage/notes_store.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';
import 'package:ketoclub/services/venue/wolt/wolt_venue_search_service.dart';
import 'package:ketoclub/state/scanned_pages_registry.dart';
import 'package:ketoclub/widgets/mobile_qr_scanner.dart';

import 'fakes/fake_api_key_store.dart';
import 'fakes/fake_install_id_store.dart';

void main() {
  group('buildDependencies', () {
    test('builds the production implementation of every service', () {
      // Act
      final dependencies = buildDependencies();

      // Assert
      expect(dependencies.menuRepository, isA<CachedMenuRepository>());
      expect(dependencies.menuClassifier, isA<RoutingMenuClassifier>());
      // "Estimate this list" gets the rule engine alone (issue #42, D13).
      expect(dependencies.estimateClassifier, isA<HeuristicMenuClassifier>());
      expect(dependencies.clock, isA<SystemClock>());
      expect(dependencies.logger, isA<DeveloperLogAppLogger>());
      expect(dependencies.settingsStore, isA<PrefsSettingsStore>());
      expect(dependencies.notesStore, isA<PrefsNotesStore>());
      // The test VM is not web, so the kIsWeb branch picks the device
      // implementation, not NoOpScreenBrightness.
      expect(dependencies.screenBrightness, isA<DeviceScreenBrightness>());
      expect(dependencies.connectivity, isA<DeviceConnectivity>());
      expect(dependencies.externalLinkOpener, isA<UrlLauncherLinkOpener>());
      expect(dependencies.appInfo, isA<DeviceAppInfo>());
      expect(dependencies.menuSharer, isA<SharePlusMenuSharer>());
      expect(dependencies.locationService, isA<GeolocatorLocationService>());
      expect(dependencies.venueSearchService, isA<WoltVenueSearchService>());
      // The test VM is not web, so the phone path: a key store for the
      // user's own Gemini key (architecture.md D17).
      expect(dependencies.apiKeyStore, isA<SecureApiKeyStore>());
      // The scan path (issue #89): consent and connectivity in front of
      // the vision engine, and the in-memory pages registry.
      expect(
        dependencies.scannedMenuClassifier,
        isA<RoutingScannedMenuClassifier>(),
      );
      expect(dependencies.scannedPages, isA<ScannedPagesRegistry>());
      // The device page picker (issue #82).
      expect(dependencies.pagePicker, isA<DevicePagePicker>());
      // The QR camera scanner, off the web (issue #182).
      expect(dependencies.qrScanner, isA<MobileQrScanner>());
      expect(dependencies.qrScanner.isAvailable, isTrue);
      // The scan budget over the real JPEG downscaler (issue #298).
      expect(dependencies.scanBudget, isA<ScanBudget>());
      // The Recent list's on-device history (issue #307).
      expect(dependencies.visitHistory, isA<HiveVisitHistoryStore>());
      // The shared menu store, on a phone too (issue #312, D24 amending
      // D17). This test is built with no KETOCLUB_BACKEND_URL, so it has
      // no address and sends nothing.
      expect(dependencies.menuStoreClient, isA<BackendMenuStoreClient>());
      final menuStore = dependencies.menuStoreClient as BackendMenuStoreClient;
      expect(menuStore.baseUrl, isNull);
      expect(menuStore.isConfigured, isFalse);
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

  group('buildDependencies scan wiring (issue #89)', () {
    test('gives each dependency graph its own empty pages registry', () {
      // Act
      final first = buildDependencies().scannedPages;
      final second = buildDependencies().scannedPages;

      // Assert: nothing is carried over, and nothing is shared.
      expect(identical(first, second), isFalse);
      expect(
        first.get(const VenueRef(source: MenuSource.scan, platformId: 'a')),
        isNull,
      );
    });
  });

  group('QR scanner wiring (issue #182)', () {
    test('a browser gets the unavailable scanner, so the action is hidden', () {
      // Act
      final scanner = qrScannerFor(
        runsInBrowser: true,
        navigatorKey: GlobalKey<NavigatorState>(),
      );

      // Assert
      expect(scanner, isA<NoQrScanner>());
      expect(scanner.isAvailable, isFalse);
    });

    test('a phone gets the camera scanner', () {
      // Act
      final scanner = qrScannerFor(
        runsInBrowser: false,
        navigatorKey: GlobalKey<NavigatorState>(),
      );

      // Assert
      expect(scanner, isA<MobileQrScanner>());
      expect(scanner.isAvailable, isTrue);
    });

    test('hands the app the navigator key the scanner shows its page on', () {
      // Arrange: a GlobalKey reads the widgets binding.
      TestWidgetsFlutterBinding.ensureInitialized();

      // Act
      final dependencies = buildDependencies();

      // Assert: a key for MaterialApp, and a scanner whose page would land
      // on that navigator; scanning with nothing mounted is a null, not a
      // throw.
      expect(dependencies.navigatorKey, isNotNull);
      expect(dependencies.qrScanner.scan(), completion(isNull));
    });
  });

  group('buildDependencies venue search wiring (issue #39)', () {
    test('routes venue search straight to Wolt outside a browser', () {
      // Act: the test VM is not web, so menuProxyBase answers null.
      final service =
          buildDependencies().venueSearchService as WoltVenueSearchService;

      // Assert
      expect(service.proxyBase, isNull);
      expect(service.runsInBrowser, isFalse);
    });
  });

  group('websiteFetcherFor (architecture.md D19)', () {
    test('goes through the backend when a proxy base is set', () {
      // Act
      final fetcher = websiteFetcherFor(
        client: http.Client(),
        proxyBase: Uri.parse('http://localhost:8000'),
        installIdStore: FakeInstallIdStore(),
      );

      // Assert
      expect(fetcher, isA<BackendWebsiteFetcher>());
      expect(
        (fetcher as BackendWebsiteFetcher).proxyBase,
        Uri.parse('http://localhost:8000'),
      );
    });

    test('fetches the site directly with no proxy base', () {
      // Act
      final fetcher = websiteFetcherFor(
        client: http.Client(),
        proxyBase: null,
        installIdStore: FakeInstallIdStore(),
      );

      // Assert: the test VM is not a browser, so it names itself.
      expect(fetcher, isA<DirectWebsiteFetcher>());
      expect((fetcher as DirectWebsiteFetcher).runsInBrowser, isFalse);
    });
  });

  group('apiKeyStoreFor (architecture.md D17)', () {
    test('returns a secure store outside a browser', () {
      // Act
      final store = apiKeyStoreFor(runsInBrowser: false);

      // Assert
      expect(store, isA<SecureApiKeyStore>());
    });

    test('returns null in a browser: the backend holds the key', () {
      // Act
      final store = apiKeyStoreFor(runsInBrowser: true);

      // Assert
      expect(store, isNull);
    });
  });

  group('chatClientFor (architecture.md D17)', () {
    test('with a key store calls Gemini directly, ignoring a configured '
        'backend', () {
      // Act
      final client = chatClientFor(
        client: http.Client(),
        apiKeyStore: FakeApiKeyStore(),
        backendBase: Uri.parse('http://localhost:8000'),
        installIdStore: FakeInstallIdStore(),
      );

      // Assert
      expect(client, isA<GeminiChatClient>());
    });

    test('with no key store goes through the backend', () {
      // Arrange
      final base = Uri.parse('http://localhost:8000');

      // Act
      final client = chatClientFor(
        client: http.Client(),
        apiKeyStore: null,
        backendBase: base,
        installIdStore: FakeInstallIdStore(),
      );

      // Assert
      expect(client, isA<BackendChatClient>());
      expect((client as BackendChatClient).baseUrl, base);
    });

    test('with no key store and no backend is a backend client that '
        'answers notConfigured', () {
      // Act
      final client = chatClientFor(
        client: http.Client(),
        apiKeyStore: null,
        backendBase: null,
        installIdStore: FakeInstallIdStore(),
      );

      // Assert
      expect((client as BackendChatClient).baseUrl, isNull);
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
  });
}
