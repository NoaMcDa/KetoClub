import 'package:flutter/foundation.dart';

/// A cheap content hash of [bytes], for [ScannedPage.hashCode].
///
/// A 31-multiplier rolling hash kept under 2^30, so every intermediate
/// value stays exact on the web, where an `int` is a JavaScript double
/// and a 32-bit FNV multiply would silently lose low bits.
int _contentHashOf(Uint8List bytes) {
  var hash = 17;
  for (final byte in bytes) {
    hash = (hash * 31 + byte) & 0x3fffffff;
  }
  return hash;
}

/// One photographed or picked page of a menu, held in memory only
/// (architecture.md D15; issues #82, #89).
///
/// Deliberately has no `toJson`: a page must never enter the Hive cache,
/// a log or the settings store. It lives from the moment the user picks
/// it until the one vision request that reads it, and on the Scan screen
/// as a thumbnail. [toString] names the type and size only, never the
/// bytes.
@immutable
final class ScannedPage {
  /// Creates a page of [mimeType] holding [bytes].
  ///
  /// [bytes] is exposed through an unmodifiable view rather than copied,
  /// so a 3 MiB page is not duplicated; callers must not mutate the list
  /// they pass in.
  new({required this.mimeType, required Uint8List bytes})
    : bytes = bytes.asUnmodifiableView(),
      contentHash = _contentHashOf(bytes);

  /// `image/jpeg`, what a camera or photo picker usually yields.
  static const String jpeg = 'image/jpeg';

  /// `image/png`.
  static const String png = 'image/png';

  /// `image/webp`.
  static const String webp = 'image/webp';

  /// `application/pdf`: a whole menu document rather than a photograph.
  static const String pdf = 'application/pdf';

  /// The page's media type; see [jpeg], [png], [webp] and [pdf].
  final String mimeType;

  /// The page's raw, un-encoded bytes, read-only.
  final Uint8List bytes;

  /// A hash of [bytes], computed once at construction so [hashCode] and
  /// [operator ==] do not walk a large page on every call.
  final int contentHash;

  /// Whether this page is a PDF document rather than an image.
  bool get isPdf => mimeType == pdf;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ScannedPage) return false;
    if (other.mimeType != mimeType) return false;
    if (other.bytes.length != bytes.length) return false;
    if (other.contentHash != contentHash) return false;
    for (var i = 0; i < bytes.length; i++) {
      if (other.bytes[i] != bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(mimeType, bytes.length, contentHash);

  @override
  String toString() => 'ScannedPage($mimeType, ${bytes.length} bytes)';
}

/// The pages of one scanned menu, in reading order, sent to the vision
/// classifier in a single request (architecture.md D6, D15; issue #89).
///
/// Holds at most `maxScanPages` pages of at most `maxScanPageBytes` each
/// by the Scan controller's own enforcement (issue #82); this type does
/// not police the bounds, so a test can build any shape. Like
/// [ScannedPage] it has no `toJson`: a `Menu` never carries bytes, and
/// this is the type that keeps them out of it.
@immutable
final class ScannedMenu {
  /// Creates a scan of [pages], kept as an unmodifiable copy.
  new({required List<ScannedPage> pages})
    : pages = List<ScannedPage>.unmodifiable(pages);

  /// The pages, in the order the user added them. Unmodifiable.
  final List<ScannedPage> pages;

  /// The sum of every page's byte length.
  int get totalBytes {
    var total = 0;
    for (final page in pages) {
      total += page.bytes.length;
    }
    return total;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ScannedMenu) return false;
    if (other.pages.length != pages.length) return false;
    for (var i = 0; i < pages.length; i++) {
      if (other.pages[i] != pages[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(pages);

  @override
  String toString() => 'ScannedMenu(${pages.length} pages, $totalBytes bytes)';
}
