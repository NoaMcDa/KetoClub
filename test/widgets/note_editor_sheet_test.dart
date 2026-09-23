import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/widgets/note_editor_sheet.dart';

/// Pumps [child] inside a localised [MaterialApp] and a [Scaffold], the
/// shape every widget test in `test/widgets/` uses.
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
  group('NoteEditorSheet', () {
    testWidgets('build shows the dish name and an empty field when there '
        'is no initial note', (tester) async {
      // Act
      await _pump(
        tester,
        NoteEditorSheet(
          dishName: 'Grilled Salmon',
          initialNote: null,
          onSave: (_) {},
          onClear: () {},
        ),
      );

      // Assert
      expect(find.text('Grilled Salmon'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
      expect(find.text('Clear note'), findsNothing);
    });

    testWidgets('build seeds the field with the initial note and shows '
        'Clear', (tester) async {
      // Act
      await _pump(
        tester,
        NoteEditorSheet(
          dishName: 'Grilled Salmon',
          initialNote: 'Ask for no cheese.',
          onSave: (_) {},
          onClear: () {},
        ),
      );

      // Assert
      expect(find.text('Ask for no cheese.'), findsOneWidget);
      expect(find.text('Clear note'), findsOneWidget);
    });

    testWidgets('tapping Save calls onSave with the trimmed field text', (
      tester,
    ) async {
      // Arrange
      String? saved;
      await _pump(
        tester,
        NoteEditorSheet(
          dishName: 'Grilled Salmon',
          initialNote: null,
          onSave: (note) => saved = note,
          onClear: () {},
        ),
      );

      // Act
      await tester.enterText(find.byType(TextField), '  A new note.  ');
      await tester.tap(find.text('Save'));
      await tester.pump();

      // Assert
      expect(saved, equals('A new note.'));
    });

    testWidgets('tapping Clear calls onClear, not onSave', (tester) async {
      // Arrange
      var cleared = false;
      var saveCalls = 0;
      await _pump(
        tester,
        NoteEditorSheet(
          dishName: 'Grilled Salmon',
          initialNote: 'Existing note.',
          onSave: (_) => saveCalls++,
          onClear: () => cleared = true,
        ),
      );

      // Act
      await tester.tap(find.text('Clear note'));
      await tester.pump();

      // Assert
      expect(cleared, isTrue);
      expect(saveCalls, equals(0));
    });

    testWidgets('an emptied field still calls onSave with an empty string, '
        'not onClear', (tester) async {
      // Arrange: MenuController.setNote is the one place that turns a
      // blank save into a clear — this sheet passes the text through as
      // typed.
      String? saved;
      await _pump(
        tester,
        NoteEditorSheet(
          dishName: 'Grilled Salmon',
          initialNote: 'Existing note.',
          onSave: (note) => saved = note,
          onClear: () {},
        ),
      );

      // Act
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Save'));
      await tester.pump();

      // Assert
      expect(saved, equals(''));
    });

    testWidgets('build renders the Hebrew title in the he locale', (
      tester,
    ) async {
      // Act
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('he'),
          home: Scaffold(
            body: NoteEditorSheet(
              dishName: 'סלמון על הגריל',
              initialNote: null,
              onSave: (_) {},
              onClear: () {},
            ),
          ),
        ),
      );

      // Assert
      expect(find.text('הערה אישית'), findsOneWidget);
    });
  });
}
