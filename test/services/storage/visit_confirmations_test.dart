// The post-meal answers kept with the visit history (Banto, ALG-14, issue
// #356; architecture.md D27): a round-trip through the Hive store, the
// tolerant read, nothing written when empty, and every other write keeping
// them.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dish_confirmation.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';

import '../../fakes/fake_clock.dart';

const String _boxName = 'menu_history';

const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'x');

final DateTime _day = DateTime(2026, 5, 12);

/// A sesame answer about the dish [dishId] with [polarity] on [day].
DishConfirmation _sesame(
  String dishId,
  ConfirmationPolarity polarity, {
  DateTime? day,
}) => DishConfirmation(
  dishId: dishId,
  restrictionId: RestrictionId.sesame,
  polarity: polarity,
  day: day ?? _day,
  source: ConcernSource.name,
  matchedText: 'טחינה',
);

HiveVisitHistoryStore _store() => HiveVisitHistoryStore(
  openBox: () => Hive.openBox<String>(_boxName),
  clock: FakeClock(DateTime.utc(2026)),
);

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('visit_confirmations_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  group('HiveVisitHistoryStore and the post-meal answers', () {
    test('setConfirmations round-trips the answers', () async {
      // Arrange
      final store = _store();
      await store.recordVisit(_ref, name: 'Hummus Bar');
      final confirmations = <DishConfirmation>[
        _sesame('salad', ConfirmationPolarity.present),
        _sesame('cake', ConfirmationPolarity.absent),
      ];
      final changes = <ChangeConfirmation>[
        ChangeConfirmation(dishId: 'salad', honoured: true, day: _day),
      ];

      // Act
      await store.setConfirmations(
        _ref,
        confirmations: confirmations,
        changes: changes,
      );
      final read = await store.read(_ref);

      // Assert
      expect(read?.confirmations, confirmations);
      expect(read?.changeConfirmations, changes);
      expect(read?.name, 'Hummus Bar');
    });

    test('setConfirmations creates no entry for a menu never opened', () async {
      // Arrange
      final store = _store();

      // Act
      await store.setConfirmations(
        _ref,
        confirmations: <DishConfirmation>[
          _sesame('salad', ConfirmationPolarity.present),
        ],
        changes: const <ChangeConfirmation>[],
      );

      // Assert
      expect(await store.read(_ref), isNull);
    });

    test('a later visit and a rename keep the answers', () async {
      // Arrange
      final store = _store();
      await store.recordVisit(_ref, openedStrict: true);
      final confirmations = <DishConfirmation>[
        _sesame('salad', ConfirmationPolarity.present),
      ];
      await store.setConfirmations(
        _ref,
        confirmations: confirmations,
        changes: const <ChangeConfirmation>[],
      );

      // Act
      await store.recordVisit(_ref, dishCount: 3);
      await store.rename(_ref, name: 'Renamed', city: null);
      final read = await store.read(_ref);

      // Assert
      expect(read?.confirmations, confirmations);
      expect(read?.openCount, 2);
      expect(read?.openedStrict, isTrue);
      expect(read?.name, 'Renamed');
    });

    test(
      'openedStrict is set by a strict visit and kept by a later one',
      () async {
        // Arrange
        final store = _store();

        // Act
        await store.recordVisit(_ref);
        final before = await store.read(_ref);
        await store.recordVisit(_ref, openedStrict: true);
        await store.recordVisit(_ref);
        final after = await store.read(_ref);

        // Assert
        expect(before?.openedStrict, isFalse);
        expect(after?.openedStrict, isTrue);
      },
    );

    test('an entry with no answers writes none of their keys', () async {
      // Arrange
      final store = _store();
      await store.recordVisit(_ref, name: 'Plain');
      await store.setConfirmations(
        _ref,
        confirmations: const <DishConfirmation>[],
        changes: const <ChangeConfirmation>[],
      );

      // Act
      final box = await Hive.openBox<String>(_boxName);
      final stored =
          jsonDecode(box.get(_ref.cacheKey)!) as Map<String, Object?>;

      // Assert
      expect(stored.containsKey('confirmations'), isFalse);
      expect(stored.containsKey('changeConfirmations'), isFalse);
      expect(stored.containsKey('openedStrict'), isFalse);
    });
  });

  group('VisitEntry reads the answers tolerantly', () {
    Map<String, Object?> base() => <String, Object?>{
      'source': 'wolt',
      'platformId': 'x',
      'firstOpenedAt': '2026-05-12T10:00:00.000Z',
      'lastOpenedAt': '2026-05-12T10:00:00.000Z',
      'openCount': 1,
    };

    test('a non-list reads as none and keeps the visit', () {
      // Act
      final entry = VisitEntry.tryFrom(
        base()
          ..['confirmations'] = 'nope'
          ..['changeConfirmations'] = 7
          ..['openedStrict'] = 'yes',
      );

      // Assert
      expect(entry, isNotNull);
      expect(entry!.confirmations, isEmpty);
      expect(entry.changeConfirmations, isEmpty);
      expect(entry.openedStrict, isFalse);
    });

    test('a malformed answer and a repeat are dropped', () {
      // Arrange
      final good = _sesame('salad', ConfirmationPolarity.present).toJson();

      // Act
      final entry = VisitEntry.tryFrom(
        base()
          ..['confirmations'] = <Object?>[
            good,
            <String, Object?>{'dishId': 'x'},
            good,
          ],
      );

      // Assert
      expect(entry!.confirmations, <DishConfirmation>[
        _sesame('salad', ConfirmationPolarity.present),
      ]);
    });

    test('a keto entry serialises exactly as before', () {
      // Arrange
      final entry = VisitEntry.tryFrom(base())!;

      // Act
      final json = entry.toJson();

      // Assert
      expect(json.keys, <String>[
        'source',
        'platformId',
        'firstOpenedAt',
        'lastOpenedAt',
        'openCount',
      ]);
    });

    test('withConfirmations keeps the latest days past the cap', () {
      // Arrange
      final entry = VisitEntry.tryFrom(base())!;
      final many = <DishConfirmation>[
        for (var i = 0; i <= VisitEntry.maxConfirmations; i++)
          _sesame(
            'dish$i',
            ConfirmationPolarity.present,
            day: DateTime(2025).add(Duration(days: i)),
          ),
      ];

      // Act
      final capped = entry.withConfirmations(
        confirmations: many,
        changes: const <ChangeConfirmation>[],
      );

      // Assert: the oldest day, the first, is the one dropped.
      expect(capped.confirmations, hasLength(VisitEntry.maxConfirmations));
      expect(capped.confirmations.first.dishId, 'dish1');
      expect(capped, isNot(entry));
    });
  });

  test('NoVisitHistoryStore ignores the answers', () async {
    // Arrange
    const store = NoVisitHistoryStore();

    // Act
    await store.recordVisit(_ref, openedStrict: true);
    await store.setConfirmations(
      _ref,
      confirmations: <DishConfirmation>[
        _sesame('salad', ConfirmationPolarity.present),
      ],
      changes: const <ChangeConfirmation>[],
    );

    // Assert
    expect(await store.read(_ref), isNull);
  });
}
