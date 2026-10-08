import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';

void main() {
  const ref = VenueRef(source: MenuSource.wolt, platformId: 'vitrina');

  VisitEntry full() => VisitEntry(
    ref: ref,
    name: 'Vitrina',
    city: 'Tel Aviv',
    firstOpenedAt: DateTime.utc(2026),
    lastOpenedAt: DateTime.utc(2026, 2),
    openCount: 3,
    dishCount: 20,
    score: 7.5,
    greenCount: 4,
    yellowCount: 6,
  );

  VisitEntry bare() => VisitEntry(
    ref: ref,
    firstOpenedAt: DateTime.utc(2026),
    lastOpenedAt: DateTime.utc(2026),
    openCount: 1,
  );

  /// The minimal valid JSON, with [extra] merged over it.
  Map<String, Object?> json([Map<String, Object?> extra = const {}]) =>
      <String, Object?>{
        'source': 'wolt',
        'platformId': 'vitrina',
        'firstOpenedAt': '2026-01-01T00:00:00.000Z',
        'lastOpenedAt': '2026-01-01T00:00:00.000Z',
        'openCount': 1,
        ...extra,
      };

  group('VisitEntry', () {
    test('toJson then tryFrom round-trips every field', () {
      expect(VisitEntry.tryFrom(full().toJson()), full());
    });

    test('toJson then tryFrom round-trips an entry with no optionals', () {
      expect(VisitEntry.tryFrom(bare().toJson()), bare());
    });

    test('toJson leaves a null field out', () {
      expect(bare().toJson().keys, isNot(contains('name')));
      expect(bare().toJson().keys, isNot(contains('score')));
    });

    test('tryFrom ignores an unknown field', () {
      expect(VisitEntry.tryFrom(json({'future': true})), bare());
    });

    test('tryFrom reads a missing openCount as 1', () {
      final raw = json()..remove('openCount');

      expect(VisitEntry.tryFrom(raw)!.openCount, 1);
    });

    test('tryFrom reads an integer score as a double', () {
      expect(VisitEntry.tryFrom(json({'score': 7}))!.score, 7.0);
    });

    test('tryFrom rejects a bad shape', () {
      final cases = <Map<String, Object?>>[
        json()..remove('source'),
        json({'source': 'nowhere'}),
        json({'platformId': ''}),
        json({'platformId': 3}),
        json()..remove('firstOpenedAt'),
        json({'lastOpenedAt': 'yesterday'}),
        json({'openCount': '2'}),
        json({'name': 5}),
        json({'city': false}),
        json({'dishCount': 1.5}),
        json({'score': 'high'}),
        json({'greenCount': '1'}),
        json({'yellowCount': <int>[]}),
      ];
      for (final raw in cases) {
        expect(VisitEntry.tryFrom(raw), isNull, reason: '$raw');
      }
    });

    test('equal fields are equal, with equal hash codes', () {
      expect(full(), full());
      expect(full().hashCode, full().hashCode);
    });

    test('a different field is unequal', () {
      expect(full(), isNot(bare()));
    });

    test('toString names the ref and the count', () {
      expect(full().toString(), contains('wolt/vitrina'));
      expect(full().toString(), contains('3'));
    });
  });
}
