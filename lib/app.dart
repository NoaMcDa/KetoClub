import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/screens/venue_search_screen.dart';
import 'package:ketoclub/state/app_dependencies.dart';
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
    return const MaterialApp(
      title: appName,
      localizationsDelegates: <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateRoute: generateRoute,
    );
  }
}

/// Builds the route for [settings], or null when the path is not one of ours.
///
/// Routes are parsed from the path rather than passed as arguments so that a
/// web deep link to a venue works (architecture.md §6.6): the menu route is
/// `/venue/{source}/{platformId}`, which is what `VenueSearchScreen` pushes.
///
/// Public and separately tested, because a silently unmatched route would
/// present as a blank screen.
Route<void>? generateRoute(RouteSettings settings) {
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

  return null;
}
