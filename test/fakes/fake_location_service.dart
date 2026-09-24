import 'package:ketoclub/services/location/location_service.dart';

/// A [LocationService] whose answer is settable, defaulting to a plausible
/// found position.
final class FakeLocationService implements LocationService {
  /// Creates a location fake reporting [result].
  new({
    this.result = const LocationFound(
      latitude: 32.0809,
      longitude: 34.7806,
      accuracyMetres: 20,
    ),
  });

  /// The result [current] answers with. Settable so a test can flip it
  /// mid-scenario, exactly like `FakeConnectivity.online`.
  LocationResult result;

  /// How many times [current] has been called.
  int currentCallCount = 0;

  @override
  Future<LocationResult> current() async {
    currentCallCount++;
    return result;
  }
}
