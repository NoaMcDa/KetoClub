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
    final line = ink.withValues(alpha: AppTokens.lineAlpha);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppTokens.lightAccent,
      primary: AppTokens.lightAccent,
      onPrimary: AppTokens.lightAccentInk,
      secondaryContainer: AppTokens.lightAccent,
      onSecondaryContainer: AppTokens.lightAccentInk,
      surface: AppTokens.lightSurface,
      onSurface: ink,
      onSurfaceVariant: AppTokens.lightInk3,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: AppTokens.lightSurface,
      surfaceContainerLow: AppTokens.lightBg,
      surfaceContainer: AppTokens.lightBg,
      surfaceContainerHigh: AppTokens.lightSurface2,
      surfaceContainerHighest: AppTokens.lightSurface2,
      outlineVariant: line,
      error: AppTokens.lightRed,
      onError: AppTokens.lightRedOn,
    );

    return _themeFrom(
      colorScheme: colorScheme,
      scaffoldBackground: AppTokens.lightBg,
      cardColor: AppTokens.lightSurface,
      dividerColor: line,
      ink: ink,
      ink2: AppTokens.lightInk2,
      ink3: AppTokens.lightInk3,
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
    final line = ink.withValues(alpha: AppTokens.lineAlpha);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppTokens.darkAccent,
      brightness: Brightness.dark,
      primary: AppTokens.darkAccent,
      onPrimary: AppTokens.darkAccentInk,
      secondaryContainer: AppTokens.darkAccent,
      onSecondaryContainer: AppTokens.darkAccentInk,
      surface: AppTokens.darkSurface,
      onSurface: ink,
      onSurfaceVariant: AppTokens.darkInk3,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: AppTokens.darkSurface,
      surfaceContainerLow: AppTokens.darkBg,
      surfaceContainer: AppTokens.darkBg,
      surfaceContainerHigh: AppTokens.darkSurface2,
      surfaceContainerHighest: AppTokens.darkSurface2,
      outlineVariant: line,
      error: AppTokens.darkRed,
      onError: AppTokens.darkRedOn,
    );

    return _themeFrom(
      colorScheme: colorScheme,
      scaffoldBackground: AppTokens.darkBg,
      cardColor: AppTokens.darkSurface,
      dividerColor: line,
      ink: ink,
      ink2: AppTokens.darkInk2,
      ink3: AppTokens.darkInk3,
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
    required Color ink3,
    required VerdictColors verdictColors,
    required NeutralSurfaces neutralSurfaces,
    required LinearGradient photoGradient,
    required Color photoInk,
  }) {
    final accent = colorScheme.primary;
    final accentInk = colorScheme.onPrimary;
    // The artboards' `.chip` (`.design/theme-snippet.txt`): a pill, 12.5px
    // semibold, `--surface` with a `--line` edge, and `--accent` filled
    // with `--accent-ink` text once selected — no check mark.
    bool selected(Set<WidgetState> states) =>
        states.contains(WidgetState.selected);
    const chipLabel = TextStyle(
      fontFamily: AppTypography.uiFamily,
      fontFamilyFallback: AppTypography.uiFallback,
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
    );
    // The artboards' tab bar (`.design/Discovery.dc.html`): no indicator
    // pill and no tinted surface; the active tab is `--accent`, the rest
    // `--ink3`, with 10px labels.
    TextStyle navLabel({required bool active}) => TextStyle(
      fontFamily: AppTypography.uiFamily,
      fontFamilyFallback: AppTypography.uiFallback,
      fontSize: 10,
      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
      color: active ? accent : ink3,
    );
    // The artboards' search field (`.design/Discovery.dc.html`): a
    // `--surface` box with a `--line` edge and a 14px radius.
    OutlineInputBorder fieldBorder(Color color, {double width = 1}) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: colorScheme.brightness,
      scaffoldBackgroundColor: scaffoldBackground,
      cardColor: cardColor,
      dividerColor: dividerColor,
      fontFamily: AppTypography.uiFamily,
      fontFamilyFallback: AppTypography.uiFallback,
      textTheme: AppTypography.textTheme(ink: ink, ink2: ink2, ink3: ink3),
      // `scrolledUnderElevation` and the transparent tint keep the bar the
      // page's own `--bg` once content scrolls under it, instead of
      // Material 3's tinted "scrolled under" surface. A title, where one
      // is shown (Settings, Saved, Scan), is the artboards' serif heading.
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBackground,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: AppTypography.displayStyle(size: 30, color: ink),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scaffoldBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => navLabel(active: selected(states)),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) =>
              IconThemeData(size: 22, color: selected(states) ? accent : ink3),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
        color: WidgetStateProperty.resolveWith(
          (states) => selected(states) ? accent : cardColor,
        ),
        side: WidgetStateBorderSide.resolveWith(
          (states) =>
              BorderSide(color: selected(states) ? accent : dividerColor),
        ),
        // A plain style whose *colour* is state-dependent: a chip resolves
        // only `labelStyle.color` per state, so a WidgetStateTextStyle
        // here would be merged as an all-null style and silently lost.
        labelStyle: chipLabel.copyWith(
          color: WidgetStateColor.resolveWith(
            (states) => selected(states) ? accentInk : ink2,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 13,
        ),
        prefixIconColor: ink3,
        suffixIconColor: ink3,
        hintStyle: TextStyle(fontSize: 13.5, color: ink3),
        border: fieldBorder(dividerColor),
        enabledBorder: fieldBorder(dividerColor),
        focusedBorder: fieldBorder(accent, width: 1.5),
        errorBorder: fieldBorder(colorScheme.error),
        focusedErrorBorder: fieldBorder(colorScheme.error, width: 1.5),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(color: dividerColor),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scaffoldBackground,
        modalBackgroundColor: scaffoldBackground,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(color: dividerColor),
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
