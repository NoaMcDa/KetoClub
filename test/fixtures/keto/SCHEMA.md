# Keto corpus file schema

One JSON file per menu under `test/fixtures/keto/menus/`. Every dish carries
the verdict a careful keto reader would give it and the hidden carbs it
likely hides. The labelling rules are in `README.md`; this file is only the
shape, and `test/utils/keto/keto_corpus_shape_test.dart` enforces it.

**Unreviewed desk labelling — not reviewed by a dietitian.** Every file says
so in its top-level `note`.

## Menu

```json
{
  "id": "il_seed_grill",
  "name": "גריל השכונה",
  "source": "synthetic",
  "language": "he",
  "note": "Unreviewed desk labelling — not reviewed by a dietitian. …",
  "categories": [
    {"name": "מנות עיקריות", "dishes": [ … ]}
  ]
}
```

| Field | Type | Meaning |
|---|---|---|
| `id` | string | Equals the file name without `.json`. Unique across the corpus. |
| `name` | string | The venue name as a menu would show it (becomes `Menu.venueName`). |
| `source` | string | `synthetic`, or `copied:<repo-relative path>` when the dish texts were copied from another fixture. Copied texts are unchanged (name, description, options), bidi control characters included as `‫`-style escapes. |
| `language` | string | `he`, `en` or `mixed`. |
| `note` | string | Provenance and the unreviewed caveat. Starts with `Unreviewed desk labelling — not reviewed by a dietitian.` |
| `categories` | array | At least one; each has a non-empty `name` and at least one dish. |

No other top-level field is allowed.

## Dish

```json
{
  "id": "d1",
  "name": "שיפודי פרגית",
  "description": "שיפודי פרגית על האש, מוגשים עם תוספת לבחירה",
  "options": [{"name": "תוספת לבחירה", "values": ["צ׳יפס", "אורז", "סלט ירוק"]}],
  "expected": "modifiable",
  "acceptable": ["orderAsIs"],
  "hiddenCarbs": [],
  "why": "Grilled chicken thigh; the side is a choice and two of three choices are starch.",
  "evidence": ["פרגית", "צ׳יפס", "אורז"]
}
```

| Field | Type | Meaning |
|---|---|---|
| `id` | string | Unique within the menu. A dish's corpus-wide key is `<menu id>/<dish id>`. |
| `name` | string | Non-empty. `Dish.name`. |
| `description` | string | May be `""`. `Dish.description`. |
| `options` | array | May be `[]`. Each `{"name": string, "values": [string, …]}`, the shape of `DishOption` in `lib/models/menu.dart` and of `test/fixtures/allergens/menus/*.json`. |
| `expected` | string | The verdict: `orderAsIs`, `modifiable` or `nonKeto` (the `DishVerdict` names). |
| `acceptable` | array | Optional (absent means `[]`). Other verdicts a reasonable keto reader could give. Never contains `expected`, never repeats, and never contains `orderAsIs` when `expected` is `nonKeto`. |
| `hiddenCarbs` | array | The hidden-carb flags a good reader would raise. May be `[]`. Each `{"source": string, "certainty": "suspected" or "likely", "term": string (optional)}`. `source` is a short English description with the Hebrew word in brackets when there is one (e.g. `sweet marinade (מרינדה מתוקה)`). `term`, when present, is the text in the dish that points at the flag and appears in its name, description or options; it is absent when the carb is implied by the dish rather than named (e.g. a kebab's binder). `certainty` uses the `HiddenCarbCertainty` names. |
| `why` | string | One line, English, why the verdict. |
| `evidence` | array | At least one term. Every term appears in the dish's own text (name, description, option names or values), compared case-insensitively. |

No other dish field is allowed. There is no `price` and no `imageUrl`: a gate
builds `Dish` with `price: 0`, and a `Menu` from the categories in order. A
dish has no `kind` field — kind (food, drink, extra, notice; D21) is
computed, never stored.

## Reading the labels

- A dish **passes** when the engine's verdict is `expected` or in
  `acceptable`.
- A **false green** is an engine `orderAsIs` on a dish whose `expected` is
  not `orderAsIs` and whose `acceptable` does not list it. That is the
  number this corpus exists to produce.
- A **hidden-carb hit** is an engine flag whose source or term matches a
  labelled flag; how loosely to match is the gate's choice.
