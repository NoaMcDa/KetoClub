import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/widgets/app_sheet.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';

final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _he = AppLocalizationsHe();

/// Pumps [RestrictionPickerSheet] leaving out [added], as a page body.
Future<void> _pumpSheet(
  WidgetTester tester, {
  Set<RestrictionId> added = const <RestrictionId>{},
  Locale locale = const Locale('en'),
}) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: Scaffold(body: RestrictionPickerSheet(added: added)),
  ),
);

/// A restriction for the pure helpers, with only [jurisdictions] mattering.
Restriction _withJurisdictions(Set<Jurisdiction> jurisdictions) => Restriction(
  id: RestrictionId.legumes,
  kind: RestrictionKind.allergen,
  jurisdictions: jurisdictions,
  nameEn: 'Legumes',
  nameHe: 'קטניות',
  source: 'test',
);

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

void main() {
  group('availableRestrictions', () {
    test('leaves out keto and the added ids, in taxonomy order', () {
      // Act
      final available = availableRestrictions(<RestrictionId>{
        RestrictionId.sesame,
        RestrictionId.milk,
      });

      // Assert
      final ids = available.map((restriction) => restriction.id).toList();
      expect(ids, isNot(contains(RestrictionId.keto)));
      expect(ids, isNot(contains(RestrictionId.sesame)));
      expect(ids, isNot(contains(RestrictionId.milk)));
      expect(ids, hasLength(RestrictionId.values.length - 3));
      expect(ids.first, RestrictionId.peanuts);
    });

    test('is empty once every restriction but keto is added', () {
      // Act
      final available = availableRestrictions(<RestrictionId>{
        for (final id in RestrictionId.values)
          if (id != RestrictionId.keto) id,
      });

      // Assert
      expect(available, isEmpty);
    });
  });

  group('restrictionJurisdictionHint', () {
    test('names both lists, one list or none', () {
      expect(
        restrictionJurisdictionHint(
          _en,
          _withJurisdictions(<Jurisdiction>{Jurisdiction.us, Jurisdiction.eu}),
        ),
        'On the US and EU allergen lists',
      );
      expect(
        restrictionJurisdictionHint(
          _en,
          _withJurisdictions(<Jurisdiction>{Jurisdiction.us}),
        ),
        'On the US allergen list',
      );
      expect(
        restrictionJurisdictionHint(
          _en,
          _withJurisdictions(<Jurisdiction>{Jurisdiction.eu, Jurisdiction.il}),
        ),
        'On the EU allergen list',
      );
      expect(
        restrictionJurisdictionHint(
          _en,
          _withJurisdictions(<Jurisdiction>{Jurisdiction.ca}),
        ),
        'Not on any official allergen list',
      );
    });

    test('reads in Hebrew', () {
      expect(
        restrictionJurisdictionHint(_he, restrictionFor(RestrictionId.celery)),
        _he.restrictionJurisdictionHint('eu'),
      );
      expect(
        _he.restrictionJurisdictionHint('none'),
        isNot(_en.restrictionJurisdictionHint('none')),
      );
    });
  });

  group('restrictionKindLabel', () {
    test('maps every kind to allergy, autoimmune, intolerance or diet', () {
      expect(
        restrictionKindLabel(_en, RestrictionKind.allergen),
        _en.restrictionKindAllergy,
      );
      expect(
        restrictionKindLabel(_en, RestrictionKind.autoimmune),
        _en.restrictionKindAutoimmune,
      );
      expect(
        restrictionKindLabel(_en, RestrictionKind.intolerance),
        _en.restrictionKindIntolerance,
      );
      for (final kind in <RestrictionKind>[
        RestrictionKind.lifestyle,
        RestrictionKind.religiousComponent,
        RestrictionKind.keto,
      ]) {
        expect(restrictionKindLabel(_en, kind), _en.restrictionKindDiet);
      }
    });
  });

  group('RestrictionPickerSheet', () {
    testWidgets('groups the restrictions by kind, strict kinds first', (
      tester,
    ) async {
      // Act
      await _pumpSheet(tester);

      // Assert
      final allergy = find.text(_en.restrictionKindAllergy);
      final autoimmune = find.text(_en.restrictionKindAutoimmune);
      final intolerance = find.text(_en.restrictionKindIntolerance);
      final diet = find.text(_en.restrictionKindDiet);
      for (final header in [allergy, autoimmune, intolerance, diet]) {
        expect(header, findsOneWidget);
      }
      expect(_top(tester, allergy), lessThan(_top(tester, autoimmune)));
      expect(_top(tester, autoimmune), lessThan(_top(tester, intolerance)));
      expect(_top(tester, intolerance), lessThan(_top(tester, diet)));

      // Each row sits under its own kind's heading.
      final sesame = find.byKey(restrictionOptionKey(RestrictionId.sesame));
      final gluten = find.byKey(restrictionOptionKey(RestrictionId.gluten));
      final lactose = find.byKey(restrictionOptionKey(RestrictionId.lactose));
      final vegan = find.byKey(restrictionOptionKey(RestrictionId.vegan));
      expect(_top(tester, sesame), lessThan(_top(tester, autoimmune)));
      expect(_top(tester, gluten), greaterThan(_top(tester, autoimmune)));
      expect(_top(tester, gluten), lessThan(_top(tester, intolerance)));
      expect(_top(tester, lactose), greaterThan(_top(tester, intolerance)));
      expect(_top(tester, lactose), lessThan(_top(tester, diet)));
      expect(_top(tester, vegan), greaterThan(_top(tester, diet)));
    });

    testWidgets('leaves out keto and the added ids', (tester) async {
      // Act
      await _pumpSheet(
        tester,
        added: <RestrictionId>{RestrictionId.sesame, RestrictionId.lactose},
      );

      // Assert
      expect(
        find.byKey(restrictionOptionKey(RestrictionId.keto)),
        findsNothing,
      );
      expect(find.text('Keto'), findsNothing);
      expect(
        find.byKey(restrictionOptionKey(RestrictionId.sesame)),
        findsNothing,
      );
      // The intolerance group had only lactose, so its heading goes too.
      expect(find.text(_en.restrictionKindIntolerance), findsNothing);
      expect(find.byKey(restrictionOptionKey(RestrictionId.milk)), findsOne);
    });

    testWidgets('shows each name with its jurisdiction hint', (tester) async {
      // Act
      await _pumpSheet(tester);

      // Assert
      Finder inRow(RestrictionId id, String text) => find.descendant(
        of: find.byKey(restrictionOptionKey(id)),
        matching: find.text(text),
      );
      expect(inRow(RestrictionId.sesame, 'Sesame'), findsOneWidget);
      expect(
        inRow(RestrictionId.sesame, 'On the US and EU allergen lists'),
        findsOneWidget,
      );
      expect(
        inRow(RestrictionId.celery, 'On the EU allergen list'),
        findsOneWidget,
      );
      expect(
        inRow(RestrictionId.lactose, 'Not on any official allergen list'),
        findsOneWidget,
      );
      expect(find.text(_en.restrictionPickerTitle), findsOneWidget);
    });

    testWidgets('under Locale(he) shows Hebrew names, right to left', (
      tester,
    ) async {
      // Act
      await _pumpSheet(tester, locale: const Locale('he'));

      // Assert
      expect(find.text('שומשום'), findsOneWidget);
      expect(find.text('Sesame'), findsNothing);
      expect(find.text(_he.restrictionPickerTitle), findsOneWidget);
      final context = tester.element(find.byType(RestrictionPickerSheet));
      expect(Directionality.of(context), TextDirection.rtl);
      expect(tester.takeException(), isNull);
    });

    testWidgets('picking a row pops the sheet with its id, and the sheet is '
        'capped at the app sheet width', (tester) async {
      // Arrange: a wide window, so the cap is what limits the width.
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      RestrictionId? picked;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showRestrictionPickerSheet(
                    context: context,
                    added: const <RestrictionId>{},
                  );
                },
                child: const Icon(Icons.add),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Assert: the cap.
      expect(
        tester.getSize(find.byType(RestrictionPickerSheet)).width,
        lessThanOrEqualTo(kSheetMaxWidth),
      );

      // Act
      final mustard = find.byKey(restrictionOptionKey(RestrictionId.mustard));
      await tester.ensureVisible(mustard);
      await tester.pumpAndSettle();
      await tester.tap(mustard);
      await tester.pumpAndSettle();

      // Assert
      expect(picked, RestrictionId.mustard);
      expect(find.byType(RestrictionPickerSheet), findsNothing);
    });
  });
}
