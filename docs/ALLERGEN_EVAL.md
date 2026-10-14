# Allergen evaluation: the last result

**Status: not yet run.** No person has run the model evaluation, so this page
holds no figure. The script that fills it in is
`backend/tools/allergen_eval.py` (ALG-10, issue #352); until it has been run
with a real key, nothing on this page is a measurement.

## What is measured

The allergen safety corpus (`test/fixtures/allergens/`) is a set of labelled
menus: for each dish and each restriction, `contains`, `may_contain` or
`free`. **The labels are unreviewed desk research.** No dietitian, allergist
or lawyer has read them (`test/fixtures/allergens/README.md`), so every
figure below is a question for the labels as much as for the engine, and
none of it should be quoted as a clinical claim until a person with a
clinical background has reviewed the labels, the Hebrew ones first.

For each strict restriction (every allergen, and celiac disease) the page
reports recall three ways:

| Source | What it is |
|---|---|
| Rules alone | `allergen_concerns` over the dish text, with no model. This is also the CI gate (see below). |
| Model alone | The `ingredients` the model returns for the dish under the extraction prompt, each name run through the allergen matcher and cut to the weaker of the ingredient's certainty and the trigger's. |
| Merged | The surest certainty per restriction across both: what the app shows when the model answered. |

A `contains` label counts as found when a concern of at least `likely`
certainty comes back for that restriction, and a `may_contain` label when
one of at least `suspected` does. False alarms (a concern on a dish
labelled `free`) are counted and shown, and never count against recall: a
false alarm is the acceptable direction.

## The CI gate is separate

The rules-only half runs on every push, with no key and no network:
`test/utils/allergens/corpus_recall_test.dart` (Dart) and
`backend/tests/test_allergen_corpus_recall.py` (Python) hold the same gate
and print the same per-restriction table. The misses the vocabulary does
not close yet are listed in `test/fixtures/allergens/known_misses.json`,
read by both; a miss that is not listed fails the build, and so does a
listed entry that no longer misses, so the list can only shrink.

## How to run it

```bash
cd backend
GEMINI_API_KEY=... uv run python tools/allergen_eval.py
```

One request goes out per corpus menu, through the backend's own model
client and the extraction prompt, and nothing is stored. The script makes
real network calls and spends the key's quota. It rewrites this page's status line
and its "Last result" section (`--no-write` prints the result instead). It refuses to run when no key
is set or when this checkout's prompt module cannot yet ask for ingredients
(ALG-03).

## Last result

Not yet run.
