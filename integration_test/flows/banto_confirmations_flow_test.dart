// Flow test (FLOW_TEST_CONVENTIONS.md; Banto, ALG-14, issue #356): a
// peanut profile opens a menu whose nut cake is to ask about; afterwards
// the Recent tab offers "Did you ask the staff?", the person records that
// the staff said there are no peanuts, and the next time the menu opens
// the cake shows that answer with its date — and, for an allergen, is
// still to ask about. The effect spans the menu, Recent, the prompt and
// the menu again, which is why this is a flow and not a widget test.
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
import 'package:ketoclub/models/dish_confirmation.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/confirmation_controller.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/widgets/confirmation_sheet.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/status_badge.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Wolt venue page the user pastes.
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/banto-confirm-venue';

/// The [VenueRef] [_woltUrl] resolves to.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'banto-confirm-venue',
);

/// The nut cake: אגוזים reads as peanuts suspected, so a peanut profile
/// asks about it.
const Dish _nutCake = Dish(
  id: 'cake',
  name: 'עוגת אגוזים',
  description: '',
  price: 30,
  options: <DishOption>[],
);

/// The menu the repository serves for [_ref].
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[
    MenuCategory(id: 'c1', name: 'קינוחים', dishes: <Dish>[_nutCake]),
  ],
);

/// The cake green from the language model, as a keto-only analysis is.
final MenuAnalysed _analysis = MenuAnalysed(
  dishes: const <AnalysedDish>[
    AnalysedDish(
      dishId: 'cake',
      name: 'עוגת אגוזים',
      verdict: DishVerdict.orderAsIs,
      why: 'Fits',
    ),
  ],
  unclassified: const <String>[],
  engine: const LlmEngine(model: 'flow-model'),
  analysedAt: DateTime.utc(2026),
);

/// The state pill reading [label].
Finder _pill(String label) => find.descendant(
  of: find.byType(StateBadge),
  matching: find.text(label.toUpperCase()),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Banto post-meal confirmation flow', () {
    testWidgets('Recent asks, the staff answer is kept, and the menu shows '
        'it on reopen, still to ask', (tester) async {
      // Setup: a peanut profile, past the onboarding.
      final fakes = FakeAppDependencies();
      await fakes.settingsStore.write(
        AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.peanuts),
          onboardingSeen: true,
        ),
      );
      fakes.repository.stub(_ref, MenuFetched(menu: _menu));
      fakes.classifier.respondWith(_analysis);
      await tester.pumpWidget(
        KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
      );
      await tester.pumpAndSettle();

      // Act: open the venue from a pasted link.
      await enterText(tester, _woltUrl);
      await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

      // Assert: the cake is to ask about; no staff answer yet.
      expect(find.text(_nutCake.name), findsOneWidget);
      expect(_pill(_en.stateAskBadge), findsOneWidget);
      final day = confirmationDay(fakes.clock.now());
      expect(find.textContaining(_en.concernDeniedOn(day)), findsNothing);

      // Act: back to Explore, then to Recent.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapAndSettle(tester, navDestination(_en.navSaved));

      // Assert: the menu opened with a strict entry offers the prompt.
      expect(find.text(_en.confirmPromptOpen), findsOneWidget);

      // Act: open it and record that the staff said there are no peanuts.
      await tapAndSettle(tester, find.text(_en.confirmPromptOpen));
      final peanuts = restrictionFor(RestrictionId.peanuts).nameEn;
      expect(
        find.text(_en.confirmPromptQuestion(peanuts, _nutCake.name)),
        findsOneWidget,
      );
      await tapAndSettle(
        tester,
        find.byKey(confirmAnswerKey('cake', 0, ConfirmationAnswer.absent)),
      );
      await tapAndSettle(tester, find.byKey(confirmSaveKey));

      // Assert: saved on the device, with the visit history.
      expect(find.text(_en.confirmSaved), findsOneWidget);
      final entry = await fakes.visitHistory.read(_ref);
      expect(entry?.confirmations.single.polarity, ConfirmationPolarity.absent);

      // Act: reopen the menu from its Recent row.
      await tapAndSettle(tester, find.text(_ref.platformId));

      // Assert: the cake carries the dated answer and, for an allergen,
      // is still to ask about — a denial never goes below suspected.
      expect(find.text(_nutCake.name), findsOneWidget);
      expect(find.textContaining(_en.concernDeniedOn(day)), findsOneWidget);
      expect(_pill(_en.stateAskBadge), findsOneWidget);

      // Act: the Why sheet, once the "saved" snack bar has gone.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(dishWhyKey));
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.byKey(dishWhyKey));

      // Assert: it says when the staff were asked.
      expect(find.text(_en.whySheetTitle), findsOneWidget);
      expect(find.text(_en.whyDeniedOn(day)), findsOneWidget);
    });
  });
}
