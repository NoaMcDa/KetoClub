import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/widgets/engine_chip.dart';

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
  group('EngineChip', () {
    testWidgets('build shows engineChipAi and an icon for LlmEngine', (
      tester,
    ) async {
      // Arrange
      await _pump(
        tester,
        const EngineChip(engine: LlmEngine(model: 'test/model')),
      );

      // Act & Assert
      expect(find.text('AI'), findsOneWidget);
      expect(find.byType(Icon), findsOneWidget);
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets(
      'build shows engineChipRules and the rulesNotVerifiedHint tooltip',
      (tester) async {
        // Arrange
        await _pump(
          tester,
          const EngineChip(
            engine: RulesEngine(
              reason: MenuAnalysisFailureReason.notConfigured,
            ),
          ),
        );

        // Act
        final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));

        // Assert
        expect(find.text('Rules'), findsOneWidget);
        expect(find.byType(Icon), findsOneWidget);
        expect(tooltip.message, 'Rule-based result, not AI-verified.');
      },
    );

    testWidgets('build shows the Hebrew labels in the he locale', (
      tester,
    ) async {
      // Arrange
      await _pump(
        tester,
        const EngineChip(
          engine: RulesEngine(reason: MenuAnalysisFailureReason.offline),
        ),
        locale: const Locale('he'),
      );

      // Act & Assert
      expect(find.text('כללים'), findsOneWidget);
    });
  });
}
