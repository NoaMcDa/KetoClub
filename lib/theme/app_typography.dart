import 'package:flutter/material.dart';

/// The two type families the `.design` artboards call for, and the
/// [TextTheme]s built on them.
///
/// `Public Sans` is the UI face (body text, labels, buttons); `Instrument
/// Serif` is the display face used for headings and the keto score (the
/// artboard's `.serif` class). Both are bundled under `assets/fonts/` and
/// declared in `pubspec.yaml`; their SIL OFL 1.1 licences are registered
/// with `LicenseRegistry` in `main.dart`.
///
/// **Neither family has Hebrew glyphs**, and the app is bilingual
/// (architecture.md D7), so every [TextStyle] here sets
/// [TextStyle.fontFamilyFallback] to a chain that reaches a Hebrew-capable
/// system face. Without it, Hebrew text would silently fall back to
/// whatever the platform default happens to be, which is untested and
/// varies by platform.
abstract final class AppTypography {
  /// The UI face's family name, as declared in `pubspec.yaml`.
  static const String uiFamily = 'Public Sans';

  /// The display face's family name, as declared in `pubspec.yaml`.
  static const String displayFamily = 'Instrument Serif';

  /// Fallback chain for [uiFamily] so Hebrew text reaches a real face.
  static const List<String> uiFallback = [
    'Noto Sans Hebrew',
    'Arial Hebrew',
    'Arial',
  ];

  /// Fallback chain for [displayFamily] so Hebrew display text (the keto
  /// score, serif headings) reaches a real face.
  static const List<String> displayFallback = [
    'Noto Serif Hebrew',
    'David',
    'serif',
  ];

  /// The base [TextTheme] over [uiFamily], for the given [ink] and [ink2]
  /// tokens (primary and secondary text colours differ between the light
  /// and dark themes).
  static TextTheme textTheme({required Color ink, required Color ink2}) {
    TextStyle ui({
      required double size,
      required FontWeight weight,
      required Color color,
    }) {
      return TextStyle(
        fontFamily: uiFamily,
        fontFamilyFallback: uiFallback,
        fontSize: size,
        fontWeight: weight,
        color: color,
      );
    }

    return TextTheme(
      displayLarge: displayStyle(size: 40, color: ink),
      displayMedium: displayStyle(size: 32, color: ink),
      displaySmall: displayStyle(size: 26, color: ink),
      headlineLarge: ui(size: 24, weight: FontWeight.w700, color: ink),
      headlineMedium: ui(size: 20, weight: FontWeight.w700, color: ink),
      headlineSmall: ui(size: 18, weight: FontWeight.w600, color: ink),
      titleLarge: ui(size: 16, weight: FontWeight.w700, color: ink),
      titleMedium: ui(size: 15, weight: FontWeight.w600, color: ink),
      titleSmall: ui(size: 14, weight: FontWeight.w600, color: ink),
      bodyLarge: ui(size: 16, weight: FontWeight.w400, color: ink),
      bodyMedium: ui(size: 14, weight: FontWeight.w400, color: ink),
      bodySmall: ui(size: 12.5, weight: FontWeight.w400, color: ink2),
      labelLarge: ui(size: 14, weight: FontWeight.w600, color: ink),
      labelMedium: ui(size: 12.5, weight: FontWeight.w600, color: ink2),
      labelSmall: ui(size: 10, weight: FontWeight.w800, color: ink2),
    );
  }

  /// A single [displayFamily] style at [size] and [color], for callers that
  /// need the serif face outside the [TextTheme] (e.g. the keto score).
  static TextStyle displayStyle({required double size, required Color color}) {
    return TextStyle(
      fontFamily: displayFamily,
      fontFamilyFallback: displayFallback,
      fontSize: size,
      fontWeight: FontWeight.w400,
      color: color,
    );
  }
}
