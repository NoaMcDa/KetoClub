import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/failures.dart';

void main() {
  group('MenuFetchFailureReason', () {
    test('has exactly the reasons named in architecture.md §10', () {
      // Arrange
      const expectedNames = [
        'offline',
        'notFound',
        'platformChanged',
        'unsupportedSource',
      ];

      // Act
      final names = MenuFetchFailureReason.values.map((r) => r.name).toList();

      // Assert
      expect(names, equals(expectedNames));
    });
  });

  group('MenuAnalysisFailureReason', () {
    test('has exactly the reasons named in architecture.md §10', () {
      // Arrange
      const expectedNames = [
        'notConfigured',
        'offline',
        'timeout',
        'rateLimited',
        'unauthorised',
        'badResponse',
        'noDishesFound',
      ];

      // Act
      final names = MenuAnalysisFailureReason.values
          .map((r) => r.name)
          .toList();

      // Assert
      expect(names, equals(expectedNames));
    });

    test('unauthorised is distinct from every other reason', () {
      // Arrange
      const reason = MenuAnalysisFailureReason.unauthorised;

      // Act
      final others = MenuAnalysisFailureReason.values.where((r) => r != reason);

      // Assert
      expect(others, isNot(contains(reason)));
    });
  });
}
