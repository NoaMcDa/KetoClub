import 'package:flutter/material.dart';
import 'package:ketoclub/screens/venue_search_screen.dart';
import 'package:ketoclub/state/app_dependencies.dart';
import 'package:ketoclub/utils/constants.dart';

/// The root widget: MaterialApp, theme, routes (architecture.md §6.6).
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
    return const MaterialApp(title: appName, home: VenueSearchScreen());
  }
}
