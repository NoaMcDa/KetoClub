// The menu screen read for a group (Banto; ALG-12, #354): the combine
// control and its sheet, the "N dishes fit everyone" header line, the
// strictest pill with a per-person breakdown, and the group chef card.
// Plain `flutter test` compiles the flag off, so each test passes
// `bantoMode` explicitly.

import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/chef_card_screen.dart';
import 'package:ketoclub/screens/menu_group.dart';
import 'package:ketoclub/screens/menu_screen.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/group_breakdown_line.dart';
import 'package:ketoclub/widgets/group_chef_card_view.dart';
import 'package:ketoclub/widgets/group_combine_sheet.dart';
import 'package:ketoclub/widgets/profile_summary_line.dart';
import 'package:ketoclub/widgets/status_badge.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_connectivity.dart';
import '../fakes/fake_external_link_opener.dart';
import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_menu_sharer.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_screen_brightness.dart';
import '../fakes/fake_settings_store.dart';

final AppLocalizations _en = AppLocalizationsEn();

const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

/// A cheese omelette (milk, in the name) and a tomato salad.
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'Mains',
      dishes: <Dish>[
        Dish(
          id: 'omelette',
          name: 'Cheese omelette',
          description: '',
          price: 10,
          options: <DishOption>[],
        ),
        Dish(
          id: 'salad',
          name: 'Tomato salad',
          description: '',
          price: 10,
          options: <DishOption>[],
        ),
      ],
    ),
  ],
);

/// Dana, holding milk.
final NamedProfile _dana = NamedProfile(
  id: 'p1',
  name: 'Dana',
  profile: DietaryProfile.empty.withEntry(RestrictionId.milk),
);

/// Me (keto) and Dana on the device, [active] combined, every dish shown.
FakeSettingsStore _settings({
  List<String> active = const <String>['me', 'p1'],
}) => FakeSettingsStore(
  initial: AppSettings(
    otherProfiles: <NamedProfile>[_dana],
    activeProfileIds: active,
    lastFilter: MenuFilter.all,
  ),
);

MenuController _controller(FakeSettingsStore settings) {
  final repository = FakeMenuRepository()..stub(_ref, MenuFetched(menu: _menu));
  final classifier = FakeMenuClassifier()
    ..respondWith(
      MenuAnalysed(
        dishes: <AnalysedDish>[
          for (final dish in _menu.allDishes)
            AnalysedDish(
              dishId: dish.id,
              name: dish.name,
              verdict: DishVerdict.orderAsIs,
              why: 'why',
            ),
        ],
        unclassified: const <String>[],
        engine: const LlmEngine(model: 'test-model'),
        analysedAt: DateTime.utc(2026),
      ),
    );
  return MenuController(
    repository,
    classifier,
    settings,
    FakeNotesStore(),
    CarbBudgetController(),
  );
}

