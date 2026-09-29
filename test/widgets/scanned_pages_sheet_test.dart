import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/widgets/scanned_pages_sheet.dart';

/// The English strings the sheet renders.
final AppLocalizations _en = AppLocalizationsEn();

/// A 1×1 transparent PNG.
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChw'
  'GA60e6kgAAAABJRU5ErkJggg==',
);

/// Pumps a sheet over [scan] as the body of a localised app.
Future<void> _pump(WidgetTester tester, ScannedMenu scan) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: ScannedPagesSheet(scan: scan)),
  ),
);

void main() {
  group('ScannedPagesSheet', () {
    testWidgets('labels each page with its number, in order', (tester) async {
      // Arrange
      final scan = ScannedMenu(
        pages: <ScannedPage>[
          ScannedPage(mimeType: ScannedPage.png, bytes: _pngBytes),
          ScannedPage(
            mimeType: ScannedPage.pdf,
            bytes: Uint8List.fromList(<int>[0x25, 0x50]),
          ),
        ],
      );

      // Act
      await _pump(tester, scan);
      await tester.pumpAndSettle();

      // Assert
      // The PDF tile's label merges with its own "PDF document" text.
      expect(find.bySemanticsLabel(RegExp('^Page 1')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('^Page 2')), findsWidgets);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text(_en.scannedMenuPdfPage), findsOneWidget);
      expect(find.text(_en.scannedMenuPagesNote), findsOneWidget);
    });

    testWidgets('a tapped image page opens full screen and closes', (
      tester,
    ) async {
      // Arrange
      await _pump(
        tester,
        ScannedMenu(
          pages: <ScannedPage>[
            ScannedPage(mimeType: ScannedPage.png, bytes: _pngBytes),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(InteractiveViewer), findsOneWidget);

      // Act: close the full-screen view.
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byTooltip(_en.scannedMenuPagesClose),
        ),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.byType(ScannedPagesSheet), findsOneWidget);
    });

    testWidgets('a page whose bytes do not decode shows a broken-image '
        'icon instead of failing', (tester) async {
      // Arrange
      final scan = ScannedMenu(
        pages: <ScannedPage>[
          ScannedPage(
            mimeType: ScannedPage.jpeg,
            bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
          ),
        ],
      );

      // Act: decoding happens off the frame, so let it run for real.
      await _pump(tester, scan);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
