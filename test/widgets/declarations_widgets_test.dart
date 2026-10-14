// Declarations on screen (Banto; ALG-09, issue #351): the dish card's
// "declared kosher by the platform" chip and the Why sheet's line for a
// concern a declaration lowered.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/utils/allergens/declarations.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/profile_wording.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/why_sheet.dart';
import 'package:provider/provider.dart';

/// Pumps [child] in a localised app with a carb-budget controller.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
}) => tester.pumpWidget(
  ChangeNotifierProvider<CarbBudgetController>.value(
    value: CarbBudgetController(),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

/// A green analysis of the bread basket.
const AnalysedDish _analysed = AnalysedDish(
  dishId: '1003',
  name: 'Bread basket',
  verdict: DishVerdict.orderAsIs,
  why: 'Fits',
);

/// The bread basket, flagged kosher by the platform when [kosher].
Dish _dish({bool kosher = true}) => Dish(
  id: '1003',
  name: 'Bread basket',
  description: 'On the house',
  price: 0,
  options: const <DishOption>[],
  declaredTags: kosher ? const <String>[kosherDeclaredTag] : const <String>[],
);

/// A dish card for [dish] in the given mode.
DishCard _card(
  Dish dish, {
  bool bantoMode = true,
  ProfileWording wording = ProfileWording.strict,
}) => DishCard(
  row: DishRow(dish: dish, category: 'Bakery', analysis: _analysed),
  localeTag: 'en',
  onShowScript: (_) {},
  evaluated: const EvaluatedDish(
    dish: _analysed,
    concerns: <Concern>[],
    state: DishState.fits,
  ),
  wording: wording,
  holdsKeto: false,
  bantoMode: bantoMode,
);

/// A concern about gluten lowered by a declaration.
const Concern _lowered = Concern(
  restrictionId: RestrictionId.gluten,
  source: ConcernSource.description,
  certainty: Certainty.suspected,
  tier: EvidenceTier.declared,
  matchedText: 'bun',
);

/// The gluten-free declaration read from [source] as [text].
Declaration _glutenFree(DeclarationSource source, String text) => Declaration(
  rule: 'glutenFree',
  restrictionIds: const <RestrictionId>[RestrictionId.gluten],
  polarity: DeclarationPolarity.absent,
  source: source,
  matchedText: text,
);

void main() {
  group('the kosher chip', () {
    testWidgets('shows on a Banto card when the platform flags the dish', (
      tester,
    ) async {
      // Act
      await _pump(tester, _card(_dish()));

      // Assert
      expect(find.byKey(dishDeclaredKosherKey), findsOneWidget);
      expect(find.text('Declared kosher by the platform'), findsOneWidget);
    });

    testWidgets('reads in Hebrew', (tester) async {
      // Act
      await _pump(tester, _card(_dish()), locale: const Locale('he'));

      // Assert
      expect(find.text('כשר לפי הצהרת הפלטפורמה'), findsOneWidget);
    });

    testWidgets('is absent without the flag', (tester) async {
      // Act
      await _pump(tester, _card(_dish(kosher: false)));

      // Assert
      expect(find.byKey(dishDeclaredKosherKey), findsNothing);
    });

    testWidgets('is absent with Banto off', (tester) async {
      // Act
      await _pump(tester, _card(_dish(), bantoMode: false));

      // Assert
      expect(find.byKey(dishDeclaredKosherKey), findsNothing);
    });

    testWidgets('is absent on a keto-only screen', (tester) async {
      // Act
      await _pump(tester, _card(_dish(), wording: ProfileWording.ketoOnly));

      // Assert: a keto-only profile is today's app, byte for byte.
      expect(find.byKey(dishDeclaredKosherKey), findsNothing);
    });

    test('the copy names the platform, never the app', () {
      for (final l10n in <AppLocalizations>[
        AppLocalizationsEn(),
        AppLocalizationsHe(),
      ]) {
        // Arrange
        final copy = l10n.dishCardDeclaredKosher;

        // Assert
        expect(
          copy.contains('platform') || copy.contains('הפלטפורמה'),
          isTrue,
          reason: copy,
        );
        for (final word in <String>['Banto', 'KetoClub', 'בנטו', 'safe']) {
          expect(copy, isNot(contains(word)));
        }
      }
    });
  });

  group('the Why sheet for a declared concern', () {
    Future<void> pumpSheet(
      WidgetTester tester,
      List<Declaration> declarations, {
      Locale locale = const Locale('en'),
    }) => _pump(
      tester,
      WhySheet(
        dishName: 'Burger',
        concerns: const <Concern>[_lowered],
        strictProfile: true,
        declarations: declarations,
        bantoMode: true,
      ),
      locale: locale,
    );

    testWidgets('the restaurant\'s words read "declared by the restaurant"', (
      tester,
    ) async {
      // Act
      await pumpSheet(tester, <Declaration>[
        _glutenFree(DeclarationSource.heading, 'ללא גלוטן'),
      ]);

      // Assert
      expect(find.text('Declared by the restaurant'), findsOneWidget);
      expect(
        find.text(
          'Marked “ללא גלוטן” — this lowers the finding '
          'but never rules it out',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a platform tag reads "declared by the platform"', (
      tester,
    ) async {
      // Act
      await pumpSheet(tester, <Declaration>[
        _glutenFree(DeclarationSource.platformTag, 'GLUTEN_FREE'),
      ]);

      // Assert
      expect(find.text('Declared by the platform'), findsOneWidget);
      expect(find.textContaining('GLUTEN_FREE'), findsOneWidget);
    });

    testWidgets('reads in Hebrew', (tester) async {
      // Act
      await pumpSheet(tester, <Declaration>[
        _glutenFree(DeclarationSource.dishText, 'ללא גלוטן'),
      ], locale: const Locale('he'));

      // Assert
      expect(find.text('הוצהר על ידי המסעדה'), findsOneWidget);
      expect(find.textContaining('לא שולל'), findsOneWidget);
    });

    testWidgets('a declaration about another restriction is not quoted', (
      tester,
    ) async {
      // Act
      await pumpSheet(tester, const <Declaration>[
        Declaration(
          rule: 'eggFree',
          restrictionIds: <RestrictionId>[RestrictionId.eggs],
          polarity: DeclarationPolarity.absent,
          source: DeclarationSource.dishText,
          matchedText: 'eggless',
        ),
      ]);

      // Assert
      expect(find.text('Declared by the platform'), findsOneWidget);
      expect(find.textContaining('eggless'), findsNothing);
    });

    test('whyDeclaredTierPhrase picks the phrase by source', () {
      // Arrange
      final en = AppLocalizationsEn();

      // Assert
      expect(whyDeclaredTierPhrase(en, null), en.whyTierDeclared);
      expect(
        whyDeclaredTierPhrase(
          en,
          _glutenFree(DeclarationSource.platformTag, 'gf'),
        ),
        en.whyTierDeclared,
      );
      for (final source in <DeclarationSource>[
        DeclarationSource.dishText,
        DeclarationSource.heading,
      ]) {
        expect(
          whyDeclaredTierPhrase(en, _glutenFree(source, 'gf')),
          en.whyTierDeclaredRestaurant,
        );
      }
    });
  });
}
