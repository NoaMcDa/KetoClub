// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §10, §14 D10,
// §18.4; issue #68): "offline → cached menu with the 'from {date}' line →
// back online → refresh shows the fresh menu" — the journey issue #68's
// acceptance criteria name.
//
// Connectivity and the repository are both faked through this
// directory's own `flow_support.dart` (`FlowFakeConnectivity`,
// `FlowFakeMenuRepository`), per this file's own top doc comment on why
// the fakes live here rather than in `test/fakes/`.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/offline_banner.dart';

import 'flow_support.dart';

/// The Wolt venue page the user pastes, matching
/// `menu_refresh_flow_test.dart`.
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

/// The dish on the venue's cached menu — all that is on screen while
/// offline.
const Dish _cachedDish = Dish(
  id: 'd1',
  name: 'Herb Butter Steak',
  description: '',
  price: 42,
  options: <DishOption>[],
);

/// The dish that appears only once the refetch succeeds.
const Dish _freshDish = Dish(
  id: 'd2',
  name: 'Grilled Chicken Salad',
  description: '',
  price: 38,
  options: <DishOption>[],
);

/// When [_cachedDish]'s menu was fetched, before the flow ever starts.
final DateTime _cachedAt = DateTime.utc(2025, 12, 1, 8);

Menu _menuWith(Dish dish, {DateTime? fetchedAt}) => Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: fetchedAt ?? DateTime.utc(2026),
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

  group('Error recovery flow', () {
    testWidgets(
      'offline shows the cached menu with the "from {date}" line and the '
      'offline banner; going back online and refreshing shows the fresh '
      'menu and clears both',
      (tester) async {
        // Setup: the device is offline, and the live fetch that failed
        // fell back to a cached menu (architecture.md §10 row 1).
        final fakes = FakeAppDependencies();
        fakes.connectivity.online = false;
        fakes.repository.stub(
          _ref,
          MenuFetched(
            menu: _menuWith(_cachedDish, fetchedAt: _cachedAt),
            fromCache: true,
            staleReason: MenuFetchFailureReason.offline,
          ),
        );
        fakes.classifier.respondWith(_analysisFor(_cachedDish));
        await pumpApp(tester, fakes);

        // Act: paste the link and open the venue.
        await enterText(tester, _woltUrl);
        await tapAndSettle(tester, find.text(_en.venueSearchOpen));

        // Assert: the cached dish is shown, dated, with the offline
        // banner and the stale-fetch reason both on screen.
        expect(find.byType(OfflineBanner), findsOneWidget);
        expect(find.text(_en.offlineBannerMessage), findsOneWidget);
        expect(find.text(_cachedDish.name), findsOneWidget);
        expect(find.text(_freshDish.name), findsNothing);
        final formatted = DateFormat.yMMMd('en')
            .add_Hm()
            .format(_cachedAt.toLocal());
        expect(find.text(_en.cachedFrom(formatted)), findsOneWidget);
        expect(find.text(_en.fetchFailedOffline), findsOneWidget);

        // Act: the device comes back online, the venue's live menu is
        // now reachable, and the user retries — the refresh action
        // beside the source line (issue #47), the same one
        // pull-to-refresh drives (issue #49).
        fakes.connectivity.online = true;
        fakes.repository.stub(_ref, MenuFetched(menu: _menuWith(_freshDish)));
        fakes.classifier.respondWith(_analysisFor(_freshDish));
        await tapAndSettle(tester, find.byTooltip(_en.actionRefreshMenu));

        // Assert: the fresh menu replaced the cached one, and neither the
        // offline banner nor the stale-cache notice is shown any more.
        expect(find.text(_freshDish.name), findsOneWidget);
        expect(find.text(_cachedDish.name), findsNothing);
        expect(find.byType(DishCard), findsOneWidget);
        expect(find.text(_en.offlineBannerMessage), findsNothing);
        expect(find.text(_en.cachedFrom(formatted)), findsNothing);
        expect(find.text(_en.fetchFailedOffline), findsNothing);
      },
    );
  });
}
