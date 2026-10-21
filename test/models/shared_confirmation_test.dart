// What other people were told by the staff, as the backend counts it
// (Banto, ALG-14, issue #409): `SharedConfirmations.tryFrom` reads the
// venue-menu route's `confirmations` list tolerantly and matches a dish by
// the fingerprint the device uploads under.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/dish_confirmation.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/shared_confirmation.dart';

/// One wire entry about [dishId], as `GET /v1/venue-menus` writes it.
Map<String, Object?> _entry(
  String dishId, {
  Object? restrictionId = 'sesame',
  Object? present = 0,
  Object? absent = 3,
  Object? first = '2026-10-01',
  Object? last = '2026-10-12',
}) => <String, Object?>{
  'dishFingerprint': dishFingerprint(dishId),
  'restrictionId': restrictionId,
  'present': present,
  'absent': absent,
  'first': first,
  'last': last,
};

void main() {
  group('SharedConfirmations.tryFrom', () {
    test('reads the wire list and matches a dish by its fingerprint', () {
      // Act
      final shared = SharedConfirmations.tryFrom(<Object?>[
        _entry('d1'),
        _entry('d2', restrictionId: 'peanuts', present: 4, absent: 0),
      ]);

      // Assert
      final d1 = shared!.forDish('d1').single;
      expect(d1.restrictionId, RestrictionId.sesame);
      expect(d1.absent, 3);
      expect(d1.present, 0);
      expect(d1.first, DateTime(2026, 10));
      expect(d1.last, DateTime(2026, 10, 12));
      expect(shared.forDish('d2').single.present, 4);
      expect(shared.forDish('d3'), isEmpty);
    });

    test('absent, not a list or nothing readable is none', () {
      for (final raw in <Object?>[
        null,
        'confirmations',
        <String, Object?>{},
        <Object?>[],
        <Object?>['entry'],
      ]) {
        // Act & Assert
        expect(SharedConfirmations.tryFrom(raw), isNull, reason: '$raw');
      }
    });

    test('an unreadable entry is dropped, the rest kept', () {
      // Act
      final shared = SharedConfirmations.tryFrom(<Object?>[
        _entry('a', restrictionId: 'unknownRestriction'),
        _entry('b', restrictionId: 'custom'),
        _entry('c', last: '2026-02-31'),
        _entry('d', first: null),
        <String, Object?>{
          ..._entry('e'),
          'dishFingerprint': 'not a token, prose',
        },
        _entry('kept'),
      ]);

      // Assert: the user's own words are never a shared fact.
      expect(shared!.counts, hasLength(1));
      expect(shared.forDish('kept'), hasLength(1));
    });

    test('a count that is not a non-negative integer reads as 0', () {
      // Act
      final count = SharedConfirmations.tryFrom(<Object?>[
        _entry('d1', present: -2, absent: '7'),
      ])!.counts.single;

      // Assert
      expect(count.present, 0);
      expect(count.absent, 0);
    });

    test('round-trips through toJson, for the menu cache', () {
      // Arrange
      final shared = SharedConfirmations.tryFrom(<Object?>[
        _entry('d1'),
        _entry('d2', restrictionId: 'milk', present: 5),
      ])!;

      // Act
      final read = SharedConfirmations.tryFrom(shared.toJson());

      // Assert
      expect(read, shared);
      expect(read.hashCode, shared.hashCode);
      expect(read.toString(), 'SharedConfirmations(2)');
      expect(
        read!.counts.first.toString(),
        contains(RestrictionId.sesame.name),
      );
    });
  });
}
