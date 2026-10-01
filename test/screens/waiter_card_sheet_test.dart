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
    testWidgets('Done pops the sheet and the close button stays', (
      tester,
    ) async {
      // Arrange: a route that pushes the sheet.
      final row = _row('Grilled Salmon', modification: 'Ask for a swap.');
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(body: WaiterCardSheet(row: row)),
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

      // Assert: both controls are present.
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);

      // Act
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(WaiterCardSheet), findsNothing);
    });

    testWidgets('Done stays on screen when the content is taller than the '
        'viewport', (tester) async {
      // Arrange
      tester.view.physicalSize = const Size(400, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final row = _row(
        'Grilled Salmon',
        modification: List.generate(12, (i) => 'Step number $i').join('\n'),
      );

      // Act
      await _pump(tester, WaiterCardSheet(row: row));

      // Assert: pinned, so visible without scrolling.
      final done = tester.getRect(find.widgetWithText(FilledButton, 'Done'));
      expect(done.bottom, lessThanOrEqualTo(500));
    });

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

    testWidgets(
      'build does not overflow at a 2x text scale on a narrow phone width '
      '(architecture.md §8.3)',
      (tester) async {
        // Arrange: a long dish name, a multi-line script and the
        // net-carb after-text together — the busiest shape this sheet
        // renders — on a 320-wide surface, a small phone, at 2x text
        // scale.
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final row = _row(
          'Grilled Sea Bass with Roasted Root Vegetable Medley',
          modification:
              'Replace the mashed potatoes with a green salad or steamed '
              'vegetables.\n'
              'Ask for the sauce to be served on the side.',
          netCarbsEstimate: 6.4,
        );

        // Act
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: WaiterCardSheet(row: row),
                ),
              ),
            ),
          ),
        );

        // Assert
        expect(tester.takeException(), isNull);
      },
    );

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
  });

  // ---------------------------------------------------------------------------
  // Hidden-carbs panel (issue #213)
  // ---------------------------------------------------------------------------

  group('_HiddenCarbsPanel', () {
    DishRow rowWithFlags(List<HiddenCarb> flags) => DishRow(
      dish: _dish('Grilled Salmon'),
      category: 'Mains',
      analysis: AnalysedDish(
        dishId: 'Grilled Salmon',
        name: 'Grilled Salmon',
        verdict: DishVerdict.modifiable,
        why: 'Suspicious glaze',
        modification: 'Ask for the glaze on the side',
        hiddenCarbs: flags,
      ),
    );

    testWidgets('panel is visible when the dish has hidden-carb flags', (
      tester,
    ) async {
      // Arrange
      const flag = HiddenCarb(
        source: 'house glaze',
        certainty: HiddenCarbCertainty.likely,
        waiterQuestion: 'Is the glaze sugar-free?',
      );
      final row = rowWithFlags([flag]);

      // Act
      await _pump(tester, WaiterCardSheet(row: row));

      // Assert
      expect(find.text('Possible hidden carbs'), findsOneWidget);
      expect(find.text('house glaze'), findsOneWidget);
      expect(find.text('Is the glaze sugar-free?'), findsOneWidget);
    });

    testWidgets('panel is not shown when the dish has no flags', (
      tester,
    ) async {
      // Arrange — yellow dish with no hidden-carb flags
      final row = _row('Grilled Salmon', modification: 'No fries please.');

      // Act
      await _pump(tester, WaiterCardSheet(row: row));

      // Assert
      expect(find.text('Possible hidden carbs'), findsNothing);
    });
  });
}
