// Flow test (FLOW_TEST_CONVENTIONS.md; Banto, ALG-08b, issue #350): a
// profile with sesame, picked on the first-run onboarding, opens a Hebrew
// menu; the eggplant salad (סלט חצילים: sesame suspected) is a dish to
// ask about; its waiter row opens the Waiter Card, which lists the dish's
// question, and the Waiter Card's "Chef card" opens the chef card for that
// dish, in Hebrew although the app is in English: the sesame line, the
// dish as printed, its question, and — the tahini salad on the same menu
// being a sesame signal (ALG-07) — the cross-contact line. The effect
// spans the onboarding, Explore, the menu, the Waiter Card and the chef
// card, which is why this is a flow and not a widget test.
//
// A second flow checks two people (sesame and keto): the dish card then has
// a section each, with the question under the sesame person's.
//
// The whole app is pumped with `bantoMode: true`, so it runs under
// `flutter test` with no `--dart-define`. The classifier answers every
// dish green from the language model: the questions are filled on the
// device from the profile's concerns, never sent.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/app.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/chef_card_screen.dart';
import 'package:ketoclub/screens/restriction_onboarding_screen.dart';
import 'package:ketoclub/screens/waiter_card_sheet.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/widgets/group_chef_card_view.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Wolt venue page the user pastes.
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/banto-chef-card-venue';

/// The [VenueRef] [_woltUrl] resolves to.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'banto-chef-card-venue',
);

/// A dish named [name] with [id].
Dish _dish(String id, String name) => Dish(
  id: id,
  name: name,
  description: '',
  price: 38,
  options: const <DishOption>[],
);

/// The eggplant salad: sesame suspected (a hidden source), so "ask".
final Dish _eggplant = _dish('eggplant', 'סלט חצילים');

/// The tahini salad: sesame stated, so "avoid", and a sesame signal.
final Dish _tahini = _dish('tahini', 'סלט עם טחינה');

/// The menu the repository serves for [_ref].
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(id: 'c1', name: 'סלטים', dishes: <Dish>[_eggplant, _tahini]),
  ],
);

/// Every dish green, from the language model.
final MenuAnalysed _analysis = MenuAnalysed(
  dishes: <AnalysedDish>[
    for (final dish in _menu.allDishes)
      AnalysedDish(
        dishId: dish.id,
        name: dish.name,
        verdict: DishVerdict.orderAsIs,
        why: 'Nothing starchy.',
      ),
  ],
  unclassified: const <String>[],
  engine: const LlmEngine(model: 'flow-model'),
  analysedAt: DateTime.utc(2026),
);

/// The eggplant salad's question, in the menu's language.
const String _question = "בתפריט כתוב 'סלט חצילים' — האם יש בזה שומשום?";

/// The sesame line of the chef card, in Hebrew.
const String _sesameLine =
    'יש לי אלרגיה לשומשום — נא לבדוק כל מרכיב, כולל רטבים, שמנים וקישוטים.';

/// "safe" as a word in English, "בטוח" anywhere in Hebrew.
final RegExp _safe = RegExp('(?<![A-Za-z])safe|בטוח', caseSensitive: false);

