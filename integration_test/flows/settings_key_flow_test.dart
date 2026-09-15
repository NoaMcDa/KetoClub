// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §15, §18.4): the
// OpenRouter key's journey through Settings, and the one failure
// (architecture.md §6.2, §10) that must never degrade silently into a
// quiet rules fallback.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/status_badge.dart';

import 'flow_support.dart';

/// The OpenRouter key typed into Settings in the happy-path journey. Not a
/// real key; the fakes never validate its shape.
const String _typedKey = 'sk-or-v1-flow-test-not-a-real-key';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// A minimal, valid [Dish] named [name] with platform id [id].
Dish _dish(String name, {required String id}) => Dish(
  id: id,
  name: name,
  description: '',
  price: 36,
  options: const <DishOption>[],
);

/// A [Menu] for [ref] containing just [dish], under one category.
Menu _menuOf(VenueRef ref, Dish dish) => Menu(
  venueRef: ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: [
    MenuCategory(id: 'c1', name: 'Mains', dishes: [dish]),
  ],
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Settings key flow', () {
    testWidgets(
      'user saves an OpenRouter key gives consent and sees the AI engine '
      'chip on a venue',
      (tester) async {
        // Setup: a venue whose classifier is scripted to answer as the AI
        // engine would, once a key and consent exist.
        const ref = VenueRef(
          source: MenuSource.wolt,
          platformId: 'sunny-diner',
        );
        final dish = _dish('Grilled Chicken', id: 'd1');
        final fakes = FakeAppDependencies();
        fakes.repository.stub(ref, MenuFetched(menu: _menuOf(ref, dish)));
        fakes.classifier.respondWith(
          MenuAnalysed(
            dishes: [
              AnalysedDish(
                dishId: 'd1',
                name: dish.name,
                verdict: DishVerdict.orderAsIs,
                why: 'Plain grilled protein.',
              ),
            ],
            unclassified: const <String>[],
            engine: const LlmEngine(model: 'test/model'),
            analysedAt: DateTime.utc(2026),
          ),
        );
        await pumpApp(tester, fakes);

        // Act: open Settings from the bottom navigation shell — the
        // Explore screen's own app bar no longer duplicates this shortcut
        // (issue #11 added the Settings tab; issue #33 removed the icon).
        await tapAndSettle(tester, find.text(_en.navSettings));

        // Act: type a key and save it.
        await enterText(tester, _typedKey);
        await tapAndSettle(tester, find.text(_en.settingsKeySave));

        // Assert: the key is stored, and the screen confirms it.
        expect(await fakes.keyStore.read(), equals(_typedKey));
        expect(find.text(_en.settingsKeyPresent), findsOneWidget);

        // Act: give consent to send menu text for AI analysis.
        final consent = find.text(_en.settingsConsentAccept);
        await tester.ensureVisible(consent);
        await tapAndSettle(tester, consent);

        // Assert: consent is recorded.
        expect(
          (await fakes.settingsStore.read()).estimationConsentGiven,
          isTrue,
        );

        // Act: back to Explore via the tab (the Settings tab replaces the
        // route rather than pushing it, so there is nothing to pop) and
        // open the venue.
        await tapAndSettle(tester, find.text(_en.navExplore));
        await enterText(tester, ref.platformId);
        await tapAndSettle(tester, find.text(_en.venueSearchOpen));

        // Assert: the engine chip shows the AI variant, not the rules one.
        expect(find.byType(EngineChip), findsOneWidget);
        expect(find.text(_en.engineChipAi), findsOneWidget);
        expect(find.text(_en.engineChipRules), findsNothing);
      },
    );

    testWidgets(
      'a rejected key shows the unauthorised message and never silently '
      'falls back to rule-based results',
      (tester) async {
        // Setup: the router has already turned an OpenRouter 401/403 into
        // this failure (architecture.md §6.2, §10) — the one reason with
        // no rules fallback; the user must see it as-is.
        const ref = VenueRef(
          source: MenuSource.wolt,
          platformId: 'harbor-grill',
        );
        final dish = _dish('Harbor Salmon', id: 'd2');
        final fakes = FakeAppDependencies();
        fakes.repository.stub(ref, MenuFetched(menu: _menuOf(ref, dish)));
        fakes.classifier.respondWith(
          const MenuAnalysisFailed(
            reason: MenuAnalysisFailureReason.unauthorised,
          ),
        );
        await pumpApp(tester, fakes);

        // Act: open the venue directly.
        await enterText(tester, ref.platformId);
        await tapAndSettle(tester, find.text(_en.venueSearchOpen));

        // Assert: the unauthorised message is shown and the raw menu is
        // still visible — but, critically, no dish carries a verdict
        // badge. A rejected key must never be quietly papered over with a
        // weaker rules answer.
        expect(find.text(_en.analysisUnauthorised), findsOneWidget);
        expect(find.text(dish.name), findsOneWidget);
        expect(find.byType(StatusBadge), findsNothing);
        expect(find.byType(EngineChip), findsNothing);
      },
    );
  });
}
