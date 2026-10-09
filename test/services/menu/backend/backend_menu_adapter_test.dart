import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_response_parser.dart';
import 'package:ketoclub/services/menu/backend/backend_menu_adapter.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/utils/constants.dart';

import '../../../fakes/fake_install_id_store.dart';
import '../platform_menu_adapter_contract.dart';

/// The backend every adapter under test talks to.
final Uri _base = Uri.parse('http://localhost:8000');

/// The install id the fake store answers with.
const String _installId = '0123456789abcdef0123456789abcdef';

const VenueRef _woltRef = VenueRef(
  source: MenuSource.wolt,
  platformId: 'hamosad',
);

const VenueRef _tenbisRef = VenueRef(
  source: MenuSource.tenbis,
  platformId: '12345',
);

const VenueRef _websiteRef = VenueRef(
  source: MenuSource.website,
  platformId: 'https://example.co.il/menu',
);

/// A menu for [ref] as the backend writes it.
Menu _menu(VenueRef ref) => Menu(
  venueRef: ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026, 10, 1, 12),
  venueName: 'Hamosad',
  categories: const <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'Mains',
      dishes: <Dish>[
        Dish(
          id: 'd1',
          name: 'Entrecote',
          description: 'With a green salad',
          price: 9800,
          options: <DishOption>[],
        ),
      ],
    ),
  ],
);

/// An analysis made under [options] at [schemaVersion].
MenuAnalysed _analysis({
  AnalysisOptionsSnapshot? options,
  int schemaVersion = MenuResponseParser.schemaVersion,
}) => MenuAnalysed(
  dishes: const <AnalysedDish>[
    AnalysedDish(
      dishId: 'd1',
      name: 'Entrecote',
      verdict: DishVerdict.orderAsIs,
      why: 'Meat and salad.',
    ),
  ],
  unclassified: const <String>[],
  engine: const LlmEngine(model: 'gemini-3.5-flash'),
  analysedAt: DateTime.utc(2026, 10, 1, 12, 1),
  options: options,
  schemaVersion: schemaVersion,
);

/// A 200 body carrying [menu] and [analysis] (raw JSON when given).
String _okBody(Menu menu, {Object? analysis, bool venueRoute = true}) =>
    jsonEncode(<String, Object?>{
      'menu': menu.toJson(),
      'analysis': analysis is MenuAnalysed ? analysis.toJson() : analysis,
      if (venueRoute) 'fromCache': true,
      if (venueRoute) 'fetchedAt': menu.fetchedAt.toIso8601String(),
    });

/// An error body as the backend writes it.
String _errorBody(String reason, int status) =>
    jsonEncode(<String, Object?>{'reason': reason, 'status_code': status});

BackendMenuAdapter _adapter({
  required http.Client client,
  MenuSource source = MenuSource.wolt,
  Uri? baseUrl,
  bool noBase = false,
  FakeInstallIdStore? installIdStore,
  ClassificationOptions options = const ClassificationOptions(),
  Duration timeout = const Duration(seconds: 25),
}) => BackendMenuAdapter(
  client: client,
  baseUrl: noBase ? null : (baseUrl ?? _base),
  installIdStore: installIdStore ?? FakeInstallIdStore(installId: _installId),
  source: source,
  readOptions: () async => options,
  timeout: timeout,
);

/// A client that answers every request with a valid menu for the ref the
/// request names, for the shared contract suite.
http.Client _echoClient(VenueRef ref) =>
    MockClient((request) async => http.Response(_okBody(_menu(ref)), 200));

/// A client answering [status] with [body], recording each request.
MockClient _answering(
  String body,
  int status, [
  List<http.Request>? requests,
]) => MockClient((request) async {
  requests?.add(request);
  return http.Response(body, status);
});

