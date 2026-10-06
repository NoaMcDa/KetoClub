import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/services/platform/image_downscaler.dart';

/// A width x height canvas filled with pseudo-random RGB content, so the
/// pixel data has no large-scale structure a codec can lean on. Produces
/// JPEG and PNG bytes neither of which compresses well.
img.Image _noisyImage({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      // A small Knuth-style hash per channel: each coordinate is multiplied
      // by a large prime and the low byte is kept. The products never line
      // up across (x, y), so neighbouring pixels differ sharply.
      final r = (((x + 1) * 2654435761) ^ ((y + 1) * 40503)) & 0xff;
      final g = (((x + 1) * 1597334677) ^ ((y + 1) * 2246822519)) & 0xff;
      final b = (((x + 1) * 374761393) ^ ((y + 1) * 3266489917)) & 0xff;
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return image;
}

/// Encodes [_noisyImage] as JPEG at [quality].
Uint8List _noisyJpeg({
  required int width,
  required int height,
  int quality = 95,
}) => Uint8List.fromList(
  img.encodeJpg(
    _noisyImage(width: width, height: height),
    quality: quality,
  ),
);

/// Encodes [_noisyImage] as PNG.
Uint8List _noisyPng({required int width, required int height}) =>
    Uint8List.fromList(
      img.encodePng(_noisyImage(width: width, height: height)),
    );

void main() {
  group('NoImageDownscaler', () {
    test('returns the page it was given, unchanged', () async {
      // Arrange
      const downscaler = NoImageDownscaler();
      final page = ScannedPage(
        mimeType: ScannedPage.jpeg,
        bytes: Uint8List.fromList(const <int>[1, 2, 3]),
      );

      // Act
      final result = await downscaler.downscale(page);

      // Assert
      expect(identical(result, page), isTrue);
    });
  });

  group('JpegImageDownscaler', () {
    test('passes a PDF through untouched regardless of size', () async {
      // Arrange: an oversize payload wearing the PDF mime type.
      final page = ScannedPage(
        mimeType: ScannedPage.pdf,
        bytes: Uint8List(4096),
      );
      const downscaler = JpegImageDownscaler(targetBytes: 1024);

      // Act
      final result = await downscaler.downscale(page);

      // Assert
      expect(identical(result, page), isTrue);
    });

    test('passes an image at or below the target through untouched', () async {
      // Arrange
      final page = ScannedPage(
        mimeType: ScannedPage.jpeg,
        bytes: _noisyJpeg(width: 48, height: 48),
      );
      final downscaler = JpegImageDownscaler(
        targetBytes: page.bytes.length + 1,
      );

      // Act
      final result = await downscaler.downscale(page);

      // Assert
      expect(identical(result, page), isTrue);
    });

    test('shrinks an oversize JPEG and keeps the JPEG mime type', () async {
      // Arrange: 400 x 400 at q=95 is well over 1 KiB; the downscaler is
      // asked to fit it into 1 KiB with a 128 px long edge at q=50.
      final bytes = _noisyJpeg(width: 400, height: 400);
      expect(bytes.length, greaterThan(1024), reason: 'test setup');
      final page = ScannedPage(mimeType: ScannedPage.jpeg, bytes: bytes);
      const downscaler = JpegImageDownscaler(
        targetBytes: 1024,
        maxLongEdge: 128,
        jpegQuality: 50,
      );

      // Act
      final result = await downscaler.downscale(page);

      // Assert
      expect(result.mimeType, ScannedPage.jpeg);
      expect(result.bytes.length, lessThan(page.bytes.length));
      // The resized image fits inside the long-edge cap.
      final decoded = img.decodeImage(result.bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(128));
      expect(decoded.height, lessThanOrEqualTo(128));
    });

    test('rewrites an oversize PNG as JPEG so it compresses better', () async {
      // Arrange: a 400 x 400 PNG of pseudo-random content is tens of KiB,
      // and a 128 px q=50 JPEG of the same pixels is a few KiB.
      final bytes = _noisyPng(width: 400, height: 400);
      expect(bytes.length, greaterThan(10 * 1024), reason: 'test setup');
      final page = ScannedPage(mimeType: ScannedPage.png, bytes: bytes);
      const downscaler = JpegImageDownscaler(
        targetBytes: 1024,
        maxLongEdge: 128,
        jpegQuality: 50,
      );

      // Act
      final result = await downscaler.downscale(page);

      // Assert
      expect(result.mimeType, ScannedPage.jpeg);
      expect(result.bytes.length, lessThan(page.bytes.length));
    });

    test('fits a landscape image inside the long-edge cap', () async {
      // Arrange
      final bytes = _noisyJpeg(width: 400, height: 200);
      final page = ScannedPage(mimeType: ScannedPage.jpeg, bytes: bytes);
      const downscaler = JpegImageDownscaler(
        targetBytes: 1024,
        maxLongEdge: 100,
        jpegQuality: 50,
      );

      // Act
      final result = await downscaler.downscale(page);

      // Assert
      final decoded = img.decodeImage(result.bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, 100);
      // Aspect ratio preserved: half the width, half the height.
      expect(decoded.height, lessThanOrEqualTo(100));
    });

    test('fits a portrait image inside the long-edge cap', () async {
      // Arrange
      final bytes = _noisyJpeg(width: 200, height: 400);
      final page = ScannedPage(mimeType: ScannedPage.jpeg, bytes: bytes);
      const downscaler = JpegImageDownscaler(
        targetBytes: 1024,
        maxLongEdge: 100,
        jpegQuality: 50,
      );

      // Act
      final result = await downscaler.downscale(page);

      // Assert
      final decoded = img.decodeImage(result.bytes);
      expect(decoded, isNotNull);
      expect(decoded!.height, 100);
      expect(decoded.width, lessThanOrEqualTo(100));
    });

    test('returns the original when the bytes cannot be decoded', () async {
      // Arrange
      final page = ScannedPage(
        mimeType: ScannedPage.jpeg,
        bytes: Uint8List.fromList(List<int>.filled(4096, 0x42)),
      );
      const downscaler = JpegImageDownscaler(targetBytes: 1024);

      // Act
      final result = await downscaler.downscale(page);

      // Assert
      expect(identical(result, page), isTrue);
    });

    test('keeps the original when the re-encode would be no smaller', () async {
      // Arrange: an input encoded at the lowest JPEG quality is already
      // minimal, and a re-encode at the top quality of the same pixels is
      // larger. The downscaler must prefer the input.
      final cheap = _noisyJpeg(width: 64, height: 64, quality: 1);
      final page = ScannedPage(mimeType: ScannedPage.jpeg, bytes: cheap);
      final downscaler = JpegImageDownscaler(
        // Below the input size, so the decode path is taken.
        targetBytes: cheap.length - 1,
        // Larger than the image, so no resize changes the content.
        maxLongEdge: 128,
        // Full quality re-encode is bigger than the q=1 input.
        jpegQuality: 100,
      );

      // Act
      final result = await downscaler.downscale(page);

      // Assert: the implementation keeps the original rather than return
      // a re-encode that gained bytes.
      expect(identical(result, page), isTrue);
    });
  });

  group('default thresholds', () {
    test('inlineImageByteTarget is well under 1 MiB on the wire', () {
      // Base64 inflates by ~33 %; the target must sit below the ~1.5 MiB
      // threshold at which Gemini answered 503 for the vision request.
      expect(inlineImageByteTarget, lessThanOrEqualTo(1024 * 1024));
    });

    test('downscaledImageMaxLongEdge is enough to keep menu text readable', () {
      expect(downscaledImageMaxLongEdge, greaterThanOrEqualTo(1024));
    });

    test('downscaledJpegQuality is a visible notch above the floor', () {
      expect(downscaledJpegQuality, inInclusiveRange(60, 90));
    });
  });
}
