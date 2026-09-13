import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/app.dart';
import 'package:ketoclub/models/venue.dart';
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

  group('venueRefFromPath', () {
    test('parses a venue path into a ref', () {
      // Act
      final ref = venueRefFromPath('/venue/wolt/vitrina-lilinblum');

      // Assert
      expect(
        ref,
        const VenueRef(
          source: MenuSource.wolt,
          platformId: 'vitrina-lilinblum',
        ),
      );
    });

    test('matches the source by name, not by ordinal', () {
      // Assert: a saved link must survive a reordering of MenuSource.
      expect(
        venueRefFromPath('/venue/tenbis/12345')?.source,
        MenuSource.tenbis,
      );
      expect(venueRefFromPath('/venue/0/12345'), isNull);
    });

    test('rejects a path that is not a venue route', () {
      // Assert
      expect(venueRefFromPath('/'), isNull);
      expect(venueRefFromPath('/settings'), isNull);
      expect(venueRefFromPath('/venue/wolt'), isNull);
      expect(venueRefFromPath('/venue/wolt/'), isNull);
      expect(venueRefFromPath('/venue/nosuch/slug'), isNull);
    });
  });

  group('generateRoute', () {
    test('builds a route for the home, settings and venue paths', () {
      // Arrange
      final dependencies = FakeAppDependencies().dependencies;

      // Assert
      for (final path in <String>[
        '/',
        settingsRoutePath,
        '/venue/wolt/vitrina-lilinblum',
      ]) {
        expect(
          generateRoute(RouteSettings(name: path), dependencies),
          isNotNull,
          reason: 'no route for $path',
        );
      }
    });

    test('returns null for an unknown path rather than a blank screen', () {
      // Arrange
      final dependencies = FakeAppDependencies().dependencies;

      // Assert
      expect(
        generateRoute(const RouteSettings(name: '/nope'), dependencies),
        isNull,
      );
    });
  });
}
