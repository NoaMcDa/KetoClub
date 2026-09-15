import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/screens/waiter_card_sheet.dart';
import 'package:ketoclub/widgets/waiter_script_widget.dart';

import '../fakes/fake_screen_brightness.dart';

/// A minimal, valid [Dish] named [name].
Dish _dish(String name) => Dish(
  id: name,
  name: name,
  description: '',
  price: 10,
  options: const <DishOption>[],
);

/// A [DishRow] for a dish named [name], with [modification] and
/// [netCarbsEstimate] carried by a [DishVerdict.modifiable] analysis when
/// [modification] is given, or no analysis at all otherwise.
DishRow _row(String name, {String? modification, double? netCarbsEstimate}) {
  return DishRow(
    dish: _dish(name),
    category: 'Mains',
    analysis: modification == null
        ? null
        : AnalysedDish(
            dishId: name,
            name: name,
            verdict: DishVerdict.modifiable,
            why: 'why',
            modification: modification,
            netCarbsEstimate: netCarbsEstimate,
          ),
  );
}

/// Pumps [child] inside a localised [MaterialApp] and a [Scaffold], the
/// shape every widget test in `test/widgets/` and `test/screens/` uses.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  // The widget test host has no real platform behind `SystemChannels.platform`,
  // so `Clipboard.setData`'s call would otherwise never resolve; a mock
  // handler that answers immediately stands in for it (mirrors
  // test/widgets/waiter_script_widget_test.dart).
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('WaiterCardSheet.new (single-row convenience)', () {
    testWidgets('build shows waiterCardTitle, the dish name and the script', (
      tester,
    ) async {
      // Arrange
      const script = 'Replace the fries with a green salad.';
      final row = _row('Grilled Salmon', modification: script);

      // Act
      await _pump(tester, WaiterCardSheet(row: row));

      // Assert
      expect(find.text('Say this to the waiter'), findsOneWidget);
      expect(find.text('Grilled Salmon'), findsOneWidget);
      expect(find.byType(WaiterScriptWidget), findsOneWidget);
      expect(find.text(script), findsOneWidget);
    });

    testWidgets('build shows no script section when the row has none', (
      tester,
    ) async {
      // Arrange
      final row = _row('Mystery bowl');

      // Act
      await _pump(tester, WaiterCardSheet(row: row));

      // Assert
      expect(find.text('Mystery bowl'), findsOneWidget);
      expect(find.byType(WaiterScriptWidget), findsNothing);
    });

    testWidgets('build shows no tabs for a single row', (tester) async {
      // Arrange
      final row = _row('Grilled Salmon', modification: 'Ask for a swap.');

      // Act
      await _pump(tester, WaiterCardSheet(row: row));

      // Assert
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('build shows no after-text when the estimate is absent', (
      tester,
    ) async {
      // Arrange
      final row = _row('Grilled Salmon', modification: 'Ask for a swap.');

      // Act
      await _pump(tester, WaiterCardSheet(row: row));

      // Assert: the missing-after-text case the acceptance criteria names.
      expect(find.textContaining('net carbs'), findsNothing);
    });

    testWidgets('build shows the after-text when an estimate is present', (
      tester,
    ) async {
      // Arrange
      final row = _row(
        'Grilled Salmon',
        modification: 'Ask for a swap.',
        netCarbsEstimate: 3.4,
      );

      // Act
      await _pump(tester, WaiterCardSheet(row: row));

      // Assert: rounded, and framed as an estimate — never a bare number
      // (issue #30, architecture.md §17.4).
      expect(find.textContaining('3g net carbs'), findsOneWidget);
      expect(find.textContaining('estimate'), findsOneWidget);
    });

    testWidgets('tapping copy shows the actionCopied confirmation', (
      tester,
    ) async {
      // Arrange
      const script = 'Ask for steamed vegetables instead of rice.';
      final row = _row('Roast Chicken', modification: script);
      await _pump(tester, WaiterCardSheet(row: row));

      // Act
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('build renders the dish name verbatim in the he locale', (
      tester,
    ) async {
      // Arrange
      const script = 'החליפו את הצ׳יפס בסלט ירוק.';
      final row = _row('Grilled Salmon', modification: script);

      // Act
      await _pump(
        tester,
        WaiterCardSheet(row: row),
        locale: const Locale('he'),
      );

      // Assert
      expect(find.text('זה מה שאומרים למלצר'), findsOneWidget);
      expect(find.text('Grilled Salmon'), findsOneWidget);
      expect(find.text(script), findsOneWidget);

      // Assert: this screen actually renders under RTL directionality for
      // the he locale, not merely with Hebrew strings under an LTR frame —
      // the layout-mirroring claim the acceptance criteria asks for.
      final context = tester.element(find.text('Grilled Salmon'));
      expect(Directionality.of(context), TextDirection.rtl);
    });

    testWidgets('raises the brightness on open and restores it on close', (
      tester,
    ) async {
      // Arrange
      final brightness = FakeScreenBrightness();
      final row = _row('Grilled Salmon', modification: 'Ask for a swap.');

      // Act: open.
      await _pump(
        tester,
        WaiterCardSheet(row: row, screenBrightness: brightness),
      );

      // Assert: raised exactly once, not yet restored.
      expect(brightness.raiseCount, 1);
      expect(brightness.restoreCount, 0);

      // Act: close, by pumping a tree that no longer holds the sheet.
      await _pump(tester, const SizedBox.shrink());

      // Assert
      expect(brightness.restoreCount, 1);
    });

    testWidgets('never raises the brightness with no screenBrightness given', (
      tester,
    ) async {
      // Arrange / Act: the convenience constructor's own default is a
      // no-op, so this must build and settle without ever throwing, even
      // though there is no brightness fake here to assert on.
      final row = _row('Grilled Salmon', modification: 'Ask for a swap.');
      await _pump(tester, WaiterCardSheet(row: row));

      // Assert
      expect(find.byType(WaiterCardSheet), findsOneWidget);
    });
  });

  group('WaiterCardSheet.forRows (multi-dish tabs)', () {
    testWidgets('shows a pill tab per row and opens on initialIndex', (
      tester,
    ) async {
      // Arrange
      final rows = [
        _row('Sea Bass', modification: 'Swap the purée for salad.'),
        _row('Chicken Thigh', modification: 'Swap the rice for salad.'),
      ];

      // Act
      await _pump(
        tester,
        WaiterCardSheet.forRows(
          rows: rows,
          screenBrightness: FakeScreenBrightness(),
          initialIndex: 1,
        ),
      );

      // Assert: both tab labels are on screen, and the second dish's own
      // name and script are what is showing as the open card.
      expect(find.byType(ChoiceChip), findsNWidgets(2));
      expect(find.text('Chicken Thigh'), findsWidgets);
      expect(find.text('Swap the rice for salad.'), findsOneWidget);
      expect(find.text('Swap the purée for salad.'), findsNothing);
    });

    testWidgets('tapping a tab switches to that dish', (tester) async {
      // Arrange
      final rows = [
        _row('Sea Bass', modification: 'Swap the purée for salad.'),
        _row('Chicken Thigh', modification: 'Swap the rice for salad.'),
      ];
      await _pump(
        tester,
        WaiterCardSheet.forRows(
          rows: rows,
          screenBrightness: FakeScreenBrightness(),
        ),
      );
      expect(find.text('Swap the purée for salad.'), findsOneWidget);

      // Act
      await tester.tap(find.text('Chicken Thigh').last);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Swap the rice for salad.'), findsOneWidget);
      expect(find.text('Swap the purée for salad.'), findsNothing);
    });

    testWidgets('clamps an out-of-range initialIndex to the last row', (
      tester,
    ) async {
      // Arrange
      final rows = [
        _row('Sea Bass', modification: 'Swap the purée for salad.'),
        _row('Chicken Thigh', modification: 'Swap the rice for salad.'),
      ];

      // Act
      await _pump(
        tester,
        WaiterCardSheet.forRows(
          rows: rows,
          screenBrightness: FakeScreenBrightness(),
          initialIndex: 99,
        ),
      );

      // Assert: no crash, and the last row is shown rather than none.
      expect(find.text('Swap the rice for salad.'), findsOneWidget);
    });

    testWidgets('mirrors the tab row under RTL: the first tab sits at the '
        'trailing edge, not the leading one', (tester) async {
      // Arrange
      final rows = [
        _row('Sea Bass', modification: 'Swap the purée for salad.'),
        _row('Chicken Thigh', modification: 'Swap the rice for salad.'),
      ];

      // Act
      await _pump(
        tester,
        WaiterCardSheet.forRows(
          rows: rows,
          screenBrightness: FakeScreenBrightness(),
        ),
        locale: const Locale('he'),
      );

      // Assert: under RTL, `Row` lays out its children right-to-left, so
      // the first tab in source order (Sea Bass) renders to the right of
      // the second (Chicken Thigh) rather than to its left, as it would
      // under LTR — real layout mirroring, not only Hebrew strings under
      // an LTR frame.
      final chips = find.byType(ChoiceChip);
      final firstTabX = tester.getTopLeft(chips.at(0)).dx;
      final secondTabX = tester.getTopLeft(chips.at(1)).dx;
      expect(firstTabX, greaterThan(secondTabX));
    });
  });
}
