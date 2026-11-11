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

  sliverVenueGridTests();
}

/// Pumps a [SliverVenueGrid] of [count] tiles in a [CustomScrollView]
/// [width] wide, recording every index built into [built] and the aspect
/// ratio each tile was built with into [ratios]. A tile is [heightOf] its
/// index tall, 50px by default.
Future<void> _pumpSliver(
  WidgetTester tester, {
  required double width,
  required int count,
  List<int>? built,
  List<double?>? ratios,
  double Function(int index)? heightOf,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: CustomScrollView(
              slivers: [
                SliverVenueGrid(
                  itemCount: count,
                  itemBuilder: (context, i, photoAspectRatio) {
                    built?.add(i);
                    ratios?.add(photoAspectRatio);
                    return SizedBox(
                      height: heightOf?.call(i) ?? 50,
                      key: ValueKey(i),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Gives the test a [size] surface for its duration.
void _useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The lazy grid (issue #446): [VenueGrid]'s layout, built row by row.
void sliverVenueGridTests() {
  group('SliverVenueGrid (issue #446)', () {
    testWidgets('one column stacks every tile full width, 19px apart, with '
        'no aspect ratio', (tester) async {
      // Arrange
      final ratios = <double?>[];

      // Act
      await _pumpSliver(tester, width: 350, count: 3, ratios: ratios);

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
      await _pumpSliver(tester, width: 760, count: 3, ratios: ratios);

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
      _useSurface(tester, const Size(1200, 900));

      // Act
      await _pumpSliver(tester, width: 1040, count: 4);

      // Assert
      final tops = [
        for (var i = 0; i < 4; i++) tester.getRect(find.byKey(ValueKey(i))).top,
      ];
      expect(tops[0], tops[1]);
      expect(tops[1], tops[2]);
      expect(tops[3], greaterThan(tops[0]));
    });

    testWidgets('tiles in one row are stretched to the tallest, so their '
        'surfaces line up', (tester) async {
      // Act: a short tile beside a tall one.
      await _pumpSliver(
        tester,
        width: 760,
        count: 2,
        heightOf: (i) => i == 0 ? 50 : 120,
      );

      // Assert: the row is as tall as its tallest tile's slot.
      final row = tester.getSize(find.byType(IntrinsicHeight));
      expect(row.height, 120);
    });

    testWidgets('lays its tiles out exactly where VenueGrid does', (
      tester,
    ) async {
      // Arrange: the eager grid's rectangles.
      await _pump(tester, width: 760, count: 5, ratios: <double?>[]);
      final eager = [
        for (var i = 0; i < 5; i++) tester.getRect(find.byKey(ValueKey(i))),
      ];

      // Act
      await _pumpSliver(tester, width: 760, count: 5);

      // Assert
      final lazy = [
        for (var i = 0; i < 5; i++) tester.getRect(find.byKey(ValueKey(i))),
      ];
      expect(lazy, eager);
    });

    testWidgets('builds only the rows on or near the screen, however many '
        'tiles there are', (tester) async {
      // Arrange: 600px of viewport, 3,000 tiles of 50px.
      final built = <int>[];

      // Act
      await _pumpSliver(tester, width: 350, count: 3000, built: built);

      // Assert: a screenful and the default cache extent beyond it, not
      // thousands.
      expect(built.toSet().length, lessThan(40));
      expect(built, contains(0));
      expect(
        find.byKey(const ValueKey(2999), skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets('scrolling builds the rows that come into view', (
      tester,
    ) async {
      // Arrange
      final built = <int>[];
      await _pumpSliver(tester, width: 350, count: 3000, built: built);
      expect(built, isNot(contains(60)));

      // Act: far enough down that tile 60 is on screen.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
      await tester.pumpAndSettle();

      // Assert
      expect(built, contains(60));
      expect(find.byKey(const ValueKey(60)), findsOneWidget);
    });

    testWidgets('in two columns a row is built whole or not at all', (
      tester,
    ) async {
      // Arrange
      final built = <int>[];

      // Act
      await _pumpSliver(tester, width: 760, count: 3001, built: built);

      // Assert: an even number of tiles, both of each row built.
      final indexes = built.toSet();
      expect(indexes.length.isEven, isTrue);
      for (final i in indexes) {
        expect(indexes, contains(i.isEven ? i + 1 : i - 1));
      }
    });

    testWidgets('builds nothing for an empty list', (tester) async {
      // Arrange
      final built = <int>[];

      // Act
      await _pumpSliver(tester, width: 350, count: 0, built: built);

      // Assert
      expect(built, isEmpty);
    });
  });
}
