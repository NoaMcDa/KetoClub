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
  engine for level-A and level-B restrictions: prefer "ask" over "safe",
  let rules block but never unblock, and measure the critical-miss rate
  before anything ships.

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
| Platform-declared tags | Wolt's `dietary_preferences` per item and 10bis's `kosher` per dish are **present in the payloads and read nowhere** | `wolt_menu_mapper.dart`, `tenbis_menu_mapper.dart` |
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
   "Ask" is what a level-A restriction with an *uncertain* trigger
   demands. Modelling it as a verdict would touch the cache format, the
   Python port, the goldens, the score and every filter. Modelling it as
   **per-dish `concerns`** — a generalisation of `hiddenCarbs` to
   `{restrictionId, source, certainty, waiterQuestion}` — keeps three wire
   verdicts and derives "ask" in the UI from "any suspected concern on a
   level-A or level-B restriction". The existing `hiddenCarbs` becomes the
   keto member of that list. This is one `schemaVersion` bump (1 → 2),
   which re-analyses cached menus once and loses the pages of cached scans
   (D22's cost) — acceptable once, so bundle every schema change of the
   epic into that one bump.
3. **The rules engine must be allowed to veto.** Today the rules engine
   runs only when the model cannot answer. For level A/B it must *also*
   run after the model and add any trigger the model missed (union of
   concerns), and a dish with a level-A trigger found by rules can never
   be shown as safe, whatever the model said. That is the "deterministic
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
6. **Copy is now a liability surface.** No screen may say "safe" for a
   level-A restriction. The verdict names, the legend, the score label and
   the share text all change by severity. `failure_copy.dart`'s rule — no
   two reasons share a message — gets a sibling: no level-A dish is ever
   labelled with the green verdict's unqualified word.
7. **Cost and cache fragmentation.** Every distinct profile is its own
   analysis-cache key and chat-cache key. With ~30 restrictions × 4
   severities the server-side sharing of analyses across users mostly
   disappears. Two mitigations are in the epic: normalise the constraint
   list to a canonical order (already the case for the three toggles), and
   split the request into a profile-independent *ingredient extraction*
   (cacheable per menu) and a cheap on-device *profile evaluation* — the
   research's own "LLM extracts, rules decide" shape, and the single
   biggest architectural choice in the epic (ALG-03).

## 4. Decisions that must be taken before building

| # | Decision | Recommendation |
|---|---|---|
| D-a | Ship allergens as a mode inside KetoClub, or rename first | **Mode first.** Branding is a separate, reversible decision; the engine work is the same either way. Keep every `keto*` identifier and wire name; change UI copy only |
| D-b | Launch with level A | **Build for level A from day one, launch it behind the consent and the "helper tool" wording.** Designing B–D first and bolting A on later would mean re-tuning the engine; the critical-miss gate exists to make A shippable |
| D-c | Pilot market | **Israel.** Hebrew is already first-class, Wolt and 10bis are integrated, the Israeli list is EU-shaped (2028), sesame and legumes are locally critical, and the competition is empty. The EU 14 is the home taxonomy |
| D-d | Where the engine's profile evaluation runs | **Extraction in the model, evaluation on the device/server by rules** (ALG-03 option B) — reproducible, cheaper, cache-friendly, and it makes the rules layer the authority for level A |
| D-e | Taxonomy scope for the first release | The EU 14 + US 9 union (16 items), celiac, lactose, vegan/vegetarian, and today's keto with its three toggles. Legumes and sesame are already in the 16 for Israel. FODMAP, histamine, GLP-1, alpha-gal are phase 2 (ALG-17) |
| D-f | Who validates the vocabulary | A named clinical reviewer (dietitian or allergist) before the critical-miss gate is trusted; until then the gate is a regression tool, not a safety claim |

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
