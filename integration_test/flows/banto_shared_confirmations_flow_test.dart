// Flow test (FLOW_TEST_CONVENTIONS.md; Banto, ALG-14, issue #409): a
// peanut profile opens a menu whose backend answer carries a shared count
// ("4 people were told there are no peanuts in the nut cake"), and the
// dish card says so with the helper-tool footer, the cake still to ask
// about. The person then turns on "Share what the staff told you" in
// Settings, answers the post-meal prompt on the Recent tab, and the
// backend receives that one fact: the
// venue, the dish's fingerprint, peanuts and the polarity, and nothing
// else. The effect spans the menu, Settings, Recent and the network,
// which is why this is a flow and not a widget test.
//
// The menu is read by the real `BackendMenuAdapter` and the answer sent by
// the real `BackendConfirmationClient`, both over one scripted HTTP
// client. The whole app is pumped with `bantoMode: true`, so it runs under
// `flutter test` with no `--dart-define`.

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/app.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/dish_confirmation.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/community/confirmation_client.dart'
    show BackendConfirmationClient;
import 'package:ketoclub/services/menu/backend/backend_menu_adapter.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/confirmation_controller.dart';
import 'package:ketoclub/utils/allergens/waiter_questions.dart';
import 'package:ketoclub/widgets/confirmation_sheet.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/status_badge.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Wolt venue page the user pastes.
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/banto-shared-venue';

/// The [VenueRef] [_woltUrl] resolves to.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'banto-shared-venue',
);

/// The nut cake: אגוזים reads as peanuts suspected, so a peanut profile
/// asks about it.
const Dish _cake = Dish(
  id: 'cake',
  name: 'עוגת אגוזים',
  description: '',
  price: 30,
  options: <DishOption>[],
);

/// The menu the backend serves for [_ref].
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[
    MenuCategory(id: 'c1', name: 'קינוחים', dishes: <Dish>[_cake]),
  ],
);

/// The cake green from the language model, as a keto-only analysis is.
final MenuAnalysed _analysis = MenuAnalysed(
  dishes: const <AnalysedDish>[
    AnalysedDish(
      dishId: 'cake',
      name: 'עוגת אגוזים',
      verdict: DishVerdict.orderAsIs,
      why: 'Fits',
    ),
  ],
  unclassified: const <String>[],
  engine: const LlmEngine(model: 'flow-model'),
  analysedAt: DateTime.utc(2026),
);

/// KetoClub's backend: the venue-menu route answers [_menu] with a shared
/// count about the cake, and the confirmations route counts every post.
final class _Backend {
  /// Every request, in order.
  final List<http.Request> requests = <http.Request>[];

  /// The client the app's backend services are built over.
  late final http.Client client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    if (request.method == 'GET' && path.startsWith('/v1/venue-menus/wolt/')) {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'menu': _menu.toJson(),
            'analysis': null,
            'fromCache': false,
            'fetchedAt': _menu.fetchedAt.toIso8601String(),
            'confirmations': <Object?>[
              <String, Object?>{
                'dishFingerprint': dishFingerprint('cake'),
                'restrictionId': 'peanuts',
                'present': 0,
                'absent': 4,
                'first': '2026-09-01',
                'last': '2026-10-12',
              },
            ],
          }),
        ),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    }
    if (request.method == 'POST' && path == '/v1/confirmations') {
      return http.Response('{"counted": true}', 201);
    }
    return http.Response('{"reason": "notFound"}', 404);
  });

  /// The bodies posted to the confirmations route, decoded.
  List<Map<String, Object?>> get confirmations => <Map<String, Object?>>[
    for (final request in requests)
      if (request.url.path == '/v1/confirmations')
        jsonDecode(request.body) as Map<String, Object?>,
  ];
}

/// Scrolls the first scrollable until [finder] is built, then taps it.
Future<void> _scrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tapAndSettle(tester, finder);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Banto shared confirmations flow', () {
    testWidgets('the dish shows what others were told, and an answer is '
        'shared once the person turns sharing on', (tester) async {
      // Setup: a peanut profile, a build with a backend.
      final backend = _Backend();
      final base = Uri.parse(flowBackendUrl);
      final fakes = FakeAppDependencies()
        ..backendConfigured = true
        ..confirmationClient = BackendConfirmationClient(
          client: backend.client,
          baseUrl: base,
          installIdStore: FlowFakeInstallIdStore(),
          logger: FlowFakeAppLogger(),
        );
      fakes.repositoryOverride = CachedMenuRepository(
        adapters: <BackendMenuAdapter>[
          BackendMenuAdapter(
            client: backend.client,
            baseUrl: base,
            installIdStore: FlowFakeInstallIdStore(),
            source: MenuSource.wolt,
            readOptions: () async => ClassificationOptions.fromSettings(
              await fakes.settingsStore.read(),
            ),
            bantoMode: true,
          ),
        ],
        cache: FlowMemoryMenuCache(),
        clock: fakes.clock,
      );
      await fakes.settingsStore.write(
        AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.peanuts),
          onboardingSeen: true,
          disclosureSeen: true,
          disclosureCopyVersion: 1,
        ),
      );
      fakes.classifier.respondWith(_analysis);
      await tester.pumpWidget(
        KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
      );
      await tester.pumpAndSettle();

      // Act: open the venue from a pasted link.
      await enterText(tester, _woltUrl);
      await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

      // Assert: the shared line, with the footer, and a denial by others
      // never takes an allergen below "ask"; nothing sent yet.
      final peanuts = WaiterQuestions.subject(
        RestrictionId.peanuts,
        hebrew: false,
      );
      expect(find.text(_cake.name), findsOneWidget);
      expect(
        find.text(_en.sharedConfirmationAbsent(4, peanuts)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(StateBadge),
          matching: find.text(_en.stateAskBadge.toUpperCase()),
        ),
        findsOneWidget,
      );
      expect(find.byKey(dishSharedFooterKey), findsOneWidget);
      expect(backend.confirmations, isEmpty);

      // Act: turn sharing on in Settings.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapAndSettle(tester, navDestination(_en.navSettings));
      await _scrollAndTap(tester, find.byKey(shareConfirmationsToggleKey));

      // Assert: stored under its own key.
      expect((await fakes.settingsStore.read()).shareConfirmations, isTrue);

      // Act: answer the post-meal prompt on Recent.
      await tapAndSettle(tester, navDestination(_en.navSaved));
      await tapAndSettle(tester, find.text(_en.confirmPromptOpen));
      await tapAndSettle(
        tester,
        find.byKey(confirmAnswerKey('cake', 0, ConfirmationAnswer.present)),
      );
      await tapAndSettle(tester, find.byKey(confirmSaveKey));

      // Assert: kept on the device, and the one fact sent.
      expect(find.text(_en.confirmSaved), findsOneWidget);
      final entry = await fakes.visitHistory.read(_ref);
      expect(
        entry?.confirmations.single.polarity,
        ConfirmationPolarity.present,
      );
      expect(backend.confirmations, <Map<String, Object?>>[
        <String, Object?>{
          'venue': <String, Object?>{
            'source': 'wolt',
            'platformId': 'banto-shared-venue',
          },
          'dishFingerprint': dishFingerprint('cake'),
          'restrictionId': 'peanuts',
          'polarity': 'present',
        },
      ]);
    });
  });
}