/// The loaded menu's list (see menu_display_flow_test.dart).
final Finder _menuList = find
    .descendant(
      of: find.descendant(
        of: find.byType(RefreshIndicator),
        matching: find.byType(ListView),
      ),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Banto chef card flow', () {
    testWidgets('a sesame profile opens the Hebrew chef card of a dish from '
        'its Waiter Card', (tester) async {
      // Setup
      final fakes = FakeAppDependencies();
      fakes.repository.stub(_ref, MenuFetched(menu: _menu));
      fakes.classifier.respondWith(_analysis);
      await tester.pumpWidget(
        KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
      );
      await tester.pumpAndSettle();

      // Act: pick sesame on the first-run onboarding.
      final chip = find.byKey(
        restrictionOnboardingChipKey(RestrictionId.sesame),
      );
      await tester.scrollUntilVisible(
        chip,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tapAndSettle(tester, chip);
      await tester.scrollUntilVisible(
        find.byKey(restrictionOnboardingContinueKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tapAndSettle(tester, find.byKey(restrictionOnboardingContinueKey));

      // Act: on Explore, paste the link and open the venue.
      await enterText(tester, _woltUrl);
      await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

      // Act: open the eggplant salad's waiter row, then its Waiter Card.
      await tester.scrollUntilVisible(
        find.text(_en.dishCardAskQuestion),
        200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.text(_en.dishCardAskQuestion));

      // Assert: the dish card's waiter row reads the question in Hebrew.
      expect(find.text(_question), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text(_en.dishCardFullScreen),
        200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.text(_en.dishCardFullScreen));

      // Assert: the Waiter Card lists the question.
      expect(find.byType(WaiterCardSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(WaiterCardSheet),
          matching: find.text(_question),
        ),
        findsOneWidget,
      );

      // Act: open the chef card.
      await tester.ensureVisible(find.byKey(waiterCardChefCardKey));
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.byKey(waiterCardChefCardKey));

      // Assert: in Hebrew, for the dish, with the sesame line, the
      // question and the cross-contact line, and no "safe".
      final card = find.byType(ChefCardScreen);
      expect(card, findsOneWidget);
      Finder onCard(String text) =>
          find.descendant(of: card, matching: find.text(text));
      expect(onCard(_sesameLine), findsOneWidget);
      expect(onCard('המנה שאני רוצה להזמין: סלט חצילים'), findsOneWidget);
      expect(onCard(_question), findsOneWidget);
      expect(
        onCard(
          'אשמח שתבררו עם המטבח איך נמנע מגע צולב '
          '(משטחים, שמן וכלים משותפים). תודה.',
        ),
        findsOneWidget,
      );
      final texts = tester
          .widgetList<SelectableText>(
            find.descendant(of: card, matching: find.byType(SelectableText)),
          )
          .map((widget) => widget.data ?? '');
      expect(texts, isNotEmpty);
      for (final text in texts) {
        expect(text, isNot(matches(_safe)), reason: text);
      }
    });

    testWidgets('two people checked: the dish card has a section each, the '
        "question under the sesame person's, in Hebrew", (tester) async {
      // Setup: me with sesame and Dana on keto, both combined.
      final fakes = FakeAppDependencies();
      fakes.repository.stub(_ref, MenuFetched(menu: _menu));
      fakes.classifier.respondWith(_analysis);
      await fakes.settingsStore.write(
        AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
          otherProfiles: const <NamedProfile>[
            NamedProfile(id: 'p1', name: 'Dana'),
          ],
          activeProfileIds: const <String>[NamedProfile.primaryId, 'p1'],
        ),
      );
      await tester.pumpWidget(
        KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
      );
      await tester.pumpAndSettle();

      // Act: open the venue, the eggplant salad's Waiter Card, its chef
      // card.
      await enterText(tester, _woltUrl);
      await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));
      await tester.scrollUntilVisible(
        find.text(_en.dishCardAskQuestion),
        200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.text(_en.dishCardAskQuestion));
      await tester.scrollUntilVisible(
        find.text(_en.dishCardFullScreen),
        200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.text(_en.dishCardFullScreen));
      await tester.ensureVisible(find.byKey(waiterCardChefCardKey));
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.byKey(waiterCardChefCardKey));

      // Assert: one section per person; the question only under me.
      final card = find.byType(ChefCardScreen);
      expect(card, findsOneWidget);
      Finder inSection(String heading, String text) => find.descendant(
        of: find.byKey(groupChefCardSectionKey(heading)),
        matching: find.text(text),
      );
      expect(inSection('אני', _sesameLine), findsOneWidget);
      expect(inSection('אני', _question), findsOneWidget);
      expect(inSection('Dana', _question), findsNothing);
      expect(
        find.descendant(
          of: card,
          matching: find.text('המנה שאני רוצה להזמין: סלט חצילים'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text(
            'אשמח שתבררו עם המטבח איך נמנע מגע צולב '
            '(משטחים, שמן וכלים משותפים). תודה.',
          ),
        ),
        findsOneWidget,
      );
    });
  });
}
