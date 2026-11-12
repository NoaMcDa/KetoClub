import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/widgets/category_chips.dart';
import 'package:ketoclub/widgets/dish_card.dart';
import 'package:ketoclub/widgets/scanned_page_chips.dart';
import 'package:provider/provider.dart';

/// The English strings the semantic labels are read from.
final AppLocalizations _en = AppLocalizationsEn();

/// Pumps [child] in a localised app, with the carb budget a dish card
/// reads.
Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  ChangeNotifierProvider<CarbBudgetController>.value(
    value: CarbBudgetController(),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: child),
    ),
  ),
);

/// Asserts the one semantics node labelled [label] is a button carrying
/// [SemanticsAction.tap], then performs that tap, as a screen reader's
/// double-tap does.
void _screenReaderTap(WidgetTester tester, String label) {
  final finder = find.semantics.byLabel(label);
  final data = finder.evaluate().single.getSemanticsData();
  expect(data.flagsCollection.isButton, isTrue, reason: label);
  expect(data.hasAction(SemanticsAction.tap), isTrue, reason: label);
  tester.semantics.tap(finder);
}

void main() {
  // Each control below wraps its button in `Semantics(excludeSemantics:
  // true)` for one clean label, which also drops the button's own tap
  // action; before issue #285 nothing put it back, so TalkBack and
  // VoiceOver announced a button a double-tap could not press.
  group('screen-reader taps (issue #285)', () {
    testWidgets('a category chip jumps to its category', (tester) async {
      // Arrange
      final semantics = tester.ensureSemantics();
      String? selected;
      await _pump(
        tester,
        CategoryChips(
          categories: const <String>['Mains', 'Sides'],
          onSelected: (category) => selected = category,
        ),
      );

      // Act
      _screenReaderTap(tester, _en.categoryChipSemanticLabel('Sides'));

      // Assert
      expect(selected, 'Sides');
      semantics.dispose();
    });

    testWidgets('a scanned-page chip selects its page, and says which is '
        'selected', (tester) async {
      // Arrange
      final semantics = tester.ensureSemantics();
      int? selected = -1;
      await _pump(
        tester,
        ScannedPageChips(
          pageCount: 2,
          hasUnknown: false,
          selected: null,
          onSelected: (page) => selected = page,
        ),
      );
      final all = _en.scannedPageChipSemanticLabel(_en.scannedPageChipAll);
      expect(
        find.semantics.byLabel(all).evaluate().single,
        isSemantics(isSelected: true),
      );

      // Act
      _screenReaderTap(
        tester,
        _en.scannedPageChipSemanticLabel(_en.scannedMenuPageLabel(2)),
      );

      // Assert
      expect(selected, 2);
      semantics.dispose();
    });

    testWidgets("a dish's note row opens the note editor", (tester) async {
      // Arrange
      final semantics = tester.ensureSemantics();
      DishRow? edited;
      const row = DishRow(
        dish: Dish(
          id: 'd1',
          name: 'Steak',
          description: '',
          price: 40,
          options: <DishOption>[],
        ),
        category: 'Mains',
      );
      await _pump(
        tester,
        DishCard(
          row: row,
          localeTag: 'en',
          onShowScript: (_) {},
          note: 'No butter',
          onEditNote: (tapped) => edited = tapped,
        ),
      );

      // Act
      _screenReaderTap(tester, _en.dishCardEditNoteSemanticLabel('No butter'));

      // Assert
      expect(edited, row);
      semantics.dispose();
    });
  });
}
