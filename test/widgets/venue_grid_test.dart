import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/widgets/venue_card.dart';
import 'package:ketoclub/widgets/venue_grid.dart';

/// Pumps a [VenueGrid] of [count] 50px-tall tiles, [width] wide,
/// recording the aspect ratio each tile was built with into [ratios].
Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required int count,
  required List<double?> ratios,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: VenueGrid(
                itemCount: count,
                itemBuilder: (context, i, photoAspectRatio) {
                  ratios.add(photoAspectRatio);
                  return SizedBox(height: 50, key: ValueKey(i));
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('venueGridColumns', () {
    test('is one below 680px, two from 680px and three from 1000px', () {
      // Act + Assert
      expect(venueGridColumns(350), 1);
      expect(venueGridColumns(679.9), 1);
      expect(venueGridColumns(680), 2);
      expect(venueGridColumns(999.9), 2);
      expect(venueGridColumns(1000), 3);
      expect(venueGridColumns(discoveryMaxWidth - 40), 3);
    });
  });

  group('VenueGrid', () {
    testWidgets('one column stacks every tile full width, 19px apart, '
        'with no aspect ratio', (tester) async {
      // Arrange
      final ratios = <double?>[];

      // Act
      await _pump(tester, width: 350, count: 3, ratios: ratios);

      // Assert
      final first = tester.getRect(find.byKey(const ValueKey(0)));
      final second = tester.getRect(find.byKey(const ValueKey(1)));
      expect(first.width, 350);
      expect(second.top - first.bottom, VenueGrid.rowGap);
      expect(ratios, everyElement(isNull));
    });

    testWidgets('two columns put two tiles in a row with the grid aspect '
        'ratio, and a short last row keeps the tile width', (tester) async {
      // Arrange
      final ratios = <double?>[];

      // Act
      await _pump(tester, width: 760, count: 3, ratios: ratios);

      // Assert
      final a = tester.getRect(find.byKey(const ValueKey(0)));
      final b = tester.getRect(find.byKey(const ValueKey(1)));
      final c = tester.getRect(find.byKey(const ValueKey(2)));
      expect(a.top, b.top);
      expect(b.left - a.right, VenueGrid.columnGap);
      expect(a.width, (760 - VenueGrid.columnGap) / 2);
      expect(c.top - a.bottom, VenueGrid.rowGap);
      expect(c.width, a.width);
      expect(ratios, everyElement(VenueCard.gridPhotoAspectRatio));
    });

    testWidgets('three columns put three tiles in a row', (tester) async {
      // Arrange: a surface wider than the default 800px.
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Act
      await _pump(tester, width: 1040, count: 4, ratios: <double?>[]);

      // Assert
      final tops = [
        for (var i = 0; i < 4; i++) tester.getRect(find.byKey(ValueKey(i))).top,
      ];
      expect(tops[0], tops[1]);
      expect(tops[1], tops[2]);
      expect(tops[3], greaterThan(tops[0]));
    });
  });
}
