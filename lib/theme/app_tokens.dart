import 'package:flutter/material.dart';

/// Raw sRGB colour constants for the design tokens in
/// `.design/theme-snippet.txt`, plus the alpha values for the two line
/// tokens.
///
/// ## Where the numbers came from
///
/// The snippet defines most tokens as `oklch(L C H)` — the design tool's
/// working colour space — rather than hex. Flutter's [Color] takes packed
/// ARGB, so every `oklch()` token was converted once, offline, by the CSS
/// Color 4 pipeline: oklch → oklab → LMS → linear sRGB → the sRGB transfer
/// function → 8-bit-per-channel ARGB. **That conversion is never repeated at
/// runtime** — doing oklch math on every frame would be wasted work for a
/// palette that never changes, and it would silently drift if the reference
/// implementation changed. The results are the literals below.
///
/// Four tokens land outside the sRGB gamut at their stated lightness and
/// chroma. Those four were gamut-mapped by **reducing chroma at constant L
/// and hue** (moving straight toward the achromatic axis in the LCh sense)
/// until the colour re-entered sRGB, not by clipping each of R, G and B
/// independently — per-channel clipping shifts both hue and lightness, which
/// chroma reduction does not. Each mapped token's doc comment below records
/// the chroma it was mapped to.
///
/// | Token | oklch | ARGB | Notes |
/// |---|---|---|---|
/// | light accent | 0.52 0.10 148 | `0xFF3C7847` | |
/// | light accent-hover | 0.42 0.10 148 | `0xFF1D5B2B` | |
/// | light green | 0.56 0.13 148 | `0xFF338946` | superseded, see below |
/// | light green-tint | 0.965 0.022 152 | `0xFFE9F8EC` | |
/// | light green-ink | 0.40 0.10 150 | `0xFF115629` | |
/// | light amber | 0.75 0.14 74 | `0xFFE29F36` | |
/// | light amber-tint | 0.965 0.032 85 | `0xFFFDF2DC` | |
/// | light amber-ink | 0.44 0.10 66 | `0xFF764500` | mapped, C 0.100→0.0981 |
/// | light red | 0.56 0.17 27 | `0xFFC44039` | |
/// | light red-tint | 0.965 0.020 25 | `0xFFFFEFEE` | gamut-mapped, C→0.0172 |
/// | light red-ink | 0.47 0.14 27 | `0xFF9A322C` | |
/// | dark accent | 0.74 0.13 148 | `0xFF6DC17B` | |
/// | dark accent-hover | 0.82 0.12 148 | `0xFF8CDA98` | |
/// | dark green | 0.76 0.14 148 | `0xFF6DC97D` | |
/// | dark green-tint | 0.30 0.055 150 | `0xFF17351F` | |
/// | dark green-ink | 0.85 0.13 150 | `0xFF8CE6A0` | |
/// | dark amber | 0.81 0.13 78 | `0xFFEFB656` | |
/// | dark amber-tint | 0.31 0.05 72 | `0xFF402C11` | |
/// | dark amber-ink | 0.89 0.11 82 | `0xFFFFD484` | gamut-mapped, C→0.1095 |
/// | dark red | 0.66 0.17 27 | `0xFFE86156` | |
/// | dark red-tint | 0.29 0.065 25 | `0xFF461D1A` | |
/// | dark red-ink | 0.78 0.14 27 | `0xFFFF968A` | mapped, C 0.140→0.1285 |
///
/// ## Contrast fixes — see issue #64
///
/// Three pairs measured below WCAG AA on `main` (`phase2_discovery_research
/// .md` §8.3) were darkened/lightened to clear 4.5:1, diverging from the
/// artboard's own literal values by design — visual fidelity lost out to
/// legibility for these three tokens only. Every drawn pair, including
/// these three, is now pinned to one decimal by `test/theme/contrast_test
/// .dart`, which implements WCAG 2.x relative luminance and contrast ratio
/// itself rather than trusting the numbers below to stay true:
///
/// - `lightGreen` was `0xFF338946`, now `0xFF2A7A3B` — `lightGreenOn`
///   (`0xFFFAF7F0`) on it, the green status pill's own 10px bold text, was
///   4.08:1 and is now **4.97:1**.
/// - `lightInk3` was `0xFFA09484`, now `0xFF7C6F5F` — on `lightBg`
///   (`0xFFFAF7F0`) it was 2.78:1 and is now **4.57:1**.
/// - `darkInk3` was `0xFF7D7364`, now `0xFF8E8474` — on `darkBg`
///   (`0xFF14120E`) it was 4.02:1 and is now **5.08:1**.
///
/// `lightGreenTint` and `lightGreenInk` are unchanged; only the saturated
/// `lightGreen` (the pill/rail colour) moved.
@immutable
abstract final class AppTokens {
  // Achromatic tokens — already hex in the snippet, copied verbatim.

  /// Light `--bg`.
  static const Color lightBg = Color(0xFFFAF7F0);

  /// Light `--surface`.
  static const Color lightSurface = Color(0xFFFFFFFF);

  /// Light `--surface2`.
  static const Color lightSurface2 = Color(0xFFF4EFE4);

  /// Light `--ink`.
  static const Color lightInk = Color(0xFF1F1C17);

  /// Light `--ink2`.
  static const Color lightInk2 = Color(0xFF6F675B);

  /// Light `--ink3`. Darkened from the artboard's `0xFFA09484` to pass AA
  /// on [lightBg] — see the class doc comment's contrast-fixes note.
  static const Color lightInk3 = Color(0xFF7C6F5F);

  /// Light `--accent-ink` — text drawn on [lightAccent].
  static const Color lightAccentInk = Color(0xFFFAF7F0);

