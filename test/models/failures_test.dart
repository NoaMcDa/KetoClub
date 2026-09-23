import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/failures.dart';

void main() {
  group('MenuFetchFailureReason', () {
    test('has exactly the reasons named in architecture.md §10', () {
      // Arrange
      const expectedNames = [
        'offline',
        'blockedByBrowser',
        'notFound',
        'platformChanged',
        'unsupportedSource',
        'backendUnreachable',
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
        'badResponse',
        'noDishesFound',
        'backendUnreachable',
        'consentWithheld',
      ];

      // Act
      final names = MenuAnalysisFailureReason.values
          .map((r) => r.name)
          .toList();

      // Assert
      expect(names, equals(expectedNames));
    });

    test('consentWithheld is distinct from notConfigured', () {
      // Arrange: the user can fix one in Settings; the other is the build's
      // or the server's, so the two must never collapse into one reason.
      const reason = MenuAnalysisFailureReason.consentWithheld;

      // Act & Assert
      expect(reason, isNot(equals(MenuAnalysisFailureReason.notConfigured)));
      expect(reason.name, isNot(equals('notConfigured')));
    });
  });
}
