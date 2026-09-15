import 'package:flutter/material.dart';
import 'package:ketoclub/theme/app_tokens.dart';
import 'package:ketoclub/theme/app_typography.dart';
import 'package:ketoclub/theme/verdict_colors.dart';

/// Builds the app's light and dark [ThemeData] from [AppTokens]
/// (architecture.md §6.6). The only place either theme is assembled;
/// `app.dart` wires the results into `MaterialApp.theme` /
/// `MaterialApp.darkTheme`.
abstract final class AppTheme {
  /// The light theme, built from the `.app` block of
  /// `.design/theme-snippet.txt`.
  static ThemeData light() {
    const ink = AppTokens.lightInk;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppTokens.lightAccent,
      primary: AppTokens.lightAccent,
      onPrimary: AppTokens.lightAccentInk,
      surface: AppTokens.lightSurface,
      onSurface: ink,
      error: AppTokens.lightRed,
      onError: AppTokens.lightRedOn,
    );

    return _themeFrom(
      colorScheme: colorScheme,
      scaffoldBackground: AppTokens.lightBg,
      cardColor: AppTokens.lightSurface,
      dividerColor: ink.withValues(alpha: AppTokens.lineAlpha),
      ink: ink,
      ink2: AppTokens.lightInk2,
      verdictColors: VerdictColors.light(),
      photoGradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppTokens.lightPhotoStart, AppTokens.lightPhotoEnd],
      ),
      photoInk: AppTokens.lightPhotoInk,
    );
  }

  /// The dark theme, built from the `.app.dark` block of
  /// `.design/theme-snippet.txt`.
  static ThemeData dark() {
    const ink = AppTokens.darkInk;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppTokens.darkAccent,
      brightness: Brightness.dark,
      primary: AppTokens.darkAccent,
      onPrimary: AppTokens.darkAccentInk,
      surface: AppTokens.darkSurface,
      onSurface: ink,
      error: AppTokens.darkRed,
      onError: AppTokens.darkRedOn,
    );

    return _themeFrom(
      colorScheme: colorScheme,
      scaffoldBackground: AppTokens.darkBg,
      cardColor: AppTokens.darkSurface,
      dividerColor: ink.withValues(alpha: AppTokens.lineAlpha),
      ink: ink,
      ink2: AppTokens.darkInk2,
      verdictColors: VerdictColors.dark(),
      photoGradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppTokens.darkPhotoStart, AppTokens.darkPhotoEnd],
      ),
      photoInk: AppTokens.darkPhotoInk,
    );
  }

  static ThemeData _themeFrom({
    required ColorScheme colorScheme,
    required Color scaffoldBackground,
    required Color cardColor,
    required Color dividerColor,
    required Color ink,
    required Color ink2,
    required VerdictColors verdictColors,
    required LinearGradient photoGradient,
    required Color photoInk,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: colorScheme.brightness,
      scaffoldBackgroundColor: scaffoldBackground,
      cardColor: cardColor,
      dividerColor: dividerColor,
      fontFamily: AppTypography.uiFamily,
      fontFamilyFallback: AppTypography.uiFallback,
      textTheme: AppTypography.textTheme(ink: ink, ink2: ink2),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBackground,
        foregroundColor: ink,
        elevation: 0,
      ),
      extensions: [
        verdictColors,
        PhotoPlaceholder(gradient: photoGradient, ink: photoInk),
      ],
    );
  }
}

/// The artboard's `--photo` gradient and `--photo-ink`, for dish and venue
/// photo placeholders. A [ThemeExtension] rather than a field on
/// [VerdictColors]: it is unrelated to any verdict.
@immutable
final class PhotoPlaceholder extends ThemeExtension<PhotoPlaceholder> {
  /// Creates a photo placeholder style.
  const new({required this.gradient, required this.ink});

  /// The placeholder background gradient.
  final LinearGradient gradient;

  /// The icon/text colour drawn over [gradient].
  final Color ink;

  @override
  PhotoPlaceholder copyWith({LinearGradient? gradient, Color? ink}) {
    return PhotoPlaceholder(
      gradient: gradient ?? this.gradient,
      ink: ink ?? this.ink,
    );
  }

  @override
  PhotoPlaceholder lerp(ThemeExtension<PhotoPlaceholder>? other, double t) {
    if (other is! PhotoPlaceholder) return this;
    return PhotoPlaceholder(
      gradient: LinearGradient.lerp(gradient, other.gradient, t) ?? gradient,
      ink: Color.lerp(ink, other.ink, t) ?? ink,
    );
  }
}
