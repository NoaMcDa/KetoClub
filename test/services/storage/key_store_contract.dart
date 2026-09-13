import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/storage/key_store.dart';

/// Asserts the [KeyStore] contract against the implementation [build]
/// returns. Call this from each implementation's own test file —
/// including the fake — passing a factory that returns a fresh, empty
/// instance on every call (architecture.md §18.1, Liskov).
void runKeyStoreContract(String name, KeyStore Function() build) {
  group('$name (KeyStore contract)', () {
    test('read returns null before any write', () async {
      final store = build();

      expect(await store.read(), isNull);
    });

    test('hasKey is false before any write', () async {
      final store = build();

      expect(await store.hasKey(), isFalse);
    });

    test('write then read returns the written key', () async {
      final store = build();

      await store.write('sk-live-abc123');

      expect(await store.read(), equals('sk-live-abc123'));
    });

    test('write then hasKey is true', () async {
      final store = build();

      await store.write('sk-live-abc123');

      expect(await store.hasKey(), isTrue);
    });

    test('a written key reads back byte-identical', () async {
      final store = build();
      const key = 'sk-live-ABC_123.xyz~é';

      await store.write(key);

      expect(await store.read(), equals(key));
    });

    test('write then write replaces the key, not appends it', () async {
      final store = build();

      await store.write('first');
      await store.write('second');

      expect(await store.read(), equals('second'));
    });

    test('delete then read returns null', () async {
      final store = build();
      await store.write('sk-live-abc123');

      await store.delete();

      expect(await store.read(), isNull);
    });

    test('delete then hasKey is false', () async {
      final store = build();
      await store.write('sk-live-abc123');

      await store.delete();

      expect(await store.hasKey(), isFalse);
    });

    test('delete on an empty store is a no-op, not a throw', () async {
      final store = build();

      await expectLater(store.delete(), completes);
      expect(await store.read(), isNull);
    });
  });
}
