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
/// A tab tap replaces the whole stack with the new tab root (`_selectTab`),
/// so the stack never grows — even when the shell was reached as a pushed
/// route, such as the menu screen's Settings action, which must not leave
/// the menu beneath the next tab (audit G8) — and the web URL tracks the
/// active tab; "active tab reflects the route" then needs no route
/// observer, since the index is simply passed in by whichever route built
/// this shell.
///
/// Back from a tab other than Explore — the browser's Back button, Android's
/// system back — returns to Explore rather than leaving the app (issue
/// #262). A `Navigator` without a `Router` tells Flutter web to keep a
/// single browser-history entry, so the browser's Back is simply a pop of
/// this navigator; a lone tab root has nothing beneath it to pop to, so
/// the shell catches that pop (`_backToExplore`) and switches to Explore
/// instead. Back from Explore still leaves the app. A shell pushed over
/// another route (Settings over a menu) pops normally, back to that route.
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
  /// destinations `_tabs` lists. Mirrors the route path constants in
  /// `app.dart` (`scanRoutePath`, `savedRoutePath`, `settingsRoutePath`);
  /// this widget cannot import `app.dart` to reuse them directly —
  /// `widgets/` sits below `app.dart` in the layer order (architecture.md
  /// §5) — so the four literals are the one place this shell must be kept
  /// in step with them.
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
    return RouteTitle(
      page: pageTitle ?? _tabs(l10n)[currentIndex].label,
      child: _backToExplore(context, _scaffold(context, l10n)),
    );
  }

  /// The four destinations, in [_routes]' order: icon, selected icon and
  /// label. The one list every navigation surface builds from, so a
  /// `NavigationRail` on wide screens (issue #223) cannot drift from the
  /// bottom bar.
  static List<({IconData icon, IconData selectedIcon, String label})> _tabs(
    AppLocalizations l10n,
  ) => [
    (
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore,
      label: l10n.navExplore,
    ),
    (
      icon: Icons.document_scanner_outlined,
      selectedIcon: Icons.document_scanner,
      label: l10n.navScan,
    ),
    (icon: Icons.history, selectedIcon: Icons.history, label: l10n.navSaved),
    (icon: Icons.tune, selectedIcon: Icons.tune, label: l10n.navSettings),
  ];

  /// Switches to tab [index]: the one tap handler every navigation surface
  /// calls (issue #223 reuses it for the rail).
  ///
  /// Removes every route, not just this one, and pushes the tab root, so
  /// the new tab replaces the current one. When this shell is the only
  /// route — every tab-to-tab switch — that is exactly a
  /// `pushReplacementNamed`. When the shell was pushed over other routes —
  /// Settings from a menu or from the Scan tab, the drinks guide from a
  /// menu, a deep link Flutter web stacks over `/` — replacing only the top
  /// would leave the menu and everything under it beneath the new tab, and
  /// each such round trip grew the stack by a whole menu screen (audit G8).
  /// Clearing them all handles every such source in this one place, while
  /// the source itself can still push Settings over the menu so that Back
  /// from Settings returns to it.
  void _selectTab(BuildContext context, int index) {
    if (index == currentIndex) return;
    Navigator.of(context).pushNamedAndRemoveUntil(_routes[index], (_) => false);
  }

  /// Wraps [scaffold] so that Back from a lone tab root other than Explore
  /// switches to Explore instead of leaving the app (issue #262; see the
  /// class doc). Explore itself, and any shell with a route beneath it to
  /// pop back to, pop as usual — which also keeps the iOS back-swipe working
  /// for Settings pushed over a menu.
  Widget _backToExplore(BuildContext context, Widget scaffold) {
    if (currentIndex == exploreIndex) return scaffold;
    return PopScope<Object?>(
      canPop: ModalRoute.canPopOf(context) ?? true,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _selectTab(context, exploreIndex);
      },
      child: scaffold,
    );
  }

  Widget _scaffold(BuildContext context, AppLocalizations l10n) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) => _selectTab(context, index),
        destinations: [
          for (final tab in _tabs(l10n))
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}
