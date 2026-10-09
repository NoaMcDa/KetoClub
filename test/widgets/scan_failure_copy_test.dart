import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/widgets/scan_failure_copy.dart';

void main() {
  group('scanFailureMessage', () {
    final languages = <String, AppLocalizations>{
      'en': AppLocalizationsEn(),
      'he': AppLocalizationsHe(),
    };

    for (final MapEntry(key: language, value: l10n) in languages.entries) {
      test('every reason has its own non-empty copy in $language', () {
        // Act
        final messages = [
          for (final reason in MenuAnalysisFailureReason.values)
            scanFailureMessage(reason, l10n, directToGoogle: false),
        ];

        // Assert
        expect(messages, everyElement(isNotEmpty));
        expect(messages.toSet(), hasLength(messages.length));
      });

      test('notConfigured differs between web and phones in $language', () {
        expect(
          scanFailureMessage(
            MenuAnalysisFailureReason.notConfigured,
            l10n,
            directToGoogle: true,
          ),
          isNot(
            scanFailureMessage(
              MenuAnalysisFailureReason.notConfigured,
              l10n,
              directToGoogle: false,
            ),
          ),
        );
      });

      test('with a backend, notConfigured names the server on web and '
          'phones alike, apart from both no-backend messages in $language '
          '(issue #331)', () {
        // Act
        String message({required bool direct, required bool backend}) =>
            scanFailureMessage(
              MenuAnalysisFailureReason.notConfigured,
              l10n,
              directToGoogle: direct,
              backendConfigured: backend,
            );

        // Assert
        expect(
          message(direct: true, backend: true),
          l10n.scanScreenFailureServerNotConfigured,
        );
        expect(
          message(direct: false, backend: true),
          l10n.scanScreenFailureServerNotConfigured,
        );
        expect(<String>{
          l10n.scanScreenFailureServerNotConfigured,
          message(direct: true, backend: false),
          message(direct: false, backend: false),
        }, hasLength(3));
      });

      test('with a backend every reason still has its own copy in '
          '$language', () {
        // Act
        final messages = [
          for (final reason in MenuAnalysisFailureReason.values)
            scanFailureMessage(
              reason,
              l10n,
              directToGoogle: true,
              backendConfigured: true,
            ),
        ];

        // Assert
        expect(messages, everyElement(isNotEmpty));
        expect(messages.toSet(), hasLength(messages.length));
      });

      test('no scan message promises rule-based results in $language', () {
        // A photograph has no rules fallback (architecture.md D15).
        for (final reason in MenuAnalysisFailureReason.values) {
          expect(
            scanFailureMessage(reason, l10n, directToGoogle: false),
            isNot(contains('rule-based')),
          );
        }
      });
    }
  });
}
