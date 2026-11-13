// The schema-drift check issue #22 asks for and issue #44 repeats for
// 10bis: a test that fails loudly the moment a real 10bis
// `NextApi/GetRestaurantMenu` payload stops carrying a field
// `TenBisMenuMapper` reads, rather than the mapper quietly starting to
// treat every fixture as `platformChanged` (or, worse, silently
// dropping a field no test happens to exercise).
//
// This does not replace `tenbis_menu_mapper_test.dart`, which asserts
// mapping *behaviour* against one fixture. This file asserts *shape*
// only — presence and type, nothing about values — against every
// checked-in `tenbis_*_menu.json` fixture except the
// deliberately-wrong-shaped `tenbis_malformed_menu.json`, so a newly
// recorded fixture (issue #44) is covered automatically with no edit
// here.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The fixtures directory every 10bis fixture lives in.
const String _fixturesDir = 'test/fixtures';

/// `tenbis_*_menu.json` fixtures that are real (or real-shaped)
/// `NextApi/GetRestaurantMenu` payloads, excluding
/// `tenbis_malformed_menu.json`, which is deliberately shaped wrong to
/// exercise the `platformChanged` path and would fail every assertion
/// below by design.
List<File> _tenBisMenuFixtures() {
  final dir = Directory(_fixturesDir);
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .where((file) {
            final name = file.uri.pathSegments.last;
            return name.startsWith('tenbis_') &&
                name.endsWith('_menu.json') &&
                name != 'tenbis_malformed_menu.json';
          })
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// The message a failed shape assertion carries: names [fixtureName] and
/// [field] and tells the reader plainly what happened, per issue #22's
/// "fails loudly" requirement (repeated for 10bis by issue #44), so a
/// schema drift is never mistaken for a flaky test.
String _driftMessage(String fixtureName, String field) =>
    '$fixtureName: TenBisMenuMapper reads "$field" but it is missing or '
    'the wrong type. 10bis changed its Menu payload shape — update '
    'TenBisMenuMapper (and, if the new shape is intentional, this test '
    'and tenbis_menu_mapper_test.dart) to match before shipping.';

/// Asserts that [json] has every top-level and nested field
/// `TenBisMenuMapper._tryBuildMenu` and its helpers read, with the type
/// each read site requires. See `tenbis_menu_mapper.dart`'s class doc
/// comment for the authoritative list this mirrors.
void _assertTenBisMenuShape(Map<String, Object?> json, String fixtureName) {
  void expectField(Object? value, Matcher matcher, String field) =>
      expect(value, matcher, reason: _driftMessage(fixtureName, field));

  expectField(json['Success'], isTrue, 'Success');
  final data = json['Data'];
  expectField(data, isA<Map<String, Object?>>(), 'Data');
  final rawCategories = (data! as Map<String, Object?>)['categoriesList'];
  expectField(rawCategories, isA<List<Object?>>(), 'Data.categoriesList');
  for (final rawCategory in rawCategories! as List<Object?>) {
    expectField(rawCategory, isA<Map<String, Object?>>(), 'categoriesList[]');
    final category = rawCategory! as Map<String, Object?>;
    expectField(category['categoryID'], isA<num>(), 'categoryID');
    expectField(category['categoryName'], isA<String>(), 'categoryName');
    final rawDishes = category['dishList'];
    expectField(rawDishes, isA<List<Object?>>(), 'dishList');
    for (final rawDish in rawDishes! as List<Object?>) {
      expectField(rawDish, isA<Map<String, Object?>>(), 'dishList[]');
      final dish = rawDish! as Map<String, Object?>;
      expectField(dish['dishId'], isA<num>(), 'dishList[].dishId');
      expectField(dish['dishName'], isA<String>(), 'dishList[].dishName');
      expectField(dish['dishPrice'], isA<num>(), 'dishList[].dishPrice');
      expectField(
        dish['dishDescription'],
        isA<String>(),
        'dishList[].dishDescription',
      );
      expectField(
        dish['dishImageUrl'],
        isA<String>(),
        'dishList[].dishImageUrl',
      );
      final rawChoices = dish['choices'];
      expectField(rawChoices, isA<List<Object?>>(), 'dishList[].choices');
      for (final rawChoice in rawChoices! as List<Object?>) {
        expectField(rawChoice, isA<Map<String, Object?>>(), 'choices[]');
        final choice = rawChoice! as Map<String, Object?>;
        expectField(
          choice['textBeforeChoosing'],
          isA<String>(),
          'choices[].textBeforeChoosing',
        );
        final rawSubs = choice['subs'];
        expectField(rawSubs, isA<List<Object?>>(), 'choices[].subs');
        for (final rawSub in rawSubs! as List<Object?>) {
          expectField(rawSub, isA<Map<String, Object?>>(), 'subs[]');
          expectField(
            (rawSub! as Map<String, Object?>)['name'],
            isA<String>(),
            'subs[].name',
          );
        }
      }
    }
  }
}

void main() {
  final fixtures = _tenBisMenuFixtures();

  test('at least one non-malformed 10bis fixture is checked in', () {
    // Guards the guard: if this list is ever empty (a rename, a moved
    // directory), every test below silently vanishes instead of failing.
    expect(fixtures, isNotEmpty);
  });

  for (final file in fixtures) {
    final fixtureName = file.uri.pathSegments.last;

    test('$fixtureName has every field TenBisMenuMapper reads, correctly '
        'typed', () {
      // Arrange
      final decoded = jsonDecode(file.readAsStringSync());

      // Assert (the "Act" is the decode above; there is nothing to
      // compute beyond it — this test is purely a shape assertion).
      expect(
        decoded,
        isA<Map<String, Object?>>(),
        reason: '$fixtureName: top level is not a JSON object at all.',
      );
      _assertTenBisMenuShape(decoded! as Map<String, Object?>, fixtureName);
    });
  }
}
