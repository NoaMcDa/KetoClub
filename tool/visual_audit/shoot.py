"""Drives the real web build in headless Chromium and screenshots every
reachable screen at a phone viewport (390x844 @2x), light and dark,
English (LTR) and Hebrew (RTL) — docs/VISUAL_AUDIT.md has the recipe.

    OUTDIR=build/visual-audit python3 tool/visual_audit/shoot.py \\
        http://localhost:8080 [screens] [combos]

screens: comma list of substrings to limit the run (discovery, menu,
         waiter, settings, saved, scan, extra); default all.
combos:  comma list like light_en,dark_he; default all four.

Environment:
  OUTDIR  where the PNGs go (default build/visual-audit/).
  CHROME  a Chromium binary, when Playwright's own is not installed.
  INJECT  "1" adds the X-KetoClub-Install-Id header to the discovery
          proxy calls — only for a build older than the fix that made the
          app send it (before it, every nearby/by-name search through the
          backend answered 400).

Flutter web draws to a canvas, so the driver clicks the semantics
placeholder to get an accessibility tree it can read, then taps by the
bounding box of a node whose label matches, or by coordinates.
"""

import os
import sys
import urllib.request

from playwright.sync_api import sync_playwright

OUT = os.environ.get("OUTDIR", "build/visual-audit/").rstrip("/") + "/"
os.makedirs(OUT, exist_ok=True)
BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8080")
BASE = BASE.rstrip("/")
ONLY = sys.argv[2] if len(sys.argv) > 2 else ""
COMBOS = (
    sys.argv[3].split(",")
    if len(sys.argv) > 3
    else ["light_en", "dark_en", "light_he", "dark_he"]
)
INJECT = os.environ.get("INJECT") == "1"
CHROME = os.environ.get("CHROME")

# Labels the driver taps by, per UI language (lib/l10n/app_*.arb).
LABELS = {
    "en": {
        "ask": "Ask your waiter",
        "card": "Show the waiter card",
        "estimate": "Estimate this list",
        "open_settings": "Open Settings",
    },
    "he": {
        "ask": "שאלו את המלצר",
        "card": "הצג כרטיס למלצר",
        "estimate": "הערך את הרשימה",
        "open_settings": "פתח הגדרות",
    },
}

_FONT_CACHE: dict = {}


def _gstatic(route):
    """Serves Flutter's on-demand Noto fallback fonts (Hebrew has no
    bundled face) through Python's own HTTP client, which honours the
    machine's proxy and CA settings where a fresh browser profile may
    not."""
    url = route.request.url
    if url not in _FONT_CACHE:
        with urllib.request.urlopen(url, timeout=30) as response:
            _FONT_CACHE[url] = (
                response.status,
                response.headers.get("content-type"),
                response.read(),
            )
    status, ctype, body = _FONT_CACHE[url]
    route.fulfill(
        status=status,
        headers={
            "content-type": ctype or "font/ttf",
            "access-control-allow-origin": "*",
        },
        body=body,
    )


def _inject(route):
    headers = dict(route.request.headers)
    headers["x-ketoclub-install-id"] = "0123456789abcdef0123456789abcdef"
    route.continue_(headers=headers)


def new_page(browser, scheme, lang, geo=True):
    ctx = browser.new_context(
        viewport={"width": 390, "height": 844},
        device_scale_factor=2,
        color_scheme=scheme,
        locale="he-IL" if lang == "he" else "en-US",
        geolocation={"latitude": 32.08, "longitude": 34.78},
        permissions=["geolocation"] if geo else [],
        service_workers="block",
    )
    page = ctx.new_page()
    page.route("https://fonts.gstatic.com/**", _gstatic)
    if INJECT:
        page.route("**/v1/proxy/wolt/pages/**", _inject)
    return ctx, page


def boot(page, path):
    page.goto(BASE + "/#" + path)
    page.wait_for_timeout(5000)
    page.evaluate(
        "document.querySelector('flt-semantics-placeholder')?.click()"
    )
    page.wait_for_timeout(1200)


def shot(page, name):
    page.mouse.move(1, 1)
    page.wait_for_timeout(900)
    page.screenshot(path=OUT + name + ".png")
    print("wrote", name, flush=True)


def find_label(page, prefix):
    for el in page.query_selector_all("flt-semantics"):
        label = el.get_attribute("aria-label") or ""
        text = (el.inner_text() or "").strip()
        if label.startswith(prefix) or text.startswith(prefix):
            box = el.bounding_box()
            if box and 0 < box["y"] + box["height"] / 2 < 844:
                return box
    return None


def click_label(page, prefix):
    box = find_label(page, prefix)
    if box is None:
        print("  !! no visible node", prefix, flush=True)
        return False
    page.mouse.click(box["x"] + box["width"] / 2, box["y"] + box["height"] / 2)
    page.wait_for_timeout(1500)
    return True


def tap(page, x, y):
    page.mouse.click(x, y)
    page.wait_for_timeout(1500)


def scroll(page, dy, x=195, y=600):
    page.mouse.move(x, y)
    page.mouse.wheel(0, dy)
    page.wait_for_timeout(1200)


