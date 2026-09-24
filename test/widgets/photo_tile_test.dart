import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/widgets/photo_tile.dart';

/// Pumps [child] inside a bare [MaterialApp], the shape every widget test
/// in `test/widgets/` uses.
Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  group('PhotoTile', () {
    testWidgets('build shows the placeholder gradient for a null URL, no '
        'Image widget', (tester) async {
      // Act
      await _pump(tester, const PhotoTile(imageUrl: null, size: 72));

      // Assert: the placeholder gradient container is drawn, and no
      // Image widget is ever built for a null URL — there is nothing to
      // attempt.
      expect(
        find.byKey(const ValueKey('photoTilePlaceholder')),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('build shows the placeholder gradient when the network request '
        'fails (the flutter_test binding fails every request with a 400)', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        const PhotoTile(imageUrl: 'https://images.wolt.com/dish.jpg', size: 72),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(
        find.byKey(const ValueKey('photoTilePlaceholder')),
        findsOneWidget,
      );
    });

    testWidgets(
      'build keeps the same fixed size whether the URL is null or fails '
      'to load, so an image arriving never shifts the layout',
      (tester) async {
        // Act: null URL.
        await _pump(tester, const PhotoTile(imageUrl: null, size: 72));
        final nullSize = tester.getSize(find.byType(PhotoTile));

        // Act: a URL that fails to load.
        await _pump(
          tester,
          const PhotoTile(
            imageUrl: 'https://images.wolt.com/dish.jpg',
            size: 72,
          ),
        );
        await tester.pumpAndSettle();
        final errorSize = tester.getSize(find.byType(PhotoTile));

        // Assert
        expect(nullSize, const Size(72, 72));
        expect(errorSize, const Size(72, 72));
      },
    );

    testWidgets('a width of double.infinity fills the parent at [size] '
        'tall — the venue card banner, not a square', (tester) async {
      // Arrange: a Stack hands its child loose constraints, as the venue
      // card's does, so a square tile would not be stretched.
      await _pump(
        tester,
        const Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: Stack(
              children: [
                PhotoTile(imageUrl: null, size: 118, width: double.infinity),
              ],
            ),
          ),
        ),
      );

      // Act
      final size = tester.getSize(find.byType(PhotoTile));

      // Assert
      expect(size, const Size(300, 118));
    });
  });
}
