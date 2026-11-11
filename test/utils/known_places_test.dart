import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/place.dart';
import 'package:ketoclub/utils/known_places.dart';

/// The ids of [places], in order.
List<String> _ids(List<KnownPlace> places) => [for (final p in places) p.id];

/// Whether [text] holds a Hebrew letter.
bool _hasHebrew(String text) => RegExp('[א-ת]').hasMatch(text);

void main() {
  group('knownPlaces (issue #443)', () {
    test('is not empty and starts with the largest cities', () {
      // Assert
      expect(_ids(knownPlaces).take(3), ['tel-aviv', 'jerusalem', 'haifa']);
    });

    test('every id is unique, lower-case ASCII with hyphens', () {
      // Arrange
      final shape = RegExp(r'^[a-z]+(-[a-z]+)*$');

      // Assert: an id is stored on the device, so it must be unambiguous.
      expect(_ids(knownPlaces).toSet(), hasLength(knownPlaces.length));
      for (final place in knownPlaces) {
        expect(shape.hasMatch(place.id), isTrue, reason: place.id);
      }
    });

    test('every place has an English name with no Hebrew in it and a '
        'Hebrew name with Hebrew in it', () {
      // Assert
      for (final place in knownPlaces) {
        expect(place.nameEn.trim(), isNotEmpty, reason: place.id);
        expect(_hasHebrew(place.nameEn), isFalse, reason: place.id);
        expect(_hasHebrew(place.nameHe), isTrue, reason: place.id);
      }
    });

    test('no two places share a name in either language', () {
      // Assert
      expect({
        for (final p in knownPlaces) p.nameEn,
      }, hasLength(knownPlaces.length));
      expect({
        for (final p in knownPlaces) p.nameHe,
      }, hasLength(knownPlaces.length));
    });

    test('every place lies inside Israel', () {
      // Assert: Eilat in the south to Metula in the north, the coast to
      // the Jordan. A swapped latitude and longitude fails this.
      for (final place in knownPlaces) {
        expect(place.latitude, inInclusiveRange(29.4, 33.4), reason: place.id);
        expect(place.longitude, inInclusiveRange(34.2, 35.9), reason: place.id);
      }
    });
  });

  group('knownPlaceById (issue #443)', () {
    test('finds a place by its id', () {
      // Act
      final place = knownPlaceById('jerusalem');

      // Assert
      expect(place?.nameEn, 'Jerusalem');
    });

    test('is null for an id the list does not hold', () {
      // Assert
      expect(knownPlaceById('atlantis'), isNull);
      expect(knownPlaceById(''), isNull);
    });
  });

  group('searchKnownPlaces (issue #443)', () {
    test('a blank query lists every place, in list order', () {
      // Assert
      expect(searchKnownPlaces(''), knownPlaces);
      expect(searchKnownPlaces('   '), knownPlaces);
    });

    test('matches part of an English name, whatever its case', () {
      // Act
      final found = _ids(searchKnownPlaces('HAI'));

      // Assert
      expect(found, ['haifa']);
    });

    test('matches part of a Hebrew name', () {
      // Act
      final found = _ids(searchKnownPlaces('ירוש'));

      // Assert
      expect(found, ['jerusalem']);
    });

    test('ignores spaces and hyphens, so "tel aviv" finds Tel Aviv-Yafo', () {
      // Assert
      expect(_ids(searchKnownPlaces('tel aviv')), ['tel-aviv']);
      expect(_ids(searchKnownPlaces('תל אביב')), ['tel-aviv']);
      expect(_ids(searchKnownPlaces('  Bat-Yam ')), ['bat-yam']);
    });

    test('ignores apostrophes, so "raanana" finds Ra\'anana', () {
      // Assert
      expect(_ids(searchKnownPlaces('raanana')), ['raanana']);
      expect(_ids(searchKnownPlaces("modi'in")), ['modiin']);
      expect(_ids(searchKnownPlaces('modi’in')), ['modiin']);
    });

    test('reads a doubled yod as one, so both spellings of "Kiryat" in '
        'Hebrew match', () {
      // Act
      final single = _ids(searchKnownPlaces('קרית גת'));
      final doubled = _ids(searchKnownPlaces('קריית גת'));

      // Assert
      expect(single, ['kiryat-gat']);
      expect(doubled, ['kiryat-gat']);
    });

    test('a shared word finds every place that has it, in list order', () {
      // Act
      final found = _ids(searchKnownPlaces('kiryat'));

      // Assert
      expect(found, ['kiryat-gat', 'kiryat-ono', 'kiryat-shmona']);
    });

    test('finds nothing for a name the list does not hold', () {
      // Assert
      expect(searchKnownPlaces('atlantis'), isEmpty);
    });
  });
}
