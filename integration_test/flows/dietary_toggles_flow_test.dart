// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §6.2, §9.1, §18.4;
// issue #56): a dietary rule switched on in Settings reaches the classifier
// on the next menu opened. With "Carnivore only" on, a vegetable dish the
// rules engine placed green comes back yellow. The effect spans three
// screens — the menu, Settings and the menu again — which is why this is a
// flow and not a widget test.
//
// Like `consent_withheld_flow_test.dart`, this wires the real
// `RoutingMenuClassifier` over a real `HeuristicMenuClassifier`, a faked
// LLM-shaped `MenuClassifier` and a faked `Connectivity`, through
// `FakeAppDependencies.classifierOverride`. Consent is never given, so the
// chat path is never taken and the real rules engine answers: the verdict
// on screen is the one the real carnivore rule produced, not a scripted
// one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/services/classifier/classifier_router.dart';
import 'package:ketoclub/services/classifier/heuristic_menu_classifier.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/platform/connectivity.dart';
import 'package:ketoclub/widgets/status_badge.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Wolt venue page the user pastes.
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/dietary-toggles-venue';

/// The [VenueRef] [_woltUrl] resolves to.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'dietary-toggles-venue',
);

/// The one dish on the menu: vegetables and nothing starchy, so the rules
/// engine places it green until the carnivore rule is on.
const Dish _vegetables = Dish(
  id: 'veg',
  name: 'Grilled Vegetables',
  description: 'Zucchini, eggplant and mushrooms',
  price: 38,
  options: <DishOption>[],
);

/// The menu the repository serves for [_ref].
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const [
    MenuCategory(id: 'c1', name: 'Mains', dishes: [_vegetables]),
  ],
);

/// A [MenuClassifier] standing in for the LLM engine. With consent never
/// given the router must not call it; it records calls so the test can
/// say so.
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

/// A [Connectivity] that always reports online.
final class _OnlineConnectivity implements Connectivity {
  @override
  Future<bool> isOnline() async => true;
}

/// Pastes [_woltUrl] on the Explore screen and opens the venue.
Future<void> _openVenue(WidgetTester tester) async {
  await enterText(tester, _woltUrl);
  await tapAndSettle(tester, find.text(_en.venueSearchOpen));
}

/// Goes back one screen through the app bar's back button.
Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

/// The dish card's verdict pill reading [label], as the user sees it.
Finder _badge(String label) => find.descendant(
  of: find.byType(StatusBadge),
  matching: find.text(label.toUpperCase()),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Dietary toggles flow', () {
    testWidgets(
      'turning on Carnivore only in Settings turns a green vegetable dish '
      'yellow on the next open',
      (tester) async {
        // Setup
        final llm = _FakeLlmClassifier();
        final fakes = FakeAppDependencies();
        fakes.repository.stub(_ref, MenuFetched(menu: _menu));
        fakes.classifierOverride = RoutingMenuClassifier(
          llm,
          HeuristicMenuClassifier(clock: fakes.clock),
          _OnlineConnectivity(),
        );
        await pumpApp(tester, fakes);

        // Act: open the venue with every rule off.
        await _openVenue(tester);

        // Assert: the rules engine placed the vegetables green.
        expect(find.text(_vegetables.name), findsOneWidget);
        expect(_badge(_en.verdictOrderAsIs), findsOneWidget);
        expect(_badge(_en.verdictModifiable), findsNothing);

        // Act: from the menu, open Settings and turn on Carnivore only.
        await tapAndSettle(tester, find.byIcon(Icons.settings));
        final carnivore = find.byKey(carnivoreOnlySwitchKey);
        await tester.ensureVisible(carnivore);
        await tapAndSettle(tester, carnivore);

        // Assert: the switch shows the rule on.
        expect(tester.widget<SwitchListTile>(carnivore).value, isTrue);

        // Act: back to the menu, back to Explore, and open it again.
        await _back(tester);
        await _back(tester);
        await _openVenue(tester);

        // Assert: the same dish is now yellow, and the LLM was never asked.
        expect(find.text(_vegetables.name), findsOneWidget);
        expect(_badge(_en.verdictModifiable), findsOneWidget);
        expect(_badge(_en.verdictOrderAsIs), findsNothing);
        expect(llm.calls, isEmpty);
      },
    );
  });
}
