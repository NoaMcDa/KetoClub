// What other people were told, on the dish card and in the Why sheet
// (Banto, ALG-14, issue #409): "N people were told it has no X here" or
// "…it has X here", in the UI language, with the helper-tool footer;
// nothing without a shared count, and nothing in a keto build.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dish_confirmation.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/utils/allergens/confirmations.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/allergens/waiter_questions.dart';
import 'package:ketoclub/utils/profile_wording.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/why_sheet.dart';
import 'package:provider/provider.dart';

final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _he = AppLocalizationsHe();

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

const Dish _dish = Dish(
  id: 'd1',
  name: 'Eggplant salad',
  description: '',
  price: 42,
  options: <DishOption>[],
);

const AnalysedDish _analysed = AnalysedDish(
  dishId: 'd1',
  name: 'Eggplant salad',
  verdict: DishVerdict.orderAsIs,
  why: 'why',
);

final ConfirmationEvidence _noSesame = ConfirmationEvidence(
  restrictionId: RestrictionId.sesame,
  polarity: ConfirmationPolarity.absent,
  day: DateTime(2026, 10, 12),
  shared: true,
  count: 4,
);

final ConfirmationEvidence _peanuts = ConfirmationEvidence(
  restrictionId: RestrictionId.peanuts,
  polarity: ConfirmationPolarity.present,
  day: DateTime(2026, 10, 12),
  shared: true,
  count: 3,
);

DishCard _card(
  List<ConfirmationEvidence> shared, {
  bool bantoMode = true,
  ProfileWording wording = ProfileWording.strict,
}) => DishCard(
  row: const DishRow(dish: _dish, category: 'Mains', analysis: _analysed),
  localeTag: 'en',
  onShowScript: (_) {},
  evaluated: EvaluatedDish(
    dish: _analysed,
    concerns: const <Concern>[],
    state: DishState.fits,
    sharedConfirmations: shared,
  ),
  wording: wording,
  holdsKeto: false,
  bantoMode: bantoMode,
);

void main() {
  group('sharedConfirmationLine', () {
    test('words both polarities, the restriction as asked about', () {
      // Act
      final no = sharedConfirmationLine(_en, _noSesame, hebrew: false);
      final yes = sharedConfirmationLine(_en, _peanuts, hebrew: false);
      final he = sharedConfirmationLine(_he, _noSesame, hebrew: true);

      // Assert
      final sesame = WaiterQuestions.subject(
        RestrictionId.sesame,
        hebrew: false,
      );
      expect(no, '4 people were told it has no $sesame here');
      expect(
        yes,
        '3 people were told it has '
        '${WaiterQuestions.subject(RestrictionId.peanuts, hebrew: false)} '
        'here',
      );
      expect(
        he,
        contains(WaiterQuestions.subject(RestrictionId.sesame, hebrew: true)),
      );
      for (final line in <String>[no, yes, he]) {
        expect(line.toLowerCase(), isNot(contains('safe')));
        expect(line, isNot(contains('בטוח')));
      }
    });
  });

  group('the dish card', () {
    testWidgets('shows each shared line and the helper-tool footer', (
      tester,
    ) async {
      // Act
      await _pump(tester, _card(<ConfirmationEvidence>[_noSesame, _peanuts]));

      // Assert
      expect(
        find.text(sharedConfirmationLine(_en, _noSesame, hebrew: false)),
        findsOneWidget,
      );
      expect(find.byKey(dishSharedConfirmationKey(1)), findsOneWidget);
      expect(find.text(_en.sharedConfirmationFooter), findsOneWidget);
    });

    testWidgets('in Hebrew, the restriction is named in Hebrew', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        _card(<ConfirmationEvidence>[_noSesame]),
        locale: const Locale('he'),
      );

      // Assert
      expect(
        find.text(sharedConfirmationLine(_he, _noSesame, hebrew: true)),
        findsOneWidget,
      );
      expect(find.text(_he.sharedConfirmationFooter), findsOneWidget);
    });

    testWidgets('shows nothing without a shared count', (tester) async {
      await _pump(tester, _card(const <ConfirmationEvidence>[]));
      expect(find.byKey(dishSharedConfirmationKey(0)), findsNothing);
      expect(find.byKey(dishSharedFooterKey), findsNothing);
    });

    testWidgets('a keto build, or keto-only wording, never shows it', (
      tester,
    ) async {
      await _pump(
        tester,
        _card(<ConfirmationEvidence>[_noSesame], bantoMode: false),
      );
      expect(find.byKey(dishSharedFooterKey), findsNothing);

      await _pump(
        tester,
        _card(<ConfirmationEvidence>[
          _noSesame,
        ], wording: ProfileWording.ketoOnly),
      );
      expect(find.byKey(dishSharedFooterKey), findsNothing);
    });

    testWidgets('Why? carries the lines to the sheet', (tester) async {
      // Arrange
      await _pump(tester, _card(<ConfirmationEvidence>[_noSesame]));

      // Act
      await tester.tap(find.byKey(dishWhyKey));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byKey(whySharedConfirmationKey(0)), findsOneWidget);
      expect(find.byKey(whyFooterKey), findsOneWidget);
    });
  });

  group('the Why sheet', () {
    testWidgets('lists the shared lines above the helper-tool footer', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        WhySheet(
          dishName: 'Eggplant salad',
          concerns: const <Concern>[],
          strictProfile: true,
          sharedConfirmations: <ConfirmationEvidence>[_noSesame, _peanuts],
          bantoMode: true,
        ),
      );

      // Assert
      final first = tester.widget<Text>(
        find.byKey(whySharedConfirmationKey(0)),
      );
      expect(first.data, sharedConfirmationLine(_en, _noSesame, hebrew: false));
      expect(find.byKey(whySharedConfirmationKey(1)), findsOneWidget);
      expect(find.text(_en.helperToolSentence), findsOneWidget);
    });

    testWidgets('has no shared line without a count', (tester) async {
      await _pump(
        tester,
        const WhySheet(
          dishName: 'Eggplant salad',
          concerns: <Concern>[],
          strictProfile: true,
          bantoMode: true,
        ),
      );
      expect(find.byKey(whySharedConfirmationKey(0)), findsNothing);
    });
  });
}
