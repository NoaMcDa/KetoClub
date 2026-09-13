import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/menu_screen.dart';
import 'package:ketoclub/screens/waiter_card_sheet.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/failure_copy.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';

/// The venue every test opens, unless a test builds its own.
const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

/// The English strings a test can read expected copy from, computed the
/// same way the widget under test does.
final AppLocalizations _en = AppLocalizationsEn();

/// The Hebrew strings for the one Locale('he') test.
final AppLocalizations _he = AppLocalizationsHe();

/// A minimal, valid [Dish] named [name].
Dish _dish(String name, {String id = 'd1'}) => Dish(
  id: id,
  name: name,
  description: '',
  price: 10,
  options: const <DishOption>[],
);

/// A minimal, valid [Menu] for [ref], containing [dishes] under one
/// category.
Menu _menuOf(List<Dish> dishes, {VenueRef ref = _ref, DateTime? fetchedAt}) =>
    Menu(
      venueRef: ref,
      currency: 'ILS',
      fetchedAt: fetchedAt ?? DateTime.utc(2026),
      categories: <MenuCategory>[
        MenuCategory(id: 'c1', name: 'Mains', dishes: dishes),
      ],
    );

/// A verdict for [dish] with [verdict], requiring [modification] only when
/// [verdict] is [DishVerdict.modifiable].
AnalysedDish _verdictFor(
  Dish dish,
  DishVerdict verdict, {
  String? modification,
}) => AnalysedDish(
  dishId: dish.id,
  name: dish.name,
  verdict: verdict,
  why: 'why',
  modification: modification,
);

/// Builds the [MenuController] the widget under test is pumped over.
MenuController _controllerFor({
  required FakeMenuRepository repository,
  FakeMenuClassifier? classifier,
  FakeSettingsStore? settings,
}) => MenuController(
  repository,
  classifier ?? FakeMenuClassifier(),
  settings ?? FakeSettingsStore(),
);

/// Pumps a [MenuScreen] for [ref] over [controller], inside a localised
/// [MaterialApp] with [controller] provided through `provider` — the
/// shape every test in this file uses.
Future<void> _pump(
  WidgetTester tester,
  MenuController controller, {
  VenueRef ref = _ref,
  Locale locale = const Locale('en'),
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: ChangeNotifierProvider<MenuController>.value(
        value: controller,
        // Keyed by ref so that a test pumping a second ref onto the same
        // tree slot (the platform-name loop test) mounts a fresh
        // MenuScreen — and so runs initState's open() again — rather than
        // Flutter updating the previous element in place.
        child: MenuScreen(key: ValueKey(ref.cacheKey), ref: ref),
      ),
    ),
  );
}

/// Pumps a [MenuScreen] like [_pump], but with a route table that records
/// every pushed route name into [pushedNames] instead of building it — for
/// the one test that taps an app bar action rather than reading the body.
Future<void> _pumpWithRoutes(
  WidgetTester tester,
  MenuController controller,
  List<String> pushedNames,
) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChangeNotifierProvider<MenuController>.value(
        value: controller,
        child: const MenuScreen(ref: _ref),
      ),
      onGenerateRoute: (settings) {
        pushedNames.add(settings.name ?? '');
        return MaterialPageRoute<void>(
          builder: (_) => const SizedBox.shrink(),
          settings: settings,
        );
      },
    ),
  );
}

