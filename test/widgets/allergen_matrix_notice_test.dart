// The menu screen's allergen-information notice and the matrix's words on
// the dish card and the Why sheet (Banto; ALG-16, related to #358). Plain
// `flutter test` compiles the flag off, so each test passes `bantoMode`.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/allergen_matrix.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/utils/allergens/allergen_matrix.dart';
import 'package:ketoclub/widgets/allergen_matrix_notice.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/why_sheet.dart';

final Menu _menu = Menu(
  venueRef: const VenueRef(source: MenuSource.wolt, platformId: 'v'),
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026, 10, 15),
  categories: const <MenuCategory>[
    MenuCategory(
      id: 'c',
      name: 'Mains',
      dishes: <Dish>[
        Dish(
          id: 'd',
          name: 'Tomato stew',
          description: '',
          price: 10,
          options: <DishOption>[],
        ),
      ],
    ),
  ],
);

AllergenMatrixMatch _match({bool stray = false}) => AllergenMatrixMatcher.match(
  AllergenMatrix(
    source: MatrixSource.restaurant,
    validFrom: DateTime.utc(2026, 10),
    rows: <AllergenMatrixRow>[
      const AllergenMatrixRow(
        name: 'Tomato stew',
        cells: <RestrictionId, MatrixCell>{
          RestrictionId.eggs: MatrixCell.contains,
        },
      ),
      if (stray) ...const <AllergenMatrixRow>[
        AllergenMatrixRow(name: 'Pizza'),
        AllergenMatrixRow(name: 'פסטה'),
      ],
    ],
  ),
  _menu,
);

Future<AppLocalizations> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
  return lookupAppLocalizations(locale);
}

void main() {
  group('AllergenMatrixNotice', () {
    testWidgets('states the source and the date, in English', (tester) async {
      // Act
      await _pump(
        tester,
        AllergenMatrixNotice(match: _match(), bantoMode: true),
      );

      // Assert
      expect(find.byKey(allergenMatrixNoticeKey), findsOneWidget);
      expect(
        find.text(
          'Allergen information from the restaurant, dated Oct 1, 2026',
        ),
        findsOneWidget,
      );
      expect(find.byKey(allergenMatrixUnmatchedKey), findsNothing);
    });

    testWidgets('and in Hebrew', (tester) async {
      // Act
      final l10n = await _pump(
        tester,
        AllergenMatrixNotice(match: _match(), bantoMode: true),
        locale: const Locale('he'),
      );

      // Assert
      expect(find.textContaining('מידע על אלרגנים מהמסעדה'), findsOneWidget);
      expect(find.textContaining('2026'), findsOneWidget);
      expect(l10n.allergenMatrixNotice('x'), contains('מתאריך'));
    });

    testWidgets('lists the rows that match no dish, as printed', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        AllergenMatrixNotice(match: _match(stray: true), bantoMode: true),
      );

      // Assert
      expect(
        find.text('2 lines of it match no dish on this menu: Pizza, פסטה'),
        findsOneWidget,
      );
    });

    testWidgets('builds nothing without Banto or without a matrix', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        Column(
          children: <Widget>[
            AllergenMatrixNotice(match: _match()),
            const AllergenMatrixNotice(match: null, bantoMode: true),
          ],
        ),
      );

      // Assert
      expect(find.byKey(allergenMatrixNoticeKey), findsNothing);
      expect(find.textContaining('Allergen information'), findsNothing);
    });
  });

  group('the matrix on the dish card and the Why sheet', () {
    const contains = Concern(
      restrictionId: RestrictionId.eggs,
      source: ConcernSource.matrix,
      certainty: Certainty.stated,
      tier: EvidenceTier.declared,
      waiterQuestion: 'Can this be made without eggs?',
    );

    testWidgets('a matrix concern names the restaurant and quotes nothing', (
      tester,
    ) async {
      // Arrange
      final l10n = await _pump(tester, const SizedBox.shrink());

      // Assert
      expect(
        concernSourceLabel(l10n, contains),
        "restaurant's allergen information",
      );
    });

    testWidgets('the Why sheet says the restaurant declared it', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        const WhySheet(
          dishName: 'Tomato stew',
          concerns: <Concern>[contains],
          strictProfile: true,
          bantoMode: true,
        ),
      );

      // Assert
      expect(
        find.text("Declared in the restaurant's allergen information"),
        findsOneWidget,
      );
      expect(
        find.text("Listed in the restaurant's own allergen information"),
        findsOneWidget,
      );
      expect(find.textContaining('Matched'), findsNothing);
    });

    testWidgets('a free cell is quoted by its row, never as a clearance', (
      tester,
    ) async {
      // Arrange: a stated sesame finding the matrix lowered to likely.
      final evidence = AllergenMatrixMatcher.evidenceOf(
        const AllergenMatrixRow(
          name: 'Tomato stew',
          cells: <RestrictionId, MatrixCell>{
            RestrictionId.sesame: MatrixCell.free,
          },
        ),
      );

      // Act
      await _pump(
        tester,
        WhySheet(
          dishName: 'Tomato stew',
          concerns: const <Concern>[
            Concern(
              restrictionId: RestrictionId.sesame,
              source: ConcernSource.description,
              certainty: Certainty.likely,
              tier: EvidenceTier.declared,
              matchedText: 'tahini',
            ),
          ],
          declarations: evidence.absences,
          strictProfile: true,
          bantoMode: true,
        ),
      );

      // Assert
      expect(
        find.text("Declared in the restaurant's allergen information"),
        findsOneWidget,
      );
      expect(
        find.text(
          'Listed as free of it, as “Tomato stew” — this '
          'lowers the finding but never rules it out',
        ),
        findsOneWidget,
      );
    });
  });

  test(
    'no allergen-matrix string says "safe" or rates, in either language',
    () {
      // Arrange
      final values = <String>[
        for (final path in <String>[
          'lib/l10n/app_en.arb',
          'lib/l10n/app_he.arb',
        ])
          for (final MapEntry(:key, :value) in (jsonDecode(
            File(path).readAsStringSync(),
          ) as Map<String, Object?>).entries)
            if ((key.startsWith('allergenMatrix') ||
                    key.endsWith('Matrix') ||
                    key == 'whyMatrixAbsent') &&
                value is String)
              value,
      ];

      // Assert
      expect(values, hasLength(12));
      for (final value in values) {
        expect(value.toLowerCase(), isNot(contains('safe')), reason: value);
        expect(value, isNot(contains('בטוח')), reason: value);
        expect(value.toLowerCase(), isNot(contains('rating')), reason: value);
        expect(value, isNot(contains('דירוג')), reason: value);
      }
    },
  );
}
