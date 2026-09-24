"""Renders the five .design artboards to PNG at their intended size
(390x844 @2x), light and dark, for side-by-side comparison with the
screenshots shoot.py takes (docs/VISUAL_AUDIT.md).

    OUTDIR=build/visual-audit python3 tool/visual_audit/render_artboards.py

The .dc.html files expect the design canvas's own runtime (./support.js),
which is not checked in next to them; tool/visual_audit/support.js is a
minimal stand-in for exactly what they use. The artboards and the app's
bundled fonts are copied into a temporary directory beside it, so nothing
is fetched from the network.
"""

import os
import pathlib
import shutil
import tempfile

from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = pathlib.Path(__file__).resolve().parent
OUT = pathlib.Path(os.environ.get("OUTDIR", "build/visual-audit"))
CHROME = os.environ.get("CHROME")

BOARDS = {
    "discovery": "Discovery",
    "menu": "Main",
    "menu_dark": "MenuDark",
    "waiter_card": "WaiterCard",
    "settings": "Settings",
}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        boards = pathlib.Path(tmp, "artboards")
        fonts = pathlib.Path(tmp, "fonts")
        boards.mkdir()
        fonts.mkdir()
        for html in (ROOT / ".design").glob("*.dc.html"):
            shutil.copy(html, boards)
        shutil.copy(HERE / "support.js", boards)
        for ttf in (ROOT / "assets" / "fonts").glob("*.ttf"):
            shutil.copy(ttf, fonts)

        with sync_playwright() as p:
            kwargs = {"executable_path": CHROME} if CHROME else {}
            browser = p.chromium.launch(
                args=["--no-proxy-server", "--allow-file-access-from-files"],
                **kwargs,
            )
            page = browser.new_page(
                viewport={"width": 390, "height": 844}, device_scale_factor=2
            )
            for name, file in BOARDS.items():
                for theme in ("Light", "Dark"):
                    if name == "menu_dark" and theme == "Light":
                        continue
                    page.goto(f"file://{boards}/{file}.dc.html?theme={theme}")
                    page.wait_for_timeout(1200)
                    target = OUT / f"artboard_{name}_{theme.lower()}.png"
                    page.screenshot(path=str(target))
                    print("wrote", target, flush=True)
            browser.close()


if __name__ == "__main__":
    main()
