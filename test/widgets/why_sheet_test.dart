import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/widgets/app_sheet.dart';
import 'package:ketoclub/widgets/why_sheet.dart';

final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _he = AppLocalizationsHe();

Concern _concern({
  RestrictionId id = RestrictionId.sesame,
  ConcernSource source = ConcernSource.name,
  EvidenceTier tier = EvidenceTier.stated,
  String? matchedText,
  String? waiterQuestion,
}) => Concern(
  restrictionId: id,
  source: source,
  certainty: Certainty.stated,
  tier: tier,
  matchedText: matchedText,
  waiterQuestion: waiterQuestion,
);

Widget _app(Widget home, Locale locale) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: locale,
  home: home,
);

Future<void> _pump(
  WidgetTester tester,
  List<Concern> concerns, {
  Locale locale = const Locale('en'),
  bool strictProfile = true,
  bool bantoMode = true,
}) => tester.pumpWidget(
  _app(
    Scaffold(
      body: WhySheet(
        dishName: 'Falafel plate',
        concerns: concerns,
        strictProfile: strictProfile,
        bantoMode: bantoMode,
      ),
    ),
    locale,
  ),
);

void main() {
  group('tier phrases', () {
    for (final entry in <EvidenceTier, (String, String)>{
      EvidenceTier.declared: (
        'Declared by the platform',
        'הוצהר על ידי הפלטפורמה',
      ),
      EvidenceTier.stated: ('Stated on the menu', 'כתוב בתפריט'),
      EvidenceTier.inferred: (
        'Inferred from a typical recipe',
        'משוער ממתכון אופייני',
      ),
      EvidenceTier.suspected: ('Suspected — please ask', 'חשד — כדאי לשאול'),
      EvidenceTier.confirmed: ('Confirmed by you', 'אושר על ידך'),
      EvidenceTier.denied: ('Ruled out by you', 'נשלל על ידך'),
    }.entries) {
      testWidgets('${entry.key.name} reads in English', (tester) async {
        await _pump(tester, [_concern(tier: entry.key)]);

        expect(find.text(entry.value.$1), findsOneWidget);
        expect(whyTierPhrase(_en, entry.key), entry.value.$1);
      });

      testWidgets('${entry.key.name} reads in Hebrew', (tester) async {
        await _pump(tester, [
          _concern(tier: entry.key),
        ], locale: const Locale('he'));

        expect(find.text(entry.value.$2), findsOneWidget);
        expect(whyTierPhrase(_he, entry.key), entry.value.$2);
      });
    }

    test('every phrase is distinct and carries no digit or percent sign', () {
      for (final l10n in [_en, _he]) {
        final phrases = [
          for (final tier in EvidenceTier.values) whyTierPhrase(l10n, tier),
        ];
        expect(phrases.toSet(), hasLength(EvidenceTier.values.length));
        for (final phrase in phrases) {
          expect(phrase, isNot(matches(RegExp('[0-9%]'))));
        }
      }
    });
  });

  group('source phrases', () {
    testWidgets('each source has its own line in both languages', (
      tester,
    ) async {
      for (final l10n in [_en, _he]) {
        final lines = [
          for (final source in ConcernSource.values)
            whySourcePhrase(l10n, source),
        ];
        expect(lines.toSet(), hasLength(ConcernSource.values.length));
      }
      await _pump(tester, [_concern(source: ConcernSource.hidden)]);
      expect(find.text('A hidden source the text implies'), findsOneWidget);
    });
  });

  group('a concern row', () {
    testWidgets('shows the restriction name in the app language', (
      tester,
    ) async {
      await _pump(tester, [_concern(id: RestrictionId.peanuts)]);
      expect(find.text('Peanuts'), findsOneWidget);

      await _pump(tester, [
        _concern(id: RestrictionId.peanuts),
      ], locale: const Locale('he'));
      expect(find.text('בוטנים'), findsOneWidget);
    });

    testWidgets("names the user's own word beside the restriction (ALG-17)", (
      tester,
    ) async {
      await _pump(tester, [
        _concern(id: RestrictionId.custom, matchedText: 'Kiwi'),
      ]);
      expect(find.text('Your own restriction: Kiwi'), findsOneWidget);

      await _pump(tester, [
        _concern(id: RestrictionId.custom, matchedText: 'קיווי'),
      ], locale: const Locale('he'));
      expect(find.text('הגבלה משלך: קיווי'), findsOneWidget);
    });

    testWidgets('quotes the matched text and shows the waiter question', (
      tester,
    ) async {
      await _pump(tester, [
        _concern(
          matchedText: 'tahini',
          waiterQuestion: 'Does the dressing contain tahini?',
        ),
      ]);

      expect(find.text('Matched: “tahini”'), findsOneWidget);
      expect(find.text('Ask the waiter'), findsOneWidget);
      expect(find.text('Does the dressing contain tahini?'), findsOneWidget);
    });

    testWidgets('quotes Hebrew matched text in the Hebrew sheet', (
      tester,
    ) async {
      await _pump(tester, [
        _concern(matchedText: 'טחינה', waiterQuestion: 'יש טחינה ברוטב?'),
      ], locale: const Locale('he'));

      expect(find.text('נמצא: “טחינה”'), findsOneWidget);
      expect(find.text('לשאול את המלצר'), findsOneWidget);
      expect(find.text('יש טחינה ברוטב?'), findsOneWidget);
    });

    testWidgets('leaves out the quote and the question when absent', (
      tester,
    ) async {
      await _pump(tester, [_concern()]);

      expect(find.textContaining('Matched'), findsNothing);
      expect(find.text('Ask the waiter'), findsNothing);
    });

    testWidgets('lists one row per concern, in the order given', (
      tester,
    ) async {
      await _pump(tester, [
        _concern(id: RestrictionId.milk, tier: EvidenceTier.declared),
        _concern(id: RestrictionId.eggs, tier: EvidenceTier.suspected),
      ]);

      expect(find.byKey(whyConcernKey(0)), findsOneWidget);
      expect(find.byKey(whyConcernKey(1)), findsOneWidget);
      expect(find.byKey(whyConcernKey(2)), findsNothing);
      expect(
        tester.getTopLeft(find.text('Milk')).dy,
        lessThan(tester.getTopLeft(find.text('Eggs')).dy),
      );
    });

    testWidgets('shows no percentage anywhere', (tester) async {
      await _pump(tester, [
        _concern(matchedText: 'tahini', tier: EvidenceTier.suspected),
      ]);

      expect(find.textContaining('%'), findsNothing);
    });
  });

  group('empty list', () {
    testWidgets('a strict profile is told to ask the restaurant', (
      tester,
    ) async {
      await _pump(tester, const []);

      expect(
        find.text(
          'Nothing in the menu text points to your restrictions. '
          'Still ask the restaurant.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a flexible profile gets the plain line', (tester) async {
      await _pump(tester, const [], strictProfile: false);

      expect(
        find.text('Nothing in the menu text points to your restrictions.'),
        findsOneWidget,
      );
      expect(find.textContaining('Still ask'), findsNothing);
    });

    testWidgets('both lines read in Hebrew', (tester) async {
      await _pump(tester, const [], locale: const Locale('he'));
      expect(find.text(_he.whyEmptyStrict), findsOneWidget);

      await _pump(
        tester,
        const [],
        locale: const Locale('he'),
        strictProfile: false,
      );
      expect(find.text(_he.whyEmptyFlexible), findsOneWidget);
    });

    test('neither line says safe', () {
      for (final line in [
        _en.whyEmptyStrict,
        _en.whyEmptyFlexible,
        _he.whyEmptyStrict,
        _he.whyEmptyFlexible,
      ]) {
        expect(line.toLowerCase(), isNot(contains('safe')));
        expect(line, isNot(contains('בטוח')));
      }
    });
  });

  group('footer and title', () {
    testWidgets('ends with the helper-tool sentence in both languages', (
      tester,
    ) async {
      await _pump(tester, [_concern()]);
      expect(find.text(_en.helperToolSentence), findsOneWidget);
      expect(find.text('Why this result'), findsOneWidget);
      expect(find.text('Falafel plate'), findsOneWidget);

      await _pump(tester, [_concern()], locale: const Locale('he'));
      expect(find.text(_he.helperToolSentence), findsOneWidget);
      expect(find.text('למה התוצאה הזו'), findsOneWidget);
    });

    testWidgets('the footer sits below the last row', (tester) async {
      await _pump(tester, [_concern(), _concern(id: RestrictionId.milk)]);

      expect(
        tester.getTopLeft(find.byKey(whyFooterKey)).dy,
        greaterThan(tester.getBottomLeft(find.byKey(whyConcernKey(1))).dy),
      );
    });
  });

  group('RTL', () {
    testWidgets('Hebrew text aligns to the right edge', (tester) async {
      await _pump(tester, [_concern()], locale: const Locale('he'));

      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final title = tester.getTopRight(find.text('למה התוצאה הזו'));
      expect(title.dx, greaterThan(width / 2));
      expect(
        Directionality.of(tester.element(find.byKey(whyConcernKey(0)))),
        TextDirection.rtl,
      );
    });

    testWidgets('English text aligns to the left edge', (tester) async {
      await _pump(tester, [_concern()]);

      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final title = tester.getTopLeft(find.text('Why this result'));
      expect(title.dx, lessThan(width / 2));
    });
  });

  group('bantoMode', () {
    testWidgets('builds nothing when off', (tester) async {
      await _pump(tester, [_concern()], bantoMode: false);

      expect(find.text('Why this result'), findsNothing);
      expect(find.byKey(whyConcernKey(0)), findsNothing);
    });
  });

  group('showWhySheet', () {
    Future<void> open(
      WidgetTester tester,
      Size size, {
      bool bantoMode = true,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showWhySheet(
                  context,
                  dishName: 'Falafel plate',
                  concerns: [_concern()],
                  strictProfile: true,
                  bantoMode: bantoMode,
                ),
                child: const Text('open'),
              ),
            ),
          ),
          const Locale('en'),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('opens the sheet capped at the sheet width', (tester) async {
      await open(tester, const Size(1200, 800));

      expect(find.byType(WhySheet), findsOneWidget);
      final material = find
          .ancestor(of: find.byType(WhySheet), matching: find.byType(Material))
          .first;
      expect(tester.getSize(material).width, kSheetMaxWidth);
    });

    testWidgets('fills a phone-width screen', (tester) async {
      await open(tester, const Size(400, 800));

      final material = find
          .ancestor(of: find.byType(WhySheet), matching: find.byType(Material))
          .first;
      expect(tester.getSize(material).width, 400);
    });

    testWidgets('opens nothing when Banto mode is off', (tester) async {
      await open(tester, const Size(400, 800), bantoMode: false);

      expect(find.byType(WhySheet), findsNothing);
    });
  });
}
