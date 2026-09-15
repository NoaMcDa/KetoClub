/// Raises the screen brightness while the Waiter Card is open, so the
/// screen stays readable when the phone is handed across a table
/// (architecture.md §6.3), and restores it once the card closes.
library;

import 'package:screen_brightness/screen_brightness.dart' as plugin;

/// Raises and restores the device's screen brightness.
///
/// A hint the UI acts on, never a guarantee: some platforms (web among
/// them) cannot change brightness at all, and even where they can, the
/// underlying call can fail — no permission, no activity bound, an
/// unsupported device. Neither [raise] nor [restore] ever throws, so a
/// broken plugin degrades to "brightness unchanged", never to a broken
/// Waiter Card.
abstract interface class ScreenBrightness {
  /// Raises the screen to full brightness.
  ///
  /// Never throws.
  Future<void> raise();

  /// Restores the screen to whatever brightness it had before [raise].
  ///
  /// Never throws.
  Future<void> restore();
}

/// A [ScreenBrightness] backed by the `screen_brightness` plugin.
///
/// The plugin handle passed to the constructor is already built, not yet
/// touched: `ScreenBrightness()` (the plugin's own class) only returns its
/// singleton wrapper and never opens a platform channel, so `di.dart` may
/// construct it directly while assembling the dependency graph, exactly as
/// it does for `plus.Connectivity()` (`connectivity.dart`). Every channel
/// call happens inside [raise] and [restore], never from this constructor.
final class DeviceScreenBrightness implements ScreenBrightness {
  /// Creates a screen brightness control over the given `screen_brightness`
  /// handle.
  ///
  /// Positional and private: Dart cannot express a private named
  /// initializing formal, so the choice was positional or a suppressed
  /// lint — see `DeviceConnectivity` (`connectivity.dart`) for the same
  /// call.
  const new(this._plugin);

  final plugin.ScreenBrightness _plugin;

  @override
  Future<void> raise() async {
    try {
      await _plugin.setApplicationScreenBrightness(1);
      // A failed brightness change must never break the Waiter Card
      // (this interface's own doc comment) — swallow and carry on.
    } on Exception {
      // Deliberately ignored; see the doc comment above.
    }
  }

  @override
  Future<void> restore() async {
    try {
      await _plugin.resetApplicationScreenBrightness();
    } on Exception {
      // Deliberately ignored; see [raise].
    }
  }
}

/// A [ScreenBrightness] that does nothing, for platforms with no
/// brightness API of their own.
///
/// `screen_brightness` has no web implementation, so `di.dart` chooses this
/// over [DeviceScreenBrightness] on web with `kIsWeb`, as a deliberate
/// composition choice rather than letting a missing platform
/// implementation surface as a caught exception.
final class NoOpScreenBrightness implements ScreenBrightness {
  /// Creates a brightness control that never touches a platform channel.
  const new();

  @override
  Future<void> raise() async {}

  @override
  Future<void> restore() async {}
}
