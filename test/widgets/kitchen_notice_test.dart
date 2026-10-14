// The menu screen's kitchen notice and the kitchen concern's words on the
// dish card and the Why sheet (Banto; ALG-07, issue #349). Plain
// `flutter test` compiles the flag off, so each test passes `bantoMode`.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/utils/allergens/kitchen_reach.dart';
import 'package:ketoclub/utils/allergens/kitchen_signals.dart';
import 'package:ketoclub/widgets/app_notice.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/kitchen_notice.dart';
import 'package:ketoclub/widgets/why_sheet.dart';

const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

Dish _dish(String id, String name) => Dish(
  id: id,
  name: name,
  description: '',
  price: 10,
  options: const <DishOption>[],
);

Menu _menuOf(List<Dish> dishes) => Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(id: 'c1', name: 'Mains', dishes: dishes),
  ],
);

/// Fries and bread: a fryer and a bakery.
final KitchenReach _english = KitchenReach.of(
  _menuOf(<Dish>[
    _dish('fries', 'French fries'),
    _dish('bread', 'Sourdough bread'),
    _dish('salad', 'Green salad'),
  ]),
);

/// The same in Hebrew.
final KitchenReach _hebrew = KitchenReach.of(
  _menuOf(<Dish>[_dish('chips', "צ'יפס"), _dish('bread', 'לחם מחמצת')]),
);

/// Fries, bread and a tahini salad: a fryer, a bakery and sesame.
final KitchenReach _three = KitchenReach.of(
  _menuOf(<Dish>[
    _dish('fries', 'French fries'),
    _dish('bread', 'Sourdough bread'),
    _dish('salad', 'Salad with tahini'),
  ]),
);

final DietaryProfile _celiac = DietaryProfile.empty.withEntry(
  RestrictionId.gluten,
);

KitchenSignal _signal(KitchenReach reach, KitchenSignalKind kind) =>
    reach.signals.firstWhere((signal) => signal.kind == kind);

