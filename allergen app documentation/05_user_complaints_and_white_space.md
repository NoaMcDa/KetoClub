# 05 — Recurring user complaints and the white space

*Source: research parts 2.2 and 2.3.*

## The seven recurring complaints (from reviews, Reddit, Trustpilot, press)

1. **Unreliable safety ratings** that rest on one person's experience ("I'm
   not celiac, it was fine") rather than kitchen procedures.
2. **Thin coverage** outside US metropolitan areas.
3. **One restriction per app.** A celiac who is also diabetic needs two apps;
   Honeycomb.ai caps a profile at two allergens.
4. **Paywalls on the core feature** — for example Fig limiting the number of
   reviews.
5. **Suspicion that restaurants influence ratings** (HappyCow).
6. **Abandonment and stale data** (AllergyEats).
7. **AI without quality control.** Niszczota & Rybicka (*Nutrition*, 2023)
   found ChatGPT recommending a nut-containing recipe for a nut allergy.
   Mathes et al. (*JACI: In Practice*, 2025) tested ChatGPT 3.5 on 56
   gluten-free dishes: 4 of 56 wrong (7.1%); on 120 allergy questions the
   average quality score was 4.1 of 5 but with 50 minor and 31 major errors,
   one of which — a formula recommendation for a cow's-milk-allergic infant —
   could lead to anaphylaxis.

## The white space (what nobody fills)

- **(a)** Dish-level analysis, in any restaurant, for a **combined profile
  with no cap** on the number of restrictions.
- **(b)** Outside the US and in **non-English languages**.
- **(c)** "**What to ask**", not just "what is allowed".
- **(d)** An **explained confidence score** per dish.
- **(e)** GLP-1, FODMAP and alpha-gal **in restaurants**.
- **(f)** A layer **above the delivery apps**, where the restaurant has
  opted out of the platform's allergen tools.
- **(g)** **Israel** as a pilot market.

## How KetoClub maps onto the complaints today

| Complaint | KetoClub today |
|---|---|
| 1 — ratings by experience | A verdict is computed per dish from the menu text; no crowd rating exists, so there is nothing to mislead — but also nothing verified by a kitchen yet |
| 2 — coverage | Any Wolt or 10bis venue, any pasted or photographed menu, any restaurant website; coverage is the menu's, not a review base's |
| 3 — one restriction | Keto plus three toggles (seed-oil free, dairy-free, carnivore). The seam for a combined profile exists (`ClassificationOptions.dietaryConstraints`), the profile does not |
| 4 — paywalls | No payments at all |
| 5 — restaurant influence | No restaurant input of any kind |
| 6 — staleness | A menu is refetched after 24 h; the analysis is recomputed when the menu or the options change |
| 7 — AI without control | **The strongest card:** an LLM answer is parsed by a never-throwing parser with eight rules (no invented dishes, no promotion of a yellow without an instruction), and a deterministic rules engine answers when the model cannot — but the rules engine is keto-only and the model has the last word while it answers |
