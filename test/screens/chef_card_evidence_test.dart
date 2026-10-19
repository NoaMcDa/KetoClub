// The per-dish chef card evaluates the dish as the menu does (Banto,
// ALG-08b with ALG-16 and ALG-14): the restaurant's allergen matrix and
// the person's own staff answers reach it, for one profile and for a
// group; and the dish's allergy note (ALG-15) sits under the card with
// Copy and Share.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/dish_confirmation.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/chef_card_screen.dart';
import 'package:ketoclub/utils/allergens/allergen_matrix.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/utils/allergens/confirmations.dart';
import 'package:ketoclub/widgets/group_chef_card_view.dart';

import '../fakes/fake_menu_sharer.dart';

final AppLocalizations _en = AppLocalizationsEn();

const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

/// A vegetable salad: no restriction in its text.
const Dish _salad = Dish(
  id: 'salad',
  name: 'סלט ירקות',
  description: 'עגבנייה, מלפפון ובצל',
  price: 30,
  options: <DishOption>[],
);

final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[
    MenuCategory(id: 'c', name: 'סלטים', dishes: <Dish>[_salad]),
  ],
);

final AnalysedDish _green = AnalysedDish(
  dishId: _salad.id,
  name: _salad.name,
  verdict: DishVerdict.orderAsIs,
  why: 'Nothing starchy.',
);

/// The matrix row for the salad: a `contains` milk cell.
const MatrixEvidence _milkCell = MatrixEvidence(
  concerns: <Concern>[
    Concern(
      restrictionId: RestrictionId.milk,
      source: ConcernSource.matrix,
      certainty: Certainty.stated,
      tier: EvidenceTier.declared,
    ),
  ],
);

/// The person's answer after an earlier meal: the staff said there were
/// peanuts in the dressing.
final List<ConfirmationEvidence> _peanutsConfirmed = <ConfirmationEvidence>[
  ConfirmationEvidence(
    restrictionId: RestrictionId.peanuts,
    polarity: ConfirmationPolarity.present,
    day: DateTime(2026, 5, 12),
    source: ConcernSource.description,
    matchedText: 'בוטנים',
  ),
];

final DietaryProfile _profile = DietaryProfile.empty
    .withEntry(RestrictionId.milk)
    .withEntry(RestrictionId.peanuts);

/// The question the card asks for [subject] stated in the dish.
String _without(String subject) => 'אפשר להכין את המנה בלי $subject?';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final copied = <String>[];

  setUp(() {
    copied.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<Object?, Object?>;
            copied.add(args['text']! as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('the per-dish chef card reads the menu evidence', () {
    testWidgets('without the matrix or the staff answers, the salad asks '
        'nothing about milk or peanuts', (tester) async {
      // Act
      await _pump(
        tester,
        ChefCardScreen(
          profile: _profile,
          dish: _salad,
          analysed: _green,
          menu: _menu,
        ),
      );

      // Assert
      expect(find.textContaining(_without('חלב')), findsNothing);
      expect(find.textContaining(_without('בוטנים')), findsNothing);
    });

    testWidgets('a matrix contains cell and a staff confirmation each ask '
        'their question on the card', (tester) async {
      // Act
      await _pump(
        tester,
        ChefCardScreen(
          profile: _profile,
          dish: _salad,
          analysed: _green,
          menu: _menu,
          matrix: _milkCell,
          confirmations: _peanutsConfirmed,
        ),
      );

      // Assert
      expect(find.textContaining(_without('חלב')), findsWidgets);
      expect(find.textContaining(_without('בוטנים')), findsWidgets);
    });

    testWidgets('the group card passes them to every person', (tester) async {
      // Arrange: me (milk and peanuts) and Dana (keto).
      final me = NamedProfile(
        id: NamedProfile.primaryId,
        name: '',
        profile: _profile,
      );
      const dana = NamedProfile(id: 'p1', name: 'Dana');

      // Act
      await _pump(
        tester,
        ChefCardScreen(
          profile: _profile,
          people: <NamedProfile>[me, dana],
          dish: _salad,
          analysed: _green,
          menu: _menu,
          matrix: _milkCell,
          confirmations: _peanutsConfirmed,
        ),
      );

      // Assert: the questions sit in my section.
      final mine = find.byKey(groupChefCardSectionKey('אני'));
      expect(mine, findsOneWidget);
      expect(
        find.descendant(
          of: mine,
          matching: find.textContaining(_without('חלב')),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: mine,
          matching: find.textContaining(_without('בוטנים')),
        ),
        findsWidgets,
      );
    });
  });

  group("the dish's allergy note", () {
    testWidgets('shows the dish note under the card, copies it and shares '
        'it', (tester) async {
      // Arrange
      final sharer = FakeMenuSharer();
      await _pump(
        tester,
        ChefCardScreen(
          profile: _profile,
          dish: _salad,
          analysed: _green,
          menu: _menu,
          matrix: _milkCell,
          menuSharer: sharer,
        ),
      );
      final expected = ChefCardText.dishAllergyNote(
        _profile,
        dishName: _salad.name,
        concerns: const <Concern>[
          Concern(
            restrictionId: RestrictionId.milk,
            source: ConcernSource.matrix,
            certainty: Certainty.stated,
            tier: EvidenceTier.declared,
          ),
        ],
        hebrew: true,
      )!;

      // Assert: the note, in the card's language (the menu's).
      expect(find.text(_en.chefCardAllergyNoteTitle), findsOneWidget);
      final note = tester.widget<Text>(find.byKey(chefCardAllergyNoteKey));
      expect(note.data, expected);
      expect(note.data, contains('בלי חלב'));

      // Act: copy, then share.
      await tester.ensureVisible(find.byKey(chefCardAllergyNoteCopyKey));
      await tester.tap(find.byKey(chefCardAllergyNoteCopyKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(chefCardAllergyNoteShareKey));
      await tester.pumpAndSettle();

      // Assert
      expect(copied, <String>[expected]);
      expect(find.text(_en.menuAllergyNoteCopied), findsOneWidget);
      expect(sharer.shareCalls.single.text, expected);
      expect(sharer.shareCalls.single.subject, _en.menuAllergyNoteSubject);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('follows the language toggle', (tester) async {
      // Arrange
      await _pump(
        tester,
        ChefCardScreen(
          profile: _profile,
          dish: _salad,
          analysed: _green,
          menu: _menu,
          matrix: _milkCell,
        ),
      );

      // Act
      await tester.tap(find.text(_en.settingsLanguageEnglish));
      await tester.pumpAndSettle();

      // Assert
      final note = tester.widget<Text>(find.byKey(chefCardAllergyNoteKey));
      expect(note.data, startsWith('I have an allergy to milk and peanuts.'));
      expect(note.data, contains('please make it without milk'));
      expect(find.byKey(chefCardAllergyNoteShareKey), findsNothing);
    });

    testWidgets('the profile card has no dish note', (tester) async {
      await _pump(tester, ChefCardScreen(profile: _profile));
      expect(find.byKey(chefCardAllergyNoteKey), findsNothing);
    });
  });
}
