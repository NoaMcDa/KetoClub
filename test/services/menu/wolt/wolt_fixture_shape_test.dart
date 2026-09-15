// The schema-drift check issue #22 asks for: a test that fails loudly the
// moment Wolt's real `menu/data` payload stops carrying a field
// `WoltMenuMapper` reads, rather than the mapper quietly starting to treat
// every fixture as `platformChanged` (or, worse, silently dropping a field
// no test happens to exercise).
//
// This does not replace `wolt_menu_mapper_test.dart`, which asserts
// mapping *behaviour* against one fixture. This file asserts *shape* only
// — presence and type, nothing about values — against every checked-in
// `wolt_*_menu.json` fixture except the deliberately-wrong-shaped
// `wolt_malformed_menu.json`, so a newly recorded fixture (see
// `tool/record_wolt_fixture.sh`) is covered automatically with no edit
// here.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The fixtures directory every Wolt fixture lives in.
const String _fixturesDir = 'test/fixtures';

/// `wolt_*_menu.json` fixtures that are real (or real-shaped) `menu/data`
/// payloads, excluding `wolt_malformed_menu.json`, which is deliberately
/// shaped wrong to exercise the `platformChanged` path and would fail
/// every assertion below by design.
List<File> _woltMenuFixtures() {
  final dir = Directory(_fixturesDir);
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .where((file) {
            final name = file.uri.pathSegments.last;
            return name.startsWith('wolt_') &&
                name.endsWith('_menu.json') &&
                name != 'wolt_malformed_menu.json';
          })
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// The message a failed shape assertion carries: names [fixtureName] and
/// [field] and tells the reader plainly what happened, per issue #22's
/// "fails loudly" requirement, so a schema drift is never mistaken for a
/// flaky test.
String _driftMessage(String fixtureName, String field) =>
    '$fixtureName: WoltMenuMapper reads "$field" but it is missing or the '
    'wrong type. Wolt changed its menu/data payload shape — update '
    'WoltMenuMapper (and, if the new shape is intentional, this test and '
    'wolt_menu_mapper_test.dart) to match before shipping.';

/// Asserts that [json] has every top-level and nested field
/// `WoltMenuMapper._tryBuildMenu` and its helpers read, with the type
/// each read site requires. See `wolt_menu_mapper.dart`'s class doc
/// comment for the authoritative list this mirrors.
void _assertWoltMenuShape(Map<String, Object?> json, String fixtureName) {
  expect(
    json['currency'],
    isA<String>(),
    reason: _driftMessage(fixtureName, 'currency'),
  );

  final rawCategories = json['categories'];
  expect(
    rawCategories,
    isA<List<Object?>>(),
    reason: _driftMessage(fixtureName, 'categories'),
  );
  for (final rawCategory in rawCategories! as List<Object?>) {
    expect(
      rawCategory,
      isA<Map<String, Object?>>(),
      reason: _driftMessage(fixtureName, 'categories[]'),
    );
    final category = rawCategory! as Map<String, Object?>;
    expect(
      category['id'],
      isA<String>(),
      reason: _driftMessage(fixtureName, 'categories[].id'),
    );
    expect(
      category['name'],
      isA<String>(),
      reason: _driftMessage(fixtureName, 'categories[].name'),
    );
    expect(
      category['item_ids'],
      isA<List<Object?>>(),
      reason: _driftMessage(fixtureName, 'categories[].item_ids'),
    );
  }

  final rawItems = json['items'];
  expect(
    rawItems,
    isA<List<Object?>>(),
    reason: _driftMessage(fixtureName, 'items'),
  );
  for (final rawItem in rawItems! as List<Object?>) {
    expect(
      rawItem,
      isA<Map<String, Object?>>(),
      reason: _driftMessage(fixtureName, 'items[]'),
    );
    final item = rawItem! as Map<String, Object?>;
    expect(
      item['id'],
      isA<String>(),
      reason: _driftMessage(fixtureName, 'items[].id'),
    );
    expect(
      item['name'],
      isA<String>(),
      reason: _driftMessage(fixtureName, 'items[].name'),
    );
    expect(
      item['price'],
      isA<num>(),
      reason: _driftMessage(fixtureName, 'items[].price'),
    );
    final description = item['description'];
    if (description != null) {
      expect(
        description,
        isA<String>(),
        reason: _driftMessage(fixtureName, 'items[].description'),
      );
    }
    final rawOptionIds = item['options'];
    if (rawOptionIds != null) {
      expect(
        rawOptionIds,
        isA<List<Object?>>(),
        reason: _driftMessage(fixtureName, 'items[].options'),
      );
      for (final rawOptionId in rawOptionIds as List<Object?>) {
        expect(
          rawOptionId,
          isA<String>(),
          reason: _driftMessage(fixtureName, 'items[].options[]'),
        );
      }
    }
  }

  final rawOptions = json['options'];
  if (rawOptions != null) {
    expect(
      rawOptions,
      isA<List<Object?>>(),
      reason: _driftMessage(fixtureName, 'options'),
    );
    for (final rawOption in rawOptions as List<Object?>) {
      expect(
        rawOption,
        isA<Map<String, Object?>>(),
        reason: _driftMessage(fixtureName, 'options[]'),
      );
      final option = rawOption! as Map<String, Object?>;
      expect(
        option['id'],
        isA<String>(),
        reason: _driftMessage(fixtureName, 'options[].id'),
      );
      expect(
        option['name'],
        isA<String>(),
        reason: _driftMessage(fixtureName, 'options[].name'),
      );
      final rawValues = option['values'];
      expect(
        rawValues,
        isA<List<Object?>>(),
        reason: _driftMessage(fixtureName, 'options[].values'),
      );
      for (final rawValue in rawValues! as List<Object?>) {
        expect(
          rawValue,
          isA<Map<String, Object?>>(),
          reason: _driftMessage(fixtureName, 'options[].values[]'),
        );
        final value = rawValue! as Map<String, Object?>;
        expect(
          value['name'],
          isA<String>(),
          reason: _driftMessage(fixtureName, 'options[].values[].name'),
        );
      }
    }
  }
}

void main() {
  final fixtures = _woltMenuFixtures();

  test('at least one non-malformed Wolt fixture is checked in', () {
    // Guards the guard: if this list is ever empty (a rename, a moved
    // directory), every test below silently vanishes instead of failing.
    expect(fixtures, isNotEmpty);
  });

  for (final file in fixtures) {
    final fixtureName = file.uri.pathSegments.last;

    test(
      '$fixtureName has every field WoltMenuMapper reads, correctly typed',
      () {
        // Arrange
        final decoded = jsonDecode(file.readAsStringSync());

        // Assert (the "Act" is the decode above; there is nothing to
        // compute beyond it — this test is purely a shape assertion).
        expect(
          decoded,
          isA<Map<String, Object?>>(),
          reason: '$fixtureName: top level is not a JSON object at all.',
        );
        _assertWoltMenuShape(decoded! as Map<String, Object?>, fixtureName);
      },
    );
  }
}
