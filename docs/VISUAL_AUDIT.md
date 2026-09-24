# Visual audit: the rendered web build against the artboards

Until this audit nobody had looked at the app rendered: `HANDOFF.md` recorded
"no screenshot or narrow-width (390px) run has confirmed the UI against the
`.design/` artboards". This document records how the real web build was
rendered with no network, what it looked like next to each artboard, what
this pull request changed, and what it deliberately left alone.

Screenshots are **not** committed. They were taken at 390×844 CSS pixels,
device scale 2, in light and dark, English (LTR) and Hebrew (RTL); the file
names below are the ones the recipe writes, so a re-run produces the same
set.

## 1. How the screens were rendered

Wolt, 10bis and the model provider are all unreachable from the machine
this ran on, so every upstream was replaced by the repository's own
fixtures. Nothing in `lib/` or `backend/` knows it is being fed a stub.

```
headless Chromium ──▶ build/web (static, :8080) ──▶ backend (:8000) ──▶ stub (:9999)
  tool/visual_audit/      flutter build web         uvicorn, upstream     tool/visual_audit/
  shoot.py                --dart-define=…           hosts pointed at      stub_upstream.py
                          KETOCLUB_BACKEND_URL      the stub, no model    test/fixtures/*.json
                                                    key → rules engine
```

1. **The stub upstream** — `tool/visual_audit/stub_upstream.py` serves the
   fixtures at the paths `backend/app/services/wolt.py` and `tenbis.py`
   call: the Wolt menu fixture for `vitrina-lilinblum`, a menu mirroring
   `.design/Main.dc.html`'s dishes for any other slug, the two discovery
   fixtures at `/v1/pages/restaurants` and `/v1/pages/search`, the 10bis
   fixture, and generated dish photos under `/img/`.

   ```bash
   python3 tool/visual_audit/stub_upstream.py 9999      # Pillow for /img/
   ```

2. **The backend**, unchanged, with its upstream hosts pointed at the stub
   and **no model key** in its environment, so `/v1/health` reports
   `"llm_configured": false` and every menu is classified by the on-device
   rules — a real product state, labelled "rules" in the UI. The default
   `CORS_ORIGIN_REGEX` already admits any `localhost` port.

   ```bash
   cd backend && uv sync --frozen
   WOLT_BASE_URL=http://127.0.0.1:9999 \
   WOLT_CONSUMER_BASE_URL=http://127.0.0.1:9999 \
   TENBIS_BASE_URL=http://127.0.0.1:9999 \
   DATABASE_URL=sqlite:////tmp/visual-audit.db \
     uv run uvicorn app.main:app --port 8000
   ```

3. **The web build**, served as static files. `--no-web-resources-cdn`
   bundles CanvasKit instead of loading it from `www.gstatic.com`.

   ```bash
   flutter build web --release --no-web-resources-cdn \
     --dart-define=KETOCLUB_BACKEND_URL=http://localhost:8000
   python3 -m http.server 8080 --directory build/web
   ```

4. **The driver** — `tool/visual_audit/shoot.py` (Python Playwright) opens
   each screen in a fresh browser context at 390×844 @2x with
   `color_scheme` light/dark and locale `en-US`/`he-IL` (the app follows the
   device language until one is chosen in Settings), a granted geolocation
   near Tel Aviv (32.08, 34.78) for Discovery's "use my location", and a
   second context with geolocation denied. Flutter web draws to a canvas,
   so the driver clicks the `flt-semantics-placeholder` to switch on the
   accessibility tree, then taps by a node's label or by coordinates; deep
   links (`/#/venue/wolt/<slug>`, `/#/settings`, `/#/saved`, `/#/scan`)
   reach the rest.

   ```bash
   pip install playwright            # CHROME=/path/to/chromium if Playwright's is not installed
   OUTDIR=build/visual-audit python3 tool/visual_audit/shoot.py http://localhost:8080
   OUTDIR=build/visual-audit python3 tool/visual_audit/render_artboards.py
   ```

   Hebrew has no bundled face (see finding G7), so Flutter fetches Noto
   Sans Hebrew from `fonts.gstatic.com` at runtime; the driver routes that
   one host through Python's own HTTP client so the fetch uses the
   machine's proxy and CA settings.

