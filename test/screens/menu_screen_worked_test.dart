// The menu header's "Worked for me" tag and overflow toggle (Banto, issue
// #412): the tag shows when the open venue is marked for the people the menu
// is read for, the overflow marks and unmarks, and neither exists without
// Banto or under a keto-only profile.
import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/menu_screen.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/utils/visit_profile.dart';
import 'package:ketoclub/widgets/worked_for_tag.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_connectivity.dart';
import '../fakes/fake_external_link_opener.dart';
import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_menu_sharer.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_screen_brightness.dart';
import '../fakes/fake_settings_store.dart';
import '../fakes/fake_visit_history_store.dart';

final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _he = AppLocalizationsHe();

const VenueRef _wolt = VenueRef(source: MenuSource.wolt, platformId: 'v1');

final DietaryProfile _sesame = DietaryProfile.empty.withEntry(
  RestrictionId.sesame,
);

final Menu _menu = Menu(
  venueRef: _wolt,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'Mains',
      dishes: <Dish>[
        Dish(
          id: 'd1',
          name: 'Grilled salmon',
          description: '',
          price: 10,
          options: <DishOption>[],
        ),
      ],
    ),
  ],
);

Future<FakeVisitHistoryStore> _pump(
  WidgetTester tester, {
  required AppSettings settings,
  bool bantoMode = true,
  List<String> workedFor = const <String>[],
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final history = FakeVisitHistoryStore(FakeClock(DateTime.utc(2026)));
  await history.recordVisit(_wolt);
  if (workedFor.isNotEmpty) await history.setWorkedFor(_wolt, workedFor);
  final repository = FakeMenuRepository()
    ..stub(_wolt, MenuFetched(menu: _menu, fromCache: true));
  final controller = MenuController(
    repository,
    FakeMenuClassifier(),
    FakeSettingsStore(initial: settings),
    FakeNotesStore(),
    CarbBudgetController(),
    null,
    history,
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<CarbBudgetController>.value(
      value: CarbBudgetController(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: ChangeNotifierProvider<MenuController>.value(
          value: controller,
          child: MenuScreen(
            ref: _wolt,
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
  return history;
}

void main() {
  testWidgets('a marked venue shows the tag in the header', (tester) async {
    // Act
    await _pump(
      tester,
      settings: AppSettings(profile: _sesame),
      workedFor: const <String>[workedForSelf],
    );

    // Assert
    expect(find.byKey(workedForTagKey), findsOneWidget);
    expect(find.text(_en.workedChip), findsOneWidget);
  });

  testWidgets('an unmarked venue shows no tag; the overflow marks it, then '
      'unmarks it', (tester) async {
    // Arrange
    final history = await _pump(
      tester,
      settings: AppSettings(profile: _sesame),
    );
    expect(find.byKey(workedForTagKey), findsNothing);

    // Act
    await tester.tap(find.byTooltip(_en.actionMoreMenuOptions));
    await tester.pumpAndSettle();
    expect(find.text(_en.workedMark), findsOneWidget);
    await tester.tap(find.byKey(menuWorkedToggleKey));
    await tester.pumpAndSettle();

    // Assert
    expect(find.byKey(workedForTagKey), findsOneWidget);
    expect((await history.read(_wolt))!.workedFor, <String>[workedForSelf]);

    // Act
    await tester.tap(find.byTooltip(_en.actionMoreMenuOptions));
    await tester.pumpAndSettle();
    expect(find.text(_en.workedUnmark), findsOneWidget);
    await tester.tap(find.byKey(menuWorkedToggleKey));
    await tester.pumpAndSettle();

    // Assert
    expect(find.byKey(workedForTagKey), findsNothing);
    expect((await history.read(_wolt))!.workedFor, isEmpty);
  });

  testWidgets('a mark for someone the menu is not read for shows no tag', (
    tester,
  ) async {
    // Act
    await _pump(
      tester,
      settings: AppSettings(profile: _sesame),
      workedFor: const <String>['Dana'],
    );

    // Assert
    expect(find.byKey(workedForTagKey), findsNothing);
  });

  testWidgets('a group reads "Worked for Noa, Dana"', (tester) async {
    // Act
    await _pump(
      tester,
      settings: AppSettings(
        profile: _sesame,
        primaryProfileName: 'Noa',
        otherProfiles: <NamedProfile>[
          NamedProfile(
            id: 'dana',
            name: 'Dana',
            profile: DietaryProfile.empty.withEntry(RestrictionId.peanuts),
          ),
        ],
        activeProfileIds: const <String>[NamedProfile.primaryId, 'dana'],
      ),
      workedFor: const <String>['Noa', 'Dana'],
    );

    // Assert
    expect(find.text(_en.workedTagNames('Noa, Dana')), findsOneWidget);
  });

  testWidgets('the tag and the toggle read in Hebrew', (tester) async {
    // Arrange
    await _pump(
      tester,
      settings: AppSettings(profile: _sesame),
      workedFor: const <String>[workedForSelf],
      locale: const Locale('he'),
    );
    expect(find.text(_he.workedChip), findsOneWidget);

    // Act
    await tester.tap(find.byTooltip(_he.actionMoreMenuOptions));
    await tester.pumpAndSettle();

    // Assert
    expect(find.text(_he.workedUnmark), findsOneWidget);
  });

  testWidgets('a build without Banto shows neither tag nor toggle', (
    tester,
  ) async {
    // Act
    await _pump(
      tester,
      settings: AppSettings(profile: _sesame),
      bantoMode: false,
      workedFor: const <String>[workedForSelf],
    );

    // Assert
    expect(find.byKey(workedForTagKey), findsNothing);
    if (find.byTooltip(_en.actionMoreMenuOptions).evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip(_en.actionMoreMenuOptions));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(menuWorkedToggleKey), findsNothing);
  });

  testWidgets('a keto-only profile shows neither tag nor toggle', (
    tester,
  ) async {
    // Act
    await _pump(
      tester,
      settings: const AppSettings(),
      workedFor: const <String>[workedForSelf],
    );

    if (find.byTooltip(_en.actionMoreMenuOptions).evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip(_en.actionMoreMenuOptions));
      await tester.pumpAndSettle();
    }

    // Assert
    expect(find.byKey(workedForTagKey), findsNothing);
    expect(find.byKey(menuWorkedToggleKey), findsNothing);
  });
}
