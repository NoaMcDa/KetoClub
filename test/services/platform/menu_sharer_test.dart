// SharePlusMenuSharer over a fake platform call (issues #54 and #420):
// the image is handed over as one PNG file, never downloaded or mailed;
// a platform that cannot share files gets the text instead, and says so.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:share_plus/share_plus.dart';

/// Eight bytes of PNG signature, enough to stand for an image.
final Uint8List _png = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
]);

/// A fake platform: records each call and answers with [answer], or
/// throws what [onFiles] gives for a call carrying files.
final class _Platform {
  final List<ShareParams> calls = <ShareParams>[];
  ShareResultStatus answer = ShareResultStatus.success;
  Object? onFiles;

  Future<ShareResult> share(ShareParams params) async {
    calls.add(params);
    final error = onFiles;
    if (error != null && (params.files?.isNotEmpty ?? false)) {
      // A test double rethrowing whatever the case under test needs.
      // ignore: only_throw_errors
      throw error;
    }
    return ShareResult('raw', answer);
  }
}

void main() {
  late _Platform platform;
  late SharePlusMenuSharer sharer;

  setUp(() {
    platform = _Platform();
    sharer = SharePlusMenuSharer(share: platform.share);
  });

  group('shareText', () {
    test(
      'passes the text and subject, and reports a completed share',
      () async {
        expect(await sharer.shareText('card', subject: 'Chef card'), isTrue);
        expect(platform.calls.single.text, 'card');
        expect(platform.calls.single.subject, 'Chef card');
      },
    );

    test('a dismissed sheet is not a completed share', () async {
      platform.answer = ShareResultStatus.dismissed;
      expect(await sharer.shareText('card'), isFalse);
    });
  });

  group('shareImage', () {
    test('the file path: one PNG file, no download or mail fallback', () async {
      var fellBack = false;
      final shared = await sharer.shareImage(
        _png,
        subject: 'Chef card',
        fallbackText: 'card',
        onTextFallback: () => fellBack = true,
      );

      expect(shared, isTrue);
      expect(fellBack, isFalse);
      final params = platform.calls.single;
      expect(params.text, isNull);
      expect(params.subject, 'Chef card');
      expect(params.files, hasLength(1));
      expect(params.files!.single.mimeType, 'image/png');
      expect(await params.files!.single.readAsBytes(), _png);
      expect(params.fileNameOverrides, <String>[chefCardImageFileName]);
      expect(params.downloadFallbackEnabled, isFalse);
      expect(params.mailToFallbackEnabled, isFalse);
    });

    test('a dismissed sheet reports false and shares no text', () async {
      platform.answer = ShareResultStatus.dismissed;
      expect(await sharer.shareImage(_png, fallbackText: 'card'), isFalse);
      expect(platform.calls, hasLength(1));
    });

    for (final (label, error) in <(String, Object)>[
      ('a browser that cannot share files', Exception('canShare false')),
      ('Linux', UnimplementedError('Sharing files not supported')),
    ]) {
      test('the fallback path ($label): the text is shared and the screen '
          'is told', () async {
        platform.onFiles = error;
        var fellBack = 0;
        final shared = await sharer.shareImage(
          _png,
          subject: 'Chef card',
          fallbackText: 'the card as text',
          onTextFallback: () => fellBack++,
        );

        expect(shared, isTrue);
        expect(fellBack, 1);
        expect(platform.calls, hasLength(2));
        expect(platform.calls.last.text, 'the card as text');
        expect(platform.calls.last.subject, 'Chef card');
        expect(platform.calls.last.files, isNull);
      });
    }

    test('with no fallback text, a platform without files reports false '
        'and shares nothing else', () async {
      platform.onFiles = Exception('canShare false');
      expect(await sharer.shareImage(_png), isFalse);
      expect(platform.calls, hasLength(1));
    });
  });
}
