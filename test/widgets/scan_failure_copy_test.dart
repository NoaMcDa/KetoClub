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
