/// The one place the `BANTO_MODE` compile-time flag is read.
///
/// Build with `--dart-define=BANTO_MODE=true` to turn Banto surfaces on
/// (`architecture.md` D26). Without the define the app is KetoClub byte for
/// byte: [enabled] is a compile-time `false`, so every branch gated on it is
/// tree-shaken away.
///
/// **Convention.** Nothing outside this file reads `bool.fromEnvironment`
/// for the flag, and a gated widget or function does not read [enabled] in
/// its body either. It takes `bool bantoMode = BantoMode.enabled` as a
/// parameter, the `backendBaseUrl(configured)` precedent in `lib/di.dart`, so
/// a test exercises both branches with no `--dart-define`.
///
/// Lives in `utils/` (layer rank 1) so widgets and `app.dart` can import it,
/// and so it imports nothing above `utils/` (in fact, nothing at all).
abstract final class BantoMode {
  /// Whether this build was compiled with `--dart-define=BANTO_MODE=true`.
  static const bool enabled = bool.fromEnvironment('BANTO_MODE');

  /// The app's *display* name: `Banto` when [enabled], `KetoClub` otherwise.
  ///
  /// Used for the window and task-switcher title only. The `appName` constant
  /// in `constants.dart` is untouched and still names the product elsewhere.
  static const String appName = enabled ? 'Banto' : 'KetoClub';
}
