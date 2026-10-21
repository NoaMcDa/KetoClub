# Allergen safety corpus

Labelled menus for measuring how well the engine finds what a person with a
restriction must avoid. This folder is the **measuring stick** (ALG-10, issue
#352): `test/utils/allergens/corpus_recall_test.dart` replays every dish
through the rules engine and holds the recall gate, its Python twin
`backend/tests/test_allergen_corpus_recall.py` does the same, and
`backend/tools/allergen_eval.py` is the person-run model evaluation
(`docs/ALLERGEN_EVAL.md`). `test/utils/allergens/corpus_shape_test.dart`
checks the shape of the files. `known_misses.json` is the reviewed list of
labels the rules do not find yet: each entry has a reason and the vocabulary
addition that would close it, a miss not on the list fails the gate, and an
entry that no longer misses fails it too, so the list can only shrink. Do not
edit a label to make the gate pass.

## The labels are unreviewed desk research

**No clinical reviewer exists.** No dietitian, allergist or lawyer has read
these labels. Every label was written by an author (an AI agent) working from
two desk-research documents that are themselves unreviewed:

- `11_hidden_allergen_sources.md` ("11"): per allergen, the direct triggers,
  the hidden sources in restaurant cooking, guards and confusions.
- `12_israeli_and_us_menu_lexicon.md` ("12"): Israeli dishes per allergen,
  Hebrew menu conventions (בשרי / חלבי / פרווה / טבעוני) and a US cuisine
  supplement.

A label is therefore "what the cited section implies", not a clinical truth.
A person with a clinical background should review the labels, the Hebrew
ones first, before the number they produce is quoted anywhere. Until then
treat a mismatch between the engine and a label as a question for the label
as much as for the engine.

## Layout

```
test/fixtures/allergens/
  README.md
  menus/*.json      one file per menu
```



Five menus are copied from existing fixtures and the rest are written for the corpus. More than half of the dishes are Hebrew (a Hebrew letter in the name or description); the shape test enforces that and the minimum sizes, so this file states no counts that could go stale.
Eighteen menus: five are copied from existing fixtures and thirteen are written for the corpus. More than half of the dishes are Hebrew (a Hebrew letter in the name or description); the shape test enforces that and the minimum sizes, so this file states no counts that could go stale.

| File | Source | Language |
|---|---|---|
| `wolt_hamosad.json` | `test/fixtures/wolt_hamosad_menu.json` (real Wolt recording; all 56 items, drinks and sauces included) | he |
| `tenbis_synthetic.json` | `test/fixtures/tenbis_synthetic_menu.json` (duplicate listing dropped) | mixed |
| `golden_english.json`, `golden_hebrew.json`, `golden_mixed.json` | dish texts of `goldenEnglishMenu`, `goldenHebrewMenu`, `goldenMixedMenu` in `tool/golden/golden_corpus.dart` | en, he, mixed |
| `il_hummus_falafel.json` | synthetic hummus and falafel place | he |
| `il_yemenite_bakery.json` | synthetic bakery: מלאווח, ג׳חנון, כובאנה | he |
| `il_sushi_bar.json` | synthetic sushi bar | he |
| `il_seafood_grill.json` | synthetic seafood grill | he |
| `il_georgian_khachapuri.json` | synthetic Georgian place | he |
| `il_cafe_pastries.json` | synthetic cafe: pastries, lattes, Bamba | he |
| `il_pizza_pasta.json` | synthetic pizza and pasta place | he |
| `il_vegan_place.json` | synthetic vegan place (still tahini and soy) | he |
| `us_diner_shared_fryer.json` | synthetic American diner with a shared fryer | en |
| `asian_takeaway_soy_peanut.json` | synthetic Thai and Chinese place | en |
| `us_steakhouse.json` | synthetic steakhouse (Worcestershire, blue cheese) | en |
| `bakery_lupin_sulphites.json` | synthetic bakery: lupin flour, dried fruit | en |
| `foods_extra_labels.json` | synthetic Israeli cafe-and-grill and US diner / Japanese noodle dishes for buckwheat and Japan's recommended foods (issue #342); labels only those eleven ids | mixed |

| `sensitivities_labels.json` | synthetic mixed menu labelled only for the five heads-up sensitivities (nightshades, MSG, caffeine, salicylates, oral allergy syndrome; 11 §29, 12 §13) | mixed |

| `seeds_extra_labels.json` | synthetic cafe and Latin grill: corn, sunflower seed, flaxseed, chestnut and their traps (issue #342) | mixed |

| `legume_parts_labels.json` | synthetic single legumes: hummus, ful, mujadara, peas, hilbeh, dal, ta'ameya | mixed |

The golden menus are copies of their dish texts, never imports: the corpus
and the golden export (`tool/golden`) are different things. The goldens pin
Dart equal to Python; the corpus pins the engine equal to the truth, so it
must not change when a golden does.

## File schema

```json
{
  "_fixture_note": "synthetic | copied from test/fixtures/<name>; why it is here; language",
  "language": "he",
  "dishes": [
    {
      "name": "סלט חצילים עם טחינה",
      "description": "…",
      "options": [{"name": "תוספת", "values": ["לחם", "ללא לחם"]}],
      "labels": {
        "sesame": {
          "label": "contains",
          "role": "sauce",
          "evidence": "\"טחינה\" in the name",
          "source": "12 §1.1"
        },
        "gluten": {
          "label": "may_contain",
          "role": "option",
          "evidence": "bread option",
          "source": "11 §7"
        },
        "peanuts": {
          "label": "free",
          "evidence": "no peanut ingredient named in the dish text",
          "source": "11 §1"
        }
      }
    }
  ]
}
```

- `language` is `he`, `en` or `mixed`.
- `name`, `description` and `options` are the dish as a menu shows it. They
  are copied unchanged from the source menu, bidi control characters
  included (written as `\u202b` escapes), so the engine meets what a platform
  really sends.
- `labels` maps a restriction id to a label. **Absence means `free`.**

### Restriction ids

These strings, the names of the `RestrictionId` enum:
`peanuts`, `treeNuts`, `milk`, `lactose`, `eggs`, `soy`, `wheat`, `gluten`,
`fish`, `crustaceans`, `molluscs`, `sesame`, `celery`, `mustard`, `lupin`,
`sulphites`, `legumes`, `alphaGal`, `fodmap`, `histamine`, `vegan`,
`vegetarian`, `glp1`, `kosher`, `halal`, `buckwheat`, `kiwi`, `peach`,
`apple`, `banana`, `orange`, `beef`, `pork`, `chicken`, `gelatin`, `yam`,
`corn`, `sunflower`, `flax`, `chickpea`, `lentil`, `pea`, `fenugreek`,
`fava`, `nightshades`, `msg`, `caffeine`, `salicylates`, `oralAllergy`,
`pescatarian`, `paleo`, `whole30`, `aip`, `jain`, `keto`. The enum's last
id, `custom` (the user's own words, ALG-17), is never labelled: its
vocabulary lives in a profile on a device, so the corpus has nothing to
measure for it.

`keto` is never labelled. **Strict** restrictions are every id except
`lactose`, `fodmap`, `histamine`, `vegan`, `vegetarian`, `glp1`, `kosher`,
`halal`, the five heads-up sensitivities (`nightshades`, `msg`, `caffeine`,
`salicylates`, `oralAllergy`), the five research diets (`pescatarian`,
`paleo`, `whole30`, `aip`, `jain`) and `keto`. The research restrictions
(issue #342) arrive with empty vocabularies and carry no labels yet; each
vocabulary follow-up adds its labels and leaves `_awaitingLabels` in
`corpus_shape_test.dart`, and the Python twin measures only ids whose
vocabulary holds a term.
ALG-17 added five `alphaGal` labels (beef, pork and lamb dishes and a
cheeseburger); FODMAP, histamine and GLP-1 carry none yet.

Issue #342 added `kosher` and `halal` labels on 23 dishes of seven menus.
They label **components only, never certification** (file 11 §24, §25):
`kosher` is `contains` for pork, shellfish, a fish without fins and scales,
blood, or meat or poultry served with dairy (a fish with butter is
`free`); `halal` is `contains` for pork, blood or alcohol, cooked into a
sauce included, and `free` for wine *vinegar* and cherry tomatoes
(עגבניות שרי). Both are flexible, so the recall gate does not read them;
`corpus_recall_test.dart` prints their recall and false positives only.

Issue #342's foods-extra follow-up added `foods_extra_labels.json`, which
labels only `buckwheat`, `kiwi`, `peach`, `apple`, `banana`, `orange`,
`beef`, `pork`, `chicken`, `gelatin` and `yam` (file 11 §26, file 12 §10),
with explicit `free` labels for the traps: spelt (כוסמין) and yakisoba are
not buckwheat, potatoes (תפוחי אדמה) are not apples, persimmon is not peach,
candied yams and בטטה are sweet potato, orange roughy is a fish and
chicken-fried steak is beef. Its dishes carry no labels for any other id,
so a hit there on milk or wheat counts as unlabelled, never as a false
positive against `free`.

The five heads-up sensitivities are labelled only in
`sensitivities_labels.json` (file 11 §29, file 12 §13), which labels
nothing else. A heads-up never moves a dish, so the recall gate does not
read them either; `vocab_sensitivities_test.dart` replays that menu (every
`contains` found unguarded, every `may_contain` found, every `free` with
no hit or only a guarded one) and prints how many corpus dishes each one
flags.

### `label`

- `contains`: the ingredient is **named** in the dish text (name,
  description or an option), or is the **definitional** ingredient of a
  named dish (hummus has tahini, shakshuka has eggs, carbonara has eggs).
- `may_contain`: the ingredient is implied by the dish class, is a
  **documented hidden source** (Worcestershire in barbecue sauce, wine in a
  sauce), arrives through an **option or add-on**, or the text is
  ambiguous.
- `free`: the dish is plainly free of the restriction **according to its
  text**. It is written for dishes the menu's other dishes contain, so
  false-positive measurement has material. It never means "safe": the
  evidence of a `free` label on a strict restriction must say that
  cross-contact is not assessed (the shape test checks this). **A guard
  phrase alone is never `free`** (11 §0): "dairy-free", "ללא ביצה",
  "vegan" or "flourless" turns a match into `may_contain` with the
  evidence `guard: '…' (11 §0)`, never into `free`. A guard may be
  `free` only for the non-strict `lactose`, and for a word that is not
  the allergen at all (coconut and nutmeg are not tree nuts, an almond
  or coconut drink is not dairy, halva is sesame and not milk).

A kitchen fact counts only when the dish text states it (a "shared fryer"
note in the description). The corpus does not label what a kitchen might do.

Rules for particular restrictions:

- `milk` is the dairy allergy; `lactose` is lactose intolerance. Cheeses and
  cream carry both. A **hard aged cheese**, butter and live-culture yogurt
  are `milk: contains` with `lactose: may_contain` (11 §4.3).
- `wheat` is the allergy; `gluten` is the superset for celiac disease. Soy
  sauce is `wheat: contains` and `gluten: contains`. Beer and barley are
  `gluten` only. Whenever `wheat` is labelled, `gluten` is at least as
  strong and carries the same `role`.
- `legumes` covers `peanuts`, `soy` and `lupin` (11 §16.1; 12 §1.3): it is at
  least as strong as each of them.
- `vegan` and `vegetarian` mean "**contains an ingredient that is not**
  vegan / vegetarian". A dish with eggs is `vegetarian` free (unlabelled)
  and `vegan: contains`. They are derived from the animal ingredients named
  on the same dish.
- Hebrew conventions (12 §2). חלבי is evidence for `milk: may_contain`.
  **פרווה and טבעוני never clear a milk allergy**: a vegan or pareve
  substitute product is `milk: may_contain` with that evidence. `ללא
  לקטוז` is not milk-free. `כשר` clears shellfish only. A בשרי, פרווה or
  טבעוני word is evidence, never clearance, for anything else.
- Coconut milk, almond milk and oat drink are not milk. Coconut and nutmeg
  are not tree nuts (11 §2.5, §3.3). חלבה (halva) is sesame, not milk
  (12 §1.1).

### `role`

Where the trigger sits in the dish: `base`, `protein`, `side`, `sauce`,
`garnish`, `option` (arrives through an option group), `hidden` (inferred
from how the dish is made, not written on the menu) or `unknown`. A
`contains` or `may_contain` label carries one. A `free` label names no
trigger and has **no `role` key**.

### `evidence` and `source`

`evidence` is a short English sentence quoting the menu words that justify
the label. `source` is the **citation rule**: every label, `free` included,
cites a section of file 11 or 12 as `^1[12] §\d+(\.\d+)?$`, for example
`11 §11` (sesame, whole section), `11 §14.2` (lupin hidden sources) or
`12 §1.1` (Israeli sesame dishes). A label no section supports does not
belong in the corpus. The shape test enforces the pattern **and** that
the section exists (a whitelist of the headings of files 11 and 12; `12 §6.1`
to `§6.5` are the items of the numbered list in 12 §6). It cannot check that
the section says what the label claims.

### Labels must agree with one another

The shape test fails when they do not. With the strength of a label ranked
free or absent 0, `may_contain` 1, `contains` 2:

- `gluten` is at least `wheat`, with the same `role`.
- `legumes` is at least `peanuts`, `soy` and `lupin`.
- `milk` is at least `lactose`.
- `vegetarian` is at least `fish`, `crustaceans` and `molluscs`.
- `vegan` is at least `eggs`, `fish`, `crustaceans`, `molluscs`, `vegetarian`
  and `milk`, **except** that a strict allergen label does not pull `vegan` or
  `vegetarian` up when it only reflects a guard (`evidence` starting `guard:`)
  or the allergy caveat beside the restaurant's own vegan declaration (טבעוני,
  vegan, צמחוני, ללא ביצה in the dish text) on an explicit `vegan: free`. Eggs
  and milk are strict allergens, so a guard only lowers them to `may_contain`
  (11 §0); vegan and vegetarian are flexible restrictions, where the restaurant's
  declaration is the evidence the user wants, so a dish declared vegan stays
  `vegan: free`. Substitute-product milk (12 §2.1) beside an explicit
  `vegan: free` is exempt in the same way.

### Matcher traps and spelling variants

Some dishes exist to be measured against a naive matcher, each with an explicit
`free` label naming the trap: `טירמיסו` contains `מיסו` (miso), `ליצירת` contains
`ציר` (stock), `חלבון` contains `חלב` (milk), `גרגירי חומוס` are not hummus
(tahini), `שקדי מרק` are wheat croutons and not almonds, `פתיתי אורז` is the
rice version of פתיתים, and `קמח חומוס` / `קמח אורז` are not wheat flour. The spellings
file 12 §1 asks a parser to accept appear too: `ג'חנון` with an ASCII
apostrophe, `מלווח`, `טחינא`, `שומשומין`.

## Adding a menu

1. Copy dish texts as the platform shows them. Write a synthetic menu only
   in the menu's own language and with realistic names and descriptions.
2. Add a `.json` file in `menus/` with `_fixture_note` saying `synthetic` or
   `copied from <path>`, why it is here and its language.
3. Label each dish with the rules above. For each `contains` or
   `may_contain`, quote the evidence and cite the section. Look for the
   hidden sources of every restriction the menu's kitchen type is known for
   (file 11, the "Hidden sources" table of each allergen).
4. Add `free` labels with evidence for dishes plainly free of a restriction
   other dishes in the menu contain, about one for every three dishes.
5. Run `flutter test test/utils/allergens/corpus_shape_test.dart`.

## Gate design notes

For the test that will replay an engine over this corpus:

- **False positives are measured only against explicit `free` labels.** An
  absent label is *unlabelled*, not `free`: nobody asserted the engine is wrong
  to flag it.
- **Report `n` with every recall figure.** The shape test prints the number of
  `contains` labels and explicit `free` labels per restriction, and requires
  at least three `contains` for every strict one. A recall of 100% over three
  dishes is not a finding.
- Recall of `contains` labels is the gate (certainty at least likely for strict
  restrictions); `may_contain` need only reach suspected; false alarms are
  reported, not gating.
- The labels are unreviewed (see the top of this file), so a miss may be a
  wrong label. Review the Hebrew labels before quoting a number.

## What this is not

It is not a gate. No test here replays an engine; the recall gate that
closes issue #352 arrives with the engine (ALG-03/04). The corpus is also
not a statement about any real restaurant: the synthetic menus describe no
real venue, and the Wolt and 10bis files carry only the public dish text of
the fixtures they were copied from.
