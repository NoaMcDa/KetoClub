import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/app.dart';
import 'package:ketoclub/utils/constants.dart';

import 'fakes/fake_app_dependencies.dart';

void main() {
  group('KetoClubApp', () {
    testWidgets('shows the app name on launch', (tester) async {
      // Arrange: the real app on top of faked services.
      await tester.pumpWidget(
        KetoClubApp(dependencies: FakeAppDependencies().dependencies),
      );
      // Assert
      expect(find.text(appName), findsOneWidget);
    });
  });
}
