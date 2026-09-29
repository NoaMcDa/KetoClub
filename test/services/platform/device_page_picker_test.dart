import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/services/platform/device_page_picker.dart';

import 'page_picker_contract.dart';

/// A camera and library that answer what a test queued, and record the
/// downsizing arguments they were called with.
final class _FakeImagePicker extends ImagePicker {
  new({this.photo, this.library = const <XFile>[], this.error});

  final XFile? photo;
  final List<XFile> library;
  final Exception? error;

  ImageSource? lastSource;
  double? lastMaxWidth;
  int? lastQuality;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    lastSource = source;
    lastMaxWidth = maxWidth;
    lastQuality = imageQuality;
    if (error != null) throw error!;
    return photo;
  }

  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    lastMaxWidth = maxWidth;
    lastQuality = imageQuality;
    if (error != null) throw error!;
    return library;
  }
}

/// A picked file that holds [bytes] under [name].
final class _FakePlatformFile extends PlatformFile {
  new(this.name, this.bytes, {this.failRead = false});

  @override
  final String name;
  final Uint8List bytes;
  final bool failRead;

  @override
  Uri get uri => Uri.parse('memory://$name');

  @override
  XFile get xFile => XFile.fromData(bytes, path: name);

  @override
  int? lengthSync() => bytes.length;

  @override
  Future<int?> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async {
    if (failRead) throw PlatformException(code: 'read');
    return bytes;
  }

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

final Uint8List _jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1]);
final Uint8List _pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1]);
final Uint8List _webpBytes = Uint8List.fromList([
  ...'RIFF'.codeUnits,
  0,
  0,
  0,
  0,
  ...'WEBP'.codeUnits,
]);
final Uint8List _pdfBytes = Uint8List.fromList('%PDF-1.7'.codeUnits);

XFile _xfile(Uint8List bytes, {String name = 'page.jpg', String? mimeType}) =>
    // `path`, not `name`: the dart:io XFile ignores `name` and derives it
    // from the path.
    XFile.fromData(bytes, path: name, mimeType: mimeType);

