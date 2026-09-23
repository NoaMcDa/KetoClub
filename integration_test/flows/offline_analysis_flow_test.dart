// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §6.2, §14 D10,
// §18.4; issue #35): "go offline → rules result with the reason" — the one
// required acceptance flow that did not exist yet.
//
// Every other flow test in this directory scripts the top-level
// `MenuClassifier` directly with the finished answer (see
// `FlowFakeMenuClassifier` in `flow_support.dart`), which is the right
// level for those journeys but never exercises `RoutingMenuClassifier`
// itself. This file wires the *real* `RoutingMenuClassifier` over a real
// `HeuristicMenuClassifier`, a faked LLM-shaped `MenuClassifier`, and a
// faked `Connectivity`, through `FakeAppDependencies.classifierOverride` —
// so the degradation the acceptance criterion names actually runs, not
// just the UI state it ends in.
//
// D10's pre-check means "offline" can be produced by two different code
// paths that must look identical to the user (`classifier_router.dart`'s
// own doc comment says so): the device-level check skipping the LLM call
// entirely, and a real call that is attempted and fails. Both are covered
// below, since they are different code.

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
import 'package:ketoclub/widgets/status_badge.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// A plain grilled protein — confirmed elsewhere
/// (`test/services/classifier/heuristic_menu_classifier_test.dart`) to
/// classify `orderAsIs` under the real rule vocabulary, so this flow can
/// assert a genuine green verdict came out of the real heuristic, not a
/// scripted one.
const String _dishName = 'Grilled Salmon';

/// A [Menu] for [ref] containing one dish named [_dishName].
Menu _menuOf(VenueRef ref) => Menu(
  venueRef: ref,
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

/// A [MenuClassifier] standing in for the LLM engine: records every call
/// and answers with whatever [scriptedFailure] is set to, or an
/// unreachable [MenuAnalysed] if a test forgets to script it — a flow
/// that reaches that branch has a bug in its own setup, not in the app.
final class _FakeLlmClassifier implements MenuClassifier {
  /// Every menu this fake was asked to classify, in call order.
  final List<Menu> calls = <Menu>[];

  /// What [classify] returns; set before pumping the app.
  MenuAnalysisFailed? scriptedFailure;

  @override
  Future<MenuAnalysis> classify(
    Menu menu, {
    ClassificationOptions options = const ClassificationOptions(),
  }) async {
    calls.add(menu);
    final failure = scriptedFailure;
    if (failure != null) return failure;
    return MenuAnalysed(
      dishes: const <AnalysedDish>[],
      unclassified: const <String>[],
      engine: const LlmEngine(model: 'unscripted/should-not-be-called'),
      analysedAt: DateTime.utc(2026),
    );
  }
}

/// A [Connectivity] that always answers [online], however many times it
/// is asked.
final class _FixedConnectivity implements Connectivity {
  /// Creates a connectivity check fixed at [online].
  new({required this.online});

  /// The answer every call to [isOnline] returns.
  final bool online;

  /// How many times [isOnline] was asked.
  int callCount = 0;

  @override
  Future<bool> isOnline() async {
    callCount++;
    return online;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Offline analysis flow', () {
    testWidgets(
      'the connectivity pre-check skips the LLM call entirely and shows a '
      'rules result stamped offline (architecture.md §14 D10)',
      (tester) async {
        // Setup: a device that plainly has no route — the router must
        // never even try the LLM engine.
        const ref = VenueRef(source: MenuSource.wolt, platformId: 'no-route');
        final fakes = FakeAppDependencies();
        fakes.repository.stub(ref, MenuFetched(menu: _menuOf(ref)));
        // Consent must be given before the router ever consults
        // connectivity: rule 1 in `classifier_router.dart` routes "no
        // consent" straight to the heuristic under `consentWithheld`.
        await fakes.settingsStore.write(
          const AppSettings(estimationConsentGiven: true),
        );
        final llm = _FakeLlmClassifier();
        final connectivity = _FixedConnectivity(online: false);
        fakes.classifierOverride = RoutingMenuClassifier(
          llm,
          HeuristicMenuClassifier(clock: fakes.clock),
          connectivity,
        );
        await pumpApp(tester, fakes);

        // Act: open the venue directly.
        await enterText(tester, ref.platformId);
        await tapAndSettle(tester, find.text(_en.venueSearchOpen));

        // Assert: connectivity was consulted, the LLM engine was never
        // called, and the real heuristic's genuine green verdict is on
        // screen under the rules engine stamped "offline".
        expect(connectivity.callCount, greaterThan(0));
        expect(llm.calls, isEmpty);
        expect(find.byType(EngineChip), findsOneWidget);
        expect(find.text(_en.engineChipRules), findsOneWidget);
        expect(find.text(' (${_en.engineChipReasonOffline})'), findsOneWidget);
        expect(find.text(_dishName), findsOneWidget);
        expect(find.byType(StatusBadge), findsOneWidget);
      },
    );

    testWidgets(
      'a connectivity reading of "online" that turns out wrong still ends '
      'in the same rules-result-stamped-offline state once the LLM call '
      'itself fails',
      (tester) async {
        // Setup: connectivity says the device is online — a hint that
        // turns out to be wrong, as architecture.md §14 D10 says it can —
        // so the router does attempt the LLM call, and that call is the
        // one that reports offline.
        const ref = VenueRef(
          source: MenuSource.wolt,
          platformId: 'flaky-route',
        );
        final fakes = FakeAppDependencies();
        fakes.repository.stub(ref, MenuFetched(menu: _menuOf(ref)));
        // Consent must be given before the router ever consults
        // connectivity: rule 1 in `classifier_router.dart` routes "no
        // consent" straight to the heuristic under `consentWithheld`.
        await fakes.settingsStore.write(
          const AppSettings(estimationConsentGiven: true),
        );
        final llm = _FakeLlmClassifier()
          ..scriptedFailure = const MenuAnalysisFailed(
            reason: MenuAnalysisFailureReason.offline,
          );
        final connectivity = _FixedConnectivity(online: true);
        fakes.classifierOverride = RoutingMenuClassifier(
          llm,
          HeuristicMenuClassifier(clock: fakes.clock),
          connectivity,
        );
        await pumpApp(tester, fakes);

        // Act: open the venue directly.
        await enterText(tester, ref.platformId);
        await tapAndSettle(tester, find.text(_en.venueSearchOpen));

        // Assert: the LLM engine was actually attempted this time, once,
        // and its failure was re-stamped onto the same heuristic result
        // and the same "offline" reason as the pre-check path above — the
        // UI's copy cannot tell the two paths apart, by design.
        expect(llm.calls, hasLength(1));
        expect(find.byType(EngineChip), findsOneWidget);
        expect(find.text(_en.engineChipRules), findsOneWidget);
        expect(find.text(' (${_en.engineChipReasonOffline})'), findsOneWidget);
        expect(find.text(_dishName), findsOneWidget);
        expect(find.byType(StatusBadge), findsOneWidget);
      },
    );
  });
}
