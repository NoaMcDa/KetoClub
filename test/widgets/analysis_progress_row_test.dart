import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/widgets/analysis_progress_row.dart';

/// The English strings a test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The Hebrew strings for the Locale('he') test.
final AppLocalizations _he = AppLocalizationsHe();

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
  group('AnalysisProgressRow', () {
    for (final phase in [LoadPhase.idle, LoadPhase.fetching]) {
      testWidgets('build renders nothing for ${phase.name}', (tester) async {
        // Arrange
        await _pump(tester, AnalysisProgressRow(phase: phase));

        // Assert
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(Text), findsNothing);
      });
    }

    final expectedCopy = <LoadPhase, String>{
      LoadPhase.classifying: _en.menuProgressAnalysing,
      LoadPhase.classifyingLlm: _en.menuProgressAskingAi,
      LoadPhase.classifyingRules: _en.menuProgressApplyingRules,
    };
    for (final entry in expectedCopy.entries) {
      testWidgets('build shows a spinner and "${entry.value}" for '
          '${entry.key.name}', (tester) async {
        // Arrange
        await _pump(tester, AnalysisProgressRow(phase: entry.key));

        // Assert
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text(entry.value), findsOneWidget);
      });
    }

    test('the three classifying labels are distinct in both languages', () {
      // Arrange
      final english = {
        _en.menuProgressAnalysing,
        _en.menuProgressAskingAi,
        _en.menuProgressApplyingRules,
      };
      final hebrew = {
        _he.menuProgressAnalysing,
        _he.menuProgressAskingAi,
        _he.menuProgressApplyingRules,
      };

      // Assert
      expect(english, hasLength(3));
      expect(hebrew, hasLength(3));
    });

    testWidgets('build shows Hebrew copy under the he locale', (tester) async {
      // Arrange
      await _pump(
        tester,
        const AnalysisProgressRow(phase: LoadPhase.classifyingLlm),
        locale: const Locale('he'),
      );

      // Assert
      expect(find.text(_he.menuProgressAskingAi), findsOneWidget);
    });
  });
}