void main() {
  runPagePickerContract(
    'DevicePagePicker',
    () => DevicePagePicker(
      imagePicker: _FakeImagePicker(),
      pdfPick: () async => null,
    ),
  );

  group('DevicePagePicker', () {
    test('builds with no plugin I/O', () {
      // Act & Assert: the default plugins are only reached on a pick.
      expect(DevicePagePicker.new, returnsNormally);
    });

    group('takePhoto', () {
      test('asks the camera to downsize and returns the page', () async {
        // Arrange
        final images = _FakeImagePicker(
          photo: _xfile(_jpegBytes, mimeType: 'image/jpeg'),
        );
        final picker = DevicePagePicker(imagePicker: images);

        // Act
        final pages = await picker.takePhoto();

        // Assert
        expect(images.lastSource, ImageSource.camera);
        expect(images.lastMaxWidth, pickedImageMaxWidth.toDouble());
        expect(images.lastQuality, pickedImageQuality);
        expect(pages, [
          ScannedPage(mimeType: ScannedPage.jpeg, bytes: _jpegBytes),
        ]);
      });

      test('answers empty when the user cancels', () async {
        final picker = DevicePagePicker(imagePicker: _FakeImagePicker());

        expect(await picker.takePhoto(), isEmpty);
      });

      test('answers empty when the plugin throws', () async {
        final picker = DevicePagePicker(
          imagePicker: _FakeImagePicker(
            error: PlatformException(code: 'camera_access_denied'),
          ),
        );

        expect(await picker.takePhoto(), isEmpty);
      });
    });

    group('pickImages', () {
      test('returns every page in the order chosen', () async {
        // Arrange
        final images = _FakeImagePicker(
          library: [
            _xfile(_pngBytes, name: 'a.png', mimeType: 'image/png'),
            _xfile(_webpBytes, name: 'b.webp', mimeType: 'image/webp'),
            _xfile(_jpegBytes, name: 'c.jpg', mimeType: 'image/jpeg'),
          ],
        );
        final picker = DevicePagePicker(imagePicker: images);

        // Act
        final pages = await picker.pickImages();

        // Assert
        expect(images.lastMaxWidth, pickedImageMaxWidth.toDouble());
        expect(images.lastQuality, pickedImageQuality);
        expect(pages.map((p) => p.mimeType), [
          ScannedPage.png,
          ScannedPage.webp,
          ScannedPage.jpeg,
        ]);
      });

      test('answers empty when the user cancels', () async {
        final picker = DevicePagePicker(imagePicker: _FakeImagePicker());

        expect(await picker.pickImages(), isEmpty);
      });

      test('answers empty when the plugin throws', () async {
        final picker = DevicePagePicker(
          imagePicker: _FakeImagePicker(
            error: PlatformException(code: 'photo_access_denied'),
          ),
        );

        expect(await picker.pickImages(), isEmpty);
      });

      test('drops an unsupported type but keeps the others', () async {
        // Arrange
        final picker = DevicePagePicker(
          imagePicker: _FakeImagePicker(
            library: [
              _xfile(_jpegBytes, name: 'menu.heic', mimeType: 'image/heic'),
              _xfile(Uint8List(3), name: 'anim.gif'),
              _xfile(_jpegBytes, name: 'ok.jpeg'),
            ],
          ),
        );

        // Act
        final pages = await picker.pickImages();

        // Assert
        expect(pages.single.mimeType, ScannedPage.jpeg);
      });

      test(
        'falls back to the file extension when no type is declared',
        () async {
          final picker = DevicePagePicker(
            imagePicker: _FakeImagePicker(
              library: [_xfile(Uint8List(2), name: 'scan.PNG')],
            ),
          );

          expect((await picker.pickImages()).single.mimeType, ScannedPage.png);
        },
      );

      test('sniffs the bytes when there is no type and no extension', () async {
        // Arrange
        final picker = DevicePagePicker(
          imagePicker: _FakeImagePicker(
            library: [
              _xfile(_jpegBytes, name: 'image_picker_1'),
              _xfile(_pngBytes, name: 'image_picker_2'),
              _xfile(_webpBytes, name: 'image_picker_3'),
              _xfile(Uint8List.fromList([1, 2, 3, 4]), name: 'image_picker_4'),
            ],
          ),
        );

        // Act
        final pages = await picker.pickImages();

        // Assert
        expect(pages.map((p) => p.mimeType), [
          ScannedPage.jpeg,
          ScannedPage.png,
          ScannedPage.webp,
        ]);
      });

      test('drops an empty file', () async {
        final picker = DevicePagePicker(
          imagePicker: _FakeImagePicker(
            library: [_xfile(Uint8List(0), name: 'empty.jpg')],
          ),
        );

        expect(await picker.pickImages(), isEmpty);
      });
    });

    group('pickPdf', () {
      test('returns the document as one pdf page', () async {
        // Arrange
        final picker = DevicePagePicker(
          pdfPick: () async => _FakePlatformFile('menu.pdf', _pdfBytes),
        );

        // Act
        final pages = await picker.pickPdf();

        // Assert
        expect(pages, [
          ScannedPage(mimeType: ScannedPage.pdf, bytes: _pdfBytes),
        ]);
        expect(pages.single.isPdf, isTrue);
      });

      test('answers empty when the user cancels', () async {
        final picker = DevicePagePicker(pdfPick: () async => null);

        expect(await picker.pickPdf(), isEmpty);
      });

      test('answers empty for a file that is not a pdf', () async {
        final picker = DevicePagePicker(
          pdfPick: () async => _FakePlatformFile('menu.docx', _pdfBytes),
        );

        expect(await picker.pickPdf(), isEmpty);
      });

      test('answers empty for a file with no extension', () async {
        final picker = DevicePagePicker(
          pdfPick: () async => _FakePlatformFile('menu', _pdfBytes),
        );

        expect(await picker.pickPdf(), isEmpty);
      });

      test('answers empty for an empty file', () async {
        final picker = DevicePagePicker(
          pdfPick: () async => _FakePlatformFile('menu.pdf', Uint8List(0)),
        );

        expect(await picker.pickPdf(), isEmpty);
      });

      test('answers empty when the bytes cannot be read', () async {
        final picker = DevicePagePicker(
          pdfPick: () async =>
              _FakePlatformFile('menu.pdf', _pdfBytes, failRead: true),
        );

        expect(await picker.pickPdf(), isEmpty);
      });

      test('answers empty when the plugin throws', () async {
        final picker = DevicePagePicker(
          pdfPick: () async => throw PlatformException(code: 'denied'),
        );

        expect(await picker.pickPdf(), isEmpty);
      });
    });
  });
}
