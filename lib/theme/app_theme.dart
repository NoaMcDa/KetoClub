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
      neutralSurfaces: NeutralSurfaces(
        surface2: AppTokens.lightSurface2,
        line2: ink.withValues(alpha: AppTokens.line2Alpha),
      ),
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
      neutralSurfaces: NeutralSurfaces(
        surface2: AppTokens.darkSurface2,
        line2: ink.withValues(alpha: AppTokens.line2Alpha),
      ),
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
    required NeutralSurfaces neutralSurfaces,
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
        neutralSurfaces,
        PhotoPlaceholder(gradient: photoGradient, ink: photoInk),
      ],
    );
  }
}

/// The artboard's `--surface2` and `--line2`: a second, quieter surface
/// and a fainter hairline shared across verdicts, rather than belonging to
/// any one of them (`.design/theme-snippet.txt`).
///
/// A [ThemeExtension], the same shape as [PhotoPlaceholder] just below and
/// for the same reason: [VerdictTone] carries only the roles a single
/// verdict palette needs, and these two tokens are neutral, not
/// per-verdict, so they do not belong there. [line2] is pre-composed as
/// `ink` at [AppTokens.line2Alpha] — the same alpha-over-ink treatment
/// [AppTheme] already gives [ThemeData.dividerColor] from
/// [AppTokens.lineAlpha] — rather than exposing the bare alpha, so a caller
/// never has to know which ink colour to layer it over.
@immutable
final class NeutralSurfaces extends ThemeExtension<NeutralSurfaces> {
  /// Creates a neutral-surfaces style.
  const new({required this.surface2, required this.line2});

  /// The artboard's `--surface2`: a second, quieter surface than
  /// [ThemeData.cardColor]/[ColorScheme.surface].
  final Color surface2;

  /// The artboard's `--line2`: a fainter hairline than
  /// [ThemeData.dividerColor].
  final Color line2;

  @override
  NeutralSurfaces copyWith({Color? surface2, Color? line2}) {
    return NeutralSurfaces(
      surface2: surface2 ?? this.surface2,
      line2: line2 ?? this.line2,
    );
  }

  @override
  NeutralSurfaces lerp(ThemeExtension<NeutralSurfaces>? other, double t) {
    if (other is! NeutralSurfaces) return this;
    return NeutralSurfaces(
      surface2: Color.lerp(surface2, other.surface2, t) ?? surface2,
      line2: Color.lerp(line2, other.line2, t) ?? line2,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NeutralSurfaces &&
      other.surface2 == surface2 &&
      other.line2 == line2;

  @override
  int get hashCode => Object.hash(surface2, line2);

  /// Reads the [NeutralSurfaces] registered on the ambient [Theme].
  ///
  /// Falls back to the light-theme values when none is registered, the
  /// same fallback [VerdictColors.of] uses and for the same reason: many
  /// existing widget tests pump a bare [MaterialApp] with no `theme:`
  /// argument.
  // ignore: prefer_constructors_over_static_methods
  static NeutralSurfaces of(BuildContext context) {
    final extension = Theme.of(context).extension<NeutralSurfaces>();
    if (extension != null) return extension;
    return NeutralSurfaces(
      surface2: AppTokens.lightSurface2,
      line2: AppTokens.lightInk.withValues(alpha: AppTokens.line2Alpha),
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
