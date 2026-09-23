/// Opens a link outside KetoClub itself — the venue's own page on Wolt or
/// 10bis (issue #53) — in whatever app or browser the device hands it to.
library;

import 'package:url_launcher/url_launcher.dart' as launcher;

/// Opens a link in an external application, never inside KetoClub itself.
///
/// A hint the UI acts on, never a guarantee: the platform may have no
/// handler for a given link, the user may dismiss a chooser, or the call
/// may fail for a reason this interface cannot see. [open] never throws —
/// a failed launch reports `false` rather than breaking whatever screen
/// asked for it, the same never-throw contract `Connectivity` and
/// `ScreenBrightness` keep (`connectivity.dart`, `screen_brightness.dart`).
abstract interface class ExternalLinkOpener {
  /// Opens [uri] externally, returning whether the platform reports it was
  /// launched.
  ///
  /// Never throws.
  Future<bool> open(Uri uri);
}

/// An [ExternalLinkOpener] backed by the `url_launcher` plugin.
///
/// Always requests [launcher.LaunchMode.externalApplication]: this is a
/// deep link out to the venue's own platform, never a page KetoClub wants
/// to frame inside an in-app browser.
final class UrlLauncherLinkOpener implements ExternalLinkOpener {
  /// Creates a link opener. Touches no platform channel until [open] is
  /// called — `url_launcher`'s top-level functions open one lazily on
  /// first use, not at construction — so `di.dart` may build this directly
  /// while assembling the dependency graph (`di.dart`'s own doc comment,
  /// "no constructor called here may perform plugin I/O").
  const new();

  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launcher.launchUrl(
        uri,
        mode: launcher.LaunchMode.externalApplication,
      );
      // A broken plugin or a platform that refuses the call must not break
      // the screen that asked for it (this interface's own doc comment).
    } on Exception {
      return false;
    }
  }
}