5. **The artboards** — the `.dc.html` files expect the design canvas's own
   `support.js`, which is not in `.design/`. `tool/visual_audit/support.js`
   is a minimal stand-in for exactly what the five artboards use
   (`{{…}}` bindings, `<sc-for>`, `<sc-if>`, `onClick`, `DCLogic` state);
   `render_artboards.py` renders each at 390×844 @2x, light and dark, with
   the app's bundled fonts, as `artboard_<screen>_<theme>.png`.

The "before" set was taken from `main` at `7269521` with one workaround:
that build never sent the install id the backend's discovery routes
require (finding D1), so the driver added the header itself (`INJECT=1`)
to get past the error and see the cards at all. The "after" set is this
branch with no workaround.

## 2. Findings

Status: **Fixed** in this pull request, **Left** deliberately (with the
reason), or **Decision** — needs a product call before anyone changes it.

### Global — theme and navigation

| # | Where | Artboard | App before | Status |
|---|---|---|---|---|
| G1 | Bottom nav, every tab | `--bg` fading bar, no indicator, active tab `--accent`, others `--ink3`, 10px labels | Material 3 `NavigationBar`: a tinted grey-green slab, a pill indicator, near-black icons | **Fixed** — `navigationBarTheme` |
| G2 | App bars | the page's own `--bg` | turned grey-green once content scrolled under them (Material 3 "scrolled under" tint) | **Fixed** — `scrolledUnderElevation: 0`, no tint |
| G3 | Every surface Material draws itself (the rules banner, chip fills, the bottom sheet, dialogs) | only `--bg`, `--surface`, `--surface2` | the seed colour's greenish greys leaking through `surfaceContainer*` / `onSurfaceVariant` | **Fixed** — those roles mapped to the tokens; `onSurfaceVariant` is `--ink3`, `outlineVariant` is `--line` |
| G4 | Search fields (Discovery, menu, note editor) | a `--surface` box, `--line` edge, 14px radius | an underlined Material field | **Fixed** — `inputDecorationTheme` |
| G5 | Chips (filters, category jumps, waiter-card tabs) | `.chip`: a pill, 12.5px semibold, `--accent` fill when selected, no check mark | rounded rectangles, 14–15px labels, a check mark, a pale green selected fill | **Fixed** — `chipTheme` |
| G6 | Small upper-case labels ("LOOKING AROUND", "KETO SCORE", tile labels) | `--ink3` | `--ink2` | **Fixed** — `labelSmall` is `--ink3` |
| G7 | Hebrew text anywhere | — | rendered as empty boxes whenever `fonts.gstatic.com` is unreachable: no Hebrew face is bundled, and the fallback chain names system fonts a CanvasKit build cannot use, so web depends on Flutter's runtime font download | **Decision** — bundle a Hebrew face (e.g. Noto Sans Hebrew, OFL) for offline and blocked networks, at the cost of app size |
| G8 | Menu → ⚙ Settings → any tab | — | the tab replaced only the top route, leaving the menu underneath: every such round trip grew the navigation stack by a whole menu screen | **Fixed** — tab taps clear the stack (`pushNamedAndRemoveUntil`) |
| G9 | Tab roots reached by deep link (`/#/settings`) | no back arrow | a back arrow (Flutter web pushes `/` under an initial deep link); tapping a tab never shows it | **Left** — web initial-route behaviour, not reachable by in-app navigation |

### Discovery (`Discovery.dc.html`)

