// The chef card in the trip's language (Banto, issue #419) and shared as
// an image (issue #420): the language toggle offers the destination's
// language and opens in it while a trip is on, a translated card carries
// the "translated by the app" line in the UI's language, and "Share as
// image" renders the card, light, to PNG bytes for the sharer.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/trip_destination.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/chef_card_image_screen.dart';
import 'package:ketoclub/screens/chef_card_screen.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/utils/allergens/chef_card_locales.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/utils/allergens/group_chef_card.dart';
import 'package:ketoclub/widgets/chef_card_image.dart';

import '../fakes/fake_menu_sharer.dart';

final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _he = AppLocalizationsHe();

/// The eight bytes every PNG file starts with.
const List<int> _pngSignature = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

final DietaryProfile _profile = DietaryProfile.empty
    .withEntry(RestrictionId.sesame)
    .withEntry(RestrictionId.lactose);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

/// The labels of the language toggle's segments, in order.
List<String> _segments(WidgetTester tester) => <String>[
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(chefCardLanguageToggleKey),
      matching: find.byType(Text),
    ),
  ))
    text.data!,
];

/// Taps the page's Share button and waits, in real time, for the image
/// to be rendered and handed to [sharer].
Future<void> _shareImage(WidgetTester tester, FakeMenuSharer sharer) async {
  await tester.runAsync(() async {
    await tester.tap(find.byKey(chefCardImageShareKey));
    for (var i = 0; i < 200 && sharer.imageCalls.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  group('ChefCardScreen in the trip language (#419)', () {
    testWidgets('a trip to France offers French beside Hebrew and English '
        'and opens in it, with the translated line', (tester) async {
      await _pump(
        tester,
        ChefCardScreen(profile: _profile, trip: TripDestination.france),
      );

      expect(_segments(tester), <String>[
        _en.chefCardLanguageFrench,
        _en.settingsLanguageHebrew,
        _en.settingsLanguageEnglish,
      ]);
      final french = ChefCardText.compose(
        _profile,
        hebrew: false,
        language: ChefCardLanguage.fr,
      );
      for (final line in french) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      expect(french[1], contains('graines de sésame'));
      expect(find.byKey(chefCardTranslatedNoteKey), findsOneWidget);
      expect(find.text(_en.chefCardTranslatedNote), findsOneWidget);
    });

    testWidgets('switching to English drops the translated line, and back '
        'to French brings it', (tester) async {
      await _pump(
        tester,
        ChefCardScreen(profile: _profile, trip: TripDestination.italy),
      );

      await tester.tap(find.text(_en.settingsLanguageEnglish));
      await tester.pumpAndSettle();
      for (final line in ChefCardText.compose(_profile, hebrew: false)) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      expect(find.byKey(chefCardTranslatedNoteKey), findsNothing);

      await tester.tap(find.text(_en.chefCardLanguageItalian));
      await tester.pumpAndSettle();
      expect(find.text(ChefCardLanguage.it.locale!.intro), findsOneWidget);
      expect(find.byKey(chefCardTranslatedNoteKey), findsOneWidget);
    });

    testWidgets('under a Hebrew app the translated line is Hebrew, the card '
        'Japanese', (tester) async {
      await _pump(
        tester,
        ChefCardScreen(profile: _profile, trip: TripDestination.japan),
        locale: const Locale('he'),
      );

      expect(_segments(tester).first, _he.chefCardLanguageJapanese);
      expect(find.text(ChefCardLanguage.ja.locale!.intro), findsOneWidget);
      expect(find.text(_he.chefCardTranslatedNote), findsOneWidget);
    });

    for (final trip in <TripDestination?>[
      null,
      TripDestination.israel,
      TripDestination.unitedStates,
      TripDestination.unitedKingdom,
    ]) {
      testWidgets('${trip?.name ?? 'no trip'}: Hebrew and English only, no '
          'translated line', (tester) async {
        await _pump(tester, ChefCardScreen(profile: _profile, trip: trip));

        expect(_segments(tester), <String>[
          _en.settingsLanguageHebrew,
          _en.settingsLanguageEnglish,
        ]);
        expect(
          find.text(ChefCardText.compose(_profile, hebrew: false).first),
          findsOneWidget,
        );
        expect(find.byKey(chefCardTranslatedNoteKey), findsNothing);
      });
    }

    testWidgets('a group card opens in German during a trip to Germany', (
      tester,
    ) async {
      final people = <NamedProfile>[
        NamedProfile(id: 'me', name: '', profile: _profile),
        NamedProfile(
          id: 'dana',
          name: 'Dana',
          profile: DietaryProfile.empty.withEntry(RestrictionId.vegan),
        ),
      ];
      await _pump(
        tester,
        ChefCardScreen(
          profile: _profile,
          people: people,
          trip: TripDestination.germany,
        ),
      );

      final german = ChefCardLanguage.de.locale!;
      expect(find.text(german.groupIntro), findsOneWidget);
      expect(find.text(german.me), findsOneWidget);
      expect(find.byKey(chefCardTranslatedNoteKey), findsOneWidget);
    });

    testWidgets("a dish card opens in Spanish, with the evaluator's English "
        'questions and English allergy note', (tester) async {
      const dish = Dish(
        id: 'd',
        name: 'Ensalada con sésamo',
        description: '',
        price: 12,
        options: <DishOption>[],
      );
      final menu = Menu(
        venueRef: const VenueRef(source: MenuSource.wolt, platformId: 'v'),
        currency: 'EUR',
        fetchedAt: DateTime.utc(2026),
        categories: const <MenuCategory>[
          MenuCategory(id: 'c', name: 'Ensaladas', dishes: <Dish>[dish]),
        ],
      );
      await _pump(
        tester,
        ChefCardScreen(
          profile: _profile,
          dish: dish,
          analysed: const AnalysedDish(
            dishId: 'd',
            name: 'Ensalada con sésamo',
            verdict: DishVerdict.orderAsIs,
            why: '',
          ),
          menu: menu,
          trip: TripDestination.spain,
        ),
      );

      final spanish = ChefCardLanguage.es.locale!;
      expect(find.text(spanish.intro), findsOneWidget);
      expect(
        find.text(spanish.dishLine.replaceAll('{dish}', 'Ensalada con sésamo')),
        findsOneWidget,
      );
      final note = tester.widget<Text>(find.byKey(chefCardAllergyNoteKey));
      expect(note.data, startsWith('I have an allergy to sesame.'));
    });
  });

  group('ChefCardScreen, Share as image (#420)', () {
    for (final (locale, hebrew) in <(Locale, bool)>[
      (const Locale('en'), false),
      (const Locale('he'), true),
    ]) {
      testWidgets('${locale.languageCode}: the boundary renders and the '
          'sharer receives PNG bytes', (tester) async {
        final sharer = FakeMenuSharer();
        await _pump(
          tester,
          ChefCardScreen(profile: _profile, menuSharer: sharer),
          locale: locale,
        );
        final l10n = hebrew ? _he : _en;

        await tester.ensureVisible(find.byKey(chefCardShareImageKey));
        await tester.tap(find.byKey(chefCardShareImageKey));
        await tester.pumpAndSettle();

        expect(find.byType(ChefCardImageScreen), findsOneWidget);
        expect(find.byKey(chefCardImageBoundaryKey), findsOneWidget);
        final language = ChefCardLanguage.of(hebrew: hebrew);
        expect(find.text(ChefCardText.imageFooter(language)), findsOneWidget);
        for (final line in ChefCardText.compose(_profile, hebrew: hebrew)) {
          expect(
            find.descendant(
              of: find.byType(ChefCardImage),
              matching: find.text(line),
            ),
            findsOneWidget,
            reason: line,
          );
        }

        await _shareImage(tester, sharer);

        final call = sharer.imageCalls.single;
        expect(call.png.length, greaterThan(_pngSignature.length));
        expect(call.png.sublist(0, 8), _pngSignature);
        expect(call.subject, l10n.chefCardTitle);
        expect(
          call.fallbackText,
          ChefCardText.asText(ChefCardText.compose(_profile, hebrew: hebrew)),
        );
        expect(sharer.shareCalls, isEmpty);
      });
    }

    testWidgets('the image is the card in the language shown: French on a '
        'trip to France, with the French footer', (tester) async {
      final sharer = FakeMenuSharer();
      await _pump(
        tester,
        ChefCardScreen(
          profile: _profile,
          trip: TripDestination.france,
          menuSharer: sharer,
        ),
      );

      await tester.ensureVisible(find.byKey(chefCardShareImageKey));
      await tester.tap(find.byKey(chefCardShareImageKey));
      await tester.pumpAndSettle();

      final image = tester.widget<ChefCardImage>(find.byType(ChefCardImage));
      expect(image.language, ChefCardLanguage.fr);
      expect(find.text(ChefCardLanguage.fr.locale!.footer), findsOneWidget);
    });

    testWidgets('the image is drawn light under a dark app', (tester) async {
      await _pump(
        tester,
        ChefCardScreen(profile: _profile, menuSharer: FakeMenuSharer()),
        themeMode: ThemeMode.dark,
      );
      await tester.ensureVisible(find.byKey(chefCardShareImageKey));
      await tester.tap(find.byKey(chefCardShareImageKey));
      await tester.pumpAndSettle();

      expect(
        Theme.of(tester.element(find.byType(ChefCardImageScreen))).brightness,
        Brightness.dark,
      );
      final inside = tester.element(
        find.descendant(
          of: find.byType(ChefCardImage),
          matching: find.byType(Material),
        ),
      );
      expect(Theme.of(inside).brightness, Brightness.light);
    });

    testWidgets('a group card is shared as its sections', (tester) async {
      final people = <NamedProfile>[
        NamedProfile(id: 'me', name: '', profile: _profile),
        NamedProfile(
          id: 'noa',
          name: 'Noa',
          profile: DietaryProfile.empty.withEntry(RestrictionId.peanuts),
        ),
      ];
      final sharer = FakeMenuSharer();
      await _pump(
        tester,
        ChefCardScreen(profile: _profile, people: people, menuSharer: sharer),
      );
      await tester.ensureVisible(find.byKey(chefCardShareImageKey));
      await tester.tap(find.byKey(chefCardShareImageKey));
      await tester.pumpAndSettle();

      final image = tester.widget<ChefCardImage>(find.byType(ChefCardImage));
      expect(
        GroupChefCardText.asText(image.group!),
        GroupChefCardText.asText(
          GroupChefCardText.compose(people, hebrew: false),
        ),
      );
      await _shareImage(tester, sharer);
      expect(sharer.imageCalls.single.png.sublist(0, 8), _pngSignature);
    });

    testWidgets('where files cannot be shared, the text is shared and a '
        'snackbar says so', (tester) async {
      final sharer = FakeMenuSharer()..canShareFiles = false;
      await _pump(
        tester,
        ChefCardScreen(profile: _profile, menuSharer: sharer),
      );
      await tester.ensureVisible(find.byKey(chefCardShareImageKey));
      await tester.tap(find.byKey(chefCardShareImageKey));
      await tester.pumpAndSettle();

      await _shareImage(tester, sharer);

      expect(
        sharer.shareCalls.single.text,
        ChefCardText.asText(ChefCardText.compose(_profile, hebrew: false)),
      );
      expect(find.text(_en.chefCardImageTextFallback), findsOneWidget);
    });

    testWidgets('no sharer, no "Share as image"; an empty card has none '
        'either', (tester) async {
      await _pump(tester, ChefCardScreen(profile: _profile));
      expect(find.byKey(chefCardShareImageKey), findsNothing);

      await _pump(
        tester,
        ChefCardScreen(
          profile: DietaryProfile.empty,
          menuSharer: FakeMenuSharer(),
        ),
      );
      expect(find.byKey(chefCardShareImageKey), findsNothing);
    });
  });
}
