import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/services/platform/image_downscaler.dart';
import 'package:ketoclub/services/platform/scan_budget.dart';

/// A downscaler that answers a JPEG of exactly the target it was asked
/// for (or [floorBytes], when that is larger), recording every call.
final class _SizingDownscaler implements ImageDownscaler {
  new({this.floorBytes = 0});

  /// The smallest page this fake can produce, to model an image that
  /// cannot shrink any further.
  final int floorBytes;

  /// Every page and target [downscaleTo] was asked for, in call order.
  final List<(ScannedPage, int)> calls = <(ScannedPage, int)>[];

  @override
  Future<ScannedPage> downscale(ScannedPage page) async => page;

  @override
  Future<ScannedPage> downscaleTo(
    ScannedPage page, {
    required int targetBytes,
  }) async {
    calls.add((page, targetBytes));
    final size = targetBytes > floorBytes ? targetBytes : floorBytes;
    if (size >= page.bytes.length) return page;
    return ScannedPage(mimeType: ScannedPage.jpeg, bytes: Uint8List(size));
  }
}

/// [bytes] bytes of varied content tagged [seed], so pages differ.
ScannedPage _page(int bytes, {int seed = 0, String mime = ScannedPage.jpeg}) =>
    ScannedPage(
      mimeType: mime,
      bytes: Uint8List.fromList(
        List<int>.generate(bytes, (i) => (i * 31 + seed * 7) & 0xff),
      ),
    );

void main() {
  group('ScanBudget.fit', () {
    test('returns the identical scan when it is under budget', () async {
      // Arrange
      final downscaler = _SizingDownscaler();
      final budget = ScanBudget(downscaler: downscaler);
      final scan = ScannedMenu(pages: [_page(100 * 1024)]);

      // Act
      final fit = await budget.fit(scan);

      // Assert
      expect(fit, isA<ScanFitted>());
      expect(identical((fit as ScanFitted).scan, scan), isTrue);
      expect(downscaler.calls, isEmpty);
    });

    test('shrinks three 900 KiB pages to an even share each', () async {
      // Arrange
      final downscaler = _SizingDownscaler();
      final budget = ScanBudget(downscaler: downscaler);
      final pages = [for (var i = 0; i < 3; i++) _page(900 * 1024, seed: i)];

      // Act
      final fit = await budget.fit(ScannedMenu(pages: pages));

      // Assert
      expect(fit, isA<ScanFitted>());
      final fitted = (fit as ScanFitted).scan;
      expect(fitted.pages, hasLength(3));
      for (final page in fitted.pages) {
        expect(page.bytes.length, lessThanOrEqualTo(300 * 1024));
      }
      expect(fitted.totalBytes, lessThanOrEqualTo(scanInlineByteBudget));
      // In order: each call saw the page at the same index.
      expect([for (final c in downscaler.calls) c.$1], pages);
      expect(
        downscaler.calls.map((c) => c.$2),
        everyElement(scanInlineByteBudget ~/ 3),
      );
    });

    test('never asks for less than the per-page minimum', () async {
      // Arrange: ten pages would share 90 KiB each.
      final downscaler = _SizingDownscaler();
      final budget = ScanBudget(downscaler: downscaler);
      final pages = [for (var i = 0; i < 10; i++) _page(200 * 1024, seed: i)];

      // Act
      final fit = await budget.fit(ScannedMenu(pages: pages));

      // Assert: 10 x 120 KiB is over budget, so it is refused.
      expect(
        downscaler.calls.map((c) => c.$2),
        everyElement(minScanPageTargetBytes),
      );
      expect(fit, isA<ScanTooLarge>());
    });

    test('passes a PDF page through untouched and does not count it', () async {
      // Arrange: a 2 MiB PDF beside a 1 MiB image.
      final downscaler = _SizingDownscaler();
      final budget = ScanBudget(downscaler: downscaler);
      final pdf = _page(2 * 1024 * 1024, mime: ScannedPage.pdf);
      final image = _page(1024 * 1024, seed: 1);

      // Act
      final fit = await budget.fit(ScannedMenu(pages: [pdf, image]));

      // Assert: the whole budget went to the one image.
      expect(fit, isA<ScanFitted>());
      final fitted = (fit as ScanFitted).scan;
      expect(identical(fitted.pages.first, pdf), isTrue);
      expect(fitted.pages.last.bytes.length, scanInlineByteBudget);
      expect(downscaler.calls.single.$1, image);
      expect(downscaler.calls.single.$2, scanInlineByteBudget);
    });

    test('a scan of PDFs alone is fitted as it is', () async {
      // Arrange
      final downscaler = _SizingDownscaler();
      final budget = ScanBudget(downscaler: downscaler);
      final scan = ScannedMenu(
        pages: [_page(2 * 1024 * 1024, mime: ScannedPage.pdf)],
      );

      // Act
      final fit = await budget.fit(scan);

      // Assert
      expect(identical((fit as ScanFitted).scan, scan), isTrue);
      expect(downscaler.calls, isEmpty);
    });

    test('answers ScanTooLarge when the pages cannot shrink enough', () async {
      // Arrange: nothing gets below 500 KiB, and there are two pages.
      final budget = ScanBudget(
        downscaler: _SizingDownscaler(floorBytes: 500 * 1024),
      );
      final pages = [_page(800 * 1024), _page(800 * 1024, seed: 1)];

      // Act
      final fit = await budget.fit(ScannedMenu(pages: pages));

      // Assert
      expect(fit, isA<ScanTooLarge>());
      final tooLarge = fit as ScanTooLarge;
      expect(tooLarge.totalBytes, 1000 * 1024);
      expect(tooLarge.budgetBytes, scanInlineByteBudget);
    });

    test('with NoImageDownscaler an over-budget scan is too large', () async {
      // Arrange
      const budget = ScanBudget(downscaler: NoImageDownscaler());

      // Act
      final fit = await budget.fit(ScannedMenu(pages: [_page(1024 * 1024)]));

      // Assert
      expect(fit, isA<ScanTooLarge>());
    });
  });
}
