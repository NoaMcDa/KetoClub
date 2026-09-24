import 'package:flutter/foundation.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/location/location_service.dart';
import 'package:ketoclub/services/menu/menu_repository.dart';
import 'package:ketoclub/services/platform/app_logger.dart';
import 'package:ketoclub/services/platform/clock.dart';
import 'package:ketoclub/services/platform/connectivity.dart';
import 'package:ketoclub/services/platform/external_link_opener.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/services/storage/notes_store.dart';
import 'package:ketoclub/services/storage/settings_store.dart';

/// The set of service interfaces the app is built on (architecture.md §18.1).
///
/// Holds interfaces only, never concrete implementations. `di.dart` fills it
/// for production; tests fill it with fakes, which is what lets a flow test run
/// the real app over faked I/O without a mocking library.
@immutable
class AppDependencies {
  /// Creates the dependency set the screens and controllers are built on.
  ///
  /// [screenBrightness] defaults to [NoOpScreenBrightness] rather than
  /// being required: it was added after every existing call site — every
  /// flow test's fake dependency set among them — was already written, and
  /// a caller with nothing to say about brightness should not have to say
  /// so.
  const new({
    required this.menuRepository,
    required this.menuClassifier,
    required this.settingsStore,
    required this.notesStore,
    required this.clock,
    required this.logger,
    required this.connectivity,
    required this.externalLinkOpener,
    required this.menuSharer,
    required this.locationService,
    this.screenBrightness = const NoOpScreenBrightness(),
  });

  /// Loads a venue's menu, cache first (architecture.md §6.1).
  final MenuRepository menuRepository;

  /// Classifies a whole menu in one call, LLM first and rules as the
  /// fallback (architecture.md §6.2).
  final MenuClassifier menuClassifier;

  /// Non-secret settings: language, default filter, consent, last venue.
  final SettingsStore settingsStore;

  /// Personal, on-device notes per dish (issue #52, architecture.md D8).
  /// Never read by [menuClassifier] and never sent anywhere — see
  /// [NotesStore]'s own doc comment for that boundary.
  final NotesStore notesStore;

  /// The only source of the current time, so tests control it.
  final Clock clock;

  /// Structured logging; never receives a credential or an upstream error
  /// body.
  final AppLogger logger;

  /// Whether the device currently appears to have a route to the network
  /// (architecture.md §14 D10). A hint, never a verdict — see
  /// [Connectivity]'s own doc comment — used both by the classifier
  /// router and by the persistent offline banner (issue #68).
  final Connectivity connectivity;

  /// Raises and restores the screen brightness while the Waiter Card is
  /// open (architecture.md §6.3). A no-op on platforms with no brightness
  /// API of their own, such as web.
  final ScreenBrightness screenBrightness;

  /// Opens a venue's own page on its platform outside KetoClub (issue #53).
  final ExternalLinkOpener externalLinkOpener;

  /// Shares the classified menu's green and yellow dishes as plain text
  /// through the platform's own share sheet (issue #54).
  final MenuSharer menuSharer;

  /// Reads the device's current position for nearby search
  /// (architecture.md §6.5, issue #37). Nothing consumes this yet — the
  /// Discovery screen and `VenueSearchService` that will (issues #39,
  /// #40) are separate work.
  final LocationService locationService;
}
