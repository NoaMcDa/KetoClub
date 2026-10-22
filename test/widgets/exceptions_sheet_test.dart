// The exceptions sheet (Banto, issue #417): add, remove, suggest, cap and
// the strict line, in English and Hebrew (right to left), plus the pure
// suggestion list and the row subtitle.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/widgets/exceptions_sheet.dart';

final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _he = AppLocalizationsHe();

/// What the opener button last received from the sheet.
List<String>? _saved;

/// Pumps a page whose button opens the sheet for [restriction] holding
/// [exceptions], then opens it.
Future<void> _open(
  WidgetTester tester,
  RestrictionId restriction, {
  List<String> exceptions = const <String>[],
  Locale locale = const Locale('en'),
}) async {
  _saved = null;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              _saved = await showExceptionsSheet(
                context: context,
                restriction: restriction,
                exceptions: exceptions,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(exceptionsFieldKey), text);
  await tester.tap(find.byKey(exceptionsAddKey));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(exceptionsSaveKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(exceptionsSaveKey));
  await tester.pumpAndSettle();
}

void main() {
  group('exceptionSuggestions', () {
    test('draws English direct terms, leaving out the group name', () {
      // Act
      final words = exceptionSuggestions(RestrictionId.treeNuts, hebrew: false);

      // Assert
      expect(words.first, 'almond');
      expect(words, contains('almonds'));
      expect(words, isNot(contains('tree nut')));
      expect(words, isNot(contains('tree nuts')));
      expect(words.length, lessThanOrEqualTo(maxExceptionSuggestions));
    });

    test('draws Hebrew direct terms for a Hebrew UI', () {
      // Act
      final words = exceptionSuggestions(RestrictionId.treeNuts, hebrew: true);

      // Assert
      expect(words, contains('שקדים'));
      expect(words.any((word) => RegExp('[a-z]').hasMatch(word)), isFalse);
    });

    test('leaves out words already held, ignoring case, and honours the '
        'limit', () {
      // Act
      final words = exceptionSuggestions(
        RestrictionId.treeNuts,
        hebrew: false,
        exclude: <String>['Almond'],
        limit: 2,
      );

      // Assert
      expect(words, hasLength(2));
      expect(words, isNot(contains('almond')));
    });

    test("has none for the user's own restriction", () {
      // Act + Assert
      expect(
        exceptionSuggestions(RestrictionId.custom, hebrew: false),
        isEmpty,
      );
    });
  });

  group('ExceptionsSheet (English)', () {
    testWidgets('explains an exception in one sentence and shows the '
        'strict line for an allergy', (tester) async {
      // Act
      await _open(tester, RestrictionId.treeNuts);

      // Assert
      expect(find.text(_en.exceptionsExplain), findsOneWidget);
      expect(find.text(_en.exceptionsSheetTitle('Tree nuts')), findsOneWidget);
      expect(find.byKey(exceptionsStrictNoteKey), findsOneWidget);
      expect(find.text(_en.exceptionsStrictNote), findsOneWidget);
      expect(find.text(_en.exceptionsNone), findsOneWidget);
    });

    testWidgets('a flexible restriction has no strict line', (tester) async {
      // Act
      await _open(tester, RestrictionId.lactose);

      // Assert
      expect(find.byKey(exceptionsStrictNoteKey), findsNothing);
      expect(find.text(_en.exceptionsExplain), findsOneWidget);
    });

    testWidgets('never says "safe" in any of its copy', (tester) async {
      // Arrange
      final safe = RegExp('(?<![A-Za-z])safe|בטוח', caseSensitive: false);
      final copy = <String>[
        for (final l10n in <AppLocalizations>[_en, _he]) ...[
          l10n.exceptionsExplain,
          l10n.exceptionsWholeWord,
          l10n.exceptionsStrictNote,
          l10n.exceptionsFull(ProfileEntry.maxExceptions),
          l10n.exceptionsRowLine('x'),
          l10n.exceptionsSheetTitle('x'),
        ],
      ];

      // Assert
      for (final text in copy) {
        expect(text, isNot(matches(safe)), reason: text);
      }
    });

    testWidgets('adds a typed word, ignoring blanks and repeats', (
      tester,
    ) async {
      // Arrange
      await _open(tester, RestrictionId.treeNuts);

      // Act
      await _type(tester, '  pecan ');
      await _type(tester, '   ');
      await _type(tester, 'PECAN');
      await _save(tester);

      // Assert
      expect(_saved, <String>['pecan']);
    });

    testWidgets('a suggestion chip adds its word and leaves the '
        'suggestions', (tester) async {
      // Arrange
      await _open(tester, RestrictionId.treeNuts);

      // Act
      await tester.tap(find.byKey(exceptionSuggestionKey('almond')));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byKey(exceptionChipKey('almond')), findsOneWidget);
      expect(find.byKey(exceptionSuggestionKey('almond')), findsNothing);
      await _save(tester);
      expect(_saved, <String>['almond']);
    });

    testWidgets('removes a held exception', (tester) async {
      // Arrange
      await _open(
        tester,
        RestrictionId.treeNuts,
        exceptions: <String>['almond', 'pecan'],
      );

      // Act
      await tester.tap(find.byTooltip(_en.exceptionsRemove('almond')));
      await tester.pumpAndSettle();
      await _save(tester);

      // Assert
      expect(_saved, <String>['pecan']);
    });

    testWidgets('refuses a sixth word with a message', (tester) async {
      // Arrange
      await _open(
        tester,
        RestrictionId.treeNuts,
        exceptions: <String>['a', 'b', 'c', 'd', 'e'],
      );
      expect(find.byKey(exceptionsFullKey), findsNothing);

      // Act
      await _type(tester, 'f');

      // Assert
      expect(find.byKey(exceptionsFullKey), findsOneWidget);
      expect(
        find.text(_en.exceptionsFull(ProfileEntry.maxExceptions)),
        findsOneWidget,
      );
      expect(find.byKey(exceptionChipKey('f')), findsNothing);

      // Act: removing one clears the message and makes room.
      await tester.tap(find.byTooltip(_en.exceptionsRemove('a')));
      await tester.pumpAndSettle();
      await _type(tester, 'f');

      // Assert
      expect(find.byKey(exceptionsFullKey), findsNothing);
      await _save(tester);
      expect(_saved, <String>['b', 'c', 'd', 'e', 'f']);
    });

    testWidgets('Save takes the word still typed in the field', (tester) async {
      // Arrange
      await _open(tester, RestrictionId.treeNuts);

      // Act
      await tester.enterText(find.byKey(exceptionsFieldKey), 'cashew');
      await _save(tester);

      // Assert
      expect(_saved, <String>['cashew']);
    });

    testWidgets('dismissing the sheet saves nothing', (tester) async {
      // Arrange
      await _open(tester, RestrictionId.treeNuts);
      await tester.tap(find.byKey(exceptionSuggestionKey('almond')));
      await tester.pumpAndSettle();

      // Act
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byKey(exceptionsSheetKey), findsNothing);
      expect(_saved, isNull);
    });
  });

  group('ExceptionsSheet (Hebrew, right to left)', () {
    testWidgets('speaks Hebrew, suggests Hebrew words and takes a Hebrew '
        'word', (tester) async {
      // Arrange
      await _open(tester, RestrictionId.treeNuts, locale: const Locale('he'));

      // Assert
      expect(find.text(_he.exceptionsExplain), findsOneWidget);
      expect(find.text(_he.exceptionsStrictNote), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byKey(exceptionsSheetKey))),
        TextDirection.rtl,
      );
      expect(find.byKey(exceptionSuggestionKey('almond')), findsNothing);

      // Act
      await tester.tap(find.byKey(exceptionSuggestionKey('שקדים')));
      await tester.pumpAndSettle();
      await _type(tester, 'פקאן');
      await _save(tester);

      // Assert
      expect(_saved, <String>['שקדים', 'פקאן']);
    });
  });

  group('RestrictionRowSubtitle', () {
    Future<void> pump(WidgetTester tester, List<String> exceptions) =>
        tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: RestrictionRowSubtitle(
                kindLabel: 'Allergy',
                exceptions: exceptions,
              ),
            ),
          ),
        );

    testWidgets('shows the kind alone with no exception', (tester) async {
      // Act
      await pump(tester, const <String>[]);

      // Assert
      expect(find.text('Allergy'), findsOneWidget);
      expect(find.textContaining('Except'), findsNothing);
    });

    testWidgets('adds one muted "Except …" line', (tester) async {
      // Act
      await pump(tester, const <String>['almonds', 'pistachio']);

      // Assert
      expect(find.text('Allergy'), findsOneWidget);
      expect(find.text('Except almonds, pistachio'), findsOneWidget);
    });
  });
}
