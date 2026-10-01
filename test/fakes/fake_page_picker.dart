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
/// order. With its queue empty a method answers an empty list, exactly as
/// a cancelled picker does. Every call, of any method, is recorded in
/// [calls] in call order.
final class FakePagePicker implements PagePicker {
  /// Creates a picker with nothing queued and nothing recorded yet.
  /// [canTakePhoto] defaults to true, a phone.
  new({this.canTakePhoto = true});

  @override
  final bool canTakePhoto;

  final List<List<ScannedPage>> _photos = <List<ScannedPage>>[];
  final List<List<ScannedPage>> _images = <List<ScannedPage>>[];
  final List<List<ScannedPage>> _pdfs = <List<ScannedPage>>[];

  /// Every call made, in call order.
  final List<PagePickerCall> calls = <PagePickerCall>[];

  /// Queues [pages] as the answer to the next unanswered [takePhoto].
  void queueTakePhoto(List<ScannedPage> pages) => _photos.add(pages);

  /// Queues [pages] as the answer to the next unanswered [pickImages].
  void queuePickImages(List<ScannedPage> pages) => _images.add(pages);

  /// Queues [pages] as the answer to the next unanswered [pickPdf].
  void queuePickPdf(List<ScannedPage> pages) => _pdfs.add(pages);

  @override
  Future<List<ScannedPage>> takePhoto() async =>
      _answer(PagePickerCall.takePhoto, _photos);

  @override
  Future<List<ScannedPage>> pickImages() async =>
      _answer(PagePickerCall.pickImages, _images);

  @override
  Future<List<ScannedPage>> pickPdf() async =>
      _answer(PagePickerCall.pickPdf, _pdfs);

  List<ScannedPage> _answer(
    PagePickerCall call,
    List<List<ScannedPage>> queue,
  ) {
    calls.add(call);
    if (queue.isEmpty) return const <ScannedPage>[];
    return List<ScannedPage>.unmodifiable(queue.removeAt(0));
  }
}
