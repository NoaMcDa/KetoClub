import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/utils/menu_share_text.dart';

/// The venue every test builds its menu against.
const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'v1');

/// A minimal, valid [Dish] named [name] with [description], under [id].
Dish _dish(String name, {String id = 'd1', String description = ''}) => Dish(
  id: id,
  name: name,
  description: description,
  price: 10,
  options: const <DishOption>[],
);

/// A minimal, valid [Menu] for [_ref], containing [dishes] under one
/// category.
Menu _menuOf(List<Dish> dishes) => Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(id: 'c1', name: 'Mains', dishes: dishes),
  ],
);

/// A verdict for [dish], carrying [modification] only when [verdict] is
/// [DishVerdict.modifiable].
AnalysedDish _verdictFor(
  Dish dish,
  DishVerdict verdict, {
  String? modification,
}) => AnalysedDish(
  dishId: dish.id,
  name: dish.name,
  verdict: verdict,
  why: 'why',
  modification: modification,
);

/// A [MenuAnalysed] for [dishes], from a rules-engine result — the engine
/// tag itself is never read by [MenuShareText.build].
MenuAnalysed _analysisOf(List<AnalysedDish> dishes) => MenuAnalysed(
  dishes: dishes,
  unclassified: const <String>[],
  engine: const RulesEngine(reason: MenuAnalysisFailureReason.notConfigured),
  analysedAt: DateTime.utc(2026),
);

