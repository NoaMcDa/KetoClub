# Keto ground-truth corpus

Israeli restaurant menus whose every dish carries the verdict a careful keto
reader would give it (`orderAsIs`, `modifiable`, `nonKeto`) and the hidden
carbs it likely hides. Until this folder existed every keto fixture was a
snapshot of the engine's own output, so no false-green rate could be
measured (`m16_menu_scanner_research.md` §10, "the wrong green"). This
folder is the measuring stick; the gates that replay it against the rule
engine and the model live elsewhere. The file shape is in `SCHEMA.md` and
`test/utils/keto/keto_corpus_shape_test.dart` enforces it, together with
the minimum sizes and the Hebrew share, so this file states no counts that
could go stale.

## Unreviewed desk labelling — not reviewed by a dietitian.

**No dietitian, nutritionist or clinician has read these labels.** Every
label was written by an author (an AI agent) from the app's own keto rules
(below) and general knowledge of Israeli restaurant cooking. A label is "what
a careful keto reader following those rules would say", not a measured carb
count. A person with a nutrition background should review the labels, the
`acceptable` lists and the hidden carbs first, before any number this corpus
produces is quoted anywhere. Until then treat a mismatch between the engine
and a label as a question for the label as much as for the engine. Every
file repeats the caveat at the start of its `note`.

## Labelling rules

The rules are the app's: `architecture.md` §6.2 and the verdict definitions
and keto rules the system prompt sends (`promptVerdictDefinitionsTemplate`,
`promptKetoRulesTemplate` in `lib/utils/constants.dart`), at the default
**6 g net-carb** limit.

- **`orderAsIs`** — protein, fat and low-carb vegetables with nothing carb on
  the plate: order it exactly as printed.
- **`modifiable`** — a keto core (protein, fish, egg, salad) arriving with a
  carb the waiter can remove or swap: a starchy side (fries, mash, rice), a
  bun, pita, laffa or toast that only carries the dish, a root vegetable
  (carrot, beet, potato in a soup), a sugary sauce, glaze or dressing.
- **`nonKeto`** — the dish *is* the carb: pasta, pizza, rice dishes, noodles,
  bread and pastry dishes (malawach, jachnun, burekas, khachapuri), legume
  mains (hummus, falafel, majadra, lentil stews), potato dishes, desserts,
  sweet drinks, and — the app's rule — breaded or battered proteins
  (schnitzel, nuggets, crispy chicken, tempura, fish and chips).
- **Drinks** — water, soda water, black coffee, espresso, tea, diet and zero
  sodas and spirits are `orderAsIs`; a latte, cappuccino or iced coffee with
  milk is `modifiable` (ask for less milk or unsweetened almond milk), tonic
  is `modifiable` (ask for soda water); juices, soft drinks, lemonade, beer,
  malt beer, sake and sweet or dessert wine are `nonKeto`. A dry or unnamed
  wine is `orderAsIs` with `nonKeto` acceptable.
- **A carb only in the options.** When a required choice ("תוספת לבחירה")
  offers both a carb and a keto value, the dish is `modifiable` (the order
  must name the keto value) with `orderAsIs` acceptable. A removal option
  ("ללא לחם", "ללא מיונז") is never read as an ingredient, and a paid add-on
  the diner does not have to take does not change the verdict.
- **A carb only in the description** ("מוגש עם פיתה", "על מצע אורז") counts
  exactly as one in the name.
- **A keto substitute is not the carb it replaces.** Cauliflower rice
  (`אורז כרובית`), cauliflower purée (`פירה כרובית`), zucchini noodles
  (`אטריות קישואים`), a lettuce-wrapped burger and a stevia cheesecake on an
  almond base are `orderAsIs` even though the text says rice, purée,
  noodles, burger or cake.
- **The base cannot be removed.** Leaving the bread out of hummus does not
  make hummus keto; leaving the toppings off malawach does not either.
