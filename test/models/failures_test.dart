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
        'scanNotSaved',
        'menuNotFound',
        'disallowedByRobots',
        'jsOnlyPage',
        'websiteUnreachable',
        'websiteTooLarge',
        'websiteRateLimited',
        'websitePdfUnread',
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
        'apiKeyMissing',
        'apiKeyRejected',
      ];

      // Act
      final names = MenuAnalysisFailureReason.values
          .map((r) => r.name)
          .toList();

      // Assert
      expect(names, equals(expectedNames));
    });
  });
}
