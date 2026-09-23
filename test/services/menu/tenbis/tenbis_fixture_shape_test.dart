// The schema-drift check issue #22 asks for and issue #44 repeats for
// 10bis: a test that fails loudly the moment a real 10bis
// `Restaurants/{id}/Menu` payload stops carrying a field
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
/// `Restaurants/{id}/Menu` payloads, excluding
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
  final rawCategories = json['categoriesList'];
  expect(
    rawCategories,
    isA<List<Object?>>(),
    reason: _driftMessage(fixtureName, 'categoriesList'),
  );
  for (final rawCategory in rawCategories! as List<Object?>) {
    expect(
      rawCategory,
      isA<Map<String, Object?>>(),
      reason: _driftMessage(fixtureName, 'categoriesList[]'),
    );
    final category = rawCategory! as Map<String, Object?>;
    expect(
      category['categoryName'],
      isA<String>(),
      reason: _driftMessage(fixtureName, 'categoriesList[].categoryName'),
    );

    final rawDishes = category['dishList'];
    expect(
      rawDishes,
      isA<List<Object?>>(),
      reason: _driftMessage(fixtureName, 'categoriesList[].dishList'),
    );
    for (final rawDish in rawDishes! as List<Object?>) {
      expect(
        rawDish,
        isA<Map<String, Object?>>(),
        reason: _driftMessage(fixtureName, 'dishList[]'),
      );
      final dish = rawDish! as Map<String, Object?>;
      final rawId = dish['dishId'];
      expect(
        rawId is String || rawId is num,
        isTrue,
        reason: _driftMessage(fixtureName, 'dishList[].dishId'),
      );
      expect(
        dish['dishName'],
        isA<String>(),
        reason: _driftMessage(fixtureName, 'dishList[].dishName'),
      );
      expect(
        dish['price'],
        isA<num>(),
        reason: _driftMessage(fixtureName, 'dishList[].price'),
      );
      final description = dish['dishDescription'];
      if (description != null) {
        expect(
          description,
          isA<String>(),
          reason: _driftMessage(fixtureName, 'dishList[].dishDescription'),
        );
      }

      final rawOptions = dish['dishOptionsList'];
      if (rawOptions != null) {
        expect(
          rawOptions,
          isA<List<Object?>>(),
          reason: _driftMessage(fixtureName, 'dishList[].dishOptionsList'),
        );
        for (final rawOption in rawOptions as List<Object?>) {
          expect(
            rawOption,
            isA<Map<String, Object?>>(),
            reason: _driftMessage(fixtureName, 'dishOptionsList[]'),
          );
          final option = rawOption! as Map<String, Object?>;
          expect(
            option['name'],
            isA<String>(),
            reason: _driftMessage(fixtureName, 'dishOptionsList[].name'),
          );
          final rawValues = option['values'];
          expect(
            rawValues,
            isA<List<Object?>>(),
            reason: _driftMessage(fixtureName, 'dishOptionsList[].values'),
          );
          for (final rawValue in rawValues! as List<Object?>) {
            expect(
              rawValue,
              isA<Map<String, Object?>>(),
              reason: _driftMessage(fixtureName, 'dishOptionsList[].values[]'),
            );
            final value = rawValue! as Map<String, Object?>;
            expect(
              value['name'],
              isA<String>(),
              reason: _driftMessage(
                fixtureName,
                'dishOptionsList[].values[].name',
              ),
            );
          }
        }
      }

      final image = dish['dishImageUrl'];
      if (image != null) {
        expect(
          image,
          isA<String>(),
          reason: _driftMessage(fixtureName, 'dishList[].dishImageUrl'),
        );
      }
    }
  }

  final restaurantName = json['restaurantName'];
  if (restaurantName != null) {
    expect(
      restaurantName,
      isA<String>(),
      reason: _driftMessage(fixtureName, 'restaurantName'),
    );
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
