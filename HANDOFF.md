# KetoClub — handoff after Phase 1

Written at the end of the session that built Phase 1, and updated at the close of
issue #36 after a second wave of parallel work substantially extended it. It says
what exists, what is deliberately unfinished, and which mistakes are already paid
for so nobody pays for them twice.

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
  spending an OpenRouter request, to avoid burning the 50-a-day free-tier quota on
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
Scan and Saved as localized placeholder screens, not blank stubs; and a light/dark
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
| Tests | 1707 unit, widget and architecture, plus 6 flow tests on real headless Chrome |
| Coverage | 98.5% of 2331 instrumented lines (gate is 80%) |
| CI | seven checks: backend, format/analyze, tests, integration, build web, build apk, build iOS (main only) |

The **`backend` CI check is new and is not Phase 1 work**: a separate,
parallel-running effort (PR #111) started the Phase 3 FastAPI backend
`backend_plan.md` designs — `backend/` is a real project with its own gate and
tests, serving `GET /v1/health` only (issue #94). **Nothing in `lib/` references
it** (no `KETOCLUB_BACKEND_URL` dart-define is read anywhere), so the Flutter app
remains exactly as client-only as `architecture.md` D1 describes; see
`backend_plan.md`'s status banner before assuming otherwise.

What is **not** built: 10bis, Tabit and Ontopo adapters (10bis is its own GitHub
milestone, `Phase 2: 10bis Integration` — see `MILESTONE_CONVENTIONS.md` for the
real milestone names, which an earlier draft of that document did not match);
nearby venue search; any geolocation (the `geolocator` dependency is present but
unused); OCR; and anything else in Phases 3–4 beyond the backend health-check
scaffold above. None of it is stubbed — the files simply do not exist, which keeps
them out of the coverage denominator.

---

## Outstanding before release

Four things are genuinely unfinished. None is a surprise; each is unfinished for a
stated reason, and issues #16 and #22 are still **open** on GitHub — this pass
gave both of them one-command tooling, it did not close either of them.

1. **The pinned OpenRouter model has never been verified** (§9.3, §17 open
   question 1 — issue #16). `nex-agi/nex-n2.5-pro:free` is pinned with two
   documented fallbacks. The 8–12 second figure in its doc comment comes from
   `m15_openrouter_models_fix.md`, **not from a measurement made here** —
   `openrouter.ai` is blocked from the build environment (the egress proxy
   answers 403 to the `CONNECT`). §9.3 asks for the real system prompt to be run
   against the pinned id and to answer in under 20 seconds. **This is now a
   one-command job for whoever has a network path to OpenRouter**:
   `tool/measure_model_latency.dart` (see `tool/README.md`) sends the real
   prompt to the pinned model and both documented fallbacks, in English and
   Hebrew, checks the reply against the real parser rules, and estimates cost —
   `OPENROUTER_API_KEY=sk-or-... dart run tool/measure_model_latency.dart` is the
   whole command. Nobody has run it yet. Free-tier ids retire without notice,
   and the m15 post-mortem records that when one did, users saw "no internet".
   The model is a constructor parameter, so swapping it is one line in `di.dart`.
2. **The Wolt fixture is synthetic** (§18.4 — issue #22).
   `test/fixtures/wolt_vitrina_lilinblum_menu.json` says so in its first key, and
   `test/fixtures/README.md` carries the reasoning. It was built to contain the
   shapes the mapper must survive, but it cannot tell you what Wolt actually
   sends. **Also now a one-command job**: `tool/record_wolt_fixture.sh
   <venue-slug>` records a real `menu/data` payload as a checked-in fixture, from
   any machine that can reach `restaurant-api.wolt.com` (this one cannot).
   Nobody has run it yet either.
3. **iOS and every physical device are unexercised.** CI builds web and an Android
   APK, and builds iOS without codesigning on pushes to `main`. Nothing has run on
   a real phone. Screen-brightness raising for the Waiter Card in particular is
   evidenced only by a mocked method channel and a fake — it has never been seen
   to actually happen.
4. **No human has reviewed the code.** §18.6 wants a review by someone who did
   not write it; none of #90, #91, or the second wave this pass closes out, was
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
- **The web build cannot fetch menus at all.** The restaurant APIs send no CORS
  headers, so live fetching is a mobile feature until a CORS-forwarding proxy exists
  (§13, D9). The web build's classifier works, because OpenRouter permits
  browser-origin calls.
- **`net_carbs_estimate` is an LLM-only figure the user is told is an estimate**
  (§17.4, reversed this pass from "never rendered"). `DishCard` now shows it as
  `"~{n}g net carbs (estimate)"`, hidden entirely when null — always true for a
  rules-engine result — because the model can produce a number but it cannot be
  trusted as fact, and the copy and `Semantics` label both say so.
- **Two light-mode colour pairs fail WCAG AA contrast**, kept exactly as the
  artboard specifies rather than silently drifting from it: the green status
  pill's own text on its green fill measures 4.08:1, and light `ink3` on `bg`
  measures 2.78:1 — both documented in `lib/theme/app_tokens.dart` and tracked as
  issue #64, not fixed here.

---

## Where to start next

Build-order §16 continues at step 6, **but the backend comes first**: the web
build cannot fetch Wolt menus (CORS), so a local Python backend is planned in
`backend_plan.md` — issues #94–#109 across three "Phase 3" milestones. **#94 has
landed** (`backend/`, a health endpoint only, see `backend_plan.md`'s status
banner); continue at #95 and #96, the menu-proxy route. Once that lands,
`flutter run -d chrome` with `--dart-define=KETOCLUB_BACKEND_URL=http://
localhost:8000` should show a live menu — nothing in `lib/` reads that
dart-define yet, so this is still the *next* step, not a done one.

- **Step 6 — the 10bis adapter**, tracked as its own GitHub milestone,
  `Phase 2: 10bis Integration` (see `MILESTONE_CONVENTIONS.md`), not a Phase 1
  one. Blocked on a live capture: the shape of `dishOptionsList` is undocumented
  anywhere in this repo, there is no stable category id (only `categoryName`),
  and no real restaurant id or URL form is recorded. `VenueRefResolver` already
  recognises a pasted 10bis URL or bare id and resolves it to `MenuSource.tenbis`
  — see `tenbis_paste_flow_test.dart` — but `MenuRepository` has no adapter
  registered for that source yet, so it fails with `unsupportedSource`. Capture a
  real response first; the adapter is otherwise a direct analogue of the Wolt
  one, and the `PlatformMenuAdapter` interface plus its shared contract suite
  already exist.
- **Step 7 — location and nearby search.** Also blocked: §17.2 records that no Wolt
  venue-search endpoint is known. `menu_api_research` covers menus only. Paste-a-link
  (Tier A) already ships, so this is Tier B polish rather than a gap in the product.
- **Step 8 — platform setup** and a run on a physical iOS and Android device against
  a real Wolt venue.

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
- **The egress proxy blocks `restaurant-api.wolt.com`, `www.10bis.co.il` and
  `openrouter.ai`.** Nothing can be verified against a live service from CI or from
  a Claude Code session. `pub.dev` and `storage.googleapis.com` are reachable.
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

- `architecture.md` §14 — the decisions log, D1 to D10, each recording what was
  decided, why, and what it supersedes. The `(Phase 1)` markers throughout were
  added across both waves of this work. D10 was rewritten in place, not
  appended to: it first recorded that a connectivity pre-check was deliberately
  cut, then — in the second wave — that decision was reversed and the old
  paragraph replaced, per §18.6's rule that code and this document may not
  disagree.
- `architecture.md` §17 — open questions, each with the default the code
  follows. Open question 1 (which model to pin) is still open — it stays
  outstanding until someone runs `tool/measure_model_latency.dart` from a
  machine that can reach OpenRouter. Question 4 (`net_carbs_estimate`) was
  answered in the second wave (issue #30). Question 5 (cache TTL) has not
  changed since the first wave: still 24 hours, still recorded as a guess, just
  a guess in one named place (`menuCacheTtl`).
- The commit messages on #90, #91, and the pull requests merged into
  `claude/phase-1-milestones-parallel-26wbh2` carry the reasoning for individual
  decisions, including the corrections made to agents' first attempts and why.
- Issue #36 (this documentation pass) is what reconciled `CLAUDE.md`,
  `architecture.md`, `MILESTONE_CONVENTIONS.md` and this file against the code
  as it stood after that second wave — including three reversed decisions, a
  parallel-track backend scaffold that landed with no client wiring, and a
  `MILESTONE_CONVENTIONS.md` phase breakdown that had drifted from the
  milestones actually created on GitHub.
- `m15_openrouter_models_fix.md` and `m16_structured_output_fix.md` are post-mortems
  from a different application, but they are the best evidence available on
  OpenRouter's behaviour and their lessons are encoded as rules in §9.
