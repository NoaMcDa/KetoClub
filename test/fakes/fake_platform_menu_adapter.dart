import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';

/// A scripted [PlatformMenuAdapter] for tests.
///
/// With nothing queued, [fetch] stands in for a working adapter: it
/// returns a [MenuFetched] wrapping a fresh, empty [Menu] keyed to
/// whichever [VenueRef] it was asked for, so the returned menu's
/// [Menu.venueRef] always matches the request. Queue a result with
/// [queueResult], [queueFetched], or [queueFailed] to stand in for a
/// cache hit, a 404, a `platformChanged` drift, or an offline device
/// instead: queued results are returned in order, and the last one
/// queued then sticks for every call after the queue drains. Every ref
/// this fake was asked about is recorded in [fetchCalls] and
/// [canHandleCalls].
class FakePlatformMenuAdapter implements PlatformMenuAdapter {
  /// Creates a fake that reads from [source].
  new({this.source = MenuSource.wolt});

  /// The fixed timestamp used for menus this fake synthesises by
  /// default, so results stay deterministic without an injected clock.
  static final DateTime defaultFetchedAt = DateTime.utc(2026);

  @override
  final MenuSource source;

  final List<MenuFetchResult> _queue = <MenuFetchResult>[];

  MenuFetchResult? _sticky;

  /// Every ref passed to [fetch], in call order.
  final List<VenueRef> fetchCalls = <VenueRef>[];

  /// Every ref passed to [canHandle], in call order.
  final List<VenueRef> canHandleCalls = <VenueRef>[];

  /// Queues [result] to be returned starting with the next [fetch] call.
  void queueResult(MenuFetchResult result) {
    _queue.add(result);
  }

  /// Queues a [MenuFetched] wrapping [menu].
  void queueFetched(
    Menu menu, {
    bool fromCache = false,
    MenuFetchFailureReason? staleReason,
  }) => queueResult(
    MenuFetched(menu: menu, fromCache: fromCache, staleReason: staleReason),
  );

  /// Queues a [MenuFetchFailed] for [reason], e.g. a 404 or an offline
  /// device. [statusCode] mirrors the `platformChanged` row of
  /// architecture.md §10.
  void queueFailed(MenuFetchFailureReason reason, {int? statusCode}) =>
      queueResult(MenuFetchFailed(reason: reason, statusCode: statusCode));

  @override
  bool canHandle(VenueRef ref) {
    canHandleCalls.add(ref);
    return ref.source == source;
  }

  @override
  Future<MenuFetchResult> fetch(VenueRef ref) async {
    fetchCalls.add(ref);
    if (_queue.isNotEmpty) {
      _sticky = _queue.removeAt(0);
    }
    final sticky = _sticky;
    if (sticky != null) return sticky;
    return MenuFetched(
      menu: Menu(
        venueRef: ref,
        currency: 'ILS',
        fetchedAt: defaultFetchedAt,
        categories: const <MenuCategory>[],
      ),
    );
  }
}
