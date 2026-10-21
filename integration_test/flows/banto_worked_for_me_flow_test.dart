// Flow test (FLOW_TEST_CONVENTIONS.md; Banto, issue #412): a sesame profile
// opens a tahini salad; afterwards the Recent tab offers "Did you ask the
// staff?", the person records that the staff said there is no sesame, and
// the one-line offer "This place worked for me" follows; one tap marks the
// venue. The Recent tab then carries the tag and a "Worked for me" chip that
// filters the list to the venue, and the venue's menu shows the tag in its
// header. The effect spans two menus, Recent, the prompt and the menu again,
// which is why this is a flow and not a widget test.
//
// The whole app is pumped with `bantoMode: true`, so it runs under
// `flutter test` with no `--dart-define`.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/app.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/menu_screen.dart';
import 'package:ketoclub/screens/saved_screen.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/confirmation_controller.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/widgets/confirmation_sheet.dart';
import 'package:ketoclub/widgets/worked_for_tag.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

const String _salmonUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/banto-other-venue';
const String _saladUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/banto-worked-venue';

const VenueRef _salmonRef = VenueRef(
  source: MenuSource.wolt,
  platformId: 'banto-other-venue',
);
const VenueRef _saladRef = VenueRef(
  source: MenuSource.wolt,
  platformId: 'banto-worked-venue',
);

const Dish _salad = Dish(
  id: 'salad',
  name: 'סלט חצילים עם טחינה',
  description: '',
  price: 40,
  options: <DishOption>[],
);

const Dish _salmon = Dish(
  id: 'salmon',
  name: 'Grilled salmon',
  description: '',
  price: 90,
  options: <DishOption>[],
);

Menu _menuOf(VenueRef ref, Dish dish) => Menu(
  venueRef: ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(id: 'c1', name: 'Mains', dishes: <Dish>[dish]),
  ],
);

/// Both dishes green from the language model, as a keto-only analysis is.
MenuAnalysed _green() => MenuAnalysed(
  dishes: <AnalysedDish>[
    for (final dish in const <Dish>[_salad, _salmon])
      AnalysedDish(
        dishId: dish.id,
        name: dish.name,
        verdict: DishVerdict.orderAsIs,
        why: 'Fits',
      ),
  ],
  unclassified: const <String>[],
  engine: const LlmEngine(model: 'flow-model'),
  analysedAt: DateTime.utc(2026),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Banto "Worked for me" flow', () {
    testWidgets('no sesame, one tap marks the venue, Recent filters to it '
        'and the menu header carries the tag', (tester) async {
      // Setup: a sesame profile, past the onboarding, two venues.
      final fakes = FakeAppDependencies();
      await fakes.settingsStore.write(
        AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
          onboardingSeen: true,
        ),
      );
      fakes.repository
        ..stub(_saladRef, MenuFetched(menu: _menuOf(_saladRef, _salad)))
        ..stub(_salmonRef, MenuFetched(menu: _menuOf(_salmonRef, _salmon)));
      fakes.classifier.respondWith(_green());
      await tester.pumpWidget(
        KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
      );
      await tester.pumpAndSettle();

      // Act: open the tahini salad's venue, then go to Recent.
      await enterText(tester, _saladUrl);
      await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));
      expect(find.byKey(workedForTagKey), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapAndSettle(tester, navDestination(_en.navSaved));

      // Assert: nothing is marked, so no chip yet.
      expect(find.byKey(savedWorkedChipKey), findsNothing);

      // Act: the staff said there is no sesame.
      await tapAndSettle(tester, find.text(_en.confirmPromptOpen));
      final sesame = restrictionFor(RestrictionId.sesame).nameEn;
      expect(
        find.text(_en.confirmPromptQuestion(sesame, _salad.name)),
        findsOneWidget,
      );
      await tapAndSettle(
        tester,
        find.byKey(confirmAnswerKey('salad', 0, ConfirmationAnswer.absent)),
      );
      await tapAndSettle(tester, find.byKey(confirmSaveKey));

      // Assert: the one strict concern was answered, so the offer follows.
      expect(find.text(_en.workedOffer), findsOneWidget);

      // Act: one tap marks the venue.
      await tapAndSettle(tester, find.byKey(workedOfferKey));

      // Assert: on the device, tagged, and the chip is there.
      expect((await fakes.visitHistory.read(_saladRef))?.workedFor, <String>[
        'Me',
      ]);
      expect(find.byKey(workedForTagKey), findsOneWidget);
      expect(find.byKey(savedWorkedChipKey), findsOneWidget);

      // Act: open the other venue, so Recent lists two.
      await tapAndSettle(tester, navDestination(_en.navExplore));
      await enterText(tester, _salmonUrl);
      await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));
      expect(find.byKey(workedForTagKey), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapAndSettle(tester, navDestination(_en.navSaved));
      expect(find.text(_salmonRef.platformId), findsOneWidget);
      expect(find.text(_saladRef.platformId), findsOneWidget);

      // Act: the chip narrows the list to the marked venue.
      await tapAndSettle(tester, find.byKey(savedWorkedChipKey));

      // Assert: a filter only; the unmarked venue is hidden, not ranked.
      expect(find.text(_saladRef.platformId), findsOneWidget);
      expect(find.text(_salmonRef.platformId), findsNothing);

      // Act: open the marked venue.
      await tapAndSettle(tester, find.text(_saladRef.platformId));

      // Assert: the menu header shows the tag.
      expect(find.text(_salad.name), findsOneWidget);
      expect(find.byKey(workedForTagKey), findsOneWidget);
      expect(find.text(_en.workedChip), findsOneWidget);

      // Act: unmark it from the header's overflow.
      await tapAndSettle(tester, find.byTooltip(_en.actionMoreMenuOptions));
      expect(find.text(_en.workedUnmark), findsOneWidget);
      await tapAndSettle(tester, find.byKey(menuWorkedToggleKey));

      // Assert: the tag and the stored mark are gone.
      expect(find.byKey(workedForTagKey), findsNothing);
      expect((await fakes.visitHistory.read(_saladRef))?.workedFor, isEmpty);
    });
  });
}
