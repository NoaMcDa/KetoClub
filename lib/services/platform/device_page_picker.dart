import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/services/platform/page_picker.dart';

/// Picks one PDF, or answers null when cancelled. The seam over
/// `file_picker`'s static API, so a test can answer without a plugin.
typedef PdfFilePick = Future<PlatformFile?> Function();

/// The longest edge, in pixels, the photo plugins downsize a picked image
/// to (issue #82). About 1600 px keeps a printed menu legible to the
/// model while holding a page well under `maxScanPageBytes`.
const int pickedImageMaxWidth = 1600;

/// The JPEG quality, 0 to 100, the photo plugins re-encode a picked image
/// with (issue #82).
const int pickedImageQuality = 80;

/// The [PagePicker] for a real device or browser, over `image_picker` and
/// `file_picker` (architecture.md D15; issue #82).
///
/// Bytes are read through `XFile.readAsBytes()` and
/// `PlatformFile.readAsBytes()`, never `dart:io`, so this file builds for
/// the web. Every method never throws: a denied camera permission, a
/// plugin error (an `Exception` or an `Error`) or a cancelled picker all
/// answer an empty list. A picked
/// file whose type is not one KetoClub sends on (JPEG, PNG, WebP, or a
/// PDF for [pickPdf]) is dropped rather than passed to the model.
///
/// The constructor performs no plugin I/O — `ImagePicker` is a plain
/// object and the file picker is reached only when [pickPdf] runs — so
/// `di.dart` can build it at start-up (`di_test` asserts this).
final class DevicePagePicker implements PagePicker {
  /// Creates a picker over [imagePicker] and [pdfPick]; each defaults to
  /// the real plugin. Tests pass fakes.
  new({ImagePicker? imagePicker, PdfFilePick? pdfPick})
    : _images = imagePicker ?? ImagePicker(),
      _pdfPick = pdfPick ?? _pickPdfFile;

  final ImagePicker _images;
  final PdfFilePick _pdfPick;

  static Future<PlatformFile?> _pickPdfFile() => FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const <String>['pdf'],
  );

  @override
  Future<List<ScannedPage>> takePhoto() async {
    try {
      final photo = await _images.pickImage(
        source: ImageSource.camera,
        maxWidth: pickedImageMaxWidth.toDouble(),
        imageQuality: pickedImageQuality,
      );
      if (photo == null) return const <ScannedPage>[];
      return await _pagesFrom(<XFile>[photo]);
    } on Object {
      return const <ScannedPage>[];
    }
  }

  @override
  Future<List<ScannedPage>> pickImages() async {
    try {
      final photos = await _images.pickMultiImage(
        maxWidth: pickedImageMaxWidth.toDouble(),
        imageQuality: pickedImageQuality,
      );
      return await _pagesFrom(photos);
    } on Object {
      return const <ScannedPage>[];
    }
  }

  @override
  Future<List<ScannedPage>> pickPdf() async {
    try {
      final file = await _pdfPick();
      if (file == null) return const <ScannedPage>[];
      final extension = (file.extension ?? _extensionOf(file.name))
          ?.toLowerCase();
      if (extension != 'pdf') return const <ScannedPage>[];
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return const <ScannedPage>[];
      return <ScannedPage>[
        ScannedPage(mimeType: ScannedPage.pdf, bytes: bytes),
      ];
    } on Object {
      return const <ScannedPage>[];
    }
  }

  /// Reads each of [files], keeping those whose type is an accepted image.
  /// A file that cannot be read is skipped, not fatal to the others.
  Future<List<ScannedPage>> _pagesFrom(List<XFile> files) async {
    final pages = <ScannedPage>[];
    for (final file in files) {
      try {
        final bytes = await file.readAsBytes();
        final mimeType = _imageMimeType(file, bytes);
        if (mimeType == null || bytes.isEmpty) continue;
        pages.add(ScannedPage(mimeType: mimeType, bytes: bytes));
      } on Object {
        continue;
      }
    }
    return pages;
  }

  /// The accepted image type of [file], or null when it is none of them.
  ///
  /// Trusts what the plugin declared, then the file name's extension, and
  /// finally the first bytes: on Android the plugin's own re-encode can
  /// leave a name with no extension and no declared type.
  static String? _imageMimeType(XFile file, Uint8List bytes) {
    final declared = file.mimeType?.toLowerCase();
    if (declared != null && _imageTypes.contains(declared)) return declared;
    final byExtension =
        _typeByExtension[_extensionOf(file.name)?.toLowerCase()];
    if (byExtension != null) return byExtension;
    // A declared type or an extension that names something else (a HEIC,
    // a GIF) is not second-guessed by the bytes.
    if (declared != null && declared.isNotEmpty) return null;
    if (_extensionOf(file.name) != null) return null;
    return _sniff(bytes);
  }

  static const Set<String> _imageTypes = <String>{
    ScannedPage.jpeg,
    ScannedPage.png,
    ScannedPage.webp,
  };

  static const Map<String, String> _typeByExtension = <String, String>{
    'jpg': ScannedPage.jpeg,
    'jpeg': ScannedPage.jpeg,
    'png': ScannedPage.png,
    'webp': ScannedPage.webp,
  };

  /// The extension after the last dot of [name], or null when there is none.
  static String? _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return null;
    return name.substring(dot + 1);
  }

  /// The image type [bytes] begin with, or null when unrecognised.
  static String? _sniff(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return ScannedPage.jpeg;
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return ScannedPage.png;
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x46 && // F
        bytes[8] == 0x57 && // W
        bytes[9] == 0x45 && // E
        bytes[10] == 0x42 && // B
        bytes[11] == 0x50) {
      // P
      return ScannedPage.webp;
    }
    return null;
  }
}