- **Hidden carbs** (`hiddenCarbs`) are carbs the dish text does not name as
  carbs: a breading or crispy coating not called breading ("קריספי", nuggets),
  sweet marinades (`מרינדה מתוקה`, teriyaki, honey), house sauces and
  dressings (`רוטב הבית`, `ויניגרט הבית`), glazes (`מזוגג`, `בזיגוג`, glaze),
  thickened sauces (cornstarch in wok and oyster sauces, flour in `רוטב חום`
  and bisques), `סילאן` (date syrup), `עמבה` (amba, usually sugared),
  ketchup-based sauces (Thousand Island, the sauce kit), sweet chili, jams on
  burgers, sugared Israeli salads (cabbage, carrot, matbucha), bread or
  breadcrumb binders in kebab, meatballs, fish patties and kotleti, and
  flavoured or "no added sugar" products. **`likely`** when the carb is the
  usual recipe; **`suspected`** when it is only possible. `term` names the
  text in the dish that points at the flag; it is absent when the carb is
  implied by the dish itself (a kebab's binder).
- **How a hidden carb moves the verdict.** A `likely` hidden carb in a part
  the waiter can leave out or be asked about makes an otherwise-clean dish
  `modifiable` (the order is "without the sauce", "ask how it is
  thickened"), with `orderAsIs` acceptable when the amount is small. A
  `suspected` one leaves the dish `orderAsIs` with `modifiable` acceptable.
- **`acceptable`** lists the other verdicts a reasonable keto reader could
  give: a grilled steak with a house sauce (`modifiable`, `orderAsIs`
  acceptable), a burger whose bun is the bulk of the plate (`modifiable`,
  `nonKeto` acceptable). `orderAsIs` is never acceptable for a dish whose
  base is starch.
- **`why`** is one English line; **`evidence`** lists the words of the dish
  text that decide the verdict, each of which appears in the dish's own
  name, description or options.

## Layout

```
test/fixtures/keto/
  README.md
  SCHEMA.md
  menus/*.json      one file per menu
```

Ten menus copy their dish texts unchanged (name, description and options,
bidi control characters included as `‫`-style escapes) from the
allergen corpus, never by import: the allergen labels and the keto labels
are different measuring sticks, and the shape test checks each copy still
matches its source. A copied dish's id is its position in the source file
(`d1` is the first dish); the categories were added for this corpus. The
other fourteen menus are synthetic Israeli venues written for it.

| File | Source | Venue |
|---|---|---|
| `il_seed_grill.json` | synthetic | neighbourhood grill, shawarma and skewers (`מסעדת בשרים`); the contract seed |
| `wolt_hamosad.json` | `allergens/menus/wolt_hamosad.json` (real Wolt recording of a Tel Aviv burger bar) | burger bar; 55 of 56 items, the "💙" notice is left out because it is not a dish |
| `golden_hebrew.json` | `allergens/menus/golden_hebrew.json` (the golden Hebrew menu's texts: nikud, maqaf, geresh) | mixed grill |
| `il_cafe_pastries.json` | `allergens/menus/il_cafe_pastries.json` | bakery and café |
| `il_georgian_khachapuri.json` | `allergens/menus/il_georgian_khachapuri.json` | Georgian (khachapuri) |
| `il_hummus_falafel.json` | `allergens/menus/il_hummus_falafel.json` | hummusia and falafel |
| `il_pizza_pasta.json` | `allergens/menus/il_pizza_pasta.json` | pizza and pasta |
| `il_seafood_grill.json` | `allergens/menus/il_seafood_grill.json` | seafood grill (Jaffa) |
| `il_sushi_bar.json` | `allergens/menus/il_sushi_bar.json` | sushi bar |
| `il_vegan_place.json` | `allergens/menus/il_vegan_place.json` | vegan place |
| `il_yemenite_bakery.json` | `allergens/menus/il_yemenite_bakery.json` | Yemenite (jachnun, malawach, kubaneh) |
| `il_breakfast_cafe.json` | synthetic | Israeli breakfast café (`ארוחת בוקר ישראלית`, shakshuka) |
| `il_mizrahi_home.json` | synthetic | Mizrahi home food (`אוכל ביתי`, kubbeh, majadra, pashtida) |
| `il_asian_wok.json` | synthetic | Asian wok chain (oyster, teriyaki and kung pao sauces, cauliflower rice, zucchini noodles) |
| `il_salad_bar.json` | synthetic | salad bar with a build-your-own bowl (carbs only in the options) |
| `il_steakhouse.json` | synthetic | steakhouse (side choice, BBQ glaze, brown gravy) |
| `il_ethiopian.json` | synthetic | Ethiopian (wat on injera, shiro, kitfo) |
| `il_russian_deli.json` | synthetic | Russian deli (pelmeni, herring, kotleti, kvass) |
| `il_dairy_cafe.json` | synthetic | kosher dairy café (`חלבי`) |
| `il_street_food.json` | synthetic | street food (sabich, falafel, shawarma, mixed grill) |
| `il_fine_dining.json` | synthetic | Tel Aviv tasting menu; English dish names, Hebrew descriptions (`mixed`) |
| `il_iraqi.json` | synthetic | Iraqi (amba, tbit, masgouf) |
| `il_moroccan.json` | synthetic | Moroccan (`חריימה`, couscous, tagine) |
| `il_juice_bar.json` | synthetic | juice and smoothie bar (drinks only) |
