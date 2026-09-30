import 'package:flutter/foundation.dart'
    show LicenseEntry, LicenseEntryWithLineBreaks, LicenseRegistry, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:ketoclub/app.dart';
import 'package:ketoclub/di.dart';

void main() {
  // Shared links read `/venue/wolt/slug`, not `/#/venue/wolt/slug` (issue
  // #226). Web only: the call is a no-op elsewhere, but guarding it keeps
  // the intent plain. It must run before `runApp`, and the host must fall
  // back to `index.html` for unknown paths (docs/RUNNING.md).
  if (kIsWeb) usePathUrlStrategy();
  _registerFontLicenses();
  runApp(KetoClubApp(dependencies: buildDependencies()));
}

/// Registers the bundled fonts' SIL OFL 1.1 licence text with
/// [LicenseRegistry] so `showLicensePage` credits `Public Sans` and
/// `Instrument Serif` (issue #9).
///
/// [LicenseRegistry.addLicense] only stores the callback; the callback
/// itself — and the [rootBundle] read inside it, which is plugin I/O — runs
/// lazily the first time something asks for the licence list (e.g. opening
/// the licence page), never during this synchronous call. That keeps
/// `main()` free of plugin I/O at construction time, the same rule
/// `di.dart` follows (architecture.md §5, `test/di_test.dart`).
void _registerFontLicenses() {
  LicenseRegistry.addLicense(_fontLicenses);
}

Stream<LicenseEntry> _fontLicenses() async* {
  for (final asset in const [
    'assets/fonts/OFL-PublicSans.txt',
    'assets/fonts/OFL-InstrumentSerif.txt',
    'assets/fonts/OFL-Rubik.txt',
  ]) {
    final text = await rootBundle.loadString(asset);
    yield LicenseEntryWithLineBreaks(const ['ketoclub'], text);
  }
}
