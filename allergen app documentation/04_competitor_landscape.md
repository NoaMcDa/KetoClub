# 04 — Competitor landscape

*Source: research part 2.1. Status as the research found it (2026);
"alive/dead" is from app-store update dates and ratings it cited.*

## The matrix

| Competitor | What it does | Restrictions | Coverage & languages | Data source | Price | Central weakness |
|---|---|---|---|---|---|---|
| **Fig** | Barcode scanning + chain-restaurant lists | 2,800+ diets and ingredients; multiple profiles ("Multiple Figs") | US; English | Dietitians + product database | Free; Fig+ ~$10/month or $50/year | Mostly supermarket; restaurants only as chain lists; **no analysis of a free-form menu** |
| **Spokin** | Reviews, "Verified Restaurants" (a 27-question questionnaire), reports of hidden allergens | Allergies and celiac | ~73,000 reviews in 80+ countries; English | Crowd reviews + restaurant-supplied info | Free; restaurants pay for Verified | Depends on review density; **does not analyse your menu** |
| **Find Me Gluten Free** | Finds restaurants with a "safe" rating | Gluten only | Worldwide; 1M+ Android downloads, 4.7 rating | Crowd reviews | Free; premium ~$20–25/year | "Safe" ratings mislead ("not celiac" reviewers instead of a real cross-contact assessment); sparse outside cities |
| **HappyCow** | Vegan/vegetarian restaurant locator | Vegan/vegetarian; not gluten | 240,000+ listings, 185 countries, 12–18 languages | Crowd | Free / one-time ~$4; restaurants pay for listings | Ratings suspected of restaurant influence; acquired by a new owner in November 2025 |
| **AllergyEats** (Sirved) | Restaurant rating for allergies | Allergies | US | Crowd | — | **Nearly abandoned:** 1.0 rating, last update October 2023 |
| **Equal Eats** | Translation cards (chef cards) | 700+ allergens | 58 languages | Professional translation | Cards ~$16–19; app $14.99/month | Static; does not analyse menus |
| **Honeycomb.ai** | Predicts ingredients from dish name and description | 29 allergens, **only two in parallel** | Canada/US | Restaurant data + ML | Free + B2B | The two-restriction cap is exactly our gap; accuracy unverified |
| **EveryBite** (SmartMenu, with FARE) | Allergen filter embedded in the restaurant's own site | The big 9 and beyond | US chains (~250 chains, ~25,000 locations) | Restaurant-supplied content | B2B | Only restaurants that cooperate; no consumer app |
| **New AI apps 2025–2026:** FoodPickAI, Allergy Lens, SnackPro, Forkiee, Foodient, MenuSafe, Safe Eats AI (Israeli) | Photograph the menu, LLM, recommendation | Varies (MenuSafe: 66–72 allergens and severity levels) | Several languages (Forkiee "any language"; FoodPickAI Japanese and Chinese) | LLM inference | SnackPro from $5.99/month; others freemium | **No validation, no confidence score, no community; mostly very small** |
| **ChatGPT / Gemini, used directly** | Reads a menu | Anything | Any language | LLM | Free | Spokin itself recommends them as a "second pair of eyes". **The real competitor** — and it lacks profile memory, rules and accountability |
| **Uber Eats / DoorDash / Wolt** | Dietary filters and per-dish notes | Basic | Worldwide | The restaurant, optionally | — | Depends on the restaurant. In a 2026 survey about 80% offered only a free-text box and only 8% flagged allergens on DoorDash (Safe Plate Alliance). **Wolt has per-dish allergen fields but no personal filter.** Terms push responsibility to the restaurant |
| **Google Maps / Yelp** | Tags such as "vegan options" | Basic | Worldwide | Crowd + AI | — | Restaurant level only |

## Adjacent products (packaged food, not restaurants)

Yuka, the Monash FODMAP app, Fig, and in Israel the Celiac Association's
"gluten-free" app (barcode and product guide). Fig extends to restaurants
only through chain lists.

## Israel

No significant player in combined-restriction dining out. What exists:
**Safe Eats AI** (a single developer, two ratings), **EAT ID** (cards),
**UP2CHOICE** ("Coming Soon", B2B for restaurants). Wolt and 10bis/Cibus
have no personal integration. Israel is therefore a plausible pilot market —
small, Hebrew, but empty of competition, with Wolt and 10bis already
integrated in KetoClub.

## Does any competitor give a per-dish verdict plus a waiter instruction?

By the research's reading: **no.** Honeycomb.ai predicts ingredients per
dish but caps the profile at two restrictions and offers no instruction.
Equal Eats gives the instruction (a card) but is static and dish-blind. The
new AI apps give a per-dish recommendation but no explanation, confidence or
modification. KetoClub already does the whole chain for keto.
