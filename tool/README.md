# `tool/`

## `check.sh`, `coverage_gate.sh`, `gen_coverage_helper.sh`

The gate. See `CLAUDE.md` / `architecture.md` §18.5 — run
`flock /tmp/ketoclub.lock tool/check.sh` before pushing.

## `record_wolt_fixture.sh` — re-record the Wolt fixture (issue #22)

`test/fixtures/wolt_vitrina_lilinblum_menu.json` is synthetic, not a recorded
response (`test/fixtures/README.md` explains why and says so in the fixture's
first key). This script records a real `menu/data` payload from a given venue
slug as a checked-in fixture, from any machine that can reach
`restaurant-api.wolt.com` — this repository's build environment cannot.

## `perf_menu.dart`: main-thread timings for a 60-dish menu (issue #65)

Times the CPU-bound steps of opening a menu, on the thread that also draws
frames, over generated 60-dish menus:

| Step | What runs | Budget |
|---|---|---|
| decode + map (Wolt / 10bis) | `jsonDecode` then `WoltMenuMapper.toMenu` / `TenBisMenuMapper.toMenu` | 16 ms |
| fingerprint | `TextNormaliser.menuFingerprint` (a refresh runs it twice) | none, informational |
| rules engine | `HeuristicMenuClassifier.classify` | none, informational |
| reply parse | `MenuResponseParser.parse` of a 60-dish AI reply | 16 ms |

The 16 ms budget is one frame at 60 Hz. Issue #65's rule: if decode + map
or the reply parse takes longer than that **on a phone**, that step moves to
`compute`. Nothing has been moved yet. The move depends on a phone
measurement, and `compute` gains nothing on web, where it runs on the
main thread anyway.

It cannot be run with `dart run`: everything it times imports
`package:flutter/foundation.dart`, which needs `dart:ui`.

- **On a phone (the numbers that count)**:
  ```bash
  flutter run --profile -t tool/perf_menu.dart -d <device>
  ```
  The table prints to the `flutter run` console. The screen stays blank
  because the entry point never calls `runApp`. The 60-dish payloads are
  generated in code, so nothing has to be copied to the device. Copy the
  medians into `docs/RELEASE.md` §5.
- **On the host** (relative cost and regressions only, not the budget):
  ```bash
  flutter test test/tool/perf_menu_test.dart --reporter expanded
  ```
  One test prints the same table with the two checked-in fixtures
  (`test/fixtures/wolt_vitrina_lilinblum_menu.json`,
  `tenbis_synthetic_menu.json`) added as extra decode + map rows. These are
  unoptimised JIT timings on a desktop CPU. The test asserts no duration,
  so CI never fails on a slow runner.

A row ending in `OVER` has a median above its budget.

## `visual_audit/` — render the web build and the artboards

`stub_upstream.py` stands in for Wolt and 10bis with `test/fixtures/`,
`shoot.py` drives the real web build in headless Chromium (Playwright) and
screenshots every reachable screen at 390px, light and dark, English and
Hebrew, and `render_artboards.py` (with `support.js`, a stand-in for the
design canvas runtime) renders the `.design/` artboards at the same size.
`docs/VISUAL_AUDIT.md` has the full recipe and what the first run found.
None of it runs in CI.

## Model verification moved to the backend (D12)

**There is no `measure_model_latency.dart` any more.** Before D12, this
directory held a script that ran KetoClub's real system prompt against the
pinned OpenRouter model from the command line, because the model was reached
directly from the Dart client with the user's own key. Since D12, classification
goes through KetoClub's own backend, which holds a Google Gemini key
server-side, so there is no client-side model call left to measure this way —
`OpenRouterClient`, the script, and its test were all deleted together in #102.

The equivalent check now lives in `backend/README.md`'s "Manual end-to-end
check" section: with `GEMINI_API_KEY` set and the backend running, a `curl`
against `/v1/chat` is the one-command way to see a real completion from the
pinned model (`GEMINI_MODEL`, default `gemini-2.5-flash`) — see that file for
the exact command. `generativelanguage.googleapis.com` is unreachable from this
build environment the same way `openrouter.ai` was, so nobody has run it from
here yet (`architecture.md` §17 open question 1, `HANDOFF.md`).
