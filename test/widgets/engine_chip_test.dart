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
      'build shows engineChipRules and the rulesNotVerifiedHint tooltip, '
      'no reason phrase (issue #169)',
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

        // Assert: the chip carries only "Rules" plus the tooltip. The
        // reason lives beside this chip in `RulesReasonBanner` now; the
        // chip and the banner used to say the same thing twice.
        expect(find.text('Rules'), findsOneWidget);
        expect(find.textContaining('not configured'), findsNothing);
        expect(find.byType(Icon), findsOneWidget);
        expect(tooltip.message, 'Rule-based result, not AI-verified.');
        expect(
          find.bySemanticsLabel('Rule-based result, not AI-verified.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the chip carries no reason phrase regardless of the RulesEngine reason',
      (tester) async {
        for (final reason in MenuAnalysisFailureReason.values) {
          await _pump(tester, EngineChip(engine: RulesEngine(reason: reason)));

          // Assert: no `(reason)` phrase in either language on any reason
          // — the banner owns that copy now (issue #169).
          final withParens = tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data ?? '')
              .where((d) => d.startsWith(' ('));
          expect(
            withParens,
            isEmpty,
            reason:
                'RulesEngine reason $reason must not restate the reason '
                'on the chip',
          );
        }
      },
    );

    testWidgets('build shows the Hebrew "Rules" label in the he locale', (
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

      // Act & Assert: no `(reason)` phrase; only the engine name.
      expect(find.text('כללים'), findsOneWidget);
      expect(find.textContaining(' ('), findsNothing);
    });
  });
}