void main() {
  group('MenuScreen', () {
    testWidgets(
      'tapping the settings action pushes the settings route even after a '
      'failed fetch',
      (tester) async {
        // Arrange: the failure whose copy names Settings as the way out
        // must leave Settings reachable from this very screen.
        final repository = FakeMenuRepository()
          ..stub(
            _ref,
            const MenuFetchFailed(
              reason: MenuFetchFailureReason.blockedByBrowser,
            ),
          );
        final controller = _controllerFor(repository: repository);
        final pushedNames = <String>[];
        await _pumpWithRoutes(tester, controller, pushedNames);
        await tester.pumpAndSettle();

        // Act
        await tester.tap(find.byIcon(Icons.settings));
        await tester.pumpAndSettle();

        // Assert
        expect(pushedNames, contains('/settings'));
      },
    );

    testWidgets('build shows menuLoading before the fetch resolves', (
      tester,
    ) async {
      // Arrange
      final repository = FakeMenuRepository();
      final controller = _controllerFor(repository: repository);

      // Act: a single pumpWidget renders the first frame, built before the
      // post-frame callback's open() call has had a chance to resolve —
      // the fake repository answers on a microtask, not this frame.
      await _pump(tester, controller);

      // Assert
      expect(find.text(_en.menuLoading), findsOneWidget);
      expect(find.byType(DishCard), findsNothing);
    });

    testWidgets(
      'build shows fetchFailureMessage and a retry affordance on a failed '
      'fetch',
      (tester) async {
        // Arrange
        final repository = FakeMenuRepository()
          ..stub(
            _ref,
            const MenuFetchFailed(
              reason: MenuFetchFailureReason.notFound,
              statusCode: 404,
            ),
          );
        final controller = _controllerFor(repository: repository);

        // Act
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Assert
        final message = fetchFailureMessage(
          MenuFetchFailureReason.notFound,
          _en,
          platform: 'Wolt',
          statusCode: 404,
        );
        expect(find.text(message), findsOneWidget);
        expect(find.text(_en.actionRetry), findsOneWidget);
      },
    );

    testWidgets('build names the platform matching ref.source in the '
        'failure message', (tester) async {
      // Arrange
      const cases = <({VenueRef ref, String name})>[
        (ref: VenueRef(source: MenuSource.wolt, platformId: 'a'), name: 'Wolt'),
        (
          ref: VenueRef(source: MenuSource.tenbis, platformId: 'b'),
          name: '10bis',
        ),
        (
          ref: VenueRef(source: MenuSource.tabit, platformId: 'c'),
          name: 'Tabit',
        ),
        (
          ref: VenueRef(source: MenuSource.ontopo, platformId: 'd'),
          name: 'Ontopo',
        ),
      ];

      for (final testCase in cases) {
        final repository = FakeMenuRepository()
          ..stub(
            testCase.ref,
            const MenuFetchFailed(
              reason: MenuFetchFailureReason.platformChanged,
              statusCode: 500,
            ),
          );
        final controller = _controllerFor(repository: repository);

        // Act
        await _pump(tester, controller, ref: testCase.ref);
        await tester.pumpAndSettle();

        // Assert
        final message = fetchFailureMessage(
          MenuFetchFailureReason.platformChanged,
          _en,
          platform: testCase.name,
          statusCode: 500,
        );
        expect(find.text(message), findsOneWidget);
      }
    });

    testWidgets('build shows the filter the engine chip and a DishCard per '
        'visibleRows on a loaded menu', (tester) async {
      // Arrange
      final green = _dish('Steak', id: 'green');
      final yellow = _dish('Fries', id: 'yellow');
      final repository = FakeMenuRepository()
        ..stub(_ref, MenuFetched(menu: _menuOf([green, yellow])));
      final classifier = FakeMenuClassifier()
        ..respondWith(
          MenuAnalysed(
            dishes: [
              _verdictFor(green, DishVerdict.orderAsIs),
              _verdictFor(
                yellow,
                DishVerdict.modifiable,
                modification: 'Ask for a salad instead of fries.',
              ),
            ],
            unclassified: const <String>[],
            engine: const LlmEngine(model: 'test-model'),
            analysedAt: DateTime.utc(2026),
          ),
        );
      final controller = _controllerFor(
        repository: repository,
        classifier: classifier,
      );

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(SegmentedButton<MenuFilter>), findsOneWidget);
      expect(find.byType(EngineChip), findsOneWidget);
      expect(find.byType(DishCard), findsNWidgets(2));
    });

    testWidgets(
      'build still shows the raw menu with analysisFailureMessage above it '
      'when analysis fails',
      (tester) async {
        // Arrange
        final steak = _dish('Steak');
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([steak])));
        final classifier = FakeMenuClassifier()
          ..respondWith(
            const MenuAnalysisFailed(
              reason: MenuAnalysisFailureReason.badResponse,
              detail: 'bad json',
            ),
          );
        final controller = _controllerFor(
          repository: repository,
          classifier: classifier,
        );

        // Act
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Assert
        final message = analysisFailureMessage(
          MenuAnalysisFailureReason.badResponse,
          _en,
          detail: 'bad json',
        );
        expect(find.text(message), findsOneWidget);
        expect(find.text('Steak'), findsOneWidget);
        expect(find.byType(EngineChip), findsNothing);
        expect(find.byType(SegmentedButton<MenuFilter>), findsNothing);
      },
    );

    testWidgets(
      'build composes the cachedFrom line and the analysisFailureMessage '
      'line when both apply',
      (tester) async {
        // Arrange
        final fetchedAt = DateTime.utc(2025, 12, 1, 8);
        final repository = FakeMenuRepository()
          ..stub(
            _ref,
            MenuFetched(
              menu: _menuOf([_dish('Steak')], fetchedAt: fetchedAt),
              fromCache: true,
              staleReason: MenuFetchFailureReason.offline,
            ),
          );
        final classifier = FakeMenuClassifier()
          ..respondWith(
            const MenuAnalysisFailed(reason: MenuAnalysisFailureReason.timeout),
          );
        final controller = _controllerFor(
          repository: repository,
          classifier: classifier,
        );

        // Act
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Assert
        expect(
          find.text(
            analysisFailureMessage(MenuAnalysisFailureReason.timeout, _en),
          ),
          findsOneWidget,
        );
        expect(
          find.text(fetchFailureMessage(MenuFetchFailureReason.offline, _en)),
          findsOneWidget,
        );
        final formatted = DateFormat.yMMMd('en')
            .add_Hm()
            .format(fetchedAt.toLocal());
        expect(find.text(_en.cachedFrom(formatted)), findsOneWidget);
      },
    );

    testWidgets('build shows menuEmpty for a menu with no dishes', (
      tester,
    ) async {
      // Arrange
      final repository = FakeMenuRepository()
        ..stub(_ref, MenuFetched(menu: _menuOf(const <Dish>[])));
      final controller = _controllerFor(repository: repository);

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.menuEmpty), findsOneWidget);
    });

    testWidgets(
      'the red group starts collapsed shows its count and expands on tap',
      (tester) async {
        // Arrange
        final green = _dish('Steak', id: 'green');
        final red = _dish('Spaghetti Carbonara', id: 'red');
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([green, red])));
        final classifier = FakeMenuClassifier()
          ..respondWith(
            MenuAnalysed(
              dishes: [
                _verdictFor(green, DishVerdict.orderAsIs),
                _verdictFor(red, DishVerdict.nonKeto),
              ],
              unclassified: const <String>[],
              engine: const RulesEngine(
                reason: MenuAnalysisFailureReason.notConfigured,
              ),
              analysedAt: DateTime.utc(2026),
            ),
          );
        final controller = _controllerFor(
          repository: repository,
          classifier: classifier,
        );
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Assert: collapsed
        expect(find.text(_en.redGroupTitle(1)), findsOneWidget);
        expect(find.text('Spaghetti Carbonara'), findsNothing);

        // Act: expand
        await tester.tap(find.text(_en.redGroupTitle(1)));
        await tester.pumpAndSettle();

        // Assert: expanded
        expect(find.text('Spaghetti Carbonara'), findsOneWidget);
      },
    );

    testWidgets('the unclassified section renders its names', (tester) async {
      // Arrange
      final green = _dish('Steak', id: 'green');
      final repository = FakeMenuRepository()
        ..stub(_ref, MenuFetched(menu: _menuOf([green])));
      final classifier = FakeMenuClassifier()
        ..respondWith(
          MenuAnalysed(
            dishes: [_verdictFor(green, DishVerdict.orderAsIs)],
            unclassified: const <String>['Mystery bowl'],
            engine: const RulesEngine(
              reason: MenuAnalysisFailureReason.notConfigured,
            ),
            analysedAt: DateTime.utc(2026),
          ),
        );
      final controller = _controllerFor(
        repository: repository,
        classifier: classifier,
      );

      // Act
      await _pump(tester, controller);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.unclassifiedTitle(1)), findsOneWidget);
      expect(find.text(_en.unclassifiedExplain), findsOneWidget);
      expect(find.text('Mystery bowl'), findsOneWidget);
    });

    testWidgets('switching the filter changes which cards are visible', (
      tester,
    ) async {
      // Arrange
      final green = _dish('Steak', id: 'green');
      final yellow = _dish('Fries', id: 'yellow');
      final red = _dish('Pasta', id: 'red');
      final repository = FakeMenuRepository()
        ..stub(_ref, MenuFetched(menu: _menuOf([green, yellow, red])));
      final classifier = FakeMenuClassifier()
        ..respondWith(
          MenuAnalysed(
            dishes: [
              _verdictFor(green, DishVerdict.orderAsIs),
              _verdictFor(yellow, DishVerdict.modifiable, modification: 'x'),
              _verdictFor(red, DishVerdict.nonKeto),
            ],
            unclassified: const <String>[],
            engine: const RulesEngine(
              reason: MenuAnalysisFailureReason.notConfigured,
            ),
            analysedAt: DateTime.utc(2026),
          ),
        );
      final controller = _controllerFor(
        repository: repository,
        classifier: classifier,
      );
      await _pump(tester, controller);
      await tester.pumpAndSettle();
      expect(find.byType(DishCard), findsNWidgets(2));

      // Act
      await tester.tap(find.text(_en.filterGreenOnly));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(DishCard), findsOneWidget);
      expect(find.text('Steak'), findsOneWidget);
    });

    testWidgets(
      'tapping a yellow card opens the Waiter Card and the script text is '
      'present',
      (tester) async {
        // Arrange
        const script = 'Ask for a salad instead of fries.';
        final yellow = _dish('Fries', id: 'yellow');
        final repository = FakeMenuRepository()
          ..stub(_ref, MenuFetched(menu: _menuOf([yellow])));
        final classifier = FakeMenuClassifier()
          ..respondWith(
            MenuAnalysed(
              dishes: [
                _verdictFor(
                  yellow,
                  DishVerdict.modifiable,
                  modification: script,
                ),
              ],
              unclassified: const <String>[],
              engine: const RulesEngine(
                reason: MenuAnalysisFailureReason.notConfigured,
              ),
              analysedAt: DateTime.utc(2026),
            ),
          );
        final controller = _controllerFor(
          repository: repository,
          classifier: classifier,
        );
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Act
        await tester.tap(find.text(_en.waiterCardOpen));
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(WaiterCardSheet), findsOneWidget);
        expect(find.text(_en.waiterCardTitle), findsOneWidget);
        expect(find.text(script), findsWidgets);
      },
    );

    testWidgets('build renders Hebrew copy under the he locale', (
      tester,
    ) async {
      // Arrange
      final green = _dish('Steak', id: 'green');
      final red = _dish('Pasta', id: 'red');
      final repository = FakeMenuRepository()
        ..stub(_ref, MenuFetched(menu: _menuOf([green, red])));
      final classifier = FakeMenuClassifier()
        ..respondWith(
          MenuAnalysed(
            dishes: [
              _verdictFor(green, DishVerdict.orderAsIs),
              _verdictFor(red, DishVerdict.nonKeto),
            ],
            unclassified: const <String>[],
            engine: const RulesEngine(
              reason: MenuAnalysisFailureReason.notConfigured,
            ),
            analysedAt: DateTime.utc(2026),
          ),
        );
      final controller = _controllerFor(
        repository: repository,
        classifier: classifier,
      );

      // Act
      await _pump(tester, controller, locale: const Locale('he'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_he.filterGreenOnly), findsOneWidget);
      expect(find.text(_he.redGroupTitle(1)), findsOneWidget);
    });

    testWidgets(
      'retry after a failed fetch calls open again with forceRefresh true',
      (tester) async {
        // Arrange
        final repository = FakeMenuRepository()
          ..stub(
            _ref,
            const MenuFetchFailed(reason: MenuFetchFailureReason.offline),
          );
        final controller = _controllerFor(repository: repository);
        await _pump(tester, controller);
        await tester.pumpAndSettle();

        // Act
        await tester.tap(find.text(_en.actionRetry));
        await tester.pumpAndSettle();

        // Assert
        expect(
          repository.loadCalls,
          equals([
            (ref: _ref, forceRefresh: false),
            (ref: _ref, forceRefresh: true),
          ]),
        );
      },
    );
  });
}
