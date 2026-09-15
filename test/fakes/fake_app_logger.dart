import 'package:ketoclub/services/platform/app_logger.dart';

/// An [AppLogger] that records every call in memory instead of logging.
///
/// [info] and [warn] messages are passed through [redactSecrets] before
/// being recorded into [infos]/[warnings], the same redaction
/// [DeveloperLogAppLogger] applies before its own sink — so a test can
/// assert on this fake exactly as it would on the real logger's output.
/// [warningErrors] is the one exception: it keeps the raw `error` object
/// a caller passed, unredacted, because tests elsewhere assert on its
/// identity (e.g. "the exact exception that was thrown"); it is not
/// something a real sink would render as-is either.
final class FakeAppLogger implements AppLogger {
  /// Creates a logger with nothing recorded yet.
  new();

  /// Every message passed to [info], in call order, redacted.
  final List<String> infos = <String>[];

  /// Every message passed to [warn], in call order, redacted.
  final List<String> warnings = <String>[];

  /// The `error` argument of every [warn] call, in call order, `null` for
  /// a call that passed none. Parallel to [warnings]. Recorded verbatim,
  /// not redacted — see the class doc comment.
  final List<Object?> warningErrors = <Object?>[];

  @override
  void info(String message) {
    infos.add(redactSecrets(message));
  }

  @override
  void warn(String message, {Object? error}) {
    warnings.add(redactSecrets(message));
    warningErrors.add(error);
  }
}
