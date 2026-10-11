# Allergen app documentation

Everything about turning KetoClub from a keto-only menu analyser into an
eating-out app for **every** dietary restriction: allergens, intolerances,
medical diets, religious and lifestyle diets.

## Where this comes from

The research in files 01–08 is a structured split of one source document:
*"אפליקציית אכילה בחוץ לכל הגבלה תזונתית: מפת הגבלות, מתחרים → KetoClub
ותוכנית פיצ'רים"* (7 pages, Hebrew, uploaded 2026-10-11). The source was a
desk-research report with inline citations (FDA, EU FIC 1169/2011, CDC MMWR,
Gallup, JACI, app-store listings, Reddit/Trustpilot complaints, vendor
sites). Its figures are reproduced here **as the source stated them, with
the source's own attribution**; they were not re-verified in this
session. Where the source flagged a number as weak (for example the
retracted lactose meta-analysis, or the 3×–4× spread in "free-from" market
estimates) the flag is kept.

Files 09 and 10 are new: 09 draws conclusions from the research against
the code that exists today (`architecture.md`, `lib/`, `backend/`), and 10
is the feature plan, written as one epic called **Allergens**.

## Files

| File | What it holds |
|---|---|
| `01_executive_summary.md` | The bottom line and the TL;DR of the source research |
| `02_regulated_allergens_by_jurisdiction.md` | The official allergen lists per country (US 9, EU/UK 14, Canada, Australia/NZ, Japan, Israel from 2028), the ~30-item union taxonomy, and the less common allergens worth modelling |
| `03_restriction_map_prevalence_severity.md` | Every restriction category with prevalence, severity, how well it is served when eating out, the market-size caveat and the recommended priority order |
| `04_competitor_landscape.md` | The competitor matrix (Fig, Spokin, Find Me Gluten Free, HappyCow, AllergyEats, Equal Eats, Honeycomb.ai, EveryBite, the 2025–26 AI apps, general LLMs, delivery platforms, Google/Yelp), adjacent products and the Israeli picture |
| `05_user_complaints_and_white_space.md` | The seven recurring user complaints and the seven gaps nobody fills |
| `06_differentiation_and_risks.md` | What KetoClub can offer that beats the field, and the legal, model, regulatory, store-policy, privacy and kosher/halal risks with their mitigations |
| `07_source_feature_plan_and_business_model.md` | The source research's own MVP / V1 / V2 plan, revenue model, retention levers, branding note and success metrics (kept verbatim in substance; the epic in file 10 refines it) |
| `08_open_questions.md` | The eight open questions the research ends with, plus the ones this documentation pass adds |
| `09_conclusions.md` | Conclusions: what the research means for KetoClub specifically, what the codebase already gives us, what has to change, and the decisions that must be taken before building |
| `10_epic_allergens.md` | **The epic.** Goal, non-goals, principles, phases, and every feature described in depth with data model, engine, UI, tests and acceptance criteria |

## How to read it

- In a hurry: `01`, then `09`, then the phase table at the top of `10`.
- Deciding whether to do this at all: `03` (who needs it), `04` + `05`
  (who else does it and how badly), `06` (what could go wrong).
- Building: `10`, with `02` open beside it for the taxonomy and `09` for
  the architectural constraints.

## Status

Research documented and concluded; epic written; **nothing built**. No
GitHub issues or milestone exist yet for this work. The epic is written
so each feature can become one issue under `ISSUE_CONVENTIONS.md` and the
whole epic one milestone under `MILESTONE_CONVENTIONS.md`.
