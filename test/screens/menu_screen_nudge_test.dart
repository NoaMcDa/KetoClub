// The empty-profile notice above the dishes on the menu screen (Banto,
// issue #421). Plain `flutter test` compiles the flag off, so each test
// passes `bantoMode` explicitly.

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
import 'package:ketoclub/widgets/helper_tool_sheet.dart';
import 'package:ketoclub/widgets/profile_nudge.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';
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
  FakeSettingsStore settings, {
  required bool bantoMode,
  Locale locale = const Locale('en'),
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
        home: ChangeNotifierProvider<MenuController>.value(
          value: _controller(settings),
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

final Finder _nudge = find.byKey(profileNudgeKey(ProfileNudgeSurface.menu));

void main() {
  group('the menu screen empty-profile notice', () {
    testWidgets('shows above the dishes for a keto-only profile, in English', (
      tester,
    ) async {
      await _pump(tester, FakeSettingsStore(), bantoMode: true);

      expect(_nudge, findsOneWidget);
      expect(find.text(_en.profileNudgeMessage), findsOneWidget);
      expect(find.text(_en.profileNudgeChoose), findsOneWidget);
      expect(find.text(_en.profileNudgeDismiss), findsOneWidget);
      // Above the dish card.
      expect(
        tester.getTopLeft(_nudge).dy,
        lessThan(tester.getTopLeft(find.text('Grilled salmon')).dy),
      );
    });

    testWidgets('shows in Hebrew, laid out right to left', (tester) async {
      await _pump(
        tester,
        FakeSettingsStore(),
        bantoMode: true,
        locale: const Locale('he'),
      );

      expect(find.text(_he.profileNudgeMessage), findsOneWidget);
      expect(find.text(_he.profileNudgeChoose), findsOneWidget);
      expect(Directionality.of(tester.element(_nudge)), TextDirection.rtl);
      // The icon leads the line, so it sits on the right.
      expect(
        tester
            .getCenter(
              find.descendant(of: _nudge, matching: find.byIcon(Icons.tune)),
            )
            .dx,
        greaterThan(tester.getCenter(find.text(_he.profileNudgeMessage)).dx),
      );
    });

    testWidgets('never says a dish is safe, in either language', (
      tester,
    ) async {
      final safe = RegExp('(?<![A-Za-z])safe|בטוח', caseSensitive: false);

      for (final text in <String>[
        _en.profileNudgeMessage,
        _en.profileNudgeChoose,
        _en.profileNudgeDismiss,
        _he.profileNudgeMessage,
        _he.profileNudgeChoose,
        _he.profileNudgeDismiss,
        _en.settingsRestrictionsRerun,
        _he.settingsRestrictionsRerun,
      ]) {
        expect(safe.hasMatch(text), isFalse, reason: text);
      }
    });

    testWidgets('is absent without the flag', (tester) async {
      await _pump(tester, FakeSettingsStore(), bantoMode: false);

      expect(_nudge, findsNothing);
      expect(find.text(_en.profileNudgeMessage), findsNothing);
    });

    testWidgets('is absent once the profile holds a restriction', (
      tester,
    ) async {
      final settings = FakeSettingsStore(
        initial: AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
        ),
      );

      await _pump(tester, settings, bantoMode: true);

      expect(_nudge, findsNothing);
    });

    testWidgets('is absent when it was dismissed on the menu', (tester) async {
      final settings = FakeSettingsStore(
        initial: const AppSettings(menuNudgeDismissed: true),
      );

      await _pump(tester, settings, bantoMode: true);

      expect(_nudge, findsNothing);
    });

    testWidgets('a dismissal on Discovery does not hide it here', (
      tester,
    ) async {
      final settings = FakeSettingsStore(
        initial: const AppSettings(discoveryNudgeDismissed: true),
      );

      await _pump(tester, settings, bantoMode: true);

      expect(_nudge, findsOneWidget);
    });

    testWidgets('"Not now" hides it and remembers it for the menu only', (
      tester,
    ) async {
      final settings = FakeSettingsStore();
      await _pump(tester, settings, bantoMode: true);

      await tester.tap(find.text(_en.profileNudgeDismiss));
      await tester.pumpAndSettle();

      expect(_nudge, findsNothing);
      final stored = await settings.read();
      expect(stored.menuNudgeDismissed, isTrue);
      expect(stored.discoveryNudgeDismissed, isFalse);
      expect(stored.profile.isEmpty, isTrue);
    });

    testWidgets('the action opens the picker; choosing adds it, shows the '
        'helper-tool sheet once and removes the notice', (tester) async {
      final settings = FakeSettingsStore();
      await _pump(tester, settings, bantoMode: true);

      await tester.tap(find.text(_en.profileNudgeChoose));
      await tester.pumpAndSettle();
      final option = find.byKey(restrictionOptionKey(RestrictionId.sesame));
      await tester.ensureVisible(option);
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pumpAndSettle();

      // The first restriction brings the helper-tool sheet.
      expect(find.byKey(helperToolSheetKey), findsOneWidget);
      await tester.tap(find.byKey(helperToolOkKey));
      await tester.pumpAndSettle();
      expect(_nudge, findsNothing);
      expect(find.text(_en.menuProfileSummary('Sesame')), findsOneWidget);
      final stored = await settings.read();
      expect(stored.profile.contains(RestrictionId.sesame), isTrue);
      expect(stored.helperToolSeen, isTrue);
    });

    testWidgets('closing the picker without a choice changes nothing', (
      tester,
    ) async {
      final settings = FakeSettingsStore();
      await _pump(tester, settings, bantoMode: true);

      await tester.tap(find.text(_en.profileNudgeChoose));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(_nudge, findsOneWidget);
      final stored = await settings.read();
      expect(stored.profile.isEmpty, isTrue);
      expect(stored.menuNudgeDismissed, isFalse);
    });
  });
}
