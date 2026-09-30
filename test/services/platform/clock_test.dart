import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/platform/clock.dart';

void main() {
  group('SystemClock', () {
    test('now returns a time within the wall clock at call time', () {
      final before = DateTime.now();

      final result = const SystemClock().now();

      final after = DateTime.now();
      expect(result.isBefore(before), isFalse);
      expect(result.isAfter(after), isFalse);
    });
  });
}
