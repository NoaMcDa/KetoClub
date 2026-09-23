import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/platform/app_logger.dart';

void main() {
  group('DeveloperLogAppLogger', () {
    test('info does not throw', () {
      expect(
        () => const DeveloperLogAppLogger().info('menu fetched'),
        returnsNormally,
      );
    });

    test('warn does not throw without an error', () {
      expect(
        () => const DeveloperLogAppLogger().warn('cache read failed'),
        returnsNormally,
      );
    });

    test('warn does not throw with an error', () {
      expect(
        () => const DeveloperLogAppLogger().warn(
          'cache read failed',
          error: StateError('boom'),
        ),
        returnsNormally,
      );
    });

    test('info sends the sink a redacted message', () {
      // Arrange & Act
      final sunk = <String>[];
      DeveloperLogAppLogger(
        sink: (message, {required level, error}) {
          sunk.add(message);
        },
      ).info('header was Bearer abcdefgh-token');

      // Assert
      expect(sunk.single, isNot(contains('abcdefgh-token')));
    });

    test('warn sends the sink a redacted message and level', () {
      // Arrange & Act
      final levels = <int>[];
      DeveloperLogAppLogger(
        sink: (message, {required level, error}) {
          levels.add(level);
        },
      ).warn('cache miss');

      // Assert
      expect(levels.single, equals(900));
    });

    test('warn redacts a secret carried in the error argument', () {
      // Arrange & Act
      final sunkErrors = <String?>[];
      DeveloperLogAppLogger(
        sink: (message, {required level, error}) {
          sunkErrors.add(error?.toString());
        },
      ).warn(
        'upstream call failed',
        error: StateError('sent Bearer abc123secret in the header'),
      );

      // Assert
      expect(sunkErrors.single, isNot(contains('abc123secret')));
    });

    test('warn passes a null error through as null, not a redacted string', () {
      // Arrange & Act
      final sunkErrors = <String?>[];
      DeveloperLogAppLogger(
        sink: (message, {required level, error}) {
          sunkErrors.add(error?.toString());
        },
      ).warn('cache miss');

      // Assert
      expect(sunkErrors.single, isNull);
    });
  });

  group('redactSecrets', () {
    test('replaces every bearer value in one string', () {
      // Act
      final result = redactSecrets('first Bearer aaa111 then Bearer bbb222');

      // Assert
      expect(result, isNot(contains('aaa111')));
      expect(result, isNot(contains('bbb222')));
    });

    test('replaces a bearer header value with a placeholder', () {
      // Act
      final result = redactSecrets('Authorization: Bearer abc.123-XYZ');

      // Assert
      expect(result, isNot(contains('abc.123-XYZ')));
      expect(result, contains('[REDACTED]'));
    });

    test('matches "bearer" case-insensitively', () {
      // Act
      final result = redactSecrets('bearer abc123');

      // Assert
      expect(result, isNot(contains('abc123')));
    });

    test('leaves ordinary text untouched', () {
      // Act
      final result = redactSecrets('menu fetched for vitrina-lilinblum');

      // Assert
      expect(result, equals('menu fetched for vitrina-lilinblum'));
    });
  });
}
