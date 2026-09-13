// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §18.4): the real
// build launches to the venue search screen.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/main.dart' as app;
import 'package:ketoclub/utils/constants.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App launch flow', () {
    testWidgets('user opens the app and sees the venue search screen', (
      tester,
    ) async {
      // Setup: launch the app through its real composition root.
      app.main();
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(appName), findsOneWidget);
    });
  });
}
