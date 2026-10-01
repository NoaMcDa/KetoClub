// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §18.4, D17; issue
// #194): on iOS and Android the app talks to Wolt and to Google's Gemini
// API itself — never through KetoClub's backend, even when a backend URL
// is compiled in.
//
// Everything from the HTTP client up is real and wired the way `di.dart`
// wires a phone build: a real `CachedMenuRepository` over a real
// `WoltMenuAdapter` whose proxy base comes from `menuProxyBase` with
// `runsInBrowser: false`, and a real `RoutingMenuClassifier` over a real
// `LlmMenuClassifier` whose chat client comes from `chatClientFor` given a
// key store. Only the network itself is scripted, by one `MockClient` that
// records every request, so the flow can assert where each one went.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/di.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/services/classifier/classifier_router.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/classifier/llm_menu_classifier.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/menu/wolt/wolt_adapter.dart';
import 'package:ketoclub/services/storage/install_id_store.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/widgets/status_badge.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// The Wolt venue page the user pastes.
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/direct-venue';

/// A backend URL, compiled in as a web build would have it. A phone must
/// ignore it for both the menu and the analysis.
const String _configuredBackend = 'http://localhost:8000';

/// The key the user saved in Settings.
const String _key = 'AIza-flow-test-key';

/// The one dish on the menu.
const String _dishName = 'Grilled Salmon';

/// A minimal consumer-assortment payload holding [_dishName].
final String _assortmentBody = jsonEncode(<String, Object?>{
  'categories': <Object?>[
    <String, Object?>{
      'id': 'c1',
      'name': 'Mains',
      'item_ids': <Object?>['item-1'],
    },
  ],
  'items': <Object?>[
    <String, Object?>{
      'id': 'item-1',
      'name': _dishName,
      'description': 'With a lemon butter sauce',
      'price': 8900,
    },
  ],
  'options': <Object?>[],
});

/// Gemini's reply placing [_dishName] as order-as-is.
final String _geminiBody = jsonEncode(<String, Object?>{
  'candidates': <Object?>[
    <String, Object?>{
      'finishReason': 'STOP',
      'content': <String, Object?>{
        'parts': <Object?>[
          <String, Object?>{
            'text': jsonEncode(<String, Object?>{
              'dishes': <Object?>[
                <String, Object?>{
                  'id': 'item-1',
                  'name': _dishName,
                  'verdict': 'orderAsIs',
                  'why': 'Fish in butter, no carb sides.',
                  'modification': null,
                  'net_carbs_estimate': 2,
                },
              ],
            }),
          },
        ],
      },
    },
  ],
  'modelVersion': 'gemini-3.5-flash',
});

/// Wires [fakes] the way `di.dart` wires a phone build, over [network]'s
/// client,
/// with [keys] as the user's key store.
void _wirePhoneBuild(
  FakeAppDependencies fakes,
  _Network network,
  FlowFakeApiKeyStore keys,
) {
  fakes
    ..apiKeyStore = keys
    ..repositoryOverride = CachedMenuRepository(
      adapters: [
        WoltMenuAdapter(
          client: network.client,
          proxyBase: menuProxyBase(
            runsInBrowser: false,
            configured: _configuredBackend,
          ),
          runsInBrowser: false,
        ),
      ],
      cache: FlowForgetfulMenuCache(),
      clock: fakes.clock,
    )
    ..classifierOverride = RoutingMenuClassifier(
      LlmMenuClassifier(
        chatClientFor(
          client: network.client,
          apiKeyStore: keys,
          backendBase: backendBaseUrl(_configuredBackend),
          installIdStore: network.installIds,
        ),
        fakes.clock,
      ),
      HeuristicMenuClassifier(clock: fakes.clock),
      fakes.connectivity,
    );
}

/// A scripted network answering Wolt's assortment and Gemini's
/// generateContent, recording every request it sees.
final class _Network {
  /// Every request, in order.
  final List<http.Request> requests = <http.Request>[];

  /// The install id store handed to `chatClientFor`; a phone never reads
  /// it, because it never talks to KetoClub's backend.
  final _CountingInstallIdStore installIds = _CountingInstallIdStore();

