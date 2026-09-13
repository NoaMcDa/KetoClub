import 'package:flutter/foundation.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/platform/app_logger.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/storage/key_store.dart';
import 'package:ketoclub/services/storage/settings_store.dart';

/// The set of service interfaces the app is built on (architecture.md §18.1).
///
/// Holds interfaces only, never concrete implementations. `di.dart` fills it
/// for production; tests fill it with fakes, which is what lets a flow test run
/// the real app over faked I/O without a mocking library.
@immutable
class AppDependencies {
  /// Creates the dependency set the screens and controllers are built on.
  const new({
    required this.menuRepository,
    required this.menuClassifier,
    required this.keyStore,
    required this.settingsStore,
    required this.clock,
    required this.logger,
  });

  /// Loads a venue's menu, cache first (architecture.md §6.1).
  final MenuRepository menuRepository;

  /// Classifies a whole menu in one call, LLM first and rules as the
  /// fallback (architecture.md §6.2).
  final MenuClassifier menuClassifier;

  /// The OpenRouter key. Read by the LLM client and by Settings, which asks
  /// only whether one exists (architecture.md §11).
  final KeyStore keyStore;

  /// Non-secret settings: language, default filter, consent, last venue.
  final SettingsStore settingsStore;

  /// The only source of the current time, so tests control it.
  final Clock clock;

  /// Structured logging; never receives the key or an upstream error body.
  final AppLogger logger;
}
