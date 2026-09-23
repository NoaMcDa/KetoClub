import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/widgets/fetch_failure_action.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the widget under test does.
final AppLocalizations _en = AppLocalizationsEn();

/// Pumps [child] inside a localised [MaterialApp].
Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('FetchFailureAction', () {
    for (final reason in [
      MenuFetchFailureReason.offline,
      MenuFetchFailureReason.backendUnreachable,
    ]) {
      testWidgets('renders a Retry button that calls onRetry for $reason', (
        tester,
      ) async {
        // Arrange
        var retried = false;
        var wentBack = false;

        // Act
        await _pump(
          tester,
          FetchFailureAction(
            reason: reason,
            onRetry: () => retried = true,
            onBackToSearch: () => wentBack = true,
          ),
        );
        await tester.tap(find.text(_en.actionRetry));
        await tester.pump();

        // Assert
        expect(retried, isTrue);
        expect(wentBack, isFalse);
        expect(find.text(_en.actionBackToSearch), findsNothing);
      });
    }

    for (final reason in [
      MenuFetchFailureReason.notFound,
      MenuFetchFailureReason.platformChanged,
      MenuFetchFailureReason.unsupportedSource,
    ]) {
      testWidgets(
        'renders a Back to search button that calls onBackToSearch for '
        '$reason',
        (tester) async {
          // Arrange
          var retried = false;
          var wentBack = false;

          // Act
          await _pump(
            tester,
            FetchFailureAction(
              reason: reason,
              onRetry: () => retried = true,
              onBackToSearch: () => wentBack = true,
            ),
          );
          await tester.tap(find.text(_en.actionBackToSearch));
          await tester.pump();

          // Assert
          expect(wentBack, isTrue);
          expect(retried, isFalse);
          expect(find.text(_en.actionRetry), findsNothing);
        },
      );
    }

    testWidgets('renders nothing for blockedByBrowser', (tester) async {
      // Act
      await _pump(
        tester,
        const FetchFailureAction(
          reason: MenuFetchFailureReason.blockedByBrowser,
        ),
      );

      // Assert
      expect(find.text(_en.actionRetry), findsNothing);
      expect(find.text(_en.actionBackToSearch), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
    });
  });
}
