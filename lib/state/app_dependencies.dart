import 'package:flutter/foundation.dart';

/// The set of service interfaces the app is built on (architecture.md §18.1).
///
/// Holds interfaces only, never concrete implementations. `di.dart` fills it
/// for production; tests fill it with fakes. Fields are added as services
/// land, one per interface, in build order (architecture.md §16).
@immutable
class AppDependencies {
  /// Creates an empty dependency set. Fields arrive with the services.
  const new();
}