Future<void> _pump(
  WidgetTester tester,
  MenuController controller, {
  bool bantoMode = true,
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider<CarbBudgetController>.value(
      value: CarbBudgetController(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const Scaffold(body: SizedBox.shrink()),
        ),
        home: ChangeNotifierProvider<MenuController>.value(
          value: controller,
          child: MenuScreen(
            ref: _ref,
            screenBrightness: FakeScreenBrightness(),
            connectivity: FakeConnectivity(),
            externalLinkOpener: FakeExternalLinkOpener(),
            menuSharer: FakeMenuSharer(),
            bantoMode: bantoMode,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The card of the dish named [name].
Finder _card(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(DishCard));

void main() {
  group('MenuScreen read for a group', () {
    testWidgets('names the people, not the restrictions, in the Filters row', (
      tester,
    ) async {
      // Act
      await _pump(tester, _controller(_settings()));

      // Assert
      expect(find.byType(GroupCombineControl), findsOneWidget);
      expect(find.text(_en.menuProfileSummary('Me, Dana')), findsOneWidget);
      expect(find.byType(ProfileSummaryLine), findsNothing);
    });

    testWidgets('the header counts the dishes that fit everyone', (
      tester,
    ) async {
      // Act
      await _pump(tester, _controller(_settings()));

      // Assert: milk is strict, so "fits" is never said.
      final line = find.byKey(menuGroupFitsKey);
      expect(line, findsOneWidget);
      expect(tester.widget<Text>(line).data, _en.groupFitsEveryoneStrict(1));
    });

    testWidgets('the omelette shows avoid, with whose it is', (tester) async {
      // Act
      await _pump(tester, _controller(_settings()));

      // Assert
      final omelette = _card('Cheese omelette');
      expect(
        find.descendant(
          of: omelette,
          matching: find.text(_en.stateAvoidBadge.toUpperCase()),
        ),
        findsOneWidget,
      );
      final breakdown = find.descendant(
        of: omelette,
        matching: find.byKey(groupBreakdownKey),
      );
      expect(
        tester.widget<Text>(breakdown).data,
        '${_en.groupBreakdownEntry('Me', _en.stateFitsBadge)} · '
        '${_en.groupBreakdownEntry('Dana', _en.stateAvoidBadge)}',
      );
      expect(
        find.descendant(
          of: _card('Tomato salad'),
          matching: find.byType(GroupBreakdownLine),
        ),
        findsOneWidget,
      );
    });

    testWidgets('one person combined: no breakdown and no header line', (
      tester,
    ) async {
      // Act
      await _pump(tester, _controller(_settings(active: const <String>['p1'])));

      // Assert
      expect(find.text(_en.menuProfileSummary('Dana')), findsOneWidget);
      expect(find.byType(GroupBreakdownLine), findsNothing);
      expect(find.byKey(menuGroupFitsKey), findsNothing);
      expect(find.byType(StateBadge), findsWidgets);
    });

    testWidgets('the sheet un-combines Dana and saves the choice', (
      tester,
    ) async {
      // Arrange
      final settings = _settings();
      await _pump(tester, _controller(settings));

      // Act
      await tester.tap(find.byKey(groupCombineControlKey));
      await tester.pumpAndSettle();
      expect(find.text(_en.groupCombineTitle), findsOneWidget);
      await tester.tap(find.byKey(groupCombineOptionKey('p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(groupCombineApplyKey));
      await tester.pumpAndSettle();

      // Assert: Me alone is keto only, today's screen.
      expect((await settings.read()).activeProfileIds, <String>['me']);
      expect(find.byType(GroupBreakdownLine), findsNothing);
      expect(find.byKey(menuGroupFitsKey), findsNothing);
      expect(find.text(_en.menuProfileSummary('Me')), findsOneWidget);
    });

    testWidgets('the last checked person cannot be unchecked', (tester) async {
      // Arrange
      final settings = _settings(active: const <String>['me']);
      await _pump(tester, _controller(settings));
      await tester.tap(find.byKey(groupCombineControlKey));
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.byKey(groupCombineOptionKey('me')));
      await tester.pumpAndSettle();

      // Assert
      final me = tester.widget<CheckboxListTile>(
        find.byKey(groupCombineOptionKey('me')),
      );
      expect(me.value, isTrue);
    });

    testWidgets('the sheet opens a chef card with a section per person', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, _controller(_settings()));
      await tester.tap(find.byKey(groupCombineControlKey));
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.byKey(groupCombineChefCardKey));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(ChefCardScreen), findsOneWidget);
      expect(find.byType(GroupChefCardView), findsOneWidget);
      expect(find.byKey(groupChefCardSectionKey('Me')), findsOneWidget);
      expect(find.byKey(groupChefCardSectionKey('Dana')), findsOneWidget);
    });

    testWidgets('renders none of it without bantoMode', (tester) async {
      // Act
      await _pump(tester, _controller(_settings()), bantoMode: false);

      // Assert
      expect(find.byType(GroupCombineControl), findsNothing);
      expect(find.byType(GroupBreakdownLine), findsNothing);
      expect(find.byKey(menuGroupFitsKey), findsNothing);
    });
  });
}
