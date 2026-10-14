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
   call: the recorded Wolt menu fixture for `hamosad` (the
   consumer-assortment path, issue #168), a menu mirroring
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

   A build with the path URLs of issue #226 needs
   `python3 tool/visual_audit/serve_spa.py build/web 8080` instead, and
   `HASH=1` for the driver only when shooting an older build (§5).

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

   This audit ran before Hebrew had a bundled face (finding G7, since
   fixed), so Flutter fetched Noto Sans Hebrew from `fonts.gstatic.com` at
   runtime; the driver routes that one host through Python's own HTTP client
   so the fetch uses the machine's proxy and CA settings.

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
branch with no workaround, taken before `main`'s accessibility pass
(#161, `docs/ACCESSIBILITY.md`) was merged in: that pass's verdict icons
on the tiles and its large-text caps are in the code but not in these
screenshots.

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
| G7 | Hebrew text anywhere | — | rendered as empty boxes whenever `fonts.gstatic.com` is unreachable: no Hebrew face was bundled, and the fallback chain named system fonts a CanvasKit build cannot use, so web depended on Flutter's runtime font download | **Fixed** (#261) — Noto Sans Hebrew 400 and 700 (OFL, 46 KB each) bundled under `assets/fonts/` and first in both `AppTypography.uiFallback` and `displayFallback` |
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
| D8 | no open button; the field is the only way in | "Show the keto menu" always shown (disabled grey until the text parses); typing a plain name such as `pizza` **enables** it, because a bare word parses as a Wolt slug, so it opens `/venue/wolt/pizza` | **Fixed** (#229) — the standing button is gone; a pasted link opens on keyboard submit or through an "Open link" suffix icon that shows only while the text is a URL or a numeric id (`VenueRefResolver.isExplicitLink`); a plain word, hyphenated or not, shows nothing and searches by name |
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
| M12 | "₪142" | "₪142.00" | **Fixed** (#242) — whole-shekel prices drop `.00` (`formatPrice`, #169); a fraction keeps two decimals ("₪12.50") |
| M13 | pill label "Modify" | "Order with a change" | **Left** — copy |
| M14 | nothing between the tiles and the dishes | a search field, the legend toggle, the rules banner, the engine chip and category chips — the banner and the chip say the same thing twice | **Fixed** (#236) — a rules result shows the banner only; an AI result keeps its chip (no banner covers it); Saved rows and venue cards keep theirs |

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
| S3 | — | "Default filter" forced its four segments into equal quarters and broke labels mid-word ("Ever / ythin / g") | **Fixed** — chip-sized labels fit at 390px in English; the longer Hebrew "Order as-is" still wraps onto two lines, at a word boundary rather than mid-word |
| S4 | "Clear" as a quiet `--red-ink` text action | a large filled green button | **Fixed** |
| S5 | an "Analysis" group with an API key and a model picker | the consent section | **Left** — the artboard predates D12 (there is no key on the device); the artboard is what should change |
| S6 | Appearance as a three-way segmented control | a radio list, as is Language | **Fixed** (#256) — Language and Appearance are one-row `SegmentedButton`s in the Default filter's style; the `languageRadioGroupKey`/`appearanceRadioGroupKey` keys are kept, and the controls are disabled while the screen is busy. Hebrew labels are not wrapped by construction (the control sizes to its content, with a sideways-scroll fallback); measured with a proxy font the longest group, "לפי ערכת הנושא של המכשיר" + two short labels, is under 300px against 350px available at 390px |
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
same names; `<scheme>` is `light`/`dark`, `<lang>` is `en`/`he`. The
`after/` set covers all four combinations; in `before/`, the flows the
driver gained during the audit (`discovery_denied_open_settings_…`,
`discovery_estimated_…`, `menu_tenbis_…`, `menu_from_card_…`,
`settings_from_menu_…`, `explore_after_settings_…`) exist for `light_en`
only.

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

## 5. Banto four-state menu (ALG-05)

The four-state menu screen (#381, `architecture.md` D26) rendered for the
first time, with the visual pass of issue #347. Screenshots are again not
committed; the pull request describes each in words.

### How it was rendered

The recipe of §1, with three additions to the harness:

- **Path URLs.** Since issue #226 the web build uses path URLs, which the
  driver's `/#/venue/...` links and `python3 -m http.server` (a 404 on any
  deep path) no longer reach: the old recipe opened every deep link on
  Explore. `tool/visual_audit/serve_spa.py <build> <port>` serves a build
  with the single-page-app fallback, and `shoot.py` opens plain paths
  (`HASH=1` keeps the old links for an older build).
- **The golden English menu.** `stub_upstream.py` serves
  `tool/golden/golden_corpus.dart`'s `goldenEnglishMenu` ("Golden Bistro")
  as a Wolt assortment at the slug `golden-bistro`, beside the recorded
  Hebrew fixture at `hamosad`.
- **A seeded profile.** `shoot.py http://localhost:8080 banto` (never part
  of the default run) writes the settings record, today's defaults plus a
  sesame + lactose profile with the onboarding marked seen, into the
  browser's `shared_preferences` store before the app starts, then shoots
  both menus at 390×844 and 1280×800, the Why sheet of a dish with nothing
  found and of one with concerns, an opened waiter row, and the first-run
  onboarding screen (no seed) before and after picking two chips.
  `keto-pair` shoots the same two menus with no profile, against a build
  without the define.

```bash
flutter build web --release --no-web-resources-cdn \
  --dart-define=KETOCLUB_BACKEND_URL=http://localhost:8000 \
  --dart-define=BANTO_MODE=true -o build/web-banto
python3 tool/visual_audit/serve_spa.py build/web-banto 8080
OUTDIR=build/visual-audit python3 tool/visual_audit/shoot.py http://localhost:8080 banto
```

Rules engine only (the backend has no model key), so every menu is a rules
result for a strict profile (sesame is an allergen; lactose an
intolerance). The hamosad fixture reads 7 "no trigger found", 0 with a
change, 15 to ask and 15 to avoid; the golden menu 9, 0, 0 and 3.

### Findings

Status as in §2. Every fix sits in a path that runs only in state mode (a
Banto build with a profile holding a restriction besides keto).

| # | Where | Before | Status |
|---|---|---|---|
| B1 | Dish card, strict "fits" | the pill is a sentence ("No trigger found — ask the restaurant") that fills the line, so the header's `Wrap` dropped the "add a note" icon onto a line of its own under it, on every such card | **Fixed** — in state mode the pill and the icon share a `Row`, the pill wrapping its own text; the keto header keeps its `Wrap` |
| B2 | Dish card semantics | the "Why?" button, the concern lines and the state waiter row had no node of their own, so they merged into the card's: the web build exposed the whole card as one button labelled with the verdict, the dish, every concern and "Why this result for…", whose tap opened the Why sheet. The driver could not find the Why button at all | **Fixed** — each is a semantics `container`; the keto waiter row keeps today's tree |
| B3 | The AI and "Rules checked" chips | not reachable on web (no model). At 320px and 1.6× text, the AI chip overflowed by 145px in Hebrew and "Rules checked" by 77px | **Fixed** — the pair scales down to the width (`FittedBox`) and wraps a chip to its own line |
| B4 | Why sheet, a Hebrew dish in the English UI | the dish name and the waiter question were laid out in the UI's direction, at the left edge, against audit M8's rule for menu content | **Fixed** — `contentDirection` for both, as on the card |
| B5 | "Why?" button, keyboard focus | Material's faint focus tint, the only control on the card without the #264 ring | **Fixed** — wrapped in `FocusRing` |
| B6 | Copy (owner's decision) | Hebrew strict tile "לא נמצא חשש", header "N בלי חשש שנמצא · …"; change sentence "Ask for it without tahini" | **Fixed** — tile "ללא חשש", header "N ללא חשש · M עם שינוי · K לשאול"; the card's pill keeps "לא נמצא חשש — לשאול את המסעדה"; the change sentence quotes the menu's own words, `לבקש את המנה בלי 'גבינת שמנת'` (`ProfileEvaluator.quotedItem`) |
| B7 | Tiles, English strict | "NO TRIGGER FOUND" wraps to three lines at 390px and in the 1280px side pane, so the four tiles are about 20px taller than the keto three | **Left** — the four stay one height (`IntrinsicHeight`, now pinned by a test) and the English wording is the owner's; Hebrew "ללא חשש" fits on one line |
| B8 | A notice item ("לקוחות יקרים", ₪0) | carries a state pill and a "Why?" button | **Left** — the keto screen gives it a verdict pill too; a notice card is a kind question (D21), not a four-state one |
| B9 | Keto AI chip at 320px and 1.6× text | the keto screen's lone AI chip overflows the same way as B3 (417px in English, 666px in Hebrew, with a long model name) | **Fixed in the engine-chip overflow PR** — `EngineChip` scales down to the width it is offered (`FittedBox`, `scaleDown`); at 390px and 1.0× the scale is 1 and the chip renders as before |
| B10 | "With a change" | neither menu produced one under this profile on the rules engine (a stated lactose option sat on a dish sesame made "ask") | **Left** — the quoted sentence is pinned by `profile_evaluator_test` instead |
| B11 | Venue name | the slug ("hamosad", "golden-bistro") | **Left** — M1, a deep link |

Checked and found right: RTL mirroring (the rail, the pill and the note
icon swap sides, the side pane sits at the right in Hebrew at 1280px), the
four tiles at one height in both languages, the "ask" card's orange
outline and pill in dark mode (its pairs are pinned by `contrast_test`),
concern chips naming the restriction in the dish's language and wrapping
inside the card at 390px, the tiles' focus ring, the
two-pane layout at 1280px (tiles, counts, Filters, profile summary and
category chips in the side pane; notices and dishes beside it), and the
onboarding screen in both languages and themes.

### Keto check

The keto build (no define) shot the same two menus before and after this
change. Every pair matches apart from the "N minutes ago" source line and,
on the hamosad fixture, an emoji the browser's fallback font had or had not
finished loading (a chip's width and a 2px shift below it); a second run of
the unchanged build differs from the first in the same places, so neither
is this change. The keto screen reads as §2 describes: three tiles, the
keto score, keto pills, the rules banner.

### Screenshots

`before/` (the Banto build at the start of the pass) and `after/` (the
fixed build), `<scheme>_<lang>` as in §4:

- `banto_menu_{fixture,golden}_390_…`, `…_390_scrolled{,2,3,4}_…`,
  `banto_menu_{fixture,golden}_1280_…`, `…_1280_scrolled_…`
- `banto_why_{fixture,golden}_…` (nothing found), `banto_why_concerns_fixture_…`,
  `banto_line_open_fixture_…`
- `banto_onboarding_…`, `banto_onboarding_picked_…`, `banto_onboarding_bottom_…`
- `keto_menu_…` (the keto pair), `banto_focus_tile_dark_he`
