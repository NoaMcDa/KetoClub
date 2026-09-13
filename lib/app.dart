// This SDK's material.dart exports its own MenuController (a menu-anchor
// widget), which collides with ours in state/. Hiding it keeps the import
// unprefixed everywhere else.
import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/menu_screen.dart';
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/screens/venue_search_screen.dart';
import 'package:ketoclub/state/app_dependencies.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/state/venue_search_controller.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:provider/provider.dart';

/// The root widget: MaterialApp, theme, routes, localisation
/// (architecture.md §6.6, §12).
///
/// Receives its services from the composition root so that tests can pump
/// the whole app with fakes.
class KetoClubApp extends StatelessWidget {
  /// Creates the app on top of [dependencies].
  const new({required this.dependencies, super.key});

  /// The service interfaces the screens and controllers are built on.
  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateRoute: (settings) => generateRoute(settings, dependencies),
    );
  }
}

/// Builds the route for [settings] over [dependencies], or null when the path
/// is not one of ours.
///
/// Routes are parsed from the path rather than passed as arguments so that a
/// web deep link to a venue works (architecture.md §6.6): the menu route is
/// `/venue/{source}/{platformId}`, which is what `VenueSearchScreen` pushes.
/// An unparseable source or an empty id yields null rather than a screen built
/// on a bad reference.
///
/// Each route creates its own controller, so screen state does not outlive the
/// screen and two visits to a venue start clean.
///
/// Public and separately tested, because a silently unmatched route would
/// present as a blank screen.
Route<void>? generateRoute(
  RouteSettings settings,
  AppDependencies dependencies,
) {
  final name = settings.name ?? '/';

  if (name == '/' || name.isEmpty) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => ChangeNotifierProvider<VenueSearchController>(
        create: (_) => VenueSearchController(),
        child: const VenueSearchScreen(),
      ),
    );
  }

  if (name == settingsRoutePath) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => ChangeNotifierProvider<SettingsController>(
        create: (_) => SettingsController(
          dependencies.keyStore,
          dependencies.settingsStore,
          dependencies.menuRepository,
        ),
        child: const SettingsScreen(),
      ),
    );
  }

  final ref = venueRefFromPath(name);
  if (ref != null) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => ChangeNotifierProvider<MenuController>(
        create: (_) => MenuController(
          dependencies.menuRepository,
          dependencies.menuClassifier,
          dependencies.settingsStore,
        ),
        child: MenuScreen(ref: ref),
      ),
    );
  }

  return null;
}

/// The Settings route path, pushed by the app bar action on every screen.
const String settingsRoutePath = '/settings';

/// Parses `/venue/{source}/{platformId}` into a [VenueRef], or null.
///
/// Matched by string against [MenuSource] names, never by ordinal, so
/// reordering the enum cannot silently re-point a saved link.
VenueRef? venueRefFromPath(String path) {
  final segments = Uri.parse(path).pathSegments;
  if (segments.length != 3 || segments.first != 'venue') return null;
  final source = MenuSource.tryParse(segments[1]);
  if (source == null || segments[2].isEmpty) return null;
  return VenueRef(source: source, platformId: segments[2]);
}
