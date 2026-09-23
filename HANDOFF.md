# KetoClub — handoff after Phase 1, and the Phase 3 backend

Written at the end of the session that built Phase 1, updated at the close of
issue #36 after a second wave of parallel work substantially extended it, and
updated again at the close of issue #97 after the Phase 3 backend foundations
and hosted-classification milestones landed (D11, D12). It says what exists,
what is deliberately unfinished, and which mistakes are already paid for so
nobody pays for them twice.

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

What is **not** built: 10bis, Tabit and Ontopo adapters (10bis is its own GitHub
milestone, `Phase 2: 10bis Integration` — see `MILESTONE_CONVENTIONS.md` for the
real milestone names, which an earlier draft of that document did not match);
nearby venue search; any geolocation (the `geolocator` dependency is present but
unused); OCR; Phase 3's community database, user reviews and venue submissions
(`backend_plan.md` §5 milestone C, issues #105–#108); and hosting the backend
anywhere beyond `localhost` (issue #109). None of it is stubbed — the files
simply do not exist, which keeps them out of the coverage denominator.

---

## Outstanding before release

Four things are genuinely unfinished. None is a surprise; each is unfinished for a
stated reason, and issues #16 and #22 are still **open** on GitHub — this pass
gave both of them one-command tooling, it did not close either of them.

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
- **Two light-mode colour pairs fail WCAG AA contrast**, kept exactly as the
  artboard specifies rather than silently drifting from it: the green status
  pill's own text on its green fill measures 4.08:1, and light `ink3` on `bg`
  measures 2.78:1 — both documented in `lib/theme/app_tokens.dart` and tracked as
  issue #64, not fixed here.

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
`backend/README.md`'s manual end-to-end check for the exact steps. Build-order
§16 continues at **step 8**:

- **Step 8 — the 10bis adapter**, tracked as its own GitHub milestone,
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
- **Step 9 — location and nearby search.** Also blocked: §17.2 records that no Wolt
  venue-search endpoint is known. `menu_api_research` covers menus only. Paste-a-link
  (Tier A) already ships, so this is Tier B polish rather than a gap in the product.
- **Step 10 — platform setup** and a run on a physical iOS and Android device against
  a real Wolt venue.

Once those resume, the remaining Phase 3 milestone — community database, ratings,
submissions (`backend_plan.md` §5 milestone C, #105–#108) — and hosting the
backend beyond `localhost` (#109) are still open, tracked separately from the
build order above.

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
  `generativelanguage.googleapis.com`** (the last one since D12; it blocked
  `openrouter.ai` before that). Nothing can be verified against a live service
  from CI or from a Claude Code session. `pub.dev` and `storage.googleapis.com`
  are reachable.
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

- `architecture.md` §14 — the decisions log, now D1 to D12, each recording what
  was decided, why, and what it supersedes. The `(Phase 1)` markers throughout
  were added across both waves of that work. D10 was rewritten in place, not
  appended to: it first recorded that a connectivity pre-check was deliberately
  cut, then — in the second wave — that decision was reversed and the old
  paragraph replaced, per §18.6's rule that code and this document may not
  disagree. D11 and D12, added in this pass (issue #97), record the backend
  (an accelerator amending D1/D9/D10) and the move to a backend-held Google
  Gemini key (superseding D3) the same way — as decisions with reasoning and a
  named cost, not a silent rewrite.
- `architecture.md` §17 — open questions, each with the default the code
  follows. Open question 1 ("which OpenRouter model to pin") is closed as posed
  by D12 — there is no OpenRouter model any more — but the pre-release
  verification it always asked for is still outstanding against Gemini; see
  `backend/README.md`'s manual end-to-end check. Question 4 (`net_carbs_estimate`)
  was answered in the second Phase 1 wave (issue #30). Question 5 (cache TTL) has
  not changed since the first wave: still 24 hours, still recorded as a guess,
  just a guess in one named place (`menuCacheTtl`). This pass added question 6
  (hosting the backend beyond `localhost`, issue #109), left open on purpose:
  D11's "accelerator, never a dependency" is exactly what makes that safe to
  leave open.
- The commit messages on #90, #91, and the pull requests merged into
  `claude/phase-1-milestones-parallel-26wbh2` carry the reasoning for individual
  Phase 1 decisions; the pull requests closing #94–#103 carry the same for the
  backend and D11/D12, including the corrections made to agents' first attempts
  and why.
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
