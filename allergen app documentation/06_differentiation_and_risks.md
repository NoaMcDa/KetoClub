# 06 — Differentiation and risks

*Source: research parts 3.1 and 3.2.*

## 3.1 What KetoClub can offer that the competitors do not

1. **A combined profile with severity levels.** Every restriction is set to
   a level: **A** anaphylaxis, **B** autoimmune or trace-sensitive (celiac),
   **C** intolerance, **D** preference. The threshold and the *language of
   risk* change by level: "probably safe" is never shown for a level-A
   restriction. *(Owner's decision 2026-10-11: levels dropped. Every allergy
   is treated the same — the strict wording applies to all of them — and
   the app is a helper tool that promises no accuracy; see file 09 D-b.)*
2. **A hybrid engine, not an LLM alone.** The LLM extracts the ingredient
   list of each dish, including the *likely hidden* ones (soy sauce,
   marinade, seed oil). A deterministic rules layer maps ingredients to
   restrictions. Regulation makes the data richer over time: California's
   SB 68 (the ADDE Act, signed 13 October 2025) requires chains with 20 or
   more locations to give written notice, on the menu or in a digital
   format, of which of the nine major allergens each menu item contains as
   an ingredient, from 1 July 2026; the EU's 14 must be disclosed for
   non-prepacked food; the UK FSA has recommended written allergen
   information as best practice since March 2025 (guidance, not law).
   Ingesting restaurant allergen matrices turns the engine from "inferred"
   to "verified". *(Checked 2026-10-19; sources in file 12 §8.1.)*
3. **An explained confidence score per dish**: the source of the evidence,
   the context, and what is left to ask. Example — beurre blanc: "contains
   butter, almost certainly; ask the waiter".
4. **Questions for the waiter, and a dynamic chef card** generated from the
   profile *and* the dish, in the restaurant's language. Equal Eats' static
   card becomes dynamic.
5. **Substitutions** — the existing asset ("without croutons, sauce on the
   side, and please use a separate pan") extended to level A.
6. **Cross-contact risk by kitchen type** (fryer, wok, shared grill,
   bakery), shown even when the dish itself is "clean".
7. **Group profiles**: "what fits everyone" when a family eats together.
8. **Community verification**: a per-dish "the waiter confirmed / did not
   confirm" report that feeds the engine and builds a dataset nobody else
   has.
9. **A delivery layer**: analysis of a delivery-platform link or screenshot
   (Wolt, Uber Eats, DoorDash).

## 3.2 Risks and mitigations

| Risk | Mitigation |
|---|---|
| **Legal liability (anaphylaxis)** | Wording is always "no trigger found in the menu text — confirm with the staff", never "safe"; clear terms of use; professional-liability insurance; for level A the product is explicitly a *helper tool*; counsel reviews the copy |
| **LLM hallucination** | A deterministic rules layer that can block but never unblock; an evaluation set that measures *critical misses* (false negatives on a level-A trigger) as the first metric; a self-consistency check (ask twice, disagree → "ask") |
| **Restaurant regulation** | SB 68 (in force from 1 July 2026 for chains of 20 or more locations: the nine allergens contained as ingredients, per item, in writing; it does **not** require cross-contact disclosure, and the penalty was not confirmed — corrected 2026-10-19), FIC 1169/2011 (Article 44: allergen information is mandatory for non-prepacked food), and the FSA's March 2025 best-practice guidance (written information recommended; "Owen's Law", the campaign to make it law, has not been enacted) give no data to a product directly, but are official building blocks: an allergen matrix is becoming something a restaurant *has*. **Israel is the exception:** its 2028 rule covers packaged food only and restaurants have no disclosure duty today (file 12 §4), so in the pilot market every restaurant answer is voluntary |
| **App-store policies** | Make no diagnosis or treatment claim; present the product as nutrition information, not a medical device |
| **Privacy** | Allergy and disease information is **health data** (GDPR Article 9, a special category). Explicit consent, data minimisation, the profile stored on the device by default, and never sent to Gemini as a *profile* — only the constraint sentences the analysis needs |
| **Kosher / halal** | Show only "contains ingredients not suitable for …", never "kosher" or "halal", unless certification data exists |
