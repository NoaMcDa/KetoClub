# UI/UX review — every screen, with a focus on the web build on a computer

Reviewed 2026-09-30 from the code on `main` at `0882d7e` (the Flutter SDK
is not installed in this environment, so nothing was rendered; every
remark below points at the widget code that produces it). Complements
`docs/VISUAL_AUDIT.md`, which compared the 390px web render against the
artboards; the open "Decision" rows there (D8, D11, M9, M11, M12, M14, S6)
are still open and are not repeated at length here.

Legend: **Fix** — a clear improvement with no product call needed.
**Decide** — needs a product choice first. **Idea** — larger, later.

---

## 1. The web build on a computer: why it looks wide and weird

**Root cause: nothing in the app ever constrains its width.** The five
artboards in `.design/` are all 390×844 phone frames, and every screen is
built as a full-width `Column`/`ListView` with 20px gutters
(`venue_search_screen.dart:183`, `menu_screen.dart:440`,
`settings_screen.dart:124`, `scan_screen.dart:132`,
`saved_screen.dart:167`). Nothing reads `MediaQuery` size or uses a
`LayoutBuilder`; the only `maxWidth` constraints in `lib/` are the two on
the source line and the keto-score badge. On a 1440px window this means:

| What | Phone (390px) | Computer (1440px) |
|---|---|---|
| Venue photo (`venue_card.dart:60,87-92`: `width: double.infinity`, `height: 118`) | a 350×118 banner | a **1400×118 letterbox strip**, `BoxFit.cover` cropping the middle of the photo |
| Venue name (21px) and the keto score badge (`venue_card.dart:106-123`) | side by side | at opposite ends of the screen, 1300px apart |
| Venue blurb (13px) | 2–3 lines | one 200-character line |
| Dish card (`dish_card.dart:179-185`) | text left, 72px photo right | a 72px photo floating at the far right of a 1400px card |
| Verdict tiles (`verdict_counter_tiles.dart:56`) | three 110px tiles | three 450px tiles with an 18px number in one corner |
| The amber "Ask your waiter" bar, the search field, the paste textarea, both Analyse buttons | full width | full width — a 1400px button |
| Bottom `NavigationBar` (`app_shell.dart:71`) | four tabs | four icons spread over 1440px with nothing between them |
| Waiter Card, note editor, question sheet (`showModalBottomSheet`, `isScrollControlled: true`) | a full-height sheet | a full-height, **full-width** sheet with a 34px title in the top-left corner |

### What to do — in order of payoff

1. **Fix — one content-width constraint for the whole app.** Wrap each
   screen's body (or `AppShell`'s `body`, plus the menu route which is
   outside the shell) in `Center(child: ConstrainedBox(constraints:
   BoxConstraints(maxWidth: 680)))`, keeping the `Scaffold` background
   full-bleed. This alone removes the letterbox photos and the
   name/score spread, and touches no screen logic. Reading screens
   (Menu, Settings, Scan, Saved, Drinks) want ~640–720px; Discovery can
   go wider once it has a grid (next item). A small `ContentWidth`
   widget in `widgets/` keeps the number in one place.
2. **Fix — Discovery becomes a responsive grid.** Above ~720px show two
   venue cards per row, above ~1080px three, with the photo at a fixed
   aspect ratio (16:9 or 3:2) instead of a fixed 118px height, so a card
   is a photo tile with the name under it rather than a strip. On a
   phone nothing changes. The list is already a plain `Column`
   (`venue_search_screen.dart:408-425`), so this is a `LayoutBuilder`
   plus a `Wrap`/`GridView.count`. This is the change that makes "the
   restaurants look good on a computer".
3. **Fix — adaptive navigation.** At ≥840px (Material 3's medium
   breakpoint) replace the bottom `NavigationBar` with a
   `NavigationRail` on the leading side; keep the bar below that. It is
   one `LayoutBuilder` in `AppShell`, and the four destinations already
   exist as data. A rail also gives the wide layout a left anchor so the
   content does not float.
4. **Fix — sheets become dialogs on wide screens.** `showModalBottomSheet`
   accepts `constraints: BoxConstraints(maxWidth: 560)`; pass it from
   `_openWaiterCard`, `_openNoteEditor`, `_openQuestionSheet` and
   `_openScannedPages` (`menu_screen.dart:1036-1092`). A centered sheet
   of 560px reads as a card; the Waiter Card in particular is meant to
   be handed across a table, not stretched across a monitor.
