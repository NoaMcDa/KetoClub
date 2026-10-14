"""Drives the real web build in headless Chromium and screenshots every
reachable screen at a phone viewport (390x844 @2x), light and dark,
English (LTR) and Hebrew (RTL) — docs/VISUAL_AUDIT.md has the recipe.

    OUTDIR=build/visual-audit python3 tool/visual_audit/shoot.py \\
        http://localhost:8080 [screens] [combos]

screens: comma list of substrings to limit the run (discovery, menu,
         waiter, settings, saved, scan, extra); default all. "banto" (never
         part of the default) drives the Banto four-state menu pass (ALG-05)
         against a build with --dart-define=BANTO_MODE=true: the hamosad
         fixture and the golden English menu at 390px and 1280px with a
         sesame + lactose profile seeded into the settings store, the Why
         sheet, and the first-run onboarding screen. "keto-pair" shoots the
         same two menus with no seeded profile, for the keto check against a
         build without the define.
combos:  comma list like light_en,dark_he; default all four.

Environment:
  OUTDIR  where the PNGs go (default build/visual-audit/).
  CHROME  a Chromium binary, when Playwright's own is not installed.
  INJECT  "1" adds the X-KetoClub-Install-Id header to the discovery
          proxy calls — only for a build older than the fix that made the
          app send it (before it, every nearby/by-name search through the
          backend answered 400).
  HASH    "1" opens deep links as `/#/venue/...`, for a build older than
          the path URLs of issue #226; otherwise the build must be served
          by serve_spa.py (or any server with an index.html fallback).

Flutter web draws to a canvas, so the driver clicks the semantics
placeholder to get an accessibility tree it can read, then taps by the
bounding box of a node whose label matches, or by coordinates.
"""

import json
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
HASH = os.environ.get("HASH") == "1"
CHROME = os.environ.get("CHROME")

