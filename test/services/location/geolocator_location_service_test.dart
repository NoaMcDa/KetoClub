import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:ketoclub/services/location/geolocator_location_service.dart';
import 'package:ketoclub/services/location/location_service.dart';

import '../../fakes/fake_location_service.dart';

/// A working position, returned by [_buildService]'s default
/// `getCurrentPosition` stub.
final geo.Position _samplePosition = geo.Position(
  latitude: 32.08,
  longitude: 34.78,
  timestamp: DateTime.utc(2026),
  accuracy: 12,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

Future<bool> _enabled() async => true;
Future<bool> _disabled() async => false;
Future<geo.LocationPermission> _whileInUse() async =>
    geo.LocationPermission.whileInUse;
Future<geo.LocationPermission> _denied() async => geo.LocationPermission.denied;

/// Fails the test if called: used to prove [GeolocatorLocationService]
/// does not call `requestPermission` when `checkPermission` already
/// answered `deniedForever`.
Future<geo.LocationPermission> _mustNotBeCalled() async {
  fail('requestPermission must not be called here');
}

/// Builds a service whose geolocator seam is entirely stubbed — no
/// argument reaches the real plugin.
GeolocatorLocationService _buildService({
  bool runsInBrowser = false,
  Future<bool> Function() isLocationServiceEnabled = _enabled,
  Future<geo.LocationPermission> Function() checkPermission = _whileInUse,
  Future<geo.LocationPermission> Function()? requestPermission,
  Future<geo.Position> Function({geo.LocationSettings? locationSettings})?
  getCurrentPosition,
  Future<bool> Function()? openAppSettings,
  Future<bool> Function()? openLocationSettings,
}) => GeolocatorLocationService(
  runsInBrowser: runsInBrowser,
  isLocationServiceEnabled: isLocationServiceEnabled,
  checkPermission: checkPermission,
  requestPermission: requestPermission ?? _whileInUse,
  getCurrentPosition:
      getCurrentPosition ?? ({locationSettings}) async => _samplePosition,
  openAppSettings: openAppSettings ?? () async => true,
  openLocationSettings: openLocationSettings ?? () async => true,
);

void main() {
  group('GeolocatorLocationService', () {
    test('runsInBrowser defaults to kIsWeb — false on the test VM', () {
      final service = GeolocatorLocationService(
        isLocationServiceEnabled: _enabled,
        checkPermission: _whileInUse,
        requestPermission: _whileInUse,
        getCurrentPosition: ({locationSettings}) async => _samplePosition,
      );

      expect(service.runsInBrowser, isFalse);
    });

    test(
      'current returns servicesOff when the location service is off',
      () async {
        // Arrange
        final service = _buildService(isLocationServiceEnabled: _disabled);

        // Act
        final result = await service.current();

        // Assert
        expect(
          result,
          equals(
            const LocationUnavailable(
              reason: LocationUnavailableReason.servicesOff,
            ),
          ),
        );
      },
    );

    test('current returns LocationDenied(permanently: false) when the user '
        'refuses both the check and the re-request', () async {
      // Arrange
      final service = _buildService(
        checkPermission: _denied,
        requestPermission: _denied,
      );

      // Act
      final result = await service.current();

      // Assert
      expect(result, equals(const LocationDenied(permanently: false)));
    });

    test('current re-requests once on an initial denial and proceeds when '
        'the re-request is granted', () async {
      // Arrange
      var requestCalls = 0;
      final service = _buildService(
        checkPermission: _denied,
        requestPermission: () async {
          requestCalls++;
          return geo.LocationPermission.whileInUse;
        },
      );

      // Act
      final result = await service.current();

      // Assert
      expect(requestCalls, equals(1));
      expect(
        result,
        equals(
          LocationFound(
            latitude: _samplePosition.latitude,
            longitude: _samplePosition.longitude,
            accuracyMetres: _samplePosition.accuracy,
          ),
        ),
      );
    });

    test('current returns LocationDenied(permanently: true) for '
        'deniedForever without ever calling requestPermission', () async {
      // Arrange
      final service = _buildService(
        checkPermission: () async => geo.LocationPermission.deniedForever,
        requestPermission: _mustNotBeCalled,
      );

      // Act
      final result = await service.current();

      // Assert
      expect(result, equals(const LocationDenied(permanently: true)));
    });

    test('current returns unsupported when the permission cannot be '
        'determined', () async {
      // Arrange
      final service = _buildService(
        checkPermission: () async => geo.LocationPermission.unableToDetermine,
      );

      // Act
      final result = await service.current();

      // Assert
      expect(
        result,
        equals(
          const LocationUnavailable(
            reason: LocationUnavailableReason.unsupported,
          ),
        ),
      );
    });

    test('current returns a LocationFound mapped from the plugin position '
        'when permission is whileInUse', () async {
      // Arrange: whileInUse is _buildService's own default.
      final service = _buildService();

      // Act
      final result = await service.current();

      // Assert
      expect(
        result,
        equals(
          LocationFound(
            latitude: _samplePosition.latitude,
            longitude: _samplePosition.longitude,
            accuracyMetres: _samplePosition.accuracy,
          ),
        ),
      );
    });

    test(
      'current also proceeds to a position when permission is always',
      () async {
        // Arrange
        final service = _buildService(
          checkPermission: () async => geo.LocationPermission.always,
        );

        // Act
        final result = await service.current();

        // Assert
        expect(result, isA<LocationFound>());
      },
    );

    test(
      'current requests medium accuracy with a 10 second time limit',
      () async {
        // Arrange
        geo.LocationSettings? captured;
        final service = _buildService(
          getCurrentPosition: ({locationSettings}) async {
            captured = locationSettings;
            return _samplePosition;
          },
        );

        // Act
        await service.current();

        // Assert
        expect(captured, isNotNull);
        expect(captured!.accuracy, equals(geo.LocationAccuracy.medium));
        expect(captured!.timeLimit, equals(const Duration(seconds: 10)));
      },
    );

    test('current returns timeout when getCurrentPosition times out', () async {
      // Arrange
      final service = _buildService(
        getCurrentPosition: ({locationSettings}) =>
            Future<geo.Position>.error(TimeoutException('too slow')),
      );

      // Act
      final result = await service.current();

      // Assert
      expect(
        result,
        equals(
          const LocationUnavailable(reason: LocationUnavailableReason.timeout),
        ),
      );
    });

    test('current returns unsupported — never throws — for an unexpected '
        'plugin exception from getCurrentPosition', () async {
      // Arrange
      final service = _buildService(
        getCurrentPosition: ({locationSettings}) => Future<geo.Position>.error(
          const geo.LocationServiceDisabledException(),
        ),
      );

      // Act
      final result = await service.current();

      // Assert
      expect(
        result,
        equals(
          const LocationUnavailable(
            reason: LocationUnavailableReason.unsupported,
          ),
        ),
      );
    });

    test('current returns unsupported — never throws — when '
        'isLocationServiceEnabled itself throws', () async {
      // Arrange
      final service = _buildService(
        isLocationServiceEnabled: () =>
            Future<bool>.error(Exception('channel gone')),
      );

      // Act
      final result = await service.current();

      // Assert
      expect(
        result,
        equals(
          const LocationUnavailable(
            reason: LocationUnavailableReason.unsupported,
          ),
        ),
      );
    });

    test('current never throws regardless of what the seam does', () async {
      // Arrange
      final service = _buildService(
        checkPermission: () =>
            Future<geo.LocationPermission>.error(Exception('boom')),
      );

      // Act & Assert
      await expectLater(service.current(), completes);
    });

    test('current maps a denial to LocationDenied(permanently: false) '
        'when runsInBrowser is true, matching an insecure-context refusal '
        'the web plugin cannot distinguish from an ordinary one', () async {
      // Arrange
      final service = _buildService(
        runsInBrowser: true,
        checkPermission: _denied,
        requestPermission: _denied,
      );

      // Act
      final result = await service.current();

      // Assert
      expect(result, equals(const LocationDenied(permanently: false)));
    });
  });

  group('GeolocatorLocationService.openSettings', () {
    test(
      'returns false without calling the plugin when runsInBrowser',
      () async {
        // Arrange
        var calls = 0;
        final service = _buildService(
          runsInBrowser: true,
          openAppSettings: () async {
            calls++;
            return true;
          },
          openLocationSettings: () async {
            calls++;
            return true;
          },
        );

        // Act
        final opened = await service.openSettings(servicesOff: false);

        // Assert
        expect(opened, isFalse);
        expect(calls, 0);
      },
    );

    test(
      'calls openAppSettings for a permanent denial (servicesOff: false)',
      () async {
        // Arrange
        var appSettingsCalls = 0;
        var locationSettingsCalls = 0;
        final service = _buildService(
          openAppSettings: () async {
            appSettingsCalls++;
            return true;
          },
          openLocationSettings: () async {
            locationSettingsCalls++;
            return true;
          },
        );

        // Act
        final opened = await service.openSettings(servicesOff: false);

        // Assert
        expect(opened, isTrue);
        expect(appSettingsCalls, 1);
        expect(locationSettingsCalls, 0);
      },
    );

    test('calls openLocationSettings for servicesOff: true', () async {
      // Arrange
      var appSettingsCalls = 0;
      var locationSettingsCalls = 0;
      final service = _buildService(
        openAppSettings: () async {
          appSettingsCalls++;
          return true;
        },
        openLocationSettings: () async {
          locationSettingsCalls++;
          return true;
        },
      );

      // Act
      final opened = await service.openSettings(servicesOff: true);

      // Assert
      expect(opened, isTrue);
      expect(appSettingsCalls, 0);
      expect(locationSettingsCalls, 1);
    });

    test(
      'returns false — never throws — when the plugin call throws',
      () async {
        // Arrange
        final service = _buildService(
          openAppSettings: () => Future<bool>.error(Exception('channel gone')),
        );

        // Act
        final opened = await service.openSettings(servicesOff: false);

        // Assert
        expect(opened, isFalse);
      },
    );
  });

  group('FakeLocationService', () {
    test('current defaults to a plausible found position', () async {
      final service = FakeLocationService();

      expect(await service.current(), isA<LocationFound>());
    });

    test('current returns the scripted result', () async {
      final service = FakeLocationService(
        result: const LocationDenied(permanently: true),
      );

      expect(
        await service.current(),
        equals(const LocationDenied(permanently: true)),
      );
    });

    test('current reflects result being changed after construction', () async {
      final service = FakeLocationService()
        ..result = const LocationUnavailable(
          reason: LocationUnavailableReason.servicesOff,
        );

      expect(
        await service.current(),
        equals(
          const LocationUnavailable(
            reason: LocationUnavailableReason.servicesOff,
          ),
        ),
      );
    });

    test('current increments currentCallCount on every call', () async {
      final service = FakeLocationService();

      await service.current();
      await service.current();

      expect(service.currentCallCount, equals(2));
    });

    test('openSettings defaults to true and records the servicesOff '
        'argument', () async {
      final service = FakeLocationService();

      final opened = await service.openSettings(servicesOff: true);

      expect(opened, isTrue);
      expect(service.openSettingsCalls, [true]);
    });

    test('openSettings returns the scripted result', () async {
      final service = FakeLocationService()..openSettingsResult = false;

      expect(await service.openSettings(servicesOff: false), isFalse);
    });
  });
}
