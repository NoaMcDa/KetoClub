// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §18.4): the real
// build launches to the venue search screen. This is the one flow through
// the real composition root (`di.dart`), so it asserts what that screen
// shows, not only the app's name.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/main.dart' as app;
import 'package:ketoclub/screens/venue_search_screen.dart';
import 'package:ketoclub/utils/constants.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App launch flow', () {
    testWidgets('user opens the app and sees the venue search screen', (
      tester,
    ) async {
      // Setup: launch the app through its real composition root.
      app.main();
      await tester.pumpAndSettle();

      // Assert: the first screen is the venue search screen, with its
      // paste field built by the real dependencies. There is no standing
      // open button any more (#229): a pasted link shows a suffix icon.
      expect(find.text(appName), findsOneWidget);
      expect(find.byType(VenueSearchScreen), findsOneWidget);
      expect(find.text(_en.venueSearchLabel), findsOneWidget);
      expect(find.text(_en.venueSearchHint), findsOneWidget);
      expect(find.byTooltip(_en.venueSearchOpenLink), findsNothing);
    });
  });
}
