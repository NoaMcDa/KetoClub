import 'dart:async';

import 'package:ketoclub/services/community/menu_store_client.dart';

/// A scripted [MenuStoreClient] for tests.
///
/// With nothing scripted, it stands in for a working store: a configured
/// fake answers every [upload] with `MenuStored(created: true)`, and an
/// unconfigured one (set [isConfigured] to false) with
/// [MenuStoreFailureReason.notConfigured]. Call [respondWith] to make
/// every later call return a specific [MenuStoreResult] instead. Every
/// upload is recorded in [uploads], in call order, before [gate] is
/// awaited, so a test can see an upload that is still being held.
final class FakeMenuStoreClient implements MenuStoreClient {
  /// Creates a configured fake with no scripted result.
  new();

  MenuStoreResult? _scripted;

  @override
  bool isConfigured = true;

  /// When non-null, every [upload] waits for this completer's future
  /// before it answers.
  Completer<void>? gate;

  /// Every upload this fake was asked to send, in call order.
  final List<MenuUpload> uploads = <MenuUpload>[];

  /// Makes every future [upload] call return [result] instead of the
  /// default one.
  // ignore: use_setters_to_change_properties, reads as an action.
  void respondWith(MenuStoreResult result) {
    _scripted = result;
  }

  @override
  Future<MenuStoreResult> upload(MenuUpload upload) async {
    uploads.add(upload);
    final pending = gate;
    if (pending != null) await pending.future;
    final scripted = _scripted;
    if (scripted != null) return scripted;
    if (!isConfigured) {
      return const MenuStoreFailed(
        reason: MenuStoreFailureReason.notConfigured,
      );
    }
    return const MenuStored(created: true);
  }
}
