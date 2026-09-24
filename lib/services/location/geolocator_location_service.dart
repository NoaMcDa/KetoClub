import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:ketoclub/services/location/location_service.dart';

/// The only accuracy [GeolocatorLocationService] ever requests
/// (architecture.md §6.5): a device that can only grant Android 12+'s
/// *approximate* permission still answers this rather than being
/// re-prompted for something more precise than it was allowed to give.
const geo.LocationAccuracy _requestedAccuracy = geo.LocationAccuracy.medium;

/// How long [GeolocatorLocationService.current] waits for a position
/// before giving up (architecture.md §6.5).
const Duration _positionTimeLimit = Duration(seconds: 10);

/// A [LocationService] backed by the `geolocator` plugin.
///
/// This is the only file under lib/ that may import `package:geolocator`
/// (`test/architecture/import_rules_test.dart`). Every geolocator call is
/// reached through a function-typed seam passed to the constructor —
/// [isLocationServiceEnabled], [checkPermission], [requestPermission] and
/// [getCurrentPosition] — so a unit test can drive every branch of
/// [current] without ever touching the real plugin or a platform channel.
/// Each defaults to the matching `geo.Geolocator` static method (see the
/// constructor's own doc comment), so `di.dart` builds this service with
/// no arguments at all and never needs its own import of the plugin.
///
/// **Web caveat.** The browser Geolocation API needs a secure context —
/// `https://` or `localhost` — and answers a plain `http://` origin with
/// `LocationPermission.denied` before ever showing a prompt, which looks
/// exactly like an ordinary user refusal from here: there is no way to
/// tell the two apart through this plugin's web implementation, so both
/// map to [LocationDenied] with `permanently: false`
/// ([LocationUnavailableReason.insecureContext] exists on the model for
/// documentation, but this class never produces it).
///
/// [current] never calls `getLastKnownPosition`, `openAppSettings` or
/// `openLocationSettings`: none of them is needed to read one position,
/// and all three throw on web. [runsInBrowser] is kept on this class for
/// whichever later caller — the "open Settings" affordance on a permanent
/// denial (issue #40) is the likely one — adds a call to one of them and
/// needs to gate it there.
final class GeolocatorLocationService implements LocationService {
  /// Creates a location service over the given geolocator seam.
  ///
  /// Every parameter defaults to the real `geo.Geolocator` static method
  /// of the same name — assigning a static method tear-off as a default
  /// value is not a call, so building this service still performs no
  /// plugin I/O (`di.dart` constructs it with no arguments at all).
  /// A test passes its own closures instead, to drive every branch of
  /// [current] without the plugin. [runsInBrowser] defaults to [kIsWeb]
  /// and exists so a test can exercise both the browser and the native
  /// path on one platform.
  new({
    this.runsInBrowser = kIsWeb,
    this.isLocationServiceEnabled = geo.Geolocator.isLocationServiceEnabled,
    this.checkPermission = geo.Geolocator.checkPermission,
    this.requestPermission = geo.Geolocator.requestPermission,
    this.getCurrentPosition = geo.Geolocator.getCurrentPosition,
  });

  /// Whether this instance runs in a browser (defaults to [kIsWeb]).
  final bool runsInBrowser;

  /// Reads whether the device's location service is currently enabled.
  final Future<bool> Function() isLocationServiceEnabled;

  /// Reads the app's current location permission.
  final Future<geo.LocationPermission> Function() checkPermission;

  /// Prompts for location permission.
  final Future<geo.LocationPermission> Function() requestPermission;

  /// Reads one position.
  final Future<geo.Position> Function({geo.LocationSettings? locationSettings})
  getCurrentPosition;

  @override
  Future<LocationResult> current() async {
    try {
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const LocationUnavailable(
          reason: LocationUnavailableReason.servicesOff,
        );
      }

      var permission = await checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await requestPermission();
      }

      switch (permission) {
        case geo.LocationPermission.denied:
          // Also what a browser on an insecure origin reports, with no
          // prompt ever shown — see this class's own doc comment.
          return const LocationDenied(permanently: false);
        case geo.LocationPermission.deniedForever:
          return const LocationDenied(permanently: true);
        case geo.LocationPermission.unableToDetermine:
          return const LocationUnavailable(
            reason: LocationUnavailableReason.unsupported,
          );
        case geo.LocationPermission.whileInUse:
        case geo.LocationPermission.always:
          break;
      }

      final position = await getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: _requestedAccuracy,
          timeLimit: _positionTimeLimit,
        ),
      );
      return LocationFound(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMetres: position.accuracy,
      );
      // A TimeoutException also implements Exception, so it must be
      // caught first to be reported as `timeout` rather than falling
      // through to the generic `unsupported` clause below.
    } on TimeoutException {
      return const LocationUnavailable(
        reason: LocationUnavailableReason.timeout,
      );
      // `services/` may import neither `dart:io` nor
      // `package:flutter/services.dart` (architecture.md §5), so
      // geolocator's platform exceptions — all of which implement
      // `Exception`, never named individually — are caught broadly here
      // to keep [current]'s own promise that it never throws.
    } on Exception {
      return const LocationUnavailable(
        reason: LocationUnavailableReason.unsupported,
      );
    }
  }
}
