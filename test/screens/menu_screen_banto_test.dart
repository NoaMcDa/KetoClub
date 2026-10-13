// The restriction profile summary in the menu screen's Filters row (Banto,
// ALG-02b, issue #344). Plain `flutter test` compiles the flag off, so each
// test passes `bantoMode` explicitly.

import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/menu_screen.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/widgets/profile_summary_line.dart';
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
final AppLocalizations _he = AppLocalizationsHe();

const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

final DietaryProfile _profile = DietaryProfile.empty
    .withEntry(RestrictionId.sesame)
    .withEntry(RestrictionId.lactose);

MenuController _controller(FakeSettingsStore settings) {
  final repository = FakeMenuRepository()
    ..stub(
      _ref,
      MenuFetched(
        menu: Menu(
          venueRef: _ref,
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
        ),
        fromCache: true,
      ),
    );
  return MenuController(
    repository,
    FakeMenuClassifier(),
    settings,
    FakeNotesStore(),
    CarbBudgetController(),
  );
}

Future<void> _pump(
  WidgetTester tester,
  MenuController controller, {
  required bool bantoMode,
  Locale locale = const Locale('en'),
  List<String>? pushed,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider<CarbBudgetController>.value(
      value: CarbBudgetController(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        onGenerateRoute: (settings) {
          pushed?.add(settings.name ?? '');
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('Settings page')),
          );
        },
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

void main() {
  testWidgets('names the profile in the Filters row when flagged', (
    tester,
  ) async {
    final settings = FakeSettingsStore(initial: AppSettings(profile: _profile));

    await _pump(tester, _controller(settings), bantoMode: true);

    expect(
      find.text(_en.menuProfileSummary('Sesame, Lactose')),
      findsOneWidget,
    );
  });

  testWidgets('names it in Hebrew', (tester) async {
    final settings = FakeSettingsStore(initial: AppSettings(profile: _profile));

    await _pump(
      tester,
      _controller(settings),
      bantoMode: true,
      locale: const Locale('he'),
    );

    expect(find.text(_he.menuProfileSummary('שומשום, לקטוז')), findsOneWidget);
  });

  testWidgets('renders nothing when the flag is off, whatever the profile', (
    tester,
  ) async {
    final settings = FakeSettingsStore(initial: AppSettings(profile: _profile));

    await _pump(tester, _controller(settings), bantoMode: false);

    expect(find.byType(ProfileSummaryLine), findsNothing);
    expect(find.textContaining('Checking for'), findsNothing);
  });

  testWidgets('renders nothing for an empty profile when flagged', (
    tester,
  ) async {
    await _pump(tester, _controller(FakeSettingsStore()), bantoMode: true);

    expect(find.byType(ProfileSummaryLine), findsNothing);
  });

  testWidgets('tapping it opens Settings and re-reads the profile on return', (
    tester,
  ) async {
    final settings = FakeSettingsStore(initial: AppSettings(profile: _profile));
    final pushed = <String>[];
    await _pump(tester, _controller(settings), bantoMode: true, pushed: pushed);

    await tester.tap(find.byType(ProfileSummaryLine));
    await tester.pumpAndSettle();
    expect(pushed, contains('/settings'));

    // The user removes a restriction on the Settings page, then goes back.
    await settings.write(
      AppSettings(profile: _profile.withoutEntry(RestrictionId.lactose)),
    );
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(find.text(_en.menuProfileSummary('Sesame')), findsOneWidget);
  });
}
