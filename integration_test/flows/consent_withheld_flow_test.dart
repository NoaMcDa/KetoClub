// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §6.2, §11, §18.4;
// issues #102, #167): "consent withheld → rules with the reason". With no
// user credential left on the device, the only thing standing between a
// menu and KetoClub's server is the user's consent in Settings. Without it
// the real `RoutingMenuClassifier` must answer with the real heuristic,
// stamped `consentWithheld`, and never ask the LLM engine — so no dish
// text leaves the device.
//
// D16 (issue #167) flipped the default: consent is on for a fresh install,
// and the disclosure banner on Explore is what the user acknowledges. This
// flow seeds `estimationConsentGiven: false` explicitly on the fake store,
// so it exercises the same "no consent" path an install that already
// refused reaches — no reliance on the pre-D16 default.
//
// Like `offline_analysis_flow_test.dart`, this wires the real router over a
// real `HeuristicMenuClassifier`, a faked LLM-shaped `MenuClassifier`, and a
// faked `Connectivity`, through `FakeAppDependencies.classifierOverride`.

import 'package:flutter/material.dart';
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
/// heuristic, [llm] and [connectivity]. Seeds
/// `estimationConsentGiven: false` on the fake settings store so the
/// journey starts from an explicit refusal, independent of the D16
/// default (issue #167).
Future<FakeAppDependencies> _fakesWith(
  _FakeLlmClassifier llm,
  _CountingConnectivity connectivity,
) async {
  final fakes = FakeAppDependencies();
  fakes.repository.stub(_ref, MenuFetched(menu: _menu()));
  fakes.classifierOverride = RoutingMenuClassifier(
    llm,
    HeuristicMenuClassifier(clock: fakes.clock),
    connectivity,
  );
  await fakes.settingsStore.write(
    // D16 flipped the AppSettings default to true; seed a stored false so
    // this flow's journey starts from a refusal that predates D16, or
    // from a fresh install that dismissed the banner with "Turn off".
    const AppSettings(estimationConsentGiven: false, disclosureSeen: true),
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
  expect(find.byType(EngineChip), findsNothing);
  expect(find.text(_en.engineChipRules), findsNothing);
  expect(find.text(_dishName), findsOneWidget);
  expect(find.byType(StatusBadge), findsOneWidget);
  // The full sentence stands alone: the "Rules" chip is dropped on the
  // menu screen (issue #236).
  expect(find.byType(RulesReasonBanner), findsOneWidget);
  expect(find.text(_en.analysisConsentWithheld), findsOneWidget);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Consent withheld flow', () {
    testWidgets(
      'with a stored refusal, pasting a Wolt link shows a rules result '
      'stamped consentWithheld and never asks the LLM engine',
      (tester) async {
        // Setup: an install that has already refused consent.
        final llm = _FakeLlmClassifier();
        final connectivity = _CountingConnectivity();
        final fakes = await _fakesWith(llm, connectivity);
        await pumpApp(tester, fakes);

        // Act: paste the Wolt link and open it.
        await enterText(tester, _woltUrl);
        await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

        // Assert
        _expectConsentWithheldRulesResult(llm, connectivity);
      },
    );

    testWidgets(
      'consent unticked in Settings then re-unticked from a ticked state '
      'still ends withheld: the menu opened afterwards is a rules result '
      'stamped consentWithheld (D16, issue #167)',
      (tester) async {
        // Setup: a fresh install where consent starts on (D16), then the
        // user unticks it in Settings.
        final llm = _FakeLlmClassifier();
        final connectivity = _CountingConnectivity();
        final fakes = await _fakesWith(llm, connectivity);
        // Overwrite the seeded refusal with a fresh D16 install (consent
        // on, disclosure already seen so the banner does not block
        // Explore).
        await fakes.settingsStore.write(
          // estimationConsentGiven defaults to true (D16), so no need
          // to pass it here — this test just needs the disclosure to
          // be already seen so the banner does not sit on Explore.
          const AppSettings(disclosureSeen: true),
        );
        await pumpApp(tester, fakes);

        // Act: untick the consent checkbox in Settings.
        await tapAndSettle(tester, navDestination(_en.navSettings));
        final accept = find.text(_en.settingsConsentAccept);
        await tester.ensureVisible(accept);
        await tapAndSettle(tester, accept);

        // Sanity: the checkbox is now unticked.
        final checkbox = tester.widget<CheckboxListTile>(
          find.byType(CheckboxListTile),
        );
        expect(checkbox.value, isFalse);

        // Act: back to Explore, paste the Wolt link and open it.
        await tapAndSettle(tester, navDestination(_en.navExplore));
        await enterText(tester, _woltUrl);
        await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

        // Assert
        _expectConsentWithheldRulesResult(llm, connectivity);
      },
    );

    testWidgets(
      'a fresh install (D16, issue #167) shows the disclosure banner on '
      'Explore once, and dismissing it with OK keeps consent on so the '
      'next menu is classified through the LLM engine',
      (tester) async {
        // Setup: a fresh install — D16 default (consent on, disclosure
        // not yet seen). No seeding on the settings store: the flow
        // exercises exactly the first-launch state.
        final llm = _FakeLlmClassifier();
        final connectivity = _CountingConnectivity();
        final fakes = FakeAppDependencies();
        fakes.repository.stub(_ref, MenuFetched(menu: _menu()));
        fakes.classifierOverride = RoutingMenuClassifier(
          llm,
          HeuristicMenuClassifier(clock: fakes.clock),
          connectivity,
        );
        await pumpApp(tester, fakes);

        // Assert: the disclosure is visible.
        expect(find.text(_en.consentDisclosureOk), findsOneWidget);
        expect(find.text(_en.consentDisclosureTurnOff), findsOneWidget);

        // Act: tap OK.
        await tapAndSettle(tester, find.text(_en.consentDisclosureOk));

        // Assert: banner is gone.
        expect(find.text(_en.consentDisclosureOk), findsNothing);

        // Act: paste the Wolt link and open it.
        await enterText(tester, _woltUrl);
        await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

        // Assert: the LLM classifier WAS called (consent stayed on), so
        // this flow is not withheld.
        expect(llm.calls, hasLength(1));
        expect(llm.calls.single.venueRef, equals(_ref));
      },
    );
  });
}