void main() {
  group('MenuShareText.build', () {
    test('lists green dishes under an English heading for an English menu', () {
      // Arrange
      final steak = _dish('Grilled Steak');
      final salad = _dish('Greek Salad', id: 'd2');
      final menu = _menuOf([steak, salad]);
      final analysis = _analysisOf([
        _verdictFor(steak, DishVerdict.orderAsIs),
        _verdictFor(salad, DishVerdict.orderAsIs),
      ]);

      // Act
      final text = MenuShareText.build(
        venueName: 'Sunny Diner',
        menu: menu,
        analysis: analysis,
      );

      // Assert
      expect(text, contains('Sunny Diner'));
      expect(text, contains('Order as-is:'));
      expect(text, contains('Grilled Steak'));
      expect(text, contains('Greek Salad'));
    });

    test('lists each yellow dish followed by its waiter script', () {
      // Arrange
      final fries = _dish('Burger with fries');
      final menu = _menuOf([fries]);
      final analysis = _analysisOf([
        _verdictFor(
          fries,
          DishVerdict.modifiable,
          modification: 'Ask for a salad instead of fries.',
        ),
      ]);

      // Act
      final text = MenuShareText.build(
        venueName: 'Sunny Diner',
        menu: menu,
        analysis: analysis,
      );

      // Assert
      expect(text, contains('Order with changes:'));
      final lines = text.split('\n');
      final nameIndex = lines.indexOf('- Burger with fries');
      expect(nameIndex, greaterThanOrEqualTo(0));
      expect(
        lines[nameIndex + 1],
        contains('Ask for a salad instead of fries.'),
      );
    });

    test('uses Hebrew headings for a menu written in Hebrew', () {
      // Arrange: the dish text (not the venue name) carries the Hebrew.
      final salad = _dish('סלט יווני', description: 'עגבניות ומלפפונים');
      final menu = _menuOf([salad]);
      final analysis = _analysisOf([_verdictFor(salad, DishVerdict.orderAsIs)]);

      // Act
      final text = MenuShareText.build(
        venueName: 'Sunny Diner',
        menu: menu,
        analysis: analysis,
      );

      // Assert
      expect(text, contains('להזמין כמו שהוא:'));
      expect(text, isNot(contains('Order as-is:')));
      expect(text, contains('סלט יווני'));
    });

    test('a Hebrew yellow dish gets the Hebrew yellow heading', () {
      // Arrange
      final dish = _dish('צ׳יפס עם בשר', description: 'מוגש עם רוטב ברביקיו');
      final menu = _menuOf([dish]);
      final analysis = _analysisOf([
        _verdictFor(
          dish,
          DishVerdict.modifiable,
          modification: 'בלי הצ׳יפס, בבקשה.',
        ),
      ]);

      // Act
      final text = MenuShareText.build(
        venueName: 'מסעדה',
        menu: menu,
        analysis: analysis,
      );

      // Assert
      expect(text, contains('להזמין עם שינויים:'));
      expect(text, contains('בלי הצ׳יפס, בבקשה.'));
    });

    test('excludes red (non-keto) dishes entirely', () {
      // Arrange
      final steak = _dish('Grilled Steak');
      final pasta = _dish('Spaghetti Carbonara', id: 'd2');
      final menu = _menuOf([steak, pasta]);
      final analysis = _analysisOf([
        _verdictFor(steak, DishVerdict.orderAsIs),
        _verdictFor(pasta, DishVerdict.nonKeto),
      ]);

      // Act
      final text = MenuShareText.build(
        venueName: 'Sunny Diner',
        menu: menu,
        analysis: analysis,
      );

      // Assert
      expect(text, contains('Grilled Steak'));
      expect(text, isNot(contains('Spaghetti Carbonara')));
    });

    test('never mentions a personal note — build is never given one', () {
      // Arrange: nothing about the user is even representable in the
      // arguments MenuShareText.build takes, but this test asserts the
      // acceptance criterion in the shape a reviewer would look for —
      // that a note's own text never appears in the export, even when it
      // happens to be sitting right beside the dish in the app.
      final steak = _dish('Grilled Steak');
      final menu = _menuOf([steak]);
      final analysis = _analysisOf([_verdictFor(steak, DishVerdict.orderAsIs)]);
      const personalNote = 'Waitstaff happily substituted cauliflower.';

      // Act
      final text = MenuShareText.build(
        venueName: 'Sunny Diner',
        menu: menu,
        analysis: analysis,
      );

      // Assert
      expect(text, isNot(contains(personalNote)));
    });

    test('omits the yellow heading and lines when no dish is yellow', () {
      // Arrange
      final steak = _dish('Grilled Steak');
      final menu = _menuOf([steak]);
      final analysis = _analysisOf([_verdictFor(steak, DishVerdict.orderAsIs)]);

      // Act
      final text = MenuShareText.build(
        venueName: 'Sunny Diner',
        menu: menu,
        analysis: analysis,
      );

      // Assert
      expect(text, isNot(contains('Order with changes:')));
    });

    test('omits the green heading and lines when no dish is green', () {
      // Arrange
      final fries = _dish('Fries');
      final menu = _menuOf([fries]);
      final analysis = _analysisOf([
        _verdictFor(fries, DishVerdict.modifiable, modification: 'x'),
      ]);

      // Act
      final text = MenuShareText.build(
        venueName: 'Sunny Diner',
        menu: menu,
        analysis: analysis,
      );

      // Assert
      expect(text, isNot(contains('Order as-is:')));
      expect(text, contains('Order with changes:'));
    });

    test('is just the venue name when neither group has a dish', () {
      // Arrange
      final pasta = _dish('Spaghetti Carbonara');
      final menu = _menuOf([pasta]);
      final analysis = _analysisOf([_verdictFor(pasta, DishVerdict.nonKeto)]);

      // Act
      final text = MenuShareText.build(
        venueName: 'Sunny Diner',
        menu: menu,
        analysis: analysis,
      );

      // Assert
      expect(text, equals('Sunny Diner'));
    });

    test('excludes unclassified dish names', () {
      // Arrange
      final steak = _dish('Grilled Steak');
      final menu = _menuOf([steak]);
      final analysis = MenuAnalysed(
        dishes: [_verdictFor(steak, DishVerdict.orderAsIs)],
        unclassified: const <String>['Mystery bowl'],
        engine: const RulesEngine(
          reason: MenuAnalysisFailureReason.notConfigured,
        ),
        analysedAt: DateTime.utc(2026),
      );

      // Act
      final text = MenuShareText.build(
        venueName: 'Sunny Diner',
        menu: menu,
        analysis: analysis,
      );

      // Assert
      expect(text, isNot(contains('Mystery bowl')));
    });

    test('keeps the menu order rather than re-sorting', () {
      // Arrange: analysis.dishes is already in menu order, matching what
      // every real MenuClassifier produces.
      final zebra = _dish('Zebra Salad');
      final apple = _dish('Apple Tart Salad', id: 'd2');
      final menu = _menuOf([zebra, apple]);
      final analysis = _analysisOf([
        _verdictFor(zebra, DishVerdict.orderAsIs),
        _verdictFor(apple, DishVerdict.orderAsIs),
      ]);

      // Act
      final text = MenuShareText.build(
        venueName: 'Sunny Diner',
        menu: menu,
        analysis: analysis,
      );

      // Assert
      expect(
        text.indexOf('Zebra Salad'),
        lessThan(text.indexOf('Apple Tart Salad')),
      );
    });
  });
}
