// Flow test (FLOW_TEST_CONVENTIONS.md; Banto, ALG-13, issue #355): trip
// mode with the phone offline. A wheat-and-sesame profile has a trip to
// Japan set; with no connection, Settings opens the pre-trip briefing —
// "labelled on packaged food only" for wheat, "not on the allergen list"
// for sesame, and the local dishes that hide them (yakisoba, goma) — and
// the briefing opens the chef card, all composed on the device. Then a
// cached Tokyo menu opens under the rules engine, and yakisoba, which only
// the Japanese lexicon reads as wheat, is a dish to ask about. Switching
// trip mode off in Settings, one tap, leaves the briefing unreachable. The
// effect spans Settings, the briefing, the chef card, Explore and the menu,
// which is why this is a flow and not a widget test.
//
// Issue #419: the briefing's chef card opens in the destination's language
// — Japanese for Japan; and, in a second flow, French for a trip to
// France, offline, with the "translated by the app" line, English a tap
// away, and the card shared as an image (#420).
//
// The whole app is pumped with `bantoMode: true`, so it runs under
// `flutter test` with no `--dart-define`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/app.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/trip_destination.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/chef_card_image_screen.dart';
import 'package:ketoclub/screens/chef_card_screen.dart';
import 'package:ketoclub/screens/settings_trip_section.dart';
import 'package:ketoclub/screens/trip_briefing_screen.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/utils/allergens/chef_card_locales.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/widgets/status_badge.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Wolt venue page the user pastes.
const String _woltUrl =
    'https://wolt.com/en/jpn/tokyo/restaurant/banto-trip-venue';

/// The [VenueRef] [_woltUrl] resolves to.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'banto-trip-venue',
);

/// Yakisoba: wheat only by the Japanese lexicon.
const Dish _yakisoba = Dish(
  id: 'yakisoba',
  name: 'Yakisoba',
  description: '',
  price: 900,
  options: <DishOption>[],
);

/// The cached Tokyo menu.
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'JPY',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[
    MenuCategory(id: 'c1', name: 'Noodles', dishes: <Dish>[_yakisoba]),
  ],
);

/// The rules engine's answer with no connection: green, stamped offline.
final MenuAnalysed _offlineAnalysis = MenuAnalysed(
  dishes: <AnalysedDish>[
    AnalysedDish(
      dishId: _yakisoba.id,
      name: _yakisoba.name,
      verdict: DishVerdict.orderAsIs,
      why: 'Nothing starchy turned up.',
    ),
  ],
  unclassified: const <String>[],
  engine: const RulesEngine(reason: MenuAnalysisFailureReason.offline),
  analysedAt: DateTime.utc(2026),
);

/// Wheat and sesame allergies.
final DietaryProfile _profile = DietaryProfile.empty
    .withEntry(RestrictionId.wheat)
    .withEntry(RestrictionId.sesame);

/// "safe" as a word in English, "בטוח" anywhere in Hebrew.
final RegExp _safe = RegExp('(?<![A-Za-z])safe|בטוח', caseSensitive: false);

/// The subtitle text of the [ListTile] keyed [key].
String _subtitle(WidgetTester tester, Key key) {
  final tile = tester.widget<ListTile>(find.byKey(key));
  return (tile.subtitle! as Text).data!;
}

