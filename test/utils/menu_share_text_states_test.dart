// MenuShareText in Banto's state mode (ALG-05, issue #347): groups by
// on-device state, worded by strictness in the menu's language, never
// "safe", the profile never written; keto-only stays today's text.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/menu_share_text.dart';
import 'package:ketoclub/utils/profile_wording.dart';
import 'package:ketoclub/utils/verdict_counts.dart';

/// "safe" as a word in English, "בטוח" anywhere in Hebrew.
final RegExp _safe = RegExp('(?<![A-Za-z])safe|בטוח', caseSensitive: false);

/// A dish named [name] with [id].
Dish _dish(String id, String name) => Dish(
  id: id,
  name: name,
  description: '',
  price: 10,
  options: const <DishOption>[],
);

/// A one-category menu of [dishes].
Menu _menu(List<Dish> dishes) => Menu(
  venueRef: const VenueRef(source: MenuSource.wolt, platformId: 'v'),
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: <MenuCategory>[
    MenuCategory(id: 'c', name: 'Mains', dishes: dishes),
  ],
);

/// A green analysis of every dish in [menu].
MenuAnalysed _analysis(Menu menu) => MenuAnalysed(
  dishes: <AnalysedDish>[
    for (final dish in menu.allDishes)
      AnalysedDish(
        dishId: dish.id,
        name: dish.name,
        verdict: DishVerdict.orderAsIs,
        why: 'why',
      ),
  ],
  unclassified: const <String>[],
  engine: const LlmEngine(model: 'test-model'),
  analysedAt: DateTime.utc(2026),
);

/// [analysis]'s dishes evaluated to [states] by id.
Map<String, EvaluatedDish> _evaluations(
  MenuAnalysed analysis,
  Map<String, (DishState, String?)> states,
) => <String, EvaluatedDish>{
  for (final dish in analysis.dishes)
    dish.dishId: EvaluatedDish(
      dish: dish,
      concerns: const <Concern>[],
      state: states[dish.dishId]!.$1,
      modification: states[dish.dishId]!.$2,
    ),
};

void main() {
  final english = _menu(<Dish>[
    _dish('a', 'Steak'),
    _dish('b', 'Hummus plate'),
    _dish('c', 'Nut cake'),
    _dish('d', 'Tahini salad'),
  ]);
  final englishAnalysis = _analysis(english);
  final englishStates = _evaluations(
    englishAnalysis,
    <String, (DishState, String?)>{
      'a': (DishState.fits, null),
      'b': (DishState.fitsWithChange, 'Ask for it without tahini'),
      'c': (DishState.ask, null),
      'd': (DishState.avoid, null),
    },
  );

  test('strict: groups by state, leaves avoid out, never says safe', () {
    // Act
    final text = MenuShareText.build(
      venueName: 'Cafe',
      menu: english,
      analysis: englishAnalysis,
      wording: ProfileWording.strict,
      evaluations: englishStates,
    );

    // Assert
    expect(
      text,
      'Cafe\n'
      '\n'
      'No trigger found — ask the restaurant:\n'
      '- Steak\n'
      '\n'
      'With a change:\n'
      '- Hummus plate\n'
      '  Ask for it without tahini\n'
      '\n'
      'Ask the restaurant first:\n'
      '- Nut cake\n'
      '\n'
      'Read from the menu text only. Ask the restaurant.',
    );
    expect(text, isNot(matches(_safe)));
  });

  test('flexible: "Fits", and no closing line', () {
    // Act
    final text = MenuShareText.build(
      venueName: 'Cafe',
      menu: english,
      analysis: englishAnalysis,
      wording: ProfileWording.flexible,
      evaluations: englishStates,
    );

    // Assert
    expect(text, startsWith('Cafe\n\nFits:\n- Steak\n'));
    expect(text, isNot(contains('Read from the menu text only')));
  });

  test('strict, Hebrew menu: Hebrew headings, never בטוח', () {
    // Arrange
    final hebrew = _menu(<Dish>[
      _dish('a', 'סטייק'),
      _dish('c', 'עוגת אגוזים'),
    ]);
    final analysis = _analysis(hebrew);

    // Act
    final text = MenuShareText.build(
      venueName: 'קפה',
      menu: hebrew,
      analysis: analysis,
      wording: ProfileWording.strict,
      evaluations: _evaluations(analysis, <String, (DishState, String?)>{
        'a': (DishState.fits, null),
        'c': (DishState.ask, null),
      }),
    );

    // Assert
    expect(text, contains('לא נמצא חשש — לשאול את המסעדה:'));
    expect(text, contains('לשאול את המסעדה קודם:'));
    expect(text, contains('נקרא מטקסט התפריט בלבד'));
    expect(text, isNot(matches(_safe)));
  });

  test("keto-only wording ignores evaluations: today's text", () {
    // Act
    final today = MenuShareText.build(
      venueName: 'Cafe',
      menu: english,
      analysis: englishAnalysis,
    );
    final withStates = MenuShareText.build(
      venueName: 'Cafe',
      menu: english,
      analysis: englishAnalysis,
      evaluations: englishStates,
    );

    // Assert
    expect(withStates, today);
  });

  group('VerdictCounts.ofStates', () {
    test('counts each state, food only', () {
      // Arrange
      final menu = _menu(<Dish>[
        _dish('a', 'Steak'),
        _dish('b', 'Salad'),
        _dish('c', 'Cake'),
        _dish('d', 'Pasta'),
        _dish('e', 'Coca-Cola'),
      ]);

      // Act
      final counts = VerdictCounts.ofStates(menu, const <String, DishState>{
        'a': DishState.fits,
        'b': DishState.fitsWithChange,
        'c': DishState.ask,
        'd': DishState.avoid,
        'e': DishState.fits,
      });

      // Assert: the drink is listed but not counted (D21).
      expect(
        counts,
        const VerdictCounts(
          green: 1,
          yellow: 1,
          hiddenCarbYellow: 0,
          red: 1,
          ask: 1,
        ),
      );
      expect(counts.total, 4);
      expect(counts.toString(), contains('ask: 1'));
    });

    test('a keto count prints as before, with no ask', () {
      const counts = VerdictCounts(
        green: 1,
        yellow: 0,
        hiddenCarbYellow: 0,
        red: 0,
      );
      expect(
        counts.toString(),
        'VerdictCounts(green: 1, yellow: 0, hiddenCarbYellow: 0, red: 0)',
      );
    });
  });
}
