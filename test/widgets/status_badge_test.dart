import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/widgets/status_badge.dart';

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
  group('StatusBadge', () {
    testWidgets('build renders an icon alongside the label for every verdict', (
      tester,
    ) async {
      for (final verdict in DishVerdict.values) {
        // Arrange
        await _pump(tester, StatusBadge(verdict: verdict));

        // Act
        final icons = find.byType(Icon);
        final texts = find.byType(Text);

        // Assert: the icon is never the only signal — a colour-blind user
        // must be able to read the same verdict from the text alone.
        expect(icons, findsOneWidget);
        expect(texts, findsOneWidget);
      }
    });

    testWidgets('build shows verdictOrderAsIs label for orderAsIs', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, const StatusBadge(verdict: DishVerdict.orderAsIs));

      // Act & Assert
      expect(find.text('Order as-is'), findsOneWidget);
    });

    testWidgets('build shows verdictModifiable label for modifiable', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, const StatusBadge(verdict: DishVerdict.modifiable));

      // Act & Assert
      expect(find.text('Order with a change'), findsOneWidget);
    });

    testWidgets('build shows verdictNonKeto label for nonKeto', (tester) async {
      // Arrange
      await _pump(tester, const StatusBadge(verdict: DishVerdict.nonKeto));

      // Act & Assert
      expect(find.text('Not keto'), findsOneWidget);
    });

    testWidgets('build shows the Hebrew label in the he locale', (
      tester,
    ) async {
      // Arrange
      await _pump(
        tester,
        const StatusBadge(verdict: DishVerdict.nonKeto),
        locale: const Locale('he'),
      );

      // Act & Assert
      expect(find.text('לא קטוגני'), findsOneWidget);
    });
  });
}
