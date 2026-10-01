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

      // Assert: the logo mark carries the name as its semantics label.
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel(appName), findsOneWidget);
      handle.dispose();
    });
  });
}
