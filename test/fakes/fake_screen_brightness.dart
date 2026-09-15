import 'package:ketoclub/services/platform/screen_brightness.dart';

/// A [ScreenBrightness] that records every call, for a test to assert on.
final class FakeScreenBrightness implements ScreenBrightness {
  /// How many times [raise] has been called.
  int raiseCount = 0;

  /// How many times [restore] has been called.
  int restoreCount = 0;

  @override
  Future<void> raise() async {
    raiseCount++;
  }

  @override
  Future<void> restore() async {
    restoreCount++;
  }
}
