/// Device position for nearby search (architecture.md §6.5, issue #37):
/// request permission, read one position, and degrade to a manual "type an
/// address or a venue name" search on denial or on web without HTTPS.
library;

import 'package:flutter/foundation.dart';

/// Why a [LocationService.current] call produced a [LocationUnavailable]
/// result rather than a position or a [LocationDenied] refusal.
enum LocationUnavailableReason {
  /// The device's location service (the GPS/location toggle) is off.
  servicesOff,

  /// Running in a browser on an insecure (`http://`, non-`localhost`)
  /// origin, where the Geolocation API refuses without ever showing a
  /// prompt.
  ///
  /// `GeolocatorLocationService` cannot currently distinguish this from an
  /// ordinary refusal on the web platform — see its own doc comment — so
  /// this reason exists in the model but is not yet produced there; it
  /// maps to [LocationDenied] with `permanently: false` instead.
  insecureContext,

  /// The position request exceeded its time budget.
  timeout,

  /// The platform could not determine a permission or position at all, or
  /// raised an error this service does not classify more precisely.
  unsupported,
}

/// The outcome of one [LocationService.current] call (architecture.md
/// §6.5).
///
/// Not constructed directly; use [LocationFound], [LocationDenied] or
/// [LocationUnavailable].
@immutable
sealed class LocationResult {
  /// Subclasses only.
  const new();
}

/// One position was read successfully.
@immutable
final class LocationFound extends LocationResult {
  /// Creates a result carrying [latitude], [longitude] and
  /// [accuracyMetres].
  const new({
    required this.latitude,
    required this.longitude,
    required this.accuracyMetres,
  });

  /// The latitude in degrees, normalised to -90.0 to +90.0 inclusive.
  final double latitude;

  /// The longitude in degrees, normalised to -180.0 (exclusive) to +180.0
  /// inclusive.
  final double longitude;

  /// The estimated horizontal accuracy of the position, in metres.
  final double accuracyMetres;

  @override
  bool operator ==(Object other) =>
      other is LocationFound &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.accuracyMetres == accuracyMetres;

  @override
  int get hashCode => Object.hash(latitude, longitude, accuracyMetres);

  @override
  String toString() => 'LocationFound($latitude, $longitude)';
}

/// The user refused location permission, or a web origin was denied
/// outright with no prompt shown.
@immutable
final class LocationDenied extends LocationResult {
  /// Creates a denial. [permanently] is true for iOS "Never" and Android
  /// "Don't ask again", where re-requesting in-app cannot show a prompt
  /// again — the caller should send the user to the platform's own
  /// settings instead.
  const new({required this.permanently});

  /// Whether the refusal is permanent: re-requesting will not show a
  /// prompt again.
  final bool permanently;

  @override
  bool operator ==(Object other) =>
      other is LocationDenied && other.permanently == permanently;

  @override
  int get hashCode => Object.hash(runtimeType, permanently);

  @override
  String toString() => 'LocationDenied(permanently: $permanently)';
}

/// A position could not be obtained for a reason other than the user
/// refusing permission.
@immutable
final class LocationUnavailable extends LocationResult {
  /// Creates an unavailable result for [reason].
  const new({required this.reason});

  /// Why a position could not be obtained.
  final LocationUnavailableReason reason;

  @override
  bool operator ==(Object other) =>
      other is LocationUnavailable && other.reason == reason;

  @override
  int get hashCode => Object.hash(runtimeType, reason);

  @override
  String toString() => 'LocationUnavailable($reason)';
}

/// Reads the device's current position for nearby search
/// (architecture.md §6.5).
///
/// Interface only: `di.dart` is the only file that constructs a concrete
/// implementation. A caller that gets anything other than [LocationFound]
/// degrades to a manual search (typing an address or a venue name) rather
/// than blocking on location.
abstract interface class LocationService {
  /// Requests permission if needed, then reads one position.
  ///
  /// Never throws.
  Future<LocationResult> current();

  /// Opens the platform's own settings so the user can grant what KetoClub
  /// cannot re-request itself (issue #40): the app's permission page for a
  /// permanent [LocationDenied] (`servicesOff: false`), or the device's
  /// location toggle for [LocationUnavailableReason.servicesOff]
  /// (`servicesOff: true`).
  ///
  /// Returns whether the platform reports having opened it. Never throws:
  /// on the web, where there is no such settings page to open, this
  /// returns false without any platform call at all.
  Future<bool> openSettings({required bool servicesOff});
}
