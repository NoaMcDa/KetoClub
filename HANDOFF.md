# KetoClub — handoff after Phase 1, the Phase 3 backend, and Phase 2

Written at the end of the session that built Phase 1, updated at the close of
issue #36 after a second wave of parallel work substantially extended it,
updated again at the close of issue #97 after the Phase 3 backend foundations
and hosted-classification milestones landed (D11, D12), and updated once more
now that Phase 2's run (10bis, location and nearby search, the Discovery
screen, platform setup, and a run of features beyond those) has landed on top
of both. It says what exists, what is deliberately unfinished, and which
mistakes are already paid for so nobody pays for them twice.

`architecture.md` is the authoritative design. Where it and `README.md` or
`CLAUDE.md` disagree, architecture.md wins; where architecture.md and the code
disagree, that is a bug in one of them and §18.6 wants it fixed in the same pull
request.

---

## What shipped

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
(Saved became a real tab in Phase 2 — see below); and a light/dark
**design-token theme** (`theme/`, issue #9) with two known WCAG AA contrast
failures kept intentionally rather than silently drifting from the artboard (see
"Known limitations" below).

The app still does its job end to end: paste a Wolt link, fetch and cache the
venue's menu, classify every dish 🟢 order-as-is / 🟡 order-with-a-change / 🔴 not
keto with a hosted language model — or with an on-device bilingual rule engine
when there is no key or no network — and show the verdicts with a full-screen
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
  claim before its menu is ever opened: a score and counts only for venues
  whose analysis is already cached on the device, nothing fetched on load or
  scroll. Both discovery fixtures (`wolt_pages_restaurants.json`,
  `wolt_pages_search.json`) are synthetic, same reason and same tracking
  issue (#38) as the Wolt menu fixture below.
- **Step 10, platform setup** (#130): icons, splash, bundle ids and
  permissions for iOS, Android and web. The iOS location-permission string
  (`NSLocationWhenInUseUsageDescription`) is English-only — the project has
  no `InfoPlist.strings` variant group for Hebrew, and `ios/Runner/Info.plist`
  says why wiring one by hand-editing the pbxproj was skipped rather than
  risked. Still owed: an actual run on a physical iOS or Android device (see
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

What is **not** built: Tabit and Ontopo adapters — Wolt and 10bis both ship
now, with an adapter registered in `di.dart` for each; OCR; Phase 3's
community database, user reviews and venue submissions (`backend_plan.md` §5
milestone C, issues #105–#108); and hosting the backend anywhere beyond
`localhost` (issue #109). None of it is stubbed — the files simply do not
exist, which keeps them out of the coverage denominator.

---

## Outstanding before release

Several things are genuinely unfinished. None is a surprise; each is unfinished
for a stated reason, and issues #16, #22, #38, #44 and #65 are still **open**
on GitHub — tooling exists for several of them, it did not close any of them.

1. **The pinned Gemini model has never been called from this environment**
   (§9.3, §17 open question 1 — closed as posed by D12, but the verification it
   always asked for is still owed, now against a different provider).
   `GEMINI_MODEL` defaults to `gemini-2.5-flash`, a backend environment
   variable, not a Dart constant — swapping it is a redeploy, not a code
   change. `generativelanguage.googleapis.com` is blocked from the build
   environment the same way `openrouter.ai` was (the egress proxy answers 403
   to the `CONNECT`), so the real system prompt has never been run against it
   from here. **The one-command check now lives in `backend/README.md`**, in
   its "Manual end-to-end check" section: with `GEMINI_API_KEY` set and the
   server running, a `curl` against `/v1/chat` with a two-dish prompt is the
   whole command, for anyone with a network path to Google. Nobody has run it
   yet. `tool/measure_model_latency.dart`, the OpenRouter-specific version of
   this check, was deleted along with `OpenRouterClient` (#102, D12) — there is
   no client-side model to measure any more, since the app never calls a model
   provider directly.
2. **The Wolt menu fixture is synthetic** (§18.4 — issue #22).
   `test/fixtures/wolt_vitrina_lilinblum_menu.json` says so in its first key, and
   `test/fixtures/README.md` carries the reasoning. It was built to contain the
   shapes the mapper must survive, but it cannot tell you what Wolt actually
   sends. **Also now a one-command job**: `tool/record_wolt_fixture.sh
   <venue-slug>` records a real `menu/data` payload as a checked-in fixture, from
   any machine that can reach `restaurant-api.wolt.com` (this one cannot).
   Nobody has run it yet either. Raised stakes since Phase 2's discovery
   research: two 2025–2026 third-party sources report this same endpoint now
   answers `200` with an **empty body** without a user token
   (`phase2_discovery_research.md` §2.5) — running the recorder either refutes
   that or means the shipped menu path is broken for real users today, which
   would outrank every other item on this list.
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
5. **iOS and every physical device are unexercised.** CI builds web and an Android
   APK, and builds iOS without codesigning on pushes to `main`. Nothing has run on
   a real phone. Screen-brightness raising for the Waiter Card in particular is
   evidenced only by a mocked method channel and a fake — it has never been seen
   to actually happen — and the same is true of the location-permission prompt
   added in Phase 2 (the approximate/precise choice on Android 12+, the "Never"
   path on iOS): evidenced only by fakes until a phone runs it
   (`docs/RELEASE.md`'s device matrix has the row). The iOS permission string
   is also English-only — see "Known limitations" below.
6. **The performance budget is unmeasured on a real device** (issue #65).
   `tool/perf_menu.dart` and its 16 ms-per-frame budget table (`tool/README.md`)
   exist; the 60-dish-fixture, real-phone, real-4G measurement itself does not.
7. **No human has reviewed the code.** §18.6 wants a review by someone who did
   not write it; none of #90, #91, the second wave, or Phase 2's run, was
   merged with one.

Also unverified, lower stakes: no screenshot or narrow-width (390px) run has
confirmed the UI against the `.design/Main.dc.html` artboards. Token fidelity
(colours, spacing values) is enforced by a test; pixel fidelity is not.

---

## Known limitations, deliberately accepted

- **A single malformed `items[]` entry fails a whole Wolt fetch** as
  `platformChanged`, on the theory that a loud schema-drift signal beats a silently
  missing dish. If real payloads ship the occasional odd entry — a null price on a
  "call for price" item — this turns one bad dish into an unreadable menu. Revisit
  when the fixture is re-recorded; the trade is documented in `wolt_menu_mapper.dart`.
- **The keto-substitute guard scans a two-word window**, so `"rice, made from
  cauliflower"` produces a needless yellow ("omit the rice" on a dish with no rice).
  That fails in the safe direction — a pointless modification request, not the wrong
  green architecture.md constraint 5 names as the failure that matters.
- **The web build cannot fetch menus only without the backend running.** The
  restaurant APIs send no CORS headers, so live fetching needed a CORS-forwarding
  proxy (§13, D9); D11 shipped one (`backend/`'s `/v1/proxy/wolt/…` route). With
  `KETOCLUB_BACKEND_URL` configured and the backend up, the web build fetches
  live Wolt menus like any other target; with neither, it is still a mobile
  feature and paste-a-menu is the fallback. The web build's classifier has
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
- **The iOS location-permission string is English-only.** The project has no
  `InfoPlist.strings` variant group registered in `Runner.xcodeproj` (only
  "en" and "Base" are known regions), and wiring one by hand-editing the
  `pbxproj` without Xcode risked corrupting a project file nothing here can
  build-test — `ios/Runner/Info.plist`'s own comment on
  `NSLocationWhenInUseUsageDescription` explains the trade. A Hebrew-speaking
  user sees the English prompt.
- **Wolt's discovery endpoints are unofficial and origin-locked**, and Wolt's
  ToS forbid "systematic retrieval" by a bot. The Discovery screen fetches a
  menu only when the user opens a venue — nothing pre-scores a whole list of
  results by fetching every menu in it — precisely to stay on the side of
  that line; see `phase2_discovery_research.md` §7 for the reasoning issue
  #41/#42 (D13) settled.

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
  `wolt.com`, `www.10bis.co.il` and `generativelanguage.googleapis.com`** (the
  last one since D12; it blocked `openrouter.ai` before that). Nothing can be
  verified against a live service from CI or from a Claude Code session —
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

- `architecture.md` §14 — the decisions log, now D1 to D13, each recording what
  was decided, why, and what it supersedes. The `(Phase 1)` markers throughout
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
