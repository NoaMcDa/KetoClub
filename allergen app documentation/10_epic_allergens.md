# 10 — Epic: Allergens

**One epic, one milestone: turn KetoClub's keto-only engine into a
profile-driven engine for every dietary restriction, without losing a
single keto behaviour and without ever telling an anaphylactic user a dish
is "safe".**

Each feature below is written to become one GitHub issue under
`ISSUE_CONVENTIONS.md` (`[feature] …`, description, context, acceptance
criteria, unit and flow tests, related issues). Feature ids are `ALG-nn`;
they are stable references inside this folder, not issue numbers. Sizes
are S (days), M (one to two weeks), L (several weeks) for one engineer.

## GitHub issues (created 2026-10-11)

Parent epic: **#342**. No milestone yet — `Phase 9: Allergens` must be
created by hand (the session had no token for milestone creation) and the
19 issues assigned to it.

| Feature | Issue | Feature | Issue |
|---|---|---|---|
| ALG-01 taxonomy and vocabulary | #343 | ALG-10 safety corpus and gate | #352 |
| ALG-02 dietary profile | #344 | ALG-11 privacy and consent | #353 |
| ALG-03 prompt, schema v2, evaluator | #345 | ALG-12 group profiles | #354 |
| ALG-04 rules pass and veto | #346 | ALG-13 trip mode | #355 |
| ALG-05 four-state UI | #347 | ALG-14 confirmations | #356 |
| ALG-06 evidence tiers | #348 | ALG-15 delivery note | #357 |
| ALG-07 kitchen signals | #349 | ALG-16 allergen matrices | #358 |
| ALG-08 chef card | #350 | ALG-17 extended restrictions | #359 |
| ALG-09 platform tags | #351 | ALG-18 premium gating | #360 |

## Goal

A user enters every restriction they live with — allergies, celiac,
lactose, vegan, keto, and later FODMAP, GLP-1 and others — once, with a
severity for each. From then on every menu KetoClub can read (Wolt, 10bis,
paste, photo, PDF, website, QR) is analysed against that whole profile in
one request, and each dish answers four questions: *can I order it as is,
can I order it with a change, what must I ask the kitchen, or should I
avoid it* — with the evidence, in the menu's language, and with a card to
hand to the waiter.

## Non-goals (this epic)

- Medical diets that need nutrient numbers (kidney, PKU, gout) — no
  restaurant supplies the data; a clinical partner is a precondition.
- Kosher or halal *certification* — only ingredient components are
  flagged ("contains pork", "meat with dairy").
- Restaurant ratings or reviews of any kind — the research's complaints 1
  and 5 are about exactly that; verification here is per dish and per
  visit (ALG-14), never a star.
- Renaming the product. Branding is tracked outside the epic (file 09,
  D-a).
- An account system. Everything personal stays on the device, as today.

## Principles every feature obeys

1. **A keto-only profile is today's app, byte for byte.** Prompt text,
   cache keys, goldens, score and copy are unchanged when the profile holds
   only keto and its three toggles. A regression suite proves it.
2. **The model proposes, the rules dispose for level A and B.** The LLM
   extracts; a deterministic layer can add a concern or block a verdict,
   never remove one.
3. **No "safe" for level A.** The strongest wording a level-A restriction
   ever gets is "no trigger found in the menu text — confirm with staff".
4. **Every concern names its evidence.** Declared by the platform, stated
   in the menu text, inferred from a dish name, or suspected hidden — the
   tier is shown, not just the colour.
5. **One request per menu, as today.** The profile never multiplies
   requests; the rate limits and quotas stay what they are.
6. **Health data stays on the device.** What leaves it is the constraint
   list the analysis needs, under the existing AI consent, with explicit
   wording.
7. **Dart is the source of truth; Python is pinned to it by goldens.**
   Every vocabulary, prompt or parser change in this epic regenerates the
   goldens and replays `backend/check.sh`, exactly as D25 requires.

## Phases and features

| Phase | Features | Outcome |
|---|---|---|
| **P0 Foundations** | ALG-01 taxonomy and vocabulary · ALG-02 dietary profile · ALG-11 privacy and consent · ALG-10 safety corpus and gate | The data, the profile, the consent and the measuring stick exist; nothing user-visible changes yet except Settings |
| **P1 Core engine** | ALG-03 profile-driven prompt and concerns schema · ALG-04 allergen rules engine and veto · ALG-05 four-state verdict UI · ALG-06 evidence tiers and explained confidence | A combined profile gets a per-dish answer on every menu source, with the safety net live |
| **P2 At the table** | ALG-08 waiter questions and dynamic chef card · ALG-07 cross-contact signals · ALG-09 platform-declared tags · ALG-15 delivery note helper | The user can act on the answer in the restaurant and on a delivery app |
| **P3 People and places** | ALG-12 group profiles · ALG-13 trip mode · ALG-14 post-meal confirmation | The product becomes a habit: family meals, travel, and a verified history |
| **P4 Breadth and business** | ALG-17 extended restrictions · ALG-16 allergen-matrix intake · ALG-18 premium gating | More people served; verified data; a revenue line |

Dependencies are stated per feature. P0 is strictly first; inside P1 the
order is 01 → 03 → 04 → 05 → 06; P2–P4 features are mostly independent of
each other.

---

## ALG-01 — Restriction taxonomy and bilingual allergen vocabulary

**Size:** L · **Phase:** P0 · **Depends on:** nothing · **Blocks:** everything

### Problem
The engine's only vocabulary is keto's (bases, carb modifiers, guards,
three toggle vocabularies). Nothing in the code can say "this dish contains
sesame". Every other feature reads from the taxonomy this one creates, and
every entry in it is a safety claim.

### What it is
Two artefacts, both in `constants.dart` and mirrored into
`vocabulary.json` for the Python port:

