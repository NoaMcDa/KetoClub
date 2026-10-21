// The Recent tab's per-profile fields kept with the visit history (Banto,
// issues #411 and #412; architecture.md D26): the state counts, the profile
// fingerprint, the strict dishes and the "worked for" people. A keto entry
// is byte for byte what it was; every field reads tolerantly; the dish list
// is capped at 200.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/models/visit_dish.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';

import '../../fakes/fake_clock.dart';

const String _boxName = 'menu_history';

const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'x');

/// The JSON of a plain entry, as every build wrote it before #411/#412.
final String _ketoJson = <String>[
  '{"source":"wolt","platformId":"x","name":"Hummus Bar",',
  '"city":"Tel Aviv","firstOpenedAt":"2026-01-01T00:00:00.000Z",',
  '"lastOpenedAt":"2026-01-01T00:00:00.000Z","openCount":1,',
  '"dishCount":12,"score":7.5,"greenCount":5,"yellowCount":3}',
].join();

/// A strict dish named [id] with a sesame concern.
VisitDish _dish(String id, {bool change = false}) => VisitDish(
  dishId: id,
  name: 'Dish $id',
  hasChange: change,
  concerns: const <VisitConcern>[
    VisitConcern(
      restrictionId: RestrictionId.sesame,
      source: ConcernSource.name,
    ),
  ],
);

/// A snapshot holding [dishes].
VisitSnapshot _snapshot(List<VisitDish> dishes, {String fingerprint = 'abc'}) =>
    VisitSnapshot(
      fits: 4,
      withChange: 2,
      ask: 3,
      avoid: 1,
      profileFingerprint: fingerprint,
      strictDishes: dishes,
    );

HiveVisitHistoryStore _store() => HiveVisitHistoryStore(
  openBox: () => Hive.openBox<String>(_boxName),
  clock: FakeClock(DateTime.utc(2026)),
);

