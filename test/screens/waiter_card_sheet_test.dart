import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/screens/waiter_card_sheet.dart';
import 'package:ketoclub/widgets/waiter_script_widget.dart';

/// A minimal, valid [Dish] named [name].
Dish _dish(String name) => Dish(
  id: 'd1',
  name: name,
  description: '',
  price: 10,
  options: const <DishOption>[],
);

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

  group('WaiterCardSheet', () {
    testWidgets(
      'build shows waiterCardTitle the dish name and the script text',
      (tester) async {
        // Arrange
        const script = 'Replace the fries with a green salad.';
        final row = DishRow(
          dish: _dish('Grilled Salmon'),
          category: 'Mains',
          analysis: const AnalysedDish(
            dishId: 'd1',
            name: 'Grilled Salmon',
            verdict: DishVerdict.modifiable,
            why: 'Mostly protein, with a starchy side to swap.',
            modification: script,
          ),
        );

        // Act
        await _pump(tester, WaiterCardSheet(row: row));

        // Assert
        expect(find.text('Say this to the waiter'), findsOneWidget);
        expect(find.text('Grilled Salmon'), findsOneWidget);
        expect(find.byType(WaiterScriptWidget), findsOneWidget);
        expect(find.text(script), findsOneWidget);
      },
    );

    testWidgets(
      'build shows no script section when the row has no modification',
      (tester) async {
        // Arrange
        final row = DishRow(dish: _dish('Mystery bowl'), category: 'Mains');

        // Act
        await _pump(tester, WaiterCardSheet(row: row));

        // Assert
        expect(find.text('Mystery bowl'), findsOneWidget);
        expect(find.byType(WaiterScriptWidget), findsNothing);
      },
    );

    testWidgets('tapping copy shows the actionCopied confirmation', (
      tester,
    ) async {
      // Arrange
      const script = 'Ask for steamed vegetables instead of rice.';
      final row = DishRow(
        dish: _dish('Roast Chicken'),
        category: 'Mains',
        analysis: const AnalysedDish(
          dishId: 'd1',
          name: 'Roast Chicken',
          verdict: DishVerdict.modifiable,
          why: 'Protein with a starchy side to swap.',
          modification: script,
        ),
      );
      await _pump(tester, WaiterCardSheet(row: row));

      // Act
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('build renders the dish name verbatim in the he locale', (
      tester,
    ) async {
      // Arrange
      const script = 'החליפו את הצ׳יפס בסלט ירוק.';
      final row = DishRow(
        dish: _dish('Grilled Salmon'),
        category: 'Mains',
        analysis: const AnalysedDish(
          dishId: 'd1',
          name: 'Grilled Salmon',
          verdict: DishVerdict.modifiable,
          why: 'why',
          modification: script,
        ),
      );

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
    });
  });
}
