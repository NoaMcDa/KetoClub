import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu_question.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';
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

  group('venueSearchFailureMessage (issue #39)', () {
    for (final locale in _locales) {
      test('returns a non-empty message for every reason in $locale', () {
        // Arrange
        final l10n = lookupAppLocalizations(locale);

        // Act & Assert
        for (final reason in VenueSearchFailureReason.values) {
          expect(
            venueSearchFailureMessage(reason, l10n),
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
          for (final reason in VenueSearchFailureReason.values)
            venueSearchFailureMessage(reason, l10n),
        ];

        // Assert: collapsing reasons is a bug (architecture.md §10).
        expect(messages.toSet(), hasLength(messages.length));
      });
    }

    test('the English and Hebrew copy differ for every reason', () {
      // Arrange
      final en = lookupAppLocalizations(const Locale('en'));
      final he = lookupAppLocalizations(const Locale('he'));

      // Act & Assert
      for (final reason in VenueSearchFailureReason.values) {
        expect(
          venueSearchFailureMessage(reason, he),
          isNot(equals(venueSearchFailureMessage(reason, en))),
          reason: '$reason is not translated',
        );
      }
    });
  });

  group('fetch, analysis and venue-search copy together', () {
    for (final locale in _locales) {
      test('never share copy across the three failure enums in $locale', () {
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

        final venueSearchMessages = [
          for (final reason in VenueSearchFailureReason.values)
            venueSearchFailureMessage(reason, l10n),
        ];

        // Assert
        final all = [
          ...fetchMessages,
          ...analysisMessages,
          ...venueSearchMessages,
        ];
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

  group('analysisFailureMessage without a detail (issue #189)', () {
    for (final locale in _locales) {
      test('badResponse with no detail has no empty parentheses in '
          '${locale.languageCode}', () {
        // Arrange
        final l10n = lookupAppLocalizations(locale);

        // Act
        final absent = analysisFailureMessage(
          MenuAnalysisFailureReason.badResponse,
          l10n,
        );
        final blank = analysisFailureMessage(
          MenuAnalysisFailureReason.badResponse,
          l10n,
          detail: '   ',
        );

        // Assert
        expect(absent, isNotEmpty);
        expect(absent, isNot(contains('()')));
        expect(absent, isNot(contains('( )')));
        expect(blank, equals(absent));
      });

      test('the detail-free copy is still distinct from every other reason '
          'in ${locale.languageCode}', () {
        // Arrange
        final l10n = lookupAppLocalizations(locale);

        // Act
        final messages = [
          for (final reason in MenuAnalysisFailureReason.values)
            analysisFailureMessage(reason, l10n),
        ];

        // Assert: collapsing reasons is a bug (architecture.md §10).
        expect(messages.toSet(), hasLength(messages.length));
      });

      test('a real detail is still rendered in ${locale.languageCode}', () {
        // Arrange
        final l10n = lookupAppLocalizations(locale);

        // Act
        final message = analysisFailureMessage(
          MenuAnalysisFailureReason.badResponse,
          l10n,
          detail: 'unexpected shape',
        );

        // Assert
        expect(message, contains('(unexpected shape)'));
      });
    }
  });

  group('menuQuestionFailureMessage (architecture.md §9.5; issue #214)', () {
    for (final locale in _locales) {
      test('returns a non-empty message for every reason in $locale', () {
        // Arrange
        final l10n = lookupAppLocalizations(locale);

        // Act & Assert
        for (final reason in MenuQuestionFailureReason.values) {
          expect(
            menuQuestionFailureMessage(reason, l10n),
            isNotEmpty,
            reason: '$reason should have copy in ${locale.languageCode}',
          );
        }
      });

      test('9 of 10 question reasons have distinct copy in '
          '${locale.languageCode} (badResponse and noDishesFound share)', () {
        // Arrange: these two map to the same key by design — the "bad AI
        // response" message covers both "model gave an unusable answer" and
        // "no dishes found", which are indistinguishable from the user's
        // perspective in the question context.
        const sharedPair = {
          MenuQuestionFailureReason.badResponse,
          MenuQuestionFailureReason.noDishesFound,
        };

        final l10n = lookupAppLocalizations(locale);

        // Act
        final reasonsOutsidePair = MenuQuestionFailureReason.values
            .where((r) => !sharedPair.contains(r))
            .toList();
        final messages = [
          for (final r in reasonsOutsidePair)
            menuQuestionFailureMessage(r, l10n),
        ];

        // Assert: the 8 outside-pair reasons all have distinct copy.
        expect(
          messages.toSet(),
          hasLength(messages.length),
          reason: 'every reason outside the shared pair must have its own copy',
        );
      });

      test('badResponse and noDishesFound share a message in '
          '${locale.languageCode} — this is intentional', () {
        final l10n = lookupAppLocalizations(locale);

        expect(
          menuQuestionFailureMessage(
            MenuQuestionFailureReason.badResponse,
            l10n,
          ),
          equals(
            menuQuestionFailureMessage(
              MenuQuestionFailureReason.noDishesFound,
              l10n,
            ),
          ),
        );
      });
    }

    group('question copy never duplicates analysis copy', () {
      for (final locale in _locales) {
        test('in ${locale.languageCode}: menuQuestion messages are distinct '
            'from analysisFailureMessage messages', () {
          // Arrange
          final l10n = lookupAppLocalizations(locale);

          final analysisMessages = {
            for (final r in MenuAnalysisFailureReason.values)
              analysisFailureMessage(r, l10n),
          };
          final questionMessages = [
            for (final r in MenuQuestionFailureReason.values)
              menuQuestionFailureMessage(r, l10n),
          ];

          // Assert: no question message appears in the analysis message set.
          // (Architecture §10 — collapsing two message families is a bug.)
          for (final msg in questionMessages) {
            expect(
              analysisMessages,
              isNot(contains(msg)),
              reason:
                  '"$msg" must not appear in the analysis failure messages; '
                  'each surface has its own copy',
            );
          }
        });
      }
    });
  });
}