/// The JSON map [_ketoJson] with [extra] merged in.
Map<String, Object?> _json([Map<String, Object?> extra = const {}]) =>
    <String, Object?>{
      ...(jsonDecode(_ketoJson) as Map<String, Object?>),
      ...extra,
    };

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('visit_profile_fields_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  group('VisitEntry and a keto entry', () {
    test('writes byte for byte the JSON it wrote before', () {
      // Arrange
      final entry = VisitEntry.tryFrom(_json())!;

      // Act & Assert
      expect(jsonEncode(entry.toJson()), _ketoJson);
    });

    test('reads with every new field absent', () {
      // Act
      final entry = VisitEntry.tryFrom(_json())!;

      // Assert
      expect(entry.hasStates, isFalse);
      expect(entry.fits, isNull);
      expect(entry.profileFingerprint, isNull);
      expect(entry.strictDishes, isNull);
      expect(entry.workedFor, isEmpty);
    });

    test('a visit without a snapshot or a mark adds no key', () async {
      // Arrange
      final store = _store();

      // Act
      await store.recordVisit(_ref, name: 'Hummus Bar', dishCount: 12);
      final box = await Hive.openBox<String>(_boxName);
      final keys = (jsonDecode(box.get(_ref.cacheKey)!) as Map).keys;

      // Assert
      expect(
        keys,
        isNot(
          anyOf(
            contains('fits'),
            contains('profileFingerprint'),
            contains('strictDishes'),
            contains('workedFor'),
          ),
        ),
      );
    });
  });

  group('VisitEntry round trip', () {
    test('keeps the counts, fingerprint, dishes and people', () {
      // Arrange
      final entry = VisitEntry(
        ref: _ref,
        firstOpenedAt: DateTime.utc(2026),
        lastOpenedAt: DateTime.utc(2026),
        openCount: 2,
        fits: 4,
        withChange: 2,
        ask: 3,
        avoid: 1,
        profileFingerprint: 'abc',
        strictDishes: <VisitDish>[
          _dish('a', change: true),
          const VisitDish(
            dishId: 'b',
            name: 'Kiwi tart',
            concerns: <VisitConcern>[
              VisitConcern(
                restrictionId: RestrictionId.custom,
                matchedText: 'kiwi',
              ),
            ],
          ),
        ],
        workedFor: const <String>['Me', 'Dana'],
      );

      // Act
      final read = VisitEntry.tryFrom(
        jsonDecode(jsonEncode(entry.toJson())) as Map<String, Object?>,
      );

      // Assert
      expect(read, entry);
      expect(read!.hasStates, isTrue);
      expect(read.strictDishes!.last.concerns.single.matchedText, 'kiwi');
    });

    test('an empty dish list is kept apart from an absent one', () {
      // Arrange
      final recorded = VisitEntry(
        ref: _ref,
        firstOpenedAt: DateTime.utc(2026),
        lastOpenedAt: DateTime.utc(2026),
        openCount: 1,
        strictDishes: const <VisitDish>[],
      );

      // Act
      final read = VisitEntry.tryFrom(
        jsonDecode(jsonEncode(recorded.toJson())) as Map<String, Object?>,
      )!;

      // Assert
      expect(read.strictDishes, isEmpty);
      expect(VisitEntry.tryFrom(_json())!.strictDishes, isNull);
    });
  });

  group('VisitEntry tolerant reads', () {
    test('a field of the wrong type reads as absent, never costing the '
        'visit', () {
      // Act
      final entry = VisitEntry.tryFrom(
        _json(<String, Object?>{
          'fits': 'many',
          'withChange': -1,
          'ask': 2.5,
          'avoid': null,
          'profileFingerprint': 7,
          'strictDishes': 'nope',
          'workedFor': 'Dana',
        }),
      )!;

      // Assert
      expect(entry.name, 'Hummus Bar');
      expect(entry.fits, isNull);
      expect(entry.withChange, isNull);
      expect(entry.ask, isNull);
      expect(entry.profileFingerprint, isNull);
      expect(entry.strictDishes, isNull);
      expect(entry.workedFor, isEmpty);
    });

    test('a malformed dish, concern or name is dropped', () {
      // Act
      final entry = VisitEntry.tryFrom(
        _json(<String, Object?>{
          'strictDishes': <Object?>[
            'junk',
            <String, Object?>{'id': 'a', 'name': 'A'},
            <String, Object?>{
              'id': 'b',
              'name': 'B',
              'concerns': <Object?>[
                <String, Object?>{'r': 'no-such-restriction'},
                <String, Object?>{'r': 'sesame', 's': 'no-such-source'},
              ],
            },
          ],
          'workedFor': <Object?>['Me', 3, '', 'Me', 'Dana'],
        }),
      )!;

      // Assert
      expect(entry.strictDishes, hasLength(1));
      expect(entry.strictDishes!.single.dishId, 'b');
      expect(entry.strictDishes!.single.concerns.single.source, isNull);
      expect(entry.workedFor, <String>['Me', 'Dana']);
    });

    test('keeps at most 200 dishes and 8 people', () {
      // Act
      final entry = VisitEntry.tryFrom(
        _json(<String, Object?>{
          'strictDishes': <Object?>[
            for (var i = 0; i < 250; i++) _dish('d$i').toJson(),
          ],
          'workedFor': <Object?>[for (var i = 0; i < 12; i++) 'p$i'],
        }),
      )!;

      // Assert
      expect(entry.strictDishes, hasLength(200));
      expect(entry.strictDishes!.first.dishId, 'd0');
      expect(entry.workedFor, hasLength(8));
    });

    test('a snapshot cuts its dishes to 200', () {
      // Act
      final snapshot = _snapshot(<VisitDish>[
        for (var i = 0; i < 230; i++) _dish('d$i'),
      ]);

      // Assert
      expect(snapshot.strictDishes, hasLength(200));
    });
  });

  group('HiveVisitHistoryStore and the profile fields', () {
    test(
      'a snapshot is stored, and a later visit without one keeps it',
      () async {
        // Arrange
        final store = _store();

        // Act
        await store.recordVisit(
          _ref,
          snapshot: _snapshot(<VisitDish>[_dish('a')]),
        );
        await store.recordVisit(_ref, dishCount: 9);
        final entry = (await store.read(_ref))!;

        // Assert
        expect(entry.openCount, 2);
        expect(entry.fits, 4);
        expect(entry.avoid, 1);
        expect(entry.profileFingerprint, 'abc');
        expect(entry.strictDishes!.single.dishId, 'a');
      },
    );

    test('a newer snapshot replaces the older as a whole', () async {
      // Arrange
      final store = _store();
      await store.recordVisit(
        _ref,
        snapshot: _snapshot(<VisitDish>[_dish('a')]),
      );

      // Act
      await store.recordVisit(
        _ref,
        snapshot: _snapshot(<VisitDish>[_dish('z')], fingerprint: 'new'),
      );
      final entry = (await store.read(_ref))!;

      // Assert
      expect(entry.profileFingerprint, 'new');
      expect(entry.strictDishes!.map((dish) => dish.dishId), <String>['z']);
    });

    test('setWorkedFor marks, recordVisit and rename keep it, and an '
        'unknown venue is not created', () async {
      // Arrange
      final store = _store();
      await store.setWorkedFor(_ref, <String>['Me']);
      expect(await store.read(_ref), isNull);
      await store.recordVisit(_ref, name: 'A');

      // Act
      await store.setWorkedFor(_ref, <String>['Me', 'Dana', 'Me']);
      await store.recordVisit(_ref, name: 'B');
      await store.rename(_ref, name: 'C', city: null);
      final entry = (await store.read(_ref))!;

      // Assert
      expect(entry.workedFor, <String>['Me', 'Dana']);
      expect(entry.name, 'C');
    });

    test('an empty list clears the marks and writes no key', () async {
      // Arrange
      final store = _store();
      await store.recordVisit(_ref);
      await store.setWorkedFor(_ref, <String>['Me']);

      // Act
      await store.setWorkedFor(_ref, const <String>[]);
      final box = await Hive.openBox<String>(_boxName);

      // Assert
      expect(
        (jsonDecode(box.get(_ref.cacheKey)!) as Map).containsKey('workedFor'),
        isFalse,
      );
    });

    test('clear removes the marks with the history', () async {
      // Arrange
      final store = _store();
      await store.recordVisit(_ref);
      await store.setWorkedFor(_ref, <String>['Me']);

      // Act
      await store.clear();

      // Assert
      expect(await store.read(_ref), isNull);
      expect(await store.entries(), isEmpty);
    });
  });
}
