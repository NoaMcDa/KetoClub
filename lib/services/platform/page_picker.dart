import 'package:ketoclub/models/scanned_menu.dart';

/// Collects menu pages from the camera, the photo library or a PDF file
/// (architecture.md D15; issue #82).
///
/// Every method never throws: a denied permission, a plugin error or a
/// cancelled picker all answer an empty list, so "the user changed their
/// mind" and "nothing could be read" look the same to the caller. The
/// pages come back as picked — no count or size bound is applied here;
/// the Scan controller enforces `maxScanPages` and `maxScanPageBytes`
/// itself, so it can say which bound a page broke.
abstract interface class PagePicker {
  /// Whether [takePhoto] can open a camera here. False on a computer's
  /// browser, where a "take photo" action would only open a file chooser
  /// beside "Choose photos" (issue #249); the Scan tab hides the action
  /// then.
  bool get canTakePhoto;

  /// Photographs one page with the camera. Empty when cancelled.
  Future<List<ScannedPage>> takePhoto();

  /// Picks one or more images from the photo library, in the order the
  /// user chose them. Empty when cancelled.
  Future<List<ScannedPage>> pickImages();

  /// Picks one PDF document, answered as a single page whose mime type is
  /// [ScannedPage.pdf]. Empty when cancelled.
  Future<List<ScannedPage>> pickPdf();
}

/// The [PagePicker] the app ships with until the device picker lands
/// (issue #82): every call answers an empty list, as if cancelled, with
/// no plugin I/O.
final class NoPagePicker implements PagePicker {
  /// Creates the picker; it holds no state.
  const new();

  @override
  bool get canTakePhoto => false;

  @override
  Future<List<ScannedPage>> takePhoto() async => const <ScannedPage>[];

  @override
  Future<List<ScannedPage>> pickImages() async => const <ScannedPage>[];

  @override
  Future<List<ScannedPage>> pickPdf() async => const <ScannedPage>[];
}
