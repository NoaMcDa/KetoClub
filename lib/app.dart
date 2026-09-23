// This SDK's material.dart exports its own MenuController (a menu-anchor
// widget), which collides with ours in state/. Hiding it keeps the import
// unprefixed everywhere else.
import 'dart:async';

import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/menu_screen.dart';
import 'package:ketoclub/screens/saved_screen.dart';
import 'package:ketoclub/screens/scan_screen.dart';
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/screens/venue_search_screen.dart';
import 'package:ketoclub/state/app_dependencies.dart';
import 'package:ketoclub/state/locale_controller.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/state/venue_search_controller.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/widgets/app_shell.dart';
import 'package:provider/provider.dart';

/// The root widget: MaterialApp, theme, routes, localisation
/// (architecture.md §6.6, §12; issues #8, #11).
///
/// Receives its services from the composition root so that tests can pump
/// the whole app with fakes.
///
/// A `StatefulWidget` for exactly one reason: it owns a [LocaleController]
/// for the lifetime of the app, created once in `initState` rather than
/// rebuilt on every `build`. A `StatelessWidget` has no such hook —
/// `provider`'s `create` runs once per *provider*, but there would be
/// nothing to host that provider above without a place to call `dispose` —
/// so this mirrors why `SettingsScreen` and `MenuScreen` are themselves
/// stateful for their own single post-frame load.
class KetoClubApp extends StatefulWidget {
  /// Creates the app on top of [dependencies].
  const new({required this.dependencies, super.key});

  /// The service interfaces the screens and controllers are built on.
  final AppDependencies dependencies;

  @override
  State<KetoClubApp> createState() => _KetoClubAppState();
}

class _KetoClubAppState extends State<KetoClubApp> {
  late final LocaleController _localeController;

  @override
  void initState() {
    super.initState();
    _localeController = LocaleController(widget.dependencies.settingsStore);
    // Fire-and-forget: the first frame renders in the device locale and
    // flips once this resolves (LocaleController's class doc, issue #8).
    unawaited(_localeController.load());
  }

  @override
  void dispose() {
    _localeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ChangeNotifierProvider.value (not `create`) because this state class,
    // not provider, owns the controller's lifecycle — see the class doc.
    // AnimatedBuilder is what actually makes MaterialApp rebuild when the
    // locale changes; the provider only makes the controller reachable
    // from SettingsScreen, several routes below.
    return ChangeNotifierProvider<LocaleController>.value(
      value: _localeController,
      child: AnimatedBuilder(
        animation: _localeController,
        builder: (context, _) => MaterialApp(
          title: appName,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          // Explicit even though it matches MaterialApp's own default: it
          // is the acceptance criterion for issue #9, and stating it here
          // means a future default change upstream can never silently
          // change it.
          // ignore: avoid_redundant_argument_values
          themeMode: ThemeMode.system,
          locale: _localeController.locale,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          onGenerateRoute: (settings) =>
              generateRoute(settings, widget.dependencies),
        ),
      ),
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
/// The four tab-root routes (`/`, `/scan`, `/saved`, `/settings`, issue #11)
/// are each wrapped in [AppShell], which supplies the bottom navigation and
/// highlights the tab that matches. `/venue/{source}/{platformId}` is a
/// pushed detail route and is deliberately left unwrapped, matching the
/// artboards: `.design/Discovery.dc.html` and `.design/Settings.dc.html`
/// carry the nav bar; `.design/MenuDark.dc.html` and
/// `.design/WaiterCard.dc.html` do not.
///
/// Each route creates its own controller, so screen state does not outlive the
/// screen and two visits to a venue start clean. That also means switching
/// tabs discards whatever was typed into the Explore text field, since
/// `VenueSearchController` is rebuilt — an accepted trade-off (issue #11)
/// rather than a reason to reach for a `Navigator` per tab, which would have
/// to own `/settings` as one of its children and break the direct deep link
/// `generateRoute`'s own tests assert.
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
      builder: (_) => AppShell(
        currentIndex: AppShell.exploreIndex,
        child: ChangeNotifierProvider<VenueSearchController>(
          create: (_) => VenueSearchController(),
          child: const VenueSearchScreen(),
        ),
      ),
    );
  }

  if (name == scanRoutePath) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) =>
          const AppShell(currentIndex: AppShell.scanIndex, child: ScanScreen()),
    );
  }

  if (name == savedRoutePath) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => const AppShell(
        currentIndex: AppShell.savedIndex,
        child: SavedScreen(),
      ),
    );
  }

  if (name == settingsRoutePath) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => AppShell(
        currentIndex: AppShell.settingsIndex,
        child: ChangeNotifierProvider<SettingsController>(
          create: (_) => SettingsController(
            dependencies.settingsStore,
            dependencies.menuRepository,
          ),
          child: const SettingsScreen(),
        ),
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
          dependencies.notesStore,
        ),
        child: MenuScreen(
          ref: ref,
          screenBrightness: dependencies.screenBrightness,
        ),
      ),
    );
  }

  return null;
}

/// The Settings route path, pushed by the app bar action on every screen and
/// by the Settings tab.
const String settingsRoutePath = '/settings';

/// The Scan tab's route path (issue #11).
const String scanRoutePath = '/scan';

/// The Saved tab's route path (issue #11).
const String savedRoutePath = '/saved';

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
