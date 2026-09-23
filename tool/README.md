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