5. **Idea — a two-pane menu on desktop.** With a rail on the left and
   ~1100px to spare, the menu screen could pin the header, verdict tiles,
   search and category chips in a left column and scroll only the dish
   list on the right; the tiles are the filter, so keeping them on
   screen while scrolling is a real gain. Further out: Discovery on the
   left and the selected venue's menu on the right (master–detail).
6. **Fix — the web shell.** `web/index.html` has no loading indicator,
   so a first visit is a blank white page until CanvasKit arrives; add a
   splash `<div>` in `--bg` with the app name that Flutter removes on
   first frame. `web/manifest.json` sets `background_color` and
   `theme_color` to the accent green, so an installed PWA flashes green
   before the cream `--bg` appears; use `#FAF7F0`. Its
   `"orientation": "portrait-primary"` is wrong for an app used on a
   computer; drop it. Consider `usePathUrlStrategy()` in `main.dart` so
   shared links read `/venue/wolt/slug` rather than `/#/venue/wolt/slug`.
7. **Fix — mouse and keyboard.** Every tappable already goes through
   `InkWell` (hover and click cursor come free), but: `RefreshIndicator`
   is unreachable with a mouse (the header refresh icon covers it —
   fine, just note it); the `Dismissible` swipe in Saved is invisible
   on desktop (the trailing delete icon covers it — fine); the Discovery
   search field should `autofocus` on web/desktop, since search is the
   primary path when location is denied or unavailable in a browser.

---

## 2. Screen by screen

### 2.1 Explore / Discovery (`venue_search_screen.dart`, `venue_card.dart`)

- **Fix — "Closed" is never shown to a sighted user.** `Venue.isOnline`
  is read only into the semantic label (`venue_card.dart:184-185`) and
  by the "Open now" chip. A card for a closed venue looks identical to
  an open one. Add a small "Closed" tag on the photo or dim the card.
- **Fix — the header before locating reads as an error.** "LOOKING
  AROUND / Location not set" (`_place`, line 291) is the first thing on
  the page for a user who never asked for location. Say "Tap to use your
  location" or hide the header until a position exists; the empty state
  below already carries the "Use my location" button, so the page has
  the same call to action twice.
- **Decide — the always-visible "Show the keto menu" button** (line
  226-234; audit D8). It is a disabled grey button on every fresh
  visit, and it enables on any single word because a word parses as a
  Wolt slug. Recommendation: remove the button; open a pasted link on
  submit (already done in `_onSubmitted`) and show a small "Open link"
  suffix icon inside the field only when the text is a URL.
- **Fix — the venue card has no boundary.** It is photo + text on the
  page background with 19px between cards. On a phone the photo carries
  the rhythm; on a computer, or in a grid, cards want a surface, a
  `--line` edge and the 16px radius the theme's `CardThemeData` already
  defines, so hover and focus have something to light up.
- **Fix — distance.** The meta line shows the platform's delivery
  estimate or walking minutes, never metres/kilometres. A dine-in user
  choosing between three places wants "350 m", and `distanceKm` is
  already computed.
- **Decide — the chip row mixes a sort with filters.** "Nearby" sits
  beside "Open now" and a cuisine as a single-select `ChoiceChip` row.
  "Nearby" is the default order, not a filter; showing it as a selected
  chip that cannot be combined with "Open now" is confusing. Either make
  the chips multi-select (`FilterChip`) or drop "Nearby".
- **Fix — "Keto 8+" appears only after someone taps "Estimate this
  list"**, so the chip row changes shape mid-session. Show it disabled
  with a tooltip until numbers exist, or fold the estimate action into
  the chip itself.
- **Fix — the estimate row's copy is long** ("Reads each menu on this
  list once and scores it with the on-device rules, not the AI. Open a
  restaurant for the full analysis."). "Quick score (on-device rules)"
  as the button and one short hint line is enough. *Superseded by
  `architecture.md` D21: the quick score now runs on its own for the first
  cards, and the button reads "Quick score the rest".*
- **Fix — the "KetoClub" label above "Where to eat"** (line 194; audit
  D7) is the app's only branding and it is a 10px muted label. Either a
  small logo mark or nothing.
