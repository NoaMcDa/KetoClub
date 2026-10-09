// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §6.2, §10, §18.4,
// D11, D25; issue #331): the backend is an accelerator, never a
// dependency. A phone built with a KetoClub backend that cannot be reached
// reads the menu from Wolt itself and classifies it on the device: with no
// key of its own, by the rule engine, whose banner says the server — not
// the user's connection — is the problem; with a key, by Gemini directly.
//
// Everything from the HTTP client up is real and wired through `di.dart`'s
// own selectors by `wireBackendBuild`; only the network is scripted, by
// `FlowBackendNetwork`, which records every request so the flow can say
// where each one went.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/widgets/rules_reason_banner.dart';
import 'package:ketoclub/widgets/status_badge.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// The Wolt venue page the user pastes.
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/server-down-venue';

/// The one dish on the menu: a plain grilled protein, which the real rule
/// engine places order-as-is.
const String _dishName = 'Grilled Salmon';

/// The venue's menu as Wolt serves it.
final Menu _menu = Menu(
  venueRef: const VenueRef(
    source: MenuSource.wolt,
    platformId: 'server-down-venue',
  ),
  currency: 'ILS',
  fetchedAt: FlowFakeClock().now(),
  categories: const <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'Mains',
      dishes: <Dish>[
        Dish(
          id: 'item-1',
          name: _dishName,
          description: '',
          price: 89,
          options: <DishOption>[],
        ),
      ],
    ),
  ],
);

/// A phone build with an unreachable backend over [network], with the
/// disclosure already seen and AI analysis on (the D16 default), and
/// [key] saved as the user's own Gemini key when given.
Future<void> _setUp(
  WidgetTester tester,
  FlowBackendNetwork network, {
  String? key,
}) async {
  final fakes = FakeAppDependencies();
  await fakes.settingsStore.write(const AppSettings(disclosureSeen: true));
  wireBackendBuild(
    fakes,
    network.client,
    apiKeyStore: FlowFakeApiKeyStore(seed: key),
  );
  await pumpApp(tester, fakes);
}

/// Pastes [_woltUrl] and opens it.
Future<void> _open(WidgetTester tester) async {
  await enterText(tester, _woltUrl);
  await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Backend fallback flow (D11, D25)', () {
    testWidgets(
      'with the backend unreachable and no key of its own, the menu comes '
      'from Wolt and the rules banner says the server could not be reached',
      (tester) async {
        // Setup
        final network = FlowBackendNetwork(
          menu: _menu,
          backendReachable: false,
        );
        await _setUp(tester, network);

        // Act
        await _open(tester);

        // Assert: the backend was tried for the menu and for the
        // analysis; the menu came from Wolt itself; Gemini was never
        // called, as there is no key to call it with.
        expect(network.pathsTo(flowBackendHost), <String>[
          '/v1/venue-menus/wolt/server-down-venue',
          '/v1/classify',
        ]);
        expect(network.pathsTo(flowWoltHost), hasLength(1));
        expect(network.pathsTo(flowGeminiHost), isEmpty);

        // Assert: the real rule engine's verdict, stamped with the
        // server-unreachable reason — never the device-offline one.
        expect(find.text(_dishName), findsOneWidget);
        expect(find.byType(StatusBadge), findsOneWidget);
        expect(find.text(_en.engineChipAi), findsNothing);
        expect(find.byType(RulesReasonBanner), findsOneWidget);
        expect(find.text(_en.analysisBackendUnreachable), findsOneWidget);
        expect(find.text(_en.analysisOffline), findsNothing);
      },
    );

    testWidgets(
      'with the backend unreachable and a key saved, the menu comes from '
      'Wolt and the verdicts from Gemini directly',
      (tester) async {
        // Setup
        final network = FlowBackendNetwork(
          menu: _menu,
          backendReachable: false,
        );
        await _setUp(tester, network, key: 'AIza-flow-test-key');

        // Act
        await _open(tester);

        // Assert: the backend first, then Wolt and Google themselves.
        expect(network.pathsTo(flowBackendHost), <String>[
          '/v1/venue-menus/wolt/server-down-venue',
          '/v1/classify',
        ]);
        expect(network.pathsTo(flowWoltHost), hasLength(1));
        expect(network.pathsTo(flowGeminiHost), hasLength(1));

        // Assert: an AI result, with no rules banner.
        expect(find.text(_dishName), findsOneWidget);
        expect(find.text(_en.engineChipAi), findsOneWidget);
        // The banner renders nothing for a model result.
        expect(
          find.descendant(
            of: find.byType(RulesReasonBanner),
            matching: find.byType(Text),
          ),
          findsNothing,
        );
      },
    );
  });
}