# Labels the driver taps by, per UI language (lib/l10n/app_*.arb).
LABELS = {
    "en": {
        "ask": "Ask your waiter",
        "card": "Show the waiter card for",
        "estimate": "Estimate this list",
        "open_settings": "Open Settings",
        "why": "Why this result for",
        "ask_question": "What to ask the waiter",
        "onboarding_chips": ["Sesame", "Lactose"],
    },
    "he": {
        "ask": "שאלו את המלצר",
        "card": "הצג כרטיס למלצר עבור",
        "estimate": "הערך את הרשימה",
        "open_settings": "פתח הגדרות",
        "why": "למה זו התוצאה עבור",
        "ask_question": "מה לשאול את המלצר",
        "onboarding_chips": ["שומשום", "לקטוז"],
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


# The settings record the Banto pass seeds (lib/services/storage/
# settings_store.dart, key `ketoclub_settings`; shared_preferences on web
# stores it JSON-encoded under the `flutter.` prefix): today's defaults plus
# a sesame + lactose profile, with the onboarding marked seen.
BANTO_SETTINGS = {
    "carnivoreOnly": False,
    "dairyFree": False,
    "disclosureSeen": True,
    "estimationConsentGiven": True,
    "filter": "all",
    "languageTag": None,
    "lastFilter": None,
    "lastVenue": None,
    "netCarbLimitGrams": 6,
    "seedOilFree": False,
    "themeMode": "system",
    "dietaryProfile": [
        {"id": "sesame", "exceptions": []},
        {"id": "lactose", "exceptions": []},
    ],
    "restrictionOnboardingSeen": True,
}


def new_page(browser, scheme, lang, geo=True, width=390, height=844,
             settings=None):
    ctx = browser.new_context(
        viewport={"width": width, "height": height},
        device_scale_factor=2,
        color_scheme=scheme,
        locale="he-IL" if lang == "he" else "en-US",
        geolocation={"latitude": 32.08, "longitude": 34.78},
        permissions=["geolocation"] if geo else [],
        service_workers="block",
    )
    if settings is not None:
        # The stored value is the JSON encoding of the record's own JSON
        # string, written into the script as a JavaScript string literal.
        record = json.dumps(json.dumps(json.dumps(settings)))
        ctx.add_init_script(
            "if (!localStorage.getItem('flutter.ketoclub_settings')) "
            f"localStorage.setItem('flutter.ketoclub_settings', {record});"
        )
    page = ctx.new_page()
    page.route("https://fonts.gstatic.com/**", _gstatic)
    if INJECT:
        page.route("**/v1/proxy/wolt/pages/**", _inject)
    return ctx, page


def boot(page, path):
    # Path URLs since issue #226: the build must be served with an SPA
    # fallback (serve_spa.py); HASH=1 restores the old `/#/` links for a
    # build that predates it.
    page.goto(BASE + ("/#" if HASH else "") + path)
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
    height = (page.viewport_size or {}).get("height", 844)
    for el in page.query_selector_all("flt-semantics"):
        label = el.get_attribute("aria-label") or ""
        text = (el.inner_text() or "").strip()
        if label.startswith(prefix) or text.startswith(prefix):
            box = el.bounding_box()
            if box and 0 < box["y"] + box["height"] / 2 < height:
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


def asked(key):
    """Whether [key] was named explicitly; the Banto groups never run by
    default, since they need their own build."""
    return key in ONLY.split(",")


# The two menus of the Banto pass: the recorded Hebrew Wolt fixture and the
# golden English menu (stub_upstream.py serves both).
BANTO_MENUS = (("hamosad", "fixture"), ("golden-bistro", "golden"))


def run_banto(browser, scheme, lang, seeded=True):
    """The four-state menu (ALG-05) at a phone and a desktop width, the
    Why sheet and the onboarding screen; with [seeded] false, the same
    menus with no profile (the keto pair)."""
    tag = f"{scheme}_{lang}"
    labels = LABELS[lang]
    prefix = "banto" if seeded else "keto"
    settings = BANTO_SETTINGS if seeded else None
    for width, height in ((390, 844), (1280, 800)):
        for slug, name in BANTO_MENUS:
            ctx, page = new_page(browser, scheme, lang, width=width,
                                 height=height, settings=settings)
            boot(page, f"/venue/wolt/{slug}")
            page.wait_for_timeout(2500)
            shot(page, f"{prefix}_menu_{name}_{width}_{tag}")
            # Over the dish list: the left half of a two-pane window in
            # LTR, the right half in RTL (the side pane is at the start).
            x = width // 2
            if width > 1000:
                x = width * 3 // 4 if lang != "he" else width // 4
            # A wheel step of 1200 moves the list about 600 CSS pixels.
            scroll(page, 1200, x=x, y=height // 2)
            shot(page, f"{prefix}_menu_{name}_{width}_scrolled_{tag}")
            if width == 390:
                for step in (2, 3, 4):
                    scroll(page, 1200)
                    shot(page,
                         f"{prefix}_menu_{name}_{width}_scrolled{step}_{tag}")
            if seeded and width == 390:
                scroll(page, -5000)
                for _ in range(6):
                    if find_label(page, labels["why"]):
                        break
                    scroll(page, 250)
                if click_label(page, labels["why"]):
                    page.wait_for_timeout(1200)
                    shot(page, f"banto_why_{name}_{tag}")
                    page.keyboard.press("Escape")
                    page.wait_for_timeout(1200)
                # The first dish with a waiter row: an "ask" question or a
                # "with a change" sentence. Small steps, so the row is not
                # scrolled past between two looks.
                for _ in range(20):
                    if find_label(page, labels["ask_question"]) or find_label(
                        page, labels["ask"]
                    ):
                        break
                    scroll(page, 300)
                row = find_label(page, labels["ask_question"]) or find_label(
                    page, labels["ask"]
                )
                if row is not None:
                    tap(page, row["x"] + row["width"] / 2,
                        row["y"] + row["height"] / 2)
                    shot(page, f"banto_line_open_{name}_{tag}")
                    # That dish's Why sheet, which lists its concerns: the
                    # "Why?" button just above the row.
                    why = None
                    for el in page.query_selector_all("flt-semantics"):
                        label = el.get_attribute("aria-label") or ""
                        text = (el.inner_text() or "").strip()
                        if not (label.startswith(labels["why"])
                                or text.startswith(labels["why"])):
                            continue
                        box = el.bounding_box()
                        if box and 0 < box["y"] < row["y"]:
                            if why is None or box["y"] > why["y"]:
                                why = box
                    if why is not None:
                        tap(page, why["x"] + why["width"] / 2,
                            why["y"] + why["height"] / 2)
                        page.wait_for_timeout(1200)
                        shot(page, f"banto_why_concerns_{name}_{tag}")
                        page.keyboard.press("Escape")
                        page.wait_for_timeout(1200)
            ctx.close()
    if not seeded:
        return
    # The first-run onboarding: no profile, not yet seen.
    ctx, page = new_page(browser, scheme, lang)
    boot(page, "/")
    shot(page, f"banto_onboarding_{tag}")
    for chip in labels["onboarding_chips"]:
        click_label(page, chip)
    shot(page, f"banto_onboarding_picked_{tag}")
    scroll(page, 3000)
    shot(page, f"banto_onboarding_bottom_{tag}")
    ctx.close()


def run(browser, scheme, lang):
    if asked("banto"):
        run_banto(browser, scheme, lang)
    if asked("keto-pair"):
        run_banto(browser, scheme, lang, seeded=False)
    if asked("banto") or asked("keto-pair"):
        return
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
            if find_label(page, labels["ask"]):
                break
            scroll(page, 150)
        # The full-screen action lives inside the expanded script (#239).
        if click_label(page, labels["ask"]):
            shot(page, f"menu_script_open_{tag}")
            scroll(page, 300)
            shot(page, f"menu_script_open_scrolled_{tag}")
            if click_label(page, labels["card"]):
                page.wait_for_timeout(1500)
                shot(page, f"waiter_card_{tag}")
                page.keyboard.press("Escape")
                page.wait_for_timeout(1500)
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
