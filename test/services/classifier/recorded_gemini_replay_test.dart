// Replays the two real Gemini replies recorded by the #165 smoke test
// (`test/fixtures/llm/smoke_*.json`, architecture.md §17.1) through
// `MenuResponseParser.parse`, against the menus they answered.
//
// What these fixtures are, and are not:
//
// - They are the model's own reply bodies, redacted, from before issue
//   #213: six properties per dish, no `hidden_carbs`. The wrapper object
//   carries the reply text under `content`, and the model id under `model`.
// - The Hebrew reply answered ten dishes of the recorded Wolt menu
//   (`wolt_hamosad_menu.json`); nine come back. Its `id` values are the
//   first sixteen characters of the menu's 24-character ids, so rule 3's id
//   match never fires and every dish is placed by name. Its first dish is
//   named "ספיישל סמאשבורגר 🌟", where the 2026-09-25 recording says
//   "סמאשבורגר": the live menu had moved on by the smoke run on 09-28.
// - The English menu was never recorded, only its reply. The menu below is
//   rebuilt from that reply's own `id` and `name` values, so for English the
//   provenance checks are a round trip, not an independent proof; the
//   verdicts, the shape tolerance and the language of the text are real.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_response_parser.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/wolt/wolt_menu_mapper.dart';

/// The engine every replay is stamped with: the model the wrapper names.
const AnalysisEngine _engine = LlmEngine(model: 'recorded');

/// The timestamp every replay is stamped with.
final DateTime _analysedAt = DateTime.utc(2026, 9, 28);

/// The text of a Hebrew letter, and of a Latin one.
final RegExp _hebrew = RegExp('[֐-׿]');
final RegExp _latin = RegExp('[A-Za-z]');

/// A recorded reply: its raw body, as the model sent it, and its dishes
/// decoded for comparison.
class _Recording {
  new(String fileName) {
    final wrapper = jsonDecode(
      File('test/fixtures/llm/$fileName').readAsStringSync(),
    ) as Map<String, Object?>;
    body = wrapper['content']! as String;
    final decoded = jsonDecode(body) as Map<String, Object?>;
    dishes = (decoded['dishes']! as List<Object?>).cast<Map<String, Object?>>();
  }

  /// The reply text exactly as the model sent it.
  late final String body;

  /// The reply's dish elements, as recorded.
  late final List<Map<String, Object?>> dishes;
}

/// A one-category menu of [dishes].
Menu _menuOf(VenueRef ref, List<Dish> dishes) => Menu(
  venueRef: ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026, 9, 28),
  categories: [MenuCategory(id: 'cat', name: 'Menu', dishes: dishes)],
);

