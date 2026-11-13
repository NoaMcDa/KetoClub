import 'package:flutter/foundation.dart' show immutable;
import 'package:ketoclub/models/scanned_menu.dart';

/// Why a [PagePicker] call collected no page although the user did not
/// cancel it (issue #284): each reason has its own copy, so a refused
/// permission never looks like a change of mind.
enum PagePickFailureReason {
  /// The camera permission is refused. The way out is the device's
  /// settings, not another tap.
  cameraDenied,

  /// Access to the photo library or the files is refused.
  libraryDenied,

  /// The picker failed for any other reason (a plugin error, a file that
  /// could not be read). Trying again may work.
  failed,
}

/// What one [PagePicker] call collected. Sealed: [PagesPicked] or
/// [PagePickFailed].
@immutable
sealed class PagePickResult {
  /// Const constructor for the subclasses.
  const new();

  /// The pages collected; empty for a cancelled picker and for every
  /// [PagePickFailed].
  List<ScannedPage> get pages;
}

/// The pages the user picked, in their order; empty when the user
/// cancelled or nothing picked was a page KetoClub sends on.
final class PagesPicked extends PagePickResult {
  /// Creates the result for [pages].
  const new(this.pages);

  /// A cancelled picker: no page, and nothing to tell the user.
  static const PagesPicked none = PagesPicked(<ScannedPage>[]);

  @override
  final List<ScannedPage> pages;
}

/// The picker could not collect a page, for [reason].
final class PagePickFailed extends PagePickResult {
  /// Creates the failure for [reason].
  const new(this.reason);

  /// Why no page was collected.
  final PagePickFailureReason reason;

  @override
  List<ScannedPage> get pages => const <ScannedPage>[];

  @override
  bool operator ==(Object other) =>
      other is PagePickFailed && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'PagePickFailed($reason)';
}

/// Collects menu pages from the camera, the photo library or a PDF file
/// (architecture.md D15; issue #82).
///
/// Every method never throws. A cancelled picker answers
/// [PagesPicked.none]; a refused permission or a plugin error answers a
/// [PagePickFailed] naming which (issue #284), so "the user changed their
/// mind" and "KetoClub may not use the camera" read differently. The
/// pages come back as picked — no count or size bound is applied here;
/// the Scan controller enforces `maxScanPages` and `maxScanPageBytes`
/// itself, so it can say which bound a page broke.
abstract interface class PagePicker {
  /// Whether [takePhoto] can open a camera here. False on a computer's
  /// browser, where a "take photo" action would only open a file chooser
  /// beside "Choose photos" (issue #249); the Scan tab hides the action
  /// then.
  bool get canTakePhoto;

  /// Photographs one page with the camera.
  Future<PagePickResult> takePhoto();

  /// Picks one or more images from the photo library, in the order the
  /// user chose them.
  Future<PagePickResult> pickImages();

  /// Picks one PDF document, answered as a single page whose mime type is
  /// [ScannedPage.pdf].
  Future<PagePickResult> pickPdf();
}

/// The [PagePicker] the app ships with until the device picker lands
/// (issue #82): every call answers [PagesPicked.none], as if cancelled, with
/// no plugin I/O.
final class NoPagePicker implements PagePicker {
  /// Creates the picker; it holds no state.
  const new();

  @override
  bool get canTakePhoto => false;

  @override
  Future<PagePickResult> takePhoto() async => PagesPicked.none;

  @override
  Future<PagePickResult> pickImages() async => PagesPicked.none;

  @override
  Future<PagePickResult> pickPdf() async => PagesPicked.none;
}
