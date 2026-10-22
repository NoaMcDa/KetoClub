// The briefing's chef card in the local language (Banto, issue #419): for
// a trip to France, Italy, Spain, Germany or Japan the note under the
// button names the language the card opens in, and the card opens in it;
// for Israel, the US and the UK there is no such note and the card stays
// Hebrew or English. Nothing says the local card is "not built yet".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/trip_destination.dart';
import 'package:ketoclub/screens/chef_card_screen.dart';
import 'package:ketoclub/screens/trip_briefing_screen.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/utils/allergens/chef_card_locales.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';

final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _he = AppLocalizationsHe();

final DietaryProfile _profile = DietaryProfile.empty.withEntry(
  RestrictionId.peanuts,
);

/// Pumps the briefing for a trip to [trip] in [locale].
Future<void> _pumpBriefing(
  WidgetTester tester,
  TripDestination trip, {
  Locale locale = const Locale('en'),
}) async {
  final controller = SettingsController(
    FakeSettingsStore(
      initial: AppSettings(profile: _profile, tripDestination: trip),
    ),
    FakeMenuRepository(),
  );
  await controller.load();
  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsController>.value(
      value: controller,
      child: MaterialApp(
        key: UniqueKey(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: const TripBriefingScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openCard(WidgetTester tester) async {
  final button = find.byKey(tripBriefingChefCardKey);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  const local = <TripDestination, ChefCardLanguage>{
    TripDestination.france: ChefCardLanguage.fr,
    TripDestination.italy: ChefCardLanguage.it,
    TripDestination.spain: ChefCardLanguage.es,
    TripDestination.germany: ChefCardLanguage.de,
    TripDestination.japan: ChefCardLanguage.ja,
  };

  for (final MapEntry(key: trip, value: language) in local.entries) {
    testWidgets('${trip.name}: the note names the language and the card '
        'opens in it', (tester) async {
      await _pumpBriefing(tester, trip);

      expect(
        find.text(
          _en.tripBriefingChefCardLocalNote(
            chefCardLanguageName(_en, language),
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(_en.tripBriefingChefCardNote), findsOneWidget);

      await _openCard(tester);
      final card = tester.widget<ChefCardScreen>(find.byType(ChefCardScreen));
      expect(card.trip, trip);
      expect(
        find.text(
          ChefCardText.compose(_profile, hebrew: false, language: language)[1],
        ),
        findsOneWidget,
      );
      expect(find.byKey(chefCardTranslatedNoteKey), findsOneWidget);
    });
  }

  for (final trip in <TripDestination>[
    TripDestination.israel,
    TripDestination.unitedStates,
    TripDestination.unitedKingdom,
  ]) {
    testWidgets('${trip.name}: no local-language note; the card stays '
        'English', (tester) async {
      await _pumpBriefing(tester, trip);

      expect(find.byKey(tripBriefingChefCardLocalNoteKey), findsNothing);
      await _openCard(tester);
      expect(
        find.text(ChefCardText.compose(_profile, hebrew: false)[1]),
        findsOneWidget,
      );
      expect(find.byKey(chefCardTranslatedNoteKey), findsNothing);
    });
  }

  testWidgets('in Hebrew the note names the language in Hebrew, and says '
      'nothing is missing', (tester) async {
    await _pumpBriefing(
      tester,
      TripDestination.france,
      locale: const Locale('he'),
    );

    expect(
      find.text(_he.tripBriefingChefCardLocalNote('צרפתית')),
      findsOneWidget,
    );
    expect(_he.tripBriefingChefCardNote, isNot(contains('עדיין לא')));
    expect(_en.tripBriefingChefCardNote, isNot(contains('not available')));
  });
}
