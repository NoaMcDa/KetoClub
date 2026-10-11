# 06 — Differentiation and risks

*Source: research parts 3.1 and 3.2.*

## 3.1 What KetoClub can offer that the competitors do not

1. **A combined profile with severity levels.** Every restriction is set to
   a level: **A** anaphylaxis, **B** autoimmune or trace-sensitive (celiac),
   **C** intolerance, **D** preference. The threshold and the *language of
   risk* change by level: "probably safe" is never shown for a level-A
   restriction.
2. **A hybrid engine, not an LLM alone.** The LLM extracts the ingredient
   list of each dish, including the *likely hidden* ones (soy sauce,
   marinade, seed oil). A deterministic rules layer maps ingredients to
   restrictions. Regulation makes the data richer over time: California's
   SB 68 requires chains with 20+ locations to publish the nine allergens
   per dish from 1 July 2026; the EU's 14 must be disclosed for
   non-prepacked food; the UK FSA has recommended written allergen
   information since 2025. Ingesting restaurant allergen matrices turns the
   engine from "inferred" to "verified".
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
| **Restaurant regulation** | SB 68 (a misdemeanour from 1 July 2026 for not disclosing cross-contact in covered chains), FIC 1169/2011, FSA 2025 ("Owen's Law") give no data to a product directly, but are official building blocks: an allergen matrix is becoming something a restaurant *has*. **Israel is the exception:** its 2028 rule covers packaged food only and restaurants have no disclosure duty (file 12 §4), so in the pilot market every restaurant answer is voluntary |
| **App-store policies** | Make no diagnosis or treatment claim; present the product as nutrition information, not a medical device |
| **Privacy** | Allergy and disease information is **health data** (GDPR Article 9, a special category). Explicit consent, data minimisation, the profile stored on the device by default, and never sent to Gemini as a *profile* — only the constraint sentences the analysis needs |
| **Kosher / halal** | Show only "contains ingredients not suitable for …", never "kosher" or "halal", unless certification data exists |