1. **The restriction taxonomy** — the closed list of things a user can put
   in a profile. One `Restriction` per entry with: a stable id (`sesame`,
   `gluten`, `lactose`, `vegan`, `keto` …), a `kind` (`allergen`,
   `intolerance`, `autoimmune`, `lifestyle`, `religiousComponent`, `keto`),
   the jurisdictions where it is regulated (file 02: `us`, `eu`, `uk`, `ca`,
   `anz`, `jp`, `il`), the allowed severities (an allergen allows A–D,
   lactose allows C–D, vegan allows D only), bilingual display names, and
   the *default* severity shown in onboarding. First release: the EU 14 +
   US 9 union (16 ids: peanuts, tree nuts, milk, eggs, soy, wheat/gluten
   cereals, fish, crustaceans, molluscs, sesame, celery, mustard, lupin,
   sulphites, plus gluten split from wheat for celiac), `lactose` (distinct
   from `milk`), `vegan`, `vegetarian`, and `keto` with its three existing
   toggles folded in as sub-options.
2. **The trigger vocabulary** — for each restriction, bilingual trigger
   lists in the exact shape the keto vocabulary already uses, so
   `ClassificationRules` compiles them with the same `hebrewTriggerPattern`
   / `latinTriggerPattern`: direct triggers ("sesame", "tahini", "שומשום",
   "טחינה", "חלבה"), **hidden-source triggers** with a certainty (soy
   sauce → wheat *likely*; Worcestershire → fish *likely*; pesto → tree nuts
   *likely* and dairy *likely*; "vegetable stock" → celery *suspected*;
   wine/vinegar → sulphites *suspected*; breaded/crumbed → wheat *likely*;
   "marinated" → soy *suspected*), **guards** that cancel a trigger
   ("sesame-free", "ללא גלוטן", "gluten-free bun", "oat milk" cancels milk),
   and **removal phrases** reused from #192 so "no cheese" is not a dairy
   hit. Each entry carries a `source` note (regulatory list, published
   hidden-allergen guidance, or the reviewer's name) in a comment.

### Design notes
- Hebrew first, written from Israeli menus, not translated: שומשום on
  בורקס and ג'חנון, טחינה in half the salads, פול in פלאפל mixes, חומוס
  as a legume, קמח in every "קציצה", אגוזים vs בוטנים (tree nuts vs
  peanuts are *different* restrictions and Hebrew menus say "אגוזים" for
  both — model it as tree nuts *likely* + peanuts *suspected*).
- Options are read (#191/#192): "בחירת לחם" is a gluten hit on the option
  values, "add feta" a dairy hit; a removal option is dropped.
- `lactose` and `milk` are two restrictions that share most triggers but
  not guards: lactose-free milk cancels lactose, not milk allergy. Hard
  cheese is a lactose *suspected*, a milk *likely*.
- Nothing here changes behaviour yet: the vocabulary is compiled and
  tested but only ALG-04 consults it.

### Tests and gate
- Table-driven unit tests per restriction, English and Hebrew, including
  the Hebrew prefix forms (בטחינה, והשומשום) and the no-prefix idiom
  collisions the keto vocabulary already documents.
- The golden corpus gains an allergen section (ALG-10) and the Python port
  replays it; `vocabulary.json` byte-equality test extended.
- A reviewer sign-off checklist in the PR template for any vocabulary
  change (file 09, D-f).

### Acceptance criteria
- [ ] `Restriction` model and the first-release taxonomy exist, with ids
      pinned by a test (no renames without a migration).
- [ ] Trigger, hidden-source, guard and removal vocabularies exist for every
      first-release restriction in both languages, each entry with a source.
- [ ] `vocabulary.json` regenerated; `backend/check.sh` green.
- [ ] No change to any keto golden.

---

## ALG-02 — Dietary profile with severity levels

**Size:** M · **Phase:** P0 · **Depends on:** ALG-01 · **Blocks:** ALG-03, ALG-05, ALG-11

### Problem
Settings has three keto booleans and a net-carb slider. There is no way to
say "peanuts, anaphylactic; lactose, intolerant; vegetarian".

### What it is
A `DietaryProfile` value in `AppSettings`: an ordered set of
`ProfileEntry {restrictionId, severity, exceptions}` where severity is one
of **A** (anaphylaxis / life-threatening), **B** (autoimmune or
trace-sensitive, e.g. celiac), **C** (intolerance / discomfort), **D**
(preference / lifestyle), and `exceptions` is a small list of tolerated
forms ("baked milk", "cooked tomato") shown to the model as text. Keto and
its three toggles and the net-carb limit become one entry of kind `keto`
with severity D, so the profile is the single source of what the engine is
asked for.

`ClassificationOptions.fromSettings` now builds `dietaryConstraints` from
the profile: one canonical sentence per entry, in a fixed order (by
taxonomy order, then severity), so the same profile always yields the same
prompt and the same cache key. The keto entry yields exactly the three
existing fragments when its toggles are on, so a keto-only profile is
byte-identical to today's prompt (principle 1).

### UX
- **Settings → "My restrictions"** replaces "Your keto rules": a list of
  entries, each a row with the restriction name, a severity segmented
  control labelled in plain words (not letters): *Life-threatening ·
  Must avoid · Makes me unwell · Prefer to avoid*, and an optional
  "exceptions" field. An "Add restriction" sheet lists the taxonomy grouped
  by kind, with a search field, Hebrew and English names, and the
  jurisdiction hint ("regulated in Israel from 2028").
- **First-run onboarding** (new, skippable): "What do you avoid?" — chips
  for the first-release taxonomy; tapping one asks the severity with a
  one-line explanation of each level and what the app will and will not
  say at that level. Keto users who already have settings see nothing new
  until they open Settings.
- Severity A entries show a persistent one-line notice under the row:
  "KetoClub reads menu text. It cannot see the kitchen. Always confirm
  with the staff."
- The profile summary ("Peanuts · Lactose · Vegetarian · Keto") appears in
  the menu screen's Filters row so the user always sees what a verdict was
  computed against.

### Data and storage
- `shared_preferences` under one JSON key, read tolerantly (unknown ids
  dropped, unknown severity → D, missing → empty profile). The three old
  boolean keys and the limit are migrated into the keto entry on first
  read and then left in place for one release.
- The analysis cache's `AnalysisOptionsSnapshot` already records the
  constraint list; nothing else to persist. The profile never enters the
  Hive cache, the visit history or `stored_menus`.

### Tests
- `AppSettings` round-trip, migration from the old keys, canonical
  ordering, keto-only byte-equality against a pinned prompt fixture.
- Widget tests for the Settings list and the add sheet in both locales and
  RTL; a flow test "add peanuts (A) → open menu → Filters row shows it".

### Acceptance criteria
- [ ] Profile model, storage, migration and canonical constraint building.
- [ ] Settings and onboarding screens, English and Hebrew, RTL verified.
- [ ] `test/golden` unchanged for the keto-only profile.
- [ ] Severity levels documented in `architecture.md` §7 and a new decision
      record (D26) recorded in §14.

---

## ALG-03 — Profile-driven prompt and the `concerns` reply schema

**Size:** L · **Phase:** P1 · **Depends on:** ALG-01, ALG-02 · **Blocks:** ALG-04, ALG-05, ALG-06

### Problem
The system prompt is "the keto-diet menu analyst"; the verdict definitions
and the rules are keto text; the reply schema has `hidden_carbs`. A
non-keto profile cannot be asked for.

### The architectural choice
Two ways to ask the model, and the epic recommends **B**:

- **A — Judge.** Send the profile as constraints (as today) and ask the
  model for the verdict directly. Simple, but each profile is its own
  request and cache key, the model's judgement is opaque, and the rules
  engine can only act as a fallback.
- **B — Extract, then evaluate.** Ask the model, once per menu and
  *independently of the profile*, to extract for every dish: the
  ingredient list it can read or infer (each with a certainty: `stated`,
  `likely`, `suspected`), the dish's components by role (base, protein,
  side, sauce, garnish, option), the cooking method (fried, grilled, raw,
  baked), and any portion or protein hint. Then evaluate the profile
  against that extraction **deterministically**, on the device (or on the
  server for the D25 routes), using the ALG-01 vocabulary and a small
  evaluator: for each entry in the profile, scan the extracted
  ingredients for triggers, apply guards, and produce the dish's concerns
  and verdict. The keto verdict keeps using the model's keto judgement
  (today's prompt section) so keto behaviour is untouched.

  Why B: one extraction serves every profile, so the analysis cache and
  the shared store become useful again; the verdict is reproducible and
  testable without a model; the rules layer is the authority for level A
  by construction, not by a post-hoc veto; and "why" can cite the exact
  extracted ingredient. Cost: the extraction reply is larger (an
  ingredient list per dish), and the evaluator is new code in Dart *and*
  Python.

### What it is
- **Prompt.** The system prompt gains a profile-independent *extraction*
  section after the keto section: "For every dish also list `ingredients`
  … with `certainty` …". The keto sections stay byte-identical. The
  per-profile `dietaryConstraints` list continues to be sent for the keto
  toggles only; allergen entries do **not** go into the prompt in option B
  (they are evaluated locally), which also shrinks what leaves the device
  (ALG-11). *Exception:* `exceptions` text and the free-text restrictions
  of ALG-17 are sent, because they need the model.
- **Schema.** `AnalysedDish` gains `ingredients: List<ExtractedIngredient
  {name, certainty, role}>` and `concerns: List<Concern {restrictionId,
  source, certainty, waiterQuestion}>`. `hiddenCarbs` is kept on the wire
  for compatibility and mirrored as concerns with `restrictionId: keto`.
  `schemaVersion` 1 → 2, once, for this and every other field the epic
  adds (ALG-06's evidence tier, ALG-07's kitchen signals). The vision
  schema gains the same fields plus a transcribed `description`, because a
  scanned menu's allergens live in the description the current vision
  prompt does not ask for (file 09 §5).
- **Parser.** `MenuResponseParser` gains rules in the §9.4 spirit: an
  ingredient the dish text cannot support is kept but capped at
  `suspected`; an empty `ingredients` list on a dish with a description
  is a `badResponse` for that dish only (it falls to the rules engine); a
  concern whose `restrictionId` is not in the taxonomy is dropped.
- **Evaluator.** `ProfileEvaluator.evaluate(dish, extraction, profile)` —
  pure, static, in `lib/utils/` beside `classification_rules.dart`, ported
  to `backend/app/keto/`. Output per dish: concerns, a verdict, and a
  `modification` when a concern sits on a removable role (side, sauce,
  garnish, option) — "ask for it without the tahini" — written from the
  bilingual sentence templates like the keto rules' (§6.3).
- **Verdict mapping** (three wire verdicts kept):
  - any concern with certainty `stated`/`likely` on a non-removable role
    → `nonKeto` (wire name; UI says "avoid");
  - concerns only on removable roles → `modifiable` with the sentence;
  - no concern → `orderAsIs`;
  - the "ask" state is **derived** in the UI (ALG-05): any `suspected`
    concern on a level-A or level-B entry, whatever the verdict.
- **Backend.** `/v1/classify`, `/v1/venue-menus`, `/v1/scan`,
  `/v1/website-menu` and `/v1/text-menu` accept the profile in `options`
  (ids and severities only), run the same extraction prompt, and evaluate
  with the Python evaluator so the client gets a complete result as D25
  promises. The analysis cache key gains the profile *only through* the
  keto constraints and exceptions text — the extraction itself is cached
  per menu, model and schema version, which is the point of option B.

### Failure modes
- Model answers but extraction is missing for some dishes → those dishes
  get rules-only concerns (ALG-04) and an `inferred` evidence tier.
- Model cannot answer at all → the whole analysis is rules-only as today,
  stamped `rules(reason)`; the UI's existing "rules" chip plus ALG-05's
  severity wording cover it.
- The user changes the profile → re-evaluate locally from the cached
  extraction without a new request (the big win of option B).

### Tests
- Prompt byte-equality for a keto-only profile; schema validity; parser
  table tests per rule; evaluator table tests per restriction × severity ×
  role; a Python replay of the same tables through the goldens.
- Backend: respx-mocked Gemini, the five routes with a profile.

### Acceptance criteria
- [ ] Extraction section in the prompt; schema v2; parser rules; evaluator
      in Dart and Python; goldens regenerated; byte-equality for keto.
- [ ] A profile change re-evaluates from the cache with no network call.
- [ ] `architecture.md` §9 rewritten for extraction + evaluation; D26
      records option B and why.

---

## ALG-04 — Allergen rules engine and the level-A veto

**Size:** M · **Phase:** P1 · **Depends on:** ALG-01, ALG-03 · **Blocks:** ALG-05

### Problem
Today the rules engine is a fallback: it runs only when the model cannot.
For an anaphylactic user the model must never be the only thing between
them and a dish, and the model's extraction can miss a trigger that sits in
plain sight in the dish name.

### What it is
1. **Rules concerns.** `ClassificationRules.match` gains an allergen pass:
   the ALG-01 triggers run over the dish's name, description and
   (non-removal) option values, exactly like the carb pass, and return
   `Concern`s with `source: rules` and the vocabulary's certainty. Guards
   cancel; removal phrases are skipped.
2. **Union, not fallback.** After the model's extraction is evaluated
   (ALG-03), the rules concerns are **merged in**: a concern the model
   missed is added; a concern both found keeps the higher certainty; a
   concern the model found that rules did not is kept. Rules never remove
   a model concern.
3. **The veto.** For a profile entry at severity A or B, a rules concern
   with certainty `stated`/`likely` forces the verdict to at least
   `modifiable` (if the trigger sits on a removable role) or `nonKeto`
   (otherwise), whatever the model said. For severity C/D the model's
   verdict stands and the rules concern is shown as evidence only. This is
   the only place in the engine where rules outrank the model, and it is
   documented as such.
4. **Rules-only mode.** When the model cannot answer, the rules pass is the
   whole analysis (as today for keto), the engine chip says "rules", and
   ALG-05 wording for level A becomes stricter still ("menu text checked
   by rules only — ask").

### Design notes
- Runs on the device after any analysis, including one that came complete
  from the backend; it is pure and takes milliseconds, so there is no
  reason to trust a server's merge over the device's own.
- The Python port runs the same pass before returning a D25 result, so a
  backend-served analysis already carries rules concerns; the device's
  pass is then idempotent (merge is a set union).
- The three keto toggle rules move under the same mechanism (they already
  are a vocabulary-driven yellow), with no behaviour change.

### Tests
- Table tests: for each first-release restriction, a dish that the model
  "missed" (fake LLM extraction without the trigger) ends up with the
  rules concern and, at severity A, the vetoed verdict; at D, the model's
  verdict.
- A flow test: fake model says `orderAsIs` for "סלט עם טחינה", profile has
  sesame at A → the dish shows "avoid / ask" with the sesame concern.

### Acceptance criteria
- [ ] Allergen pass in `ClassificationRules` and in `backend/app/keto/rules.py`.
- [ ] Merge and veto in one pure function with its table tests, in Dart
      and Python, pinned by goldens.
- [ ] Keto goldens unchanged.

---

## ALG-05 — Four-state verdict UI: safe / modify / ask / avoid, by severity

**Size:** M · **Phase:** P1 · **Depends on:** ALG-02, ALG-03, ALG-04

### Problem
The menu screen speaks keto: green "order as is", yellow "modifiable", red
"non-keto", a keto score, verdict tiles and filters named after them. An
allergy user needs a fourth state — *ask* — and must never read the word
"safe" beside a life-threatening restriction.

### What it is
- **Derived state per dish:** `fits` (green), `fitsWithChange` (yellow),
  `ask` (new, amber/outlined), `avoid` (red). `ask` = any `suspected`
  concern on an A/B entry, or any concern at all on an A entry whose
  verdict is green (because "no stated trigger" is not "safe"). The wire
  verdict is unchanged; this is a `utils/` function with a table test.
- **Wording by severity.** Verdict names, the legend, tile labels and the
  share text (`menu_share_text.dart`) come from one function of (state,
  highest severity in the profile). With keto only: today's names,
  verbatim. With any A entry: green reads "No trigger found — confirm",
  never "Safe"; the legend carries the helper-tool sentence. A test
  asserts no string containing "safe"/"בטוח" is ever produced for a
  profile with an A entry — the sibling of `failure_copy.dart`'s
  no-shared-copy test.
- **Dish card.** Under the verdict, one line per concern: a restriction
  chip (named, coloured by its severity), the source ("in the name", "in
  the description", "option: bread", "hidden: soy sauce"), and the
  certainty as words. The existing one-waiter-action row becomes the
  concern's `waiterQuestion` or the modification, whichever applies.
- **Counter tiles and filters.** Four tiles when the profile has a non-keto
  entry; `MenuFilter` gains `askOnly` and the default filter for a profile
  with an A entry is "fits + ask" (hide avoid, show what to check).
- **The headline number.** The keto score stays only when keto is in the
  profile; otherwise the header shows "N fit · M with a change · K to
  ask" and no score (file 09 §5). `VerdictCounts.of` is extended, not
  replaced.
- **Engine chip.** Unchanged, plus a second chip "rules checked" when the
  ALG-04 pass ran on a model result, so the user sees the safety net was
  applied.

### Accessibility and RTL
Severity colour is never the only signal: each state has an icon and a
word; the concern chip has the restriction's name. Hebrew names come from
the taxonomy, not ARB, because they are read beside the Hebrew dish name.

### Tests
- Table test of the derived state; copy test for the "safe" ban; widget
  tests of the card, tiles and filters in both locales; a flow test
  "profile with peanuts (A) → menu → default filter hides avoid, a dish
  with 'אגוזים' is ask, share text has no 'safe'".

### Acceptance criteria
- [ ] Derived state, severity wording, dish-card concerns, tiles, filters,
      header counts, share text.
- [ ] `docs/UX_REVIEW.md`-style pass on the menu screen at 390px and
      desktop, light and dark, Hebrew and English.
- [ ] Keto-only screens pixel-identical to today (the existing visual audit
      pages as the reference).

---

## ALG-06 — Evidence tiers and explained confidence

**Size:** S–M · **Phase:** P1 · **Depends on:** ALG-03, ALG-04 · **Enhances:** ALG-05, ALG-09, ALG-16

### Problem
The research's single most repeated gap: competitors give a colour with no
reason, and the free LLM gives a reason with no accountability. The user
must be able to see *why* and *how sure*.

### What it is
A per-concern `EvidenceTier`, in strength order:
`declared` (the platform or the restaurant said so — ALG-09, ALG-16),
`stated` (the words are in the dish text), `inferred` (a dish-name rule:
"schnitzel" → wheat), `suspected` (a hidden-source rule or the model's
guess), `confirmed`/`denied` (a person asked the kitchen — ALG-14). Plus
a per-dish `coverage` note: whether the dish had a description, options,
and whether the extraction came from the model, rules, or both.

The UI shows the tier as a short phrase on the concern line (ALG-05) and,
on tap, a sheet "Why this verdict" listing every concern, its tier, the
exact text it matched, and what would change the verdict ("ask whether the
dressing contains soy sauce"). No numeric percentage is shown anywhere: a
number would be invented, and the research's own warning is that
uncalibrated scores are what the AI apps do.

### Tests
- Tier assignment table tests; a widget test of the explanation sheet;
  the copy test that no percentage string appears.

### Acceptance criteria
- [ ] `EvidenceTier` on `Concern`, assigned by the evaluator, the rules
      pass and (later) ALG-09/14/16; in the cache and the Python port.
- [ ] "Why this verdict" sheet, both locales.

---

## ALG-07 — Cross-contact signals at menu level

**Size:** S · **Phase:** P2 · **Depends on:** ALG-03, ALG-05

### Problem
A "clean" dish in a kitchen with a shared fryer or a flour-dusted counter is
not clean for a celiac or a peanut-allergic user. No menu says "shared
fryer", but the menu *reveals* the kitchen.

### What it is
A pure, rules-only pass over the **whole menu** (not per dish) that emits
`KitchenSignal`s: `fryer` (any "fried", "chips", "צ'יפס", "מטוגן" dish),
`wok` (Asian menu markers), `sharedGrill` (meat and fish on one grill
section), `bakery` (bread, pastries, pizza on the menu), `nuts` (any dish
naming nuts), `sesame` (any dish naming sesame or tahini — on an Israeli
menu nearly always true, which is exactly the point). Each signal maps to
the restrictions it threatens and to a standard question for the staff.

The menu screen shows a collapsible "Kitchen" notice under the header when
any signal threatens an A/B entry: "This menu has a fryer and a bakery. For
celiac disease, ask whether fries share the fryer with breaded dishes." It
never changes a dish's verdict — it is a menu-level fact beside the
per-dish answer — but it does add a `suspected` concern with tier
`inferred` to green dishes in the affected category when the entry is A
(so they become *ask*, by ALG-05's rule).

### Tests
- Signal table tests on the Wolt and 10bis fixtures and on Hebrew paste
  fixtures; a widget test for the notice; the keto-only profile shows no
  notice.

### Acceptance criteria
- [ ] `KitchenSignals.of(menu)` in Dart and Python; the notice; the
      A-entry demotion; no effect for keto-only.

---

## ALG-08 — Waiter questions and the dynamic chef card

**Size:** M · **Phase:** P2 · **Depends on:** ALG-03, ALG-05 · **Extends:** the Waiter Card

### Problem
Equal Eats sells a static card. KetoClub already has a full-screen,
brightness-raised Waiter Card for one dish's modification. An allergy user
needs the card to say what they *are*, what this *dish* must not contain,
and what to *ask* — in the restaurant's language.

### What it is
- **Per-dish questions.** Every concern carries a `waiterQuestion` (from
  the vocabulary's templates or the model), bilingual, written in the
  menu's language as the modification is (§12). ALG-05 shows the first;
  the Waiter Card shows them all.
- **The chef card.** A new full-screen page (reusing the Waiter Card's
  shell: brightness, large type, copy button, share) composed from the
  profile: a heading line per A/B entry ("I have a severe allergy to
  sesame — even traces can be dangerous"), the dish's name as printed,
  the dish's modification and questions, and a closing line asking the
  kitchen to confirm cross-contact precautions when ALG-07 raised a
  signal. The whole card is produced from sentence templates per
  restriction and severity in both languages — the §6.3 exception extended
  — and, when the menu's language is neither, by one request to the
  existing menu-question path (#214) asking for a translation, cached per
  (card text, language).
- **Card without a menu.** From Settings, the same card for the profile
  alone ("show this at any restaurant"), so the feature is useful on day
  one even where no menu can be read.
- Copy-to-clipboard and share as text and as an image (the existing share
  path), for sending to a restaurant's WhatsApp before a visit.

### Tests
- Template rendering table tests per restriction × severity × language;
  widget test of the card page; a flow test "profile with sesame (A) →
  dish → Waiter Card → chef card shows the sesame line and the dish's
  question in Hebrew for a Hebrew menu".

### Acceptance criteria
- [ ] Questions on every concern; the chef card page; the profile-only
      card from Settings; translation through the question path with its
      consent and failure copy.

---

## ALG-09 — Platform-declared dietary data as evidence

**Size:** S · **Phase:** P2 · **Depends on:** ALG-06 · **Open question:** 11 in file 08

### Problem
Wolt sends `dietary_preferences` on every item and 10bis sends `kosher` on
every dish; both mappers read neither. That is the one evidence source
stronger than anything the engine can infer, and it is free.

### What it is
- `Dish` gains `declaredTags: List<String>` (platform strings, kept raw);
  the Wolt and 10bis mappers fill it; the Hive cache and the Python
  mappers follow (a field on `Dish` needs no `schemaVersion` bump — the
  CLAUDE.md trap).
- A small mapping from platform tags to restriction ids with a polarity
  ("vegan" → clears `vegan`, `vegetarian`, and marks `milk`, `eggs` as
  `declared` absent; "gluten-free" → clears `gluten` at tier `declared`;
  `kosher: true` → shows a "declared kosher by the platform" chip, which is
  the only kosher statement the app ever makes, and is attributed to the
  platform, not to KetoClub).
- A `declared` absence lowers a concern's certainty but **never** below
  `suspected` for an A entry (the restaurant can be wrong; principle 3).
- **First task of the issue:** record one real Wolt menu in Israel that has
  non-empty `dietary_preferences`, or establish that the field is unused
  here (`tool/record_wolt_fixture.sh`). File 12 §4.4 found that what Wolt
  Israel *shows* is venue-level (🌱 🌾 beside the venue name, city category
  pages) and that dish-level information is restaurant-written text; 10bis
  puts "ללא גלוטן" and "טבעוני" as free text in section headings, item names
  and footnotes. So the likelier shape of this feature is **text
  self-declarations**: the ALG-01 vocabulary gains 🌱, 🌾, "טבעוני",
  "ללא גלוטן", "צמחוני", "vegan", "gluten-free" as *declared-by-restaurant*
  guards that lower certainty and never clear an A entry, read from the
  category heading as well as the dish (the D21 `dish_kind` precedent). If
  the JSON field is unused, that text path is the whole feature and Wolt
  reads stay tolerant.

### Tests
- Mapper tests with a fixture carrying tags; evaluator tests for the
  polarity rules; the kosher-chip attribution copy test.

### Acceptance criteria
- [ ] `declaredTags` through both mappers, the cache and the Python port;
      the tag mapping; the chip; the fixture recorded or the absence
      documented in `test/fixtures/README.md`.

---

## ALG-10 — Safety evaluation corpus and the critical-miss gate

**Size:** M · **Phase:** P0 (corpus) and P1 (gate) · **Depends on:** ALG-01; the gate on ALG-03/04

### Problem
The research's first metric is the critical-miss rate on level-A triggers,
and its evidence that unguarded LLMs miss 7% of gluten dishes. Nothing in
the current test suite measures misses per restriction.

### What it is
- **A labelled corpus** under `test/fixtures/allergens/`: real and
  synthetic menus (the existing Wolt and 10bis fixtures, Hebrew pastes,
  the smoke-test menus) with a human label per dish per first-release
  restriction: *contains / may contain / free*, and the role of the
  trigger. Labelled by the clinical reviewer (D-f) or, until one exists,
  by the author with the source noted — and flagged as unreviewed in the
  file header.
- **A rules-only replay** (`flutter test` and `pytest`): the ALG-04 pass
  over the corpus must find every *contains* label at certainty ≥ likely
  for every A-capable restriction. Any miss fails CI: that is the gate.
  `may contain` must be ≥ suspected. False positives are reported, not
  gating (a false alarm is the acceptable direction).
- **A model replay** (`backend/tools/allergen_eval.py`, person-run like
  the vision smoke test, #88): sends the corpus through the real extraction
  prompt and reports per-restriction miss rates for the model alone, for
  rules alone, and for the merge — the number the research says to
  publish before launch, and the benchmark against a bare prompt that file
  07's MVP asks for.
- The corpus and the goldens are different things: goldens pin Dart ==
  Python; the corpus pins engine == truth.

### Acceptance criteria
- [ ] Corpus with ≥ 300 labelled dishes across ≥ 15 menus, half Hebrew.
- [ ] CI gate on rules recall for A-capable restrictions.
- [ ] The person-run model evaluation script and a `docs/` page for its
      last result.

---

## ALG-11 — Health-data privacy, consent and liability copy

**Size:** S · **Phase:** P0 · **Depends on:** ALG-02

### Problem
A restriction profile is health data. Today's consent text explains that
menu text leaves the device; it must now explain what of the *profile*
leaves it, and the product must say what it is not.

### What it is
- **What leaves the device, exactly:** with ALG-03 option B, only the keto
  constraint fragments, the `exceptions` free text and any ALG-17 free-text
  restriction travel with a request; restriction ids and severities do
  not. The "What leaves this device" disclosure in Settings states this in
  both languages, and the architecture test pins that no field named
  `severity` or `restrictionId` appears in any request body built under
  `lib/services/`.
- **A second consent** is not added: the existing AI consent covers the
  request, but its copy changes and a changed copy re-shows the
  disclosure once (`disclosureSeen` is reset by a copy version).
- **`stored_menus` keeps dropping options** (D24); add a backend test that
  a `/v1/menus` body with any profile field is rejected with 422.
- **Liability copy, once, in three places:** onboarding when the first A
  entry is added, the Settings notice (ALG-02), and the legend (ALG-05):
  "KetoClub reads menus. It cannot see the kitchen, verify a recipe or
  replace asking the staff. For a life-threatening allergy, always
  confirm." No diagnosis or treatment wording anywhere — a copy test over
  the ARB files for a short banned-word list ("diagnose", "treat",
  "medical device", "מאבחן", "מטפל").
- **Terms:** a `docs/TERMS_NOTES.md` listing what counsel must review
  before an A-entry build ships to a store (the research's "clear terms,
  insurance, helper-tool" items), so the dependency on a human is
  written down.

### Acceptance criteria
- [ ] Disclosure copy, the architecture-test pin, the backend 422 test, the
      banned-word copy test, the terms notes.

---

## ALG-12 — Group profiles ("what fits everyone")

**Size:** M · **Phase:** P3 · **Depends on:** ALG-02, ALG-03

### Problem
Families and groups choose a restaurant together; the person with the
restriction is often ordering for a child. "What can *we* eat here" is the
research's differentiator 7 and nobody offers it.

### What it is
- **Named profiles on the device:** "Me", "Dana (8)", "Grandma" — each a
  `DietaryProfile`; one is active; any subset can be *combined* for a
  menu. Still on the device only; no account; sharing a profile is an
  export/import of its JSON by QR or a share sheet (a profile is health
  data, so the export screen says so and the import asks).
- **Combined evaluation:** with option B this is free — the extraction is
  per menu, the evaluation runs once per selected profile, and the dish
  state shown is the *strictest* across them, with a per-person breakdown
  on the card ("fits Dana · ask for you"). The header shows "N dishes fit
  everyone".
- **The chef card** (ALG-08) composes one section per person.
- **Discovery:** the quick score stays keto's (`estimateMenuRepository`,
  D25); group fit is computed only on an opened menu.

### Tests
- Profile store with several profiles; strictest-state table tests; a flow
  test "two profiles, one with milk (A), one keto → a cheese omelette is
  avoid for one, fits for the other, strictest shown".

### Acceptance criteria
- [ ] Profiles list in Settings, the combine control on the menu screen,
      per-person breakdown, export/import with the health-data wording.

---

## ALG-13 — Trip mode

**Size:** M · **Phase:** P3 · **Depends on:** ALG-01 (jurisdictions), ALG-08 · **Priority note (2026-10-11):** both launch markets (Israel, US) are home markets, so this is the last of P3

### Problem
Abroad, the user does not know which allergens the local restaurant is
obliged to disclose, which local dishes hide their trigger (buckwheat soba
in Japan, lupin flour in France, mustard in every German sauce), or how to
say "anaphylaxis" in the local language. The research names this as the
highest-value moment for retention and the gap Equal Eats half-fills.

### What it is
- **A destination picker** (country) that sets a `tripJurisdiction` beside
  the profile. From the taxonomy's jurisdiction tags the app shows, per A/B
  entry: "regulated here — the restaurant must be able to tell you" or
  "not regulated here — you must ask every time". The tag must distinguish
  *packaged-food* regulation from a *restaurant* duty: Israel's 2028 rule
  and the US FASTER Act cover packaged food, so in both home markets the
  hint is "ask every time"; the EU/UK and SB 68 chains are where a
  restaurant must answer (file 12 §4).
- **A local hidden-ingredient lexicon** per country: a small, reviewed list
  per destination (first: Israel, the EU's largest tourist countries, the
  UK, the US, Japan) of dishes and ingredients that hide each restriction,
  added to the evaluator as `suspected` triggers while the trip is active
  and shown as a pre-trip briefing page ("In Japan: soba is buckwheat;
  soy sauce is wheat; dashi is fish").
- **The chef card in the local language** (ALG-08's translation path),
  pre-generated and cached before the trip so it works offline at the
  table.
- Trip mode never changes the keto rules and switches off with one tap.

### Tests
- Jurisdiction rendering table test for every taxonomy entry × country;
  lexicon trigger tests; an offline flow test that the cached card opens
  with connectivity off.

### Acceptance criteria
- [ ] Destination picker, regulation hints, lexicons for the first set of
      countries with sources, pre-cached cards, offline behaviour.

---

## ALG-14 — Post-meal confirmation and community verification

**Size:** L · **Phase:** P3 · **Depends on:** ALG-05, ALG-06, D24's shared store

### Problem
The research's unique-dataset idea: after the meal, did the kitchen confirm
what the app said? Competitors have star ratings nobody trusts; KetoClub
can have *per-dish, per-visit facts* instead, and they are the only way the
`declared` → `confirmed` tier ever gets filled without a restaurant's
cooperation.

### What it is
- **The prompt:** a few hours after a menu was opened with an A/B entry
  (a local notification, opt-in, no server), or from the Recent tab: "Did
  you ask about *sesame* in *סלט חצילים*?" with three answers per concern:
  *confirmed present · confirmed absent · didn't ask*, plus "they changed
  the dish as requested — yes/no" for a modification, and a free-text
  note that stays local (`NotesStore`).
- **Local effect:** the visit history (D23) records the confirmations;
  the next time the menu opens, the dish shows the concern at tier
  `confirmed`/`denied` with the date, and the "Why" sheet says "you
  confirmed with the staff on 12 May".
- **Shared effect (opt-in, separate consent):** a confirmation is uploaded
  to a new backend table keyed by **venue, dish fingerprint, restriction
  id and polarity** — a count, a first and last date, never an install id,
  never a note (the D24 rule). The server returns the counts with
  `/v1/venue-menus`, and the evaluator uses them only as evidence tier
  (`denied` by N people lowers certainty but, for an A entry, never below
  `suspected`; `confirmed` raises it). There is **no rating**: a venue is
  never summed into a number, which is the whole difference from
  AllergyEats and Spokin.
- **Abuse:** a count needs ≥ 3 distinct confirmations before it is shown;
  the per-install rate limit applies; a restaurant cannot submit (there is
  no restaurant side).

### Tests
- Store round-trip; evaluator tier effects; the "never below suspected for
  A" rule; backend tests for the table, the 422 on any install id or note,
  the ≥ 3 threshold; a flow test from Recent to the prompt to the tier
  shown.

### Acceptance criteria
- [ ] Local confirmations in the visit history and their display; the
      opt-in upload with its own consent; the backend table and route; the
      threshold; architecture decision recorded (D27).

---

## ALG-15 — Delivery note helper

**Size:** S · **Phase:** P2 · **Depends on:** ALG-08

### Problem
On Wolt, 10bis, Uber Eats or DoorDash the only allergy channel is usually a
free-text box (80% of restaurants in the research's survey). Users type
the same paragraph every time, badly, and screenshots of a delivery menu
already go through the scan path.

### What it is
- On any Wolt or 10bis menu, a "Copy allergy note" action in the overflow
  that composes, from the profile and the chosen dish's concerns, a short
  note in the menu's language: "אלרגיה חמורה לשומשום — בבקשה ללא טחינה,
  ולוודא שאין מגע עם שומשום בהכנה." One tap copies it; a second shares
  it. The text is the chef card's (ALG-08) compact form.
- A screenshot of a delivery app's menu is already a scan (D15); the
  action exists there too.
- No integration with the platforms' order flow (none exists and the
  research's reading of their terms is that the restaurant bears the
  responsibility anyway).

### Acceptance criteria
- [ ] The action, bilingual templates, copy and share, a widget test and a
      template table test.

---

## ALG-16 — Restaurant allergen-matrix intake (the verified layer)

**Size:** L · **Phase:** P4 · **Depends on:** ALG-06, ALG-09 · **Seeds:** B2B

### Problem
Regulation is producing allergen matrices (EU 14 for non-prepacked food,
UK written information, California SB 68 per-dish allergens for chains from
July 2026; Israel's 2028 rule covers packaged food only, so Israeli
matrices will be voluntary). Nothing in KetoClub can read one. A matrix turns a
dish's concern from inferred to `declared` and is the strongest evidence
the app will ever have without a kitchen visit.

### What it is
- **A matrix format**: one CSV/JSON per venue and date, rows = dishes (by
  printed name), columns = the 14 EU allergens + sesame + "may contain",
  plus source and the person who entered it. Stored on the backend beside
  `stored_menus`, keyed by venue, with a validity date.
- **Intake paths, in order of trust:** (1) a restaurant uploads its own
  through a minimal, authenticated B2B page (the first restaurant-facing
  surface; out of scope to build the account system here, so this path
  starts as a manual import by the maintainer); (2) a photographed printed
  matrix read by the existing vision path with a matrix-specific prompt
  and schema; (3) a user-submitted matrix photo, held as `suspected` until
  a second submission agrees.
- **Matching** a matrix row to a `Dish` is by the same normaliser and
  fingerprint rules the parser uses for names (§9.4), with unmatched rows
  listed, never guessed.
- **Effect:** matched dishes carry `declared` concerns (or declared
  absences) with the matrix's date; the evaluator treats a declared
  absence as it does ALG-09's (never below `suspected` for A). The venue
  card shows "allergen information from the restaurant, dated …" — a
  fact, not a badge, and no restaurant can buy a rating (file 07, B2B
  rule).

### Tests
- Format parsing, matching table tests with Hebrew and English name
  variants, evaluator tier tests; backend route tests; a vision fixture of
  a printed matrix.

### Acceptance criteria
- [ ] Format, backend storage and route, manual intake, vision intake,
      matching, the dated venue notice, the "no rating" rule in the
      architecture.

---

## ALG-17 — Extended restrictions: FODMAP, histamine, GLP-1, alpha-gal, legumes, free text

**Size:** L · **Phase:** P4 · **Depends on:** ALG-01, ALG-03, ALG-10

### Problem
The research's second tier: the fastest-growing (GLP-1 ×3.7 in two years,
alpha-gal) and least-served (FODMAP, histamine, legumes, mustard outside
the US) restrictions. Each has a different shape, so each needs its own
design rather than a new row in the taxonomy.

### What it is
- **Legumes and mustard** are ordinary allergen entries (A-capable):
  vocabulary + corpus only. Legumes matter in Israel (hummus, falafel,
  lentil soup) and are the first to add.
- **Alpha-gal** is an allergen whose trigger is a *class* (mammalian meat
  and derivatives: beef, lamb, pork, gelatin, lard, dairy for some): an
  entry with a class vocabulary and an "includes dairy" exception toggle.
- **FODMAP and histamine** are *dose and preparation* sensitivities
  (onion and garlic in a sauce; aged, fermented, cured foods): C-only
  entries whose vocabulary carries a `highDose`/`lowDose` note and whose
  concerns always read as "may be high in …", never avoid. The research
  says nobody serves these at the restaurant and the data basis is thin,
  so they ship as "preference" with a clear "based on common FODMAP
  guidance, not a measurement" line.
- **GLP-1 (small portions, protein first)** is not a restriction but a
  *preference signal*: a D-only entry that asks the extraction prompt for
  the portion hint and protein role it already extracts (ALG-03) and sorts
  or tags dishes "protein-forward · small portion" rather than colouring
  them. No nutrition numbers are shown (none exist).
- **Free-text restriction** ("I react to kiwi") — the only thing sent to
  the model as a constraint sentence beyond keto's (ALG-11), evaluated by
  the model, tier `suspected` at most, severity capped at B until a
  vocabulary entry exists.

### Acceptance criteria
- [ ] Each sub-feature as its own PR with vocabulary, corpus labels, the
      evaluator rule, copy and tests; the GLP-1 tag; the free-text entry
      with its cap.

---

## ALG-18 — Premium gating and the free tier

**Size:** M · **Phase:** P4 · **Depends on:** most of P1–P3 · **Decision:** file 08 Q4

### Problem
The research proposes free up to N scans a month with one restriction and
basic questions, and premium at $4–8/month for unlimited scans, the
combined profile, trip mode, group profiles and history. KetoClub has no
payments, no accounts, and a per-install rate limit that is the only
"quota".

### What it is
- **The gate lives on the device and is honest:** a `Entitlement` read
  from the store purchase (StoreKit / Play Billing through one plugin,
  behind an interface with a null implementation for web and tests, in
  `services/platform/` like the other plugins), and a monthly scan counter
  in `shared_preferences`. The web build has no store and stays free (the
  backend's rate limit is its quota), or gets a code — a decision for the
  issue.
- **What is never gated:** the chef card for the profile (ALG-08's
  Settings card), the liability copy, confirmations (ALG-14), and anything
  about a level-A entry already in the profile. Gating safety is the
  research's complaint 4 and the fastest way to lose trust.
- **What is gated:** more than one restriction in the active profile,
  group profiles, trip mode, scans past the monthly count.
- Copy, prices and the paywall screen are a design task with the research's
  reference prices (file 07); the backend learns nothing about purchases
  (no account).

### Acceptance criteria
- [ ] `Entitlement` interface and null implementation; the counter; the
      gates with their "never gated" test; the paywall screen; `di.dart`
      wiring with no plugin I/O in constructors (the CLAUDE.md trap).

---

## Cross-cutting work that is not a feature

- **Architecture records.** D26 (profile, severities, extraction +
  evaluation, three wire verdicts + derived state), D27 (confirmations and
  the no-rating rule), amendments to D2, D15 (scan transcribes
  descriptions), D22 (the one schema bump), D24 (new table, same install-id
  rule), D25 (profile in `options`).
- **Docs:** `architecture.md` §6.2, §6.3, §7, §9, §11, §14, §17;
  `CLAUDE.md` status banner and traps (add: "rules outrank the model only
  for A/B", "no 'safe' for A", "a profile never enters a request body");
  `HANDOFF.md`; `README.md`'s classification narrative.
- **CI:** the ALG-10 gate as a required job beside `backend/check.sh`.
- **Regression promise:** a `test/architecture/keto_unchanged_test.dart`
  that builds the keto-only prompt, the keto score and the verdict copy
  and compares them to committed fixtures — the mechanical form of
  principle 1.

## Suggested issue order for the first milestone ("Allergens: P0 + P1")

1. ALG-01 taxonomy (vocabulary PRs may be split per restriction group).
2. ALG-10 corpus (labels can start before the engine).
3. ALG-02 profile and Settings.
4. ALG-11 privacy and copy.
5. ALG-03 prompt, schema v2, evaluator (Dart + Python, one PR each).
6. ALG-04 rules pass, merge and veto.
7. ALG-05 UI states and copy.
8. ALG-06 evidence tiers and the "Why" sheet.
9. The ALG-10 gate switched to required.

A second milestone ("Allergens: at the table") takes ALG-08, 07, 09, 15;
a third ("Allergens: people and places") ALG-12, 13, 14; a fourth
("Allergens: breadth and business") ALG-17, 16, 18.