/// Every [Text] on screen, joined.
String _allText(WidgetTester tester) => <String>[
  for (final text in tester.widgetList<Text>(find.byType(Text)))
    text.data ?? text.textSpan?.toPlainText() ?? '',
].join('\n');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offline, the trip briefing and its chef card open, and a '
      'cached menu reads the local lexicon', (tester) async {
    // Setup: a trip to Japan, the phone offline, a cached menu.
    final fakes = FakeAppDependencies();
    await fakes.settingsStore.write(
      AppSettings(
        profile: _profile,
        onboardingSeen: true,
        disclosureSeen: true,
        tripDestination: TripDestination.japan,
      ),
    );
    fakes.connectivity.online = false;
    fakes.repository.stub(_ref, MenuFetched(menu: _menu, fromCache: true));
    fakes.classifier.respondWith(_offlineAnalysis);
    await tester.pumpWidget(
      KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
    );
    await tester.pumpAndSettle();

    // Act: Settings, then the trip row.
    await tapAndSettle(tester, navDestination(_en.navSettings));
    final row = find.byKey(settingsTripActiveKey);
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text(_en.settingsTripActive('Japan')), findsOneWidget);
    await tapAndSettle(tester, row);

    // Assert: the briefing, composed with no connection.
    expect(find.byType(TripBriefingScreen), findsOneWidget);
    expect(find.text(_en.tripBriefingTitle('Japan')), findsOneWidget);
    expect(
      _subtitle(tester, tripHintRowKey(RestrictionId.wheat)),
      _en.tripHintPackagedOnly,
    );
    expect(
      _subtitle(tester, tripHintRowKey(RestrictionId.sesame)),
      _en.tripHintNotRegulated,
    );
    expect(find.byKey(tripLexiconRowKey('yakisoba')), findsOneWidget);
    expect(find.byKey(tripLexiconRowKey('goma')), findsOneWidget);
    expect(_safe.hasMatch(_allText(tester)), isFalse);

    // Act: the chef card, still offline.
    final chefCard = find.byKey(tripBriefingChefCardKey);
    await tester.ensureVisible(chefCard);
    await tester.pumpAndSettle();
    await tapAndSettle(tester, chefCard);

    // Assert: the profile's card in Japanese (#419), every line on screen.
    expect(find.byType(ChefCardScreen), findsOneWidget);
    final lines = ChefCardText.compose(
      _profile,
      hebrew: false,
      language: ChefCardLanguage.ja,
    );
    expect(lines, isNotEmpty);
    for (final line in lines) {
      expect(find.text(line), findsOneWidget, reason: line);
    }
    expect(find.text(_en.chefCardTranslatedNote), findsOneWidget);
    expect(_safe.hasMatch(_allText(tester)), isFalse);
    expect(fakes.connectivity.online, isFalse);

    // Act: back to Explore, and open the cached menu.
    await tapAndSettle(
      tester,
      find.byTooltip(
        MaterialLocalizations.of(tester.element(find.byType(ChefCardScreen)))
            .closeButtonTooltip,
      ),
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapAndSettle(tester, navDestination(_en.navExplore));
    await enterText(tester, _woltUrl);
    await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

    // Assert: yakisoba is a dish to ask about, read on the device.
    expect(find.text(_yakisoba.name), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(StateBadge),
        matching: find.text(_en.stateAskBadge.toUpperCase()),
      ),
      findsOneWidget,
    );
    // The trip never reached the classifier's options: they are exactly
    // the options of the same settings with no trip (D26 C1, C2).
    expect(fakes.classifier.optionCalls, hasLength(1));
    final stored = await fakes.settingsStore.read();
    expect(
      fakes.classifier.optionCalls.single,
      ClassificationOptions.fromSettings(
        stored.copyWith(tripDestination: null),
        bantoMode: true,
      ),
    );

    // Act: back from the menu; one tap in Settings switches trip mode off.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapAndSettle(tester, navDestination(_en.navSettings));
    final off = find.byKey(settingsTripOffKey);
    await tester.scrollUntilVisible(
      off,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tapAndSettle(tester, off);

    // Assert: no trip, stored; the briefing row is gone.
    expect((await fakes.settingsStore.read()).tripDestination, isNull);
    expect(find.byKey(settingsTripActiveKey), findsNothing);
    expect(find.byKey(settingsTripPickKey), findsOneWidget);
  });

  testWidgets('offline, a trip to France opens the chef card in French, '
      'English a tap away, and shares it as an image', (tester) async {
    // Setup: a trip to France, the phone offline.
    final fakes = FakeAppDependencies();
    await fakes.settingsStore.write(
      AppSettings(
        profile: _profile,
        onboardingSeen: true,
        disclosureSeen: true,
        tripDestination: TripDestination.france,
      ),
    );
    fakes.connectivity.online = false;
    await tester.pumpWidget(
      KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
    );
    await tester.pumpAndSettle();

    // Act: Settings, the trip row, the briefing's chef card.
    await tapAndSettle(tester, navDestination(_en.navSettings));
    final row = find.byKey(settingsTripActiveKey);
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tapAndSettle(tester, row);
    expect(find.text(_en.tripBriefingTitle('France')), findsOneWidget);
    expect(
      find.text(_en.tripBriefingChefCardLocalNote(_en.chefCardLanguageFrench)),
      findsOneWidget,
    );
    final chefCard = find.byKey(tripBriefingChefCardKey);
    await tester.ensureVisible(chefCard);
    await tester.pumpAndSettle();
    await tapAndSettle(tester, chefCard);

    // Assert: French by default, with the Annex II names and the
    // "translated by the app" line in the UI's English.
    final french = ChefCardText.compose(
      _profile,
      hebrew: false,
      language: ChefCardLanguage.fr,
    );
    for (final line in french) {
      expect(find.text(line), findsOneWidget, reason: line);
    }
    expect(french.join('\n'), contains('blé'));
    expect(french.join('\n'), contains('graines de sésame'));
    expect(find.text(_en.chefCardTranslatedNote), findsOneWidget);
    expect(_safe.hasMatch(_allText(tester)), isFalse);

    // Act: English, then French again.
    await tapAndSettle(tester, find.text(_en.settingsLanguageEnglish));
    expect(
      find.text(ChefCardText.compose(_profile, hebrew: false)[1]),
      findsOneWidget,
    );
    expect(find.text(_en.chefCardTranslatedNote), findsNothing);
    await tapAndSettle(tester, find.text(_en.chefCardLanguageFrench));
    expect(find.text(french[1]), findsOneWidget);

    // Act: share it as an image (#420).
    final shareImage = find.byKey(chefCardShareImageKey);
    await tester.ensureVisible(shareImage);
    await tester.pumpAndSettle();
    await tapAndSettle(tester, shareImage);
    expect(find.byType(ChefCardImageScreen), findsOneWidget);
    expect(find.text(ChefCardLanguage.fr.locale!.footer), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(chefCardImageShareKey));
      for (var i = 0; i < 300 && fakes.menuSharer.imageCalls.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();

    // Assert: PNG bytes went to the sharer; nothing went online.
    expect(fakes.menuSharer.imageCalls, hasLength(1));
    expect(fakes.menuSharer.imageCalls.single.sublist(0, 4), <int>[
      0x89,
      0x50,
      0x4E,
      0x47,
    ]);
    expect(fakes.connectivity.online, isFalse);
  });
}