- **Decide — tab switching discards the search** (documented trade-off
  in `app.dart`). On a computer, where a user flips between Saved and
  Explore with a mouse, losing the typed query and the result list each
  time is felt more. A route-level `VenueSearchController` kept alive in
  `AppDependencies` (or `PageStorage`) would keep results across tabs.
- **Left as is:** no location prompt on open (good), skeleton cards
  while loading (good), every failure state has a way out (good), and
  the address in the header being the nearest venue's, not the user's
  (audit D9).

### 2.2 Menu (`menu_screen.dart`, `dish_card.dart`, `verdict_counter_tiles.dart`)

- **Fix — the first dish is below the fold on a phone.** Above the list
  sit: the header, the search field, the carb-budget field *or its
  disabled notice*, the three tiles, the "Showing" label and source
  line, the legend toggle, the progress row, the stale/failed banners,
  the rules banner, the engine chip, and the category chips
  (`_loadedView`, lines 441-498). Suggested order and trims:
  header → tiles → category chips → dishes, with search, budget and the
  rules notice in one collapsible "Filters" row or behind a filter icon
  in the app bar.
- **Fix — the carb-budget "disabled" notice** (`carb_budget_field.dart:77-106`)
  is a permanent grey banner on every rules-classified menu, which on
  the web build without a backend is *every* menu: "Set a budget after
  AI analysis — rule-based results have no carb estimates." A user who
  cannot use the feature should not see a box about it on every visit.
  Render nothing when the budget is unavailable, and mention the budget
  once in the legend.
- **Decide — the rules banner and the "Rules" chip say the same thing**
  (audit M14, still open). Keep the banner (it carries the reason and
  the Retry/Settings actions) and drop the chip on the menu screen; the
  chip still earns its place on Saved and venue cards where there is no
  room for a banner.
- **Fix — the venue name scrolls away.** The app bar has no title
  (line 219) and up to four icon actions (drinks, ask, share, settings);
  the name and score are in the list body. Once a user scrolls into a
  40-dish menu there is no context. A `SliverAppBar` that shows the name
  when the header scrolls under it, or simply `AppBar(title: name)`,
  fixes it; the tiles could pin too (see §1 item 5 for desktop).
- **Fix — four icon-only actions in the app bar** is at the limit for
  discoverability, and "drinks guide" is a content shortcut sitting
  beside "settings". Move drinks and share into an overflow menu, keep
  "Ask about this menu" (it is the AI feature) and Settings visible.
- **Fix — two ways to open the same script on a yellow dish.** The
  amber "Ask your waiter" row expands the script inline; a separate
  "Show the waiter card" text button below it opens the full-screen
  card, and that button is visible even when the disclosure is
  collapsed (`dish_card.dart:191-212`). Show the full-screen action
  inside the expanded panel (an icon beside "Copy"), not as a standing
  second button.
- **Fix — "Add a note" on every card.** `_NoteRow` renders on every
  dish (line 187-190), adding a muted line and an icon to each card
  whether or not a note exists. Show the row only when a note exists,
  and put "Add a note" behind a long-press or an icon in the card's
  corner.
- **Fix — the keto score is always green.** `KetoScoreBadge` paints the
  digit in `green.ink` regardless of value (`keto_score_badge.dart:43`),
  so "3.2 KETO SCORE" reads as a positive claim. Tone it by band (≥7
  green, 4–7 amber, <4 muted), or at least drop the colour below 5.
- **Decide — "₪142.00"** (audit M12). Israeli menus print whole shekels;
  show two decimals only when the price has them.
- **Fix — "With changes" vs "Order with a change" vs "Ask your waiter".**
  The yellow verdict has three labels on one screen: the tile says "With
  changes", the badge says "Order with a change", the disclosure says
  "Ask your waiter". Pick one noun phrase for the verdict and keep "Ask
  your waiter" only as the action.
- **Fix — the unclassified section** (line 1012-1033) is a heading and a
  bare list of names with no card, no way to act (no "classify these"
  retry). Give each name the same card shell as a dish with a neutral
  "not classified" badge, so the list reads as one menu.
- **Fix — the source line's `maxWidth: 180`** truncates a website host
  on a phone but is far too small on a computer once width is
  constrained; make it a fraction of the available width or let it wrap.
- **Left as is:** the rail + badge + tint triple coding of the verdict
  (good for colour-blind users), pull-to-refresh plus a refresh icon,
  the legend that reads the prompt's own definitions, red dishes shown
  by default and filterable by the tile (the Phase 1 decision).

