// The schema-drift check for Wolt's discovery pages, in the pattern of
// `wolt_fixture_shape_test.dart` for menus: a test that fails loudly the
// moment a checked-in `wolt_pages_*.json` fixture stops carrying a field
// `WoltVenueMapper` reads, rather than the mapper quietly turning every
// venue's field into null.
//
// This asserts *shape* only — presence and type, nothing about values.
// The mapper's *behaviour* is `wolt_venue_mapper_test.dart`'s job. Once
// the fixtures are re-recorded (`test/fixtures/README.md`, "Wolt
// discovery"), a new `wolt_pages_*.json` file is covered with no edit here.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The fixtures directory every Wolt fixture lives in.
const String _fixturesDir = 'test/fixtures';

/// Every `wolt_pages_*.json` discovery fixture, sorted by path.
List<File> _discoveryFixtures() =>
    Directory(_fixturesDir).listSync().whereType<File>().where((file) {
      final name = file.uri.pathSegments.last;
      return name.startsWith('wolt_pages_') && name.endsWith('.json');
    }).toList()..sort((a, b) => a.path.compareTo(b.path));

/// The message a failed shape assertion carries, naming [fixtureName] and
/// [field].
String _driftMessage(String fixtureName, String field) =>
    '$fixtureName: WoltVenueMapper reads "$field" but it is missing or the '
    'wrong type. Wolt changed its discovery page shape — update '
    'WoltVenueMapper (and, if the new shape is intentional, this test and '
    'wolt_venue_mapper_test.dart) to match before shipping.';

/// Expects [value], when present, to satisfy [matcher].
void _optional(Object? value, Matcher matcher, String reason) {
  if (value != null) expect(value, matcher, reason: reason);
}

/// Asserts one `venue` object has every field the mapper reads, typed as
/// the mapper requires. `slug` and `name` are required; the rest may be
/// absent, but never of the wrong type.
void _assertVenueShape(Map<String, Object?> venue, String fixtureName) {
  String reason(String field) => _driftMessage(fixtureName, 'venue.$field');

  expect(venue['slug'], isA<String>(), reason: reason('slug'));
  expect(venue['name'], isA<String>(), reason: reason('name'));
  _optional(venue['address'], isA<String>(), reason('address'));
  _optional(venue['short_description'], isA<String>(), reason('short'));
  _optional(venue['online'], isA<bool>(), reason('online'));
  _optional(venue['estimate'], isA<num>(), reason('estimate'));

  final location = venue['location'];
  if (location != null) {
    expect(location, isA<List<Object?>>(), reason: reason('location'));
    final pair = location as List<Object?>;
    expect(pair, hasLength(2), reason: reason('location'));
    expect(pair[0], isA<num>(), reason: reason('location[0] (longitude)'));
    expect(pair[1], isA<num>(), reason: reason('location[1] (latitude)'));
  }

  final tags = venue['tags'];
  if (tags != null) {
    expect(tags, isA<List<Object?>>(), reason: reason('tags'));
    for (final tag in tags as List<Object?>) {
      expect(tag, isA<String>(), reason: reason('tags[]'));
    }
  }

  final rating = venue['rating'];
  if (rating != null) {
    expect(rating, isA<Map<String, Object?>>(), reason: reason('rating'));
    _optional(
      (rating as Map<String, Object?>)['score'],
      isA<num>(),
      reason('rating.score'),
    );
  }

  final brandImage = venue['brand_image'];
  if (brandImage != null) {
    expect(
      brandImage,
      isA<Map<String, Object?>>(),
      reason: reason('brand_image'),
    );
    expect(
      (brandImage as Map<String, Object?>)['url'],
      isA<String>(),
      reason: reason('brand_image.url'),
    );
  }
}

/// Asserts [json] is a discovery page the mapper can walk.
void _assertPageShape(Map<String, Object?> json, String fixtureName) {
  final sections = json['sections'];
  expect(
    sections,
    isA<List<Object?>>(),
    reason: _driftMessage(fixtureName, 'sections'),
  );
  var venueCount = 0;
  for (final section in sections! as List<Object?>) {
    expect(
      section,
      isA<Map<String, Object?>>(),
      reason: _driftMessage(fixtureName, 'sections[]'),
    );
    final items = (section! as Map<String, Object?>)['items'];
    expect(
      items,
      isA<List<Object?>>(),
      reason: _driftMessage(fixtureName, 'sections[].items'),
    );
    for (final item in items! as List<Object?>) {
      expect(
        item,
        isA<Map<String, Object?>>(),
        reason: _driftMessage(fixtureName, 'sections[].items[]'),
      );
      final entry = item! as Map<String, Object?>;
      final image = entry['image'];
      if (image != null) {
        expect(
          image,
          isA<Map<String, Object?>>(),
          reason: _driftMessage(fixtureName, 'items[].image'),
        );
        expect(
          (image as Map<String, Object?>)['url'],
          isA<String>(),
          reason: _driftMessage(fixtureName, 'items[].image.url'),
        );
      }
      final venue = entry['venue'];
      if (venue == null) continue; // a promo tile or a dish result
      expect(
        venue,
        isA<Map<String, Object?>>(),
        reason: _driftMessage(fixtureName, 'items[].venue'),
      );
      _assertVenueShape(venue as Map<String, Object?>, fixtureName);
      venueCount++;
    }
  }
  expect(
    venueCount,
    greaterThan(0),
    reason: '$fixtureName: no item carries a venue at all.',
  );
}

void main() {
  final fixtures = _discoveryFixtures();

  test('both Wolt discovery fixtures are checked in', () {
    // Guards the guard: a rename would otherwise make every test below
    // silently vanish instead of failing.
    expect(
      fixtures.map((file) => file.uri.pathSegments.last),
      containsAll(<String>[
        'wolt_pages_restaurants.json',
        'wolt_pages_search.json',
      ]),
    );
  });

  for (final file in fixtures) {
    final fixtureName = file.uri.pathSegments.last;

    test('$fixtureName has every field WoltVenueMapper reads, correctly '
        'typed', () {
      // Arrange
      final decoded = jsonDecode(file.readAsStringSync());

      // Assert
      expect(
        decoded,
        isA<Map<String, Object?>>(),
        reason: '$fixtureName: top level is not a JSON object at all.',
      );
      _assertPageShape(decoded! as Map<String, Object?>, fixtureName);
    });
  }
}
