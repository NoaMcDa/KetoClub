import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/state/venue_search_controller.dart';

void main() {
  group('VenueSearchController', () {
    late VenueSearchController controller;

    setUp(() {
      controller = VenueSearchController();
    });

    test('setInput with a Wolt url resolves to a wolt VenueRef', () {
      // Arrange
      const url = 'https://wolt.com/en/isr/tel-aviv/restaurant/vitrina';

      // Act
      controller.setInput(url);

      // Assert
      expect(
        controller.resolved,
        const VenueRef(source: MenuSource.wolt, platformId: 'vitrina'),
      );
      expect(controller.isInvalid, isFalse);
    });

    test('setInput with a bare slug resolves to MenuSource.wolt', () {
      // Arrange
      const slug = 'vitrina-lilinblum';

      // Act
      controller.setInput(slug);

      // Assert
      expect(controller.resolved?.source, MenuSource.wolt);
      expect(controller.resolved?.platformId, slug);
    });

    test('setInput with a numeric id resolves to MenuSource.tenbis', () {
      // Arrange
      const id = '123456';

      // Act
      controller.setInput(id);

      // Assert
      expect(controller.resolved?.source, MenuSource.tenbis);
      expect(controller.resolved?.platformId, id);
    });

    test('setInput with nonsense sets isInvalid true', () {
      // Arrange
      const nonsense = 'https://example.com/not/a/venue';

      // Act
      controller.setInput(nonsense);

      // Assert
      expect(controller.resolved, isNull);
      expect(controller.isInvalid, isTrue);
    });

    test('setInput with empty input is neither resolved nor invalid', () {
      // Act
      controller.setInput('');

      // Assert
      expect(controller.resolved, isNull);
      expect(controller.isInvalid, isFalse);
      expect(controller.input, '');
    });

    test('setInput notifies listeners exactly once per call', () {
      // Arrange
      var notifyCount = 0;

      // Act
      controller
        ..addListener(() => notifyCount++)
        ..setInput('vitrina-lilinblum')
        ..setInput('123456')
        ..setInput('');

      // Assert
      expect(notifyCount, 3);
    });
  });
}
