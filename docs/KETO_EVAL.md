# Keto evaluation: the last result

**Status: not yet run.** No person has run the model evaluation, so this page holds no model figure. The rules-only tables under "Last result" were made 2026-10-28 from `backend/tests/fixtures/keto_eval/menus` with `--rules-only`, which is not the keto corpus: they show the page's shape, not a measurement.

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

A flagged source matches a labelled hidden carb when it matches the label's
`source` or its `term`, and two texts match when their normalised forms
(`app.keto.normaliser.normalise`, which drops punctuation and brackets) are
equal or one holds the other as whole words: "sugar" matches "brown sugar",
and both "sweet marinade" and "מרינדה מתוקה" match the label
"sweet marinade (מרינדה מתוקה)".

## The CI gate is separate

The rules-only half runs on every push, with no key and no network:
`backend/tests/test_keto_corpus_gate.py` (Python) and the Dart gate over the
same corpus hold the same rule. A dish whose rules verdict the labels do not
accept is a miss; the misses the rules do not close yet are listed in
`test/fixtures/keto/known_keto_misses.json` (`[{menu, dish, expected, got,
reason}]`, read by both). A miss that is not listed fails the build, and so
does a listed entry that no longer misses in exactly that way, so the list
can only shrink. The Python gate skips when the corpus directory is absent
or empty.

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

Run: 2026-10-28 17:27 UTC. Commit: `2d5aaef`. Corpus: `backend/tests/fixtures/keto_eval/menus` (2 menus, 11 dishes). Model: **not yet run** (rules only). Net-carb limit: 6 g, keto only.

The labels are **unreviewed**: no dietitian has read them, so every figure here is a question for the labels as much as for the engine.

### Overall

| Source | Dishes | Accuracy | **False green** | False red | Unclassified | Hidden-carb recall | Hidden-carb precision |
|---|---:|---:|---:|---:|---:|---:|---:|
| Rules | 11 | 10/11 (90.9%) | **1/7 (14.3%)** | 0/9 (0.0%) | 0 | 0/3 (0.0%) | 0/0 (-) |

### Per language

| Slice | Dishes | Accuracy | **False green** | False red | Unclassified | Hidden-carb recall | Hidden-carb precision |
|---|---:|---:|---:|---:|---:|---:|---:|
| en: Rules | 6 | 5/6 (83.3%) | **1/4 (25.0%)** | 0/5 (0.0%) | 0 | 0/2 (0.0%) | 0/0 (-) |
| he: Rules | 5 | 5/5 (100.0%) | **0/3 (0.0%)** | 0/4 (0.0%) | 0 | 0/1 (0.0%) | 0/0 (-) |

### Hidden carbs

| Source | Labelled | Found | Recall (likely) | Recall (suspected) | Flagged | Matched a label | Precision |
|---|---:|---:|---:|---:|---:|---:|---:|
| Rules | 3 | 0 | 0/2 (0.0%) | 0/1 (0.0%) | 0 | 0 | - |

### False greens

| Menu | Dish | Expected | Rules |
|---|---|---|---|
| eval_en_bistro | Coleslaw | modifiable | orderAsIs |
