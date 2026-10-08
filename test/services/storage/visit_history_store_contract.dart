import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';

import '../../fakes/fake_clock.dart';

/// A venue this suite records visits for.
const VenueRef _woltRef = VenueRef(source: MenuSource.wolt, platformId: 'x');

/// The same platform id on another platform: a different menu.
const VenueRef _tenbisRef = VenueRef(
  source: MenuSource.tenbis,
  platformId: 'x',
);

/// The time every suite's clock starts at.
final DateTime _start = DateTime.utc(2026, 10, 8, 12);

/// Asserts the [VisitHistoryStore] contract against the implementation
/// [build] returns. Call this from each implementation's own test file —
/// including the fake — passing a factory that returns a fresh, virgin
/// instance stamped by the given clock on every call (architecture.md
/// §18.1, Liskov).
void runVisitHistoryStoreContract(
  String name,
  VisitHistoryStore Function(FakeClock clock) build,
) {
  group('$name (VisitHistoryStore contract)', () {
    late FakeClock clock;
    late VisitHistoryStore store;

    setUp(() {
      clock = FakeClock(_start);
      store = build(clock);
    });

    test('read on a virgin store returns null', () async {
      expect(await store.read(_woltRef), isNull);
    });

    test('entries on a virgin store is empty', () async {
      expect(await store.entries(), isEmpty);
    });

    test('the first visit opens and last-opens now, once', () async {
      // Act
      await store.recordVisit(_woltRef, name: 'Vitrina');

      // Assert
      final entry = await store.read(_woltRef);
      expect(entry, isNotNull);
      expect(entry!.ref, _woltRef);
      expect(entry.name, 'Vitrina');
      expect(entry.firstOpenedAt, _start);
      expect(entry.lastOpenedAt, _start);
      expect(entry.openCount, 1);
      expect(await store.entries(), <VisitEntry>[entry]);
    });

    test('a later visit counts again and moves only the last-opened '
        'time', () async {
      // Arrange
      await store.recordVisit(_woltRef);
      clock.advance(const Duration(hours: 3));

      // Act
      await store.recordVisit(_woltRef);

      // Assert
      final entry = (await store.read(_woltRef))!;
      expect(entry.openCount, 2);
      expect(entry.firstOpenedAt, _start);
      expect(entry.lastOpenedAt, _start.add(const Duration(hours: 3)));
    });

    test('a null never erases a recorded value', () async {
      // Arrange
      await store.recordVisit(
        _woltRef,
        name: 'Vitrina',
        city: 'Tel Aviv',
        dishCount: 20,
        score: 7.5,
        greenCount: 4,
        yellowCount: 6,
      );

      // Act
      await store.recordVisit(_woltRef);

      // Assert
      final entry = (await store.read(_woltRef))!;
      expect(entry.name, 'Vitrina');
      expect(entry.city, 'Tel Aviv');
      expect(entry.dishCount, 20);
      expect(entry.score, 7.5);
      expect(entry.greenCount, 4);
      expect(entry.yellowCount, 6);
    });

    test('a non-null value replaces the recorded one', () async {
      // Arrange
      await store.recordVisit(
        _woltRef,
        name: 'Vitrina',
        city: 'Tel Aviv',
        dishCount: 20,
        score: 7.5,
        greenCount: 4,
        yellowCount: 6,
      );

      // Act
      await store.recordVisit(
        _woltRef,
        name: 'Vitrina Lilienblum',
        city: 'Jaffa',
        dishCount: 22,
        score: 6,
        greenCount: 3,
        yellowCount: 7,
      );

      // Assert
      final entry = (await store.read(_woltRef))!;
      expect(entry.name, 'Vitrina Lilienblum');
      expect(entry.city, 'Jaffa');
      expect(entry.dishCount, 22);
      expect(entry.score, 6);
      expect(entry.greenCount, 3);
      expect(entry.yellowCount, 7);
    });

    test('rename sets both name and city', () async {
      // Arrange
      await store.recordVisit(_woltRef, name: 'Old', city: 'Haifa');

      // Act
      await store.rename(_woltRef, name: 'New', city: 'Tel Aviv');

      // Assert
      final entry = (await store.read(_woltRef))!;
      expect(entry.name, 'New');
      expect(entry.city, 'Tel Aviv');
      expect(entry.openCount, 1);
      expect(entry.lastOpenedAt, _start);
    });

    test('rename with nulls clears both name and city', () async {
      // Arrange
      await store.recordVisit(_woltRef, name: 'Old', city: 'Haifa');

      // Act
      await store.rename(_woltRef, name: null, city: null);

      // Assert
      final entry = (await store.read(_woltRef))!;
      expect(entry.name, isNull);
      expect(entry.city, isNull);
    });

    test('rename of a ref with no entry creates none', () async {
      // Act
      await store.rename(_woltRef, name: 'New', city: 'Tel Aviv');

      // Assert
      expect(await store.read(_woltRef), isNull);
      expect(await store.entries(), isEmpty);
    });

    test('remove deletes only that entry', () async {
      // Arrange
      await store.recordVisit(_woltRef);
      await store.recordVisit(_tenbisRef);

      // Act
      await store.remove(_woltRef);

      // Assert
      expect(await store.read(_woltRef), isNull);
      expect(await store.read(_tenbisRef), isNotNull);
      expect(await store.entries(), hasLength(1));
    });

    test('remove of a ref with no entry completes', () async {
      await expectLater(store.remove(_woltRef), completes);
    });

    test('clear removes every entry', () async {
      // Arrange
      await store.recordVisit(_woltRef);
      await store.recordVisit(_tenbisRef);

      // Act
      await store.clear();

      // Assert
      expect(await store.entries(), isEmpty);
      expect(await store.read(_woltRef), isNull);
    });

    test('entries are keyed by the whole ref, platform included', () async {
      // Act
      await store.recordVisit(_woltRef, name: 'On Wolt');
      await store.recordVisit(_tenbisRef, name: 'On 10bis');

      // Assert
      expect((await store.read(_woltRef))!.name, 'On Wolt');
      expect((await store.read(_tenbisRef))!.name, 'On 10bis');
      final refs = (await store.entries()).map((e) => e.ref).toSet();
      expect(refs, <VenueRef>{_woltRef, _tenbisRef});
    });
  });
}
