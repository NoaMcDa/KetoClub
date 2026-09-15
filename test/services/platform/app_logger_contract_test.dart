import 'package:ketoclub/services/platform/app_logger.dart';

import '../../fakes/fake_app_logger.dart';
import 'app_logger_contract.dart';

/// The messages actually sent downstream by every [DeveloperLogAppLogger]
/// this file has built, keyed by the logger instance itself (identity),
/// so `capture` below can find the right list for a given built logger.
final Map<AppLogger, List<String>> _developerLoggerSinks =
    <AppLogger, List<String>>{};

/// Builds a [DeveloperLogAppLogger] whose sink is a capturing function
/// instead of the real `dart:developer` one, and registers its captured
/// list in [_developerLoggerSinks].
AppLogger _buildDeveloperLogAppLogger() {
  final sink = <String>[];
  final logger = DeveloperLogAppLogger(
    sink: (message, {required level, error}) {
      sink.add(message);
      if (error != null) sink.add(error.toString());
    },
  );
  _developerLoggerSinks[logger] = sink;
  return logger;
}

void main() {
  runAppLoggerSecretRedactionContract(
    'DeveloperLogAppLogger',
    _buildDeveloperLogAppLogger,
    (logger) => _developerLoggerSinks[logger]!,
  );

  runAppLoggerSecretRedactionContract(
    'FakeAppLogger',
    FakeAppLogger.new,
    (logger) => <String>[
      ...(logger as FakeAppLogger).infos,
      ...logger.warnings,
    ],
  );
}
