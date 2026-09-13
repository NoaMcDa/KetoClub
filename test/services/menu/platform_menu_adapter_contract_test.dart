import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';

import '../../fakes/fake_platform_menu_adapter.dart';
import 'platform_menu_adapter_contract.dart';

/// The ref [FakePlatformMenuAdapter] is configured to accept.
const VenueRef _refItHandles = VenueRef(
  source: MenuSource.wolt,
  platformId: 'accepted-venue',
);

/// A ref on a different [MenuSource], which the fake must reject.
const VenueRef _refItRejects = VenueRef(
  source: MenuSource.tenbis,
  platformId: 'rejected-venue',
);

/// A menu for [_refItHandles], used by the value-semantics tests below.
Menu _menu() => Menu(
  venueRef: _refItHandles,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const <MenuCategory>[],
);

void main() {
  runPlatformMenuAdapterContract(
    'FakePlatformMenuAdapter',
    FakePlatformMenuAdapter.new,
    refItHandles: _refItHandles,
    refItRejects: _refItRejects,
  );

  group('MenuFetched value semantics', () {
    test('equal fields make two instances equal', () {
      final a = MenuFetched(menu: _menu());
      final b = MenuFetched(menu: _menu());
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.toString(), contains('MenuFetched'));
    });

    test('a differing fromCache makes two instances unequal', () {
      final menu = _menu();
      final a = MenuFetched(menu: menu);
      final b = MenuFetched(
        menu: menu,
        fromCache: true,
        staleReason: MenuFetchFailureReason.offline,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('MenuFetchFailed value semantics', () {
    test('equal fields make two instances equal', () {
      const a = MenuFetchFailed(
        reason: MenuFetchFailureReason.notFound,
        statusCode: 404,
      );
      const b = MenuFetchFailed(
        reason: MenuFetchFailureReason.notFound,
        statusCode: 404,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.toString(), contains('MenuFetchFailed'));
    });

    test('a differing statusCode makes two instances unequal', () {
      const a = MenuFetchFailed(
        reason: MenuFetchFailureReason.platformChanged,
        statusCode: 500,
      );
      const b = MenuFetchFailed(
        reason: MenuFetchFailureReason.platformChanged,
        statusCode: 502,
      );
      expect(a, isNot(equals(b)));
    });
  });
}
