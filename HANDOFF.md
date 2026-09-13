# KetoClub — handoff after Phase 1

Written at the end of the session that built Phase 1. It says what exists, what is
deliberately unfinished, and which mistakes are already paid for so nobody pays
for them twice.

`architecture.md` is the authoritative design. Where it and `README.md` or
`CLAUDE.md` disagree, architecture.md wins; where architecture.md and the code
disagree, that is a bug in one of them and §18.6 wants it fixed in the same pull
request.

---

## What shipped

**Phase 1 — build-order steps 1 to 5 of architecture.md §16**, merged in #90, with
the documentation reconciliation and two flow tests following in #91.

The app does its job end to end: paste a Wolt link, fetch and cache the venue's
menu, classify every dish 🟢 order-as-is / 🟡 order-with-a-change / 🔴 not keto with
a hosted language model — or with an on-device bilingual rule engine when there is
no key and no network — and show the verdicts with a full-screen Waiter Card to
read to a server.

| | |
|---|---|
| Tests | 1418 unit, widget and architecture, plus 3 flow tests on real headless Chrome |
| Coverage | 98.9% of 1673 instrumented lines (gate is 80%) |
| CI | six checks: format/analyze, tests, integration, build web, build apk, build iOS (main only) |

What is **not** built: 10bis, Tabit and Ontopo adapters; nearby venue search; any
geolocation (the `geolocator` dependency is present but unused); OCR; and anything
in Phases 3–4. None of it is stubbed — the files simply do not exist, which keeps
them out of the coverage denominator.

---

## Outstanding before release

Four things are genuinely unfinished. None is a surprise; each is unfinished for a
stated reason.

1. **The pinned OpenRouter model has never been verified** (§9.3, §17.1).
   `nex-agi/nex-n2.5-pro:free` is pinned with two documented fallbacks. The 8–12
   second figure in its doc comment comes from `m15_openrouter_models_fix.md`, **not
   from a measurement made here** — `openrouter.ai` is blocked from the build
   environment. §9.3 asks for the real system prompt to be run against the pinned id
   and to answer in under 20 seconds. Do that before shipping. Free-tier ids retire
   without notice, and the m15 post-mortem records that when one did, users saw
   "no internet". The model is a constructor parameter, so swapping it is one line in
   `di.dart`.
2. **The Wolt fixture is synthetic** (§18.4).
   `test/fixtures/wolt_vitrina_lilinblum_menu.json` says so in its first key, and
   `test/fixtures/README.md` carries the `curl` to re-record it. It was built to
   contain the shapes the mapper must survive, but it cannot tell you what Wolt
   actually sends. Re-record from a real venue.
3. **iOS and every physical device are unexercised.** CI builds web and an Android
   APK, and builds iOS without codesigning on pushes to `main`. Nothing has run on a
   real phone.
4. **No human has reviewed the code.** §18.6 wants a review by someone who did not
   write it; #90 and #91 were merged without one.

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
- **`net_carbs_estimate` is modelled but never rendered** (§17.4). The model can
  produce a number; it cannot be trusted as fact.

---

## Where to start next

Build-order §16 continues at step 6.

- **Step 6 — the 10bis adapter.** Blocked on a live capture: the shape of
  `dishOptionsList` is undocumented anywhere in this repo, there is no stable
  category id (only `categoryName`), and no real restaurant id or URL form is
  recorded. Capture a real response first; the adapter is otherwise a direct analogue
  of the Wolt one, and the `PlatformMenuAdapter` interface plus its shared contract
  suite already exist.
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
  decided, why, and what it supersedes. D10 (no connectivity pre-check) and the
  `(Phase 1)` markers throughout were added by this work.
- `architecture.md` §17 — open questions, each with the default the code follows.
- The commit messages on #90 and #91 carry the reasoning for individual decisions,
  including the corrections made to agents' first attempts and why.
- `m15_openrouter_models_fix.md` and `m16_structured_output_fix.md` are post-mortems
  from a different application, but they are the best evidence available on
  OpenRouter's behaviour and their lessons are encoded as rules in §9.
