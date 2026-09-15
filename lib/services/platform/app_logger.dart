import 'dart:developer' as developer;

/// The `dart:developer` log level for [AppLogger.info] messages, matching
/// the conventional "informational" severity.
const int _infoLevel = 800;

/// The `dart:developer` log level for [AppLogger.warn] messages, matching
/// the conventional "warning" severity.
const int _warnLevel = 900;

/// The name every log record is tagged with, so KetoClub's own log lines
/// are easy to filter out of plugin noise.
const String _logName = 'ketoclub';

/// Matches an OpenRouter key wherever one appears in a string, e.g.
/// inside an upstream error message that echoed the request header back.
final RegExp _openRouterKeyPattern = RegExp('sk-or-[A-Za-z0-9._-]+');

/// Matches a bearer/authorization header value wherever one appears in
/// a string, case-insensitively (`bearer` and `Bearer` both occur across
/// the platform APIs this app talks to).
final RegExp _bearerTokenPattern = RegExp(
  r'Bearer\s+\S+',
  caseSensitive: false,
);

/// Replaces anything in [text] that looks like an OpenRouter key
/// (`sk-or-...`) or a bearer header value (`Bearer ...`) with a fixed
/// placeholder; everything else is returned unchanged.
///
/// Pure, and the one function either [AppLogger] implementation in this
/// file may route caller-supplied text through before it reaches a real
/// sink. This is the backstop for architecture.md §11 and §18.3's rule
/// that the OpenRouter key must never reach a log: `OpenRouterClient` is
/// the key's only reader and is not expected to log it, but a future
/// caller logging a raw upstream error message (which can echo a
/// request's own headers back) must not leak it either.
String redactSecrets(String text) => text
    .replaceAll(_openRouterKeyPattern, '[REDACTED]')
    .replaceAll(_bearerTokenPattern, '[REDACTED]');

/// The shape `dart:developer`'s `log` is called through in
/// [DeveloperLogAppLogger], factored out so a test can inject a capture
/// function and observe exactly what reaches the sink after redaction,
/// without depending on the VM service stream `log` actually writes to.
typedef LogSink = void Function(
  String message, {
  required int level,
  Object? error,
});

/// The default [LogSink]: `dart:developer`'s own `log`, tagged with
/// [_logName].
void _developerLogSink(String message, {required int level, Object? error}) {
  developer.log(message, name: _logName, level: level, error: error);
}

/// Structured logging through one seam (architecture.md §18.3): nothing
/// in `services/` calls `print`, and nothing logged here may include the
/// OpenRouter key, a bearer header, or an upstream response body.
abstract interface class AppLogger {
  /// Logs a routine informational message.
  ///
  /// Never throws.
  void info(String message);

  /// Logs a warning, optionally naming the [error] that caused it.
  ///
  /// Never throws.
  void warn(String message, {Object? error});
}

/// An [AppLogger] backed by `dart:developer`'s `log`.
///
/// Every `message` and every `warn` `error` is passed through
/// [redactSecrets] before it reaches [sink], so a secret already
/// embedded in either — for example an upstream error message that
/// echoed a request's own `Authorization` header back — cannot reach
/// the device log through this seam.
final class DeveloperLogAppLogger implements AppLogger {
  /// Creates a logger that writes through [sink], `dart:developer`'s own
  /// `log` by default. Tests inject a capturing [sink] to assert on the
  /// exact, post-redaction message this logger sends downstream.
  const new({this.sink = _developerLogSink});

  /// Where a redacted message is actually sent.
  final LogSink sink;

  @override
  void info(String message) {
    sink(redactSecrets(message), level: _infoLevel);
  }

  @override
  void warn(String message, {Object? error}) {
    sink(
      redactSecrets(message),
      level: _warnLevel,
      error: error == null ? null : redactSecrets(error.toString()),
    );
  }
}
