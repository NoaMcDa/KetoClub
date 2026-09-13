import 'package:flutter/foundation.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/platform/app_logger.dart';
import 'package:ketoclub/services/platform/clock.dart';

/// The set of service interfaces the app is built on (architecture.md §18.1).
///
/// Holds interfaces only, never concrete implementations. `di.dart` fills it
/// for production; tests fill it with fakes. Fields are added as services
/// land, one per interface, in build order (architecture.md §16).
@immutable
class AppDependencies {
  /// Creates the dependency set the screens and controllers are built on.
  const new({
    required this.menuRepository,
    required this.menuClassifier,
    required this.clock,
    required this.logger,
  });

  /// Loads a venue's menu, cache first (architecture.md §6.1).
  final MenuRepository menuRepository;

  /// Classifies a whole menu in one call (architecture.md §6.2).
  final MenuClassifier menuClassifier;

  /// The only source of the current time, so tests control it.
  final Clock clock;

  /// Structured logging; never receives the OpenRouter key or an upstream body.
  final AppLogger logger;
}