Future<AppLocalizations> _pump(
  WidgetTester tester, {
  required KitchenReach kitchen,
  required DietaryProfile profile,
  bool bantoMode = true,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(
        body: SingleChildScrollView(
          child: KitchenNotice(
            kitchen: kitchen,
            profile: profile,
            bantoMode: bantoMode,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return lookupAppLocalizations(locale);
}

void main() {
  late List<MethodCall> platformCalls;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    platformCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('KitchenNotice, collapsed', () {
    testWidgets('one line naming the kitchens (en)', (tester) async {
      // Act
      final l10n = await _pump(tester, kitchen: _english, profile: _celiac);

      // Assert
      expect(find.byKey(kitchenNoticeKey), findsOneWidget);
      expect(find.byType(AppNotice), findsOneWidget);
      expect(
        find.text(
          'This kitchen has a fryer and a bakery — ask about cross-contact',
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.kitchenNoticeShow), findsOneWidget);
      expect(
        find.byKey(kitchenNoticeRowKey(KitchenSignalKind.fryer)),
        findsNothing,
      );
    });

    testWidgets('one line naming the kitchens (he)', (tester) async {
      // Act
      await _pump(
        tester,
        kitchen: _hebrew,
        profile: _celiac,
        locale: const Locale('he'),
      );

      // Assert
      expect(
        find.text('במטבח הזה יש מטגנת ומאפייה — כדאי לשאול על מגע צולב'),
        findsOneWidget,
      );
      expect(find.text('הצגת השאלות'), findsOneWidget);
    });

    testWidgets('three kitchens join with commas and "and"', (tester) async {
      // Act
      await _pump(
        tester,
        kitchen: _three,
        profile: _celiac.withEntry(RestrictionId.sesame),
      );

      // Assert
      expect(
        find.text(
          'This kitchen has a fryer, a bakery and sesame — ask about '
          'cross-contact',
        ),
        findsOneWidget,
      );
    });

    testWidgets('names only the kitchens a strict entry cares about', (
      tester,
    ) async {
      // Act: sesame is threatened by the bakery and by sesame, not by the
      // fryer.
      await _pump(
        tester,
        kitchen: _three,
        profile: DietaryProfile.empty
            .withEntry(RestrictionId.sesame)
            .withEntry(RestrictionId.lactose),
      );

      // Assert
      expect(
        find.text(
          'This kitchen has a bakery and sesame — ask about cross-contact',
        ),
        findsOneWidget,
      );
    });
  });

  group('KitchenNotice, expanded', () {
    testWidgets('one row per signal with its question and a copy button '
        '(en)', (tester) async {
      // Arrange
      final l10n = await _pump(tester, kitchen: _english, profile: _celiac);

      // Act
      await tester.tap(find.text(l10n.kitchenNoticeShow));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(l10n.kitchenNoticeHide), findsOneWidget);
      for (final kind in <KitchenSignalKind>[
        KitchenSignalKind.fryer,
        KitchenSignalKind.bakery,
      ]) {
        final row = find.byKey(kitchenNoticeRowKey(kind));
        expect(row, findsOneWidget);
        expect(
          find.descendant(
            of: row,
            matching: find.text(_signal(_english, kind).questionEn),
          ),
          findsOneWidget,
        );
        expect(find.byKey(kitchenNoticeCopyKey(kind)), findsOneWidget);
      }
      expect(find.text('Fryer'), findsOneWidget);
      expect(find.text('Bakery'), findsOneWidget);
      expect(find.text('Matters for: Gluten'), findsNWidgets(2));
      expect(find.text('Seen in: French fries'), findsOneWidget);
      expect(find.text('Seen in: Sourdough bread'), findsOneWidget);
    });

    testWidgets('a Hebrew menu asks in Hebrew in the English UI', (
      tester,
    ) async {
      // Arrange
      final l10n = await _pump(tester, kitchen: _hebrew, profile: _celiac);

      // Act
      await tester.tap(find.text(l10n.kitchenNoticeShow));
      await tester.pumpAndSettle();

      // Assert
      final question = _signal(_hebrew, KitchenSignalKind.fryer).questionHe;
      expect(find.text(question), findsOneWidget);
      expect(
        tester.widget<Text>(find.text(question)).textDirection,
        TextDirection.rtl,
      );
    });

    testWidgets('the Hebrew UI names the restriction in Hebrew', (
      tester,
    ) async {
      // Arrange
      final l10n = await _pump(
        tester,
        kitchen: _hebrew,
        profile: _celiac,
        locale: const Locale('he'),
      );

      // Act
      await tester.tap(find.text(l10n.kitchenNoticeShow));
      await tester.pumpAndSettle();

      // Assert
      expect(find.textContaining('רלוונטי עבור:'), findsNWidgets(2));
      expect(find.text(l10n.kitchenNoticeQuestionLabel), findsNWidgets(2));
    });

    testWidgets('copy puts the question on the clipboard', (tester) async {
      // Arrange
      final l10n = await _pump(tester, kitchen: _english, profile: _celiac);
      await tester.tap(find.text(l10n.kitchenNoticeShow));
      await tester.pumpAndSettle();

      // Act
      await tester.tap(
        find.byKey(kitchenNoticeCopyKey(KitchenSignalKind.fryer)),
      );
      await tester.pump();

      // Assert
      final setData = platformCalls.singleWhere(
        (call) => call.method == 'Clipboard.setData',
      );
      expect(
        (setData.arguments as Map<Object?, Object?>)['text'],
        _signal(_english, KitchenSignalKind.fryer).questionEn,
      );
      expect(find.text(l10n.actionCopied), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text(l10n.actionCopied), findsNothing);
    });

    testWidgets('hide collapses it again', (tester) async {
      // Arrange
      final l10n = await _pump(tester, kitchen: _english, profile: _celiac);
      await tester.tap(find.text(l10n.kitchenNoticeShow));
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.text(l10n.kitchenNoticeHide));
      await tester.pumpAndSettle();

      // Assert
      expect(
        find.byKey(kitchenNoticeRowKey(KitchenSignalKind.fryer)),
        findsNothing,
      );
      expect(find.text(l10n.kitchenNoticeShow), findsOneWidget);
    });
  });

  group('KitchenNotice, hidden', () {
    for (final (label, profile, bantoMode) in <(String, DietaryProfile, bool)>[
      ('a keto-only (empty) profile', DietaryProfile.empty, true),
      (
        'a keto entry',
        DietaryProfile.empty.withEntry(RestrictionId.keto),
        true,
      ),
      (
        'a flexible-only profile',
        DietaryProfile.empty
            .withEntry(RestrictionId.lactose)
            .withEntry(RestrictionId.vegan),
        true,
      ),
      (
        'a strict entry no signal threatens',
        DietaryProfile.empty.withEntry(RestrictionId.mustard),
        true,
      ),
      ('bantoMode off', _celiac, false),
    ]) {
      testWidgets('for $label', (tester) async {
        // Act
        await _pump(
          tester,
          kitchen: _english,
          profile: profile,
          bantoMode: bantoMode,
        );

        // Assert
        expect(find.byKey(kitchenNoticeKey), findsNothing);
        expect(find.byType(AppNotice), findsNothing);
      });
    }

    testWidgets('for a menu with no signal', (tester) async {
      // Act
      await _pump(tester, kitchen: KitchenReach.empty, profile: _celiac);

      // Assert
      expect(find.byKey(kitchenNoticeKey), findsNothing);
    });
  });

  group('the kitchen concern in words', () {
    const fryerConcern = Concern(
      restrictionId: RestrictionId.gluten,
      source: ConcernSource.kitchen,
      certainty: Certainty.suspected,
      tier: EvidenceTier.inferred,
      matchedText: 'fryer',
      waiterQuestion: 'Do the fried dishes share a fryer?',
    );
    const unknownConcern = Concern(
      restrictionId: RestrictionId.gluten,
      source: ConcernSource.kitchen,
      certainty: Certainty.suspected,
      tier: EvidenceTier.inferred,
      matchedText: 'smoker',
    );

    test('kitchenKindOf reads only kitchen concerns', () {
      // Assert
      expect(kitchenKindOf(fryerConcern), KitchenSignalKind.fryer);
      expect(kitchenKindOf(unknownConcern), isNull);
      expect(
        kitchenKindOf(
          const Concern(
            restrictionId: RestrictionId.gluten,
            source: ConcernSource.name,
            certainty: Certainty.stated,
            tier: EvidenceTier.stated,
            matchedText: 'fryer',
          ),
        ),
        isNull,
      );
    });

    for (final locale in AppLocalizations.supportedLocales) {
      test('the dish card and the Why sheet name the kitchen '
          '(${locale.languageCode})', () {
        // Arrange
        final l10n = lookupAppLocalizations(locale);
        final fryer = l10n.kitchenKindFryer;

        // Assert
        expect(
          concernSourceLabel(l10n, fryerConcern),
          l10n.concernSourceWithText(l10n.concernSourceKitchen, fryer),
        );
        expect(
          concernSourceLabel(l10n, unknownConcern),
          l10n.concernSourceKitchen,
        );
        expect(
          whyConcernSourcePhrase(l10n, fryerConcern),
          l10n.whySourceKitchen(fryer),
        );
        expect(
          whyConcernSourcePhrase(l10n, unknownConcern),
          l10n.whySourceKitchenGeneric,
        );
      });
    }

    testWidgets('the Why sheet shows the kitchen line, not "Matched"', (
      tester,
    ) async {
      // Act
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: WhySheet(
              dishName: 'French fries',
              concerns: <Concern>[fryerConcern],
              strictProfile: true,
              bantoMode: true,
            ),
          ),
        ),
      );

      // Assert
      expect(
        find.text('This kitchen has a fryer — ask about cross-contact'),
        findsOneWidget,
      );
      expect(find.textContaining('Matched'), findsNothing);
      expect(find.text('Do the fried dishes share a fryer?'), findsOneWidget);
    });
  });

  test('no kitchen string says "safe", in either language', () {
    // Arrange
    final values = <String>[
      for (final path in <String>['lib/l10n/app_en.arb', 'lib/l10n/app_he.arb'])
        for (final MapEntry(:key, :value) in (jsonDecode(
          File(path).readAsStringSync(),
        ) as Map<String, Object?>).entries)
          if ((key.startsWith('kitchen') ||
                  key.startsWith('whySourceKitchen') ||
                  key == 'concernSourceKitchen') &&
              value is String)
            value,
    ];

    // Assert
    expect(values, hasLength(greaterThanOrEqualTo(48)));
    for (final value in values) {
      expect(value.toLowerCase(), isNot(contains('safe')), reason: value);
      expect(value, isNot(contains('בטוח')), reason: value);
    }
  });
}
