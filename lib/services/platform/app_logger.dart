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
final class DeveloperLogAppLogger implements AppLogger {
  /// Creates a logger that writes through `dart:developer`.
  const new();

  @override
  void info(String message) {
    developer.log(message, name: _logName, level: _infoLevel);
  }

  @override
  void warn(String message, {Object? error}) {
    developer.log(message, name: _logName, level: _warnLevel, error: error);
  }
}
