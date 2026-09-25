// The schema-drift check issue #22 asks for: a test that fails loudly the
// moment Wolt's real consumer-assortment payload (issue #168) stops
// carrying a field `WoltMenuMapper` reads, rather than the mapper quietly
// starting to treat every fixture as `platformChanged` (or, worse,
// silently dropping a field no test happens to exercise).
//
// This does not replace `wolt_menu_mapper_test.dart`, which asserts
// mapping *behaviour*. This file asserts *shape* only — presence and
// type, nothing about values — against every checked-in
// `wolt_*_menu.json` fixture except the deliberately-wrong-shaped
// `wolt_malformed_menu.json`, so a newly recorded fixture (see
// `tool/record_wolt_fixture.sh`) is covered automatically with no edit
// here. It also pins the counts of the one real recording, so a
// re-record that quietly loses half the menu is a diff someone reads.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The fixtures directory every Wolt fixture lives in.
const String _fixturesDir = 'test/fixtures';

/// `wolt_*_menu.json` fixtures that are real (or real-shaped)
/// consumer-assortment payloads, excluding `wolt_malformed_menu.json`,
/// which is deliberately shaped wrong to exercise the `platformChanged`
/// path and would fail every assertion below by design.
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
    'wrong type. Wolt changed its consumer-assortment payload shape — '
    'update WoltMenuMapper (and, if the new shape is intentional, this '
    'test and wolt_menu_mapper_test.dart) to match before shipping.';

/// Asserts [value] is a `T`, with the drift message for [field].
void _expectType<T>(Object? value, String fixtureName, String field) =>
    expect(value, isA<T>(), reason: _driftMessage(fixtureName, field));

/// Asserts that [json] has every field `WoltMenuMapper` and its helpers
/// read, with the type each read site requires. See
/// `wolt_menu_mapper.dart`'s class doc comment for the authoritative
/// list this mirrors. `subcategories` is asserted to be a list because
/// every recorded category carries one, even though the mapper tolerates
/// its absence.
void _assertWoltMenuShape(Map<String, Object?> json, String fixtureName) {
  final rawCategories = json['categories'];
  _expectType<List<Object?>>(rawCategories, fixtureName, 'categories');
  for (final rawCategory in rawCategories! as List<Object?>) {
    _expectType<Map<String, Object?>>(rawCategory, fixtureName, 'categories[]');
    final category = rawCategory! as Map<String, Object?>;
    _expectType<String>(category['id'], fixtureName, 'categories[].id');
    _expectType<String>(category['name'], fixtureName, 'categories[].name');
    final itemIds = category['item_ids'];
    _expectType<List<Object?>>(itemIds, fixtureName, 'categories[].item_ids');
    for (final itemId in itemIds! as List<Object?>) {
      _expectType<String>(itemId, fixtureName, 'categories[].item_ids[]');
    }
    _expectType<List<Object?>>(
      category['subcategories'],
      fixtureName,
      'categories[].subcategories',
    );
  }

  final rawItems = json['items'];
  _expectType<List<Object?>>(rawItems, fixtureName, 'items');
  for (final rawItem in rawItems! as List<Object?>) {
    _expectType<Map<String, Object?>>(rawItem, fixtureName, 'items[]');
    final item = rawItem! as Map<String, Object?>;
    _expectType<String>(item['id'], fixtureName, 'items[].id');
    _expectType<String>(item['name'], fixtureName, 'items[].name');
    // Minor units: an integer, never a decimal major-unit price.
    _expectType<int>(item['price'], fixtureName, 'items[].price (agorot)');
    final description = item['description'];
    if (description != null) {
      _expectType<String>(description, fixtureName, 'items[].description');
    }
    final images = item['images'];
    _expectType<List<Object?>>(images, fixtureName, 'items[].images');
    for (final image in images! as List<Object?>) {
      _expectType<Map<String, Object?>>(image, fixtureName, 'items[].images[]');
      _expectType<String>(
        (image! as Map<String, Object?>)['url'],
        fixtureName,
        'items[].images[].url',
      );
    }
    final itemOptions = item['options'];
    _expectType<List<Object?>>(itemOptions, fixtureName, 'items[].options');
    for (final itemOption in itemOptions! as List<Object?>) {
      _expectType<Map<String, Object?>>(
        itemOption,
        fixtureName,
        'items[].options[]',
      );
      final option = itemOption! as Map<String, Object?>;
      _expectType<String>(
        option['option_id'],
        fixtureName,
        'items[].options[].option_id',
      );
      _expectType<String>(
        option['name'],
        fixtureName,
        'items[].options[].name',
      );
    }
  }

  final rawOptions = json['options'];
  _expectType<List<Object?>>(rawOptions, fixtureName, 'options');
  for (final rawOption in rawOptions! as List<Object?>) {
    _expectType<Map<String, Object?>>(rawOption, fixtureName, 'options[]');
    final option = rawOption! as Map<String, Object?>;
    _expectType<String>(option['id'], fixtureName, 'options[].id');
    _expectType<String>(option['name'], fixtureName, 'options[].name');
    final rawValues = option['values'];
    _expectType<List<Object?>>(rawValues, fixtureName, 'options[].values');
    for (final rawValue in rawValues! as List<Object?>) {
      _expectType<Map<String, Object?>>(
        rawValue,
        fixtureName,
        'options[].values[]',
      );
      _expectType<String>(
        (rawValue! as Map<String, Object?>)['name'],
        fixtureName,
        'options[].values[].name',
      );
    }
  }
}

/// Decodes [file] as a JSON object.
Map<String, Object?> _decode(File file) =>
    jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

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

  test('the hamosad recording keeps its recorded size and joins', () {
    // Arrange
    final json = _decode(File('$_fixturesDir/wolt_hamosad_menu.json'));

    // Act
    final categories = json['categories']! as List<Object?>;
    final items = json['items']! as List<Object?>;
    final options = json['options']! as List<Object?>;
    final itemIds = <Object?>{
      for (final item in items) (item! as Map<String, Object?>)['id'],
    };
    final categoryItemIds = <Object?>[
      for (final category in categories)
        ...((category! as Map<String, Object?>)['item_ids']! as List<Object?>),
    ];

    // Assert: 12 categories, 56 items, 48 option groups, and every item a
    // category lists is present in items[] (issue #22's "category count,
    // dish count" pin).
    expect(categories, hasLength(12));
    expect(items, hasLength(56));
    expect(options, hasLength(48));
    expect(json.containsKey('currency'), isFalse);
    expect(itemIds.containsAll(categoryItemIds), isTrue);
  });
}
