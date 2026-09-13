import 'package:ketoclub/services/platform/app_logger.dart';

/// An [AppLogger] that records every call in memory instead of logging.
final class FakeAppLogger implements AppLogger {
  /// Creates a logger with nothing recorded yet.
  new();

  /// Every message passed to [info], in call order.
  final List<String> infos = <String>[];

  /// Every message passed to [warn], in call order.
  final List<String> warnings = <String>[];

  /// The `error` argument of every [warn] call, in call order, `null` for
  /// a call that passed none. Parallel to [warnings].
  final List<Object?> warningErrors = <Object?>[];

  @override
  void info(String message) {
    infos.add(message);
  }

  @override
  void warn(String message, {Object? error}) {
    warnings.add(message);
    warningErrors.add(error);
  }
}
