# M15 — Meal Entry: research, pre-flight, and the milestone plan

**Source issue:** #312 → rewritten as the **M15 Epic**
**Status:** **shipped.** All twelve issues plus #327 and #328 are merged; the
four e2e flows are green in the `e2e flows` job. This document's research and
pre-flight sections are kept as written — they record what was measured before
the code existed, and §10 below records what shipping did and did not verify.
**Read before:** picking up any M15 issue, and before trusting any number the
app produces for a meal it did not read off a label.

---

## 0. Verdict, in one paragraph

#312 asks for three ways to add a meal. **One of them already ships, half of
another already ships, and the third is the only genuinely new engine.** Mode 1
(type the macros) is `AddMealBottomSheet`, live since M2. Mode 3's
photo-of-a-*label* path is the Keto Lens pipeline, live since M6 and corrected
by #257 — it is simply not reachable from the add-meal affordance. What is
actually missing is **an estimator: free Hebrew text, or a photographed plate →
macros**, plus a chooser in front of the three, plus the provenance the diary
needs once a number in it may be a guess. This document records what was
measured, the decision taken on which engine to build, and the twelve issues
that follow from it.

---

## 1. What #312 says, and the four things its text gets wrong

> 1. enter all of the values - carbs, protein, fat manually
> 2. enter a description of a meal and the system will calculate automatically the values with options to edit before adding
> 3. enter a photo of the meal with ocr, with optional description of the meal and the system will calculate automatically the values with options to edit before adding

### 1.1 Mode 1 is not work. It is the screen that exists.

`lib/features/diary/presentation/widgets/add_meal_bottom_sheet.dart` is exactly
mode 1: a name and three macro fields, validated through the same finite-number
rule the rest of the app uses, saved through `MealLoggingService`. The title
"adding meal by hand fix" reads as though hand entry is broken. It is not — it
is the only mode that works, and **every M15 issue must leave it behaving
identically**. It is also the mode the other two funnel into: an estimate that
cannot be edited before saving is not what #312 asked for, and the edit surface
is this sheet.

The one real change mode 1 needs is that it stops being the *only* thing behind
the `+`.

### 1.2 "a photo of the meal with ocr" conflates two different capabilities

OCR reads **text**. A photographed plate of shakshuka has no text on it. Two
distinct things hide behind one line, and M15 ships both — by different engines:

| What the photo is | What reads it | Status |
|---|---|---|
| The **nutrition panel** of a packaged product | Tesseract → `HebrewLabelParser` → `ScanOrchestrator`, on-device | **Ships.** M6, corrected by #257 |
| The **meal itself** on a plate | A multimodal model; not OCR at all | New. §4 |

The order matters and is a design rule, not a preference: **mode 3 tries the
local label OCR first.** On a nutrition panel it is free, offline, instant and
*exact* — it reads printed figures rather than estimating them. The remote
estimator is the fallback for everything that is not a label.

Mode 3 also finally writes `MealEntry.imageRef`, a field persisted, mapped and
contract-tested since M1 and **never written by any production code path**.

### 1.3 "the system will calculate automatically" hides the entire engineering question

