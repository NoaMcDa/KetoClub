# 09 — Conclusions

What the research means for KetoClub specifically, measured against the
code that exists today. File 10 turns these into features.

## 1. The verdict on the pivot

**Do it, as an extension of the engine, not as a new app.** The research's
white space — a per-dish verdict for a combined profile, with a modification
and questions to read to the waiter, in the menu's language, explained and
with a deterministic safety net — is a description of what KetoClub already
does for one restriction. The pivot is "generalise the restriction", not
"build an allergy app". Everything that makes the current product unusual
(one request per menu, the never-throwing parser, the rules fallback, the
waiter card, the scan and website paths, the backend with its caches and
the Python port) carries over unchanged in shape.

Two things the research gets right that must drive the design:

- **The real competitor is a bare ChatGPT/Gemini prompt.** It is free and
  reads any menu in any language. The product beats it only on what a
  prompt cannot provide: a remembered profile, a deterministic layer that
  can veto the model, an explained confidence, questions to ask, and a
  record of what the kitchen confirmed. Every feature in the epic should be
  checked against "could the user get this from a chat window?"
- **The failure that matters is the critical miss**, not the false alarm.
  A keto false negative costs a few grams of carbs; an allergen false
  negative can be an anaphylaxis. This inverts the tuning of the whole
  engine for every allergen and celiac entry: prefer "ask" over "safe",
  let rules block but never unblock, and measure the critical-miss rate
  in CI. (The owner's stance, 2026-10-11: the app is a helper and promises
  no accuracy — which is exactly why its wording floor is "ask the
  restaurant", for every allergy alike.)

## 2. What the codebase already gives us

| Research asks for | Already in KetoClub | Where |
|---|---|---|
| Combined profile sent to the engine | `ClassificationOptions.dietaryConstraints` — a list of constraint sentences appended to the system prompt and switched on in the rules engine, recorded in the cached analysis's options snapshot so a change re-analyses | `menu_classifier.dart`, `menu_analysis_prompt.dart`, `analysis.dart` (`AnalysisOptionsSnapshot`), #56, #57 |
| Hybrid engine: LLM + deterministic rules | `RoutingMenuClassifier` → LLM (backend first, device key second) with `HeuristicMenuClassifier` as the fallback; `ClassificationRules.match` is bilingual regex over a vocabulary in `constants.dart`, ported to Python and pinned by goldens | §6.2, D2, D25 |
| "Ask the waiter" per dish | `HiddenCarb {source, certainty: suspected/likely, waiterQuestion}` — a per-dish list of suspected hidden ingredients each with a question; the UI shows one waiter action per yellow dish | `analysis.dart`, §9.2 |
| Four states (fits / change / ask / no) | Three verdicts (`orderAsIs`, `modifiable`, `nonKeto`) plus the hidden-carb "suspected" flag, which already demotes a green to yellow and lowers its score weight (#213) | `DishVerdict`, `keto_score.dart` |
| Waiter card in the restaurant's language | `AnalysedDish.modification` written in the menu's language, detected from the dish text, shown full-screen with raised brightness | §6.3, §12, `waiter_card_sheet.dart` |
| Free-text question about the menu | Menu questions (#214, §9.5): an LLM answer referencing dish ids, no rules fallback | `menu_question_*.dart` |
| Any input: platform, paste, photo, PDF, website, QR | Wolt, 10bis, `TextMenuSource`, `VisionMenuClassifier`, website locator, QR router | D15, D18, D19, #182 |
| Shared data layer | `stored_menus` on the backend keyed by venue, with the analysis minus its options; analysis cache keyed by fingerprint, model, schema version, limit and constraints | D24, D25 |
| Platform-declared tags | Wolt's `dietary_preferences` per item and 10bis's `kosher` per dish are **present in the payloads and read nowhere**; file 12 §4.4 found Wolt's visible tags are venue-level (🌱 🌾) and 10bis's are free text in headings and item names, so the dish-level field may well be empty in Israel | `wolt_menu_mapper.dart`, `tenbis_menu_mapper.dart` |
| Privacy posture | Every setting on the device; the install id travels only for rate limiting and is never stored beside content; constraints never reach `stored_menus` | D24, §11 |

## 3. What has to change

1. **The verdict semantics are keto-shaped.** The enum is named `nonKeto`,
   the prompt's role is "the keto-diet menu analyst", the verdict
   definitions and rules in `constants.dart` talk about net carbs, and the
   score is a "keto score". A profile-driven engine needs verdict
   definitions *generated from the profile*: "orderAsIs" means "no
   restriction in the profile is violated", "modifiable" means "violated,
   but a stated modification makes it compliant", "nonKeto" (wire name
   kept) means "no compliant path". With a keto-only profile the generated
   text must be byte-identical to today's, so the server's chat cache and
   every golden stay valid.
2. **A fourth state is needed but should not be a fourth wire verdict.**
   "Ask" is what an allergen entry with an *uncertain* trigger
   demands. Modelling it as a verdict would touch the cache format, the
   Python port, the goldens, the score and every filter. Modelling it as
   **per-dish `concerns`** — a generalisation of `hiddenCarbs` to
   `{restrictionId, source, certainty, waiterQuestion}` — keeps three wire
   verdicts and derives "ask" in the UI from "any suspected concern on an
   allergen or celiac entry". The existing `hiddenCarbs` becomes the
   keto member of that list. This is one `schemaVersion` bump (1 → 2),
   which re-analyses cached menus once and loses the pages of cached scans
   (D22's cost) — acceptable once, so bundle every schema change of the
   epic into that one bump.
3. **The rules engine must be allowed to veto.** Today the rules engine
   runs only when the model cannot answer. For every allergen and celiac
   entry it must *also* run after the model and add any trigger the model
   missed (union of concerns), and a dish with such a trigger found by
   rules can never be shown as safe, whatever the model said. That is the "deterministic
   layer blocks, never unblocks" principle from the research, and it is
   the one thing a chat window cannot offer.
4. **The vocabulary becomes a safety artefact.** The keto vocabulary is
   bilingual regex with a golden corpus; an allergen vocabulary is the same
   mechanism but every entry is a safety claim. It needs a source per entry
   (the regulatory lists in file 02, plus hidden-ingredient knowledge such
   as soy sauce → wheat, tahini → sesame, Worcestershire → fish, pesto →
   nuts and dairy, "vegetable broth" → celery, lupin flour, sulphites in
   wine), a reviewer, and a critical-miss gate in CI. Every change still
   needs the golden regeneration and the Python replay (`backend/check.sh`).
5. **The profile is health data.** Three booleans in `shared_preferences`
   were not; "anaphylactic to peanuts" is (GDPR Article 9). The profile
   stays on the device; what leaves it is the constraint sentences, which
   today already go to Gemini under the AI consent. The consent copy must
   say so explicitly, and `stored_menus` must keep ignoring options.
6. **Copy is the product's promise.** No screen may say "safe" for an
   allergen or celiac entry; the floor is "ask the restaurant". The
   verdict names, the legend, the score label and the share text all
   change when the profile holds a strict entry. `failure_copy.dart`'s
   rule — no two reasons share a message — gets a sibling: no dish is ever
   labelled with the green verdict's unqualified word for such a profile.
7. **Cost and cache fragmentation.** Every distinct profile is its own
   analysis-cache key and chat-cache key. With ~30 restrictions in any
   combination the server-side sharing of analyses across users mostly
   disappears. Two mitigations are in the epic: normalise the constraint
   list to a canonical order (already the case for the three toggles), and
   split the request into a profile-independent *ingredient extraction*
   (cacheable per menu) and a cheap on-device *profile evaluation* — the
   research's own "LLM extracts, rules decide" shape, and the single
   biggest architectural choice in the epic (ALG-03).

## 4. Decisions that must be taken before building

| # | Decision | Recommendation |
|---|---|---|
| D-a | Ship allergens as a mode inside KetoClub, or rename first | **Decided 2026-10-11: a rename is planned, name not chosen.** The engine work is the same either way. Keep every `keto*` identifier and wire name; change UI copy only; the rename is a branding and store-listing task tracked outside the epic |
| D-b | Severity levels | **Decided 2026-10-11: none.** The owner's rule: an allergy is an allergy whether or not it is life-threatening; the app promises no accuracy, is a helper tool only, and the user asks the restaurant about everything. So the research's A–D levels are dropped. A restriction is *strict* (allergen, celiac) or *flexible* (intolerance, diet, keto) by its kind in the taxonomy; the rules veto, the "ask" state and the no-"safe" wording apply to every strict entry; one helper-tool sentence appears at onboarding and in every menu's legend. The critical-miss gate stays as an engineering quality gate, not a legal shield |
| D-c | Pilot market | **Decided 2026-10-11: Israel and the United States.** Hebrew is already first-class, Wolt and 10bis are integrated, the Israeli list is EU-shaped (2028, packaged food only — restaurants have no duty, file 12 §4), sesame and legumes are locally critical, and the competition is empty; the US is the largest market and brings SB 68-style chain allergen data (ALG-16). The home taxonomy is the EU 14 ∪ US 9, which the first-release scope already is. Trip mode (ALG-13) becomes a later feature: both markets are home markets |
| D-d | Where the engine's profile evaluation runs | **Extraction in the model, evaluation on the device/server by rules** (ALG-03 option B) — reproducible, cheaper, cache-friendly, and it makes the rules layer the authority for level A |
| D-e | Taxonomy scope for the first release | The EU 14 + US 9 union (16 items) — confirmed by the Israel + US market decision — celiac, lactose, vegan/vegetarian, and today's keto with its three toggles. Legumes and sesame are already in the 16 for Israel. FODMAP, histamine, GLP-1, alpha-gal are phase 2 (ALG-17) |
| D-f | Who validates the vocabulary | **Decided 2026-10-11: no clinical reviewer is available; published sources stand in.** Every vocabulary entry cites a source from `11_hidden_allergen_sources.md` or `12_israeli_and_us_menu_lexicon.md` (FARE, FDA, FSA, Coeliac UK, the Israeli Ministry of Health and allergy association, and so on). The critical-miss gate is a regression tool, not a safety claim, until a reviewer exists; the liability copy (ALG-11) says so |

## 5. What the research did not look at and the epic has to

- **The Hebrew problem is bigger than translation.** Israeli menus hide
  allergens in dish *names* (טחינה in "סלט חצילים עם טחינה", שומשום on
  every בורקס, פול in פול-ופלאפל) and Hebrew has no `\b`. The existing
  lookaround machinery handles it, but the vocabulary must be written by
  someone who reads Israeli menus, not translated from an English list.
- **Options are part of the dish** (#191/#192): "choice of bread" is where
  gluten hides, "add feta" where dairy hides. The allergen rules must read
  options the same way the carb rules do, with the same removal-option
  exclusion.
- **Scans have no rules fallback** (D15) and the vision path transcribes
  only names. For allergens a scan must also transcribe descriptions, or
  the concern list on a scanned menu will be hollow.
- **The score.** A "keto score" out of 10 makes no sense for an
  anaphylactic user; a menu with one safe dish is a usable menu. The epic
  replaces the headline number with counts per state for non-keto
  profiles and keeps the score only when keto is in the profile.
