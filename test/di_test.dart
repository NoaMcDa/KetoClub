import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/di.dart';
import 'package:ketoclub/state/app_dependencies.dart';

void main() {
  group('buildDependencies', () {
    test('returns an AppDependencies for the production app', () {
      // Act
      final dependencies = buildDependencies();

      // Assert
      expect(dependencies, isA<AppDependencies>());
    });
  });
}
