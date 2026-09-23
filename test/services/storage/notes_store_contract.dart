import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/notes_store.dart';

/// A venue this suite reads and writes notes for.
const VenueRef _venue = VenueRef(source: MenuSource.wolt, platformId: 'v1');

/// A second, distinct venue, for cross-venue isolation assertions.
const VenueRef _otherVenue = VenueRef(
  source: MenuSource.wolt,
  platformId: 'v2',
);

/// Asserts the [NotesStore] contract against the implementation [build]
/// returns. Call this from each implementation's own test file —
/// including the fake — passing a factory that returns a fresh, virgin
/// instance on every call (architecture.md §18.1, Liskov).
void runNotesStoreContract(String name, NotesStore Function() build) {
  group('$name (NotesStore contract)', () {
    test('read on a virgin store returns null', () async {
      final store = build();

      expect(await store.read(_venue, 'dish_1'), isNull);
    });

    test('readAll on a virgin store returns an empty map', () async {
      final store = build();

      expect(await store.readAll(_venue), isEmpty);
    });

    test('write then read round-trips the note', () async {
      final store = build();

      await store.write(_venue, 'dish_1', 'Ask for no cheese.');

      expect(await store.read(_venue, 'dish_1'), equals('Ask for no cheese.'));
    });

    test('write then write replaces the note, not appends to it', () async {
      final store = build();

      await store.write(_venue, 'dish_1', 'First note.');
      await store.write(_venue, 'dish_1', 'Second note.');

      expect(await store.read(_venue, 'dish_1'), equals('Second note.'));
    });

    test(
      'notes for different dishes on the same venue are independent',
      () async {
        final store = build();

        await store.write(_venue, 'dish_1', 'About dish 1.');
        await store.write(_venue, 'dish_2', 'About dish 2.');

        expect(await store.read(_venue, 'dish_1'), equals('About dish 1.'));
        expect(await store.read(_venue, 'dish_2'), equals('About dish 2.'));
      },
    );

    test(
      'notes for the same dish id on different venues are independent',
      () async {
        final store = build();

        await store.write(_venue, 'dish_1', 'This venue only.');
        await store.write(_otherVenue, 'dish_1', 'Other venue only.');

        expect(await store.read(_venue, 'dish_1'), equals('This venue only.'));
        expect(
          await store.read(_otherVenue, 'dish_1'),
          equals('Other venue only.'),
        );
      },
    );

    test(
      'readAll returns every note written for a venue, keyed by dish id',
      () async {
        final store = build();

        await store.write(_venue, 'dish_1', 'Note one.');
        await store.write(_venue, 'dish_2', 'Note two.');
        await store.write(_otherVenue, 'dish_3', 'Not this venue.');

        final all = await store.readAll(_venue);

        expect(
          all,
          equals(<String, String>{
            'dish_1': 'Note one.',
            'dish_2': 'Note two.',
          }),
        );
      },
    );

    test('delete removes the note for that dish only', () async {
      final store = build();
      await store.write(_venue, 'dish_1', 'Keep me.');
      await store.write(_venue, 'dish_2', 'Delete me.');

      await store.delete(_venue, 'dish_2');

      expect(await store.read(_venue, 'dish_1'), equals('Keep me.'));
      expect(await store.read(_venue, 'dish_2'), isNull);
    });

    test('delete on a dish with no note is a no-op, not a throw', () async {
      final store = build();

      await expectLater(store.delete(_venue, 'never_written'), completes);
      expect(await store.read(_venue, 'never_written'), isNull);
    });

    test('delete does not affect other venues', () async {
      final store = build();
      await store.write(_venue, 'dish_1', 'This venue.');
      await store.write(_otherVenue, 'dish_1', 'Other venue.');

      await store.delete(_venue, 'dish_1');

      expect(await store.read(_venue, 'dish_1'), isNull);
      expect(await store.read(_otherVenue, 'dish_1'), equals('Other venue.'));
    });

    test('read never throws', () async {
      final store = build();

      await expectLater(store.read(_venue, 'dish_1'), completes);
    });

    test('write never throws', () async {
      final store = build();

      await expectLater(store.write(_venue, 'dish_1', 'A note.'), completes);
    });

    test('delete never throws', () async {
      final store = build();

      await expectLater(store.delete(_venue, 'dish_1'), completes);
    });

    test('readAll never throws', () async {
      final store = build();

      await expectLater(store.readAll(_venue), completes);
    });
  });
}
