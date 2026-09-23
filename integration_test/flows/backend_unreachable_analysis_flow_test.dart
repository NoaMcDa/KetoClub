// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §6.2, §10, §18.4;
// issue #102): "KetoClub's server is down → rules with the reason". With a
// backend configured and consent given, the LLM engine's request to
// KetoClub's server fails before any HTTP status arrives
// (`BackendChatClient` maps that `ClientException` to `backendUnreachable`).
// The real `RoutingMenuClassifier` must fall back to the real heuristic and
// carry that reason through, so the user is told the server — not their own
// connection — is the problem.
//
// Like `offline_analysis_flow_test.dart`, this wires the real router over a
// real `HeuristicMenuClassifier`, a faked LLM-shaped `MenuClassifier`, and a
// faked `Connectivity`, through `FakeAppDependencies.classifierOverride`.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/classifier_router.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/platform/connectivity.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/rules_reason_banner.dart';
import 'package:ketoclub/widgets/status_badge.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// The Wolt venue page the user pastes, in the documented
/// `wolt.com/{lang}/{country}/{city}/restaurant/{slug}` form
/// (architecture.md §6.5 Tier A).
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/server-down-venue';

/// The [VenueRef] [_woltUrl] resolves to, and the key the fake repository
/// is stubbed under.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'server-down-venue',
);

/// A plain grilled protein — confirmed elsewhere
/// (`test/services/classifier/heuristic_menu_classifier_test.dart`) to
/// classify `orderAsIs` under the real rule vocabulary, so this flow can
/// assert a genuine verdict came out of the real heuristic.
const String _dishName = 'Grilled Salmon';

/// A [Menu] for [_ref] containing one dish named [_dishName].
Menu _menu() => Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const [
    MenuCategory(
      id: 'c1',
      name: 'Mains',
      dishes: [
        Dish(
          id: 'd1',
          name: _dishName,
          description: '',
          price: 44,
          options: <DishOption>[],
        ),
      ],
    ),
  ],
);

/// A [MenuClassifier] standing in for the LLM engine behind a backend that
/// cannot be reached: every call records the menu and fails with
/// [MenuAnalysisFailureReason.backendUnreachable], exactly as
/// `LlmMenuClassifier` reports `BackendChatClient`'s `ClientException`.
final class _UnreachableBackendLlmClassifier implements MenuClassifier {
  /// Every menu this fake was asked to classify, in call order.
  final List<Menu> calls = <Menu>[];

  @override
  Future<MenuAnalysis> classify(
    Menu menu, {
    ClassificationOptions options = const ClassificationOptions(),
  }) async {
    calls.add(menu);
    return const MenuAnalysisFailed(
      reason: MenuAnalysisFailureReason.backendUnreachable,
    );
  }
}

/// A [Connectivity] that always reports the device online: the device has
/// a route, only KetoClub's server is down.
final class _OnlineConnectivity implements Connectivity {
  @override
  Future<bool> isOnline() async => true;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Backend-unreachable analysis flow', () {
    testWidgets(
      'with consent given and the server unreachable, pasting a Wolt link '
      'shows a rules result stamped backendUnreachable, never offline',
      (tester) async {
        // Setup: consent given, device online, server unreachable.
        final fakes = FakeAppDependencies();
        fakes.repository.stub(_ref, MenuFetched(menu: _menu()));
        await fakes.settingsStore.write(
          const AppSettings(estimationConsentGiven: true),
        );
        final llm = _UnreachableBackendLlmClassifier();
        fakes.classifierOverride = RoutingMenuClassifier(
          llm,
          HeuristicMenuClassifier(clock: fakes.clock),
          _OnlineConnectivity(),
        );
        await pumpApp(tester, fakes);

        // Act: paste the Wolt link and open it.
        await enterText(tester, _woltUrl);
        await tapAndSettle(tester, find.text(_en.venueSearchOpen));

        // Assert: the LLM engine was tried once, and its failure was
        // re-stamped onto the real heuristic's result under the
        // server-unreachable reason — never the device-offline one.
        expect(llm.calls, hasLength(1));
        expect(find.byType(EngineChip), findsOneWidget);
        expect(find.text(_en.engineChipRules), findsOneWidget);
        expect(
          find.text(' (${_en.engineChipReasonBackendUnreachable})'),
          findsOneWidget,
        );
        expect(find.text(' (${_en.engineChipReasonOffline})'), findsNothing);
        expect(find.text(_dishName), findsOneWidget);
        expect(find.byType(StatusBadge), findsOneWidget);
        // The full sentence, not only the engine chip's short reason
        // (issue #119).
        expect(find.byType(RulesReasonBanner), findsOneWidget);
        expect(find.text(_en.analysisBackendUnreachable), findsOneWidget);
      },
    );
  });
}
