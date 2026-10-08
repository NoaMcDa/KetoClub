import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/widgets/rename_menu_dialog.dart';

/// The English strings a test can read expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// What the last [showRenameMenuDialog] completed with, and whether it has.
MenuRename? _result;
bool _completed = false;

/// Pumps a button that opens the dialog seeded with [name] and [city].
Future<void> _pump(WidgetTester tester, {String? name, String? city}) {
  _result = null;
  _completed = false;
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () async {
              _result = await showRenameMenuDialog(
                context,
                initialName: name,
                initialCity: city,
              );
              _completed = true;
            },
            child: const Icon(Icons.edit),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byType(FilledButton));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

void main() {
  group('RenameMenuDialog', () {
    testWidgets('shows the title, both hints and the seeded values', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, name: 'Café Noam', city: 'Haifa');

      // Act
      await _open(tester);

      // Assert
      expect(find.text(_en.menuRenameTitle), findsOneWidget);
      expect(_text(tester, 'menuRenameName'), 'Café Noam');
      expect(_text(tester, 'menuRenameCity'), 'Haifa');
      expect(find.text(_en.menuRenameSave), findsOneWidget);
      expect(find.text(_en.actionCancel), findsOneWidget);
    });

    testWidgets('null values seed empty fields showing the hints', (
      tester,
    ) async {
      // Arrange
      await _pump(tester);

      // Act
      await _open(tester);

      // Assert
      expect(_text(tester, 'menuRenameName'), isEmpty);
      expect(_text(tester, 'menuRenameCity'), isEmpty);
      expect(find.text(_en.menuRenameHint), findsOneWidget);
      expect(find.text(_en.menuRenameCityHint), findsOneWidget);
    });

    testWidgets('Save completes with the raw text of both fields', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, name: 'Old', city: 'Lod');
      await _open(tester);

      // Act
      await tester.enterText(
        find.byKey(const ValueKey('menuRenameName')),
        ' Café Noam ',
      );
      await tester.enterText(find.byKey(const ValueKey('menuRenameCity')), '');
      await tester.tap(find.byKey(const ValueKey('menuRenameSave')));
      await tester.pumpAndSettle();

      // Assert
      expect(_completed, isTrue);
      expect(_result, (name: ' Café Noam ', city: ''));
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Cancel completes with null', (tester) async {
      // Arrange
      await _pump(tester, name: 'Old');
      await _open(tester);

      // Act
      await tester.enterText(
        find.byKey(const ValueKey('menuRenameName')),
        'Café Noam',
      );
      await tester.tap(find.text(_en.actionCancel));
      await tester.pumpAndSettle();

      // Assert
      expect(_completed, isTrue);
      expect(_result, isNull);
    });

    testWidgets('the save button is a FilledButton', (tester) async {
      // Arrange
      await _pump(tester);

      // Act
      await _open(tester);

      // Assert
      expect(
        tester.widget(find.byKey(const ValueKey('menuRenameSave'))),
        isA<FilledButton>(),
      );
    });
  });
}
