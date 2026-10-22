/// Shares the classified menu's plain-text summary through the platform's
/// own share sheet (issue #54), and the chef card as an image (Banto,
/// issue #420).
library;

import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// The file name the chef card image is shared under.
const String chefCardImageFileName = 'chef-card.png';

/// Shares text through whatever the platform hands the user — the OS share
/// sheet on mobile and desktop, the Web Share API (or its download
/// fallback) on web.
///
/// A hint the UI acts on, never a guarantee: the user may dismiss the
/// share sheet, or the platform may have no handler at all. [shareText]
/// never throws — a failed or dismissed share reports `false` rather than
/// breaking whatever screen asked for it, the same never-throw contract
/// `ExternalLinkOpener`, `Connectivity` and `ScreenBrightness` keep
/// (`external_link_opener.dart`, `connectivity.dart`,
/// `screen_brightness.dart`).
abstract interface class MenuSharer {
  /// Shares [text] through the platform's share sheet, with [subject] as
  /// the share's subject line where the platform supports one (e.g. an
  /// email's subject line). Returns whether the platform reports the
  /// share completed.
  ///
  /// Never throws.
  Future<bool> shareText(String text, {String? subject});

  /// Shares [png], a PNG image, as a file through the platform's share
  /// sheet, with [subject] as for [shareText]. Returns whether the
  /// platform reports the share completed.
  ///
  /// When the platform cannot share files (some web browsers, Linux), and
  /// [fallbackText] is given, shares [fallbackText] instead, calling
  /// [onTextFallback] first so the screen can say so; the result is then
  /// [shareText]'s. The image is handed to the platform only: nothing here
  /// writes it anywhere, and nothing uploads it.
  ///
  /// Never throws.
  Future<bool> shareImage(
    Uint8List png, {
    String? subject,
    String? fallbackText,
    void Function()? onTextFallback,
  });
}

/// The share call [SharePlusMenuSharer] makes: `SharePlus.instance.share`
/// unless a test passes its own.
typedef ShareCall = Future<ShareResult> Function(ShareParams params);

/// A [MenuSharer] backed by the `share_plus` plugin.
final class SharePlusMenuSharer implements MenuSharer {
  /// Creates a sharer. Touches no platform channel until [shareText] is
  /// called — `SharePlus.instance` only assembles a singleton wrapper
  /// around the plugin, not yet a platform channel, so `di.dart` may build
  /// this directly while assembling the dependency graph (`di.dart`'s own
  /// doc comment, "no constructor called here may perform plugin I/O"), the
  /// same reasoning `UrlLauncherLinkOpener` and `DeviceConnectivity` rely
  /// on for their own plugin handles.
  ///
  /// `share` replaces the plugin's own call, for a test; null uses
  /// `SharePlus.instance.share`, looked up on each call.
  const new({this._share});

  final ShareCall? _share;

  Future<ShareResult> _call(ShareParams params) =>
      (_share ?? SharePlus.instance.share)(params);

  @override
  Future<bool> shareText(String text, {String? subject}) async {
    try {
      final result = await _call(ShareParams(text: text, subject: subject));
      return result.status == ShareResultStatus.success;
      // A dismissed sheet, an unavailable share surface, or a broken
      // plugin must not break the screen that asked for it (this
      // interface's own doc comment) — report `false` rather than throw.
    } on Exception {
      return false;
    }
  }

  @override
  Future<bool> shareImage(
    Uint8List png, {
    String? subject,
    String? fallbackText,
    void Function()? onTextFallback,
  }) async {
    try {
      final result = await _call(
        ShareParams(
          files: <XFile>[
            XFile.fromData(
              png,
              mimeType: 'image/png',
              name: chefCardImageFileName,
            ),
          ],
          fileNameOverrides: const <String>[chefCardImageFileName],
          subject: subject,
          // On web a browser that cannot share files would otherwise
          // download the image or open an email: neither is a share, and
          // the app saves nothing (issue #420). Fall back to the text.
          downloadFallbackEnabled: false,
          mailToFallbackEnabled: false,
        ),
      );
      return result.status == ShareResultStatus.success;
      // A platform that cannot share files throws: an Exception on web
      // (Navigator.canShare() is false), an UnimplementedError on Linux.
    } on Exception {
      return await _fallBack(subject, fallbackText, onTextFallback);
      // ignore: avoid_catching_errors, the plugin's Linux "not supported".
    } on UnimplementedError {
      return await _fallBack(subject, fallbackText, onTextFallback);
    }
  }

  Future<bool> _fallBack(
    String? subject,
    String? fallbackText,
    void Function()? onTextFallback,
  ) async {
    if (fallbackText == null) return false;
    onTextFallback?.call();
    return await shareText(fallbackText, subject: subject);
  }
}