void main() {
  runPlatformMenuAdapterContract(
    'BackendMenuAdapter (wolt)',
    () => _adapter(client: _echoClient(_woltRef)),
    refItHandles: _woltRef,
    refItRejects: _tenbisRef,
  );

  runPlatformMenuAdapterContract(
    'BackendMenuAdapter (website)',
    () => _adapter(
      client: _echoClient(
        // The server's normalised ref differs: the adapter re-addresses.
        const VenueRef(
          source: MenuSource.website,
          platformId: 'https://example.co.il/menu/',
        ),
      ),
      source: MenuSource.website,
    ),
    refItHandles: _websiteRef,
    refItRejects: _woltRef,
  );

  group('canHandle', () {
    test('is true only for the configured source', () {
      final adapter = _adapter(
        client: _echoClient(_tenbisRef),
        source: MenuSource.tenbis,
      );
      expect(adapter.source, MenuSource.tenbis);
      expect(adapter.canHandle(_tenbisRef), isTrue);
      expect(adapter.canHandle(_woltRef), isFalse);
      expect(adapter.canHandle(_websiteRef), isFalse);
    });

    test('is false for every ref when no backend is configured', () {
      final adapter = _adapter(client: _echoClient(_woltRef), noBase: true);
      expect(adapter.canHandle(_woltRef), isFalse);
    });

    test('is false for a source the backend serves no menu for', () {
      const scanRef = VenueRef(source: MenuSource.scan, platformId: 'ab12');
      final adapter = _adapter(
        client: _echoClient(scanRef),
        source: MenuSource.scan,
      );
      expect(adapter.canHandle(scanRef), isFalse);
    });
  });

  group('fetch without I/O', () {
    test('no backend: unsupportedSource, no request, no install id', () async {
      final requests = <http.Request>[];
      final store = FakeInstallIdStore();
      final adapter = _adapter(
        client: _answering('', 200, requests),
        noBase: true,
        installIdStore: store,
      );

      final result = await adapter.fetch(_woltRef);

      expect(
        result,
        const MenuFetchFailed(reason: MenuFetchFailureReason.unsupportedSource),
      );
      expect(requests, isEmpty);
      expect(store.calls, 0);
    });

    test('a ref of another source is unsupportedSource, no request', () async {
      final requests = <http.Request>[];
      final adapter = _adapter(client: _answering('', 200, requests));

      final result = await adapter.fetch(_tenbisRef);

      expect(
        result,
        const MenuFetchFailed(reason: MenuFetchFailureReason.unsupportedSource),
      );
      expect(requests, isEmpty);
    });

    test('a website ref that is not an http(s) URL is unsupported', () async {
      final requests = <http.Request>[];
      final adapter = _adapter(
        client: _answering('', 200, requests),
        source: MenuSource.website,
      );

      final result = await adapter.fetch(
        const VenueRef(
          source: MenuSource.website,
          platformId: 'ftp://example.co.il/menu',
        ),
      );

      expect(
        result,
        const MenuFetchFailed(reason: MenuFetchFailureReason.unsupportedSource),
      );
      expect(requests, isEmpty);
    });
  });

  group('venue route request', () {
    test('GETs the venue route with classify and the default limit', () async {
      final requests = <http.Request>[];
      final adapter = _adapter(
        client: _answering(_okBody(_menu(_woltRef)), 200, requests),
      );

      await adapter.fetch(_woltRef);

      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'GET');
      expect(
        request.url.toString(),
        'http://localhost:8000/v1/venue-menus/wolt/hamosad'
        '?classify=true&netCarbLimitGrams=$defaultNetCarbLimitGrams',
      );
      expect(request.url.queryParametersAll.containsKey('constraints'), false);
    });

    test('names tenbis by its wire name', () async {
      final requests = <http.Request>[];
      final adapter = _adapter(
        client: _answering(_okBody(_menu(_tenbisRef)), 200, requests),
        source: MenuSource.tenbis,
      );

      await adapter.fetch(_tenbisRef);

      expect(requests.single.url.path, '/v1/venue-menus/tenbis/12345');
    });

    test('repeats constraints once per fragment, verbatim', () async {
      final requests = <http.Request>[];
      const options = ClassificationOptions(
        netCarbLimitGrams: 12,
        dietaryConstraints: <String>[
          seedOilFreePromptFragment,
          dairyFreePromptFragment,
        ],
      );
      final adapter = _adapter(
        client: _answering(_okBody(_menu(_woltRef)), 200, requests),
        options: options,
      );

      await adapter.fetch(_woltRef);

      final url = requests.single.url;
      expect(url.queryParameters['classify'], 'true');
      expect(url.queryParameters['netCarbLimitGrams'], '12');
      expect(url.queryParametersAll['constraints'], <String>[
        seedOilFreePromptFragment,
        dairyFreePromptFragment,
      ]);
      expect(
        'constraints='.allMatches(url.query),
        hasLength(2),
        reason: 'repeated, never comma-joined',
      );
    });

    test('percent-encodes the platform id as one path segment', () {
      final url = BackendMenuAdapter.venueMenuUri(
        Uri.parse('http://host:8000/api/'),
        const VenueRef(source: MenuSource.wolt, platformId: 'a b/c?d'),
        const ClassificationOptions(),
      );

      expect(
        url.toString(),
        startsWith('http://host:8000/api/v1/venue-menus/wolt/a%20b%2Fc%3Fd?'),
      );
      expect(url.pathSegments.last, 'a b/c?d');
    });

    test('sends the install id and never an Authorization header', () async {
      final requests = <http.Request>[];
      final adapter = _adapter(
        client: _answering(_okBody(_menu(_woltRef)), 200, requests),
      );

      await adapter.fetch(_woltRef);

      final headers = requests.single.headers;
      expect(headers[BackendMenuAdapter.installIdHeader], _installId);
      expect(
        headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('authorization')),
      );
    });

    test('reads the options anew on every fetch', () async {
      final requests = <http.Request>[];
      var limit = 6;
      final adapter = BackendMenuAdapter(
        client: _answering(_okBody(_menu(_woltRef)), 200, requests),
        baseUrl: _base,
        installIdStore: FakeInstallIdStore(),
        source: MenuSource.wolt,
        readOptions: () async =>
            ClassificationOptions(netCarbLimitGrams: limit),
      );

      await adapter.fetch(_woltRef);
      limit = 20;
      await adapter.fetch(_woltRef);

      expect(
        requests.map((r) => r.url.queryParameters['netCarbLimitGrams']),
        <String>['6', '20'],
      );
    });
  });

  group('website route request', () {
    test('POSTs the URL and the options as camelCase JSON', () async {
      final requests = <http.Request>[];
      const options = ClassificationOptions(
        netCarbLimitGrams: 10,
        dietaryConstraints: <String>[carnivoreOnlyPromptFragment],
      );
      final adapter = _adapter(
        client: _answering(
          _okBody(_menu(_websiteRef), venueRoute: false),
          200,
          requests,
        ),
        source: MenuSource.website,
        baseUrl: Uri.parse('http://localhost:8000/'),
        options: options,
      );

      await adapter.fetch(_websiteRef);

      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'http://localhost:8000/v1/website-menu');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(request.headers[BackendMenuAdapter.installIdHeader], _installId);
      expect(
        request.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(jsonDecode(request.body), <String, Object?>{
        'url': 'https://example.co.il/menu',
        'options': <String, Object?>{
          'netCarbLimitGrams': 10,
          'dietaryConstraints': <String>[carnivoreOnlyPromptFragment],
        },
      });
    });
  });

  group('a 200 answer', () {
    test('is the menu, re-addressed to the ref, not fromCache', () async {
      const serverRef = VenueRef(
        source: MenuSource.website,
        platformId: 'https://example.co.il/menu/',
      );
      final adapter = _adapter(
        client: _answering(_okBody(_menu(serverRef), venueRoute: false), 200),
        source: MenuSource.website,
      );

      final result = await adapter.fetch(_websiteRef);

      expect(result, isA<MenuFetched>());
      final fetched = result as MenuFetched;
      expect(fetched.menu.venueRef, _websiteRef);
      expect(fetched.menu.venueName, 'Hamosad');
      expect(fetched.menu.categories, _menu(serverRef).categories);
      expect(fetched.menu.fetchedAt, DateTime.utc(2026, 10, 1, 12));
      expect(fetched.fromCache, isFalse, reason: 'the server cache is fresh');
      expect(fetched.staleReason, isNull);
    });

    test('carries an analysis made under the same options', () async {
      const options = ClassificationOptions(
        netCarbLimitGrams: 8,
        dietaryConstraints: <String>[dairyFreePromptFragment],
      );
      final analysis = _analysis(options: options.snapshot);
      final adapter = _adapter(
        client: _answering(_okBody(_menu(_woltRef), analysis: analysis), 200),
        options: options,
      );

      final result = await adapter.fetch(_woltRef);

      expect((result as MenuFetched).analysis, analysis);
    });

    test('accepts an analysis with no options under the defaults', () async {
      final analysis = _analysis();
      final adapter = _adapter(
        client: _answering(_okBody(_menu(_woltRef), analysis: analysis), 200),
      );

      final result = await adapter.fetch(_woltRef);

      expect((result as MenuFetched).analysis, analysis);
    });

    test('drops an analysis made under another limit', () async {
      final adapter = _adapter(
        client: _answering(
          _okBody(
            _menu(_woltRef),
            analysis: _analysis(
              options: const AnalysisOptionsSnapshot(netCarbLimitGrams: 6),
            ),
          ),
          200,
        ),
        options: const ClassificationOptions(netCarbLimitGrams: 12),
      );

      final result = await adapter.fetch(_woltRef);

      expect((result as MenuFetched).analysis, isNull);
      expect(result.menu.venueRef, _woltRef);
    });

    test('drops an analysis made under other constraints', () async {
      final adapter = _adapter(
        client: _answering(
          _okBody(
            _menu(_woltRef),
            analysis: _analysis(
              options: const AnalysisOptionsSnapshot(netCarbLimitGrams: 6),
            ),
          ),
          200,
        ),
        options: const ClassificationOptions(
          dietaryConstraints: <String>[seedOilFreePromptFragment],
        ),
      );

      final result = await adapter.fetch(_woltRef);

      expect((result as MenuFetched).analysis, isNull);
    });

    test('drops an analysis at another schema version', () async {
      final adapter = _adapter(
        client: _answering(
          _okBody(
            _menu(_woltRef),
            analysis: _analysis(
              options: const ClassificationOptions().snapshot,
              schemaVersion: MenuResponseParser.schemaVersion + 1,
            ),
          ),
          200,
        ),
      );

      final result = await adapter.fetch(_woltRef);

      expect((result as MenuFetched).analysis, isNull);
    });

    test('drops an unreadable analysis but keeps the menu', () async {
      final adapter = _adapter(
        client: _answering(
          _okBody(
            _menu(_woltRef),
            analysis: <String, Object?>{'dishes': 'nope'},
          ),
          200,
        ),
      );

      final result = await adapter.fetch(_woltRef);

      expect(result, isA<MenuFetched>());
      expect((result as MenuFetched).analysis, isNull);
    });

    test('with a null analysis is the menu alone', () async {
      final adapter = _adapter(
        client: _answering(_okBody(_menu(_woltRef)), 200),
      );

      final result = await adapter.fetch(_woltRef);

      expect((result as MenuFetched).analysis, isNull);
    });

    test('with an unreadable menu is platformChanged', () async {
      final adapter = _adapter(
        client: _answering(
          jsonEncode(<String, Object?>{
            'menu': <String, Object?>{'venueRef': 'x'},
            'analysis': null,
          }),
          200,
        ),
      );

      expect(
        await adapter.fetch(_woltRef),
        const MenuFetchFailed(
          reason: MenuFetchFailureReason.platformChanged,
          statusCode: 200,
        ),
      );
    });

    test('that is not JSON is platformChanged', () async {
      final adapter = _adapter(client: _answering('<html>', 200));

      expect(
        await adapter.fetch(_woltRef),
        const MenuFetchFailed(
          reason: MenuFetchFailureReason.platformChanged,
          statusCode: 200,
        ),
      );
    });
  });

  group('no answer', () {
    test('a ClientException is backendUnreachable', () async {
      final adapter = _adapter(
        client: MockClient((_) async => throw http.ClientException('down')),
      );

      expect(
        await adapter.fetch(_woltRef),
        const MenuFetchFailed(
          reason: MenuFetchFailureReason.backendUnreachable,
        ),
      );
    });

    test('a timeout is backendUnreachable', () async {
      final never = Completer<http.Response>();
      final adapter = _adapter(
        client: MockClient((_) => never.future),
        timeout: const Duration(milliseconds: 10),
      );

      expect(
        await adapter.fetch(_woltRef),
        const MenuFetchFailed(
          reason: MenuFetchFailureReason.backendUnreachable,
        ),
      );
    });

    test('a website ClientException is backendUnreachable', () async {
      final adapter = _adapter(
        client: MockClient((_) async => throw http.ClientException('down')),
        source: MenuSource.website,
      );

      expect(
        await adapter.fetch(_websiteRef),
        const MenuFetchFailed(
          reason: MenuFetchFailureReason.backendUnreachable,
        ),
      );
    });
  });

  group('venue route errors', () {
    final cases = <(int, String, MenuFetchFailureReason)>[
      (404, _errorBody('notFound', 404), MenuFetchFailureReason.notFound),
      (
        502,
        _errorBody('platformChanged', 502),
        MenuFetchFailureReason.platformChanged,
      ),
      (502, _errorBody('offline', 502), MenuFetchFailureReason.offline),
      (504, _errorBody('timeout', 504), MenuFetchFailureReason.offline),
      (
        429,
        _errorBody('rateLimited', 429),
        MenuFetchFailureReason.backendUnreachable,
      ),
      (
        400,
        _errorBody('badResponse', 400),
        MenuFetchFailureReason.backendUnreachable,
      ),
      (
        422,
        jsonEncode(<String, Object?>{
          'detail': <Object?>[
            <String, Object?>{'type': 'x', 'loc': <Object?>[], 'msg': 'm'},
          ],
        }),
        MenuFetchFailureReason.backendUnreachable,
      ),
      (
        404,
        jsonEncode(<String, Object?>{'detail': 'Not Found'}),
        MenuFetchFailureReason.backendUnreachable,
      ),
      (500, 'Internal Server Error', MenuFetchFailureReason.backendUnreachable),
      (
        502,
        _errorBody('somethingNew', 502),
        MenuFetchFailureReason.backendUnreachable,
      ),
    ];
    for (final (status, body, reason) in cases) {
      test('$status $body is $reason', () async {
        final adapter = _adapter(client: _answering(body, status));

        expect(
          await adapter.fetch(_woltRef),
          MenuFetchFailed(reason: reason, statusCode: status),
        );
      });
    }
  });

  group('website route errors', () {
    final cases = <(int, String?, MenuFetchFailureReason)>[
      (429, 'rateLimited', MenuFetchFailureReason.websiteRateLimited),
      (404, 'menuNotFound', MenuFetchFailureReason.menuNotFound),
      (404, 'notFound', MenuFetchFailureReason.notFound),
      (403, 'disallowedByRobots', MenuFetchFailureReason.disallowedByRobots),
      (403, 'aiReserved', MenuFetchFailureReason.disallowedByRobots),
      (422, 'jsOnlyPage', MenuFetchFailureReason.jsOnlyPage),
      (413, 'tooLarge', MenuFetchFailureReason.websiteTooLarge),
      (415, 'unsupportedContent', MenuFetchFailureReason.menuNotFound),
      (400, 'invalidUrl', MenuFetchFailureReason.unsupportedSource),
      (502, 'offline', MenuFetchFailureReason.websiteUnreachable),
      (504, 'timeout', MenuFetchFailureReason.websiteUnreachable),
      (502, 'upstreamStatus', MenuFetchFailureReason.websiteUnreachable),
      (502, 'notConfigured', MenuFetchFailureReason.websitePdfUnread),
      (502, 'badResponse', MenuFetchFailureReason.websitePdfUnread),
      (502, 'timeout', MenuFetchFailureReason.websitePdfUnread),
      (502, 'rateLimited', MenuFetchFailureReason.websitePdfUnread),
      (422, 'noDishesFound', MenuFetchFailureReason.websitePdfUnread),
      (400, 'badResponse', MenuFetchFailureReason.backendUnreachable),
      (502, 'somethingNew', MenuFetchFailureReason.backendUnreachable),
      (404, null, MenuFetchFailureReason.backendUnreachable),
      (422, null, MenuFetchFailureReason.backendUnreachable),
      (500, null, MenuFetchFailureReason.backendUnreachable),
    ];
    for (final (status, wire, reason) in cases) {
      test('$status ${wire ?? '(no reason)'} is $reason', () async {
        final body = wire == null
            ? jsonEncode(<String, Object?>{'detail': 'Not Found'})
            : _errorBody(wire, status);
        final adapter = _adapter(
          client: _answering(body, status),
          source: MenuSource.website,
        );

        expect(
          await adapter.fetch(_websiteRef),
          MenuFetchFailed(reason: reason, statusCode: status),
        );
      });
    }

    test('a non-JSON error body is backendUnreachable', () async {
      final adapter = _adapter(
        client: _answering('Bad Gateway', 502),
        source: MenuSource.website,
      );

      expect(
        await adapter.fetch(_websiteRef),
        const MenuFetchFailed(
          reason: MenuFetchFailureReason.backendUnreachable,
          statusCode: 502,
        ),
      );
    });
  });

  group('shouldFallBack', () {
    test('is true for backendUnreachable and offline only', () {
      for (final reason in MenuFetchFailureReason.values) {
        expect(
          BackendMenuAdapter.shouldFallBack(reason),
          reason == MenuFetchFailureReason.backendUnreachable ||
              reason == MenuFetchFailureReason.offline,
          reason: reason.name,
        );
      }
    });
  });
}
