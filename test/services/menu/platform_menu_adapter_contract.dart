// The shared PlatformMenuAdapter contract (architecture.md §18.1, Liskov).
//
// Every implementation of PlatformMenuAdapter, including the fake in
// test/fakes/, is run through this suite from its own *_contract_test.dart
// so an implementation cannot silently drift from the interface's
// documented contract. The suite asserts shape and provenance only — it
// never assumes a particular MenuFetchResult for a particular ref, because
// that is implementation behaviour, not interface contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';

/// Asserts the [PlatformMenuAdapter] contract against what [build] returns.
///
/// [refItHandles] must be a ref the adapter accepts; [refItRejects] one it
/// does not. The suite drives only the interface, never an implementation
/// detail: it does not assume what [PlatformMenuAdapter.fetch] returns for
/// either ref, only that the result obeys the documented invariants.
void runPlatformMenuAdapterContract(
  String name,
  PlatformMenuAdapter Function() build, {
  required VenueRef refItHandles,
  required VenueRef refItRejects,
}) {
  group(name, () {
    test('canHandle accepts refItHandles and rejects refItRejects', () {
      final adapter = build();
      expect(adapter.canHandle(refItHandles), isTrue);
      expect(adapter.canHandle(refItRejects), isFalse);
    });

    test('canHandle never throws', () {
      final adapter = build();
      expect(() => adapter.canHandle(refItHandles), returnsNormally);
      expect(() => adapter.canHandle(refItRejects), returnsNormally);
    });

    test('source is stable across repeated reads', () {
      final adapter = build();
      final first = adapter.source;
      final second = adapter.source;
      expect(second, equals(first));
    });

    test('canHandle is true only for a ref whose source matches', () {
      final adapter = build();
      if (adapter.canHandle(refItHandles)) {
        expect(refItHandles.source, equals(adapter.source));
      }
      if (adapter.canHandle(refItRejects)) {
        expect(refItRejects.source, equals(adapter.source));
      }
    });

    test('fetch never throws for a ref it handles', () async {
      final adapter = build();
      late final Future<MenuFetchResult> future;
      expect(() => future = adapter.fetch(refItHandles), returnsNormally);
      await expectLater(future, completes);
    });

    test('fetch never throws for a ref it does not handle', () async {
      final adapter = build();
      late final Future<MenuFetchResult> future;
      expect(() => future = adapter.fetch(refItRejects), returnsNormally);
      await expectLater(future, completes);
    });

    test('a fetched menu carries the ref that was asked for', () async {
      final adapter = build();
      for (final ref in [refItHandles, refItRejects]) {
        final result = await adapter.fetch(ref);
        if (result is MenuFetched) {
          expect(
            result.menu.venueRef,
            equals(ref),
            reason: 'fetch($ref) returned a menu for another venue',
          );
        }
      }
    });

    test('staleReason is null unless fromCache is true', () async {
      final adapter = build();
      for (final ref in [refItHandles, refItRejects]) {
        final result = await adapter.fetch(ref);
        if (result is MenuFetched && !result.fromCache) {
          expect(
            result.staleReason,
            isNull,
            reason: 'fromCache is false but staleReason is set',
          );
        }
      }
    });
  });
}
