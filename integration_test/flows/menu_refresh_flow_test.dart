// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §6.4, §15, §18.4,
// issue #49): pulling the classified menu screen down refetches its venue
// and, when the refetched menu actually differs, shows the new dish.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/widgets/dish_card.dart';

import 'flow_support.dart';

/// The Wolt venue page the user pastes, matching `menu_display_flow_test.dart`.
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/vitrina-lilinblum';

/// The [VenueRef] [_woltUrl] resolves to, and the key the fakes below are
/// stubbed under.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'vitrina-lilinblum',
);

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// The dish on the venue's first menu.
const Dish _firstDish = Dish(
  id: 'd1',
  name: 'Herb Butter Steak',
  description: '',
  price: 42,
  options: <DishOption>[],
);

/// The dish that appears only on the venue's refetched menu — a second
/// category entirely, so the refetched menu's dish-text fingerprint
/// (architecture.md §6.4) cannot match the first menu's.
const Dish _secondDish = Dish(
  id: 'd2',
  name: 'Cauliflower Risotto',
  description: '',
  price: 36,
  options: <DishOption>[],
);

Menu _menuWith(Dish dish) => Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: [
    MenuCategory(id: 'c1', name: 'Mains', dishes: [dish]),
  ],
);

MenuAnalysed _analysisFor(Dish dish) => MenuAnalysed(
  dishes: [
    AnalysedDish(
      dishId: dish.id,
      name: dish.name,
      verdict: DishVerdict.orderAsIs,
      why: 'Protein-forward, no starch.',
    ),
  ],
  unclassified: const <String>[],
  engine: const RulesEngine(reason: MenuAnalysisFailureReason.notConfigured),
  analysedAt: DateTime.utc(2026),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Menu refresh flow', () {
    testWidgets(
      "pulling the menu screen down shows the refetched menu's dish",
      (tester) async {
        // Setup: the venue's first menu and its analysis.
        final fakes = FakeAppDependencies();
        fakes.repository.stub(_ref, MenuFetched(menu: _menuWith(_firstDish)));
        fakes.classifier.respondWith(_analysisFor(_firstDish));
        await pumpApp(tester, fakes);

        // Act: paste the link and open the venue.
        await enterText(tester, _woltUrl);
        await tapAndSettle(tester, find.text(_en.venueSearchOpen));

        // Assert: the first menu's dish is showing.
        expect(find.text(_firstDish.name), findsOneWidget);
        expect(find.text(_secondDish.name), findsNothing);

        // Act: script the second call — `FlowFakeMenuRepository.stub`
        // overwrites the ref's scripted result, so the next `load` call
        // (the one the pull-to-refresh below triggers) answers with the
        // second menu instead.
        fakes.repository.stub(_ref, MenuFetched(menu: _menuWith(_secondDish)));
        fakes.classifier.respondWith(_analysisFor(_secondDish));

        // Act: pull the list down far and fast enough to cross
        // RefreshIndicator's own trigger threshold.
        await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();

        // Assert: the refetched menu's dish is now shown in place of the
        // first one, and it was reclassified — the two menus' dish text
        // differs, so architecture.md §6.4's "kept when unchanged" path
        // does not apply here.
        expect(find.text(_secondDish.name), findsOneWidget);
        expect(find.text(_firstDish.name), findsNothing);
        expect(find.byType(DishCard), findsOneWidget);
      },
    );
  });
}
