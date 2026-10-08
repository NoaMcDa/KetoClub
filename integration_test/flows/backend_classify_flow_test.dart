// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §18.4, D25; issue
// #331): a phone built with a KetoClub backend asks it first. A Discovery
// card opens a menu that arrives already classified by the server, in one
// request, so the app classifies nothing itself and uploads nothing to the
// shared menu store (the server stored it); the Recent tab then lists the
// visit. A card the quick score already read opens from the shared cache
// and is classified once, by the server's classify route.
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
import 'package:ketoclub/services/location/location_service.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/widgets/keto_score_badge.dart';
import 'package:ketoclub/widgets/rules_reason_banner.dart';
import 'package:ketoclub/widgets/status_badge.dart';
import 'package:ketoclub/widgets/venue_card.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// The one venue the backend's nearby search finds.
const Venue _venue = Venue(
  ref: VenueRef(source: MenuSource.wolt, platformId: 'ember-vine'),
  name: 'Ember & Vine',
  city: 'Tel Aviv',
);

/// The one dish on the venue's menu.
const String _dishName = 'Grilled Salmon';

/// The venue's menu, fetched at the flow clock's time so the cache counts
/// it fresh; like every Wolt menu it names no venue.
final Menu _menu = Menu(
  venueRef: _venue.ref,
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
          description: 'With a lemon butter sauce',
          price: 89,
          options: <DishOption>[],
        ),
      ],
    ),
  ],
);

/// A phone build with a backend over [network], located, with the
/// disclosure already seen and AI analysis on (the D16 default).
Future<FakeAppDependencies> _setUp(
  WidgetTester tester,
  FlowBackendNetwork network,
) async {
  final fakes = FakeAppDependencies();
  await fakes.settingsStore.write(const AppSettings(disclosureSeen: true));
  fakes.locationService.result = const LocationFound(
    latitude: 32.0809,
    longitude: 34.7806,
    accuracyMetres: 20,
  );
  wireBackendBuild(fakes, network.client);
  await pumpApp(tester, fakes);
  return fakes;
}

/// The card for [_venue].
Finder get _card => find.widgetWithText(VenueCard, _venue.name);

/// Locates, so the nearby list arrives and its quick score runs.
Future<void> _locate(WidgetTester tester) async {
  await tapAndSettle(tester, find.byTooltip(_en.discoveryUseLocation));
  await tester.ensureVisible(_card);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Backend classify flow (D25)', () {
    testWidgets(
      'a card opens a menu the backend classified in the same request: '
      'nothing is classified again or uploaded, and Recent lists the visit',
      (tester) async {
        // Setup: Wolt does not answer this device, so the quick score has
        // nothing to read and the card's menu comes from the backend.
        final network = FlowBackendNetwork(
          menu: _menu,
          venues: const <Venue>[_venue],
          woltReachable: false,
        );
        final fakes = await _setUp(tester, network);

        // Act: locate, then open the card.
        await _locate(tester);
        await tapAndSettle(tester, _card);

        // Assert: the backend searched, then served the menu with its
        // analysis — and was never asked to classify it afterwards.
        expect(network.pathsTo(flowBackendHost), <String>[
          '/v1/venues/nearby',
          '/v1/venue-menus/wolt/ember-vine',
        ]);
        final menuRequest = network.requests.lastWhere(
          (r) => r.url.path.startsWith('/v1/venue-menus/'),
        );
        expect(menuRequest.url.queryParameters['classify'], 'true');
        expect(network.pathsTo(flowGeminiHost), isEmpty);

        // Assert: an AI result the user can see, with no rules banner.
        expect(find.text(_dishName), findsOneWidget);
        expect(find.byType(StatusBadge), findsOneWidget);
        expect(find.text(_en.engineChipAi), findsOneWidget);
        // The banner renders nothing for a model result.
        expect(
          find.descendant(
            of: find.byType(RulesReasonBanner),
            matching: find.byType(Text),
          ),
          findsNothing,
        );

        // Assert: the backend stored the menu itself, so the app did not
        // upload it again.
        expect(fakes.menuStoreClient.uploads, isEmpty);

        // Act: back to Explore, then to Recent.
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tapAndSettle(tester, navDestination(_en.navSaved));

        // Assert: the visit is listed under the card's name, with its
        // dish count and the score the server's analysis earned.
        expect(find.text(_venue.name), findsOneWidget);
        expect(find.text(_en.savedEntryDishCount(1)), findsOneWidget);
        expect(find.byType(KetoScoreBadge), findsOneWidget);
      },
    );

    testWidgets(
      'a card the quick score read straight from Wolt opens from the cache '
      'and is classified once, by the backend, and then uploaded',
      (tester) async {
        // Setup: Wolt answers, so the quick score reads the menu itself.
        final network = FlowBackendNetwork(
          menu: _menu,
          venues: const <Venue>[_venue],
        );
        final fakes = await _setUp(tester, network);

        // Act: locate; the quick score scores the card on the device.
        await _locate(tester);

        // Assert: the quick score went straight to Wolt and never asked
        // the backend to classify (D13, D21).
        expect(
          find.descendant(of: _card, matching: find.byType(KetoScoreBadge)),
          findsOneWidget,
        );
        expect(network.pathsTo(flowWoltHost), hasLength(1));
        expect(network.pathsTo(flowBackendHost), <String>['/v1/venues/nearby']);

        // Act: open the card.
        await tapAndSettle(tester, _card);

        // Assert: the menu came from the cache the quick score filled;
        // the backend classified it once; Wolt and Gemini were not asked
        // again.
        expect(network.pathsTo(flowBackendHost), <String>[
          '/v1/venues/nearby',
          '/v1/classify',
        ]);
        expect(network.pathsTo(flowWoltHost), hasLength(1));
        expect(network.pathsTo(flowGeminiHost), isEmpty);
        expect(find.text(_dishName), findsOneWidget);
        expect(find.text(_en.engineChipAi), findsOneWidget);

        // Assert: the classify route stores nothing, so the device
        // contributes the menu and its model analysis itself (D24).
        await tester.pumpAndSettle();
        final upload = fakes.menuStoreClient.uploads.single;
        expect(upload.ref, _venue.ref);
        expect(upload.analysis, isNotNull);
      },
    );
  });
}
