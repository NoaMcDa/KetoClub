import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:ketoclub/models/scanned_menu.dart';

/// The target size, in bytes, [JpegImageDownscaler] shrinks a picked
/// photograph below. A larger image is decoded, resized and re-encoded as
/// JPEG; a smaller one is passed through untouched.
///
/// Set to 900 KiB: with Base64's ~33 % overhead inside the Gemini request
/// body, 900 KiB on disk is about 1.2 MB on the wire, under the practical
/// inline threshold a 1113 KB image was observed to cross (the Gemini
/// request answered 503 UNAVAILABLE at ~1.5 MB on the wire). The backend's
/// `VISION_MAX_IMAGE_BYTES` is 3 MiB and stays the hard cap — this is a
/// softer target the picker aims for so the model request succeeds.
const int inlineImageByteTarget = 900 * 1024;

/// The longest edge, in pixels, [JpegImageDownscaler] fits an oversize
/// image into. 1280 px keeps a printed menu's dish names legible to the
/// vision model while reliably producing a JPEG under
/// [inlineImageByteTarget] at [downscaledJpegQuality].
const int downscaledImageMaxLongEdge = 1280;

/// The JPEG quality, 0 to 100, [JpegImageDownscaler] re-encodes a shrunk
/// image with. 75 is a visible notch above the lower bound JPEG
/// compression stays faithful to printed text.
const int downscaledJpegQuality = 75;

/// Shrinks a picked [ScannedPage] below the practical inline cap of the
/// vision request. PDFs and already-small images are returned untouched.
///
/// Implementations never throw: an undecodable image is returned unchanged
/// so a picker never loses a page to a downscaler fault.
abstract interface class ImageDownscaler {
  /// Returns [page] with its bytes reduced below [inlineImageByteTarget]
  /// when the implementation can do so, otherwise [page] itself.
  Future<ScannedPage> downscale(ScannedPage page);
}

/// The [ImageDownscaler] that does nothing: every page comes back as it
/// went in. The default where no plugin or heavy decode is wanted (the
/// tests of callers that are not about downscaling).
final class NoImageDownscaler implements ImageDownscaler {
  /// Creates the no-op downscaler; it holds no state.
  const new();

  @override
  Future<ScannedPage> downscale(ScannedPage page) async => page;
}

/// The real [ImageDownscaler], over the pure-Dart `image` package.
///
/// A page whose mime type is a PDF is returned untouched (PDF pages are
/// not decoded here) and so is one whose bytes are already at or below
/// [targetBytes]. Otherwise the bytes are decoded, fitted inside
/// [maxLongEdge] by `copyResize` and re-encoded as JPEG at [jpegQuality];
/// a result that somehow turned out larger than the input is discarded in
/// favour of the input, and a decode failure returns the input too. The
/// output mime type of a shrunk page is always [ScannedPage.jpeg],
/// including for a PNG or a WebP source: the vision model reads them the
/// same way and JPEG compresses a photograph best.
final class JpegImageDownscaler implements ImageDownscaler {
  /// Creates a downscaler with the shared [inlineImageByteTarget],
  /// [downscaledImageMaxLongEdge] and [downscaledJpegQuality] by default.
  const new({
    this.targetBytes = inlineImageByteTarget,
    this.maxLongEdge = downscaledImageMaxLongEdge,
    this.jpegQuality = downscaledJpegQuality,
  });

  /// Bytes above which [downscale] re-encodes the image.
  final int targetBytes;

  /// Pixels the longest edge of the re-encoded image is fitted into.
  final int maxLongEdge;

  /// JPEG quality (0–100) the re-encoded image is written with.
  final int jpegQuality;

  @override
  Future<ScannedPage> downscale(ScannedPage page) async {
    if (page.isPdf) return page;
    if (page.bytes.length <= targetBytes) return page;
    try {
      final decoded = img.decodeImage(page.bytes);
      if (decoded == null) return page;
      final resized = _fitInside(decoded, maxLongEdge);
      final encoded = Uint8List.fromList(
        img.encodeJpg(resized, quality: jpegQuality),
      );
      if (encoded.isEmpty || encoded.length >= page.bytes.length) return page;
      return ScannedPage(mimeType: ScannedPage.jpeg, bytes: encoded);
    } on Object {
      return page;
    }
  }

  static img.Image _fitInside(img.Image src, int maxEdge) {
    if (src.width <= maxEdge && src.height <= maxEdge) return src;
    if (src.width >= src.height) {
      return img.copyResize(src, width: maxEdge);
    }
    return img.copyResize(src, height: maxEdge);
  }
}