| # | Artboard | App before | Status |
|---|---|---|---|
| D1 | venue cards after "use my location" and after a name search | **every** nearby and by-name search through the backend failed with "Wolt changed how its restaurant search works": the client never sent `X-KetoClub-Install-Id`, which both discovery routes require (`400 badResponse`), and a 400 maps to `platformChanged` | **Fixed** — `WoltVenueSearchService` sends the install id on proxied calls only; two tests pin it |
| D2 | a full-width 118px photo banner per venue | a 118px **square** — `PhotoTile` is square and the card's `Stack` hands it loose constraints, so the column's stretch never reached it (regression from #159) | **Fixed** — `PhotoTile.width` (`double.infinity` on the card); a test pins 300×118 inside a `Stack` |
| D3 | "Where to eat" 34px serif | 26px | **Fixed** |
| D4 | blurb 13px `--ink2`, line height 1.45 | 14px `--ink` | **Fixed** |
| D5 | score "9.1 KETO" on one baseline beside the name | the menu header's stacked 24px score + label | **Fixed** — `KetoScoreBadge(inline: true)` |
| D6 | permanent denial, **web**: — | "Open Settings" did nothing at all — a browser has no settings page to open, and the service's `false` was ignored | **Fixed** — a snack bar says where to allow location instead (new `discoveryOpenSettingsUnavailable`, en + he) |
| D7 | no app-name label | "KetoClub" above the heading | **Left** — `app_test`/`main_test` find `appName` on the launch screen |
| D8 | no open button; the field is the only way in | "Show the keto menu" always shown (disabled grey until the text parses); typing a plain name such as `pizza` **enables** it, because a bare word parses as a Wolt slug, so it opens `/venue/wolt/pizza` | **Decision** — keep the paste button, hide it until a link is pasted, or require a URL for it |
| D9 | the user's street ("Rothschild 22") | the nearest venue's address, in the feed's language (a Hebrew street in the English UI) | **Left** — reverse geocoding is deferred (`venue_search_screen.dart`'s own doc) |
| D10 | an avatar ("N") | the location button | **Left** — there are no accounts |
| D11 | — | cuisine chip and meta show the feed's English tag ("Falafel") in the Hebrew UI | **Decision** — translate known tags or leave feed text verbatim |

### Menu (`Main.dc.html`, `MenuDark.dc.html`)

| # | Artboard | App before | Status |
|---|---|---|---|
| M1 | the venue's name | the slug ("ember-and-vine", "hakosem") even when opened from a Discovery card that shows the real name — no documented Wolt menu payload names the venue | **Fixed** for a card tap (the name rides along as route arguments, `MenuScreen.venueNameHint`); **Left** for deep links, Saved and "Continue with …", which need the name persisted with the cached menu |
| M2 | the "rules" chip sized to its text | stretched to a full-width bar (a `ListView` child) | **Fixed** |
| M3 | dish name 15px bold, description 12.5px at 1.45, price 13.5px, card padding 12/13 | semibold name, tight description, 14px price, 12 all round | **Fixed** |
| M4 | tile count 18px, label 9.5px `--ink3` | 16px, 10px `--ink2` | **Fixed** |
| M5 | 20px page gutters | 16px | **Fixed** (menu and Saved) |
| M6 | the waiter script as separate instructions | the rules engine joined its instructions with a space, and README's templates carry no full stop, so two asks ran together: "…or steamed vegetables Ask to leave out carrots…", numbered as one line | **Fixed** — joined with a newline, the script's documented separator (architecture.md §6.3, updated); each instruction is its own numbered line; the shared text keeps the indent |
| M7 | inline script 13px at 1.55 | 16px, numbers in the accent green | **Fixed** — 13px, numbers in the modify amber |
| M8 | — | English dish text in the Hebrew UI laid out right to left, its full stop jumping to the front (".butter, grilled onion"); the mirror image for Hebrew dishes in English | **Fixed** — names, descriptions and script lines take the direction of their own text (`contentDirection`) |
| M9 | a 158px venue photo band with round back and bookmark buttons | a plain app bar | **Decision** — the menu payload has no venue photo, and "bookmark" duplicates Saved, which is automatic |
| M10 | a subtitle ("Charcoal grill · Herzl 8 · ₪₪₪") | none | **Left** — not in the menu payload |
| M11 | a floating "Waiter card · 2 dishes" pill opening every modify dish as tabs | only a per-dish "Show the waiter card"; `WaiterCardSheet.forRows` exists but nothing calls it | **Decision** — a floating bar overlaps the list's last cards and needs its own design pass |
| M12 | "₪142" | "₪142.00" | **Decision** — `price_format_test` pins two decimals |
| M13 | pill label "Modify" | "Order with a change" | **Left** — copy |
| M14 | nothing between the tiles and the dishes | a search field, the legend toggle, the rules banner, the engine chip and category chips — the banner and the chip say the same thing twice | **Decision** — keep one of the two rules notices |

### Waiter Card (`WaiterCard.dc.html`)

