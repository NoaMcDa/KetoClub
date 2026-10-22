import 'dart:async';

import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/menu_screen.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/text/text_menu_source.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/widgets/carb_budget_field.dart';
import 'package:ketoclub/widgets/menu_filters_row.dart';
import 'package:ketoclub/widgets/menu_search_field.dart';
import 'package:ketoclub/widgets/skeletons.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_connectivity.dart';
import '../fakes/fake_external_link_opener.dart';
import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_menu_sharer.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_screen_brightness.dart';
import '../fakes/fake_settings_store.dart';

/// The venue every test opens, unless it builds its own.
const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

/// The English strings expected copy is read from.
final AppLocalizations _en = AppLocalizationsEn();

/// A dish named [name] with id [id].
Dish _dish(String name, String id) => Dish(
  id: id,
  name: name,
  description: '',
  price: 10,
  options: const <DishOption>[],
);

/// A menu for [ref] holding [categories] in order.
Menu _menu(List<MenuCategory> categories, {VenueRef ref = _ref}) => Menu(
  venueRef: ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: categories,
);

/// [dish] placed [verdict], with a script for a yellow and an optional
/// net-carb [estimate].
AnalysedDish _placed(Dish dish, DishVerdict verdict, {double? estimate}) =>
    AnalysedDish(
      dishId: dish.id,
      name: dish.name,
      verdict: verdict,
      why: 'why',
      modification: verdict == DishVerdict.modifiable
          ? 'Swap the fries for a salad.'
          : null,
      netCarbsEstimate: estimate,
    );

/// An analysis of [dishes], leaving [unclassified] unplaced, from the AI
/// engine unless [rules].
MenuAnalysed _analysis(
  List<AnalysedDish> dishes, {
  List<String> unclassified = const <String>[],
  bool rules = false,
}) => MenuAnalysed(
  dishes: dishes,
  unclassified: unclassified,
  engine: rules
      ? const RulesEngine(reason: MenuAnalysisFailureReason.consentWithheld)
      : const LlmEngine(model: 'test-model'),
  analysedAt: DateTime.utc(2026),
);

/// A controller serving [menu] at its ref, classified as [analysis].
MenuController _controller(
  Menu menu,
  MenuAnalysis analysis, {
  CarbBudgetController? budget,
}) => MenuController(
  FakeMenuRepository()..stub(menu.venueRef, MenuFetched(menu: menu)),
  FakeMenuClassifier()..respondWith(analysis),
  FakeSettingsStore(),
  FakeNotesStore(),
  budget ?? CarbBudgetController(),
);