  /// The client the app's services are built over.
  late final http.Client client = MockClient((request) async {
    requests.add(request);
    if (request.url.host == 'consumer-api.wolt.com') {
      return http.Response(_assortmentBody, 200);
    }
    if (request.url.host == 'generativelanguage.googleapis.com') {
      return http.Response(_geminiBody, 200);
    }
    return http.Response('unexpected host', 599);
  });

  /// The host of every request, in order.
  List<String> get hosts => [for (final r in requests) r.url.host];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Direct Wolt and Gemini flow on a phone (D17)', () {
    testWidgets(
      'with a key saved, the menu comes from Wolt and the verdicts from '
      "Gemini, and KetoClub's backend is never called",
      (tester) async {
        // Setup: phone build, consent on (the D16 default) with the
        // disclosure already seen, key saved, backend compiled in.
        final fakes = FakeAppDependencies();
        await fakes.settingsStore.write(
          const AppSettings(disclosureSeen: true),
        );
        final network = _Network();
        _wirePhoneBuild(fakes, network, FlowFakeApiKeyStore(seed: _key));
        await pumpApp(tester, fakes);

        // Act: paste the Wolt link and open it.
        await enterText(tester, _woltUrl);
        await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

        // Assert: exactly two requests, straight to Wolt then to Google.
        expect(network.hosts, [
          'consumer-api.wolt.com',
          'generativelanguage.googleapis.com',
        ]);
        expect(network.hosts, isNot(contains('localhost')));
        expect(network.installIds.reads, 0);
        final gemini = network.requests.last;
        expect(gemini.headers['x-goog-api-key'], _key);
        expect(gemini.url.toString(), isNot(contains(_key)));

        // Assert: an AI result the user can see, with no rules banner.
        expect(find.text(_dishName), findsOneWidget);
        expect(find.byType(StatusBadge), findsOneWidget);
        expect(find.text(_en.engineChipAi), findsOneWidget);
        expect(find.text(_en.engineChipRules), findsNothing);
        expect(find.text(_en.analysisApiKeyMissing), findsNothing);
        expect(find.text(_en.analysisBackendUnreachable), findsNothing);
      },
    );

    testWidgets(
      'with no key saved, Gemini is never called, the rules result says to '
      'add a key, and Settings takes one',
      (tester) async {
        // Setup: phone build, consent on (the D16 default) with the
        // disclosure already seen, no key yet.
        final fakes = FakeAppDependencies();
        await fakes.settingsStore.write(
          const AppSettings(disclosureSeen: true),
        );
        final network = _Network();
        final keys = FlowFakeApiKeyStore();
        _wirePhoneBuild(fakes, network, keys);
        await pumpApp(tester, fakes);

        // Act: paste the Wolt link and open it.
        await enterText(tester, _woltUrl);
        await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

        // Assert: the menu came from Wolt; nothing went to Google.
        expect(network.hosts, ['consumer-api.wolt.com']);
        expect(find.text(_dishName), findsOneWidget);
        expect(find.text(_en.engineChipRules), findsOneWidget);
        expect(find.text(_en.analysisApiKeyMissing), findsOneWidget);

        // Act: follow the banner to Settings and save a key there.
        await tapAndSettle(tester, find.text(_en.actionOpenSettings));
        expect(find.text(_en.settingsKeySection), findsOneWidget);
        expect(find.text(_en.settingsConsentBodyDirect), findsOneWidget);
        await tester.enterText(find.byKey(apiKeyFieldKey), _key);
        // Scrolled into view first, as a user would: at the test window's
        // height the button sits under the bottom navigation bar.
        await tester.ensureVisible(find.byKey(apiKeySaveKey));
        await tester.pumpAndSettle();
        await tapAndSettle(tester, find.byKey(apiKeySaveKey));

        // Assert: the key is stored and Settings says so.
        expect(await keys.read(), _key);
        expect(find.text(_en.settingsKeyPresent), findsOneWidget);
      },
    );
  });
}

/// The install id store a phone build never reads for analysis: its only
/// reader there is the backend chat client, which `chatClientFor` does not
/// build when given a key store. Counts reads so the flow can say so.
final class _CountingInstallIdStore implements InstallIdStore {
  /// How many times [id] was called.
  int reads = 0;

  @override
  Future<String> id() async {
    reads++;
    return '0123456789abcdef0123456789abcdef';
  }
}
