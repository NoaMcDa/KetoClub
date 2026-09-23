import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/storage/install_id_store.dart';

/// Matches exactly what a valid install ID looks like: 32 lowercase hex
/// characters (`backend_plan.md` §3.4). Kept local to this suite rather
/// than exported from `install_id_store.dart`, whose own validation
/// pattern is private.
final RegExp _validInstallIdShape = RegExp(r'^[0-9a-f]{32}$');

/// Asserts the [InstallIdStore] contract against the implementation
/// [build] returns. Call this from each implementation's own test file —
/// including the fake — passing a factory that returns a fresh instance on
/// every call (architecture.md §18.1, Liskov).
void runInstallIdStoreContract(String name, InstallIdStore Function() build) {
  group('$name (InstallIdStore contract)', () {
    test('id returns 32 lowercase hex characters', () async {
      final store = build();

      final id = await store.id();

      expect(id, matches(_validInstallIdShape));
    });

    test('id is stable across two calls on the same instance', () async {
      final store = build();

      final first = await store.id();
      final second = await store.id();

      expect(second, equals(first));
    });

    test('id never throws', () async {
      final store = build();

      await expectLater(store.id(), completes);
    });
  });
}
