# Keto evaluation: the last result

**Status: not yet run.** No person has run the model evaluation, so this page holds no model figure. The rules-only tables under "Last result" were made 2026-10-28 from `test/fixtures/keto/menus` with `--rules-only`.

## What is measured

The Israeli keto corpus (`test/fixtures/keto/menus/`, contract in
`test/fixtures/keto/SCHEMA.md`) is a set of labelled menus: for each dish
the verdict a careful keto diner would reach (`orderAsIs`, `modifiable` or
`nonKeto`), any other verdict that is also defensible (`acceptable`), and
the hidden carbs a standard recipe carries (`hiddenCarbs`). **The labels
are unreviewed desk research.** No dietitian has read them, so every figure
below is a question for the labels as much as for the engine, and none of it
should be quoted as a claim about the app until a person has reviewed them.

Each dish is scored three ways:

| Source | What it is |
|---|---|
| Rules | The on-device rule engine's twin (`app.keto.heuristic`) over the dish text, with no model. This is also the CI gate (see below). |
| Model | The model's reply to the real text-path prompt and schema (`app.keto.prompt`, keto only, 6 g), read by the real parser (`app.keto.parser`) exactly as the app reads it: an invented dish is dropped, a yellow with no instruction is unclassified, a green over 6 g or with a hidden carb is demoted. |
| Merged | The model's verdict with a rules floor: a dish the rules call `modifiable` or `nonKeto` is never upgraded to `orderAsIs`. A dish the model did not place keeps the rules' verdict; hidden carbs are the union. |

The metrics, the same in the Python and the Dart scoring:

| Metric | Definition |
|---|---|
| Accuracy | Dishes whose verdict is the expected one or an `acceptable` one, over all dishes. An unclassified dish is never correct. |
| **False green** (the headline) | Dishes expected `modifiable` or `nonKeto` that came back `orderAsIs` (when that is not acceptable for them), over all dishes expected `modifiable` or `nonKeto`. A false green is the error that puts carbs on a diner's plate. |
| False red | Dishes expected `orderAsIs` or `modifiable` that came back `nonKeto` (not acceptable), over all dishes expected `orderAsIs` or `modifiable`. |
| Unclassified | Dishes with no verdict at all. |
| Hidden-carb recall | Labelled hidden carbs that a flagged source matches, over labelled hidden carbs; also split by the label's certainty. |
| Hidden-carb precision | Flagged sources that match a labelled hidden carb, over flagged sources. |

A produced hidden-carb flag (the model's or the rules') matches a labelled
one by the label's `term`, the text in the dish that points at it: the
flag's source contains the term, the term contains the flag's source, or
the flag's waiter question contains the term. A label with no `term` (a
carb the dish implies rather than names) falls back to its `source`: one of
the two texts contains the other. Every text is normalised first
(`app.keto.normaliser.normalise`: case, punctuation and brackets gone).

## The CI gate is separate

The rules-only half runs on every push, with no key and no network:
`backend/tests/test_keto_corpus_gate.py` (Python) and
`test/utils/keto/keto_corpus_gate_test.dart` (Dart) hold the same rule over
the same corpus. **Only false greens fail.** The false greens the rules do
not close yet are listed in `test/fixtures/keto/known_keto_misses.json`
(`[{menu, dish, expected, got, reason}]`, false greens only, read by both;
the Dart gate's `--dart-define=KETO_GATE_WRITE_MISSES=true` rewrites it,
keeping each reason and marking a new entry `TODO`). An unlisted false green
fails the build, and so does a listed entry that is no longer a false green
or whose `expected` or `got` changed, so the list can only shrink. Every
other disagreement (a false red, a yellow for a red) is printed and never
fails. The Python gate skips when the corpus directory is absent or empty.

## How to run it

```bash
cd backend
GEMINI_API_KEY=... uv run python tools/keto_eval.py
```

The key is read from the environment only, never from `backend/.env`; with
none the script says so and exits 1. Each corpus menu goes out through the
backend's own model client (`app.services.gemini.complete`) with the real
prompt and schema, split into batches exactly as `/v1/classify` splits a
large menu (#188), one request at a time with a pause between them
(`--delay`, default 4 s). A failure (`timeout`, `rateLimited`,
`badResponse`, ...) is recorded against its batch and never stops the run;
that batch's dishes count as unclassified for the model. The run reports
latency and, when the reply exposes them, token counts per menu. The script
makes real network calls and spends the key's quota.

| Flag | Effect |
|---|---|
| `--no-write` | Print the report instead of rewriting this page. |
| `--record` | Also save each menu's raw upstream replies, with no request, no header and the key redacted, to `test/fixtures/llm/keto_eval/<menu>.json`. |
| `--menus a,b` | Run only these menu ids. |
| `--timeout S` | Seconds to wait for each request (default 180; the client's own read timeout of 110 s may answer `timeout` first). |
| `--rules-only` | Score the rules alone; needs no key and sends nothing. |
| `--corpus DIR` | Score another directory of labelled menus. |

It rewrites this page's status line and its "Last result" section with the
run's date, the configured `GEMINI_MODEL`, the commit, and the tables.

## Last result

Run: 2026-10-28 19:40 UTC. Commit: `6cd4060`. Corpus: `test/fixtures/keto/menus` (24 menus, 456 dishes). Model: **not yet run** (rules only). Net-carb limit: 6 g, keto only.

The labels are **unreviewed**: no dietitian has read them, so every figure here is a question for the labels as much as for the engine.

### Overall

| Source | Dishes | Accuracy | **False green** | False red | Unclassified | Hidden-carb recall | Hidden-carb precision |
|---|---:|---:|---:|---:|---:|---:|---:|
| Rules | 456 | 400/456 (87.7%) | **6/343 (1.7%)** | 5/232 (2.2%) | 0 | 5/137 (3.6%) | 5/12 (41.7%) |

### Per language

| Slice | Dishes | Accuracy | **False green** | False red | Unclassified | Hidden-carb recall | Hidden-carb precision |
|---|---:|---:|---:|---:|---:|---:|---:|
| he: Rules | 441 | 388/441 (88.0%) | **6/331 (1.8%)** | 4/225 (1.8%) | 0 | 5/134 (3.7%) | 5/12 (41.7%) |
| mixed: Rules | 15 | 12/15 (80.0%) | **0/12 (0.0%)** | 1/7 (14.3%) | 0 | 0/3 (0.0%) | 0/0 (-) |

### Hidden carbs

| Source | Labelled | Found | Recall (likely) | Recall (suspected) | Flagged | Matched a label | Precision |
|---|---:|---:|---:|---:|---:|---:|---:|
| Rules | 137 | 5 | 5/81 (6.2%) | 0/56 (0.0%) | 12 | 5 | 41.7% |

### False greens

| Menu | Dish | Expected | Rules |
|---|---|---|---|
| golden_hebrew | דג מטוגן | modifiable | orderAsIs |
| il_juice_bar | קומבוצ׳ה | nonKeto | orderAsIs |
| il_moroccan | תה נענע מרוקאי | nonKeto | orderAsIs |
| il_sushi_bar | סלט וואקמה | modifiable | orderAsIs |
| il_sushi_bar | סאקה חם | nonKeto | orderAsIs |
| il_vegan_place | גבינת קשיו | modifiable | orderAsIs |
