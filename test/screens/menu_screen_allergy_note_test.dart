// The menu overflow's "Copy allergy note" (Banto, ALG-15, issue #357): one
// tap copies the profile's note in the menu's language, a second shares it;
// gated on Banto and a profile with more than keto, and offered on scanned
// menus too (D15). Plain `flutter test` compiles the flag off, so each test
// passes `bantoMode` explicitly.

import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter/services.dart';
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
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
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

const VenueRef _wolt = VenueRef(source: MenuSource.wolt, platformId: 'v1');
const VenueRef _scan = VenueRef(source: MenuSource.scan, platformId: 'abc');

final DietaryProfile _sesame = DietaryProfile.empty.withEntry(
  RestrictionId.sesame,
);

/// A one-dish menu at [ref] whose dish is named [dishName].
Menu _menu(VenueRef ref, String dishName) => Menu(
  venueRef: ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(
      id: 'c1',
      name: 'Mains',
      dishes: <Dish>[
        Dish(
          id: 'd1',
          name: dishName,
          description: '',
          price: 10,
          options: const <DishOption>[],
        ),
      ],
    ),
  ],
);

MenuController _controller(Menu menu, DietaryProfile profile) {
  final repository = FakeMenuRepository()
    ..stub(menu.venueRef, MenuFetched(menu: menu, fromCache: true));
  return MenuController(
    repository,
    FakeMenuClassifier(),
    FakeSettingsStore(initial: AppSettings(profile: profile)),
    FakeNotesStore(),
    CarbBudgetController(),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required Menu menu,
  required bool bantoMode,
  DietaryProfile? profile,
  FakeMenuSharer? sharer,
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
          value: _controller(menu, profile ?? _sesame),
          child: MenuScreen(
            ref: menu.venueRef,
            screenBrightness: FakeScreenBrightness(),
            connectivity: FakeConnectivity(),
            externalLinkOpener: FakeExternalLinkOpener(),
            menuSharer: sharer ?? FakeMenuSharer(),
            bantoMode: bantoMode,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the overflow menu, when there is one.
Future<void> _openOverflow(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.byTooltip(l10n.actionMoreMenuOptions));
  await tester.pumpAndSettle();
}

void main() {
  final copied = <String>[];

  setUp(() {
    copied.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<Object?, Object?>;
            copied.add(args['text']! as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('one tap copies the English note of an English menu, and '
      'Share sends it', (tester) async {
    // Arrange
    final sharer = FakeMenuSharer();
    await _pump(
      tester,
      menu: _menu(_wolt, 'Grilled salmon'),
      bantoMode: true,
      sharer: sharer,
    );
    final note = ChefCardText.allergyNote(_sesame, hebrew: false)!;

    // Act
    await _openOverflow(tester, _en);
    await tester.tap(find.text(_en.menuAllergyNoteAction));
    await tester.pumpAndSettle();

    // Assert
    expect(copied, <String>[note]);
    expect(find.text(_en.menuAllergyNoteCopied), findsOneWidget);
    expect(sharer.shareCalls, isEmpty);

    // Act
    await tester.tap(find.text(_en.menuAllergyNoteShare));
    await tester.pumpAndSettle();

    // Assert
    expect(sharer.shareCalls.single.text, note);
    expect(sharer.shareCalls.single.subject, _en.menuAllergyNoteSubject);
  });

  testWidgets('a Hebrew menu gets the Hebrew note, whatever the app '
      'language', (tester) async {
    // Arrange
    await _pump(tester, menu: _menu(_wolt, 'סלט ירוק'), bantoMode: true);

    // Act
    await _openOverflow(tester, _en);
    await tester.tap(find.text(_en.menuAllergyNoteAction));
    await tester.pumpAndSettle();

    // Assert
    expect(
      copied.single,
      'יש לי אלרגיה לשומשום. בבקשה לבדוק כל מרכיב, כולל רטבים, ולוודא '
      'שאין מגע צולב בהכנה. תודה.',
    );
  });

  testWidgets('the action reads in Hebrew under a Hebrew app', (tester) async {
    // Arrange
    await _pump(
      tester,
      menu: _menu(_wolt, 'Grilled salmon'),
      bantoMode: true,
      locale: const Locale('he'),
    );

    // Act
    await _openOverflow(tester, _he);
    await tester.tap(find.text(_he.menuAllergyNoteAction));
    await tester.pumpAndSettle();

    // Assert: the chrome is Hebrew; the note follows the English menu.
    expect(find.text(_he.menuAllergyNoteCopied), findsOneWidget);
    expect(find.text(_he.menuAllergyNoteShare), findsOneWidget);
    expect(copied, <String>[ChefCardText.allergyNote(_sesame, hebrew: false)!]);
  });

  testWidgets('a scanned menu offers it too', (tester) async {
    // Arrange
    await _pump(tester, menu: _menu(_scan, 'סלט ירוק'), bantoMode: true);

    // Act
    await _openOverflow(tester, _en);

    // Assert
    expect(find.text(_en.menuAllergyNoteAction), findsOneWidget);
  });

  testWidgets('without Banto there is no allergy note', (tester) async {
    // Act
    await _pump(tester, menu: _menu(_wolt, 'Grilled salmon'), bantoMode: false);

    // Assert
    expect(find.text(_en.menuAllergyNoteAction), findsNothing);
    if (find.byTooltip(_en.actionMoreMenuOptions).evaluate().isNotEmpty) {
      await _openOverflow(tester, _en);
      expect(find.text(_en.menuAllergyNoteAction), findsNothing);
    }
  });

  testWidgets('a keto-only profile has no allergy note', (tester) async {
    // Act
    await _pump(
      tester,
      menu: _menu(_wolt, 'Grilled salmon'),
      bantoMode: true,
      profile: DietaryProfile.empty.withEntry(RestrictionId.keto),
    );

    // Assert
    if (find.byTooltip(_en.actionMoreMenuOptions).evaluate().isNotEmpty) {
      await _openOverflow(tester, _en);
    }
    expect(find.text(_en.menuAllergyNoteAction), findsNothing);
  });
}
