import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/theme/verdict_colors.dart';
import 'package:ketoclub/widgets/app_notice.dart';

/// The text every notice under test carries.
const String _message = 'The AI engine did not answer, so rules decided.';

/// Pumps [notice] at [width] logical pixels wide under [theme].
Future<void> _pump(
  WidgetTester tester,
  Widget notice, {
  double width = 800,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: Scaffold(body: notice),
    ),
  );
}

/// The box an [AppNotice] draws its background in, when it draws one.
BoxDecoration _decorationOf(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byType(AppNotice),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return box.decoration as BoxDecoration;
}

/// The colour [_message] is drawn in.
Color? _messageColor(WidgetTester tester) =>
    tester.widget<Text>(find.text(_message)).style?.color;

void main() {
  group('AppNotice.decision', () {
    testWidgets('shows the title, the body, a filled primary and an outlined '
        'secondary button, each running its own callback', (tester) async {
      // Arrange
      var primaryTaps = 0;
      var secondaryTaps = 0;
      await _pump(
        tester,
        AppNotice.decision(
          title: 'Title',
          message: _message,
          primary: AppNoticeAction(label: 'OK', onPressed: () => primaryTaps++),
          secondary: AppNoticeAction(
            label: 'Turn off',
            onPressed: () => secondaryTaps++,
          ),
        ),
      );

      // Act
      await tester.tap(find.widgetWithText(FilledButton, 'OK'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Turn off'));

      // Assert
      expect(find.text('Title'), findsOneWidget);
      expect(find.text(_message), findsOneWidget);
      expect(primaryTaps, 1);
      expect(secondaryTaps, 1);
      expect(
        tester.widget<AppNotice>(find.byType(AppNotice)).kind,
        AppNoticeKind.decision,
      );
    });

    testWidgets('is a surface card, not the grey info box', (tester) async {
      // Act
      await _pump(
        tester,
        const AppNotice.decision(
          title: 'Title',
          message: _message,
          primary: AppNoticeAction(label: 'OK', onPressed: null),
        ),
      );

      // Assert
      final colorScheme = AppTheme.light().colorScheme;
      expect(_decorationOf(tester).color, colorScheme.surface);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('a null onPressed renders the button disabled', (tester) async {
      // Act
      await _pump(
        tester,
        const AppNotice.decision(
          title: 'Title',
          message: _message,
          primary: AppNoticeAction(label: 'OK', onPressed: null),
        ),
      );

      // Assert
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  });

  group('AppNotice.info', () {
    testWidgets('is one muted line with an icon and no box', (tester) async {
      // Act
      await _pump(tester, const AppNotice.info(message: _message));

      // Assert
      final muted = AppTheme.light().colorScheme.onSurfaceVariant;
      expect(_messageColor(tester), muted);
      expect(tester.widget<Icon>(find.byIcon(Icons.info_outline)).color, muted);
      expect(
        find.descendant(
          of: find.byType(AppNotice),
          matching: find.byType(DecoratedBox),
        ),
        findsNothing,
      );
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('a wide notice keeps its actions on the text row', (
      tester,
    ) async {
      // Arrange
      var retried = false;
      await _pump(
        tester,
        AppNotice.info(
          message: _message,
          actions: [
            AppNoticeAction(label: 'Retry', onPressed: () => retried = true),
          ],
        ),
      );

      // Act
      await tester.tap(find.text('Retry'));

      // Assert
      final text = tester.getRect(find.text(_message));
      final button = tester.getRect(find.byType(TextButton));
      expect(retried, isTrue);
      expect(button.left, greaterThanOrEqualTo(text.right));
      expect(button.top, lessThan(text.bottom));
    });

    testWidgets('a phone-width notice moves its actions under the text, so '
        'they never squeeze it (issue #234)', (tester) async {
      // Act
      await _pump(
        tester,
        const AppNotice.info(
          message: _message,
          actions: [
            AppNoticeAction(label: 'Open Settings', onPressed: null),
            AppNoticeAction(label: 'Retry', onPressed: null),
          ],
        ),
        width: 390,
      );

      // Assert
      final text = tester.getRect(find.text(_message));
      final notice = tester.getRect(find.byType(AppNotice));
      for (final label in ['Open Settings', 'Retry']) {
        final button = tester.getRect(find.widgetWithText(TextButton, label));
        expect(button.top, greaterThanOrEqualTo(text.bottom));
      }
      // The text keeps the row's full width beside the icon.
      expect(text.width, greaterThan(300));
      expect(notice.height, lessThan(120));
    });
  });

  group('AppNotice.warning', () {
    for (final entry in {
      'light': (AppTheme.light(), VerdictColors.light()),
      'dark': (AppTheme.dark(), VerdictColors.dark()),
    }.entries) {
      testWidgets('draws amber ink on the amber tint under the ${entry.key} '
          'theme', (tester) async {
        // Arrange
        final (theme, verdicts) = entry.value;

        // Act
        await _pump(
          tester,
          const AppNotice.warning(message: _message, icon: Icons.wifi_off),
          theme: theme,
        );

        // Assert
        expect(_decorationOf(tester).color, verdicts.amber.tint);
        expect(_messageColor(tester), verdicts.amber.ink);
        expect(
          tester.widget<Icon>(find.byIcon(Icons.wifi_off)).color,
          verdicts.amber.ink,
        );
        expect(
          tester.widget<AppNotice>(find.byType(AppNotice)).kind,
          AppNoticeKind.warning,
        );
      });
    }
  });
}
