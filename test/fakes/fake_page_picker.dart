import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/services/platform/page_picker.dart';

/// Which [FakePagePicker] method a recorded call was.
enum PagePickerCall {
  /// [FakePagePicker.takePhoto].
  takePhoto,

  /// [FakePagePicker.pickImages].
  pickImages,

  /// [FakePagePicker.pickPdf].
  pickPdf,
}

/// A scripted [PagePicker] for tests.
///
/// Each method draws from its own queue: [queueTakePhoto],
/// [queuePickImages] and [queuePickPdf] each add one answer, returned in
/// order, and [queueFailure] queues a [PagePickFailed] for one method.
/// With its queue empty a method answers [PagesPicked.none], exactly as a
/// cancelled picker does. Every call, of any method, is recorded in
/// [calls] in call order.
final class FakePagePicker implements PagePicker {
  /// Creates a picker with nothing queued and nothing recorded yet.
  /// [canTakePhoto] defaults to true, a phone.
  new({this.canTakePhoto = true});

  @override
  final bool canTakePhoto;

  final List<PagePickResult> _photos = <PagePickResult>[];
  final List<PagePickResult> _images = <PagePickResult>[];
  final List<PagePickResult> _pdfs = <PagePickResult>[];

  /// Every call made, in call order.
  final List<PagePickerCall> calls = <PagePickerCall>[];

  /// Queues [pages] as the answer to the next unanswered [takePhoto].
  void queueTakePhoto(List<ScannedPage> pages) =>
      _photos.add(PagesPicked(List<ScannedPage>.unmodifiable(pages)));

  /// Queues [pages] as the answer to the next unanswered [pickImages].
  void queuePickImages(List<ScannedPage> pages) =>
      _images.add(PagesPicked(List<ScannedPage>.unmodifiable(pages)));

  /// Queues [pages] as the answer to the next unanswered [pickPdf].
  void queuePickPdf(List<ScannedPage> pages) =>
      _pdfs.add(PagesPicked(List<ScannedPage>.unmodifiable(pages)));

  /// Queues a [PagePickFailed] for [reason] as the answer to the next
  /// unanswered [call].
  void queueFailure(PagePickerCall call, PagePickFailureReason reason) =>
      switch (call) {
        PagePickerCall.takePhoto => _photos,
        PagePickerCall.pickImages => _images,
        PagePickerCall.pickPdf => _pdfs,
      }.add(PagePickFailed(reason));

  @override
  Future<PagePickResult> takePhoto() async =>
      _answer(PagePickerCall.takePhoto, _photos);

  @override
  Future<PagePickResult> pickImages() async =>
      _answer(PagePickerCall.pickImages, _images);

  @override
  Future<PagePickResult> pickPdf() async =>
      _answer(PagePickerCall.pickPdf, _pdfs);

  PagePickResult _answer(PagePickerCall call, List<PagePickResult> queue) {
    calls.add(call);
    if (queue.isEmpty) return PagesPicked.none;
    return queue.removeAt(0);
  }
}