### 2.3 Waiter Card (`waiter_card_sheet.dart`, `waiter_script_widget.dart`)

- **Fix — width on desktop** (§1 item 4).
- **Fix — the sheet has no drag handle and the close button is the only
  exit besides tapping the scrim**; add `showDragHandle: true` as the
  scanned-pages sheet does (`menu_screen.dart:632`).
- **Idea — a "hand to waiter" mode.** The card already raises
  brightness on phones. A single large "Done" button at the bottom
  (the artboard's pinned bar, audit W6) and hiding the app's own chrome
  would make it safe to hand over; today the top-right × is the only
  control and it is small.
- **Fix — copy confirmation** uses a `SnackBar` on the *sheet's*
  messenger; on a full-height sheet it appears under the card and is
  easy to miss. Swap the button label to "Copied ✓" for two seconds.
- **Left as is:** menu-language text direction per line, the "about Ng
  net carbs" note only for an AI verdict.

### 2.4 Scan (`scan_screen.dart`)

- **Fix — two full-width primary buttons on one page**, both
  `ElevatedButton`: "Analyse pages" (disabled until pages exist, so a
  fresh visit shows a disabled primary button) and "Analyse" for the
  paste. Split the page into two clear modes with a `SegmentedButton`
  ("Photos & PDF" / "Paste text" / "QR code" where available) so one
  primary action is on screen at a time, or hide "Analyse pages" until
  there is a page.
- **Fix — button and field styles differ from the rest of the app.**
  Scan and the question sheet use `ElevatedButton`; Explore, banners and
  Settings use `FilledButton`. The paste field, the question field and
  the carb-budget field each pass their own `OutlineInputBorder`
  (`scan_screen.dart:288`, `menu_question_sheet.dart:138`,
  `carb_budget_field.dart:131`), overriding the theme's 14px `--line`
  border. Delete the overrides and use `FilledButton` throughout.
- **Fix — "Take photo" on a computer** opens a file chooser (or nothing,
  depending on the browser). Hide it when `kIsWeb` and no camera, or
  relabel to "Upload photos".
- **Fix — page rows have no reorder and no preview tap.** A user who
  photographed page 2 before page 1 cannot fix the order, and tapping a
  thumbnail does nothing. `ReorderableListView` and a tap that opens the
  page in `ScannedPagesSheet` would close both gaps.
- **Fix — the disclosure line and "Settings" link sit between the page
  list and the Analyse button**, so the eye crosses them on the way to
  the action. Move them under the button in smaller type.

### 2.5 Saved (`saved_screen.dart`)

- **Fix — the tab is misnamed.** The title is "Saved venues" and the
  icon is a bookmark, but nothing is ever saved by the user: it is an
  automatic 24-hour history that also holds pasted menus, scans and
  websites. Call it "Recent" (or "History") with a clock icon; the empty
  state already explains the behaviour correctly.
- **Fix — the entry is a bare `ListTile`** (name, source · age, dish
  count, engine chip) while the same venue on Explore has a photo, a
  score and green/yellow counts. Reuse `VenueCardNumbers` here so a user
  picking where to go back to sees the score, and show the photo when
  the cache has a URL.
- **Fix — no expiry shown.** Entries vanish after a day with no
  warning; "expires in 5 h" on the row (or a "keep" action that pins it)
  makes the behaviour legible.
- **Fix — the remove icon is in the accent colour palette** (default
  `IconButton`), not `red.ink` like Settings' "Clear"; destructive
  actions should look alike.

### 2.6 Settings (`settings_screen.dart`)

- **Fix — the first thing on the page is a 90-word privacy paragraph.**
  The consent section leads, then (on phones) the API key; Language and
  Appearance, the settings most people open Settings for, come third
  and fourth. Reorder: Language, Appearance, Your keto rules, Net-carb
  limit, Default filter, then "AI & privacy" (consent + key), then
  Saved menus, then Drinks guide. Collapse the consent body behind a
  "What leaves this device" disclosure with the checkbox visible.
- **Decide — radio lists for a three-way choice** (audit S6). Language
  and Appearance are each three `RadioListTile`s, 150px tall; a
  `SegmentedButton` is one row and matches the Default filter control
  below them. Tests address the groups by key, so the change is
  contained.
- **Fix — the cache section has no section label** while every other
  group does; add "Saved menus".
- **Fix — the drinks guide is buried at the bottom of Settings.** It is
  content, not a setting; it belongs on Explore (a card under the
  search) or as a "Guides" entry, and the menu app bar icon can then go.
- **Fix — nothing says what version this is or how to report a
  problem.** An "About" row (version, licences, a link to the privacy
  text) is expected in Settings.

### 2.7 Drinks guide (`drinks_guide_screen.dart`)

- **Fix — the three sections are not colour-coded** although they map
  one-to-one onto the verdicts (as-is / swap / skip). A verdict rail or
  the `StatusBadge` on each group header would tie it to the menu
  screen's vocabulary at no cost.
- **Fix — the net-carb `Chip`** uses the theme's filter-chip style
  (pill, `--line` edge), so it looks tappable and it is not. Use the
  dish card's `_NetCarbsChip` shape instead.

---

## 3. Cross-cutting

- **Fix — button hierarchy.** Four button kinds are in use for primary
  actions (`FilledButton`, `ElevatedButton`, `OutlinedButton.icon`,
  `TextButton`). Rule of thumb: one `FilledButton` per screen for the
  primary action, `OutlinedButton` for secondary, `TextButton` for
  inline links; no `ElevatedButton` (it is Material 2's primary).
- **Fix — field styling** (see 2.4): let `inputDecorationTheme` own it.
- **Decide — bundle a Hebrew face** (audit G7). Half the target users
  read Hebrew; on a blocked or slow network the whole UI renders as
  boxes. Noto Sans Hebrew is ~50 KB per weight.
- **Fix — the browser tab title is always "KetoClub"**; `MaterialApp
  .onGenerateTitle` per route ("Hamosad · KetoClub") helps with several
  tabs open and with history.
- **Fix — back-button semantics on web.** A tab tap clears the whole
  stack (`app_shell.dart:80`), so the browser's Back after switching
  tabs leaves the site. Pushing tabs as replacements (`pushReplacementNamed`)
  keeps in-app history sane; the stack-growth bug the clear was added
  for (audit G8) only involved the menu → Settings path and can be
  handled there.
- **Fix — banners share one look for very different weights.** The
  first-launch AI disclosure, the offline notice, the rules reason, the
  carb-budget notice and the stale-cache lines are all grey
  `surfaceContainerHighest` boxes or bare text. Give the one that needs
  a decision (consent) a surface card with the primary button, the
  informational ones a single muted line with an icon, and make offline
  visibly different (amber) since it changes what the app can do.
- **Fix — copy uses "AI" and "rules" without ever explaining rules.**
  The engine chip's tooltip ("not AI-verified") is the only place. One
  line in the legend ("Rules: KetoClub's own keyword checks, no
  estimate of carbs") would let users calibrate trust.
- **Left as is and worth keeping:** every failure reason has distinct
  copy and an action; skeletons instead of spinners; text direction per
  content string; verdicts triple-coded; large-text handling; contrast
  fixes pinned by test; no location prompt until asked.

---

## 4. Suggested order of work

Every remark above is filed as its own issue under the GitHub milestone
**Phase 8: UI Polish & Desktop Web** (#221–#264, label `Phase 8`), and all of
them were built on the `phase-8` branch (PR #266) on 2026-10-01; the
"Decide" items were settled as each issue recommended (architecture.md D20).

1. Content-width constraint (#221) + sheet `maxWidth` (#224) — an
   afternoon, no logic touched, fixes most of "wide and weird".
2. Discovery grid + card surface (#222), "Closed" tag (#227), distance
   (#230).
3. `NavigationRail` at ≥840px (#223).
4. Menu screen top-of-list diet (#234; budget notice #235, chip/banner
   duplicate #236, note row #240, second waiter button #239) and the
   app-bar title (#237).
5. Rename Saved → Recent (#251) and enrich its rows (#252, #253).
6. Settings reorder (#255) and segmented controls (#256).
7. Web shell: splash, manifest colours, path URLs, per-route titles (#226).
8. Hebrew font bundle (#261; product decision on size).

The rest, by section: Explore #228, #229, #231, #232, #233; Menu #238,
#241, #242, #243, #244, #245; Waiter Card #246; Scan #247, #248, #249,
#250; Saved #254; Settings #257, #258; Drinks #259; cross-cutting #260,
#262, #263, #264; desktop two-pane menu #225.
