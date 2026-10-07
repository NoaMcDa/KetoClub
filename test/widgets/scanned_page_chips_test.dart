import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/widgets/scanned_page_chips.dart';

/// Pumps [child] in a localised app.
Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  ),
);

void main() {
  final en = AppLocalizationsEn();

  group('ScannedPageChips', () {
    testWidgets('renders All plus one chip per page', (tester) async {
      await _pump(
        tester,
        ScannedPageChips(
          pageCount: 3,
          hasUnknown: false,
          selected: null,
          onSelected: (_) {},
        ),
      );

      expect(find.byType(ChoiceChip), findsNWidgets(4));
      expect(find.text(en.scannedPageChipAll), findsOneWidget);
      expect(find.text(en.scannedMenuPageLabel(3)), findsOneWidget);
      expect(find.text(en.scannedPageUnknown), findsNothing);
    });

    testWidgets('adds the unknown chip when hasUnknown', (tester) async {
      await _pump(
        tester,
        ScannedPageChips(
          pageCount: 2,
          hasUnknown: true,
          selected: null,
          onSelected: (_) {},
        ),
      );

      expect(find.byType(ChoiceChip), findsNWidgets(4));
      expect(find.text(en.scannedPageUnknown), findsOneWidget);
    });

    testWidgets('renders nothing for one page without unknown', (tester) async {
      await _pump(
        tester,
        ScannedPageChips(
          pageCount: 1,
          hasUnknown: false,
          selected: null,
          onSelected: (_) {},
        ),
      );

      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('one page with unknown dishes still shows chips', (
      tester,
    ) async {
      await _pump(
        tester,
        ScannedPageChips(
          pageCount: 1,
          hasUnknown: true,
          selected: null,
          onSelected: (_) {},
        ),
      );

      expect(find.byType(ChoiceChip), findsNWidgets(3));
    });

    testWidgets('reflects the selected chip', (tester) async {
      Future<List<bool>> selections(int? selected) async {
        await _pump(
          tester,
          ScannedPageChips(
            pageCount: 2,
            hasUnknown: true,
            selected: selected,
            onSelected: (_) {},
          ),
        );
        return [
          for (final chip in tester.widgetList<ChoiceChip>(
            find.byType(ChoiceChip),
          ))
            chip.selected,
        ];
      }

      expect(await selections(null), [true, false, false, false]);
      expect(await selections(2), [false, false, true, false]);
      expect(await selections(scanPageUnknown), [false, false, false, true]);
    });

    testWidgets('reports null, a page number and the unknown value', (
      tester,
    ) async {
      final reported = <int?>[];
      await _pump(
        tester,
        ScannedPageChips(
          pageCount: 2,
          hasUnknown: true,
          selected: 1,
          onSelected: reported.add,
        ),
      );

      await tester.tap(find.text(en.scannedPageChipAll));
      await tester.tap(find.text(en.scannedMenuPageLabel(2)));
      await tester.tap(find.text(en.scannedPageUnknown));

      expect(reported, <int?>[null, 2, scanPageUnknown]);
    });

    testWidgets('each chip carries its semantic label', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        ScannedPageChips(
          pageCount: 2,
          hasUnknown: false,
          selected: null,
          onSelected: (_) {},
        ),
      );

      expect(
        find.bySemanticsLabel(
          en.scannedPageChipSemanticLabel(en.scannedMenuPageLabel(2)),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('wrap: true lays chips on several lines without scrolling', (
      tester,
    ) async {
      final reported = <int?>[];
      await _pump(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            child: ScannedPageChips(
              pageCount: 8,
              hasUnknown: true,
              selected: null,
              onSelected: reported.add,
              wrap: true,
            ),
          ),
        ),
      );

      expect(find.byType(SingleChildScrollView), findsNothing);
      final first = tester.getRect(find.text(en.scannedPageChipAll));
      final last = tester.getRect(find.text(en.scannedPageUnknown));
      expect(last.top, greaterThan(first.bottom));

      await tester.tap(find.text(en.scannedPageUnknown));
      expect(reported, <int?>[scanPageUnknown]);
    });
  });
}
