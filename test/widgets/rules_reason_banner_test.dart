import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/widgets/failure_copy.dart';
import 'package:ketoclub/widgets/rules_reason_banner.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the widget under test does.
final AppLocalizations _en = AppLocalizationsEn();

/// Pumps [child] inside a localised [MaterialApp] with [pushedNames]
/// recording every route pushed onto it, the shape every widget test that
/// exercises navigation in this repository uses.
Future<void> _pump(
  WidgetTester tester,
  Widget child,
  List<String> pushedNames,
) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
      onGenerateRoute: (settings) {
        pushedNames.add(settings.name ?? '');
        return MaterialPageRoute<void>(
          builder: (_) => const SizedBox.shrink(),
          settings: settings,
        );
      },
    ),
  );
}

void main() {
  group('RulesReasonBanner', () {
    testWidgets('renders nothing for an LlmEngine result', (tester) async {
      // Arrange
      final pushedNames = <String>[];

      // Act
      await _pump(
        tester,
        const RulesReasonBanner(engine: LlmEngine(model: 'test/model')),
        pushedNames,
      );

      // Assert: no banner surface, no message text from either enum's
      // copy could plausibly appear.
      expect(find.byType(RulesReasonBanner), findsOneWidget);
      for (final reason in MenuAnalysisFailureReason.values) {
        expect(find.text(analysisFailureMessage(reason, _en)), findsNothing);
      }
      expect(find.text(_en.actionOpenSettings), findsNothing);
    });

    for (final reason in MenuAnalysisFailureReason.values) {
      testWidgets(
        'renders analysisFailureMessage for RulesEngine reason $reason',
        (tester) async {
          // Arrange
          final pushedNames = <String>[];

          // Act
          await _pump(
            tester,
            RulesReasonBanner(engine: RulesEngine(reason: reason)),
            pushedNames,
          );

          // Assert
          expect(
            find.text(analysisFailureMessage(reason, _en)),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets('offers a Settings action only for consentWithheld, tapping it '
        'pushes the settings route', (tester) async {
      // Arrange
      final pushedNames = <String>[];

      // Act
      await _pump(
        tester,
        const RulesReasonBanner(
          engine: RulesEngine(
            reason: MenuAnalysisFailureReason.consentWithheld,
          ),
        ),
        pushedNames,
      );

      // Assert: the action is present.
      expect(find.text(_en.actionOpenSettings), findsOneWidget);

      // Act: tap it.
      await tester.tap(find.text(_en.actionOpenSettings));
      await tester.pumpAndSettle();

      // Assert
      expect(pushedNames, contains('/settings'));
    });

    testWidgets('every other reason offers no Settings action', (tester) async {
      for (final reason in MenuAnalysisFailureReason.values) {
        if (reason == MenuAnalysisFailureReason.consentWithheld) continue;

        // Arrange
        final pushedNames = <String>[];

        // Act
        await _pump(
          tester,
          RulesReasonBanner(engine: RulesEngine(reason: reason)),
          pushedNames,
        );

        // Assert
        expect(
          find.text(_en.actionOpenSettings),
          findsNothing,
          reason: '$reason must not offer the Settings shortcut',
        );
      }
    });
  });
}
