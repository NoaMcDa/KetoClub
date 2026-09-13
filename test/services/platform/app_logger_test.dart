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
  });
}
