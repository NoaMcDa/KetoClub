/// Shares the classified menu's plain-text summary through the platform's
/// own share sheet (issue #54).
library;

import 'package:share_plus/share_plus.dart';

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
}

/// A [MenuSharer] backed by the `share_plus` plugin.
final class SharePlusMenuSharer implements MenuSharer {
  /// Creates a sharer. Touches no platform channel until [shareText] is
  /// called — `SharePlus.instance` only assembles a singleton wrapper
  /// around the plugin, not yet a platform channel, so `di.dart` may build
  /// this directly while assembling the dependency graph (`di.dart`'s own
  /// doc comment, "no constructor called here may perform plugin I/O"), the
  /// same reasoning `UrlLauncherLinkOpener` and `DeviceConnectivity` rely
  /// on for their own plugin handles.
  const new();

  @override
  Future<bool> shareText(String text, {String? subject}) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(text: text, subject: subject),
      );
      return result.status == ShareResultStatus.success;
      // A dismissed sheet, an unavailable share surface, or a broken
      // plugin must not break the screen that asked for it (this
      // interface's own doc comment) — report `false` rather than throw.
    } on Exception {
      return false;
    }
  }
}
