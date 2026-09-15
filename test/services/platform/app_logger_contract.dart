import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/platform/app_logger.dart';

/// One secret-bearing message every [AppLogger] implementation must
/// never let through unredacted, paired with the exact substring that
/// must never appear in what [runAppLoggerSecretRedactionContract]'s
/// `capture` reads back.
class _Case {
  const new(this.description, this.message, this.secret);

  final String description;
  final String message;
  final String secret;
}

const List<_Case> _cases = <_Case>[
  _Case(
    'an OpenRouter key',
    'request failed with key sk-or-v1-abcdefghijklmnop in the header',
    'sk-or-v1-abcdefghijklmnop',
  ),
  _Case(
    'a bearer header value',
    'sent header Authorization: Bearer abc123XYZ.token-value',
    'Bearer abc123XYZ.token-value',
  ),
];

/// Asserts the secret-redaction contract every [AppLogger] implementation
/// must uphold (issue #7, architecture.md §11 and §18.3): a message
/// containing an OpenRouter key or a bearer header value must never let
/// that secret reach wherever the implementation actually sends its
/// output.
///
/// [build] returns a fresh logger. [capture] reads back every string
/// that logger has, by the time it is called, actually sent downstream
/// — a fake's own recorded list, or a test double standing in for a real
/// sink — so this checks the contract on what leaves the logger, not on
/// what happens to be true of one implementation's internals.
void runAppLoggerSecretRedactionContract(
  String name,
  AppLogger Function() build,
  List<String> Function(AppLogger logger) capture,
) {
  group('$name (AppLogger secret-redaction contract)', () {
    for (final case_ in _cases) {
      test('info never lets ${case_.description} reach the log', () {
        // Arrange & Act
        final logger = build()..info(case_.message);

        // Assert
        for (final sunk in capture(logger)) {
          expect(sunk, isNot(contains(case_.secret)));
        }
      });

      test('warn never lets ${case_.description} reach the log', () {
        // Arrange & Act
        final logger = build()..warn(case_.message);

        // Assert
        for (final sunk in capture(logger)) {
          expect(sunk, isNot(contains(case_.secret)));
        }
      });
    }
  });
}
