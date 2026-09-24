import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/widgets/keto_score_badge.dart';

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
  group('KetoScoreBadge', () {
    testWidgets('build renders nothing when score is null — never a '
        'fallback 0.0', (tester) async {
      // Arrange & Act
      await _pump(tester, const KetoScoreBadge(score: null));

      // Assert
      expect(find.byType(Text), findsNothing);
      expect(find.text('0.0'), findsNothing);
    });

    testWidgets('build shows the score to one decimal place and its label', (
      tester,
    ) async {
      // Arrange & Act
      await _pump(tester, const KetoScoreBadge(score: 9.1));

      // Assert
      expect(find.text('9.1'), findsOneWidget);
      expect(find.text('KETO SCORE'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Keto score: 9.1 out of 10'),
        findsOneWidget,
      );
    });

    testWidgets('build shows the Hebrew label in the he locale', (
      tester,
    ) async {
      // Arrange & Act
      await _pump(
        tester,
        const KetoScoreBadge(score: 5),
        locale: const Locale('he'),
      );

      // Assert
      expect(find.text('5.0'), findsOneWidget);
      expect(find.text('ציון קטוגני'), findsOneWidget);
    });

    testWidgets('inline sets the label beside the score, not under it — the '
        'venue card layout', (tester) async {
      // Arrange & Act
      await _pump(
        tester,
        const Align(
          alignment: Alignment.topLeft,
          child: KetoScoreBadge(score: 9.1, inline: true),
        ),
      );

      // Assert: same row, label after the number.
      final number = tester.getRect(find.text('9.1'));
      final label = tester.getRect(find.text('KETO SCORE'));
      expect(label.left, greaterThan(number.right));
      expect(label.top, lessThan(number.bottom));
      expect(
        find.bySemanticsLabel('Keto score: 9.1 out of 10'),
        findsOneWidget,
      );
    });
  });
}
