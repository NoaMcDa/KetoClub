/// The app's own version and build number, for the About section of
/// Settings (issue #258).
library;

import 'package:flutter/foundation.dart' show immutable;
import 'package:package_info_plus/package_info_plus.dart' as plus;

/// The version and build number the running app was built with, e.g.
/// `1.0.0` and `1` for pubspec's `version: 1.0.0+1`.
@immutable
final class AppVersion {
  /// Creates a version.
  const new({required this.version, required this.buildNumber});

  /// The human-readable version, e.g. `1.0.0`.
  final String version;

  /// The build number, e.g. `1`. Empty when the platform reports none.
  final String buildNumber;

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      other.version == version &&
      other.buildNumber == buildNumber;

  @override
  int get hashCode => Object.hash(version, buildNumber);
}

/// Reads the running app's [AppVersion].
///
/// A seam, like `Clock` and `Connectivity`, so a test controls the answer
/// and `di.dart` constructs it without plugin I/O: nothing is read until
/// [load] is called, which the Settings screen does after its first frame.
abstract interface class AppInfo {
  /// The version and build number, or null when the platform cannot say.
  ///
  /// Never throws.
  Future<AppVersion?> load();
}

/// An [AppInfo] that knows nothing: [load] answers null, so Settings shows
/// no version. The default for a caller that wires no reader.
final class NoAppInfo implements AppInfo {
  /// Creates the null reader.
  const new();

  @override
  Future<AppVersion?> load() async => null;
}

/// An [AppInfo] backed by the `package_info_plus` plugin.
///
/// On web the plugin reads `version.json`, which `flutter build web`
/// writes next to the page; if that file cannot be fetched, [load] answers
/// null and Settings shows no version rather than a wrong one.
final class DeviceAppInfo implements AppInfo {
  /// Creates an app-info reader. Touches no platform channel until [load]
  /// is called, so `di.dart` may build it directly (`di.dart`'s own doc
  /// comment, "no constructor called here may perform plugin I/O").
  const new();

  @override
  Future<AppVersion?> load() async {
    try {
      final info = await plus.PackageInfo.fromPlatform();
      return AppVersion(version: info.version, buildNumber: info.buildNumber);
      // A broken plugin or a missing version.json must not break Settings.
    } on Exception {
      return null;
    }
  }
}
