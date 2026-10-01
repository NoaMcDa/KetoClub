// Pins WCAG AA contrast (issue #64, the contrast half) for every colour
// pair `StatusBadge`, the counter tiles and the theme's own ink tokens
// actually draw, by computing relative luminance and the contrast ratio
// itself — see `app_tokens.dart`'s "Contrast fixes" note for the three
// pairs this test was written to pin.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/theme/app_tokens.dart';
import 'package:ketoclub/theme/verdict_colors.dart';
import 'package:ketoclub/widgets/keto_score_badge.dart';

/// WCAG AA's minimum contrast ratio for normal-weight/small text — the
/// bar every pair below must clear.
const double _aaMinimum = 4.5;

/// Converts one gamma-encoded sRGB channel (`Color.r`/`.g`/`.b`, each
/// already 0.0-1.0) to linear light — the transfer function WCAG 2.x's
/// relative luminance formula is defined over.
double _linearise(double channel) {
  if (channel <= 0.04045) return channel / 12.92;
  return math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
}

/// The WCAG 2.x relative luminance of [color]: 0.0 (black) to 1.0
/// (white).
double _relativeLuminance(Color color) {
  final red = _linearise(color.r);
  final green = _linearise(color.g);
  final blue = _linearise(color.b);
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

/// The WCAG 2.x contrast ratio between [a] and [b]: 1.0 (identical
/// luminance) to 21.0 (black on white). Symmetric in its two arguments.
double _contrastRatio(Color a, Color b) {
  final lumA = _relativeLuminance(a) + 0.05;
  final lumB = _relativeLuminance(b) + 0.05;
  return lumA >= lumB ? lumA / lumB : lumB / lumA;
}

/// One drawn pair to check: a description, the foreground and the
/// background it is drawn on.
class _Pair {
  const new(this.description, this.foreground, this.background);

  final String description;
  final Color foreground;
  final Color background;
}

/// The pairs `StatusBadge` actually renders for [colors]: `on` on `pill`
/// for green and amber, but `ink` on `pill` for red, because red's
/// `pill` is itself a tint rather than the loud saturated colour — see
/// `VerdictTone`'s class doc comment and `StatusBadge.build`, which
/// special-cases the foreground for `DishVerdict.nonKeto` accordingly.
List<_Pair> _statusBadgePairs(VerdictColors colors) => [
  _Pair('green on/pill', colors.green.on, colors.green.pill),
  _Pair('amber on/pill', colors.amber.on, colors.amber.pill),
  _Pair('red ink/pill', colors.red.ink, colors.red.pill),
];

/// Each tone's `ink` against [background] — the colour `KetoScoreBadge`,
/// the waiter-script disclosure and the active counter tile draw text
/// and icons in.
List<_Pair> _inkOnBackgroundPairs(VerdictColors colors, Color background) => [
  _Pair('green ink/bg', colors.green.ink, background),
  _Pair('amber ink/bg', colors.amber.ink, background),
  _Pair('red ink/bg', colors.red.ink, background),
];

/// Registers one `test` per pair in [pairs] asserting it clears
/// `_aaMinimum`.
void _expectAllPass(List<_Pair> pairs) {
  for (final pair in pairs) {
    test('${pair.description} clears AA', () {
      final ratio = _contrastRatio(pair.foreground, pair.background);
      expect(ratio, greaterThanOrEqualTo(_aaMinimum));
    });
  }
}

/// The three tones `scoreTone` can return for [colors] and [muted] — one
/// per band of `KetoScoreBadge` (issue #241) — against [background].
List<_Pair> _scoreBandPairs(
  VerdictColors colors,
  Color muted,
  Color background,
) => [
  for (final (band, score) in [('high', 9.0), ('mid', 5.0), ('low', 2.0)])
    _Pair(
      'keto score $band band/bg',
      scoreTone(score, verdicts: colors, muted: muted),
      background,
    ),
];

/// The "Closed" tag over a venue photo (issue #227): the theme's `ink` on
/// its `surface`, the pair `VenueCard`'s closed pill draws.
List<_Pair> _closedTagPairs(Color ink, Color surface) => [
  _Pair('closed tag ink/surface', ink, surface),
];

/// The Saved row's remove icon (issue #254): the red `ink` drawn on the
/// card, which is the theme's `surface`.
List<_Pair> _removeIconPairs(VerdictColors colors, Color surface) => [
  _Pair('saved remove icon red ink/surface', colors.red.ink, surface),
];

/// The offline notice (issue #260): an `AppNotice.warning` draws its icon
/// and text in the amber tone's `ink` on its `tint`.
List<_Pair> _warningNoticePairs(VerdictColors colors) => [
  _Pair('offline notice amber ink/tint', colors.amber.ink, colors.amber.tint),
];

/// The drinks guide's carb chips (issue #259): `ink` on the card surface
/// for green and on the tint for amber and red, as `NetCarbsChip` draws.
List<_Pair> _carbChipPairs(VerdictColors colors, Color surface) => [
  _Pair('green carb chip ink/surface', colors.green.ink, surface),
  _Pair('amber carb chip ink/tint', colors.amber.ink, colors.amber.tint),
  _Pair('red carb chip ink/tint', colors.red.ink, colors.red.tint),
];

void main() {
  group('relative luminance and contrast ratio (self-test)', () {
    test('identical colours have a ratio of 1.0', () {
      expect(_contrastRatio(AppTokens.lightBg, AppTokens.lightBg), 1.0);
    });

    test('black on white is the maximum ratio, 21.0', () {
      const black = Color(0xFF000000);
      const white = Color(0xFFFFFFFF);
      expect(_contrastRatio(black, white), closeTo(21.0, 0.01));
    });

    test('the ratio is symmetric in its two arguments', () {
      final forward = _contrastRatio(AppTokens.lightGreen, AppTokens.lightBg);
      final backward = _contrastRatio(AppTokens.lightBg, AppTokens.lightGreen);
      expect(forward, backward);
    });
  });

  group('VerdictColors.light()', () {
    final colors = VerdictColors.light();
    const background = AppTokens.lightBg;

    _expectAllPass([
      ..._statusBadgePairs(colors),
      ..._inkOnBackgroundPairs(colors, background),
      ..._scoreBandPairs(colors, AppTokens.lightInk3, background),
      ..._closedTagPairs(AppTokens.lightInk, AppTokens.lightSurface),
      ..._removeIconPairs(colors, AppTokens.lightSurface),
      ..._warningNoticePairs(colors),
      ..._carbChipPairs(colors, AppTokens.lightSurface),
    ]);

    test('ink1, ink2 and ink3 all clear AA on the background', () {
      for (final ink in [
        AppTokens.lightInk,
        AppTokens.lightInk2,
        AppTokens.lightInk3,
      ]) {
        expect(
          _contrastRatio(ink, background),
          greaterThanOrEqualTo(_aaMinimum),
        );
      }
    });

    test('the green pill text was 4.08:1, now 4.97:1 (issue #64)', () {
      final ratio = _contrastRatio(colors.green.on, colors.green.pill);
      expect(ratio, closeTo(4.97, 0.05));
    });

    test('ink3 on the background was 2.78:1, now 4.57:1 (issue #64)', () {
      final ratio = _contrastRatio(AppTokens.lightInk3, background);
      expect(ratio, closeTo(4.57, 0.05));
    });
  });

  group('VerdictColors.dark()', () {
    final colors = VerdictColors.dark();
    const background = AppTokens.darkBg;

    _expectAllPass([
      ..._statusBadgePairs(colors),
      ..._inkOnBackgroundPairs(colors, background),
      ..._scoreBandPairs(colors, AppTokens.darkInk3, background),
      ..._closedTagPairs(AppTokens.darkInk, AppTokens.darkSurface),
      ..._removeIconPairs(colors, AppTokens.darkSurface),
      ..._warningNoticePairs(colors),
      ..._carbChipPairs(colors, AppTokens.darkSurface),
    ]);

    test('ink1, ink2 and ink3 all clear AA on the background', () {
      for (final ink in [
        AppTokens.darkInk,
        AppTokens.darkInk2,
        AppTokens.darkInk3,
      ]) {
        expect(
          _contrastRatio(ink, background),
          greaterThanOrEqualTo(_aaMinimum),
        );
      }
    });

    test('ink3 on the background was 4.02:1, now 5.08:1 (issue #64)', () {
      final ratio = _contrastRatio(AppTokens.darkInk3, background);
      expect(ratio, closeTo(5.08, 0.05));
    });
  });
}