/// Pumps the menu screen for [ref] over [controller] and [budget] at
/// [width] logical pixels wide, and lets it load — or, without [settle],
/// runs it to whatever step a test holds it at.
Future<void> _pump(
  WidgetTester tester,
  MenuController controller, {
  VenueRef ref = _ref,
  CarbBudgetController? budget,
  double width = 800,
  bool settle = true,
}) async {
  _setWidth(tester, width);
  await tester.pumpWidget(
    ChangeNotifierProvider<CarbBudgetController>.value(
      value: budget ?? CarbBudgetController(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: ChangeNotifierProvider<MenuController>.value(
          value: controller,
          child: MenuScreen(
            ref: ref,
            screenBrightness: FakeScreenBrightness(),
            connectivity: FakeConnectivity(),
            externalLinkOpener: FakeExternalLinkOpener(),
            menuSharer: FakeMenuSharer(),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // A load still running animates its progress row, which never
    // settles: two frames run the open up to the held step.
    await tester.pump();
    await tester.pump();
  }
}

/// Sizes the window [width] wide and phone-tall, restored at the end.
void _setWidth(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1600);
  addTearDown(tester.view.reset);
}

/// Opens the collapsed Filters row (issue #234).
Future<void> _openFilters(WidgetTester tester) async {
  await tester.tap(find.text(_en.menuFilters));
  await tester.pumpAndSettle();
}

/// The search field's own text field.
final Finder _searchField = find.descendant(
  of: find.byType(MenuSearchField),
  matching: find.byType(TextField),
);

/// The carb budget's own text field.
final Finder _budgetField = find.descendant(
  of: find.byType(CarbBudgetField),
  matching: find.byType(TextField),
);

void main() {
  group('MenuScreen correctness (issue #286)', () {
    testWidgets('an unclassified dish is listed exactly once under "All"', (
      tester,
    ) async {
      // Arrange: one dish placed, one the analysis could not place.
      final steak = _dish('Steak', 'd1');
      final mystery = _dish('Mystery stew', 'd2');
      final controller = _controller(
        _menu([
          MenuCategory(id: 'c1', name: 'Mains', dishes: [steak, mystery]),
        ]),
        _analysis(
          [_placed(steak, DishVerdict.orderAsIs)],
          unclassified: ['Mystery stew'],
        ),
      );

      // Act
      await _pump(tester, controller);

      // Assert: once, in the unclassified section, not again in the list.
      expect(controller.filter, MenuFilter.all);
      expect(find.text(_en.unclassifiedTitle(1)), findsOneWidget);
      expect(find.text('Mystery stew'), findsOneWidget);
      expect(find.text('Steak'), findsOneWidget);
    });

    testWidgets('a pasted menu repeating a heading renders, each header with '
        'a key of its own', (tester) async {
      // Arrange: TextMenuSource keeps the two "Mains" sections apart.
      final menu = TextMenuSource.parse(
        'Mains:\nSteak\nSides:\nFries\nMains:\nBurger',
        now: DateTime.utc(2026),
      )!;
      expect(menu.categories.map((category) => category.name), <String>[
        'Mains',
        'Sides',
        'Mains',
      ]);
      final controller = _controller(
        menu,
        _analysis([
          for (final dish in menu.allDishes)
            _placed(dish, DishVerdict.orderAsIs),
        ], rules: true),
      );

      // Act
      await _pump(tester, controller, ref: menu.venueRef);

      // Assert: no "Multiple widgets used the same GlobalKey", every
      // dish, and two "Mains" headers beside its one chip.
      expect(tester.takeException(), isNull);
      for (final name in ['Steak', 'Fries', 'Burger']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('Mains'), findsNWidgets(3));
    });

    testWidgets('"Showing N dishes" counts what the search leaves', (
      tester,
    ) async {
      // Arrange
      final dishes = [
        _dish('Grilled salmon', 'd1'),
        _dish('Ribeye', 'd2'),
        _dish('Caesar salad', 'd3'),
      ];
      final controller = _controller(
        _menu([MenuCategory(id: 'c1', name: 'Mains', dishes: dishes)]),
        _analysis([
          for (final dish in dishes) _placed(dish, DishVerdict.orderAsIs),
        ]),
      );
      await _pump(tester, controller);
      expect(find.text(_en.menuShowingAll(3)), findsOneWidget);
      await _openFilters(tester);

      // Act
      await tester.enterText(_searchField, 'salmon');
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.menuShowingAll(1)), findsOneWidget);
    });

    testWidgets('"Showing N dishes" counts what the carb budget leaves', (
      tester,
    ) async {
      // Arrange: two estimated dishes, one over the budget about to be set.
      final light = _dish('Salmon', 'd1');
      final heavy = _dish('Risotto', 'd2');
      final budget = CarbBudgetController();
      final controller = _controller(
        _menu([
          MenuCategory(id: 'c1', name: 'Mains', dishes: [light, heavy]),
        ]),
        _analysis([
          _placed(light, DishVerdict.orderAsIs, estimate: 4),
          _placed(heavy, DishVerdict.nonKeto, estimate: 60),
        ]),
        budget: budget,
      );
      await _pump(tester, controller, budget: budget);
      expect(find.text(_en.menuShowingAll(2)), findsOneWidget);

      // Act
      budget.setBudget(10);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.menuShowingAll(1)), findsOneWidget);
    });

    testWidgets('the budget field follows a budget cleared by "Clear filter"', (
      tester,
    ) async {
      // Arrange: a budget typed in the field hides every dish.
      final heavy = _dish('Risotto', 'd1');
      final budget = CarbBudgetController();
      final controller = _controller(
        _menu([
          MenuCategory(id: 'c1', name: 'Mains', dishes: [heavy]),
        ]),
        _analysis([_placed(heavy, DishVerdict.nonKeto, estimate: 60)]),
        budget: budget,
      );
      await _pump(tester, controller, budget: budget);
      await _openFilters(tester);
      await tester.enterText(_budgetField, '10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text(_en.menuNoResults), findsOneWidget);

      // Act
      await tester.tap(find.text(_en.menuClearFilter));
      await tester.pumpAndSettle();

      // Assert: no budget, and the field no longer shows the old one.
      expect(budget.hasBudget, isFalse);
      expect(tester.widget<TextField>(_budgetField).controller?.text, '');
      expect(find.text('Risotto'), findsOneWidget);
    });

    testWidgets('a budget hidden on a rules-engine menu is not counted as an '
        'active filter', (tester) async {
      // Arrange: a budget left over from an AI menu, then a rules menu.
      final steak = _dish('Steak', 'd1');
      final budget = CarbBudgetController()..setBudget(10);
      final controller = _controller(
        _menu([
          MenuCategory(id: 'c1', name: 'Mains', dishes: [steak]),
        ]),
        _analysis([_placed(steak, DishVerdict.orderAsIs)], rules: true),
        budget: budget,
      );

      // Act
      await _pump(tester, controller, budget: budget);

      // Assert: the field is hidden, and so is the count.
      expect(controller.isBudgetAvailable, isFalse);
      expect(
        tester.widget<MenuFiltersRow>(find.byType(MenuFiltersRow)).activeCount,
        0,
      );
    });

    testWidgets('the search text survives the field being rebuilt from '
        'scratch, here by the window crossing the two-pane width', (
      tester,
    ) async {
      // Arrange: a search typed on a phone-wide window.
      final dishes = [_dish('Grilled salmon', 'd1'), _dish('Ribeye', 'd2')];
      final controller = _controller(
        _menu([MenuCategory(id: 'c1', name: 'Mains', dishes: dishes)]),
        _analysis([
          for (final dish in dishes) _placed(dish, DishVerdict.orderAsIs),
        ]),
      );
      await _pump(tester, controller);
      await _openFilters(tester);
      await tester.enterText(_searchField, 'salmon');
      await tester.pumpAndSettle();
      final before = tester.state(find.byType(MenuSearchField));

      // Act: the header and the Filters row move to the side pane.
      _setWidth(tester, menuTwoPaneMinWidth + 100);
      await tester.pumpAndSettle();

      // Assert: a new field, still reading the query that filters.
      expect(tester.state(find.byType(MenuSearchField)), isNot(same(before)));
      expect(controller.query, 'salmon');
      expect(tester.widget<TextField>(_searchField).controller?.text, 'salmon');
      expect(find.text('Ribeye'), findsNothing);
    });

    testWidgets('an open waiter script stays with its dish when a filter '
        'moves it up the list', (tester) async {
      // Arrange: a green dish, then a yellow one whose script is opened.
      final steak = _dish('Steak', 'd1');
      final burger = _dish('Burger', 'd2');
      final controller = _controller(
        _menu([
          MenuCategory(id: 'c1', name: 'Mains', dishes: [steak, burger]),
        ]),
        _analysis([
          _placed(steak, DishVerdict.orderAsIs),
          _placed(burger, DishVerdict.modifiable),
        ]),
      );
      await _pump(tester, controller);
      await tester.tap(find.text(_en.dishCardAskWaiter));
      await tester.pumpAndSettle();
      expect(find.text(_en.dishCardFullScreen), findsOneWidget);

      // Act: only the yellow dish is left, in the green dish's place.
      await controller.setFilter(MenuFilter.yellowOnly);
      await tester.pumpAndSettle();

      // Assert: its script is still open.
      expect(find.text('Steak'), findsNothing);
      expect(find.text(_en.dishCardFullScreen), findsOneWidget);
    });
  });

  group('MenuScreen loads (issue #287)', () {
    testWidgets('the refresh action is disabled while the menu is being '
        'classified, and enabled once it is done', (tester) async {
      // Arrange: the menu is fetched, its classification held.
      final steak = _dish('Steak', 'd1');
      final engine = Completer<void>();
      final classifier = FakeMenuClassifier()
        ..gate = engine.future
        ..respondWith(_analysis([_placed(steak, DishVerdict.orderAsIs)]));
      final controller = MenuController(
        FakeMenuRepository()..stub(
          _ref,
          MenuFetched(
            menu: _menu([
              MenuCategory(id: 'c1', name: 'Mains', dishes: [steak]),
            ]),
          ),
        ),
        classifier,
        FakeSettingsStore(),
        FakeNotesStore(),
        CarbBudgetController(),
      );
      await _pump(tester, controller, settle: false);
      IconButton refresh() => tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.refresh),
      );

      // Assert: no second classification can be started.
      expect(controller.isLoading, isTrue);
      expect(refresh().onPressed, isNull);

      // Act
      engine.complete();
      await tester.pumpAndSettle();

      // Assert
      expect(refresh().onPressed, isNotNull);
      expect(classifier.calls, hasLength(1));
    });

    testWidgets('Retry after a failed fetch clears the failure for the '
        'loading state, and a second tap starts no second open', (
      tester,
    ) async {
      // Arrange: a failed fetch on screen, the retry's fetch held.
      final repository = FakeMenuRepository()
        ..stub(
          _ref,
          const MenuFetchFailed(reason: MenuFetchFailureReason.offline),
        );
      final controller = MenuController(
        repository,
        FakeMenuClassifier(),
        FakeSettingsStore(),
        FakeNotesStore(),
        CarbBudgetController(),
      );
      await _pump(tester, controller);
      final retry = find.text(_en.actionRetry);
      expect(retry, findsOneWidget);
      final fetch = Completer<void>();
      repository.loadGate = fetch.future;

      // Act
      await tester.tap(retry);
      await tester.pump();

      // Assert: the failure has given way to the loading skeleton, so
      // there is no retry left to tap twice.
      expect(controller.fetchFailure, isNull);
      expect(find.text(_en.actionRetry), findsNothing);
      expect(find.byType(DishCardSkeleton), findsWidgets);
      expect(repository.loadCalls, hasLength(2));
      fetch.complete();
      await tester.pumpAndSettle();
    });
  });
}
