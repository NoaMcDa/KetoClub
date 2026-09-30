import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/widgets/content_width.dart';

/// Marks the child whose laid-out rectangle a test measures.
const Key _childKey = ValueKey('content');

/// Sets the test surface to [width] × [height] logical pixels for the rest
/// of the test.
void _useSurface(WidgetTester tester, double width, {double height = 800}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps [body] as a [Scaffold] body wrapped in [ContentWidth], the shape
/// every screen uses.
Future<void> _pump(WidgetTester tester, Widget body, {double? maxWidth}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: maxWidth == null
            ? ContentWidth(child: body)
            : ContentWidth(maxWidth: maxWidth, child: body),
      ),
    ),
  );
}

void main() {
  group('ContentWidth', () {
    testWidgets('at phone width the child fills the whole width from the '
        'top-left corner, as it would without the wrapper', (tester) async {
      // Arrange
      _useSurface(tester, 390);

      // Act
      await _pump(tester, const SizedBox(key: _childKey, height: 100));

      // Assert
      final rect = tester.getRect(find.byKey(_childKey));
      expect(rect, const Rect.fromLTWH(0, 0, 390, 100));
    });

    testWidgets('a width exactly at the cap is passed through unchanged', (
      tester,
    ) async {
      // Arrange
      _useSurface(tester, contentMaxWidth);

      // Act
      await _pump(tester, const SizedBox(key: _childKey, height: 100));

      // Assert
      final rect = tester.getRect(find.byKey(_childKey));
      expect(rect, const Rect.fromLTWH(0, 0, contentMaxWidth, 100));
    });

    testWidgets('on a wide window the child is capped at contentMaxWidth '
        'and centred horizontally', (tester) async {
      // Arrange
      _useSurface(tester, 1440);

      // Act
      await _pump(tester, const SizedBox(key: _childKey, height: 100));

      // Assert: 1440 − 680 = 760, split evenly either side.
      final rect = tester.getRect(find.byKey(_childKey));
      expect(rect.width, contentMaxWidth);
      expect(rect.left, (1440 - contentMaxWidth) / 2);
      expect(rect.center.dx, 720);
    });

    testWidgets('on a wide window a short child stays at the top rather '
        'than floating to the middle of the screen', (tester) async {
      // Arrange
      _useSurface(tester, 1440);

      // Act
      await _pump(tester, const SizedBox(key: _childKey, height: 100));

      // Assert
      expect(tester.getRect(find.byKey(_childKey)).top, 0);
    });

    testWidgets('a child that sizes to its content still fills the capped '
        'column', (tester) async {
      // Arrange: a Text is only as wide as its words without a tight
      // width.
      _useSurface(tester, 1440);

      // Act
      await _pump(tester, const Text('Menu', key: _childKey));

      // Assert
      expect(tester.getSize(find.byKey(_childKey)).width, contentMaxWidth);
    });

    testWidgets('a scroll view child keeps the full height of the body', (
      tester,
    ) async {
      // Arrange
      _useSurface(tester, 1440, height: 600);

      // Act
      await _pump(
        tester,
        ListView(key: _childKey, children: const [SizedBox(height: 40)]),
      );

      // Assert
      final rect = tester.getRect(find.byKey(_childKey));
      expect(rect.height, 600);
      expect(rect.width, contentMaxWidth);
    });

    testWidgets('a caller-supplied maxWidth replaces the default cap', (
      tester,
    ) async {
      // Arrange
      _useSurface(tester, 1440);

      // Act
      await _pump(
        tester,
        const SizedBox(key: _childKey, height: 100),
        maxWidth: 1000,
      );

      // Assert
      final rect = tester.getRect(find.byKey(_childKey));
      expect(rect.width, 1000);
      expect(rect.left, 220);
    });

    test('the cap is 680 logical pixels (issue #221)', () {
      expect(contentMaxWidth, 680);
      expect(const ContentWidth(child: SizedBox()).maxWidth, contentMaxWidth);
    });
  });
}
