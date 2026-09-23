#!/usr/bin/env python3
"""Generate KetoClub's app-icon and splash source images (issue #66).

There is no external design asset to import: the artboards
(`.design/theme-snippet.txt`, `lib/theme/app_tokens.dart`) define colour
tokens, not a logo. This script draws a small vector-style leaf mark from
those tokens and writes the flat PNGs that `flutter_launcher_icons` and
`flutter_native_splash` need as their `image_path` inputs. It is a one-off,
manual-run generator (not part of `flutter pub get` or CI) — re-run it only
if the mark itself needs to change.

Requires Pillow: `pip install pillow`.

Usage: `python3 tool/generate_brand_assets.py` from the repository root.
Writes:
  assets/icon/icon.png              1024x1024, full-bleed, opaque background.
                                     Used for the iOS and web app icons and
                                     as the legacy (non-adaptive) Android icon.
  assets/icon/icon_foreground.png   1024x1024, transparent background, mark
                                     scaled to fit Android's adaptive-icon
                                     safe zone (centre 66%). Used with
                                     `adaptive_icon_background` in
                                     `pubspec.yaml`.
  assets/splash/branding_light.png  Transparent background, mark in the
                                     light-theme accent colour. Shown on
                                     `AppTokens.lightBg`.
  assets/splash/branding_dark.png   Transparent background, mark in the
                                     dark-theme accent colour. Shown on
                                     `AppTokens.darkBg`.

Colours below are copied from `lib/theme/app_tokens.dart` (light/dark
`--accent`, `--accent-hover` and `--green-tint`) so the generated mark
matches the app theme without importing Dart at generation time.
"""

from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw

# --- Tokens copied from lib/theme/app_tokens.dart --------------------------
LIGHT_ACCENT = (0x3C, 0x78, 0x47)  # AppTokens.lightAccent
LIGHT_ACCENT_HOVER = (0x1D, 0x5B, 0x2B)  # AppTokens.lightAccentHover
LIGHT_GREEN_TINT = (0xE9, 0xF8, 0xEC)  # AppTokens.lightGreenTint
DARK_ACCENT = (0x6D, 0xC1, 0x7B)  # AppTokens.darkAccent
DARK_ACCENT_HOVER = (0x8C, 0xDA, 0x98)  # AppTokens.darkAccentHover

CANVAS = 1024
CENTER = CANVAS // 2

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _rotate_point(x: float, y: float, cx: float, cy: float, deg: float):
    """Rotate (x, y) by `deg` degrees about (cx, cy)."""
    rad = math.radians(deg)
    dx, dy = x - cx, y - cy
    return (
        cx + dx * math.cos(rad) - dy * math.sin(rad),
        cy + dx * math.sin(rad) + dy * math.cos(rad),
    )


def draw_leaf(
    size: int,
    fill: tuple[int, int, int],
    vein: tuple[int, int, int],
    scale: float,
) -> Image.Image:
    """Draw a simple leaf mark: a rotated ellipse plus a vein and stem.

    `scale` is the leaf's half-width as a fraction of `size`, so the caller
    controls how much of the canvas the mark fills (e.g. the Android
    adaptive-icon safe zone, or a smaller splash mark).
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cx = cy = size / 2

    half_w = size * scale
    half_h = half_w * 0.55

    # The leaf body: an axis-aligned ellipse, then the whole layer is
    # rotated 45 degrees so it reads as a leaf rather than an eye.
    body = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(body)
    draw.ellipse(
        [cx - half_w, cy - half_h, cx + half_w, cy + half_h],
        fill=(*fill, 255),
    )
    body = body.rotate(-45, resample=Image.BICUBIC, center=(cx, cy))
    img.alpha_composite(body)

    # Vein plus stem: one continuous line along the ellipse's long axis
    # (kept short of the near tip so it reads as a vein, not a line poking
    # out of the shape) through to just past the far tip, where it becomes
    # the stem. Drawn as a single line so the two segments never gap.
    tip_a = _rotate_point(cx - half_w, cy, cx, cy, -45)
    tip_b = _rotate_point(cx + half_w, cy, cx, cy, -45)
    vein_a = (cx + (tip_a[0] - cx) * 0.82, cy + (tip_a[1] - cy) * 0.82)
    dx, dy = tip_b[0] - tip_a[0], tip_b[1] - tip_a[1]
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length
    stem_len = half_w * 0.10
    stem_end = (tip_b[0] + ux * stem_len, tip_b[1] + uy * stem_len)
    draw = ImageDraw.Draw(img)
    vein_width = max(4, int(size * 0.010))
    draw.line([vein_a, stem_end], fill=(*vein, 255), width=vein_width)

    return img


def make_icon() -> None:
    """`assets/icon/icon.png`: full-bleed square, opaque background."""
    img = Image.new("RGBA", (CANVAS, CANVAS), (*LIGHT_ACCENT, 255))
    leaf = draw_leaf(CANVAS, LIGHT_GREEN_TINT, LIGHT_ACCENT_HOVER, scale=0.30)
    img.alpha_composite(leaf)
    out = os.path.join(ROOT, "assets", "icon", "icon.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.convert("RGB").save(out)
    print(f"wrote {out}")


def make_icon_foreground() -> None:
    """`assets/icon/icon_foreground.png`: transparent, safe-zone scaled."""
    img = draw_leaf(CANVAS, LIGHT_GREEN_TINT, LIGHT_ACCENT_HOVER, scale=0.20)
    out = os.path.join(ROOT, "assets", "icon", "icon_foreground.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out)
    print(f"wrote {out}")


def make_splash(name: str, fill, vein) -> None:
    img = draw_leaf(CANVAS, fill, vein, scale=0.16)
    out = os.path.join(ROOT, "assets", "splash", name)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out)
    print(f"wrote {out}")


if __name__ == "__main__":
    make_icon()
    make_icon_foreground()
    make_splash("branding_light.png", LIGHT_ACCENT, LIGHT_ACCENT_HOVER)
    make_splash("branding_dark.png", DARK_ACCENT, DARK_ACCENT_HOVER)
