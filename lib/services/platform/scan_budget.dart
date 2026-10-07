import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/services/platform/image_downscaler.dart';

/// The most image bytes, summed over every page, one vision request may
/// carry inline (issue #298).
///
/// The same 900 KiB as `inlineImageByteTarget`, but for the whole scan
/// rather than one page: Gemini answers 503 once the request body passes
/// about 1.5 MB on the wire, and that limit is per request, so three
/// pages each just under the per-page target still fail together.
const int scanInlineByteBudget = 900 * 1024;

/// The smallest per-page target [ScanBudget] asks the downscaler for,
/// however many pages share [scanInlineByteBudget]. Below about 120 KiB a
/// printed menu page stops being legible to the vision model, so a scan
/// that cannot fit at this size is refused rather than sent unreadable.
const int minScanPageTargetBytes = 120 * 1024;

/// The outcome of [ScanBudget.fit].
sealed class ScanFit {
  const new();
}

/// The scan fits [scanInlineByteBudget]: [scan] is what to send.
final class ScanFitted extends ScanFit {
  /// Creates the outcome carrying the [scan] to send.
  const new(this.scan);

  /// The scan to send: the input itself when it already fitted, otherwise
  /// a rebuilt scan of shrunk pages in the same order.
  final ScannedMenu scan;
}

/// The scan's images could not be shrunk to fit: even after downscaling
/// they weigh [totalBytes], above [budgetBytes].
final class ScanTooLarge extends ScanFit {
  /// Creates the outcome naming the [totalBytes] reached and the
  /// [budgetBytes] they had to fit.
  const new({required this.totalBytes, required this.budgetBytes});

  /// The image bytes, summed over every non-PDF page, after downscaling.
  final int totalBytes;

  /// The budget they had to fit, [ScanBudget.budgetBytes].
  final int budgetBytes;
}

/// Fits the image pages of a [ScannedMenu] into one request's inline
/// budget (issue #298). Pure apart from the [downscaler] it is given.
///
/// PDF pages pass through untouched and are not counted: the downscaler
/// cannot shrink a PDF, and the backend and the direct client already cap
/// a PDF on its own. Never throws, because the downscaler does not.
final class ScanBudget {
  /// Creates a budget of [budgetBytes] that shrinks pages with
  /// [downscaler], never asking for less than [minPageBytes] per page.
  const new({
    required this.downscaler,
    this.budgetBytes = scanInlineByteBudget,
    this.minPageBytes = minScanPageTargetBytes,
  });

  /// Shrinks one image page towards a byte target.
  final ImageDownscaler downscaler;

  /// The most image bytes the scan may carry, summed over its pages.
  final int budgetBytes;

  /// The smallest per-page target handed to [downscaler].
  final int minPageBytes;

  /// Returns [ScanFitted] with [scan] itself when its image pages already
  /// fit [budgetBytes]; otherwise shrinks every image page towards an even
  /// share of the budget (at least [minPageBytes]) and returns the rebuilt
  /// scan, or [ScanTooLarge] when the shrunk images still do not fit.
  Future<ScanFit> fit(ScannedMenu scan) async {
    final images = scan.pages.where((page) => !page.isPdf).toList();
    if (_imageBytes(scan.pages) <= budgetBytes) return ScanFitted(scan);

    final share = budgetBytes ~/ images.length;
    final perPage = share > minPageBytes ? share : minPageBytes;
    final fitted = <ScannedPage>[];
    for (final page in scan.pages) {
      fitted.add(
        page.isPdf
            ? page
            : await downscaler.downscaleTo(page, targetBytes: perPage),
      );
    }
    final total = _imageBytes(fitted);
    if (total > budgetBytes) {
      return ScanTooLarge(totalBytes: total, budgetBytes: budgetBytes);
    }
    return ScanFitted(ScannedMenu(pages: fitted));
  }

  static int _imageBytes(List<ScannedPage> pages) {
    var total = 0;
    for (final page in pages) {
      if (!page.isPdf) total += page.bytes.length;
    }
    return total;
  }
}
