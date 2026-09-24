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

  /// When non-null, every [current] call waits for this future before it
  /// answers — the same shape `FakeMenuClassifier.gate` uses, so a test
  /// can look at the screen while a locate is still in flight (issue
  /// #63).
  Future<void>? gate;

  @override
  Future<LocationResult> current() async {
    currentCallCount++;
    final pending = gate;
    if (pending != null) await pending;
    return result;
  }
}
