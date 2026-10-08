import 'dart:typed_data';

import 'package:flutter/widgets.dart' show GlobalKey, NavigatorState;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/di.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/classifier_router.dart';
import 'package:ketoclub/services/classifier/fallback_classifiers.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_classifier_router.dart';
import 'package:ketoclub/services/community/menu_store_client.dart';
import 'package:ketoclub/services/llm/backend_chat_client.dart';
import 'package:ketoclub/services/llm/fallback_chat_client.dart';
import 'package:ketoclub/services/llm/gemini_chat_client.dart';
import 'package:ketoclub/services/location/geolocator_location_service.dart';
import 'package:ketoclub/services/menu/backend/backend_menu_adapter.dart';
import 'package:ketoclub/services/menu/fallback_menu_adapter.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
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
import 'package:ketoclub/services/venue/backend_venue_search_service.dart';
import 'package:ketoclub/services/venue/wolt/wolt_venue_search_service.dart';
import 'package:ketoclub/state/scanned_pages_registry.dart';
import 'package:ketoclub/widgets/mobile_qr_scanner.dart';

import 'fakes/fake_api_key_store.dart';
import 'fakes/fake_install_id_store.dart';
import 'fakes/fake_menu_classifier.dart';
import 'fakes/fake_platform_menu_adapter.dart';
import 'fakes/fake_scanned_menu_classifier.dart';
import 'fakes/fake_venue_search_service.dart';

/// The backend address every "with a URL" case configures.
final Uri _base = Uri.parse('http://localhost:8000');

/// A client that records every request and answers none: each throws the
/// `ClientException` an unreachable backend produces.
final class _UnreachableNetwork {
  /// Every request, in order.
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  /// The client the services under test are built over.
  late final http.Client client = MockClient((request) async {
    requests.add(request);
    throw http.ClientException('unreachable', request.url);
  });

  /// The host and path of every request, in order.
  List<String> get targets => [
    for (final r in requests) '${r.url.host}${r.url.path}',
  ];
}

