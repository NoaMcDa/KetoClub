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
      // findable by itself, as the flow tests rely on),
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

        // Assert: the reason ("not configured" for notConfigured) is
        // shown right on the chip, not only in the tooltip — issue #30.
        expect(find.text('Rules'), findsOneWidget);
        expect(find.text(' (not configured)'), findsOneWidget);
        expect(find.byType(Icon), findsOneWidget);
        expect(tooltip.message, 'Rule-based result, not AI-verified.');
        expect(
          find.bySemanticsLabel(
            'Rules engine, not AI-verified: not configured',
          ),
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

    testWidgets(
      'build shows the server-unreachable reason for backendUnreachable',
      (tester) async {
        // Arrange
        await _pump(
          tester,
          const EngineChip(
            engine: RulesEngine(
              reason: MenuAnalysisFailureReason.backendUnreachable,
            ),
          ),
        );

        // Act & Assert
        expect(find.text(' (server unreachable)'), findsOneWidget);
      },
    );

    testWidgets('build shows the AI-not-allowed reason for consentWithheld', (
      tester,
    ) async {
      // Arrange
      await _pump(
        tester,
        const EngineChip(
          engine: RulesEngine(
            reason: MenuAnalysisFailureReason.consentWithheld,
          ),
        ),
      );

      // Act & Assert
      expect(find.text(' (AI not allowed)'), findsOneWidget);
    });

    testWidgets('every reason gets its own chip label', (tester) async {
      // Arrange
      final labels = <String>{};

      // Act
      for (final reason in MenuAnalysisFailureReason.values) {
        await _pump(tester, EngineChip(engine: RulesEngine(reason: reason)));
        final texts = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .where((d) => d.startsWith(' ('));
        labels.addAll(texts);
      }

      // Assert: collapsing reasons is a bug (architecture.md §10).
      expect(labels, hasLength(MenuAnalysisFailureReason.values.length));
    });

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
