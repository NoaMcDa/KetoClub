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
/// 1. asks [primary] when it can handle the ref and [usePrimary] allows it
///    (a build with no backend URL has a primary that handles nothing, and
///    goes straight to 2);
/// 2. asks [fallback] when the primary could not handle the ref, was not
///    allowed, or failed with a reason [shouldFallBack] accepts;
/// 3. returns the primary's failure when the fallback fails too, since
///    that failure was the first and better explanation — unless the
///    primary never handled the ref, when the fallback's is the only one.
///
/// Never throws: both adapters promise not to, and [usePrimary] must not
/// either.
final class FallbackMenuAdapter implements PlatformMenuAdapter {
  /// Creates an adapter trying [primary], then [fallback], for one
  /// source. [shouldFallBack] decides which primary failures are worth a
  /// second try; it defaults to [BackendMenuAdapter.shouldFallBack].
  /// [usePrimary] is asked once per [fetch] whether [primary] may be asked
  /// at all; it defaults to always.
  new({
    required this.primary,
    required this.fallback,
    this.shouldFallBack = BackendMenuAdapter.shouldFallBack,
    this.usePrimary = _always,
  });

  /// The adapter asked first.
  final PlatformMenuAdapter primary;

  /// The adapter asked when [primary] cannot handle a ref or fails with a
  /// reason [shouldFallBack] accepts. Its [source] is this adapter's.
  final PlatformMenuAdapter fallback;

  /// Whether a primary failure for this reason is worth asking [fallback].
  final bool Function(MenuFetchFailureReason reason) shouldFallBack;

  /// Whether [primary] may be asked for this fetch; when it answers false,
  /// the fetch is [fallback]'s alone, as if the primary could not handle
  /// the ref.
  ///
  /// `di.dart` passes the user's AI-analysis consent (architecture.md
  /// D25, §11): the backend's menu routes analyse the menu they read, and
  /// calling one is the consent, so without it the device reads the menu
  /// its own way and nothing is analysed off the device.
  final Future<bool> Function() usePrimary;

  static Future<bool> _always() async => true;

  @override
  MenuSource get source => fallback.source;

  @override
  bool canHandle(VenueRef ref) =>
      ref.source == source &&
      (primary.canHandle(ref) || fallback.canHandle(ref));

  @override
  Future<MenuFetchResult> fetch(VenueRef ref) async {
    if (!primary.canHandle(ref) ||
        ref.source != source ||
        !await usePrimary()) {
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
