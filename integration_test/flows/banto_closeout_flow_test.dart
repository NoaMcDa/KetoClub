// Flow test (FLOW_TEST_CONVENTIONS.md; Banto, ALG-11 #353, ALG-03 #345,
// ALG-06 #348): the privacy and helper-tool copy and a milk profile read
// against a menu.
//
// 1. A first run that skips the onboarding sees the disclosure banner with
//    what of the profile leaves the device; in Settings the first
//    restriction brings the helper-tool sheet once, and the sentence stays
//    at the head of "My restrictions".
// 2. With milk in the profile, a dish with "שמנת" in its description is to
//    avoid, a dish offering "גבינת שמנת" as an option is ordered with a
//    Hebrew change, and its Why sheet says the model listed its
//    ingredients and the rules read the text too.
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
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/restriction_onboarding_screen.dart';
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/helper_tool_sheet.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';
import 'package:ketoclub/widgets/status_badge.dart';
import 'package:ketoclub/widgets/verdict_counter_tiles.dart';
import 'package:ketoclub/widgets/why_sheet.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Wolt venue page the user pastes.
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/banto-closeout-venue';

/// The [VenueRef] [_woltUrl] resolves to.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'banto-closeout-venue',
);

/// Sour cream in the description: milk in a part that cannot be left off.
const Dish _caesar = Dish(
  id: 'caesar',
  name: 'סלט קיסר',
  description: 'חסה, עגבניות ושמנת חמוצה',
  price: 48,
  options: <DishOption>[],
);

/// Cream cheese only as an option: milk on a removable part.
const Dish _green = Dish(
  id: 'green',
  name: 'סלט ירוק',
  description: 'חסה ומלפפון',
  price: 42,
  options: <DishOption>[
    DishOption(name: 'תוספות', values: <String>['גבינת שמנת']),
  ],
);

/// The menu the repository serves for [_ref].
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[
    MenuCategory(id: 'c1', name: 'סלטים', dishes: <Dish>[_caesar, _green]),
  ],
);

/// Both dishes green for keto, from the language model, with its
/// ingredient extraction (ALG-03).
final MenuAnalysed _analysis = MenuAnalysed(
  dishes: const <AnalysedDish>[
    AnalysedDish(
      dishId: 'caesar',
      name: 'סלט קיסר',
      verdict: DishVerdict.orderAsIs,
      why: 'Leaves.',
      ingredients: <ExtractedIngredient>[
        ExtractedIngredient(
          name: 'חסה',
          certainty: Certainty.stated,
          role: ComponentRole.base,
        ),
      ],
    ),
    AnalysedDish(
      dishId: 'green',
      name: 'סלט ירוק',
      verdict: DishVerdict.orderAsIs,
      why: 'Leaves.',
      ingredients: <ExtractedIngredient>[
        ExtractedIngredient(
          name: 'מלפפון',
          certainty: Certainty.stated,
          role: ComponentRole.base,
        ),
      ],
    ),
  ],
  unclassified: const <String>[],
  engine: const LlmEngine(model: 'flow-model'),
  analysedAt: DateTime.utc(2026),
);

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

/// Scrolls the first scrollable until [finder] is built, then taps it.
Future<void> _scrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tapAndSettle(tester, finder);
}

