import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/widgets/waiter_script_widget.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

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
  // handler that answers immediately stands in for it, recording every call
  // so a test can assert on exactly what was copied.
  late List<MethodCall> platformCalls;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    platformCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('WaiterScriptWidget', () {
    testWidgets('build shows a single-line script as one numbered line', (
      tester,
    ) async {
      // Arrange
      const script = 'Replace the fries with a green salad.';

      // Act
      await _pump(tester, const WaiterScriptWidget(script: script));

      // Assert: no newline in the script still yields exactly one
      // numbered line, not zero and not the raw string left unsplit.
      expect(find.text(script), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('build splits a multi-line script into numbered lines', (
      tester,
    ) async {
      // Arrange
      const script =
          'Replace the fries with a green salad.\n'
          'Ask for the sauce on the side.';

      // Act
      await _pump(tester, const WaiterScriptWidget(script: script));

      // Assert: each line is its own selectable line, numbered in order.
      expect(
        find.text('Replace the fries with a green salad.'),
        findsOneWidget,
      );
      expect(find.text('Ask for the sauce on the side.'), findsOneWidget);
      expect(find.byType(SelectableText), findsNWidgets(2));
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('build drops a stray trailing blank line from the count', (
      tester,
    ) async {
      // Arrange
      const script = 'Replace the fries with a green salad.\n';

      // Act
      await _pump(tester, const WaiterScriptWidget(script: script));

      // Assert: the trailing empty piece is not numbered "2".
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsNothing);
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
      await tester.tap(find.text(_en.waiterCardCopyButton));
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
      await tester.tap(find.text(_en.waiterCardCopyButton));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('tapping copy puts the plain script on the clipboard, not the '
        'numbering this widget draws around it', (tester) async {
      // Arrange
      const script =
          'Replace the fries with a green salad.\n'
          'Ask for the sauce on the side.';
      await _pump(tester, const WaiterScriptWidget(script: script));

      // Act
      await tester.tap(find.text(_en.waiterCardCopyButton));
      await tester.pumpAndSettle();

      // Assert: the clipboard call carries the script verbatim — with
      // its newline, and with no "1." / "2." numbering prepended.
      final setData = platformCalls.singleWhere(
        (call) => call.method == 'Clipboard.setData',
      );
      final arguments = setData.arguments as Map<Object?, Object?>;
      expect(arguments['text'], script);
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
