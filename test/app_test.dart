import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/app.dart';
import 'package:ketoclub/state/app_dependencies.dart';
import 'package:ketoclub/utils/constants.dart';

void main() {
  group('KetoClubApp', () {
    testWidgets('shows the app name on launch', (tester) async {
      // Arrange: the app on top of an (empty, for now) dependency set.
      await tester.pumpWidget(
        const KetoClubApp(dependencies: AppDependencies()),
      );

      // Assert
      expect(find.text(appName), findsOneWidget);
    });
  });
}