/// Adds [id] from Settings' "My restrictions" picker.
Future<void> _add(WidgetTester tester, RestrictionId id) async {
  await _scrollAndTap(tester, find.byKey(restrictionsAddKey));
  final option = find.byKey(restrictionOptionKey(id));
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  await tapAndSettle(tester, option);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Banto close-out flow', () {
    testWidgets('the disclosure says what leaves the device, and the first '
        'restriction brings the helper-tool sheet once', (tester) async {
      // Setup
      final fakes = FakeAppDependencies();
      await tester.pumpWidget(
        KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
      );
      await tester.pumpAndSettle();

      // Act: skip the first-run onboarding.
      await _scrollAndTap(tester, find.byKey(restrictionOnboardingSkipKey));

      // Assert: Explore's banner carries the Banto copy.
      expect(find.textContaining(_en.whatLeavesDeviceBanto), findsOneWidget);
      await tapAndSettle(tester, find.text(_en.consentDisclosureOk));
      expect(find.textContaining(_en.whatLeavesDeviceBanto), findsNothing);

      // Act: add the first restriction in Settings.
      await tapAndSettle(tester, navDestination(_en.navSettings));
      await _add(tester, RestrictionId.milk);

      // Assert: the helper-tool sheet, once.
      expect(find.byKey(helperToolSheetKey), findsOneWidget);
      expect(find.text(_en.helperToolTitle), findsOneWidget);
      await tapAndSettle(tester, find.byKey(helperToolOkKey));
      await _add(tester, RestrictionId.sesame);
      expect(find.byKey(helperToolSheetKey), findsNothing);

      // Assert: the sentence heads "My restrictions".
      await tester.scrollUntilVisible(
        find.text(_en.helperToolSentence),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(_en.helperToolSentence), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(_en.helperToolSentence)).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(restrictionRowKey(RestrictionId.milk)))
              .dy,
        ),
      );
      final saved = await fakes.settingsStore.read();
      expect(saved.helperToolSeen, isTrue);
    });

    testWidgets('milk: sour cream in the description is to avoid, cream '
        'cheese as an option is a Hebrew change, and Why says who read it', (
      tester,
    ) async {
      // Setup
      final fakes = FakeAppDependencies();
      fakes.repository.stub(_ref, MenuFetched(menu: _menu));
      fakes.classifier.respondWith(_analysis);
      await tester.pumpWidget(
        KetoClubApp(dependencies: fakes.dependencies, bantoMode: true),
      );
      await tester.pumpAndSettle();

      // Act: pick milk on the onboarding, then open the venue.
      await _scrollAndTap(
        tester,
        find.byKey(restrictionOnboardingChipKey(RestrictionId.milk)),
      );
      await _scrollAndTap(tester, find.byKey(restrictionOnboardingContinueKey));
      await enterText(tester, _woltUrl);
      await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

      // Assert: one analysis, which asked for the ingredients.
      expect(fakes.classifier.calls, hasLength(1));
      expect(fakes.classifier.optionCalls.single.restrictionsRequested, isTrue);

      // Assert: the cream-cheese salad is ordered with a change, in Hebrew.
      await tester.scrollUntilVisible(
        find.text(_green.name),
        200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(StateBadge),
          matching: find.text(_en.stateFitsWithChangeBadge.toUpperCase()),
        ),
        findsOneWidget,
      );
      await tapAndSettle(tester, find.text(_en.dishCardAskWaiter));
      expect(find.textContaining("לבקש את המנה בלי '"), findsOneWidget);

      // Act: open its Why sheet.
      await tapAndSettle(tester, find.byKey(dishWhyKey));

      // Assert: the option it was found in, and who read the dish.
      expect(find.byKey(whyCoverageKey), findsOneWidget);
      expect(
        find.text('${_en.whyCoverageFull} ${_en.whyCoverageModelAndRules}'),
        findsOneWidget,
      );
      expect(find.text(_en.whySourceOption), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Act: the Avoid tile reaches the sour-cream salad.
      await tester.scrollUntilVisible(
        find.descendant(
          of: find.byType(VerdictCounterTiles),
          matching: find.text(_en.stateAvoidTile.toUpperCase()),
        ),
        -200,
        scrollable: _menuList,
      );
      await tester.pumpAndSettle();
      await tapAndSettle(
        tester,
        find.descendant(
          of: find.byType(VerdictCounterTiles),
          matching: find.text(_en.stateAvoidTile.toUpperCase()),
        ),
      );

      // Assert
      expect(find.text(_caesar.name), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(StateBadge),
          matching: find.text(_en.stateAvoidBadge.toUpperCase()),
        ),
        findsOneWidget,
      );
    });
  });
}
