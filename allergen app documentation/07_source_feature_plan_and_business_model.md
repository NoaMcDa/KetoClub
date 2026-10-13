# 07 — The source research's own feature plan and business model

*Source: research part 4, kept in substance. The epic in file 10 refines,
re-orders and grounds this plan in the codebase; where the two differ, the
epic is the plan.*

## MVP (months 0–3): profile, menu analysis, confidence

- **Onboarding:** choose from the unified taxonomy; a severity per item;
  "exceptions" (e.g. baked milk is tolerated); priorities. *Gap it closes:*
  one restriction per app (Honeycomb's two-allergen cap). Keto stays as one
  option among many.
- **Data model:** an ingredient ontology with a mapping from each
  ingredient to each restriction, built on open sources such as FoodOn and
  Open Food Facts. A dish = a set of ingredients + the role of each
  (base, side, sauce, garnish).
- **Input:** text, link, menu photograph (OCR / vision). *Gap:* apps that
  rest only on reviews.
- **Output:** four states per dish — fits / fits with a change / ask /
  does not fit — with a confidence score and an explanation.
- **Questions for the waiter + substitutions** (the existing asset).
- **A benchmark against ChatGPT or Gemini with a bare prompt**, to show
  *why* the product is better than the free alternative.
- **Languages:** Hebrew, English, Spanish, French, German, Italian; menu
  analysis in every language.

## V1 (months 3–6): travel and community

- **Trip mode:** a chef card in the local language; "what must be
  disclosed here" by country; a lexicon of local risky ingredients. *Gap:*
  Equal Eats.
- **Group and family profiles.**
- **After-meal report:** "the waiter confirmed", "cross-contact?", a card
  for the model.
- **Allergen-matrix intake from chains** (California, UK, EU) as a
  "verified" layer.
- **GLP-1 / protein / small portions; FODMAP and histamine in restaurants.**

## V2 (months 6–12): delivery and B2B

- Analysis of a delivery-platform link or screenshot, and "copy an allergy
  note for the notes box".
- **B2B for restaurants:** "your menu by the 14 allergens", demand
  dashboards ("how many users searched for sesame-free near you"), and
  compliance with regulation such as SB 68.
- **Personal history:** "restaurants that worked for me" and menu-change
  alerts.

## Later

Platform partnerships; kosher/halal certification through an API; medical
diets with clinics.

## Revenue model

- **Free:** up to X scans a month, one restriction, basic waiter questions.
- **Premium, $4–8/month or $30–50/year:** unlimited scans, the combined
  profile, trip mode, group profiles, history. Reference prices: Fig
  $10/month or $50/year; SnackPro $5.99/month; Equal Eats $14.99/month;
  Find Me Gluten Free $20–25/year.
- **Trip pack:** one-time, priced per trip.
- **B2B:** important — **never let restaurants influence ratings** (the
  Spokin and HappyCow lesson).
- **Partnerships / affiliate** with delivery platforms only once there is
  usage data.

## Retention

The profile as the anchor ("all my restrictions in one place"); restaurant
history; community reports; trip mode before a holiday (a high-value
moment); the personal kitchen card as a habit.

## Branding

"KetoClub" is too narrow and alienates allergy users. The research
recommends a neutral, bilingual name pointing at "what can I eat here",
keeping KetoClub as a "keto mode" or a community inside the product. Before
deciding: check trademarks and domains.

## Success metrics

- **Activation:** full profile and first scan within 24 hours.
- **Retention:** D30 above 20%; at least 2 scans a week among active users.
- **The core assumption:** the share of users with 2+ restrictions.
- **Critical-miss rate** on a level-A test set, measured before launch.
- **Agreement rate** between the app's verdict and the waiter's confirmation.
- **Conversion to paid**; trip-mode usage; B2B: restaurants requesting
  verification.
