import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/widgets/menu_search_field.dart';

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

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
  group('MenuSearchField', () {
    testWidgets('shows the hint text and no clear button when empty', (
      tester,
    ) async {
      // Arrange & Act
      await _pump(tester, MenuSearchField(onChanged: (_) {}));

      // Assert
      expect(find.text(_en.menuSearchHint), findsOneWidget);
      expect(find.byIcon(Icons.clear), findsNothing);
    });

    testWidgets('typing reports every change through onChanged', (
      tester,
    ) async {
      // Arrange
      final reported = <String>[];
      await _pump(tester, MenuSearchField(onChanged: reported.add));

      // Act
      await tester.enterText(find.byType(TextField), 'fries');

      // Assert
      expect(reported, ['fries']);
    });

    testWidgets('a non-empty field shows a clear button that reports an empty '
        'string and empties the field', (tester) async {
      // Arrange
      final reported = <String>[];
      await _pump(tester, MenuSearchField(onChanged: reported.add));
      await tester.enterText(find.byType(TextField), 'fries');
      await tester.pump();
      expect(find.byIcon(Icons.clear), findsOneWidget);

      // Act
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      // Assert
      expect(reported.last, '');
      expect(find.byIcon(Icons.clear), findsNothing);
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, '');
    });

    testWidgets('starts from the query it is given, so a field built afresh '
        'shows the search still filtering (issue #286)', (tester) async {
      // Arrange & Act
      await _pump(tester, MenuSearchField(query: 'salmon', onChanged: (_) {}));

      // Assert
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'salmon',
      );
      expect(find.byIcon(Icons.clear), findsOneWidget);
    });

    testWidgets('follows a query changed from outside, and keeps the cursor '
        'while the user types (issue #286)', (tester) async {
      // Arrange: a field whose query mirrors what is typed, as the menu
      // screen's does through MenuController.setQuery.
      var query = '';
      late StateSetter rebuild;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return MenuSearchField(
              query: query,
              onChanged: (text) => setState(() => query = text),
            );
          },
        ),
      );
      await tester.enterText(find.byType(TextField), 'sal');
      await tester.pump();
      TextEditingController field() =>
          tester.widget<TextField>(find.byType(TextField)).controller!;
      expect(field().text, 'sal');
      expect(field().selection, const TextSelection.collapsed(offset: 3));

      // Act: the query is cleared elsewhere.
      rebuild(() => query = '');
      await tester.pump();

      // Assert
      expect(field().text, '');
    });
  });
}
