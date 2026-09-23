import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/widgets/failure_copy.dart';

const _locales = [Locale('en'), Locale('he')];

void main() {
  group('fetchFailureMessage', () {
    for (final locale in _locales) {
      test('returns a non-empty message for every reason in $locale', () {
        // Arrange
        final l10n = lookupAppLocalizations(locale);

        // Act & Assert
        for (final reason in MenuFetchFailureReason.values) {
          final message = fetchFailureMessage(
            reason,
            l10n,
            platform: 'Wolt',
            statusCode: 502,
          );
          expect(
            message,
            isNotEmpty,
            reason: '$reason should have copy in ${locale.languageCode}',
          );
        }
      });

      test('gives every reason its own copy in ${locale.languageCode}', () {
        // Arrange
        final l10n = lookupAppLocalizations(locale);

        // Act
        final messages = [
          for (final reason in MenuFetchFailureReason.values)
            fetchFailureMessage(
              reason,
              l10n,
              platform: 'Wolt',
              statusCode: 502,
            ),
        ];

        // Assert: collapsing reasons is a bug (architecture.md §10).
        expect(messages.toSet(), hasLength(messages.length));
      });
    }
  });

  group('analysisFailureMessage', () {
    for (final locale in _locales) {
      test('returns a non-empty message for every reason in $locale', () {
        // Arrange
        final l10n = lookupAppLocalizations(locale);

        // Act & Assert
        for (final reason in MenuAnalysisFailureReason.values) {
          final message = analysisFailureMessage(
            reason,
            l10n,
            detail: 'unexpected shape',
          );
          expect(
            message,
            isNotEmpty,
            reason: '$reason should have copy in ${locale.languageCode}',
          );
        }
      });

      test('gives every reason its own copy in ${locale.languageCode}', () {
        // Arrange
        final l10n = lookupAppLocalizations(locale);

        // Act
        final messages = [
          for (final reason in MenuAnalysisFailureReason.values)
            analysisFailureMessage(reason, l10n, detail: 'unexpected shape'),
        ];

        // Assert: collapsing reasons is a bug (architecture.md §10).
        expect(messages.toSet(), hasLength(messages.length));
      });
    }
  });

  group('fetchFailureMessage and analysisFailureMessage together', () {
    for (final locale in _locales) {
      test('never share copy across the two failure enums in $locale', () {
        // Arrange
        final l10n = lookupAppLocalizations(locale);

        // Act
        final fetchMessages = [
          for (final reason in MenuFetchFailureReason.values)
            fetchFailureMessage(
              reason,
              l10n,
              platform: 'Wolt',
              statusCode: 502,
            ),
        ];
        final analysisMessages = [
          for (final reason in MenuAnalysisFailureReason.values)
            analysisFailureMessage(reason, l10n, detail: 'unexpected shape'),
        ];

        // Assert
        final all = [...fetchMessages, ...analysisMessages];
        expect(all.toSet(), hasLength(all.length));
      });
    }
  });

  group('the no-internet copy is exclusive to offline', () {
    for (final locale in _locales) {
      test('fetchFailureMessage: only offline returns the no-internet copy '
          'in ${locale.languageCode}', () {
        // Arrange
        final l10n = lookupAppLocalizations(locale);
        final offlineCopy = fetchFailureMessage(
          MenuFetchFailureReason.offline,
          l10n,
        );

        // Act & Assert
        for (final reason in MenuFetchFailureReason.values) {
          final message = fetchFailureMessage(
            reason,
            l10n,
            platform: 'Wolt',
            statusCode: 502,
          );
          if (reason == MenuFetchFailureReason.offline) {
            expect(message, equals(offlineCopy));
          } else {
            expect(
              message,
              isNot(equals(offlineCopy)),
              reason: '$reason must not share the no-internet copy',
            );
          }
        }
      });

      test('analysisFailureMessage: only offline returns the no-internet '
          'copy in ${locale.languageCode}', () {
        // Arrange
        final l10n = lookupAppLocalizations(locale);
        final offlineCopy = analysisFailureMessage(
          MenuAnalysisFailureReason.offline,
          l10n,
        );

        // Act & Assert
        for (final reason in MenuAnalysisFailureReason.values) {
          final message = analysisFailureMessage(
            reason,
            l10n,
            detail: 'unexpected shape',
          );
          if (reason == MenuAnalysisFailureReason.offline) {
            expect(message, equals(offlineCopy));
          } else {
            expect(
              message,
              isNot(equals(offlineCopy)),
              reason: '$reason must not share the no-internet copy',
            );
          }
        }
      });
    }
  });
}