  /// Light `--green-on` — text drawn on [lightGreen].
  static const Color lightGreenOn = Color(0xFFFAF7F0);

  /// Light `--amber-on` — text drawn on [lightAmber].
  static const Color lightAmberOn = Color(0xFF2A1E08);

  /// Light `--red-on` — text drawn on [lightRed].
  static const Color lightRedOn = Color(0xFFFAF7F0);

  /// Light `--photo` gradient start.
  static const Color lightPhotoStart = Color(0xFFE9E1CF);

  /// Light `--photo` gradient end.
  static const Color lightPhotoEnd = Color(0xFFD8CBB0);

  /// Light `--photo-ink`.
  static const Color lightPhotoInk = Color(0xFF8B7D63);

  /// Light `--shadow` colour (opacity folded in; blur/spread live on the
  /// call site since [Color] cannot carry them).
  static const Color lightShadow = Color(0x661F1C17);

  /// Dark `--bg`.
  static const Color darkBg = Color(0xFF14120E);

  /// Dark `--surface`.
  static const Color darkSurface = Color(0xFF1E1B15);

  /// Dark `--surface2`.
  static const Color darkSurface2 = Color(0xFF272218);

  /// Dark `--ink`.
  static const Color darkInk = Color(0xFFF5F0E4);

  /// Dark `--ink2`.
  static const Color darkInk2 = Color(0xFFA99E8C);

  /// Dark `--ink3`. Lightened from the artboard's `0xFF7D7364` to pass AA
  /// on [darkBg] — see the class doc comment's contrast-fixes note.
  static const Color darkInk3 = Color(0xFF8E8474);

  /// Dark `--accent-ink` — text drawn on [darkAccent].
  static const Color darkAccentInk = Color(0xFF14120E);

  /// Dark `--green-on` — text drawn on [darkGreen].
  static const Color darkGreenOn = Color(0xFF0F1710);

  /// Dark `--amber-on` — text drawn on [darkAmber].
  static const Color darkAmberOn = Color(0xFF1C1406);

  /// Dark `--red-on` — text drawn on [darkRed].
  static const Color darkRedOn = Color(0xFF170C0A);

  /// Dark `--photo` gradient start.
  static const Color darkPhotoStart = Color(0xFF322C22);

  /// Dark `--photo` gradient end.
  static const Color darkPhotoEnd = Color(0xFF1C180F);

  /// Dark `--photo-ink`.
  static const Color darkPhotoInk = Color(0xFF6B6152);

  /// Dark `--shadow` colour.
  static const Color darkShadow = Color(0xD9000000);

  // Chromatic tokens — converted from oklch by the table in the class doc
  // comment above. Never recompute oklch at runtime.

  /// Light `--accent`.
  static const Color lightAccent = Color(0xFF3C7847);

  /// Light `--accent-hover`.
  static const Color lightAccentHover = Color(0xFF1D5B2B);

  /// Light `--green`. Darkened from the artboard's `0xFF338946` to pass AA
  /// against [lightGreenOn] — see the class doc comment's contrast-fixes
  /// note.
  static const Color lightGreen = Color(0xFF2A7A3B);

  /// Light `--green-tint`.
  static const Color lightGreenTint = Color(0xFFE9F8EC);

  /// Light `--green-ink`.
  static const Color lightGreenInk = Color(0xFF115629);

  /// Light `--amber`.
  static const Color lightAmber = Color(0xFFE29F36);

  /// Light `--amber-tint`.
  static const Color lightAmberTint = Color(0xFFFDF2DC);

  /// Light `--amber-ink`. Gamut-mapped: chroma 0.100 → 0.0981 at constant L
  /// and hue.
  static const Color lightAmberInk = Color(0xFF764500);

  /// Light `--red`.
  static const Color lightRed = Color(0xFFC44039);

  /// Light `--red-tint`. Gamut-mapped: chroma → 0.0172 at constant L and
  /// hue.
  static const Color lightRedTint = Color(0xFFFFEFEE);

  /// Light `--red-ink`.
  static const Color lightRedInk = Color(0xFF9A322C);

  /// Dark `--accent`.
  static const Color darkAccent = Color(0xFF6DC17B);

  /// Dark `--accent-hover`.
  static const Color darkAccentHover = Color(0xFF8CDA98);

  /// Dark `--green`.
  static const Color darkGreen = Color(0xFF6DC97D);

  /// Dark `--green-tint`.
  static const Color darkGreenTint = Color(0xFF17351F);

  /// Dark `--green-ink`.
  static const Color darkGreenInk = Color(0xFF8CE6A0);

  /// Dark `--amber`.
  static const Color darkAmber = Color(0xFFEFB656);

  /// Dark `--amber-tint`.
  static const Color darkAmberTint = Color(0xFF402C11);

  /// Dark `--amber-ink`. Gamut-mapped: chroma → 0.1095 at constant L and
  /// hue.
  static const Color darkAmberInk = Color(0xFFFFD484);

  /// Dark `--red`.
  static const Color darkRed = Color(0xFFE86156);

  /// Dark `--red-tint`.
  static const Color darkRedTint = Color(0xFF461D1A);

  /// Dark `--red-ink`. Gamut-mapped: chroma 0.140 → 0.1285 at constant L
  /// and hue.
  static const Color darkRedInk = Color(0xFFFF968A);

  // `--line` / `--line2` are alpha-over-ink in the snippet, not their own
  // hex; expose the alphas so `AppTheme` can compute `ink.withValues(...)`
  // rather than hard-coding a second colour that could drift from `ink`.

  /// Alpha for `--line` (11%), applied over the theme's ink colour.
  static const double lineAlpha = 0.11;

  /// Alpha for `--line2` (7%), applied over the theme's ink colour.
  static const double line2Alpha = 0.07;
}
