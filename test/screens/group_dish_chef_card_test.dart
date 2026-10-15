// The chef card for one dish read for several people (Banto, ALG-12,
// issue #354, the follow-up of ALG-08b): a section per person with their
// own lines and questions, the dish named once, one closing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/chef_card_screen.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/widgets/group_chef_card_view.dart';

import '../fakes/fake_menu_sharer.dart';

final AppLocalizations _en = AppLocalizationsEn();

const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

/// Me, with sesame.
final NamedProfile _me = NamedProfile(
  id: NamedProfile.primaryId,
  name: '',
  profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
);

/// Dana, keto (an empty profile reads as keto).
const NamedProfile _dana = NamedProfile(id: 'p1', name: 'Dana');

Dish _dish(String id, String name) => Dish(
  id: id,
  name: name,
  description: '',
  price: 30,
  options: const <DishOption>[],
);

/// The tahini salad: sesame stated in its name, and a sesame signal.
final Dish _salad = _dish('salad', 'סלט עם טחינה');

Menu _menu(List<Dish> dishes) => Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(id: 'c', name: 'מנות', dishes: dishes),
  ],
);

AnalysedDish _green(Dish dish) => AnalysedDish(
  dishId: dish.id,
  name: dish.name,
  verdict: DishVerdict.orderAsIs,
  why: 'Nothing starchy.',
);

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

ChefCardScreen _screen(Dish dish, {FakeMenuSharer? sharer}) => ChefCardScreen(
  profile: _me.profile,
  people: <NamedProfile>[_me, _dana],
  dish: dish,
  analysed: _green(dish),
  menu: _menu(<Dish>[dish]),
  menuSharer: sharer,
);

/// [text] drawn inside the section headed [heading].
Finder _inSection(String heading, String text) => find.descendant(
  of: find.byKey(groupChefCardSectionKey(heading)),
  matching: find.textContaining(text),
);

void main() {
  group('ChefCardScreen for a dish and a group', () {
    testWidgets('one section per person: the question under the person it '
        'is for, the dish once, the cross-contact closing once', (
      tester,
    ) async {
      // Act
      await _pump(tester, _screen(_salad));

      // Assert
      expect(find.byType(GroupChefCardView), findsOneWidget);
      expect(find.byKey(groupChefCardSectionKey('אני')), findsOneWidget);
      expect(find.byKey(groupChefCardSectionKey('Dana')), findsOneWidget);
      expect(_inSection('אני', 'אלרגיה לשומשום'), findsOneWidget);
      expect(_inSection('אני', 'בלי שומשום?'), findsOneWidget);
      expect(_inSection('Dana', 'קטו'), findsOneWidget);
      expect(_inSection('Dana', 'בלי שומשום'), findsNothing);
      expect(find.text('המנה שאני רוצה להזמין: סלט עם טחינה'), findsOneWidget);
      expect(
        find.text(ChefCardText.closingLine(crossContact: true, hebrew: true)),
        findsOneWidget,
      );
      expect(find.text(_en.helperToolSentence), findsOneWidget);
    });

    testWidgets('the toggle re-composes every section in English', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, _screen(_salad));

      // Act
      await tester.tap(find.text(_en.settingsLanguageEnglish));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byKey(groupChefCardSectionKey('Me')), findsOneWidget);
      expect(
        _inSection('Me', 'Can this be made without sesame?'),
        findsOneWidget,
      );
      expect(find.text('The dish I would like: סלט עם טחינה'), findsOneWidget);
      expect(find.text('אפשר להכין את המנה בלי שומשום?'), findsNothing);
    });

    testWidgets('closes with thanks and asks nothing when the dish raises '
        'nothing', (tester) async {
      // Arrange: a steak on a menu with no sesame, fryer or bakery.
      final steak = _dish('steak', 'סטייק אנטריקוט');

      // Act
      await _pump(tester, _screen(steak));

      // Assert: both sections state their lines; no question anywhere.
      expect(_inSection('אני', 'אלרגיה לשומשום'), findsOneWidget);
      expect(find.textContaining('?'), findsNothing);
      expect(find.text('תודה.'), findsOneWidget);
    });

    testWidgets('Share carries the whole group dish card in order', (
      tester,
    ) async {
      // Arrange
      final sharer = FakeMenuSharer();
      await _pump(tester, _screen(_salad, sharer: sharer));

      // Act
      await tester.ensureVisible(find.byKey(chefCardShareKey));
      await tester.tap(find.byKey(chefCardShareKey));
      await tester.pumpAndSettle();

      // Assert: the question sits under the first person, before Dana.
      final lines = sharer.shareCalls.single.text.split('\n');
      expect(lines.first, startsWith('שלום'));
      expect(
        lines,
        containsAllInOrder(<String>[
          'אני:',
          'אפשר להכין את המנה בלי שומשום?',
          'Dana:',
          'המנה שאני רוצה להזמין: סלט עם טחינה',
          ChefCardText.closingLine(crossContact: true, hebrew: true),
        ]),
      );
    });
  });
}
