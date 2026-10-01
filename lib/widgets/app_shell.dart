import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/widgets/route_title.dart';

/// The bottom-navigation shell around the four tab-root routes: Explore,
/// Scan, Saved and Settings (architecture.md §6.6; issue #11).
///
/// Purely presentational: it takes an already-built [child] screen and a
/// `const` [currentIndex] the route builder supplies, and holds no state and
/// reaches no service of its own — `app.dart`'s `generateRoute` is the only
/// place that decides which index a route gets.
///
/// A tab tap uses [Navigator.pushNamedAndRemoveUntil], clearing every route
/// beneath it, so the stack never grows — even when the shell was reached
/// as a pushed route, such as the menu screen's Settings action — and the
/// web URL tracks the active tab; "active tab reflects the route"
/// then needs no route observer, since the index is simply passed in by
/// whichever route built this shell.
///
/// This is deliberately not an `IndexedStack`: the other routes in
/// `generateRoute` build a fresh controller on purpose (so two visits to a
/// screen start clean), and an `IndexedStack` would have to own `/settings`
/// as one of its children, breaking the direct deep link `test/app_test.dart`
/// asserts. Explore keeps its query, results and chip across a tab switch
/// anyway, because its `VenueSearchController` lives as long as the app
/// rather than the route (issue #233) — see `generateRoute`'s doc comment in
/// `app.dart`.
class AppShell extends StatelessWidget {
  /// Creates the shell around [child], with tab [currentIndex] highlighted.
  const new({
    required this.currentIndex,
    required this.child,
    this.pageTitle,
    super.key,
  });

  /// The Explore tab's index — `/`, wrapping `VenueSearchScreen`.
  static const int exploreIndex = 0;

  /// The Scan tab's index — `/scan`, wrapping `ScanScreen`.
  static const int scanIndex = 1;

  /// The Saved tab's index — `/saved`, wrapping `SavedScreen`.
  static const int savedIndex = 2;

  /// The Settings tab's index — `/settings`, wrapping `SettingsScreen`.
  static const int settingsIndex = 3;

  /// The route pushed for each tab index, in the same order as the
  /// `NavigationDestination`s built in `build` below. Mirrors the route
  /// path constants in `app.dart`
  /// (`scanRoutePath`, `savedRoutePath`, `settingsRoutePath`); this widget
  /// cannot import `app.dart` to reuse them directly — `widgets/` sits below
  /// `app.dart` in the layer order (architecture.md §5) — so the four
  /// literals are the one place this shell must be kept in step with them.
  static const List<String> _routes = <String>[
    '/',
    '/scan',
    '/saved',
    '/settings',
  ];

  /// Which of the four tabs is active.
  ///
  /// One of [exploreIndex], [scanIndex], [savedIndex] or [settingsIndex].
  final int currentIndex;

  /// The tab-root screen this shell wraps.
  final Widget child;

  /// The browser-tab title's page name, when it should not be the active
  /// tab's label (the drinks guide, which lives under Settings; issue #226).
  final String? pageTitle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tabLabels = <String>[
      l10n.navExplore,
      l10n.navScan,
      l10n.navSaved,
      l10n.navSettings,
    ];
    return RouteTitle(
      page: pageTitle ?? tabLabels[currentIndex],
      child: _scaffold(context, l10n),
    );
  }

  Widget _scaffold(BuildContext context, AppLocalizations l10n) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          if (index == currentIndex) return;
          // Removes every route, not just this one: the shell is also
          // reached as a pushed route (the menu screen's Settings
          // action), and replacing only the top would leave the menu
          // and everything under it stacked beneath the new tab — each
          // such round trip grew the stack by a whole menu screen.
          Navigator.of(context)
              .pushNamedAndRemoveUntil(_routes[index], (_) => false);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.explore_outlined),
            selectedIcon: const Icon(Icons.explore),
            label: l10n.navExplore,
          ),
          NavigationDestination(
            icon: const Icon(Icons.document_scanner_outlined),
            selectedIcon: const Icon(Icons.document_scanner),
            label: l10n.navScan,
          ),
          NavigationDestination(
            icon: const Icon(Icons.history),
            selectedIcon: const Icon(Icons.history),
            label: l10n.navSaved,
          ),
          NavigationDestination(
            icon: const Icon(Icons.tune),
            selectedIcon: const Icon(Icons.tune),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }
}
