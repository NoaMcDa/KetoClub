// Trip mode's screens (Banto, ALG-13, issue #355): the Settings section
// with its destination picker and one-tap off, built only with
// `bantoMode: true`, and the pre-trip briefing page — regulation hints per
// strict entry, the local lexicon for the profile, the chef card, in
// English and Hebrew, never "safe".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/trip_destination.dart';
import 'package:ketoclub/screens/chef_card_screen.dart';
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/screens/settings_trip_section.dart';
import 'package:ketoclub/screens/trip_briefing_screen.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/locale_controller.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/state/theme_mode_controller.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_app_info.dart';
import '../fakes/fake_external_link_opener.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';

final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _he = AppLocalizationsHe();

/// "safe" as a word in English, "בטוח" anywhere in Hebrew.
final RegExp _safe = RegExp('(?<![A-Za-z])safe|בטוח', caseSensitive: false);

/// A profile holding [ids], in order.
DietaryProfile _profile(List<RestrictionId> ids) {
  var profile = DietaryProfile.empty;
  for (final id in ids) {
    profile = profile.withEntry(id);
  }
  return profile;
}

/// Pumps the real [SettingsScreen] over [store] with [bantoMode].
Future<void> _pumpSettings(
  WidgetTester tester,
  FakeSettingsStore store, {
  required bool bantoMode,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>(
            create: (_) => SettingsController(store, FakeMenuRepository()),
          ),
          ChangeNotifierProvider<LocaleController>(
            create: (_) => LocaleController(FakeSettingsStore()),
          ),
          ChangeNotifierProvider<ThemeModeController>(
            create: (_) => ThemeModeController(FakeSettingsStore()),
          ),
        ],
        child: SettingsScreen(
          appInfo: FakeAppInfo(),
          externalLinkOpener: FakeExternalLinkOpener(),
          bantoMode: bantoMode,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Pumps the [TripBriefingScreen] over a loaded controller for [settings],
/// in [locale], under a home route so it can be popped.
Future<FakeSettingsStore> _pumpBriefing(
  WidgetTester tester,
  AppSettings settings, {
  Locale locale = const Locale('en'),
}) async {
  final store = FakeSettingsStore(initial: settings);
  final controller = SettingsController(store, FakeMenuRepository());
  await controller.load();
  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsController>.value(
      value: controller,
      // A fresh app per pump, so a test may pump several briefings.
      child: MaterialApp(
        key: UniqueKey(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const TripBriefingScreen(),
                  ),
                ),
                child: const Icon(Icons.flight),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byIcon(Icons.flight));
  await tester.pumpAndSettle();
  return store;
}

/// Every [Text] on screen, joined.
String _allText(WidgetTester tester) => <String>[
  for (final text in tester.widgetList<Text>(find.byType(Text)))
    text.data ?? text.textSpan?.toPlainText() ?? '',
].join('\n');

/// The subtitle text of the [ListTile] keyed [key].
String _subtitle(WidgetTester tester, Key key) {
  final tile = tester.widget<ListTile>(find.byKey(key));
  return (tile.subtitle! as Text).data!;
}

void main() {
  group('Settings, trip mode section', () {
    testWidgets('is absent with bantoMode off, even with a stored trip', (
      tester,
    ) async {
      final store = FakeSettingsStore(
        initial: const AppSettings(tripDestination: TripDestination.japan),
      );

      await _pumpSettings(tester, store, bantoMode: false);

      expect(find.text(_en.settingsTrip), findsNothing);
      expect(find.byKey(settingsTripPickKey), findsNothing);
      expect(find.byKey(settingsTripActiveKey), findsNothing);
    });

    testWidgets('picks a destination, shows it, and switches off with one '
        'tap', (tester) async {
      final store = FakeSettingsStore();
      await _pumpSettings(tester, store, bantoMode: true);

      // Arrange: no trip yet.
      expect(find.text(_en.settingsTrip), findsOneWidget);
      expect(find.text(_en.settingsTripNote), findsOneWidget);
      final pick = find.byKey(settingsTripPickKey);
      await tester.ensureVisible(pick);
      await tester.tap(pick);
      await tester.pumpAndSettle();

      // Act: the picker lists every destination; pick Japan.
      expect(find.text(_en.tripPickerTitle), findsOneWidget);
      for (final destination in TripDestination.values) {
        expect(
          find.byKey(tripDestinationOptionKey(destination)),
          findsOneWidget,
        );
      }
      await tester.tap(
        find.byKey(tripDestinationOptionKey(TripDestination.japan)),
      );
      await tester.pumpAndSettle();

      // Assert: the trip is on and stored.
      expect(find.text(_en.settingsTripActive('Japan')), findsOneWidget);
      expect((await store.read()).tripDestination, TripDestination.japan);

      // Act: one tap switches it off.
      final off = find.byKey(settingsTripOffKey);
      await tester.ensureVisible(off);
      await tester.tap(off);
      await tester.pumpAndSettle();

      expect((await store.read()).tripDestination, isNull);
      expect(find.byKey(settingsTripPickKey), findsOneWidget);
      expect(find.byKey(settingsTripActiveKey), findsNothing);
    });

    testWidgets('changes the destination, marking the current one', (
      tester,
    ) async {
      final store = FakeSettingsStore(
        initial: const AppSettings(tripDestination: TripDestination.italy),
      );
      await _pumpSettings(tester, store, bantoMode: true);

      final change = find.byKey(settingsTripChangeKey);
      await tester.ensureVisible(change);
      await tester.tap(change);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(tripDestinationOptionKey(TripDestination.italy)),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(tripDestinationOptionKey(TripDestination.spain)),
      );
      await tester.pumpAndSettle();

      expect((await store.read()).tripDestination, TripDestination.spain);
      expect(find.text(_en.settingsTripActive('Spain')), findsOneWidget);
    });

    testWidgets('dismissing the picker changes nothing', (tester) async {
      final store = FakeSettingsStore();
      await _pumpSettings(tester, store, bantoMode: true);
      final pick = find.byKey(settingsTripPickKey);
      await tester.ensureVisible(pick);
      await tester.tap(pick);
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect((await store.read()).tripDestination, isNull);
      expect(store.writeCallCount, 0);
    });

    testWidgets('the active row opens the briefing', (tester) async {
      final store = FakeSettingsStore(
        initial: AppSettings(
          tripDestination: TripDestination.japan,
          profile: _profile(<RestrictionId>[RestrictionId.wheat]),
        ),
      );
      await _pumpSettings(tester, store, bantoMode: true);

      final row = find.byKey(settingsTripActiveKey);
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.byType(TripBriefingScreen), findsOneWidget);
      expect(find.text(_en.tripBriefingTitle('Japan')), findsOneWidget);
    });
  });

  group('the briefing page', () {
    testWidgets('gives one hint per strict entry, telling packaged-food '
        'rules from no rule at all', (tester) async {
      await _pumpBriefing(
        tester,
        AppSettings(
          tripDestination: TripDestination.japan,
          profile: _profile(<RestrictionId>[
            RestrictionId.sesame,
            RestrictionId.wheat,
            RestrictionId.lactose,
            RestrictionId.keto,
          ]),
        ),
      );

      expect(find.text(_en.tripBriefingRulesSection), findsOneWidget);
      expect(
        _subtitle(tester, tripHintRowKey(RestrictionId.wheat)),
        _en.tripHintPackagedOnly,
      );
      expect(
        _subtitle(tester, tripHintRowKey(RestrictionId.sesame)),
        _en.tripHintNotRegulated,
      );
      // Flexible entries and keto get no hint.
      expect(find.byKey(tripHintRowKey(RestrictionId.lactose)), findsNothing);
      expect(find.byKey(tripHintRowKey(RestrictionId.keto)), findsNothing);
      // Taxonomy order: wheat before sesame.
      expect(
        tester.getTopLeft(find.byKey(tripHintRowKey(RestrictionId.wheat))).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(tripHintRowKey(RestrictionId.sesame)))
              .dy,
        ),
      );
    });

    testWidgets('in the UK a listed allergen is a restaurant duty, still '
        'asked; the US names the large chains', (tester) async {
      await _pumpBriefing(
        tester,
        AppSettings(
          tripDestination: TripDestination.unitedKingdom,
          profile: _profile(<RestrictionId>[RestrictionId.sesame]),
        ),
      );
      expect(
        _subtitle(tester, tripHintRowKey(RestrictionId.sesame)),
        _en.tripHintRestaurantMustTell,
      );

      await _pumpBriefing(
        tester,
        AppSettings(
          tripDestination: TripDestination.unitedStates,
          profile: _profile(<RestrictionId>[RestrictionId.sesame]),
        ),
      );
      expect(
        _subtitle(tester, tripHintRowKey(RestrictionId.sesame)),
        _en.tripHintPackagedOnlyLargeChains,
      );
    });

    testWidgets("lists the local dishes that hide the profile's "
        'restrictions, with what each may hide', (tester) async {
      await _pumpBriefing(
        tester,
        AppSettings(
          tripDestination: TripDestination.japan,
          profile: _profile(<RestrictionId>[RestrictionId.sesame]),
        ),
      );

      expect(find.text(_en.tripBriefingLexiconSection), findsOneWidget);
      expect(find.byKey(tripLexiconRowKey('furikake')), findsOneWidget);
      expect(find.byKey(tripLexiconRowKey('goma')), findsOneWidget);
      expect(find.byKey(tripLexiconRowKey('soba')), findsNothing);
      expect(
        _subtitle(tester, tripLexiconRowKey('goma')),
        contains(_en.tripBriefingHides('Sesame')),
      );
      expect(find.text('goma · gomadare'), findsOneWidget);
    });

    testWidgets('a keto-only profile sees both empty states', (tester) async {
      await _pumpBriefing(
        tester,
        AppSettings(
          tripDestination: TripDestination.france,
          profile: _profile(<RestrictionId>[RestrictionId.keto]),
        ),
      );

      expect(find.byKey(tripBriefingRulesEmptyKey), findsOneWidget);
      expect(find.byKey(tripBriefingLexiconEmptyKey), findsOneWidget);
    });

    testWidgets('reads in Hebrew, with Hebrew glosses and names', (
      tester,
    ) async {
      await _pumpBriefing(
        tester,
        AppSettings(
          tripDestination: TripDestination.germany,
          profile: _profile(<RestrictionId>[RestrictionId.mustard]),
        ),
        locale: const Locale('he'),
      );

      expect(find.text(_he.tripBriefingTitle('גרמניה')), findsOneWidget);
      expect(
        _subtitle(tester, tripHintRowKey(RestrictionId.mustard)),
        _he.tripHintRestaurantMustTell,
      );
      final senf = _subtitle(tester, tripLexiconRowKey('Senf'));
      expect(senf, startsWith('חרדל:'));
      expect(senf, contains(_he.tripBriefingHides('חרדל')));
    });

    testWidgets('never says safe, in either language', (tester) async {
      for (final locale in <Locale>[const Locale('en'), const Locale('he')]) {
        for (final destination in TripDestination.values) {
          await _pumpBriefing(
            tester,
            AppSettings(
              tripDestination: destination,
              profile: _profile(<RestrictionId>[
                RestrictionId.peanuts,
                RestrictionId.gluten,
                RestrictionId.fish,
                RestrictionId.vegan,
              ]),
            ),
            locale: locale,
          );
          expect(
            _safe.hasMatch(_allText(tester)),
            isFalse,
            reason: '${destination.name} in $locale',
          );
        }
      }
    });

    testWidgets('opens the chef card for the profiles menus are read for', (
      tester,
    ) async {
      await _pumpBriefing(
        tester,
        AppSettings(
          tripDestination: TripDestination.japan,
          profile: _profile(<RestrictionId>[RestrictionId.sesame]),
        ),
      );

      final button = find.byKey(tripBriefingChefCardKey);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      final card = tester.widget<ChefCardScreen>(find.byType(ChefCardScreen));
      expect(card.profile.contains(RestrictionId.sesame), isTrue);
      expect(find.byKey(chefCardEmptyKey), findsNothing);
    });

    testWidgets('turning the trip off from the briefing clears it and goes '
        'back', (tester) async {
      final store = await _pumpBriefing(
        tester,
        const AppSettings(tripDestination: TripDestination.spain),
      );

      final off = find.byKey(tripBriefingOffKey);
      await tester.ensureVisible(off);
      await tester.tap(off);
      await tester.pumpAndSettle();

      expect((await store.read()).tripDestination, isNull);
      expect(find.byType(TripBriefingScreen), findsNothing);
    });
  });
}
