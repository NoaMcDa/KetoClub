import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/dietary_profile.dart';
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
      expect(ids, isNot(contains(RestrictionId.custom)));
      expect(ids, hasLength(RestrictionId.values.length - 4));
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

    test('kosher and halal name their components, never the word itself '
        '(#342)', () {
      for (final l10n in [_en, _he]) {
        final kosher = restrictionJurisdictionHint(
          l10n,
          restrictionFor(RestrictionId.kosher),
        );
        final halal = restrictionJurisdictionHint(
          l10n,
          restrictionFor(RestrictionId.halal),
        );
        expect(kosher, l10n.restrictionKosherHint);
        expect(halal, l10n.restrictionHalalHint);
        for (final hint in [kosher, halal]) {
          expect(hint.toLowerCase(), isNot(contains('kosher')));
          expect(hint.toLowerCase(), isNot(contains('halal')));
          expect(hint, isNot(contains('כשר')));
          expect(hint, isNot(contains('חלאל')));
        }
      }
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
    test('maps every kind to allergy, autoimmune, intolerance, diet or '
        'religious diet', () {
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
        RestrictionKind.keto,
      ]) {
        expect(restrictionKindLabel(_en, kind), _en.restrictionKindDiet);
      }
      expect(
        restrictionKindLabel(_en, RestrictionKind.religiousComponent),
        _en.restrictionKindReligious,
      );
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
        added: <RestrictionId>{
          RestrictionId.sesame,
          RestrictionId.lactose,
          RestrictionId.fodmap,
          RestrictionId.histamine,
        },
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
      // The intolerance group had only lactose, FODMAP and histamine, so
      // its heading goes too.
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
      RestrictionPick? picked;
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
      expect(picked, const RestrictionPick.restriction(RestrictionId.mustard));
      expect(find.byType(RestrictionPickerSheet), findsNothing);
    });
  });

  group('ALG-17', () {
    test('the heads-up restrictions and alpha-gal say what they are', () {
      for (final id in headsUpRestrictions) {
        expect(
          restrictionJurisdictionHint(_en, restrictionFor(id)),
          _en.restrictionHeadsUpHint,
        );
        expect(
          restrictionJurisdictionHint(_he, restrictionFor(id)),
          _he.restrictionHeadsUpHint,
        );
      }
      expect(
        restrictionJurisdictionHint(
          _en,
          restrictionFor(RestrictionId.alphaGal),
        ),
        _en.restrictionAlphaGalHint,
      );
    });

    test('profileEntryDisplayName shows the own words, else the name', () {
      // Arrange
      final profile = DietaryProfile.empty
          .withEntry(RestrictionId.sesame)
          .withCustomTerm('kiwi')
          .withCustomTerm('כוסברה');

      // Act
      final names = <String>[
        for (final entry in profile.entries)
          profileEntryDisplayName(entry, const Locale('en')),
      ];

      // Assert
      expect(names, <String>['Sesame', 'kiwi, כוסברה']);
    });

    test('canAddToProfile is true while a word still fits', () {
      // Arrange: every taxonomy restriction is held.
      var profile = DietaryProfile.empty;
      for (final restriction in availableRestrictions(
        const <RestrictionId>{},
      )) {
        profile = profile.withEntry(restriction.id);
      }

      // Assert
      expect(canAddToProfile(profile), isTrue);
      for (var i = 0; i < ProfileEntry.maxTerms; i++) {
        profile = profile.withCustomTerm('word $i');
      }
      expect(canAddToProfile(profile), isFalse);
    });

    test('RestrictionPick compares by value and never prints the word', () {
      expect(
        const RestrictionPick.own('kiwi'),
        const RestrictionPick.own('kiwi'),
      );
      expect(
        const RestrictionPick.own('kiwi'),
        isNot(const RestrictionPick.restriction(RestrictionId.custom)),
      );
      expect(
        const RestrictionPick.own('kiwi').toString(),
        isNot(contains('kiwi')),
      );
      expect(
        const RestrictionPick.restriction(RestrictionId.sesame).toString(),
        contains('sesame'),
      );
    });

    testWidgets('the picker offers neither keto nor the own id as a row', (
      tester,
    ) async {
      await _pumpSheet(tester);
      expect(
        find.byKey(restrictionOptionKey(RestrictionId.custom)),
        findsNothing,
      );
      expect(
        find.byKey(restrictionOptionKey(RestrictionId.keto)),
        findsNothing,
      );
      expect(
        find.byKey(restrictionOptionKey(RestrictionId.glp1)),
        findsOneWidget,
      );
    });

    Future<RestrictionPick?> typeAndAdd(
      WidgetTester tester,
      String text, {
      Locale locale = const Locale('en'),
    }) async {
      RestrictionPick? picked;
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showRestrictionPickerSheet(
                    context: context,
                    added: const <RestrictionId>{},
                  );
                  closed = true;
                },
                child: const Icon(Icons.add),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      final field = find.byKey(restrictionOwnFieldKey);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, text);
      await tester.tap(find.byKey(restrictionOwnAddKey));
      await tester.pumpAndSettle();
      expect(closed, picked != null);
      return picked;
    }

    testWidgets('"Add your own" pops the trimmed word', (tester) async {
      expect(
        await typeAndAdd(tester, '  pine nuts '),
        const RestrictionPick.own('pine nuts'),
      );
      expect(find.byType(RestrictionPickerSheet), findsNothing);
    });

    testWidgets('a Hebrew word in the Hebrew UI', (tester) async {
      expect(
        await typeAndAdd(tester, 'כוסברה', locale: const Locale('he')),
        const RestrictionPick.own('כוסברה'),
      );
    });

    testWidgets('a blank word adds nothing and keeps the sheet open', (
      tester,
    ) async {
      expect(await typeAndAdd(tester, '   '), isNull);
      expect(find.byType(RestrictionPickerSheet), findsOneWidget);
      expect(find.text(_en.restrictionOwnTitle), findsOneWidget);
    });
  });
}