| # | Artboard | App before | Status |
|---|---|---|---|
| W1 | a full screen of its own | a bottom sheet about a third of the screen tall | **Fixed** — fills the modal sheet |
| W2 | the script at 21px medium | 16px — `SelectableText`'s own `bodyLarge` style overrode the sheet's 21px `DefaultTextStyle` | **Fixed** — `WaiterScriptWidget(prominent: true)` |
| W3 | the dish name, 34px serif | 18px sans | **Fixed** |
| W4 | a small muted title and a close button | a 14px title, no close button | **Fixed** (the title keeps its case: tests find the string verbatim) |
| W5 | numbered circles in amber | accent green | **Fixed** |
| W6 | each instruction in its own amber-railed card; an ink "Copy text" bar and a brightness button pinned to the bottom, with "Screen brightness is raised…" | one card, the copy button inside it | **Left** — the brightness caption would be false on web, where raising is a no-op |

### Settings (`Settings.dc.html`)

| # | Artboard | App before | Status |
|---|---|---|---|
| S1 | a 32px serif "Settings" | a 22px sans app-bar title | **Fixed** — app-bar titles (Settings, Saved, Scan) are the serif display face |
| S2 | small muted section labels over grouped `--surface` cards (15px radius, `--line` edge) | full-size titles over a flat list | **Fixed** |
| S3 | — | "Default filter" forced its four segments into equal quarters and broke labels mid-word ("Ever / ythin / g") | **Fixed** — chip-sized labels fit at 390px; scrolls sideways if a translation is longer |
| S4 | "Clear" as a quiet `--red-ink` text action | a large filled green button | **Fixed** |
| S5 | an "Analysis" group with an API key and a model picker | the consent section | **Left** — the artboard predates D12 (there is no key on the device); the artboard is what should change |
| S6 | Appearance as a three-way segmented control | a radio list, as is Language | **Decision** — tests address both through `RadioGroup` keys |
| S7 | a compact `--surface2` stepper | outlined circular buttons | **Left** |

### Saved and Scan (no artboard)

| # | App before | Status |
|---|---|---|
| V1 | Material default card and title | **Fixed** by the theme — the serif title, a `--surface` card with a `--line` edge |
| V2 | Saved shows the slug for a card-opened venue | **Left** — see M1 |

## 3. Screens that could not be reached

- **AI analysis.** The model provider is unreachable here, so every menu is
  a rules result. Everything that only an AI result draws was never
  rendered: the AI engine chip, the net-carb chips on dish cards (the
  artboard's "~2g net carbs"), and the Waiter Card's "about 3g net carbs —
  safe to order" box.
- **Location unavailable** (services off, timeout, insecure context): the
  headless browser only grants or denies.
- **The offline banner**: the browser always reports itself online.
- **A failed fetch, a stale cached menu, the note editor sheet**: reachable
  in principle (the stub could answer a 404), not driven in this pass.
- **Loading skeletons**: they last a few hundred milliseconds against a
  local stub, shorter than the driver's settle time.
- **iOS and Android**: web only; `docs/RELEASE.md`'s device matrix still
  owns the phone run.

## 4. Screenshots

In the audit run's scratch directory, as `before/` and `after/` with the
same names; `<scheme>` is `light`/`dark`, `<lang>` is `en`/`he`:

- `discovery_empty_…`, `discovery_nearby_…`, `discovery_nearby_scrolled_…`,
  `discovery_search_…`, `discovery_denied_…`,
  `discovery_denied_open_settings_…`, `discovery_estimated_…`
- `menu_top_…`, `menu_scrolled_…`, `menu_script_open_…`,
  `menu_script_open_scrolled_…`, `menu_filter_skip_…`, `menu_fixture_…`,
  `menu_fixture_scrolled_…`, `menu_tenbis_…`, `menu_from_card_…`
- `waiter_card_…`
- `settings_top_…`, `settings_mid_…`, `settings_bottom_…`,
  `settings_from_menu_…`, `explore_after_settings_…`
- `saved_empty_…`, `saved_one_…`, `scan_…`
- `artboard_discovery_{light,dark}`, `artboard_menu_{light,dark}`,
  `artboard_menu_dark_dark`, `artboard_waiter_card_{light,dark}`,
  `artboard_settings_{light,dark}`
