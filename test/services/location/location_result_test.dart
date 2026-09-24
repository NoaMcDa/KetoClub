import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/location/location_service.dart';

void main() {
  group('LocationFound', () {
    test('== returns true for equal positions', () {
      const a = LocationFound(
        latitude: 32.08,
        longitude: 34.78,
        accuracyMetres: 15,
      );
      const b = LocationFound(
        latitude: 32.08,
        longitude: 34.78,
        accuracyMetres: 15,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('== returns false for positions differing in latitude', () {
      const a = LocationFound(
        latitude: 32.08,
        longitude: 34.78,
        accuracyMetres: 15,
      );
      const b = LocationFound(
        latitude: 33.08,
        longitude: 34.78,
        accuracyMetres: 15,
      );

      expect(a, isNot(equals(b)));
    });

    test('== returns false for positions differing in longitude', () {
      const a = LocationFound(
        latitude: 32.08,
        longitude: 34.78,
        accuracyMetres: 15,
      );
      const b = LocationFound(
        latitude: 32.08,
        longitude: 35.78,
        accuracyMetres: 15,
      );

      expect(a, isNot(equals(b)));
    });

    test('== returns false for positions differing in accuracyMetres', () {
      const a = LocationFound(
        latitude: 32.08,
        longitude: 34.78,
        accuracyMetres: 15,
      );
      const b = LocationFound(
        latitude: 32.08,
        longitude: 34.78,
        accuracyMetres: 90,
      );

      expect(a, isNot(equals(b)));
    });

    test('toString mentions the coordinates', () {
      const result = LocationFound(
        latitude: 32.08,
        longitude: 34.78,
        accuracyMetres: 15,
      );

      expect(result.toString(), contains('32.08'));
      expect(result.toString(), contains('34.78'));
    });
  });

  group('LocationDenied', () {
    test('== returns true for equal denials', () {
      const a = LocationDenied(permanently: true);
      const b = LocationDenied(permanently: true);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('== returns false for denials differing in permanently', () {
      const a = LocationDenied(permanently: false);
      const b = LocationDenied(permanently: true);

      expect(a, isNot(equals(b)));
    });

    test('a LocationDenied never equals a LocationFound with the same '
        'field-shaped data', () {
      const denied = LocationDenied(permanently: false);
      const unavailable = LocationUnavailable(
        reason: LocationUnavailableReason.servicesOff,
      );

      expect(denied, isNot(equals(unavailable)));
    });

    test('toString mentions permanently', () {
      const result = LocationDenied(permanently: true);

      expect(result.toString(), contains('true'));
    });
  });

  group('LocationUnavailable', () {
    test('== returns true for equal results', () {
      const a = LocationUnavailable(reason: LocationUnavailableReason.timeout);
      const b = LocationUnavailable(reason: LocationUnavailableReason.timeout);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('== returns false for results differing in reason', () {
      const a = LocationUnavailable(reason: LocationUnavailableReason.timeout);
      const b = LocationUnavailable(
        reason: LocationUnavailableReason.servicesOff,
      );

      expect(a, isNot(equals(b)));
    });

    test('every LocationUnavailableReason value constructs and prints', () {
      for (final reason in LocationUnavailableReason.values) {
        final result = LocationUnavailable(reason: reason);

        expect(result.reason, equals(reason));
        expect(result.toString(), contains(reason.name));
      }
    });

    test('toString mentions the reason', () {
      const result = LocationUnavailable(
        reason: LocationUnavailableReason.unsupported,
      );

      expect(result.toString(), contains('unsupported'));
    });
  });
}
