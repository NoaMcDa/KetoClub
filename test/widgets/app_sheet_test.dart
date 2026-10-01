import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/widgets/app_sheet.dart';

/// Key of the probe filling the sheet.
const Key _probeKey = Key('sheet-probe');

/// Pumps a button that opens [showKetoClubSheet] at [size], opens it, and
/// returns once the sheet has settled.
Future<void> _openSheet(
  WidgetTester tester,
  Size size, {
  bool showDragHandle = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showKetoClubSheet<void>(
              context: context,
              showDragHandle: showDragHandle,
              builder: (_) => const SizedBox(
                key: _probeKey,
                width: double.infinity,
                height: 200,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The height of the sheet's own surface: the probe's height, plus the
/// drag handle's row when one is shown.
double _sheetHeight(WidgetTester tester) => tester
    .getSize(
      find
          .ancestor(of: find.byKey(_probeKey), matching: find.byType(Material))
          .first,
    )
    .height;

void main() {
  group('showKetoClubSheet', () {
    testWidgets('caps the sheet at the dialog width, centred, at 1200px', (
      tester,
    ) async {
      // Arrange + Act
      await _openSheet(tester, const Size(1200, 800));

      // Assert
      final rect = tester.getRect(find.byKey(_probeKey));
      expect(rect.width, lessThanOrEqualTo(kSheetMaxWidth));
      expect(rect.center.dx, closeTo(600, 0.5));
    });

    testWidgets('is full width at 390px, as before the cap', (tester) async {
      // Arrange + Act
      await _openSheet(tester, const Size(390, 800));

      // Assert
      expect(tester.getRect(find.byKey(_probeKey)).width, 390);
    });

    testWidgets('shows a drag handle only when asked to', (tester) async {
      // Arrange + Act
      await _openSheet(tester, const Size(390, 800), showDragHandle: true);

      // Assert
      expect(_sheetHeight(tester), 200 + kMinInteractiveDimension);
    });

    testWidgets('shows no drag handle by default', (tester) async {
      // Arrange + Act
      await _openSheet(tester, const Size(390, 800));

      // Assert
      expect(_sheetHeight(tester), 200);
    });
  });
}
