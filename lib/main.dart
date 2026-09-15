import 'package:flutter/foundation.dart'
    show LicenseEntry, LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:ketoclub/app.dart';
import 'package:ketoclub/di.dart';

void main() {
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
  ]) {
    final text = await rootBundle.loadString(asset);
    yield LicenseEntryWithLineBreaks(const ['ketoclub'], text);
  }
}
