import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/backend/backend_menu_adapter.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';

/// One [MenuSource] read through KetoClub's backend first and the device's
/// own adapter second (architecture.md D25, issue #327).
///
/// The backend is an accelerator, never a dependency (D11): [primary] is
/// normally a [BackendMenuAdapter], which answers with the menu and its
/// analysis in one request, and [fallback] the adapter the app used before
/// it — Wolt, 10bis or the website reader. [fetch]:
///
/// 1. asks [primary] when it can handle the ref (a build with no backend
///    URL has a primary that handles nothing, and goes straight to 2);
/// 2. asks [fallback] when the primary could not handle the ref, or failed
///    with a reason [shouldFallBack] accepts;
/// 3. returns the primary's failure when the fallback fails too, since
///    that failure was the first and better explanation — unless the
///    primary never handled the ref, when the fallback's is the only one.
///
/// Never throws: both adapters promise not to.
final class FallbackMenuAdapter implements PlatformMenuAdapter {
  /// Creates an adapter trying [primary], then [fallback], for one
  /// source. [shouldFallBack] decides which primary failures are worth a
  /// second try; it defaults to [BackendMenuAdapter.shouldFallBack].
  new({
    required this.primary,
    required this.fallback,
    this.shouldFallBack = BackendMenuAdapter.shouldFallBack,
  });

  /// The adapter asked first.
  final PlatformMenuAdapter primary;

  /// The adapter asked when [primary] cannot handle a ref or fails with a
  /// reason [shouldFallBack] accepts. Its [source] is this adapter's.
  final PlatformMenuAdapter fallback;

  /// Whether a primary failure for this reason is worth asking [fallback].
  final bool Function(MenuFetchFailureReason reason) shouldFallBack;

  @override
  MenuSource get source => fallback.source;

  @override
  bool canHandle(VenueRef ref) =>
      ref.source == source &&
      (primary.canHandle(ref) || fallback.canHandle(ref));

  @override
  Future<MenuFetchResult> fetch(VenueRef ref) async {
    if (!primary.canHandle(ref) || ref.source != source) {
      return await fallback.fetch(ref);
    }
    final first = await primary.fetch(ref);
    if (first is! MenuFetchFailed || !shouldFallBack(first.reason)) {
      return first;
    }
    if (!fallback.canHandle(ref)) return first;
    final second = await fallback.fetch(ref);
    return second is MenuFetched ? second : first;
  }
}
