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

      // Act & Assert: "AI" is still its own Text widget (so it stays
      // findable by itself, as `settings_key_flow_test.dart` relies on),
      // but a sibling Text carries the model, so the chip reads "AI ·
      // test/model" — issue #30.
      expect(find.text('AI'), findsOneWidget);
      expect(find.text(' · test/model'), findsOneWidget);
      expect(find.byType(Icon), findsOneWidget);
      expect(find.byType(Tooltip), findsNothing);
      expect(
        find.bySemanticsLabel('AI engine, model test/model'),
        findsOneWidget,
      );
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

        // Assert: the reason ("no key" for notConfigured) is shown right
        // on the chip, not only in the tooltip — issue #30.
        expect(find.text('Rules'), findsOneWidget);
        expect(find.text(' (no key)'), findsOneWidget);
        expect(find.byType(Icon), findsOneWidget);
        expect(tooltip.message, 'Rule-based result, not AI-verified.');
        expect(
          find.bySemanticsLabel('Rules engine, not AI-verified: no key'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'build shows the offline reason on the chip for the offline reason',
      (tester) async {
        // Arrange
        await _pump(
          tester,
          const EngineChip(
            engine: RulesEngine(reason: MenuAnalysisFailureReason.offline),
          ),
        );

        // Act & Assert
        expect(find.text(' (offline)'), findsOneWidget);
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
      expect(find.text(' (לא מקוון)'), findsOneWidget);
    });
  });
}
