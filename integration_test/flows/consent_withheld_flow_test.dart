// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §6.2, §11, §18.4;
// issue #102): "consent withheld → rules with the reason". With no user
// credential left on the device, the only thing standing between a menu and
// KetoClub's server is the user's consent in Settings. Without it the real
// `RoutingMenuClassifier` must answer with the real heuristic, stamped
// `consentWithheld`, and never ask the LLM engine — so no dish text leaves
// the device.
//
// Like `offline_analysis_flow_test.dart`, this wires the real router over a
// real `HeuristicMenuClassifier`, a faked LLM-shaped `MenuClassifier`, and a
// faked `Connectivity`, through `FakeAppDependencies.classifierOverride`.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/classifier_router.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/platform/connectivity.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/status_badge.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// The Wolt venue page the user pastes, in the documented
/// `wolt.com/{lang}/{country}/{city}/restaurant/{slug}` form
/// (architecture.md §6.5 Tier A).
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/consent-withheld-venue';

/// The [VenueRef] [_woltUrl] resolves to, and the key the fake repository
/// is stubbed under.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'consent-withheld-venue',
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

/// A [MenuClassifier] standing in for the LLM engine. It records every
/// call; this flow asserts it is never called at all.
final class _FakeLlmClassifier implements MenuClassifier {
  /// Every menu this fake was asked to classify, in call order.
  final List<Menu> calls = <Menu>[];

  @override
  Future<MenuAnalysis> classify(
    Menu menu, {
    ClassificationOptions options = const ClassificationOptions(),
  }) async {
    calls.add(menu);
    return MenuAnalysed(
      dishes: const <AnalysedDish>[],
      unclassified: const <String>[],
      engine: const LlmEngine(model: 'unscripted/should-not-be-called'),
      analysedAt: DateTime.utc(2026),
    );
  }
}

/// A [Connectivity] that reports online and counts how often it is asked.
final class _CountingConnectivity implements Connectivity {
  /// How many times [isOnline] was asked.
  int callCount = 0;

  @override
  Future<bool> isOnline() async {
    callCount++;
    return true;
  }
}

/// Builds the fakes for one journey, wiring the real router over the real
/// heuristic, [llm] and [connectivity].
FakeAppDependencies _fakesWith(
  _FakeLlmClassifier llm,
  _CountingConnectivity connectivity,
) {
  final fakes = FakeAppDependencies();
  fakes.repository.stub(_ref, MenuFetched(menu: _menu()));
  fakes.classifierOverride = RoutingMenuClassifier(
    llm,
    HeuristicMenuClassifier(clock: fakes.clock),
    connectivity,
  );
  return fakes;
}

/// Asserts the menu is on screen as a rules result stamped
/// `consentWithheld`, and that nothing was sent anywhere.
void _expectConsentWithheldRulesResult(
  _FakeLlmClassifier llm,
  _CountingConnectivity connectivity,
) {
  expect(llm.calls, isEmpty);
  expect(connectivity.callCount, equals(0));
  expect(find.byType(EngineChip), findsOneWidget);
  expect(find.text(_en.engineChipRules), findsOneWidget);
  expect(
    find.text(' (${_en.engineChipReasonConsentWithheld})'),
    findsOneWidget,
  );
  expect(find.text(_dishName), findsOneWidget);
  expect(find.byType(StatusBadge), findsOneWidget);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Consent withheld flow', () {
    testWidgets(
      'with consent never given, pasting a Wolt link shows a rules result '
      'stamped consentWithheld and never asks the LLM engine',
      (tester) async {
        // Setup: a fresh install — consent has never been given.
        final llm = _FakeLlmClassifier();
        final connectivity = _CountingConnectivity();
        final fakes = _fakesWith(llm, connectivity);
        await pumpApp(tester, fakes);

        // Act: paste the Wolt link and open it.
        await enterText(tester, _woltUrl);
        await tapAndSettle(tester, find.text(_en.venueSearchOpen));

        // Assert
        _expectConsentWithheldRulesResult(llm, connectivity);
      },
    );

    testWidgets(
      'consent ticked and then unticked in Settings still withholds it: the '
      'menu opened afterwards is a rules result stamped consentWithheld',
      (tester) async {
        // Setup
        final llm = _FakeLlmClassifier();
        final connectivity = _CountingConnectivity();
        final fakes = _fakesWith(llm, connectivity);
        await pumpApp(tester, fakes);

        // Act: tick the consent checkbox, then untick it again.
        await tapAndSettle(tester, navDestination(_en.navSettings));
        final accept = find.text(_en.settingsConsentAccept);
        await tester.ensureVisible(accept);
        await tapAndSettle(tester, accept);
        await tapAndSettle(tester, accept);

        // Act: back to Explore, paste the Wolt link and open it.
        await tapAndSettle(tester, navDestination(_en.navExplore));
        await enterText(tester, _woltUrl);
        await tapAndSettle(tester, find.text(_en.venueSearchOpen));

        // Assert
        _expectConsentWithheldRulesResult(llm, connectivity);
      },
    );
  });
}
