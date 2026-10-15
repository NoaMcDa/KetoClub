// DishConfirmation and ChangeConfirmation (Banto, ALG-14, issue #356):
// round-trips and the tolerant reader.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dish_confirmation.dart';
import 'package:ketoclub/models/restriction.dart';

void main() {
  final day = DateTime(2026, 5, 12);

  group('DishConfirmation', () {
    test('round-trips every field', () {
      // Arrange
      final confirmation = DishConfirmation(
        dishId: 'salad',
        restrictionId: RestrictionId.sesame,
        polarity: ConfirmationPolarity.absent,
        day: day,
        source: ConcernSource.name,
        matchedText: 'טחינה',
      );

      // Act
      final json = confirmation.toJson();
      final read = DishConfirmation.tryFromJson(json);

      // Assert
      expect(json['day'], '2026-05-12');
      expect(read, confirmation);
      expect(read.hashCode, confirmation.hashCode);
      expect(confirmation.toString(), contains('sesame'));
    });

    test('leaves out an absent source and matched text', () {
      // Arrange
      final confirmation = DishConfirmation(
        dishId: 'd',
        restrictionId: RestrictionId.peanuts,
        polarity: ConfirmationPolarity.present,
        day: day,
      );

      // Act
      final json = confirmation.toJson();

      // Assert
      expect(json.containsKey('source'), isFalse);
      expect(json.containsKey('matchedText'), isFalse);
      expect(DishConfirmation.tryFromJson(json), confirmation);
    });

    final bad = <String, Object?>{
      'not a map': 'x',
      'no dish': <String, Object?>{
        'restrictionId': 'sesame',
        'polarity': 'present',
        'day': '2026-05-12',
      },
      'unknown restriction': <String, Object?>{
        'dishId': 'd',
        'restrictionId': 'saffron',
        'polarity': 'present',
        'day': '2026-05-12',
      },
      'unknown polarity': <String, Object?>{
        'dishId': 'd',
        'restrictionId': 'sesame',
        'polarity': 'maybe',
        'day': '2026-05-12',
      },
      'bad day': <String, Object?>{
        'dishId': 'd',
        'restrictionId': 'sesame',
        'polarity': 'present',
        'day': '2026-02-31',
      },
      'timestamp, not a day': <String, Object?>{
        'dishId': 'd',
        'restrictionId': 'sesame',
        'polarity': 'present',
        'day': '2026-05-12T10:00:00Z',
      },
    };
    for (final MapEntry(key: name, value: json) in bad.entries) {
      test('reads $name as null', () {
        // Act & Assert
        expect(DishConfirmation.tryFromJson(json), isNull);
      });
    }

    test('reads an unknown source as none', () {
      // Act
      final read = DishConfirmation.tryFromJson(<String, Object?>{
        'dishId': 'd',
        'restrictionId': 'sesame',
        'polarity': 'present',
        'day': '2026-05-12',
        'source': 'oracle',
      });

      // Assert
      expect(read?.source, isNull);
    });
  });

  group('ChangeConfirmation', () {
    test('round-trips', () {
      // Arrange
      final change = ChangeConfirmation(dishId: 'd', honoured: false, day: day);

      // Act
      final read = ChangeConfirmation.tryFromJson(change.toJson());

      // Assert
      expect(read, change);
      expect(read.hashCode, change.hashCode);
      expect(change.toString(), contains('2026-05-12'));
    });

    test('reads a malformed record as null', () {
      // Act & Assert
      expect(ChangeConfirmation.tryFromJson(null), isNull);
      expect(
        ChangeConfirmation.tryFromJson(<String, Object?>{
          'dishId': 'd',
          'honoured': 'yes',
          'day': '2026-05-12',
        }),
        isNull,
      );
      expect(
        ChangeConfirmation.tryFromJson(<String, Object?>{
          'dishId': 'd',
          'honoured': true,
        }),
        isNull,
      );
    });
  });

  group('the shared-store shape (PR #392)', () {
    test('dishFingerprint is FNV-1a hex in the backend key shape', () {
      // Arrange
      final shape = RegExp(r'^[A-Za-z0-9._:-]{1,64}$');

      // Act & Assert: the published FNV-1a 32-bit test vectors.
      expect(dishFingerprint(''), '811c9dc5');
      expect(dishFingerprint('a'), 'e40c292c');
      for (final id in <String>['salad', '12345', 'סלט/חצילים', 'x' * 500]) {
        expect(dishFingerprint(id), matches(shape));
      }
      final confirmation = DishConfirmation(
        dishId: 'a',
        restrictionId: RestrictionId.sesame,
        polarity: ConfirmationPolarity.present,
        day: day,
      );
      expect(confirmation.dishKey, 'e40c292c');
    });

    test("the user's own words are local-only", () {
      // Arrange
      DishConfirmation about(RestrictionId id) => DishConfirmation(
        dishId: 'd',
        restrictionId: id,
        polarity: ConfirmationPolarity.absent,
        day: day,
      );

      // Act & Assert
      expect(about(RestrictionId.custom).isShareable, isFalse);
      expect(about(RestrictionId.sesame).isShareable, isTrue);
    });
  });

  test('confirmationDay keeps the calendar day and drops the time', () {
    // Act & Assert
    expect(confirmationDay(DateTime(2026, 5, 12, 23, 59)), day);
    expect(
      ConfirmationPolarity.tryParse('absent'),
      ConfirmationPolarity.absent,
    );
    expect(ConfirmationPolarity.tryParse(3), isNull);
  });
}