/// The recorded Wolt menu, mapped as the app maps it.
Menu _recordedWoltMenu() {
  const ref = VenueRef(source: MenuSource.wolt, platformId: 'hamosad');
  final payload = jsonDecode(
    File('test/fixtures/wolt_hamosad_menu.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final result = WoltMenuMapper.toMenu(
    payload,
    ref: ref,
    fetchedAt: DateTime.utc(2026, 9, 25),
  );
  return (result as MenuFetched).menu;
}

/// The recorded Wolt dishes the Hebrew reply's ids are prefixes of, in
/// reply order.
List<Dish> _answeredHebrewDishes(Menu wolt, _Recording reply) => [
  for (final element in reply.dishes)
    wolt.allDishes.singleWhere(
      (dish) => dish.id.startsWith(element['id']! as String),
    ),
];

/// The Hebrew smoke menu: the answered dishes with the one name the menu
/// had changed by the smoke run (see the file header) as the reply printed
/// it.
Menu _hebrewSmokeMenu(Menu wolt, _Recording reply) {
  final dishes = _answeredHebrewDishes(wolt, reply);
  final renamed = <Dish>[
    for (var i = 0; i < dishes.length; i++)
      Dish(
        id: dishes[i].id,
        name: reply.dishes[i]['name']! as String,
        description: dishes[i].description,
        price: dishes[i].price,
        options: dishes[i].options,
      ),
  ];
  return _menuOf(wolt.venueRef, renamed);
}

/// The English smoke menu, rebuilt from the reply's own ids and names.
Menu _englishSmokeMenu(_Recording reply) => _menuOf(
  const VenueRef(source: MenuSource.wolt, platformId: 'english-smoke'),
  [
    for (final element in reply.dishes)
      Dish(
        id: element['id']! as String,
        name: element['name']! as String,
        description: '',
        price: 0,
        options: const [],
      ),
  ],
);

/// Parses [reply] against [menu] with the recorded engine and timestamp.
MenuAnalysed _replay(_Recording reply, Menu menu) {
  final result = MenuResponseParser.parse(
    reply.body,
    source: menu,
    analysedAt: _analysedAt,
    engine: _engine,
  );
  return result as MenuAnalysed;
}

/// The recorded verdict of [element].
DishVerdict _recordedVerdict(Map<String, Object?> element) =>
    DishVerdict.values.byName(element['verdict']! as String);

/// Checks the properties both recordings must share once replayed.
void _expectFaithfulReplay(MenuAnalysed analysis, Menu menu, _Recording reply) {
  final menuDishes = menu.allDishes.toList();
  final menuIds = menuDishes.map((dish) => dish.id).toList();
  final placedIds = analysis.dishes.map((dish) => dish.dishId).toList();

  // Nothing invented and nothing duplicated: every placed dish is a menu
  // dish, once.
  expect(placedIds.toSet(), hasLength(placedIds.length));
  expect(menuIds, containsAll(placedIds));

  // Every recorded element came through under its menu dish, in order.
  expect(analysis.dishes, hasLength(reply.dishes.length));
  for (var i = 0; i < reply.dishes.length; i++) {
    final element = reply.dishes[i];
    final placed = analysis.dishes[i];
    expect(placed.dishId, menuDishes[i].id, reason: '${element['name']}');
    expect(placed.name, menuDishes[i].name);
    expect(placed.verdict, _recordedVerdict(element), reason: placed.name);
    expect(placed.why, element['why']);
    expect(placed.modification, element['modification']);
    expect(
      placed.netCarbsEstimate,
      (element['net_carbs_estimate'] as num?)?.toDouble(),
      reason: placed.name,
    );
    // The recording predates `hidden_carbs`: absent reads as empty.
    expect(element.containsKey('hidden_carbs'), isFalse);
    expect(placed.hiddenCarbs, isEmpty, reason: placed.name);
  }

  // Yellow carries an instruction, and only yellow does (constraint 7).
  for (final dish in analysis.dishes) {
    expect(
      dish.modification != null,
      dish.verdict == DishVerdict.modifiable,
      reason: dish.name,
    );
  }
  expect(analysis.engine, _engine);
  expect(analysis.analysedAt, _analysedAt);
}

void main() {
  group('Recorded Gemini replies (issue #165 smoke test)', () {
    group('the Hebrew reply on the recorded Wolt menu', () {
      final reply = _Recording('smoke_10_dish_hebrew.json');
      final wolt = _recordedWoltMenu();
      final menu = _hebrewSmokeMenu(wolt, reply);

      test('parse given the recorded reply keeps all nine verdicts '
          'and the ids the model shortened', () {
        // Arrange: the reply's ids are 16-character prefixes of the menu's
        // 24-character ones, so rule 3's id match cannot fire.
        for (final element in reply.dishes) {
          expect(
            menu.allDishes.map((d) => d.id),
            isNot(contains(element['id'])),
          );
        }

        // Act
        final analysis = _replay(reply, menu);

        // Assert
        _expectFaithfulReplay(analysis, menu, reply);
        expect(analysis.unclassified, isEmpty);
        expect(
          analysis.dishes.where((d) => d.verdict == DishVerdict.modifiable),
          hasLength(7),
        );
        expect(
          analysis.dishes.where((d) => d.verdict == DishVerdict.nonKeto),
          hasLength(2),
        );
        expect(
          analysis.dishes.where((d) => d.verdict == DishVerdict.orderAsIs),
          isEmpty,
        );
      });

      test('parse given the recorded reply keeps why and modification '
          'in Hebrew', () {
        // Act
        final analysis = _replay(reply, menu);

        // Assert
        for (final dish in analysis.dishes) {
          expect(dish.why, matches(_hebrew), reason: dish.name);
          expect(dish.why, isNot(matches(_latin)), reason: dish.name);
          final modification = dish.modification;
          if (modification != null) {
            expect(modification, matches(_hebrew), reason: dish.name);
            expect(modification, isNot(matches(_latin)), reason: dish.name);
          }
        }
      });

      test('parse given the one dish the recording named differently '
          'from the 09-25 menu does not place it and lists both names', () {
        // Arrange: the menu exactly as recorded on 09-25, where the first
        // dish is "סמאשבורגר", not "ספיישל סמאשבורגר 🌟".
        final asRecorded = _menuOf(
          wolt.venueRef,
          _answeredHebrewDishes(wolt, reply),
        );

        // Act
        final analysis = _replay(reply, asRecorded);

        // Assert: its short id names nothing and its name is too far from
        // the recorded one, so it is not given a verdict (rule 3) and the
        // source dish is listed as one the model skipped (rule 7); the
        // other eight are placed by name.
        expect(analysis.dishes, hasLength(8));
        expect(
          analysis.unclassified,
          unorderedEquals(['ספיישל סמאשבורגר 🌟', 'סמאשבורגר']),
        );
      });
    });

    group('the English reply on a menu rebuilt from its own ids', () {
      final reply = _Recording('smoke_20_dish_english.json');
      final menu = _englishSmokeMenu(reply);

      test('parse given the recorded reply keeps all twenty verdicts', () {
        // Act
        final analysis = _replay(reply, menu);

        // Assert
        _expectFaithfulReplay(analysis, menu, reply);
        expect(analysis.unclassified, isEmpty);
        expect(
          analysis.dishes.where((d) => d.verdict == DishVerdict.orderAsIs),
          hasLength(5),
        );
        expect(
          analysis.dishes.where((d) => d.verdict == DishVerdict.modifiable),
          hasLength(5),
        );
        expect(
          analysis.dishes.where((d) => d.verdict == DishVerdict.nonKeto),
          hasLength(10),
        );
      });

      test('parse given the recorded reply keeps why and modification '
          'in English', () {
        // Act
        final analysis = _replay(reply, menu);

        // Assert
        for (final dish in analysis.dishes) {
          expect(dish.why, isNot(matches(_hebrew)), reason: dish.name);
          expect(dish.why, matches(_latin), reason: dish.name);
        }
      });

      test('parse given the same reply against a menu missing one dish '
          'does not invent a verdict for it', () {
        // Arrange
        final smaller = _menuOf(menu.venueRef, menu.allDishes.skip(1).toList());

        // Act
        final analysis = _replay(reply, smaller);

        // Assert
        expect(analysis.dishes, hasLength(19));
        expect(analysis.unclassified, ['Ribeye steak 300g']);
      });
    });
  });
}
