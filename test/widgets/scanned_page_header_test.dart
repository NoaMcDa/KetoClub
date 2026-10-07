import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/widgets/scanned_page_header.dart';

/// A 1x1 transparent PNG.
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChw'
  'GA60e6kgAAAABJRU5ErkJggg==',
);

/// Pumps [child] in a localised app at [locale].
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
}) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  final en = AppLocalizationsEn();
  final he = AppLocalizationsHe();

  group('ScannedPageHeader', () {
    testWidgets('shows "Page n of N", the dish count and an image', (
      tester,
    ) async {
      await _pump(
        tester,
        ScannedPageHeader(
          number: 2,
          total: 3,
          dishCount: 5,
          thumbnail: ScannedPage(mimeType: ScannedPage.png, bytes: _pngBytes),
        ),
      );

      expect(find.text(en.scannedPageHeader(2, 3)), findsOneWidget);
      expect(find.text(en.scannedPageDishCount(5)), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.byKey(const ValueKey('scannedPageHeader-2')), findsOneWidget);
    });

    testWidgets('a null total reads "Page n"', (tester) async {
      await _pump(tester, ScannedPageHeader(number: 1, dishCount: 1));

      expect(find.text(en.scannedMenuPageLabel(1)), findsOneWidget);
    });

    testWidgets('no thumbnail draws no tile', (tester) async {
      await _pump(tester, ScannedPageHeader(number: 1, dishCount: 2));

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsNothing);
    });

    testWidgets('a PDF page shows the PDF tile', (tester) async {
      await _pump(
        tester,
        ScannedPageHeader(
          number: 1,
          dishCount: 2,
          thumbnail: ScannedPage(
            mimeType: ScannedPage.pdf,
            bytes: Uint8List(4),
          ),
        ),
      );

      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('undecodable bytes show a broken-image icon', (tester) async {
      await _pump(
        tester,
        ScannedPageHeader(
          number: 1,
          dishCount: 2,
          thumbnail: ScannedPage(
            mimeType: ScannedPage.jpeg,
            bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tap is reported and a chevron shown', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        ScannedPageHeader(number: 1, dishCount: 2, onTap: () => taps++),
      );

      await tester.tap(find.text(en.scannedMenuPageLabel(1)));
      await tester.pump();

      expect(taps, 1);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.bySemanticsLabel(en.scannedPageHeaderOpen), findsOneWidget);
    });

    testWidgets('without onTap there is no chevron or button semantics', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, ScannedPageHeader(number: 1, dishCount: 2));

      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.bySemanticsLabel(en.scannedPageHeaderOpen), findsNothing);
      expect(find.byType(InkWell), findsNothing);
      handle.dispose();
    });

    testWidgets('the unknown variant explains itself and is not tappable', (
      tester,
    ) async {
      await _pump(tester, const ScannedPageHeader.unknown(dishCount: 3));

      expect(find.text(en.scannedPageUnknown), findsOneWidget);
      expect(find.text(en.scannedPageUnknownExplain), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byType(InkWell), findsNothing);
      expect(
        find.byKey(const ValueKey('scannedPageHeader-unknown')),
        findsOneWidget,
      );
    });

    testWidgets('is at least 44 tall', (tester) async {
      await _pump(tester, ScannedPageHeader(number: 1, dishCount: 2));

      final size = tester.getSize(
        find.byKey(const ValueKey('scannedPageHeader-1')),
      );
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('renders in Hebrew, right to left, with the chevron at the '
        'end', (tester) async {
      await _pump(
        tester,
        ScannedPageHeader(
          number: 1,
          total: 2,
          dishCount: 4,
          thumbnail: ScannedPage(
            mimeType: ScannedPage.pdf,
            bytes: Uint8List(4),
          ),
          onTap: () {},
        ),
        locale: const Locale('he'),
      );

      expect(find.text(he.scannedPageHeader(1, 2)), findsOneWidget);
      expect(find.text(he.scannedPageDishCount(4)), findsOneWidget);
      final header = tester.getRect(
        find.byKey(const ValueKey('scannedPageHeader-1')),
      );
      final chevron = tester.getRect(find.byIcon(Icons.chevron_right));
      final tile = tester.getRect(find.byIcon(Icons.picture_as_pdf_outlined));
      expect(tile.center.dx, greaterThan(chevron.center.dx));
      expect(chevron.center.dx, lessThan(header.center.dx));
    });
  });
}