Which system, reading what, and — the question this project has learned to ask
first — **what does it do when it cannot tell?** M6 shipped a sealed
`ScanResult` precisely so a failed scan could not be reported as a verdict
(`design/m6_preflight.md` §1.1: issue #83 would have told a user in a shop that
an unreadable product was Clean Keto). An estimator has the same shape of
failure and needs the same shape of answer: a sealed result, a per-item
breakdown the user can see, and **no silent zero** — the rule #257 already wrote
down for scanned amounts (`CLAUDE.md` § OCR: *"an empty or unparseable amount
falls back to the printed figures, never to zero"*).

### 1.4 It is three issues' worth of UI and one milestone's worth of engine

Filed as one issue it fails `issue_conventions.md` §1 on all four atomicity
tests. It needs an HTTP client, a key store, a consent surface, an estimator, a
sealed result, a mode chooser, two new review surfaces, a provenance field that
reaches the diary, and e2e coverage of three flows. That is a milestone.

---

## 2. What the codebase already gives M15

Read this before planning anything — most of the plumbing is built.

| Asset | Where | M15 use |
|---|---|---|
| Manual macro form with prefills | `add_meal_bottom_sheet.dart` — `initialName`, `initialFatG`, `initialNetCarbsG`, `initialProteinG` | The edit-before-save surface for **both** new modes. Already built for #84 |
| `MealEntry.imageRef` | `diary/domain/models/meal_entry.dart`, mapped and contract-tested | Mode 3's photo reference. **Currently written by nothing** |
| `MealEntry.ingredients` | same | The estimator's identified-item list. **Currently written by nothing** |
| The one add-meal affordance | `add_meal_fab.dart` (`AddMealFab`), two hosts, two keys | The chooser hangs off this, not off a new inline FAB (`design/user_bugs_handoff.md`) |
| Photo capture and gallery import | `keto_lens/presentation/camera/` — `CameraSession`, `PhotoPicker`, both with web implementations | Mode 3 reuses them; **no new plugin, no new permission** |
| Label OCR, six platforms, no network | `ScanOrchestrator` + `TextRecognitionService` behind the conditional-export firewall | Mode 3's first attempt, unchanged |
| Serving-basis scaling | `ServingBasis`, `_SuccessBody` amount field (#257) | The precedent for how an amount turns figures into what was eaten |
| The numeric-input rule | `NumericInput.positiveFinite` | Every number that comes back from the model goes through it. Do not copy the guard |
| Typed persistence failure | `guardPersistence`, `PersistenceException` | The key store's reads wrap like every other storage call |
| The `user_profile` singleton store | `UserProfileMapper` | Where the API key and the consent flag live. **No new store** |

**Two dead fields are the tell.** `imageRef` and `ingredients` were specified in
M1, persisted correctly, and then no feature ever filled them. M15 is the
feature they were for.

---

## 3. The accuracy bar: why a keto app cannot borrow a calorie app's

This is the measurement that drives every rule below, and it is worth stating
before the engine rather than inside it.

`KetoConstants.defaultNetCarbTargetG` is **20 g**. That is the whole day, and
`OnboardingService` hands out the same induction allowance. So:

- The best vision-language model in the 2026 Nutrition5k benchmark — Gemini 3.0
  Flash — estimates **calories** with a mean absolute error of **80.7 kcal**
  (CCC 0.767); the best ingredient overlap across the ten models benchmarked was
  Jaccard 0.655.
- 80.7 kcal **is 20 g of carbohydrate.** If an error that size lands on the carb
  term rather than the fat term, it is the user's entire daily allowance. A
  calorie app absorbs an 80 kcal miss inside a 2,000 kcal budget — 4%. A keto
  app cannot: the same absolute error is up to **100%** of the number that
  decides whether the day was compliant.
- Consumer photo-calorie apps measure at **68–86% for identifying the food and
  as low as 39% for estimating the portion**. Portion is the half that matters
  most here, because macros scale linearly with it.

And the error does not stop at the meal card. `MealLoggingService` recalculates
the `DailyLog` on every save and feeds the day's ratio to
`AdaptationPhaseService.evaluateToday`. **A wrong estimate can break a streak,
or falsely preserve one** — it reaches the adaptation phase state machine, which
is the app's retention mechanic. Nothing else the app computes has that reach.

Three rules follow, and every M15 issue inherits them:

1. **No estimate is ever saved without passing through an editable form.** The
   numbers in front of the user when they press שמור are the numbers that get
   saved — the invariant #257 established for the scan sheet.
2. **An estimate is labelled as one, in the entry itself.** Hence `MacroSource`
   (§6.3): the diary must be able to say "this was a guess" a week later, when
   the user is looking at a day that broke their streak.
3. **An item the model did not identify is reported, never dropped.** A
   silently-ignored `לחם` makes a 40 g-carb meal look like a 2 g one, and the
   day still reads compliant. `IngredientVerdict.recognisedNothing` exists for
   the same reason on the scan side.

**None of the figures above measures the estimator M15 builds.** They belong to
other datasets and other approaches, and they are quoted to set a bar, not to
predict a result. §10 is explicit that no accuracy claim is made here.

---

## 4. The engine: what was evaluated, and the decision taken

Four options were assessed.

| | Offline food table | **Cloud LLM** | On-device image classifier | Barcode lookup |
|---|---|---|---|---|
| Coverage of Israeli home/street food | Partial — needs a recipe table for שקשוקה | **Broad** | None — Western restaurant classes, in English | Packaged goods only |
| Works offline | Yes | No | Yes | No (10 GiB dump is not bundleable) |
| Deterministic / auditable | Yes | No | No | Yes |
| Marginal cost | Zero | Per request | Zero | Zero |
| Health data leaves device | No | **Yes** | No | Barcode only |
| Produces a portion | From the description | **Yes** | No — a class label is not grams | N/A |

> ### Decision taken: the cloud LLM, via OpenRouter, not gated on login
>
> This session's research recommended the offline table and rejected the cloud
> option, on the grounds that a hosted key implies a backend, which implies the
> unscheduled `epic:login` milestone (#206–#226) — a forward dependency
> `milestone_conventions.md` §1.4 forbids.
>
> **The product owner's call is that the login dependency does not exist**, and
> they are right about the mechanism: an OpenRouter key is a string, not an
> identity system. The app needs a key, not accounts. That removes the
> sequencing objection entirely, and it buys the one thing the offline table
> cannot give — an answer for "שקשוקה עם פיתה" — which is what most people
> actually type.
>
> The other three objections do not disappear; they become requirements, and
> §4.1–§4.3 are where they are paid for. The offline table is **not deleted** —
> it is demoted to a documented fallback behind the same `MacroEstimator`
> interface, and §5 keeps the dataset research intact for whoever picks it up.

### 4.1 Consequence one: bring your own key

**OpenRouter's free tier is 20 requests per minute and 50 requests per day, per
key** — 1,000/day only for accounts that have at some point purchased $10+ in
credits. A single key baked into the app would be exhausted by a handful of
users before lunch. And a key in a Flutter bundle is extractable anyway:
trivially on web, where it ships as plaintext JavaScript, and with modest effort
from an APK or an `.app`.

So the key is **per user**: pasted into Settings, stored in the existing
`user_profile` store. A `--dart-define=OPENROUTER_API_KEY` stays as a developer
and CI-smoke convenience, never as the shipping default.

A hosted proxy holding a paid key is the obvious later improvement and **still
needs no login** — it is an adapter behind `MacroEstimator`, exactly as
`TextRecognitionService` absorbed a complete engine swap from ML Kit to
Tesseract without a single consumer changing.

### 4.2 Consequence two: the offline promise has to be restated, not quietly broken

`design/mvp.md` §165 claims *"All 5 core features work offline on an iPhone 12
or newer."* Macro tracking is one of the five. The honest reconciliation, and
the wording M15 must put in that document:

> **Manual meal entry works offline, always.** Estimation is an optional
> enhancement that requires a network and a key, and every failure path in it
> lands the user in the manual form with what they typed intact.

That is true, it is checkable, and it is the difference between an enhancement
and a regression. It also means `EstimateFailureReason.offline` is a
first-class, designed-for state rather than an error screen.

**Keto Lens's invariant is untouched.** A *scan* still makes no network call —
Epic #10's first architectural invariant and `CLAUDE.md`'s OCR section both
stand exactly as written. M15's request belongs to a different feature, and
every document that records it must say so, or the next reader will conclude the
OCR invariant was relaxed.

### 4.3 Consequence three: this is health data, and consent is an issue, not a checkbox

A meal description plus a photo, sent to a third party, is dietary health
information. Three things follow:

- **Opt-in.** Estimation is off until the user enters a key and accepts a
  disclosure that says what is sent and to whom. No pre-ticked box.
- **The App Store privacy labels change.** `epic:release-v1` (#125–#128)
  currently describes an app that transmits nothing. Issue 12 updates that, and
  it is a blocking item for the release milestone, not a nicety.
- **Nothing is sent that was not asked for.** The request carries the
  description and, in mode 3, the photo. Not the diary, not the symptom log, not
  the profile.

### 4.4 What was rejected and why

- **On-device image classifier** — its label space is Western restaurant food in
  English; לאפה, מלאווח and לביבות are not in it, and a class label is not a
  portion. Rejected on the grounds M6 rejected every non-Tesseract engine: it
  does not speak the language the users do.
- **Barcode lookup (Open Food Facts)** — a genuinely good fit for Israeli
  packaged goods and *more* accurate than any estimate, because it is a lookup
  rather than an inference. Out of scope here: `milestone_conventions.md`
  already lists it as deferred, and the offline dump is ~10 GiB compressed, so
  it is an online lookup with a cache — a different architecture from anything
  M15 builds. Worth its own milestone.

---

## 5. The offline fallback, kept on the shelf

Preserved because the `MacroEstimator` seam makes it a drop-in, and because a
key-less, offline, zero-cost estimator is the right answer for the common case
("200 גרם חזה עוף") even after the cloud one ships.

**The Israeli Ministry of Health national nutrition database ("צמרת" /
Tzameret)**, published on `data.gov.il` as the מאגר התזונה הלאומי הישראלי, is
the dataset to use. From its published description: about a third of its foods
come from USDA and other national databases, a third from the Israeli food
industry, and **a third are recipes — composed dishes with their ingredient
breakdown**. It ships as four files: an ingredient/recipe list with nutritional
components **per 100 grams**, and a recipe file giving each recipe's ingredient
composition and quantities, each with an explanation file. That third group is
the direct answer to a food table's usual coverage limit.

**It could not be downloaded from this session** — `data.gov.il` is blocked by
the network egress policy of the environment this research ran in (HTTP 403 at
the proxy, for both the dataset page and the CKAN API). So all of the following
remain **unverified** and are the first job of anyone who picks the fallback up:
the column schema and units; the row count and whether a **fibre** column exists
(the app needs *net* carbs); the licence, and specifically whether it permits
redistribution inside an app bundle; and the encoding.

Fallbacks to the fallback: USDA FoodData Central (public domain, English, needs
a Hebrew mapping), Open Food Facts (ODbL, branded goods), or a hand-curated
200–400-row seed of Israeli keto staples.

**Asset budget, for whenever this lands:** a row is a Hebrew name, synonyms,
four numbers and a household-portion weight — ~80–120 bytes of JSON, so ~500 KB
at 5,000 rows and ~1 MB at 10,000. The app already bundles **4.9 MB** of
`tessdata` on every native target. The budget is not the constraint; the licence
is.

---

## 6. Architecture

No new plugin, no new permission, and no change to either conditional-export
firewall. The photo half reuses `camera` and `image_picker`, both already in
`pubspec.yaml` with web implementations. One new package: `http`.

### 6.1 The pipeline

```
AddMealFab → mode chooser ─┬─ manual      → AddMealBottomSheet                      (ships today, unchanged)
                           │
                           ├─ description → MacroEstimator ─ RemoteMacroEstimator
                           │                  → OpenRouterClient   (http, pinned :free model)
                           │                  → MealEstimate       (sealed)
                           │                  → itemised review → AddMealBottomSheet (prefilled)
                           │
                           └─ photo       → PhotoPicker / CameraSession             (reused)
                                             → ScanOrchestrator — if it parses, the #257 path, offline
                                             → else image + optional description → RemoteMacroEstimator
                                             → review → AddMealBottomSheet + imageRef
```

### 6.2 New domain surface

Feature directory: **`lib/features/diary/`**. This is meal entry — it belongs
with the meals, not in `keto_lens/`, and not in a new feature folder. (Compare
`design/m5_preflight.md`, where the directory named in the issue text did not
exist.)

```dart
// domain/models/meal_estimate.dart — sealed, for the reason ScanResult is
sealed class MealEstimate {}

final class EstimateSucceeded extends MealEstimate {
  final List<EstimatedItem> items;   // what the model named, at what weight
  final List<String> unidentified;   // what it could not — shown, never silent
  final double fatG, netCarbsG, proteinG;
}

final class EstimateFailed extends MealEstimate {
  final EstimateFailureReason reason;
}

enum EstimateFailureReason {
  emptyInput, notConfigured, offline, rateLimited,
  unauthorised, badResponse, nothingIdentified,
}

// domain/services/macro_estimator.dart
abstract interface class MacroEstimator {
  /// Never throws. Every failure is a value, so no caller can mistake one for
  /// a verdict — the rule ScanResult exists to enforce.
  Future<MealEstimate> estimate({String? description, String? imagePath});
}
```

### 6.3 Provenance — the one change to a shipped model

```dart
enum MacroSource { manual, scannedLabel, estimatedFromText, estimatedFromPhoto }
```

added to `MealEntry` with a default of `MacroSource.manual`, stored **by
`.name`** (`CLAUDE.md` § Local Persistence — never by ordinal), and decoded with
a null-tolerant fallback to `manual` so every meal already in a user's database
keeps reading. The diary card shows an estimate as an estimate.

This is what makes §3's rule 2 real rather than a comment, and it is the field
that lets a future audit ask *"how often is an estimate edited before saving?"*
— the only honest way to find out whether the estimator is any good on real food.

### 6.4 Layer rules

`domain/` holds `MealEstimate`, `EstimatedItem`, `MacroSource` and the
`MacroEstimator` interface — pure Dart, no `http`. `data/` holds
`OpenRouterClient`, `RemoteMacroEstimator` and the key store; `application/`
composes them; `presentation/` renders. `OpenRouterClient` takes an injected
`http.Client`, which is what keeps the whole stack testable without a network —
the property `ScanOrchestrator` was built for, and the reason **no test in this
milestone, unit or e2e, makes a request**.

### 6.5 Treating the model's answer as untrusted input

The response is JSON from a third party, shaped by text the user typed. It is
parsed, never evaluated, and every number crosses the same guard the keyboard
does:

- Missing, `null`, non-numeric, negative, `NaN` and `Infinity` all fail through
  `NumericInput.positiveFinite` — the same reason that helper exists at all.
- A macro the model omitted stays **null**, and the form's own validator asks
  for it. Never zero — the `initialFatG` doc comment on `AddMealBottomSheet`
  spells out why (a fat-free tahini saved without anyone noticing).
- An implausible total is a `badResponse`, not a saved meal.
- No field of the response is ever interpreted as an instruction.

---

## 7. UX

- **The chooser is three large targets in one sheet**, opened by the existing
  `AddMealFab`: `הזנה ידנית` · `תיאור הארוחה` · `צילום`. Not a tab bar, not a
  dropdown — 44×44 pt minimum, RTL, per `design/ui_ux_design.md`.
- **Every path ends in the same editable form.** One save button, one validator,
  one code path to `MealLoggingService`.
- **The estimate review shows its work**: each identified item with its weight
  and its contribution, then the total. An unidentified token appears in the same
  list, greyed, marked `לא זוהה` — visible, not silent.
- **Every failure reason gets its own Hebrew copy and its own escape.** "אין
  חיבור לאינטרנט" and "לא הוגדר מפתח" want different sentences and different
  buttons; both end at manual entry with the typed text preserved.
- **Digit runs stay `TextDirection.ltr`** inside the RTL layout — an M3
  convention the macro fields already follow.
- **The scan path keeps every word of its copy.** #257's Definition of Done says
  an unreadable label keeps exactly the behaviour and wording it had; reaching it
  from a new entry point does not change that.

---

## 8. The milestone

### North Star

A meal can be added three ways — typed, described, or photographed — and every
one of them lands in the same editable form before anything is saved, with the
app never presenting a guess as a measurement.

### Explicitly out of scope

- **The offline food table** (§5) → kept behind the same interface, filed separately
- **Barcode lookup** (§4.4) → its own milestone
- **A hosted key proxy** (§4.1) → a later adapter; BYOK ships first
- **Accounts and login** — M15 needs a key, not an identity. `epic:login` is unaffected
- **Editing an already-saved meal** — M15 is about *adding*. A real gap, and a separate issue
- **Changing manual entry's behaviour** — mode 1 is a regression surface, not a work item

### Architectural invariants

1. No estimate reaches the database without passing through `AddMealBottomSheet`.
2. An unidentified item is reported, never dropped and never zeroed.
3. `MealEntry.source` is set on every write path, manual included.
4. **Keto Lens's no-network invariant is untouched** — a scan still makes no network call.
5. Manual entry's observable behaviour is byte-identical at the end of the milestone.
6. No new plugin, no new permission, no change to either conditional-export firewall.
7. No test, unit or e2e, makes a network call.
8. Estimation is opt-in: off until a key is entered and the disclosure accepted.

### Definition of Done

`milestone_conventions.md` §3's standard list, plus:

- [ ] All three modes reachable from **both** hosts of `AddMealFab` — the defect in `design/user_bugs_handoff.md` was exactly one host having an affordance the other lacked
- [ ] Three e2e flows in `integration_test/`, one per mode, run by the `e2e flows` job
- [ ] `MacroSource` round-trips for every value, and a record written before M15 still reads
- [ ] `design/mvp.md`'s offline claim restated per §4.2, and the privacy labels in `epic:release-v1` updated

---

## 9. The twelve issues, in build order

Dependencies point backwards only. Every issue leaves `main` green on its own.

| # | Issue | Layer | Depends on |
|---|---|---|---|
| 1 | `MacroSource` on `MealEntry` + mapper + contract tests + backward-compatible decode | domain → data | — |
| 2 | `MealEstimate` / `EstimatedItem` / `EstimateFailureReason` + the `MacroEstimator` interface | domain | — |
| 3 | `EstimationSettings` — BYOK key and consent flag in the `user_profile` store, `--dart-define` fallback, `guardPersistence`-wrapped | data | — |
| 4 | `OpenRouterClient` — `http`, `POST /api/v1/chat/completions`, pinned `:free` model, typed failures for 401 / 429 / timeout / offline | data | 3 |
| 5 | `RemoteMacroEstimator` (text) — prompt, strict-JSON response contract, tolerant parse, §6.5 validation, provider wiring | data → application | 2, 4 |
| 6 | `RemoteMacroEstimator` (photo) — base64 image part, optional description, size and dimension cap before upload | data | 5 |
| 7 | Settings surface — enable estimation, paste key, §4.3 disclosure copy. Lands in the `lib/features/profile/` placeholder | presentation | 3 |
| 8 | Mode chooser sheet behind `AddMealFab`; manual path unchanged | presentation | — |
| 9 | Description mode — input → estimate → itemised editable review → prefilled `AddMealBottomSheet`, with copy for every failure reason | presentation | 5, 8 |
| 10 | Photo mode — capture/pick → label OCR first → remote estimate otherwise → review → prefill + `imageRef` | presentation | 6, 8, 9 |
| 11 | Provenance in `MealCard` and the diary — an estimate reads as an estimate | presentation | 1 |
| 12 | Three e2e flows + the docs update (`CLAUDE.md`, `design/mvp.md`, `design/technology.md`, `design/tasks.md`, this file's status line) | test / docs | 9, 10, 11 |

Issues 1, 2, 3 and 8 have no dependencies and can start immediately. **Issue 8
is the cheapest useful thing in the milestone** — it makes the two other modes
discoverable the moment they land, and until then it is one extra tap on a path
that already works.

---

## 10. Risks, and what has not been verified

Written in the spirit of `design/m6_handoff.md`'s "what is unverified" section,
because the failure mode this project keeps rediscovering is a green suite over
an untested reality.

| Risk | Reality |
|---|---|
| **Accuracy on real Israeli meals** | **Nobody has measured it.** No corpus of real Hebrew meal descriptions exists here, exactly as no corpus of real labels existed before M6 — and `design/m6_platform_handoff.md` records what that cost. Collect 100 real descriptions and their true macros; it needs no app and no device |
| **The free tier runs out** | 50 requests/day per key (§4.1). A user who logs six meals a day is fine; one who retries is not. `rateLimited` must be an ordinary, well-worded state |
| **The model returns confident nonsense** | §6.5 validates ranges and nulls, but a *plausible* wrong number passes every check. §3's three rules are the only real defence, and the reviewing user is the last one |
| **The user just presses save** | The realistic behaviour, and why reporting unidentified items matters more than a confidence percentage nobody reads |
| **An estimate silently drives the streak** | Mitigated by §6.3's provenance, not eliminated. Whether an estimated day should count toward the streak is a **product decision** — §11 |
| **A free model is deprecated upstream** | `:free` model IDs come and go. Issue 4 pins one and carries a fallback list; a dead model must surface as `badResponse`, not a crash |
| **The photo mode regresses M6** | It reuses `ScanOrchestrator` unchanged. Any divergence in copy or behaviour is a defect against #257's DoD |
| **The Tzameret licence** | Unverified — `data.gov.il` was unreachable from this session (§5). Only blocks the offline fallback, which is out of M15's scope |

**No accuracy number is claimed anywhere in this document for the estimator this
milestone builds.** None has been measured, and §3's figures belong to a
different approach and a different dataset.

---

## 11. Open decisions for the product owner

1. **Does an estimated day count toward the streak?** Today every logged meal
   does. Count it (simple, occasionally wrong) or require one measured meal a day
   (safer, annoying). *Recommendation: count it, and revisit once §6.3's
   provenance shows how often estimates are edited before saving.*
2. **BYOK forever, or a hosted proxy later?** BYOK ships M15 with no
   infrastructure and no login. A proxy with paid credits removes the setup step
   and the 50/day ceiling, at the cost of running something. *Recommendation:
   ship BYOK, revisit when someone complains about the setup step — the seam
   makes it a swap.*
3. **Is editing a saved meal in or out?** Out of M15 as written, and a real gap
   — an estimate you can fix before saving but not after is a strange place to
   stop. *Recommendation: a separate issue, right after M15.*

---

## Sources

- OpenRouter FAQ (free-tier rate limits, OpenAI-compatible endpoint) — <https://openrouter.ai/docs/faq>
- OpenRouter free tier: rate limits, models, BYOK — <https://klymentiev.com/blog/openrouter-free-tier>
- Vision-Language Models for Image-Based Dietary Assessment: A Benchmark of Accuracy, Cost, and Prompt Strategies Across Ten Models — <https://www.biorxiv.org/content/10.64898/2026.07.26.740845v1>
- Nutrition5k: Towards Automatic Nutritional Understanding of Generic Food — <https://arxiv.org/pdf/2103.03375>
- Apps That Calculate Calories From Photos: Are They Accurate? — <https://fitia.app/learn/article/ai-calorie-photo-apps-accuracy-2026/>
- Food Portion Estimation: From Pixels to Calories — <https://arxiv.org/html/2602.05078v1>
- Israeli National Nutrition Database (מאגר התזונה הלאומי הישראלי) — <https://data.gov.il/dataset/nutrition-database> *(unreachable from this session; see §5)*
- Israeli Ministry of Health, food-service databases — <https://www.health.gov.il/UnitsOffice/HD/PH/FCS/Pages/DataBases.aspx>
- Open Food Facts data, API and SDKs — <https://world.openfoodfacts.org/data>

---

## 11. What shipping M15 measured, and what it did not

Added at closure, so the "not verified" line stays honest rather than
inheriting the pre-flight's optimism.

**Verified.**

- The three modes are reachable from the `+` on **both** hosts, driven end to
  end by `add_meal_manual_flow.dart`. That separation is deliberate: the first
  defect a real user hit was the diary telling them to tap a `+` it did not
  have.
- **The label is read before any network call.** `add_meal_photo_flow.dart`
  asserts the estimator fake was called **zero** times when the scan
  succeeded. That is the OCR-first rule, and this is the only place it is
  checked end to end.
- The review list's total is what reaches the form, after a removal, rounded
  to one decimal — `0.17999999999999988` cannot reach a field.
- An unidentified token is rendered, never dropped.
- A saved estimate carries `MacroSource`, the card shows it, correcting a
  macro clears it and correcting only the name does not.
- Tap-to-edit and swipe-to-delete coexist on the same card.
- `MealEntry.imageRef` is written for the first time since M1.

**Not verified, and not claimed.**

- **No real model has ever answered.** Every test and every flow fakes
  `MacroEstimator` at the interface — the suite makes no network call by
  construction. Nothing here measures how good an estimate actually is, and
  the accuracy argument in §3 is still the only thing that bounds it.
- **No camera and no gallery.** `MealPhotoSource` is faked everywhere. The
  capture path has never run against a real picker on any platform.
- **No photograph has ever been sent.** `MealPhotoPrep` is unit-tested against
  generated bitmaps; no phone photo has been through it.
- **The BYOK key has never been used against the live provider.** The
  credentials, the transport and the prompt are all tested against fakes.
- The quota argument (50 requests/day per key) is taken from OpenRouter's
  published free tier and has not been observed.
