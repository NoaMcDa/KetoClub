import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/menu/backend/backend_menu_adapter.dart';
import 'package:ketoclub/services/menu/fallback_menu_adapter.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';

import '../../fakes/fake_install_id_store.dart';
import '../../fakes/fake_platform_menu_adapter.dart';
import 'platform_menu_adapter_contract.dart';

const VenueRef _woltRef = VenueRef(
  source: MenuSource.wolt,
  platformId: 'hamosad',
);

const VenueRef _tenbisRef = VenueRef(
  source: MenuSource.tenbis,
  platformId: '12345',
);

/// A menu for [_woltRef] tagged with [venueName], so a test can tell
/// which adapter answered.
Menu _menu(String venueName) => Menu(
  venueRef: _woltRef,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026, 10, 2),
  venueName: venueName,
  categories: const <MenuCategory>[],
);

/// A fake adapter whose [canHandle] answers [handles] for its own source.
final class _SelectiveAdapter extends FakePlatformMenuAdapter {
  new({required this.handles});

  /// Whether this adapter accepts a ref of its own source.
  final bool handles;

  @override
  bool canHandle(VenueRef ref) => super.canHandle(ref) && handles;
}

void main() {
  runPlatformMenuAdapterContract(
    'FallbackMenuAdapter over two fakes',
    () => FallbackMenuAdapter(
      primary: FakePlatformMenuAdapter(),
      fallback: FakePlatformMenuAdapter(),
    ),
    refItHandles: _woltRef,
    refItRejects: _tenbisRef,
  );

  runPlatformMenuAdapterContract(
    'FallbackMenuAdapter over a backend with no URL',
    () => FallbackMenuAdapter(
      primary: BackendMenuAdapter(
        client: MockClient((_) async => http.Response('', 500)),
        baseUrl: null,
        installIdStore: FakeInstallIdStore(),
        source: MenuSource.wolt,
        readOptions: () async => const ClassificationOptions(),
      ),
      fallback: FakePlatformMenuAdapter(),
    ),
    refItHandles: _woltRef,
    refItRejects: _tenbisRef,
  );

  runPlatformMenuAdapterContract(
    'FallbackMenuAdapter over an unreachable backend',
    () => FallbackMenuAdapter(
      primary: BackendMenuAdapter(
        client: MockClient((_) async => throw http.ClientException('down')),
        baseUrl: Uri.parse('http://localhost:8000'),
        installIdStore: FakeInstallIdStore(),
        source: MenuSource.wolt,
        readOptions: () async => const ClassificationOptions(),
      ),
      fallback: FakePlatformMenuAdapter(),
    ),
    refItHandles: _woltRef,
    refItRejects: _tenbisRef,
  );

  group('FallbackMenuAdapter', () {
    late FakePlatformMenuAdapter primary;
    late FakePlatformMenuAdapter fallback;
    late FallbackMenuAdapter adapter;

    setUp(() {
      primary = FakePlatformMenuAdapter();
      fallback = FakePlatformMenuAdapter();
      adapter = FallbackMenuAdapter(primary: primary, fallback: fallback);
    });

    test('source is the fallback source', () {
      final mixed = FallbackMenuAdapter(
        primary: FakePlatformMenuAdapter(),
        fallback: FakePlatformMenuAdapter(source: MenuSource.tenbis),
      );
      expect(mixed.source, MenuSource.tenbis);
    });

    test('canHandle is true when either adapter handles the ref', () {
      final onlyPrimary = FallbackMenuAdapter(
        primary: FakePlatformMenuAdapter(),
        fallback: _SelectiveAdapter(handles: false),
      );
      final onlyFallback = FallbackMenuAdapter(
        primary: _SelectiveAdapter(handles: false),
        fallback: FakePlatformMenuAdapter(),
      );
      final neither = FallbackMenuAdapter(
        primary: _SelectiveAdapter(handles: false),
        fallback: _SelectiveAdapter(handles: false),
      );

      expect(onlyPrimary.canHandle(_woltRef), isTrue);
      expect(onlyFallback.canHandle(_woltRef), isTrue);
      expect(neither.canHandle(_woltRef), isFalse);
      expect(adapter.canHandle(_tenbisRef), isFalse);
    });

    test('a primary success is returned; the fallback is not asked', () async {
      primary.queueFetched(_menu('primary'));

      final result = await adapter.fetch(_woltRef);

      expect((result as MenuFetched).menu.venueName, 'primary');
      expect(fallback.fetchCalls, isEmpty);
    });

    for (final reason in <MenuFetchFailureReason>[
      MenuFetchFailureReason.backendUnreachable,
      MenuFetchFailureReason.offline,
    ]) {
      test('a primary $reason asks the fallback', () async {
        primary.queueFailed(reason);
        fallback.queueFetched(_menu('fallback'));

        final result = await adapter.fetch(_woltRef);

        expect((result as MenuFetched).menu.venueName, 'fallback');
        expect(fallback.fetchCalls, <VenueRef>[_woltRef]);
      });
    }

    for (final reason in <MenuFetchFailureReason>[
      MenuFetchFailureReason.notFound,
      MenuFetchFailureReason.platformChanged,
      MenuFetchFailureReason.websiteRateLimited,
      MenuFetchFailureReason.menuNotFound,
    ]) {
      test('a primary $reason is returned as is', () async {
        primary.queueFailed(reason, statusCode: 404);

        final result = await adapter.fetch(_woltRef);

        expect(result, MenuFetchFailed(reason: reason, statusCode: 404));
        expect(fallback.fetchCalls, isEmpty);
      });
    }

    test('when both fail, the primary failure is returned', () async {
      primary.queueFailed(
        MenuFetchFailureReason.backendUnreachable,
        statusCode: 503,
      );
      fallback.queueFailed(MenuFetchFailureReason.blockedByBrowser);

      final result = await adapter.fetch(_woltRef);

      expect(
        result,
        const MenuFetchFailed(
          reason: MenuFetchFailureReason.backendUnreachable,
          statusCode: 503,
        ),
      );
      expect(fallback.fetchCalls, <VenueRef>[_woltRef]);
    });

    test('a primary that cannot handle the ref defers wholly', () async {
      final skipping = FallbackMenuAdapter(
        primary: _SelectiveAdapter(handles: false),
        fallback: fallback,
      );
      fallback.queueFailed(MenuFetchFailureReason.notFound);

      final result = await skipping.fetch(_woltRef);

      expect(
        result,
        const MenuFetchFailed(reason: MenuFetchFailureReason.notFound),
      );
    });

    test('a fallback that cannot handle the ref is never asked', () async {
      final noFallback = _SelectiveAdapter(handles: false);
      final wrapped = FallbackMenuAdapter(
        primary: primary,
        fallback: noFallback,
      );
      primary.queueFailed(MenuFetchFailureReason.backendUnreachable);

      final result = await wrapped.fetch(_woltRef);

      expect(
        result,
        const MenuFetchFailed(
          reason: MenuFetchFailureReason.backendUnreachable,
        ),
      );
      expect(noFallback.fetchCalls, isEmpty);
    });

    test('a ref of another source goes to the fallback only', () async {
      final result = await adapter.fetch(_tenbisRef);

      expect(primary.fetchCalls, isEmpty);
      expect(fallback.fetchCalls, <VenueRef>[_tenbisRef]);
      expect(result, isA<MenuFetchResult>());
    });

    test('a custom shouldFallBack decides which failures retry', () async {
      final custom = FallbackMenuAdapter(
        primary: primary,
        fallback: fallback,
        shouldFallBack: (reason) => reason == MenuFetchFailureReason.notFound,
      );
      primary
        ..queueFailed(MenuFetchFailureReason.notFound)
        ..queueFailed(MenuFetchFailureReason.backendUnreachable);
      fallback.queueFetched(_menu('fallback'));

      final first = await custom.fetch(_woltRef);
      final second = await custom.fetch(_woltRef);

      expect(first, isA<MenuFetched>());
      expect(
        second,
        const MenuFetchFailed(
          reason: MenuFetchFailureReason.backendUnreachable,
        ),
      );
    });

    test('a usePrimary that says no sends the fetch to the fallback only, '
        'and its failure is the answer (issue #331)', () async {
      // Arrange: the AI consent is withheld, so the backend is not asked.
      var asked = 0;
      final gated = FallbackMenuAdapter(
        primary: primary,
        fallback: fallback,
        usePrimary: () async {
          asked++;
          return false;
        },
      );
      fallback.queueFailed(MenuFetchFailureReason.notFound);

      // Act
      final result = await gated.fetch(_woltRef);

      // Assert
      expect(asked, 1);
      expect(primary.fetchCalls, isEmpty);
      expect(fallback.fetchCalls, <VenueRef>[_woltRef]);
      expect(
        result,
        const MenuFetchFailed(reason: MenuFetchFailureReason.notFound),
      );
    });

    test('a usePrimary that says yes asks the primary first', () async {
      // Arrange
      final gated = FallbackMenuAdapter(
        primary: primary,
        fallback: fallback,
        usePrimary: () async => true,
      );
      primary.queueFetched(_menu('primary'));

      // Act
      final result = await gated.fetch(_woltRef);

      // Assert
      expect((result as MenuFetched).menu.venueName, 'primary');
      expect(fallback.fetchCalls, isEmpty);
    });

    test(
      'usePrimary is not asked for a ref the primary cannot handle',
      () async {
        // Arrange
        var asked = 0;
        final gated = FallbackMenuAdapter(
          primary: _SelectiveAdapter(handles: false),
          fallback: fallback,
          usePrimary: () async {
            asked++;
            return true;
          },
        );
        fallback.queueFetched(_menu('fallback'));

        // Act
        final result = await gated.fetch(_woltRef);

        // Assert
        expect((result as MenuFetched).menu.venueName, 'fallback');
        expect(asked, 0);
      },
    );

    test('usePrimary defaults to always', () async {
      expect(await adapter.usePrimary(), isTrue);
    });

    test('defaults to BackendMenuAdapter.shouldFallBack', () {
      expect(
        identical(adapter.shouldFallBack, BackendMenuAdapter.shouldFallBack),
        isTrue,
      );
    });

    test('an unreachable backend falls back to the device adapter', () async {
      final requests = <http.Request>[];
      final wrapped = FallbackMenuAdapter(
        primary: BackendMenuAdapter(
          client: MockClient((request) async {
            requests.add(request);
            throw http.ClientException('down');
          }),
          baseUrl: Uri.parse('http://localhost:8000'),
          installIdStore: FakeInstallIdStore(),
          source: MenuSource.wolt,
          readOptions: () async => const ClassificationOptions(),
        ),
        fallback: fallback,
      );
      fallback.queueFetched(_menu('device'));

      final result = await wrapped.fetch(_woltRef);

      expect(requests, hasLength(1));
      expect((result as MenuFetched).menu.venueName, 'device');
    });
  });
}
