# `tool/`

## `check.sh`, `coverage_gate.sh`, `gen_coverage_helper.sh`

The gate. See `CLAUDE.md` / `architecture.md` §18.5 — run
`flock /tmp/ketoclub.lock tool/check.sh` before pushing.

## `measure_model_latency.dart` — the OpenRouter pre-release check (issue #16)

`architecture.md` §9.3 and §17.1 ask for one thing before every release: run
the real system prompt against the pinned OpenRouter model and confirm it
answers in under 20 seconds with a reply the parser accepts. This script is
that check, automated, plus the two things #16 also asked for — the
`json_schema`/`json_object` fallback check and a per-menu cost estimate — so
it is a five-minute job for whoever has a network path to `openrouter.ai`.

### Running it

From the repository root, with a real OpenRouter API key:

```bash
OPENROUTER_API_KEY=sk-or-v1-... dart run tool/measure_model_latency.dart
```

That's the whole command. No build step, no `flutter pub get` beyond what
the repository already needs, no other environment variable. The key is
read once from `OPENROUTER_API_KEY` and is never printed, logged, or
written anywhere — same rule as `lib/services/llm/open_router_client.dart`
(architecture.md §11).

**This container cannot run it.** The egress proxy answers `403` to the
`CONNECT` for `openrouter.ai` from here (confirmed directly, and recorded in
`HANDOFF.md` and in `open_router_client.dart`'s own doc comment), so issue
#16 stays open until someone runs this from a machine that can reach
OpenRouter. Everything below this line is what that person needs to know;
none of it was exercised end-to-end from this environment.

### What the script does

For the pinned model (`OpenRouterClient.defaultOpenRouterModel`) and each of
its two documented fallbacks (`OpenRouterClient.documentedFallbackModels`),
against both a 40-dish English fixture menu and a 40-dish Hebrew fixture
menu (`test/fixtures/latency_menu_en.json` / `_he.json`) — six runs in
total:

1. Builds the real system prompt and the real per-menu user prompt text
   (mirrors of `MenuAnalysisPrompt`, kept honest by
   `test/tool/measure_model_latency_test.dart` — see the script's own doc
   comment for why it cannot import that class directly: `dart:ui` is not
   available to the plain `dart` command this script runs under).
2. Sends one chat-completion request with the strict `json_schema`
   `response_format`; on a 400/404/422 (a shape refusal, not a key/quota/
   provider problem), retries once with `json_object`, exactly like
   `OpenRouterClient.complete` does.
3. Times the whole exchange, decodes the reply, and runs it through a
   dependency-free reimplementation of `MenuResponseParser`'s `badResponse`
   checks to report whether the real parser would accept it.
4. Fetches `GET https://openrouter.ai/api/v1/models` once and estimates
   this request's USD cost from the reply's own token usage — see the
   formula below.
5. Prints one `PASS`/`FAIL` line per model per language.

### Reading the output

One line per (model, language), for example:

```
--- nex-agi/nex-n2.5-pro:free (en) ---
PASS  latency=8214ms  validJson=true  structuredOutputs=true  jsonObjectFallback=false  parserAccepted=true (40/40 dishes placed by id)  costPerMenu=$0.000000
```

**A PASS line means exactly issue #16's accept rule**: valid JSON matching
the schema, structured outputs supported *or* the `json_object` fallback
worked, the real parser would accept the reply, and the whole exchange took
under 20 seconds (`llmReleaseCheckSeconds` in `lib/utils/constants.dart`).
Any one of those failing is a `FAIL` line, and `errorDetail=` names what
went wrong (a network failure, a non-200 status, an unparseable reply, and
so on).

The final summary line and the process exit code care only about the
**pinned** model: a fallback failing is informative, not fatal — that is
the point of having fallbacks — but the pinned model failing for either
language exits non-zero, so this can be wired into a pre-release CI job or
a pre-push hook without anyone having to read the output by hand.

`parserAccepted`'s parenthesised detail (`"N/M dishes placed by id"`) is
diagnostic, not part of the PASS/FAIL rule: it tells you how many of the
fixture's dishes the model actually recognised and classified, which is
useful for judging model quality even on a run that technically passes.

### The cost formula (for the Settings screen)

```
costUsd = promptTokens * pricing.prompt + completionTokens * pricing.completion
```

`promptTokens` / `completionTokens` come from the gateway response's own
`usage` object (never estimated from a character or word count — OpenRouter
returns the real counts), and `pricing.prompt` / `pricing.completion` are
USD-per-token, read from `GET https://openrouter.ai/api/v1/models` and
matched by the model id that actually served the reply (OpenRouter can
route to a different model than the one requested). This is a **per-menu**
figure: architecture.md D6 sends one request per menu however many dishes
it holds, so `costPerMenu` in the output is already the cost of analysing
one visit's menu, not one dish. A future Settings screen wanting to show
"estimated cost per scan" can use this exact formula against the same
`/models` pricing endpoint.

### When the pinned model has retired

Free-tier model ids on OpenRouter retire without notice (this is what
`m15_openrouter_models_fix.md` documents happening once already). If this
script's pinned-model lines come back `FAIL` with `errorDetail=gateway
refused the request (status 404)`, the id has most likely retired:

1. Run this script again with `OPENROUTER_API_KEY` set to confirm the 404
   (not a transient network issue).
2. Pick a new free-tier model on <https://openrouter.ai/models> that
   supports structured outputs (or at least `json_object`).
3. Change **one line** — `OpenRouterClient.defaultOpenRouterModel` in
   `lib/services/llm/open_router_client.dart` — to the new id. It is a
   constructor default parameter, not wired anywhere else; `di.dart`
   picks it up automatically.
4. Update `OpenRouterClient.documentedFallbackModels` and the doc comment
   above `defaultOpenRouterModel` with what this script measured for the
   new pin (latency, and which of the old fallbacks still work).
5. Run `flock /tmp/ketoclub.lock tool/check.sh` — `test/tool/
   measure_model_latency_test.dart` and `test/services/llm/
   open_router_client_test.dart` will catch anything the swap missed.
6. Run this script one more time against the new pin before shipping.

### The fixture menus

`test/fixtures/latency_menu_en.json` and `latency_menu_he.json` are
synthetic 40-dish menus (not recorded responses — see
`test/fixtures/README.md`'s convention for `llm_*.json` and the Wolt
fixtures for why synthetic is the right call here too), built to be
realistic in length and variety rather than to exercise any particular
classification rule. If a future model needs a bigger or smaller menu to
test against, edit those two files directly — the script does not
hardcode dish counts anywhere; `test/tool/measure_model_latency_test.dart`
only asserts they currently hold 40 dishes each and that the Hebrew one is
actually written in Hebrew.
