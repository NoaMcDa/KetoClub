// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §18.4; issue #11):
// the bottom navigation shell — launch, visit every tab, and return to
// Explore without the navigation stack growing underneath the user.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/utils/constants.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// The app bar title reading [title], scoped for the same reason as
/// [navDestination].
Finder _appBarTitle(String title) =>
    find.descendant(of: find.byType(AppBar), matching: find.text(title));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Tab navigation flow', () {
    testWidgets(
      'user launches the app, visits every tab, and returns to Explore',
      (tester) async {
        // Setup: the app on top of in-memory fakes, no venue stubbed —
        // this journey never leaves the four tab-root screens.
        final fakes = FakeAppDependencies();
        await pumpApp(tester, fakes);

        // Assert: launch lands on Explore.
        expect(find.text(appName), findsOneWidget);
        expect(find.text(_en.venueSearchLabel), findsOneWidget);

        // Act: Scan.
        await tapAndSettle(tester, navDestination(_en.navScan));

        // Assert
        expect(find.text(_en.scanPlaceholderTitle), findsOneWidget);

        // Act: Saved.
        await tapAndSettle(tester, navDestination(_en.navSaved));

        // Assert
        expect(find.text(_en.savedPlaceholderTitle), findsOneWidget);

        // Act: Settings.
        await tapAndSettle(tester, navDestination(_en.navSettings));

        // Assert
        expect(_appBarTitle(_en.settingsTitle), findsOneWidget);

        // Act: back to Explore.
        await tapAndSettle(tester, navDestination(_en.navExplore));

        // Assert: Explore again, and nothing left over from Settings —
        // pushReplacementNamed means the stack never grew, so there is
        // nothing to pop back through.
        expect(find.text(_en.venueSearchLabel), findsOneWidget);
        expect(_appBarTitle(_en.settingsTitle), findsNothing);
      },
    );
  });
}