/// A one-dish menu to classify.
final Menu _menu = Menu(
  venueRef: const VenueRef(source: MenuSource.wolt, platformId: 'hamosad'),
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'Mains',
      dishes: <Dish>[
        Dish(
          id: 'd1',
          name: 'Entrecote',
          description: '',
          price: 98,
          options: <DishOption>[],
        ),
      ],
    ),
  ],
);

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
      // No backend URL: nothing goes to a backend first (issue #331), and
      // the quick score shares the menu screen's repository.
      expect(dependencies.backendConfigured, isFalse);
      expect(
        identical(
          dependencies.estimateMenuRepository,
          dependencies.menuRepository,
        ),
        isTrue,
      );
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

  group('deviceChatClientFor (architecture.md D17, D25)', () {
    test(
      'with a key store calls Gemini directly, ignoring a configured '
      'backend: the backend was already asked by the classifier in front',
      () {
        // Act
        final client = deviceChatClientFor(
          client: http.Client(),
          apiKeyStore: FakeApiKeyStore(),
          backendBase: _base,
          installIdStore: FakeInstallIdStore(),
        );

        // Assert
        expect(client, isA<GeminiChatClient>());
      },
    );

    test('with no key store goes through the backend', () {
      // Act
      final client = deviceChatClientFor(
        client: http.Client(),
        apiKeyStore: null,
        backendBase: _base,
        installIdStore: FakeInstallIdStore(),
      );

      // Assert
      expect(client, isA<BackendChatClient>());
      expect((client as BackendChatClient).baseUrl, _base);
    });

    test('with no key store and no backend is a backend client that '
        'answers notConfigured', () {
      // Act
      final client = deviceChatClientFor(
        client: http.Client(),
        apiKeyStore: null,
        backendBase: null,
        installIdStore: FakeInstallIdStore(),
      );

      // Assert
      expect((client as BackendChatClient).baseUrl, isNull);
    });
  });

  group('chatClientFor (architecture.md D17, D25)', () {
    test('a phone with a backend asks the backend first and its own key '
        'second', () async {
      // Arrange
      final network = _UnreachableNetwork();

      // Act
      final client = chatClientFor(
        client: network.client,
        apiKeyStore: FakeApiKeyStore(seed: 'AIza-test'),
        backendBase: _base,
        installIdStore: FakeInstallIdStore(),
      );
      await client.complete(systemPrompt: 's', userPrompt: 'u');

      // Assert: the backend, unreachable, then Google with the key.
      expect(client, isA<FallbackChatClient>());
      expect(network.requests.map((r) => r.url.host), <String>[
        'localhost',
        'generativelanguage.googleapis.com',
      ]);
    });

    test('a phone with no backend calls Gemini directly (D17)', () {
      // Act
      final client = chatClientFor(
        client: http.Client(),
        apiKeyStore: FakeApiKeyStore(),
        backendBase: null,
        installIdStore: FakeInstallIdStore(),
      );

      // Assert
      expect(client, isA<GeminiChatClient>());
    });

    test('a browser with a backend goes through it', () {
      // Act
      final client = chatClientFor(
        client: http.Client(),
        apiKeyStore: null,
        backendBase: _base,
        installIdStore: FakeInstallIdStore(),
      );

      // Assert
      expect((client as BackendChatClient).baseUrl, _base);
    });

    test('a browser with no backend is a backend client that answers '
        'notConfigured', () {
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

  group('llmClassifierFor (D25)', () {
    test('with no backend is the device engine itself', () {
      // Arrange
      final device = FakeMenuClassifier();

      // Act
      final classifier = llmClassifierFor(
        backendBase: null,
        client: http.Client(),
        installIdStore: FakeInstallIdStore(),
        device: device,
      );

      // Assert
      expect(identical(classifier, device), isTrue);
    });

    test('with a backend asks its classify route first, then the device '
        'engine when it cannot be reached', () async {
      // Arrange
      final network = _UnreachableNetwork();
      final device = FakeMenuClassifier();

      // Act
      final classifier = llmClassifierFor(
        backendBase: _base,
        client: network.client,
        installIdStore: FakeInstallIdStore(),
        device: device,
      );
      final result = await classifier.classify(_menu);

      // Assert
      expect(classifier, isA<FallbackMenuClassifier>());
      expect(network.targets, <String>['localhost/v1/classify']);
      expect(device.calls, hasLength(1));
      expect(result, isA<MenuAnalysed>());
    });
  });

  group('scannedClassifierFor (D15, D25)', () {
    final scan = ScannedMenu(
      pages: <ScannedPage>[
        ScannedPage(
          mimeType: ScannedPage.jpeg,
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
        ),
      ],
    );

    test('with no backend is the device engine itself', () {
      // Arrange
      final device = FakeScannedMenuClassifier();

      // Act
      final classifier = scannedClassifierFor(
        backendBase: null,
        client: http.Client(),
        installIdStore: FakeInstallIdStore(),
        device: device,
      );

      // Assert
      expect(identical(classifier, device), isTrue);
    });

    test('with a backend asks its scan route first, then the device engine '
        'when it cannot be reached', () async {
      // Arrange
      final network = _UnreachableNetwork();
      final device = FakeScannedMenuClassifier();

      // Act
      final classifier = scannedClassifierFor(
        backendBase: _base,
        client: network.client,
        installIdStore: FakeInstallIdStore(),
        device: device,
      );
      await classifier.classify(
        scan,
        options: const ClassificationOptions(estimationConsentGiven: true),
      );

      // Assert
      expect(classifier, isA<FallbackScannedMenuClassifier>());
      expect(network.targets, <String>['localhost/v1/scan']);
      expect(device.calls, hasLength(1));
    });
  });

  group('venueSearchFor (D13, D25)', () {
    test('with no backend is the direct search itself', () {
      // Arrange
      final direct = FakeVenueSearchService();

      // Act
      final service = venueSearchFor(
        backendBase: null,
        client: http.Client(),
        installIdStore: FakeInstallIdStore(),
        direct: direct,
      );

      // Assert
      expect(identical(service, direct), isTrue);
    });

    test('with a backend asks it first and the direct search second', () {
      // Arrange
      final direct = FakeVenueSearchService();

      // Act
      final service = venueSearchFor(
        backendBase: _base,
        client: http.Client(),
        installIdStore: FakeInstallIdStore(),
        direct: direct,
      );

      // Assert
      final fallback = service as FallbackVenueSearchService;
      final primary = fallback.primary as BackendVenueSearchService;
      expect(primary.baseUrl, _base);
      expect(identical(fallback.fallback, direct), isTrue);
    });
  });

  group('menuAdaptersFor (D25)', () {
    late List<PlatformMenuAdapter> direct;

    setUp(() {
      direct = <PlatformMenuAdapter>[
        FakePlatformMenuAdapter(),
        FakePlatformMenuAdapter(source: MenuSource.tenbis),
        FakePlatformMenuAdapter(source: MenuSource.website),
      ];
    });

    test('with no backend are the direct adapters themselves', () {
      // Act
      final adapters = menuAdaptersFor(
        backendBase: null,
        client: http.Client(),
        installIdStore: FakeInstallIdStore(),
        readOptions: () async => const ClassificationOptions(),
        direct: direct,
      );

      // Assert
      expect(identical(adapters, direct), isTrue);
    });

    test('with a backend put a backend adapter for the same source in '
        'front of each direct one, in order, with the long timeout', () {
      // Act
      final adapters = menuAdaptersFor(
        backendBase: _base,
        client: http.Client(),
        installIdStore: FakeInstallIdStore(),
        readOptions: () async => const ClassificationOptions(),
        direct: direct,
      );

      // Assert
      expect(adapters, hasLength(3));
      for (var i = 0; i < 3; i++) {
        final chain = adapters[i] as FallbackMenuAdapter;
        final primary = chain.primary as BackendMenuAdapter;
        expect(identical(chain.fallback, direct[i]), isTrue);
        expect(primary.source, direct[i].source);
        expect(primary.baseUrl, _base);
        expect(primary.timeout, backendMenuTimeout);
      }
      // Longer than the backend's own 110 s Gemini timeout.
      expect(backendMenuTimeout, greaterThan(const Duration(seconds: 110)));
    });

    test('the backend is asked only with the AI-analysis consent', () async {
      // Arrange
      var consent = false;
      final adapters = menuAdaptersFor(
        backendBase: _base,
        client: http.Client(),
        installIdStore: FakeInstallIdStore(),
        readOptions: () async =>
            ClassificationOptions(estimationConsentGiven: consent),
        direct: direct,
      );
      final chain = adapters.first as FallbackMenuAdapter;

      // Act & Assert
      expect(await chain.usePrimary(), isFalse);
      consent = true;
      expect(await chain.usePrimary(), isTrue);
    });

    test('without consent a fetch never reaches the backend', () async {
      // Arrange
      final network = _UnreachableNetwork();
      final wolt = FakePlatformMenuAdapter();
      final adapters = menuAdaptersFor(
        backendBase: _base,
        client: network.client,
        installIdStore: FakeInstallIdStore(),
        readOptions: () async => const ClassificationOptions(),
        direct: <PlatformMenuAdapter>[wolt],
      );

      // Act
      await adapters.single.fetch(_menu.venueRef);

      // Assert
      expect(network.requests, isEmpty);
      expect(wolt.fetchCalls, <VenueRef>[_menu.venueRef]);
    });

    test('with consent an unreachable backend falls back to the direct '
        'adapter', () async {
      // Arrange
      final network = _UnreachableNetwork();
      final wolt = FakePlatformMenuAdapter()
        ..queueFailed(MenuFetchFailureReason.notFound);
      final adapters = menuAdaptersFor(
        backendBase: _base,
        client: network.client,
        installIdStore: FakeInstallIdStore(),
        readOptions: () async =>
            const ClassificationOptions(estimationConsentGiven: true),
        direct: <PlatformMenuAdapter>[wolt],
      );

      // Act
      final result = await adapters.single.fetch(_menu.venueRef);

      // Assert: the backend was tried, then the device's own adapter.
      expect(network.targets, <String>[
        'localhost/v1/venue-menus/wolt/hamosad',
      ]);
      expect(wolt.fetchCalls, <VenueRef>[_menu.venueRef]);
      expect(result, isA<MenuFetchFailed>());
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