def want(key):
    return not ONLY or any(k in key for k in ONLY.split(","))


def run(browser, scheme, lang):
    tag = f"{scheme}_{lang}"
    labels = LABELS[lang]
    he = lang == "he"
    locate_x = 40 if he else 350  # the header's location button

    if want("discovery"):
        ctx, page = new_page(browser, scheme, lang)
        boot(page, "/")
        shot(page, f"discovery_empty_{tag}")
        tap(page, locate_x, 36)
        page.wait_for_timeout(2500)
        shot(page, f"discovery_nearby_{tag}")
        scroll(page, 600)
        shot(page, f"discovery_nearby_scrolled_{tag}")
        ctx.close()

        ctx, page = new_page(browser, scheme, lang)
        boot(page, "/")
        tap(page, 195, 163)  # the search field
        page.keyboard.type("pizza")
        page.keyboard.press("Enter")
        page.wait_for_timeout(2500)
        shot(page, f"discovery_search_{tag}")
        ctx.close()

        ctx, page = new_page(browser, scheme, lang, geo=False)
        boot(page, "/")
        tap(page, locate_x, 36)
        page.wait_for_timeout(2500)
        shot(page, f"discovery_denied_{tag}")
        if click_label(page, labels["open_settings"]):
            page.wait_for_timeout(800)
            shot(page, f"discovery_denied_open_settings_{tag}")
        ctx.close()

    if want("menu") or want("waiter") or want("saved"):
        ctx, page = new_page(browser, scheme, lang)
        boot(page, "/venue/wolt/ember-and-vine")
        page.wait_for_timeout(2000)
        shot(page, f"menu_top_{tag}")
        scroll(page, 450)
        shot(page, f"menu_scrolled_{tag}")
        for _ in range(4):
            if find_label(page, labels["card"]):
                break
            scroll(page, 150)
        if click_label(page, labels["card"]):
            page.wait_for_timeout(1500)
            shot(page, f"waiter_card_{tag}")
            page.keyboard.press("Escape")
            page.wait_for_timeout(1500)
        if click_label(page, labels["ask"]):
            shot(page, f"menu_script_open_{tag}")
            scroll(page, 300)
            shot(page, f"menu_script_open_scrolled_{tag}")
        scroll(page, -5000)
        tap(page, 70 if he else 320, 205)  # the Skip tile
        shot(page, f"menu_filter_skip_{tag}")
        if want("saved"):
            boot(page, "/saved")
            shot(page, f"saved_one_{tag}")
        ctx.close()

        ctx, page = new_page(browser, scheme, lang)
        boot(page, "/venue/wolt/hamosad")
        page.wait_for_timeout(2000)
        shot(page, f"menu_fixture_{tag}")
        scroll(page, 500)
        shot(page, f"menu_fixture_scrolled_{tag}")
        ctx.close()

        ctx, page = new_page(browser, scheme, lang)
        boot(page, "/venue/tenbis/12345")
        page.wait_for_timeout(2500)
        shot(page, f"menu_tenbis_{tag}")
        ctx.close()

    if want("settings"):
        ctx, page = new_page(browser, scheme, lang)
        boot(page, "/settings")
        shot(page, f"settings_top_{tag}")
        scroll(page, 700)
        shot(page, f"settings_mid_{tag}")
        scroll(page, 3000)
        shot(page, f"settings_bottom_{tag}")
        ctx.close()

    if want("saved"):
        ctx, page = new_page(browser, scheme, lang)
        boot(page, "/saved")
        shot(page, f"saved_empty_{tag}")
        ctx.close()

    if want("scan"):
        ctx, page = new_page(browser, scheme, lang)
        boot(page, "/scan")
        shot(page, f"scan_{tag}")
        ctx.close()

    if want("extra"):
        # Estimate this list, then open a venue from its card (not a deep
        # link), then Menu -> Settings (app bar) -> Explore (bottom nav).
        ctx, page = new_page(browser, scheme, lang)
        boot(page, "/")
        tap(page, locate_x, 36)
        page.wait_for_timeout(2500)
        if click_label(page, labels["estimate"]):
            page.wait_for_timeout(6000)
            shot(page, f"discovery_estimated_{tag}")
            scroll(page, 450)
            shot(page, f"discovery_estimated_scrolled_{tag}")
            scroll(page, -3000)
        scroll(page, 380)
        tap(page, 195, 420)
        page.wait_for_timeout(4000)
        shot(page, f"menu_from_card_{tag}")
        tap(page, 40 if he else 350, 28)
        page.wait_for_timeout(2500)
        shot(page, f"settings_from_menu_{tag}")
        tap(page, 350 if he else 48, 815)
        page.wait_for_timeout(2500)
        shot(page, f"explore_after_settings_{tag}")
        ctx.close()


if __name__ == "__main__":
    with sync_playwright() as p:
        kwargs = {"executable_path": CHROME} if CHROME else {}
        browser = p.chromium.launch(args=["--no-proxy-server"], **kwargs)
        for combo in COMBOS:
            scheme, lang = combo.split("_")
            run(browser, scheme, lang)
        browser.close()
