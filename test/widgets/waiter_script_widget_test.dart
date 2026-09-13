import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/widgets/waiter_script_widget.dart';

/// Pumps [child] inside a localised [MaterialApp] and a [Scaffold], the
/// shape every widget test in `test/widgets/` uses.
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
  // handler that answers immediately stands in for it.
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

  group('WaiterScriptWidget', () {
    testWidgets('build renders the script as selectable text', (tester) async {
      // Arrange
      const script = 'Replace the fries with a green salad.';

      // Act
      await _pump(tester, const WaiterScriptWidget(script: script));

      // Assert
      expect(find.text(script), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('tapping copy invokes onCopied', (tester) async {
      // Arrange
      const script = 'Ask for steamed vegetables instead of rice.';
      var copiedCount = 0;
      await _pump(
        tester,
        WaiterScriptWidget(script: script, onCopied: () => copiedCount++),
      );

      // Act
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      // Assert
      expect(copiedCount, 1);
    });

    testWidgets('tapping copy shows the actionCopied confirmation', (
      tester,
    ) async {
      // Arrange
      const script = 'Ask for steamed vegetables instead of rice.';
      await _pump(tester, const WaiterScriptWidget(script: script));

      // Act
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('build renders correctly in the he locale', (tester) async {
      // Arrange
      const script = 'החליפו את הצ׳יפס בסלט ירוק.';

      // Act
      await _pump(
        tester,
        const WaiterScriptWidget(script: script),
        locale: const Locale('he'),
      );

      // Assert
      expect(find.text(script), findsOneWidget);
    });
  });
}
