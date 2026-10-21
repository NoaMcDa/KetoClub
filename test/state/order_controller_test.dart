// "My order" (Banto, issue #418): dish ids per menu, in the order added,
// in memory only.

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/state/order_controller.dart';

const VenueRef _a = VenueRef(source: MenuSource.wolt, platformId: 'a');
const VenueRef _b = VenueRef(source: MenuSource.tenbis, platformId: 'b');

void main() {
  group('OrderController', () {
    test('toggle adds in the order added, and a second toggle removes', () {
      // Arrange
      var notified = 0;
      final order = OrderController()
        ..addListener(() => notified++)
        // Act
        ..toggle(_a, 'd2')
        ..toggle(_a, 'd1');

      // Assert
      expect(order.dishIdsFor(_a), <String>['d2', 'd1']);
      expect(order.contains(_a, 'd1'), isTrue);

      // Act
      order.toggle(_a, 'd2');

      // Assert
      expect(order.dishIdsFor(_a), <String>['d1']);
      expect(order.contains(_a, 'd2'), isFalse);
      expect(notified, 3);
    });

    test('each menu keeps its own order', () {
      // Arrange
      final order = OrderController()
        ..toggle(_a, 'd1')
        ..toggle(_b, 'x')
        // Act
        ..clear(_b);

      // Assert
      expect(order.dishIdsFor(_a), <String>['d1']);
      expect(order.dishIdsFor(_b), isEmpty);
    });

    test('remove and clear are no-ops, and do not notify, when there is '
        'nothing to remove', () {
      // Arrange
      var notified = 0;
      final order = OrderController()
        ..toggle(_a, 'd1')
        ..addListener(() => notified++)
        // Act
        ..remove(_a, 'nope')
        ..clear(_b)
        ..remove(_a, 'd1')
        ..remove(_a, 'd1')
        ..clear(_a);

      // Assert
      expect(order.dishIdsFor(_a), isEmpty);
      expect(notified, 1);
    });

    test('the ids handed out cannot change the order', () {
      // Arrange
      final order = OrderController()..toggle(_a, 'd1');

      // Act / Assert
      expect(() => order.dishIdsFor(_a).add('d2'), throwsUnsupportedError);
    });
  });
}
