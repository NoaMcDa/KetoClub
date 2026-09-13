import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/main.dart' as app;
import 'package:ketoclub/utils/constants.dart';

void main() {
  group('main', () {
    testWidgets('launches the app through the composition root', (
      tester,
    ) async {
      // Act: the real entry point, under the test binding.
      app.main();
      await tester.pump();

      // Assert
      expect(find.text(appName), findsOneWidget);
    });
  });
}
