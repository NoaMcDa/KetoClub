# KetoClub — handoff after Phase 1, the Phase 3 backend, Phase 2, Phase 4's scan core, and Phase 8

Written at the end of the session that built Phase 1, updated at the close of
issue #36 after a second wave of parallel work substantially extended it,
updated again at the close of issue #97 after the Phase 3 backend foundations
and hosted-classification milestones landed (D11, D12), and updated once more
now that Phase 2's run (10bis, location and nearby search, the Discovery
screen, platform setup, and a run of features beyond those) has landed on top
of both, again for Phase 4's menu-scanning core (paste, photographs, PDF),
and once more for Phase 8 (the UI/UX review's 44 issues, #221–#264, built in
parallel on the `phase-8` branch and opened as PR #266).
It says what exists, what is deliberately unfinished, and which
mistakes are already paid for so nobody pays for them twice.

`architecture.md` is the authoritative design. Where it and `README.md` or
`CLAUDE.md` disagree, architecture.md wins; where architecture.md and the code
disagree, that is a bug in one of them and §18.6 wants it fixed in the same pull
request.

---

## What shipped

**Phase 8 — UI Polish & Desktop Web (PR #266, issues #221–#264).** Every
remark in `docs/UX_REVIEW.md` became one issue and one feature branch
(`p8/<n>-<slug>`), merged into `phase-8` in eight waves with `tool/check.sh`
green after each. The two threads: the web build on a computer (a
`ContentWidth` cap on every screen, a 1/2/3-column venue grid, a
`NavigationRail` at 840px+, 560px modal sheets, a two-pane menu at 1080px+, a
web splash, cream manifest colours, path URLs, per-route tab titles, focus
rings and desktop autofocus) and per-screen polish (see CLAUDE.md's status
banner for the list). Things to know that the issues did not predict:
`ContentWidth` is top-aligned, not centred, because a Scaffold body gets loose
height; the venue photo stays a 118px banner in one column and is 3:2 only in
the grid; browser Back is handled by a `PopScope` in `AppShell` (a plain
`pushReplacementNamed` could not work, since `MaterialApp` without a `Router`
uses single-entry browser history); the Recent tab's Keep pin lives in a
second Hive box (`menu_cache_pins`), so no schema migration; `package_info_plus`
backs the About group behind an `AppInfo` seam. **Unverified**: nothing in
Phase 8 has been seen in a real browser or on a phone; the wide layouts are
evidenced by widget tests at 1200/1440px and by CI's 1600px headless-Chrome
flow run only.


**Phase 1 — build-order steps 1 to 5 of architecture.md §16**, originally merged
in #90/#91, then substantially extended by a second wave of parallel work closed
out by this documentation pass (issue #36 — the last Phase 1 issue). Three
previously-recorded decisions were **reversed** in that second wave, in place, not
appended beside the old text (§18.6 forbids code and this document disagreeing):

- **`Connectivity` is reinstated** (`architecture.md` §14 D10). It previously
  recorded that this abstraction was deliberately cut; `services/platform/
  connectivity.dart` now exists and `RoutingMenuClassifier` asks it before ever
  spending a model request, to avoid burning the per-install rate limit (D12) on
  a call that cannot succeed. It is a hint, never a verdict: a failed call still
  reports `offline` exactly as before.
- **`net_carbs_estimate` now renders** (`architecture.md` §17.4). It previously
  said "never shown as fact" and meant "never shown at all"; `DishCard` now
  renders it as a labelled `"~{n}g net carbs (estimate)"` chip, hidden entirely
  when the field is null — which is always true for a rules-engine result, since
  `HeuristicMenuClassifier` never sets it.
- **The collapsed red-dish group is gone** (`architecture.md` §6.6, issue #29).
  The three verdict counter tiles are the filter now — tap the "Skip" tile and
  non-keto dishes are the list, shown inline with the same rail, tint and pill
  every other verdict gets. `MenuController.redRows` went with the group.

Also new since #90/#91: a menu-header **keto score out of 10** (`utils/
keto_score.dart`, renders nothing when null, never a fallback `0.0`); the Waiter
Card **raises screen brightness** while open and restores it on close
(`services/platform/screen_brightness.dart`); a **bottom-navigation shell**
(`AppShell`, issue #11) around four tabs — Explore, Scan, Saved, Settings — with
Scan and Saved as localized placeholder screens at the time, not blank stubs
(Saved became a real tab in Phase 2, Scan in Phase 4 — see below); and a light/dark
**design-token theme** (`theme/`, issue #9) with two known WCAG AA contrast
failures kept intentionally rather than silently drifting from the artboard (see
"Known limitations" below).

The app still does its job end to end: paste a Wolt link, fetch and cache the
venue's menu, classify every dish 🟢 order-as-is / 🟡 order-with-a-change / 🔴 not
keto with Google's Gemini model — called directly with the user's key on a
phone, through the backend on web — or with an on-device bilingual rule engine
when there is no key, no backend or no network — and show the verdicts with a full-screen
Waiter Card to read to a server.

| | |
|---|---|
| Tests | 1707+ unit, widget and architecture on the Flutter side (figure as of the Phase 1 close-out; the backend work since added its own suite, see below), plus flow tests on real headless Chrome |
| Coverage | 98.5% of 2331 instrumented lines as of Phase 1 close-out (gate is 80%, both `tool/check.sh` and `backend/check.sh`) |
| CI | seven checks: backend, format/analyze, tests, integration, build web, build apk, build iOS (main only) |

**The `backend` CI check, started as scaffolding-only Phase 1 work (PR #111,
issue #94, `GET /v1/health` only), is now doing the job it was built for**: the
Phase 3 FastAPI backend `backend_plan.md` designs is built out — the Wolt menu
proxy (#95), `WoltMenuAdapter` taking a `proxyBase` so the web build routes
through it (#96), and `POST /v1/chat` forwarding to Google Gemini with the
server's own key, an anonymous install id and a per-install rate limit
(#100–#103). `lib/` now reads `KETOCLUB_BACKEND_URL` (in `di.dart` only) and
`BackendChatClient` replaced `OpenRouterClient` — the bring-your-own-key path is
gone entirely (D12). The backend remains an accelerator, never a dependency: with
no backend URL configured the app still behaves exactly as the fully
client-only version did. `architecture.md` D11 and D12 (§14) are the
authoritative record of what shipped; `backend_plan.md`'s own status banner may
lag behind them.

**Since D17 (issue #194) the backend serves the web build only.** iOS and
Android call Wolt and Google's Gemini API themselves and ignore
`KETOCLUB_BACKEND_URL`. The Wolt half was already true (`menuProxyBase` is null
off the web). The Gemini half is new: `GeminiChatClient`
(`services/llm/gemini_chat_client.dart`) is a Dart port of the backend's
`services/gemini.py` and calls `generateContent` with a key the user pastes into
a phone-only Settings section, kept in the Keychain/Keystore by
`SecureApiKeyStore` (`flutter_secure_storage`, reinstated). `di.dart`'s
`apiKeyStoreFor`/`chatClientFor` pick the phone or web path. Two failure
reasons exist only on phones, `apiKeyMissing` and `apiKeyRejected`; both fall
back to rules and offer "Open Settings". `architecture.md` D17 is the record.

**Phase 2 — build-order steps 8 to 10, plus a run of features neither step
names — has since landed too.** It shipped as a run of PRs (#124–#154) after
the plan in `phase2_plan.md`, with a mid-run docs pass (#146, #147) closing
out the Discovery chain that first run had deferred:

- **Step 8, the 10bis adapter** (#126 proxy route, #127 `TenBisMenuMapper`,
  #134 `TenBisAdapter` + `di.dart` registration). `VenueRefResolver` had
  already recognised a pasted 10bis URL or bare id since Phase 1; #134 is what
  closed the gap HANDOFF previously recorded — `MenuRepository` now has an
  adapter for it, so a 10bis link resolves and fetches end to end, not just
  parses. The 10bis menu fixture is still synthetic (issue #44, tracked
  separately from the Wolt one) — `test/fixtures/README.md` has the curl to
  run once a machine can reach `www.10bis.co.il`.
- **Step 9, location and nearby search.** §17.2's blocker ("no Wolt
  venue-search endpoint is known") was resolved by research rather than a
  live capture: `phase2_discovery_research.md` documents two unofficial,
  anonymous, origin-locked Wolt endpoints (`GET .../v1/pages/restaurants`
  near a point, `POST .../v1/pages/search` by name) from third-party clients,
  confidence-rated since none of them were reachable to verify directly.
  `LocationService` (#151, issue #37) wraps `geolocator` — bumped from the
  `^11.0.0` the dependency had sat at unused to `^14.0.0` — behind a sealed
  `LocationResult`; the Wolt venue-search proxy (#149, issue #123) and
  `WoltVenueSearchService` (#150, issue #39) back a real Discovery screen
  (#154, issue #40) with a location header, search, filter chips and venue
  cards. `architecture.md` D13 (added by #147) governs what a venue card may
  claim before its menu is ever opened: a score and counts for venues whose
  analysis is cached on the device or, since D21, scored by the capped
  rules-only quick score that runs when a list arrives; nothing fetched on
  scroll. Both discovery fixtures (`wolt_pages_restaurants.json`,
  `wolt_pages_search.json`) are synthetic, same reason and same tracking
  issue (#38) as the Wolt menu fixture below.
- **Step 10, platform setup** (#130): icons, splash, bundle ids and
  permissions for iOS, Android and web. The iOS permission strings have Hebrew
  translations on disk (`ios/Runner/{en,he}.lproj/InfoPlist.strings`, #169,
  #196; the camera and photo-library ones arrived with the Scan tab), but the
  Runner target registers them only after a one-time Xcode step
  (`docs/RUNNING_IOS.md`), because hand-editing the pbxproj risked corrupting
  it. Still owed: an actual run on a physical iOS or Android device (see
  "Outstanding before release" below).

The same run also built a real Saved tab (#132, issue #48: cached menus,
offline access, remove — no longer a placeholder), dish and venue photos from
the feeds with a placeholder tile (#152, issue #50), and a run of features
`architecture.md` §16 does not name step-by-step: pull-to-refresh and
stale-menu refetch (#128), personal notes on dishes (#131), a menu source/
freshness line with refresh (#136), the net-carb limit stepper (#135), an
engine name shown while analysing plus a perf harness (#137), opening the
venue on its source platform (#138), a Settings appearance toggle (#129),
persisted last-filter/last-venue (#141), search within a menu with
category-jump chips (#140), dietary rule toggles (#143), a shareable
text-summary menu card (#145), and error-recovery UX — retry actions, an
offline banner, cached-menu fallback copy (#144). `docs/RELEASE.md` (#133)
is the pre-release checklist and device-test matrix that names what a real
device run still needs to confirm.

**Phase 4, "Menu Scanning", has its core built** (the one GitHub milestone
"Phase 4: Menu Scanning"; it absorbed the earlier Vision Classifier milestone).
A menu no delivery platform serves now comes from the Scan tab, three ways, all
stored under `MenuSource.scan` and opened at `/venue/scan/{id}` like any venue:

- **Paste** (#83, D18): `TextMenuSource.parse` turns lines of text into a `Menu`
  (prices stripped, no options, ids `p1..pN`); `MenuRepository.store` caches it
  and the ordinary classifier router reads it. The ref is a hash of the dishes,
  so pasting the same menu twice is one cache entry.
- **Photographs, gallery images and a PDF** (#170, #89, #82; D15): pages travel
  as image parts of the one chat request per menu (`LlmChatClient.complete`'s
  `images`; `/v1/chat`'s `images` on web, straight to Google on phones), and
  `VisionMenuClassifier` has Gemini transcribe *and* classify them in that one
  call. It is a **sibling** of `MenuClassifier` (`ScannedMenuClassifier`),
  fronted by `RoutingScannedMenuClassifier` (consent, then connectivity), with
  **no rules fallback**: the rule engine needs text and a photo has none. The
  reply goes through `MenuResponseParser.parseScanned`, which swaps "never
  invent a dish" (there is no source menu to check against) for "drop a
  nameless element, keep the first of duplicate names". The scan menu's header
  says it was read by AI and offers **View pages** from `ScannedPagesRegistry`,
  the in-memory page thumbnails, so the user can check the transcription
  against the photograph. Page bytes are never cached (Hive would hold them
  as JSON), never stored server-side and never logged beyond a count.
  `DevicePagePicker` (over `image_picker` and `file_picker`) is the one place
  that touches the camera, gallery or file system.
- **No on-device OCR** (D15; #81 closed as not planned): Gemini reads the page
  itself, so a misread column cannot be lost before classification starts.

Also shipped: flow tests for the three scan paths (**#84**), menus read
from a restaurant's own website (**#181**, D19: paste any restaurant URL; the
backend's `POST /v1/website/fetch` on web, a direct fetch on phones, a PDF
read by the vision path), and a table's QR code (**#182**: the Scan tab's
"Scan QR code" reads it with the camera through `MobileQrScanner`, and the
pure `QrPayloadRouter` sends a Wolt, 10bis, website or PDF link to that menu,
says Tabit is not supported yet, and suggests photographing the menu for
Instagram, Linktree or a non-link code). Still open in that milestone: **#88**
the person-run Gemini vision smoke test (`backend/tools/vision_smoke.py`).
Configurable dietary rules, which the roadmap once listed under
Phase 4, had already shipped under Phase 2 (#56, #143).

What is **not** built: Tabit and Ontopo adapters — Wolt and 10bis both ship
now, with an adapter registered in `di.dart` for each, and so does a
restaurant's own website (D19) and a scanned QR code (#182); Phase 3's
community database, user reviews and venue submissions (`backend_plan.md` §5
milestone C, issues #105–#108); and hosting the backend anywhere beyond
`localhost` (issue #109). None of it is stubbed — the files simply do not
exist, which keeps them out of the coverage denominator.

---

## Outstanding before release

Several things are genuinely unfinished. None is a surprise; each is unfinished
for a stated reason, and issues #16, #38, #44, #65 and #88 are still **open**
on GitHub — tooling exists for several of them, it did not close any of them.

1. **The pinned Gemini model has never answered a phone's request** (§9.3, §17
   open question 1 — closed as posed by D12, but the verification it always
   asked for is still owed for phones). The model is `gemini-3.5-flash` on
   both paths: the backend's `GEMINI_MODEL` default on web, and
   `GeminiChatClient.defaultModel` on phones (D17) — a Dart constant there, so
   swapping the phones' model is a release, not a redeploy. The retiring
   `gemini-2.5-flash` answers 404 to new keys, which is why both moved. As of
   2026-09-28 `generativelanguage.googleapis.com` **is** reachable from the
   build environment (it was blocked before): Google's real invalid-key 400
   was recorded into `gemini_chat_client_test.dart`, and the Gemini smoke test
   (#165, `architecture.md` §17.1) saw real completions through the local
   backend from a laptop. **No completion has been seen from the phone path
   (`GeminiChatClient`) with a valid key.** For the web path, the one-command
   check is in `backend/README.md`'s "Manual end-to-end check" section. For a
   phone, run the app on a device, paste a key in Settings, leave AI analysis
   on (the D16 default) and open a Wolt menu; the engine chip should read
   "AI".
2. **The Wolt menu fixture is real now; the endpoint moved** (issues #22,
   #168, both closed by the port). Wolt's `/v4/venues/slug/{slug}/menu/data`
   answers every anonymous caller with `200` and a zero-byte body — measured
   2026-09-25 by the owner against two venues, with and without the web-client
   header set — so every Wolt menu in the shipped app read `platformChanged`.
   `WoltMenuAdapter` and the backend's menu proxy now call Wolt's
   consumer-assortment endpoint (`consumer-api.wolt.com/consumer-api/
   consumer-assortment/v1/venues/slug/{slug}/assortment`) with the web-client
   header set (`lib/utils/wolt_headers.dart`), and `WoltMenuMapper` reads its
   shape. `test/fixtures/wolt_hamosad_menu.json` is a **real recording** of it
   (12 categories, 56 items), the fixture the mapper and shape tests run
   against; the synthetic `/v4` fixture is gone. What the recording could not
   settle: the payload names no currency (the mapper defaults to `ILS`), no
   venue name, and every recorded `subcategories` list is empty, so the
   flattening rule for them is inferred, not observed. Re-record with
   `tool/record_wolt_fixture.sh <slug>` from any machine that can reach
   `consumer-api.wolt.com` (this one cannot). The Discovery-chain
   recordings below are still owed.
3. **The Wolt discovery fixtures are synthetic too** (issue #38, tracked
   separately from #22). `wolt_pages_restaurants.json` and
   `wolt_pages_search.json` were hand-built from third-party client
   documentation (`phase2_discovery_research.md` §2), because neither
   `consumer-api.wolt.com` nor `restaurant-api.wolt.com` is reachable from
   here. `phase2_discovery_research.md` §2.4 has the exact capture steps for
   whoever records them.
4. **The 10bis fixture is synthetic** (issue #44, tracked separately from
   #22 and #38). `tenbis_synthetic_menu.json` was hand-built from
   `menu_api_research` and issue #44's own body text, because
   `www.10bis.co.il` is also blocked here. `test/fixtures/README.md` has the
   curl to run once a machine can reach it, and what to check
   (`TenBisMenuMapper`'s assumed field names) once it does.
5. **No real Gemini request has carried images** (#88, D15). Everything on the
   vision path is proven against fakes: whether `gemini-3.5-flash` accepts
   `image/*` and `application/pdf` parts with the real prompt and schema, how
   long a multi-page scan takes (the text path took 33.5 s cold for 20 dishes),
   and how faithfully it transcribes a real printed, photographed or Hebrew menu
   are unobserved. Run `backend/tools/vision_smoke.py` against a backend that
   holds a key (its docstring has the command), with real menu photos, and
   record the outcome in `architecture.md` §17.
6. **iOS and every physical device are unexercised.** CI builds web and an Android
   APK, and builds iOS without codesigning on pushes to `main`. Nothing has run on
   a real phone. Screen-brightness raising for the Waiter Card in particular is
   evidenced only by a mocked method channel and a fake — it has never been seen
   to actually happen — and the same is true of the location-permission prompt
   added in Phase 2 (the approximate/precise choice on Android 12+, the "Never"
   path on iOS): evidenced only by fakes until a phone runs it
   (`docs/RELEASE.md`'s device matrix has the row). The Scan tab's pickers are
   in the same position: the camera and photo-library permission prompts, the
   gallery and PDF pickers and a real photograph's size and orientation are
   evidenced only by fakes until a phone runs them. The iOS Hebrew permission
   strings still need their Xcode registration — see "Known limitations" below.
7. **The performance budget is unmeasured on a real device** (issue #65).
   `tool/perf_menu.dart` and its 16 ms-per-frame budget table (`tool/README.md`)
   exist; the 60-dish-fixture, real-phone, real-4G measurement itself does not.
8. **No human has reviewed the code.** §18.6 wants a review by someone who did
   not write it; none of #90, #91, the second wave, or Phase 2's run, was
   merged with one.

Also lower stakes: the UI has now been compared with the `.design/`
artboards, on the web build at 390px, light and dark, English and Hebrew —
`docs/VISUAL_AUDIT.md` has the recipe (`tool/visual_audit/`), the findings
and what was deliberately left. It could render rules-engine results only
(no model is reachable here) and ran on no phone. Token fidelity (colours,
spacing values) is enforced by a test; pixel fidelity by no test at all.

---

## Known limitations, deliberately accepted

- **A single malformed `items[]` entry fails a whole Wolt fetch** as
  `platformChanged`, on the theory that a loud schema-drift signal beats a silently
  missing dish. If real payloads ship the occasional odd entry — a null price on a
  "call for price" item — this turns one bad dish into an unreadable menu. The one
  real recording (`wolt_hamosad_menu.json`, #168) has no such entry — every item has
  an integer price, a string description and well-formed options — so the trade
  stands; the two joins stay lenient (an unknown `item_id` or `option_id` is
  skipped, and the recording does carry two dangling `option_id`s). The trade is
  documented in `wolt_menu_mapper.dart`.
- **The keto-substitute guard scans a two-word window**, so `"rice, made from
  cauliflower"` produces a needless yellow ("omit the rice" on a dish with no rice).
  That fails in the safe direction — a pointless modification request, not the wrong
  green architecture.md constraint 5 names as the failure that matters.
- **The carb-only-dish rule (#191) fires on the dish name only**, and
  stands down when the description or an option names a filling from a
  fixed protein/plant/dairy vocabulary. A bread named "לאפה" and described
  with a filling word the vocabulary lacks is still red, and a dish named
  plainly but described as "just a basket of fries" still gets the D-V3
  yellow. **The option-removal rule (#192) keys on a value's first word
  only**, so "Bun, no sesame" — a removal that is not the first word — is
  still read as an ingredient, not dropped. **`מאפה` is red** even for a
  crustless "מאפה חצילים", accepted as the rarer reading.
- **The web build cannot fetch menus only without the backend running.** The
  restaurant APIs send no CORS headers, so live fetching needed a CORS-forwarding
  proxy (§13, D9); D11 shipped one (`backend/`'s `/v1/proxy/wolt/…` route). With
  `KETOCLUB_BACKEND_URL` configured and the backend up, the web build fetches
  live Wolt menus like any other target; with neither, it is still a mobile
  feature and the Scan tab's paste-a-menu (D18) is the fallback. The web build's classifier has
  always worked regardless, because it always went through a backend that
  permits browser-origin calls — KetoClub's own since D12, OpenRouter before it.
- **`net_carbs_estimate` is an LLM-only figure the user is told is an estimate**
  (§17.4, reversed this pass from "never rendered"). `DishCard` now shows it as
  `"~{n}g net carbs (estimate)"`, hidden entirely when null — always true for a
  rules-engine result — because the model can produce a number but it cannot be
  trusted as fact, and the copy and `Semantics` label both say so.
- **The three colour pairs that failed WCAG AA contrast are fixed**: the
  green status pill's own text on its green fill was 4.08:1 (now 4.97:1),
  light `ink3` on `bg` was 2.78:1 (now 4.57:1), and dark `ink3` on `bg` was
  4.02:1 (now 5.08:1). The new values and the reasoning are in
  `lib/theme/app_tokens.dart`'s "Contrast fixes" note, and every drawn
  `on`/surface pair — these three plus every other one `VerdictColors`
  produces — is pinned by `test/theme/contrast_test.dart` (issue #64's
  contrast half; semantics/RTL/large text are a later PR).
- **A scan has no rules fallback and no offline path.** The rule engine needs
  text, so with consent withheld, no network or a failed model call a photograph
  or PDF produces an error and nothing else (D15). Pasted text does fall back to
  rules, being an ordinary menu. Scan pages also never survive a restart: only the
  transcription is cached, and the registry keeps the pages of at most the last
  four scans, so "View pages" disappears once the app is closed (or the scan is
  evicted) and the menu then reads like a pasted one.
- **The iOS Hebrew permission strings are unregistered until someone runs one
  Xcode step.** `ios/Runner/{en,he}.lproj/InfoPlist.strings` hold the location,
  camera and photo-library prompts in both languages (#169, #196, #205), but
  `Runner.xcodeproj` was not edited by hand — nothing here can build-test a
  project file — so iOS cannot discover them until the "Add Files to Runner"
  step in `docs/RUNNING_IOS.md` ("iOS Hebrew permission string") is done on a
  Mac. Until then, and until a Hebrew phone has shown the result, a
  Hebrew-speaking user may still see the English prompt.
- **Wolt's discovery endpoints are unofficial and origin-locked**, and Wolt's
  ToS forbid "systematic retrieval" by a bot. Since D21 the Discovery screen
  does pre-score the first `venueAutoEstimateLimit` (12) venues of a list by
  fetching their menus for the rule engine, three at a time, each once per
  list — an exposure the owner accepted knowingly; see `architecture.md` D21
  for the bounds and `phase2_discovery_research.md` §7 for the reasoning
  issue #41/#42 (D13) originally settled the other way.

---

## Where to start next

**The backend came first, and it has landed** (build-order §16 steps 6–7, D11,
D12): `backend/` now serves `GET /v1/health`, the Wolt menu proxy (#95, D11),
and `POST /v1/chat` against Google Gemini with the server's own key, an
anonymous install id and a per-install rate limit (#100–#103, D12).
`WoltMenuAdapter` takes a `proxyBase` and the web build routes through it when
configured (#96); `BackendChatClient` replaced `OpenRouterClient` and the
bring-your-own-key path is gone entirely (#102). `flutter run -d chrome
--dart-define=KETOCLUB_BACKEND_URL=http://localhost:8000` against a running
backend shows a live menu with AI analysis and no key entered anywhere — see
`backend/README.md`'s manual end-to-end check for the exact steps.

**Build-order §16's steps 8, 9 and 10 have since landed too**, closing out
what this section previously called blocked:

- **Step 8 — the 10bis adapter** (#126, #127, #134). The live capture this
  section used to say was required turned out not to be, in the same way
  step 9 below did: `TenBisAdapter` was written against a synthetic fixture
  built from `menu_api_research` §3.2 and issue #44's body text, and is
  registered in `di.dart`. `VenueRefResolver`'s existing 10bis recognition
  now actually reaches an adapter instead of `unsupportedSource`. The real
  capture (issue #44) is still owed before release — see "Outstanding before
  release".
- **Step 9 — location and nearby search** (#37/#151, #39/#150, #123/#149,
  #40/#154, D13). §17.2's "no Wolt venue-search endpoint is known" was
  answered by `phase2_discovery_research.md`'s third-party research rather
  than a live capture, the same move as step 8: two unofficial, anonymous
  Wolt endpoints were documented with confidence ratings and built against
  synthetic fixtures. `LocationService`, `WoltVenueSearchService`, the
  discovery proxy routes and the Discovery screen all ship. Recording the
  real fixtures (issue #38) and a phone run of the permission prompt are
  still owed.
- **Step 10 — platform setup** (#130): icons, splash, bundle ids and
  permissions. A run on a physical iOS and Android device against a real
  Wolt venue is still owed — see "Outstanding before release" item 5.

What resumes now is the remaining Phase 3 milestone — community database,
ratings, submissions (`backend_plan.md` §5 milestone C, #105–#108) — and
hosting the backend beyond `localhost` (#109), both still open and tracked
separately from the build order above, plus the recordings and phone/device
work "Outstanding before release" lists.

---

## Environment and workflow

- **Flutter 3.47.4 / Dart 3.13.3**, pinned in two places that must agree:
  `flutter-version` in `.github/workflows/ci.yml` and `environment: flutter` in
  `pubspec.yaml`. Bump both in one commit.
- **`tool/check.sh` is the gate.** It runs exactly what the `quality` and `test` CI
  jobs run: `pub get`, `dart format --set-exit-if-changed`, `flutter analyze
  --fatal-infos --fatal-warnings`, the all-imports coverage helper, `flutter test
  --coverage`, and the 80% coverage gate. Run it before pushing.
- **An info-level lint fails the build.** `--fatal-infos` is not decoration: the
  80-column limit and `public_member_api_docs` apply to `test/` and
  `integration_test/` too.
- **The egress proxy blocks `restaurant-api.wolt.com`, `consumer-api.wolt.com`,
  `wolt.com` and `www.10bis.co.il`.** `generativelanguage.googleapis.com` was
  blocked too until at least D12, but answered from here on 2026-09-28 (a fake
  key got Google's real invalid-key 400); a real key is still needed to see a
  completion. Nothing else can be verified against a live service from CI or
  from a Claude Code session —
  including Phase 2's discovery endpoints, which is why
  `phase2_discovery_research.md` is confidence-rated third-party evidence
  rather than a capture. `pub.dev` and `storage.googleapis.com` are reachable.
- **Running several agents in one worktree:** serialise test runs with
  `flock /tmp/ketoclub.lock -c 'flutter test …'`. Concurrent `flutter test` races on
  `.dart_tool` and `coverage/lcov.info` and produces failures that are not real.
  `tool/check.sh` formats the whole tree, so it will trip over another agent's
  in-flight file; scope checks to your own paths until the wave ends.

---

## Traps that already cost time

Each of these was found the expensive way. They are in `architecture.md` too, but
this is the short list.

- **Dart's `\b` is ASCII-only.** `RegExp(r'\bפסטה\b')` matches *nothing*, and
  `unicode: true` does not change it. A literal port of README's `rf"\b{base}\b"`
  leaves the entire Hebrew vocabulary dead while every English test passes. Hebrew
  triggers use a lookaround that is permissive on the left (ב/ה/ו/כ/ל/מ/ש are
  grammatical particles) and strict on the right (a suffix is a different word).
- **A web flow test's imports must be same-directory or `package:`.** `flutter
  drive` compiles the test as a web app entry point and roots
  `org-dartlang-app:///` at that file's directory, so `../support/…` or
  `../../test/fakes/…` fails to resolve and the app never compiles. This is why
  `integration_test/flows/flow_support.dart` duplicates a few fakes instead of
  importing `test/fakes/`. Note that **`flutter test -d flutter-tester` and
  `flutter build web --target=…` both pass anyway** — only `flutter drive` catches
  it, and it does so without needing a working browser, because the compile happens
  while it waits for one.
- **`material.dart` exports its own `MenuController`** in this SDK, colliding with
  ours in `state/`. Files needing both import material with `hide MenuController`.
- **`services/` may import neither `dart:io` nor `package:flutter/services.dart`.**
  The first breaks `flutter build web`; the second breaks the architecture test. So
  no `SocketException` (use `ClientException`) and no `PlatformException` by name —
  the plugin-backed stores catch `Exception` and say why at the top of the file.
- **No constructor reached from `di.dart` may perform plugin I/O.**
  `buildDependencies()` runs from `main()` and from tests with no plugin binding, so
  Hive and shared_preferences are reached through closures invoked on first use. Break
  this and `di_test`, `main_test` and the launch flow test all fail at once with
  `MissingPluginException`, and `di.dart` becomes uncoverable. `di_test` asserts it.
- **A `ListView` builds lazily against the viewport**, so widgets below the fold do
  not exist in the element tree and `find.text` returns nothing rather than
  "off-screen". `MenuScreen` keeps its `ListView` deliberately — a 60-dish menu
  should stay lazy — so a test asserting on content below its fold must scroll first.
  `SettingsScreen` uses a `Column` in a `SingleChildScrollView` for the opposite
  reason: it is short, and a screen reader should not have to scroll to find a control.
- **`FLOW_TEST_CONVENTIONS.md`'s examples do not match this codebase.** They
  reference `HomeScreen`, `VenueListScreen` and a string `status` field, none of which
  exist. They are illustrative, not runnable. Same for the hypothetical workflow files
  in `UNIT_TEST_CONVENTIONS.md`: the real CI is the single `.github/workflows/ci.yml`.
  Worth tidying both documents.

---

## Where the reasoning lives

- `architecture.md` §14 — the decisions log, now D1 to D18, each
  recording what was decided, why, and what it supersedes. The `(Phase 1)` markers throughout
  were added across both waves of that work. D10 was rewritten in place, not
  appended to: it first recorded that a connectivity pre-check was deliberately
  cut, then — in the second wave — that decision was reversed and the old
  paragraph replaced, per §18.6's rule that code and this document may not
  disagree. D11 and D12 record the backend (an accelerator amending D1/D9/D10)
  and the move to a backend-held Google Gemini key (superseding D3) the same
  way — as decisions with reasoning and a named cost, not a silent rewrite. D13
  (Phase 2, issue #41/#42) records what a Discovery venue card may claim before
  its menu is opened — a score and counts only for venues already cached on the
  device, nothing fetched on load or scroll.
- `architecture.md` §17 — open questions, each with the default the code
  follows. Open question 1 ("which OpenRouter model to pin") is closed as posed
  by D12 — there is no OpenRouter model any more — but the pre-release
  verification it always asked for is still outstanding against Gemini; see
  `backend/README.md`'s manual end-to-end check. Question 2 (the Wolt
  venue-search endpoint) is answered as far as third-party evidence goes —
  `phase2_discovery_research.md` §2 — but not verified by a live call; the
  browser recording (#38) is still outstanding. Question 4
  (`net_carbs_estimate`) was answered in the second Phase 1 wave (issue #30).
  Question 5 (cache TTL) has not changed since the first wave: still 24 hours,
  still recorded as a guess, just a guess in one named place (`menuCacheTtl`).
  Question 6 (hosting the backend beyond `localhost`, issue #109) is still
  open on purpose: D11's "accelerator, never a dependency" is exactly what
  makes that safe to leave open.
- `phase2_plan.md` and `phase2_discovery_research.md` are Phase 2's own
  planning documents — an execution plan and issue list, then the research
  that unblocked the Discovery chain a first run of that plan had deferred.
  Read them for the reasoning behind individual Phase 2 issues; this document
  and `CLAUDE.md`/`architecture.md` are where that reasoning gets reconciled
  against what actually shipped.
- The commit messages on #90, #91, and the pull requests merged into
  `claude/phase-1-milestones-parallel-26wbh2` carry the reasoning for individual
  Phase 1 decisions; the pull requests closing #94–#103 carry the same for the
  backend and D11/D12, and #124–#154 for Phase 2 and D13, including the
  corrections made to agents' first attempts and why.
- Issue #36 (the first documentation pass) reconciled `CLAUDE.md`,
  `architecture.md`, `MILESTONE_CONVENTIONS.md` and this file against the code
  as it stood after the second Phase 1 wave — including three reversed
  decisions, a parallel-track backend scaffold that landed with no client
  wiring, and a `MILESTONE_CONVENTIONS.md` phase breakdown that had drifted
  from the milestones actually created on GitHub. Issue #97 (this pass) did the
  same after the backend foundations and hosted-classification milestones
  landed, adding D11 and D12 and correcting every reference to OpenRouter, a
  user-supplied key, or a client-only web build across these documents,
  `backend_plan.md`, `MILESTONE_CONVENTIONS.md` and `tool/README.md`.
- `m15_openrouter_models_fix.md` and `m16_structured_output_fix.md` are
  post-mortems from a different application and a different provider, but they
  are still the best evidence available on hosted-LLM failure modes in
  general, and their lessons — distinct failure reasons, a strict-schema
  request with a fallback, verifying the pinned model before release — are
  encoded as rules in §9, now against Gemini rather than OpenRouter.
