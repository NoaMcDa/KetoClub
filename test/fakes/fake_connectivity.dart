import 'package:ketoclub/services/platform/connectivity.dart';

/// A [Connectivity] whose answer is settable, defaulting to online.
final class FakeConnectivity implements Connectivity {
  /// Creates a connectivity fake reporting [online].
  new({this.online = true});

  /// Whether [isOnline] currently reports the device as online. Settable so
  /// a test can flip it mid-scenario, exactly like `FakeClock.advance`.
  bool online;

  @override
  Future<bool> isOnline() async => online;
}
