# Where else restaurant menus can come from: sources beyond Wolt, 10bis and ordering apps

Written 2026-09-24. KetoClub reads menus from two delivery platforms, Wolt
and 10bis, through their unofficial internal JSON endpoints (`menu_api_research`,
`architecture.md` §6.3), and has Tabit and Ontopo pencilled in as the next two
adapters. This report asks what else exists: every other place a restaurant's
menu can be obtained from, weighted towards Israel first and the rest of the
world second, with official and unofficial routes ranked side by side and the
legal exposure of each flagged. It ends with a recommendation and a build order
that fits the adapter architecture.

Sections: 1 summary · 2 how this was researched, and what it could not verify ·
3 the source catalogue (3.1 Israeli platforms, 3.2 restaurants' own websites and
PDFs, 3.3 licensed and commercial APIs, 3.4 open data, 3.5 social platforms,
3.6 vision and QR codes, 3.7 people as the source, 3.8 chain nutrition data) ·
4 legal and terms · 5 ranked comparison · 6 recommendation · 7 build order and
draft issues · 8 what only a machine with network access can settle · 9 sources.

## 1. Summary

**No licensed, official API anywhere returns menu items for Israeli
restaurants.** Every official places-style API (Google Places, Foursquare,
Tripadvisor, Yelp) stops at venue metadata and a few dietary booleans. Every
API that does return dish-level data is either North-America-only (MealMe,
Nutritionix, Spoonacular, Datafiniti), gated behind the restaurant's own
consent (POS and aggregator partner programmes, Google Business Profile's
FoodMenus, Wolt's merchant API), or a packaged scraper of the same Wolt data
KetoClub already reads (Apify, Bright Data).

What does exist, ranked by how much new Israeli coverage it would buy for the
effort and risk:

| Finding | Effect on KetoClub |
|---|---|
| **The restaurant's own website or PDF menu, extracted by Gemini vision with a JSON schema, is the only source that covers every Israeli restaurant**, including the dine-in-only ones that never appear on Wolt or 10bis. The backend, the structured-output prompt and `MenuResponseParser` already exist; what is missing is a URL-to-menu locator and an image part in the chat request. | Highest-value new adapter. It is also the engine behind three other paths below (QR codes, photographed menus, community uploads), so it should be built first. |
| **Wix Restaurants Menus (New) is the one third-party platform whose data model matches KetoClub's `Menu`** — sections, items, price variants, modifier groups with min/max rules, dietary labels — and Wix is Israeli and common among Israeli small restaurants. Its read methods are marked visitor-callable in Wix's own SDK, and every Wix site issues anonymous visitor tokens. Whether a stranger's backend may call a restaurant site's `_api/restaurants-menus-*` routes is technically plausible and unverified, and Wix's terms explicitly ban "page scrape" and any "robot, spider or other automatic device … or equivalent manual process" — the same contractual exposure class as today's Wolt and 10bis adapters, enforced by an Israeli company. | The compliant version — the restaurant installs a Wix app or authorises a headless client — is the structured route and belongs to the Phase 3 "restaurant submissions" milestone. An anonymous visitor-token detector inside the website adapter is a product decision about accepting Wolt-class risk for a second source, not an engineering one. |
| **Tabit and Ontopo remain the only Israeli platforms with structured menus outside delivery**, and both are still unverified: the Tabit endpoints in `menu_api_research` have zero hits in public code, and two open-source Ontopo clients disagree about whether `/slug_content` carries `menus[].sections[].items[]` or only a PDF URL. Ontopo's terms explicitly ban automated retrieval of content; Tabit's Israeli terms were unreachable. | Both are a one-afternoon probe from a machine with network access, before any adapter is written. Tabit is the higher prize (POS-grade modifiers, ~40% share of Israeli POS by its own claim). |
| **A QR code on an Israeli table resolves to a small set of shapes**: `tabitisrael.co.il/tabit-order?siteName=…`, a PDF on `static.rest.co.il`, a Wix site, an Israeli QR-menu SaaS page (tafryt, C-MENU, OurMenu), or an Instagram link. | The Scan tab (issue #11) is a URL classifier in front of the adapters above plus the vision path, not a new data source. |
| **Israeli chains publish real per-item nutrition**: McDonald's Israel (a nutrition calculator), Aroma (carbs per 100 g on every product page), KFC Israel (a PDF table). Nobody else found does. | Real carb numbers for a handful of chains, replacing `net_carbs_estimate` guesses. Small, self-contained, low legal risk. |
| **Google Places (New), Foursquare and OpenStreetMap are useful for finding venues and their website URL, not for menus.** Places' terms forbid caching anything but the place id (and lat/lng for 30 days), which collides with the 24-hour Hive cache. | Keep Wolt discovery (D13) as the primary; consider OSM (`website`, `website:menu` tags) as a free, cacheable seed for the website adapter. |
| **Hebrew is the differentiator in the vision path.** Verified: Azure Document Intelligence reads printed Hebrew, AWS Textract does not, PaddleOCR does not, Tesseract does but loses the leading digit of prices (measured in this repo's own M16 research), Surya claims 90.9% on Hebrew on its own benchmark. Gemini's vision Hebrew has no public benchmark. Text-layer extraction from Hebrew PDFs silently reverses 68% of documents in one measured corpus. | Prefer vision over PDF text layers for Hebrew, never show a scanned price as fact, and validate extracted Hebrew with the final-letter check (§3.6). |
| **The legal picture is consistent across US, EU and Israeli law**: dish names and prices are facts and thin compilations with little copyright protection, so the real constraints are contracts (terms of service), anti-bot measures and robots.txt. Logged-out reading of public pages is the defensible posture; creating accounts or bypassing access controls is not. Google's Maps Platform terms (read in full) forbid caching anything but the place id, feeding Google content into AI models, and use "in a listings or directory service". | Every source in §5 carries a risk rating; §4 has the reasoning and the hygiene rules. The one structural risk is Phase 3's community database: storing KetoClub's own verdicts keyed by venue id is fine, storing copied menu text is a redistributed compilation. |

One operational finding surfaced on the way: the backend pins
`GEMINI_MODEL=gemini-2.5-flash`, and third-party trackers report Google has
scheduled that model's retirement for October 2026 with conflicting dates
(16 or 20 October, or "no date"). It could not be confirmed against Google's
own deprecations page from here. Any vision work depends on the pin moving, so
it is the first item in §7. A second: a May 2026 network-sniff report on
GitHub corroborates `phase2_discovery_research.md` §2.5 — Wolt's
`/v4/venues/slug/{slug}/menu/data` "returns HTTP 200 with `content-length: 0`
via CloudFront even with browser-like headers", while
`consumer-api.wolt.com/order-xp/web/v1/venue/slug/{slug}/dynamic/` still
answers with `Referer: https://wolt.com/` and `Platform: Web` headers. That
makes issue #22's fixture recording more urgent than anything in this report.

## 2. How this was researched, and what it could not verify

Five parallel research passes (Israeli non-delivery platforms; licensed and
commercial APIs; the open web and open data; vision, QR codes, crowdsourcing
and chain nutrition; legal terms) were run on 2026-09-24 with web search and
page fetching. The sandbox's egress proxy blocked almost every primary host
that mattered: every `.co.il` domain tried, `ontopo.com`, `tabit.cloud`,
`dev.wix.com`, `developers.google.com`, Yelp, Tripadvisor, Foursquare, Apify,
Bright Data, `schema.org`, `webdatacommons.org`, `arxiv.org`, Hugging Face,
Kaggle, Meta's developer site and most law-firm sites. Reachable: `github.com`
and raw GitHub files, `registry.npmjs.org`, `cloud.google.com`,
`developer.apple.com`, and search-engine result snippets. The search budget ran
out near the end of three of the five passes.

So every claim below carries one of three evidence levels, and the tables use
them:

- **verified** — read from a fetched page, file or SDK (mostly GitHub-hosted
  docs, open-source clients and published npm packages).
- **snippet** — quoted by a search-engine snippet of the primary page, which
  itself could not be opened.
- **unverified** — could not be checked from here; a lead, not a fact.

Nothing in this report was confirmed by a live call to any Israeli site. §8
lists the calls that would settle the open points, most of them thirty minutes
of work from a laptop.

## 3. The source catalogue

### 3.1 Israeli platforms that are not delivery apps

**Wix Restaurants Menus (New).** Wix's current restaurant-menu product. The
API contract was verified from Wix's own published SDK packages
(`@wix/restaurants_menus@1.0.65`, `_items@1.0.57`, `_sections@1.0.56`,
`_item-modifier-groups@1.0.59`, `_item-modifiers@1.0.72`,
`_item-variants@1.0.46`, `_item-labels@1.0.43`, all re-exported by
`@wix/restaurants@1.0.529`, fetched from npm 2026-09-24):

- Read methods carry `@applicableIdentity VISITOR`: `getMenu`, `listMenus`,
  `queryMenus`, `getItem`, `listItems`, `queryItems`, `getSection`,
  `listSections`, `getModifierGroup`, `listModifierGroups`,
  `queryModifierGroups`, `getModifier`, `queryModifiers`, `getVariant`,
  `queryVariants`, `getLabel`, `listLabels`. An anonymous site visitor may call
  them (verified).
- Routes: `/v1/menus`, `/v1/menus/query`, `/v1/menus/{menuId}`, resolved on a
  live site under the prefix `/_api/restaurants-menus-menu` and on
  `www.wixapis.com` under `/restaurants/menus-menu` (verified from the SDK's
  HTTP resolver). The item, section and modifier prefixes will be analogous
  but were not extracted.
- Data shape (verified from the type definitions): `Item { name, description,
  image, labels[], priceInfo.price | priceVariants[], modifierGroups[],
  visible }`; `ModifierGroup { name, modifiers[{id, preSelected,
  additionalChargeInfo}], rule{required, minSelections, maxSelections} }`;
  modifier names live in a separate entity. **Option text — "choice of side"
  — is present**, as the modifier group's name plus its modifiers' names,
  which is exactly what `DishOption` carries today. Assembling one menu takes
  four or five calls. Prices are strings; currency comes from the site.
  Language is whatever the owner typed, so Hebrew on Israeli sites.
- Auth: a visitor access token from the site's own
  `https://<site-domain>/_api/v1/access-tokens` endpoint. That anonymous
  endpoint is used by several independent open-source projects (verified),
  but nobody was seen using it against the restaurants routes specifically
  (unverified). The sanctioned routes are a Wix App the owner installs or a
  Wix Headless OAuth client the owner creates.
- CORS: unknown; assume the backend must proxy, as it does for Wolt.
- Terms: Wix's terms of use prohibit any "robot, spider or other automatic
  device … to access, acquire, copy or monitor any portion of Wix's Services"
  (snippet). Reading a stranger's site's `_api` is feasible and a terms
  violation; the owner-installed app is the compliant route.
- The old public API (`api.wixrestaurants.com/v2`, which by design needed no
  auth for menus) was deprecated and removed in August 2022 (verified from
  Wix's GitHub repo). Do not build on it.
- Israeli coverage: Wix is Israeli, bought the Israeli online-ordering
  start-up OpenRest to build this product (snippet), and is common among
  Israeli small businesses. How many Israeli restaurants use the Menus app
  rather than a PDF or an image is unquantified.

**Ontopo.** Israel's main reservation platform. Two open-source clients
(`erezd/ontopo-mcp`, `alexpolonsky/agent-skill-ontopo`, both read 2026-09-24)
agree on the endpoints: base `https://ontopo.com/api`; `POST /loginAnonymously`
returns a 15-minute JWT; `GET /venue_search`, `GET /venue_profile?slug&locale`,
`GET /slug_content?slug&locale` (called without auth), `POST
/availability_search`; the Israel distributor slug is `15171493`. Neither uses
the `GET /api/venue/{venue_id}` route in `menu_api_research`. They disagree on
menus: one has a `menu` command that reads `menus[].sections[].items[]` with
`name/description/price` from `/slug_content` (hedging on the key name, which
suggests the author saw it in some responses), the other documents
`venue_profile` as returning only title, address, phone, logo, geolocation,
price band and pages. Ontopo does serve per-venue web menu pages
(`ontopo.co.il/en/{slug}/menu`). No modifiers anywhere. The client handles
`429`, so rate limits exist. Terms unreachable. Verdict: high confidence on
the endpoints, low on menu content — a ten-venue probe settles it.

**Tabit.** Israeli POS with a claimed market share "over 40 percent"
(snippet, marketing). There is no public developer portal, API reference or
authentication scheme; integrations go through a certified partner programme
(verified, api-evangelist profile dated 2026-06-21). The two endpoints in
`menu_api_research` §3.3 (`tgp-api.tabit.cloud/menu/v2/{site_id}`,
`online.tabit.cloud/api/v1/ordering/menu?siteId=`) have **zero hits in GitHub
code search** and the hosts are blocked, so they are unverified. What is
verified from public links: the consumer ordering page is
`https://tabitisrael.co.il/tabit-order?siteName={slug}` (a US mirror uses
`tabit.us/tabit-order?orgName=`), and Tabit Pay's QR-on-the-bill lives at
`pay.tabit.cloud`. The SPA fetches JSON, so a menu endpoint exists; a browser
capture on a real `tabit-order` page is what `architecture.md` §17 open
question 3 has always needed. If reachable, this is the best dine-in source in
Israel: POS-grade modifiers, forced questions ("choice of side"), allergen
flags.

**Zap Rest (rest.co.il).** Israel's largest restaurant directory: "over 12,000
restaurants", "approximately 1,500 interactive menus" (snippet, marketing).
Page pattern `https://www.rest.co.il/rest/{8-digit id}/`; menu PDFs at the
predictable `https://static.rest.co.il/{id}/{ddmmyyyy}/menu.pdf` and
`…/{id}/site/menu.pdf` (pattern verified from search listings; the text-layer
status of the PDFs is unknown). No API found. Owner-uploaded, so freshness is
poor, and no modifiers. A Zap Group ad-supported property, so assume scraping
is prohibited. Its main value is as a QR-code target (§3.6): the PDFs feed the
vision path.

**Israeli QR-menu and POS vendors (all unverified — hosts blocked).** C-MENU
(`cmenu.co.il`, per-table QR), OUR MENU (`ourmenu.co.il`), tafryt
(`menu.tafryt.co.il/{chain}` — Greg's chain menu lives there), Digital Menu,
Chipit, qrmenu.co.il, and Beecomm POS (`orders.beecommcloud.com`, "thousands of
restaurants", marketing; Beecomm also ships a Wix app, so Beecomm menus may
already sync into Wix Restaurants Menus). Each hosts per-restaurant web menus
that must fetch JSON from somewhere; none documents an API and GitHub has no
code for any of them. "Presto", "Menu Pad" and "Caspit" produced no Israeli
menu evidence at all; treat them as non-existent for this purpose.

**Cibus / Pluxee and Goodi.** Corporate meal-card apps with ordering menus
behind employee logins (verified from two open-source automation projects for
`consumers.pluxee.co.il`; "Pluxee's API is undocumented"). Reading them means
operating inside someone's financial account. Not a source.

**Easy (easy.co.il), TimeOut, Eatwith, 2eat, Tapuz, kosher directories.**
Listings, hours, reviews, editorial picks; no menus, no APIs. Not sources.

**Israeli chains' own sites.** Covered in §3.8, because their value is the
nutrition tables rather than menu coverage — every chain found is already on
Wolt or 10bis.

### 3.2 Restaurants' own websites and PDF menus (the open web)

**schema.org `Menu` / `MenuItem` markup.** The vocabulary exists
(`Restaurant.hasMenu` → `Menu` → `MenuSection` → `MenuItem` with `offers.price`,
`nutrition`, `suitableForDiet`), and Web Data Commons extracts all schema.org
markup from Common Crawl yearly (adoption grew from 3.1% of domains in 2013 to
37.9% in 2022; snippet). Whether a `Menu` subset exists with meaningful counts
could not be checked (site blocked). The practitioner evidence is
discouraging: a 2026 scraper's notes say JSON-LD "carries only name /
description / offers.price" and "silently dropped four whole categories" on a
sampled restaurant (verified, GitHub); a heuristic menu-finder pipeline tries
JSON-LD first and then four other fallbacks (verified). Google gives `Menu` no
rich result and sources its dish-level data through the owner-only Business
Profile FoodMenus API, so restaurants have little SEO incentive to publish
dish-level markup. No evidence was found that Wix, Squarespace, Popmenu, Toast
or Owner.com emit `MenuItem` JSON-LD; BentoBox emits restaurant-level schema
(snippet). There is no modifier-group concept in schema.org. Verdict: a
trivial parser worth running first on any page, expected to hit rarely.

**Website platforms with predictable public JSON.**

| Platform | Public JSON without owner credentials? | Modifiers | Israel | Evidence |
|---|---|---|---|---|
| Wix Restaurants Menus (New) | Plausible via visitor token (§3.1); unverified | Yes | Common | verified SDK, unverified live |
| Toast online ordering | Historically yes: `window.OO_GLOBALS` → unauthenticated GraphQL `MENUS` on `ws.toasttab.com/consumer-app-bff`; a 2026 report says it now sits behind a Cloudflare interstitial that curl and headless Chrome cannot pass | Yes | None found | verified (GitHub scrapers, 2026 note) |
| Square Online | Storefront `__BOOTSTRAP_STATE__` plus an unauthenticated store API on `cdn5.editmysite.com`; modifiers only by opening each item modal | Partial | Square does not operate in Israel | verified scrapers |
| Popmenu | No — GraphQL schema is auth-gated; DOM scraping only | No | None | verified (api-evangelist) |
| BentoBox | No public API; DOM classes `.bb-*`, partial JSON-LD | No | None | verified |
| Owner.com | Nothing found either way | — | None | unverified |
| Squarespace Menu Blocks | Formatted text, no JSON, no schema by default | No | Negligible | snippet |
| Untappd for Business | JSON only on the paid tier with a token; beer menus | — | — | snippet |

**A practical website-to-menu pipeline for 2026**, synthesised from the
open-source pipelines read:

1. Resolve venue → website URL (OSM `website` / `website:menu`, Google Places
   `websiteUri`, the venue page on Wolt or 10bis, a pasted URL, a QR code).
2. Fetch the homepage, respecting `robots.txt`; look for JSON-LD `hasMenu`,
   links matching `/menu`, `תפריט`, `.pdf`, or known hosts (Wix `_api`,
   Tabit, tafryt); read `sitemap.xml`; if JavaScript-rendered, use a headless
   browser and intercept the menu XHR, which is "usually cleaner JSON than
   anything you could scrape from the rendered result".
3. Extract: structured route if one matched; otherwise HTML → markdown → Gemini
   with a `Menu` JSON schema; PDF and image menus → render pages to images →
   Gemini vision with the same schema. Tools: Crawl4AI (Apache-2.0, Docker
   image, has an LLM extraction strategy and a PDF strategy), Firecrawl (hosted,
   from about $16/month), Jina Reader (URL → markdown, free tier), docling
   (MIT), marker (code Apache-2.0, model weights free only under $5M revenue).
4. Validate with `MenuResponseParser`'s rules unchanged, cache 24 hours as
   today.

Cost: a three-page menu as images plus a 1,500-token JSON reply is well under
one cent on Flash-class Gemini (§3.6 has the arithmetic).

**Hebrew and RTL pitfalls in PDF text extraction (important).** Firecrawl's
`pdf-inspector` found **68% of Hebrew documents in a 179-PDF corpus were
extracted character-reversed**, as valid UTF-8 with no warning, because Hebrew
has no presentation-form codepoints that betray visual order; their first fix
detects misplaced word-final letters (ך ם ן ף ץ) document-wide (verified, PR
filed 2026-08-07, superseded by a geometric fix merged 2026-08-21). PyMuPDF
below 1.24 returned RTL text reversed and 1.24+ returns logical order, while
pdfium does not reorder at all, so a fix written for one library breaks the
other (snippet). Digits are weak bidi types and are not reordered inside an RTL
run, which is exactly where "₪ 68" and mixed Hebrew/English dish names break.
Practical rules: prefer vision over text layers for Hebrew; if extracting text,
use PyMuPDF 1.24+ and never apply a bidi library blindly; treat a Hebrew word
that *begins* with a final-form letter as proof the text is reversed.

### 3.3 Licensed and commercial APIs

| Source | Returns menu items? | Israel | Cost | Terms on caching and derived data | Still alive in 2026? |
|---|---|---|---|---|---|
| **Google Places API (New)** | No. Dietary booleans only (`servesVegetarianFood`, `menuForChildren`, `serves*`), summaries, photos, `websiteUri`; no menu URL, no "menu" photo category | Yes | 1,000 free Enterprise calls/month since March 2025, then ~$40 per 1,000 for Enterprise + Atmosphere (snippet) | **Verified** from the Maps Service Terms (2024-05-22): lat/lng cacheable 30 days, `place_id` indefinitely, nothing else; attribution required; no derived datasets | Yes |
| Google Business Profile `foodMenus` | Yes — sections, items, price, allergens, nutrition | n/a | Free | Owner-only OAuth (`business.manage`); not a third-party read | Yes |
| **Foursquare Places** | No — `price`, `tastes`, `features`, photos, tips; a menu URL field may survive from v3 (unverified) | Yes | Pro $15 per 1,000; free allowance 500 (change notice) vs 10,000 (marketing page) — the two disagree; legacy v3 deprecated 15 May 2026 | Not verified | Yes; FSQ OS Places is an open POI dataset with no menus |
| **Tripadvisor Content API → Terra** | No — cuisine, price level, dietary flags | Yes | 5,000 free/month (legacy); Terra 1,000 free then pay-as-you-go | Attribution; AI-use clauses unverified | Legacy sunset reported 31 Aug 2026, Partner API 30 Oct 2026 (third-party trackers) |
| SinglePlatform (Tripadvisor "Menu Connect") | Was a restaurant-pays menu *syndication* service; no developer data licence | — | — | — | Dormant since 2020; site redirects |
| **Yelp Fusion** | No (attributes; a menu URL is unverified) | **No — Yelp has no Israel market** | $7.99–14.99 per 1,000 | 24-hour cache limit, attribution, analysis non-commercial only | Yes |
| MealMe | Yes, with options (aggregated delivery menus) | No — US and Canada | Unpublished | — | Yes |
| Nutritionix / Spoonacular / Edamam / FatSecret | US chain nutrition items, not venue menus | No Israeli venues | $299+/month; free–$149/month; n/a; free basic | Attribution | Yes |
| OpenMenu | Claims 550K menus, 25M items, kosher/GF tags | Unknown, probably none | Credit tiers with a free tier | Unverified | Appears live (profile dated June 2026); probe the sandbox for Tel Aviv before spending time |
| Datafiniti | Partial (`menus.*` name/description/price fields) | Unlikely | Per record | Unverified | Yes |
| Zomato public API | Dead; POS partner integration only | Never | — | — | No |
| Apify Wolt actors | Yes — items, prices, options, dietary tags, "961 cities in 30 countries" with Israel listed | Yes | ~$0.8–3 per 1,000 venues plus per-item | Same Wolt-ToS footing as today's adapter, plus Apify's terms | Yes |
| Bright Data Wolt dataset | Yes — items, prices, descriptions; no option groups seen in the scraper README (verified) | Probable | From $250/month | Same | Yes |
| Outscraper / ScrapeHero | Google Maps `menu_link` column only; no menu product | Yes / — | ~$3 per 1,000 | Google ToS | Yes |
| Apify Google Maps menu scrapers | AI vision over Maps menu photos; vendors warn of "misread names, wrong prices, invented or missing items" | Yes | Per result | Google ToS | Yes |
| **POS and aggregator partner APIs** (Toast, Square, Clover, Lightspeed, Deliverect, Otter, Chowly, Olo, **Wolt Merchant Menu API**) | Yes, full items with modifier groups | Mostly no; Wolt merchant API yes | Partner agreements | Every one requires the restaurant to authorise the integration | Yes |

The reading across this table: for Israeli **menu text** nothing licensed
replaces the Wolt and 10bis endpoints, and the only alternatives are packaged
scrapers of the same Wolt data, which add a vendor and a cost without adding
legitimacy. For **discovery and enrichment** Google Places is the strongest,
but its no-caching rule collides with the Hive cache and with storing a derived
verdict; Foursquare's new API and FSQ OS Places are the more permissive fallback
if the Wolt discovery proxy proves fragile. One side use: an Apify Wolt actor
is the cheapest way to obtain a real recorded Wolt payload for the synthetic
fixture problem (issue #22) from a machine that cannot reach Wolt directly, if
that provenance is acceptable.

### 3.4 Open data

| Source | Menu items? | Israel | Use for KetoClub |
|---|---|---|---|
| OpenStreetMap | No. `amenity=restaurant` carries `cuisine`, `diet:*`, `website`, and optionally `website:menu=*` ("the full URL to the official menu … HTML always preferred", snippet); tag counts unverified | Overpass works; a Tel Aviv extractor exists on GitHub | A free, ODbL-attributed seed of venue → website URL for the website adapter, cacheable without Google's restrictions |
| Wikidata | No; only notable chains | Dozens of items | Negligible |
| Open Food Facts | Confirmed out of scope — packaged products only | — | Net-carb lookups for branded packaged items sold in cafés at most |
| Yelp Open Dataset | No items; 200,100 photos labelled `food/drink/menu/inside/outside`, 11 US/Canadian metros | None | Thousands of labelled menu photos to evaluate a menu-photo vision path; licence academic (unverified) |
| Kaggle Uber Eats USA | Yes — 63K restaurants, 5M+ rows (name, category, description, price), no modifiers, ~2022 snapshot | None, English only | A classifier test corpus (heuristic-vs-LLM agreement at scale), not a source |
| Common Crawl / Web Data Commons | Raw pages / JSON-LD extracts | `.co.il` present, shallow | Bootstrapping a list of Israeli restaurant domains; stale by months |
| Wayback Machine | Historical snapshots | Depends | Not a live source |

### 3.5 Social platforms

- **Instagram.** The Graph API serves only business accounts you manage; there
  is no endpoint to read another restaurant's profile or a "menu". Profile
  buttons are "Order Food" links out to Wolt. Menus live in photos and
  highlights, reachable only by scraping the web app, which Instagram's
  anti-bot posture makes unreliable even where it is lawful (§4). Last-resort
  OCR fallback only.
- **Facebook Pages.** A "Menu" tab where owners upload PDFs, photos or a link;
  the legacy `restaurant.menu_section` object and `restaurant_services` fields
  exist in the docs, but no public read of a Page's menu could be verified, and
  the v18 Pages API was deprecated in January 2026 (snippet).
- **Google Maps menu tab.** Google assembles it from delivery apps (Wolt is a
  likely provider in Israel), aggregators, owner edits, user-uploaded photos
  and "transcribed from your business website"; the Places API exposes none of
  it as fields. Scraping the Maps UI violates the Maps Platform terms and, in
  Israel, would mostly return the Wolt data KetoClub already has.
- **TikTok.** Research API for academics only. Not realistic.

### 3.6 Vision paths: photographed menus, PDFs and QR codes

**Engines, with Hebrew support as the deciding column.**

| Engine | Hebrew | Structured output | Cost | Evidence |
|---|---|---|---|---|
| **Gemini 2.5 / 3 Flash and Pro** (through the existing backend) | Text Hebrew: yes, already exercised by the app's prompt. Vision Hebrew: **no public benchmark found**; the April 2026 paper *GlotOCR Bench: OCR Models Still Struggle Beyond a Handful of Unicode Scripts* (arXiv 2604.12978) is the warning, unread from here | Yes, JSON via `responseSchema` | 2.5 Flash $0.30 in / $2.50 out per 1M tokens; 3 Flash $0.50 / $3.00; an image is ~260–1,100 input tokens and a 40-dish JSON reply ~1,500–3,000 output tokens, so **≈ $0.005–0.01 per page, output-dominated** (rates are snippets, arithmetic is ours) | OmniDocBench v1.6 (verified): Gemini 3 Pro 92.91 overall, 3 Flash 92.62, Mistral OCR 85.66, Marker 78.44; specialised open models lead at 95+ |
| Google Document AI OCR | Printed Hebrew (`iw`/`Hebr`) listed; handwriting not (snippet) | No — boxes and text; still needs the LLM | $1.50 per 1,000 pages | Adds geometry for row-to-price association |
| Azure Document Intelligence Read/Layout | **Printed Hebrew `he`: yes (verified from Microsoft's docs). Handwriting: no Hebrew (verified)** | No — boxes, lines, words, confidence | $1.50 per 1,000 pages, 500 free/month | Same role as Document AI |
| AWS Textract | **No Hebrew** (six languages) | — | — | Ruled out |
| Mistral OCR 3 | "90+ languages"; Hebrew never named (unverified) | Markdown plus annotations; markdown is a bidi hazard for RTL | $2 per 1,000 pages, batch $1 | Untested for Hebrew |
| Tesseract 5 `heb` (on-device) | Yes, weak; **measured in this repo** (`m16_menu_scanner_research.md` §5, §10.2): 9/23 dish names character-perfect, 19/23 ≥ 0.70 similarity, **2/23 prices correct**, the rest losing the leading digit (28→8, 52→2) | No | Free | Dish names usable, prices not |
| Surya OCR 2 / marker (self-hosted) | 90.9% on Hebrew on Datalab's own 91-language benchmark (verified, not independent) | marker: markdown/JSON | GPU server; weights free under $5M revenue | Best open number found; RTL unstated |
| PaddleOCR PP-OCRv5, docTR, olmOCR 2 | No / not mentioned / English-tuned (verified) | — | — | Ruled out |
| ML Kit, Apple Vision on-device | Not Hebrew (from memory, unverified) | — | — | Do not rely on |

**Failure modes documented across every engine**, and what they mean for a
menu: multi-column sections collapsed into one stream or interleaved; a price
attached to the wrong row when dish and price are far apart; leading-digit loss
on Latin digits inside Hebrew (measured); vision models **silently omitting
rows** ("forty rows might return only thirty-eight with no visible gap") and
producing fluent, plausible wrong prices instead of visible garbage; no cloud
engine verified here reads Hebrew handwriting, so specials boards are out; low
light, glare, curl and crop at frame edges (the four failed names in the M16
measurement were the bottom of the photo). Yelp and DoorDash both say the same
thing about their photo pipelines: the limit is the photo, not the model. The
M16 rule stands: **never present a scanned price as fact.**

**What a QR code on an Israeli table resolves to (2026).** From public links,
in rough order of frequency (proportions unverified): a Tabit ordering page
(`tabitisrael.co.il/tabit-order?siteName=…`); a PDF on `static.rest.co.il`
or any other host; a Wix site's `/menu` page; an Israeli QR-menu SaaS page
(tafryt, C-MENU, OurMenu, qrmenu.co.il); a Google Drive PDF, Linktree or
Instagram profile. So the Scan tab is a URL classifier: Tabit → the Tabit
adapter once it exists; `.pdf` → text layer if it passes the final-letter
check, else render and send to vision; Wix → the structured route, else the
rendered page to vision; everything else → screenshot → vision.

### 3.7 People as the source: community uploads and restaurant self-serve

**Crowdsourced menu photos.** Google Maps auto-labels photos "Menu" and lets
users flag stale ones and upload replacements; Yelp's "Menu Vision" transcribes
user- and business-uploaded photos and warns they are "dim, angled, glare-y, or
partial"; Zomato ran OCR plus a formal menu-moderation queue; HappyCow reviews
every submission manually and rewards ambassadors; Untappd's menus come only
from paid verified venues. The best-documented precedent is Open Food Facts
(verified from its docs): photos typed by role, only the latest *selected*
photo per role displayed, a CC-BY-SA licence on contributions, machine-generated
insights "applied automatically, or after a manual validation", and years of
OCR-typo pain that an LLM spellcheck finally cut by 11%. A KetoClub flow would
need: per-venue menu versions (photo set plus one extraction; `data_source =
manual` already exists in the schema); provenance (install id, timestamp, a
coarse location match via `LocationService`); a hold-for-review window for new
contributors; deduplication by perceptual hash plus dish-name overlap, merging a
duplicate as a "re-confirmed on …" rather than a new version; a freshness badge
and a re-shoot nudge after ~90 days; report, takedown and owner-override
controls; a blur/brightness gate at capture, because every precedent names
photo quality as failure mode one. Note that community versions live
indefinitely, unlike the 24-hour cache, and need an audit trail.

**Restaurant self-serve.** Google Business Profile's owner-only FoodMenus API
and menu link, and Wix's owner-authorised Menus API, are the two structured
routes a restaurant could open to KetoClub. The verification problem is real
(reservation-app impersonation scams are documented) and postcards do not
scale; what a one-developer app can afford is an OTP to the phone number Wolt,
10bis or Google already list for the venue, or a code posted temporarily in the
venue's Instagram bio. The incentive has to be concrete: the
`is_verified_keto_friendly` badge already in the schema, plus the ability to
correct a community extraction. This is Phase 3's "restaurant submissions"
milestone (`backend_plan.md` §5 milestone C), not a data purchase.

### 3.8 Chains' own nutrition data — real carb numbers

| Chain | Per-item nutrition published? | Where | Shape |
|---|---|---|---|
| **McDonald's Israel** | Yes — "מחשבון תזונה", allergens and nutrition for every product, recomputed when ingredients are removed | `mcdonalds.co.il/מהפיכת_התזונה/מחשבון_תזונה`, `order.mcdonalds.co.il/nutrition-calculator` | JavaScript calculator; underlying JSON unknown (snippet) |
| **Aroma** | Yes — every product page carries nutrition, e.g. carbs per 100 g, with a "deviation up to 20%" disclaimer | `aroma.co.il/מוצרים/{id}/{slug}/`, `aroma.co.il/menus/` | HTML product pages on WordPress, scrapable; a `wp-json` surface may exist (unverified) |
| **KFC Israel** | Yes — nutrition and allergen table | `kfc.co.il/wp-content/uploads/2024/05/28068_Allergic_Table_he.pdf` | PDF table (snippet) |
| Cafe Cafe | PDF menus; a dietitian-calculated low-calorie menu; per-item carbs not found | `cafecafe.co.il/Warehouse/…/תפריט בשרי.pdf` | PDF |
| Burger King IL, Cofix, Greg, Landwer, BBB, Moses, Japanika, Giraffe, Sushi Rehavia, Yotvata | Nothing per-item found | Greg on `menu.tafryt.co.il/greg`, Japanika HTML menu | Menus without nutrition |
| Israeli aggregators | foodiepedia.co.il has chain pages "from manufacturers" with a no-accuracy disclaimer; foodsdictionary, kaloria are packaged-goods oriented | HTML | Secondary |
| Global | McDonald's has no public API (an undocumented per-market one is wrapped on GitHub); Nutritionix carries US chain menus; Starbucks and Subway publish PDFs and web tables | — | Mixed |

Context: Israel's 2017–2020 labelling reform is front-of-pack for
*prepackaged* food; no Israeli restaurant menu-labelling mandate was found. US
FDA labelling covers chains of 20+ units, which is why US chain data exists and
Israeli franchises publish voluntarily. For KetoClub, three chains' real carb
numbers would replace estimates on exactly the dishes people ask about most
(a bunless burger, a coffee with milk), at low legal risk and low effort per
chain — but chains change items and Aroma's own disclaimer is ±20%.

## 4. Legal and terms

Background for engineers, not legal advice. The one document read in full
was Google's; everything else is a mirror, a snippet or, where marked, a prior
belief to check.

### 4.1 Copyright in a menu is the weakest claim against copying it

- **US.** *Feist v. Rural* (1991): facts are not copyrightable; a compilation
  is protected only in its original selection and arrangement. Applied to
  menus by several practitioner sources: dish names, ingredients and prices
  are facts; elaborate descriptions, photos and layout are protectable; a
  plain standard menu is not (snippet).
- **Israel.** Copyright Act 5768-2007 §4(b): copyright in a compilation
  "extends to the originality of the selection and arrangement of the data …
  not to the discrete data items"; §5 excludes "facts or data" outright; the
  Supreme Court in *Interlego v. Exin-Lines* adopted *Feist* and rejected
  sweat-of-the-brow (snippet, WIPO Lex and practice guides). Israel has no
  sui generis database right (unverified). So an Israeli restaurant's list of
  dishes and prices is unprotected data; its prose, photos and design are the
  restaurant's works — not Wolt's or 10bis's, who are licensees.
- **EU.** Database Directive 96/9/EC gives a sui generis right over
  substantial investment in obtaining or presenting contents; *Ryanair v PR
  Aviation* (C-30/14) lets a site restrict re-use by contract even when the
  database is unprotected; DSM Directive Art. 4 permits commercial
  text-and-data mining unless reserved "in machine-readable means", which in
  practice means honouring robots.txt and TDM-reservation signals. Relevant
  only for EU users or EU-hosted databases (Wolt is Finnish).

### 4.2 Scraping public pages: contract and circumvention are the live risks

- *hiQ v. LinkedIn*: the Ninth Circuit (2022) held public-page access is not
  "without authorization" under the CFAA, yet hiQ lost on breach of contract
  and paid a $500,000 consent judgment (fake accounts). Public is not free.
- *Meta v. Bright Data* (N.D. Cal., 2024): Meta's terms did not reach
  logged-out scraping of public pages because a non-user did not "use" the
  products. *LinkedIn v. ProAPIs* (consent judgment 2026-09-21) permanently
  bars scraping done with fake accounts.
- **Israel.** No scraping-specific judgment was found. Relevant statutes to
  check: Computer Law 5755-1995 §4 (unlawful access to computer material),
  the Unjust Enrichment Law, and the Privacy Protection Law (Amendment 13,
  in force August 2025) for any personal data such as reviews. A Petah Tikva
  Magistrate's Court decision (2013) treated RSS republication with
  attribution and takedown-on-request as non-infringing; a 2025 High Court
  case shows Israeli courts treat access conditions as enforceable contract
  terms (snippets).
- **robots.txt** (RFC 9309) is voluntary and "does not form a contract", but
  courts and regulators read it as evidence of the operator's intent and it
  is the machine-readable reservation the EU regime looks for.

The bottom line for engineers: the exposures that matter are (1) breach of a
platform's terms where the app or its users are bound, (2) circumvention of
technical measures (Cloudflare, CloudFront, tokens), (3) explicit anti-bot
clauses enforced by Israeli companies (Wix, Ontopo, 10bis), and (4) any
*stored, shared* dataset, which turns an ephemeral per-user fetch into a
redistributed compilation. Phase 3's community database is where (4) bites.

### 4.3 Per-source terms

| Source | Governing document | Third-party read allowed? | Caching limit | Attribution | Risk |
|---|---|---|---|---|---|
| **Wolt** (today's adapter) | `wolt.com/en/terms` and country pages (snippet); `developer.wolt.com` merchant Menu API | **No.** The terms "strictly forbid" any "robot, spider, web crawler, extraction software, automated process" to "scrape, copy and / or monitor" the service, and bar collecting or transferring information obtained from it. The official Menu API is merchant/POS-only with credentials from an account manager. A May 2026 network-sniff report on GitHub says `/v4/venues/slug/{slug}/menu/data` now returns `200` with `content-length: 0` via CloudFront even with browser headers, while `consumer-api.wolt.com/order-xp/web/v1/venue/slug/{slug}/dynamic/` still answers with `Referer` and `Platform: Web` headers — Wolt is actively defending these endpoints (mirror). | None granted | None specified; label anyway | **High** for anything stored server-side or redistributed (the proxy cache rehosts menu JSON); **medium** for a per-user, on-demand fetch on device |
| **10bis** (today's adapter) | `10bis.co.il/next/terms` (not fetched); shop terms (snippet) | **No** (expected). Copying or storing content beyond "private, personal non-commercial use" is prohibited in the shop terms; the consumer terms' automation clause is unverified but standard Israeli boilerplate | None granted | None specified | **High**; Israeli forum. Verify the consumer text before release |
| **Tabit** | `legal.tabit.cloud` IL and US documents (not fetched) | Unverified. The data is the restaurant's POS data hosted by its vendor, served to diners at the table; Tabit's contract with the restaurant, not the public, governs it | Unknown | Unknown | **Medium–high** until the IL terms are read |
| **Ontopo** | `club.ontopo.co.il/help/terms`, `ontopo.co.il/en/settings/terms` (snippet) | **No.** Users may not use "automated tools or means to search, scan, copy or retrieve content from the site" (כלים או אמצעים אוטומטיים לחיפוש, סריקה, העתקה או אחזור של תוכן), nor copy, reverse engineer or modify any part of it. Fifteen-plus public GitHub projects call `loginAnonymously`, which proves it is easy, not permitted | None granted | None specified | **High** for its API; **medium** if the app only opens the restaurant's own PDF link that Ontopo publishes |
| **Google Places API** | Maps Platform ToS (last modified 2026-08-26) and Service Specific Terms §14 (2026-06-10) — **both fetched and read in full** | Via the API only. ToS §3.2.3(a) "No Scraping": no pre-fetching, indexing, storing, resharing or rehosting; no copying and saving business names or addresses. §3.2.3(c)(vii): no use of Google Maps Content "to improve machine learning and artificial intelligence models, including to train, test, validate or fine-tune". **§3.2.3(d)(iii): no use "in a listings or directory service"** — KetoClub arguably is one. §3.2.3(e): no Places content on a non-Google map. `google.com/robots.txt` disallows `/maps/place` and `/local/dining/` | `place_id` indefinitely; lat/lng 30 days (§14.3); **nothing else** | **Yes** (§3.2.2(b)), never modified or obscured; the app's own terms must bind users to Google's end-user terms | **Low** for discovery-only use within the rules; **high** if any other field is cached, a venue database is seeded from it, or Google text is fed into the classifier prompt |
| **Yelp Fusion** | API Terms 2025-01-13 (snippet, quoted verbatim by two 2026 research repos and Yelp's own GitHub issue #426) | Via the API only; the consumer terms ban robots | **24 hours** for any content; business ids indefinitely for back-end matching; no building your own listing database; commercial analysis needs written consent | **Yes**: logo and link, ratings never blended | **Medium**; moot for Israel |
| **Tripadvisor Content API / Terra** | Master terms, display requirements, caching policy on `tripadvisor-content-api.readme.io` (snippet) | Via the API under signed terms; consumer terms ban robots | **None** except Location ID | **Yes**: marks served from Tripadvisor URLs, displays non-indexable | **Medium–high** (no caching at all conflicts with the Hive cache; AI-use limits unverified) |
| **Foursquare Places** | API licence agreement, Usage Guidelines (snippet); FSQ OS Places is Apache-2.0 | Via the API; no bulk availability, no systematic extraction of a locality; you must prevent crawling of your own pages showing the data | Per account type; PAYG reportedly none server-side (unverified) | **Yes**: "Powered by Foursquare" | **Low–medium**; the OS Places dataset is freely storable |
| **Wix storefront `_api` as a third party** | `wix.com/about/terms-of-use` (mirror, verbatim) | **No.** Users may not "'page scrape', mirror and/or create a browser or border environment around any of the Wix Services", nor use "any 'robot', 'spider' or other automatic device … or any similar or equivalent manual process, to access, acquire, copy, or monitor any portion of the Wix Services (or its data and/or Content)". Wix is Israeli, so enforcement is local. Wix also documents how site owners block AI crawlers via robots.txt; honour it per site | None granted | n/a | **High** (contractual, not copyright: the facts copied are free) |
| **Wix Restaurants Menus API with owner install** | `dev.wix.com` Restaurants Menus docs (snippet) | **Yes**, once the restaurant installs the app or authorises a headless client with the menu-read scope | Your own policy | App-market rules | **Low** |
| **Instagram / Facebook** | Meta Platform Terms; Facebook ToS 2025-01-01 §3.2 (mirror) | Scraping: **no** ("may not access or collect data from our Products using automated means"). API: Business Discovery returns public fields of another *business* account only to an app with its own business account, and serving anyone but the app's role-holders needs App Review. No menu object exists; reading captions and photos is "deriving" Platform Data under §3 | Delete Platform Data when no longer needed (§3.d); Meta may audit | Per platform branding | **High** (scrape) / **medium** (API, and no menu data anyway) |
| **Restaurant's own website** | Each site's terms and robots.txt; copyright (facts free, prose and photos protected); EU TDM opt-out where applicable | Usually grey: the facts are free, a per-site clause or robots rule may forbid bots | Your own policy; honour opt-outs | Good practice: "Source: site" plus a link | **Medium**; low with permission |
| **User-photographed menus** | Copyright only: the restaurant owns the photo's subject, the facts are free | **Yes**: the user's own photo, processed for the user | Keep on device or do not republish the image | n/a | **Low** |

### 4.4 Risk-mitigation patterns seen in comparable apps

1. **Treat cache TTL as a licence term.** One open-source project hard-codes
   Yelp's 24 hours with the comment "This number is a licence term, not a
   tuning knob". KetoClub's 24-hour Hive cache is fine for Yelp-style terms
   and not fine for Google or Tripadvisor content.
2. **Store ids, re-fetch content.** Google's and Yelp's terms both point to
   the same design: persist opaque ids, fetch content on demand.
3. **Attribute on every screen that shows sourced data.** The source chip
   plus a deep link to the venue's own page is the unofficial-source
   equivalent and supports a commentary posture.
4. **Never redistribute raw menus.** The backend proxy cache should not
   become a public menu mirror (short TTL, keyed to a requesting install, no
   listing endpoint), and the Phase 3 community database should store
   KetoClub's *own* derived analysis (verdicts, modifications, notes) keyed
   by venue id, not copies of menu text and prices.
5. **Rate-limit and back off per origin.** Space requests, honour
   `Retry-After` on `429`, cache searches for minutes.
6. **Identify yourself and offer a way out.** A descriptive User-Agent with
   a contact URL, a published takedown contact, and per-site honouring of
   robots.txt, `noai` and TDM-reservation signals.
7. **Prefer consented channels where they exist.** Wolt's merchant Menu API,
   a Wix app install, Google Places for discovery only, FSQ OS Places for
   POIs. Several projects stopped calling `restaurant-api.wolt.com` directly
   in 2026 because it answers with empty bodies; one moved to a paid
   third-party scraper, which transfers the technical problem but not the
   contractual one.
8. **User-supplied photos are the cleanest source.** The user photographs a
   menu they lawfully have in front of them; the classification is
   KetoClub's own work; the photo stays on device or is never republished.

## 5. Ranked comparison

Ranked by expected new Israeli coverage per unit of effort and risk, for a
product that classifies dishes and needs option text. "Risk" is legal and
terms exposure; "Verified" is the evidence level of the access route.

| # | Source / route | Official? | Structured | Options | Israel coverage | Risk | Effort | Verified |
|---|---|---|---|---|---|---|---|---|
| 1 | Restaurant website / PDF → Gemini structured extraction | n/a (public web) | LLM-structured | Only if printed | **Every restaurant with a site or PDF** | Low–medium (facts; robots.txt and per-site terms; do not republish prose) | High | Pipeline pieces verified; no Israeli site fetched |
| 2 | Wix Restaurants Menus (New), visitor-token route | Documented API; visitor reads | **Yes** (sections, variants, modifier groups, labels) | **Yes** | Common, unquantified | **High** (Wix terms ban page-scraping and robots verbatim; same class as Wolt/10bis today); low with owner install | Medium | SDK verified; live access unverified |
| 3 | Tabit (`tabit-order` SPA's JSON) | No (partner-only) | Yes, POS-grade | **Yes** | Hundreds of dine-in venues, ~40% POS share claimed | Medium–high (unsanctioned; IL terms unread; anti-bot unknown) | Medium after capture | Endpoints unverified |
| 4 | Ontopo `/slug_content` | No (internal, anonymous JWT) | Claimed `menus[]`, else PDF URL | No | Large (main reservation platform) | **High** for its API (terms ban automated retrieval); medium for opening the venue's own PDF link | Low to probe | Endpoints verified; menu content contested |
| 5 | QR code → URL classifier (Tabit / rest.co.il PDF / Wix / SaaS / vision) | Mixed | Depends on target | Depends | Every table with a QR | As per target | Medium (on top of 1–3) | Targets verified from public links |
| 6 | Community-photographed menus → vision | n/a | LLM-structured | Rarely | Anywhere users go | Low legal, high moderation | High (versions, trust, dedup, takedown) | Precedents verified |
| 7 | Restaurant self-serve (Wix app / GBP FoodMenus / upload) | Yes | Yes | Yes | Only restaurants that opt in | Low | Medium (verification) | Owner-only routes verified |
| 8 | Chain nutrition (McDonald's IL, Aroma, KFC IL) | n/a | HTML / calculator / PDF | No | Three chains | Low | Low per chain | Snippets |
| 9 | schema.org `Menu` JSON-LD | Open standard | Yes when present | No | Rare | Low | Trivial | Adoption unmeasured |
| 10 | OSM `website` / `website:menu` as a discovery seed | Open data | URL only | — | Decent, sparse tags | Low (ODbL attribution) | Low | Tag counts unverified |
| 11 | Google Places (New) for enrichment | Yes | Attributes only | No | Yes | Medium–high (no caching beyond place id) | Low | Terms verified |
| 12 | Foursquare Places / FSQ OS Places | Yes | Attributes, maybe a menu URL | No | Yes | Medium (unverified) | Low | Snippets |
| 13 | rest.co.il directory pages | No | HTML, owner PDFs | No | ~1,500 menus (marketing) | Medium–high | Medium | Pattern verified |
| 14 | Israeli QR-menu SaaS (tafryt, C-MENU, OurMenu, Beecomm) | No | Probably JSON behind the page | Possibly | Unknown, fragmented | Medium–high | High (one adapter per vendor) | Unverified |
| 15 | Apify / Bright Data Wolt scrapers | Commercial scrapers | Yes | Apify yes | Yes | High (same Wolt terms as today, plus a vendor) | Low | Snippets |
| 16 | Tripadvisor Terra, Yelp, MealMe, Nutritionix, Spoonacular, OpenMenu, Datafiniti | Yes | Varies | Varies | None with Israeli items (Yelp has no Israel at all) | Medium | — | Snippets |
| 17 | Toast / Square / Popmenu / BentoBox / Owner.com unofficial JSON | No | Yes/partial | Toast yes | None | Medium–high (Cloudflare, partner-only) | Medium | Verified, US-only |
| 18 | Google Maps menu tab, Instagram, Facebook, TikTok | No | Photos | No | High in principle | High (terms, anti-bot) | High | — |
| 19 | Cibus/Pluxee, Goodi | No | Behind personal financial logins | — | Large | High | — | Verified logins required |
| 20 | Kaggle Uber Eats, Yelp Open Dataset, Common Crawl, Wikidata, Open Food Facts | Open | Varies | No | None | Low | — | Test corpora only |

## 6. Recommendation

Build **one new adapter, the website-and-document adapter**, and make three
other roadmap items ride on it, rather than adding platform adapters one by
one:

1. **`MenuSource.website`** (or `document`): a `VenueRef` whose platform id is
   a URL. The backend fetches the URL with a named User-Agent, honouring
   `robots.txt`; locates the menu (JSON-LD → Wix structured route → `/menu`
   page → PDF); and either maps the structured result or renders pages to
   images and sends them to Gemini with the existing `Menu`-shaped
   `responseSchema`. `MenuResponseParser` and the completion cache are reused
   unchanged. Prices from the vision path are stamped unverified. This one
   adapter covers every restaurant with a website or a PDF, which is the
   coverage gap Wolt and 10bis leave (dine-in-only venues).
2. **The Scan tab (issue #11) becomes a QR-code URL classifier** over that
   adapter plus the existing ones, and a photo path that sends camera images
   down the same vision route. No new data source, one new input mode.
3. **Wix** is where modifier groups survive, so it deserves a structured
   route — but the anonymous visitor-token route carries the same contractual
   exposure as the Wolt and 10bis adapters (§4.3), enforced by an Israeli
   company. Recommended split: the website adapter reads a Wix site's public
   menu *page* through the vision path like any other site (medium risk); the
   structured Menus API is used only with the owner's install or
   authorisation, alongside the Google Business Profile menu link, in the
   Phase 3 restaurant-submissions milestone (low risk). If the product owner
   decides to accept Wolt-class risk for a Wix visitor-token detector, it is
   a one-file addition behind the same locator, and §8 item 3 is the capture
   that must precede it.
4. **Tabit and Ontopo stay next in line** but are gated on two captures from
   a real machine (§8), exactly as `architecture.md` §17 already says. Do not
   write either adapter against guessed endpoints; the Wolt `/v4 … menu/data`
   scare (`phase2_discovery_research.md` §2.5) is the cautionary tale.
5. **Chain nutrition** (McDonald's Israel, Aroma, KFC Israel) is a small,
   separate enrichment that feeds real carb numbers into
   `net_carbs_estimate` for a handful of dishes; worth doing once the model
   pin is settled, cheap enough to do any time.
6. **Do not spend on licensed APIs for menus.** None returns Israeli items.
   Google Places' caching terms are incompatible with the Hive cache; if
   discovery needs a second source, OSM (free, cacheable) or Foursquare's
   more permissive API are the candidates, not Places. Skip Yelp entirely (no
   Israel), skip Apify/Bright Data for production (same terms exposure as
   today plus a vendor).
7. **Community uploads come after the vision path is trusted**, because every
   precedent says the photo is the bottleneck, and a community feature with a
   weak extractor produces confidently wrong menus at scale.

The legal posture that makes this defensible (§4): logged-out reads of public
pages only; honour `robots.txt` and machine-readable text-and-data-mining
opt-outs; identify the crawler with a contact URL; rate-limit per host; store
dish names, prices and structure for classification but do not republish a
restaurant's prose descriptions verbatim; keep the 24-hour cache; label the
source on every menu (the source chip already exists); and provide a takedown
contact.

## 7. Build order and draft issues

Ordered so each step is independently shippable and the captures that need a
human's laptop sit off the critical path.

| Step | Draft issue title | Depends on | Size |
|---|---|---|---|
| 0 | Move `GEMINI_MODEL` off `gemini-2.5-flash` before its reported October 2026 retirement, after confirming the date on Google's deprecations page | — | S |
| 1 | Record Ontopo `/slug_content` for ten venues and settle whether it carries `menus[].sections[].items[]` (network capture) | a laptop | S |
| 2 | Capture Tabit's `tabit-order?siteName=` menu request (endpoint, headers, token flow) — closes `architecture.md` §17 open question 3 | a laptop | S |
| 3 | Capture a Wix Restaurants Menus site's visitor-token flow and `_api/restaurants-menus-*` calls; confirm CORS and whether anonymous reads answer | a laptop | S |
| 4 | Backend: `POST /v1/chat` accepts image parts (and a PDF rasteriser) alongside text, same install-id rate limit and completion cache | 0 | M |
| 5 | `MenuSource.website`: `VenueRefResolver` accepts any http(s) URL not on a known host; `WebsiteMenuAdapter` with a pure `WebsiteMenuLocator` (JSON-LD, `/menu`, `.pdf`, Wix detection) tested against fixtures | 4 | L |
| 6 | Vision extraction: page images → Gemini with the `Menu` schema; prices stamped `unverified`; Hebrew final-letter reversal check on any PDF text layer; the 30-menu Hebrew corpus with ground truth that `m16_menu_scanner_research.md` says nothing public substitutes for | 4, 5 | L |
| 7 | Wix structured route (menus → sections → items → modifier groups → `DishOption`) as a pure mapper over the Menus API, used with owner authorisation in step 12 — or, if the product owner accepts the §4.3 risk, behind an anonymous detector in the website adapter | 3, 5 | M |
| 8 | Scan tab: QR-code scanner that classifies the URL (Tabit, rest.co.il PDF, Wix, other) and routes to the matching adapter; camera photo → vision path | 5, 6 | M |
| 9 | Chain nutrition enrichment: McDonald's Israel calculator, Aroma product pages, KFC Israel PDF → per-dish carbs for matched chain venues | 0 | M |
| 10 | Tabit adapter (split HTTP adapter and pure mapper, recorded fixture) | 2 | M |
| 11 | Ontopo adapter — only if step 1 finds structured menus; otherwise Ontopo's `menu_url` PDFs feed step 6 | 1 | S–M |
| 12 | Restaurant self-serve: claim-your-venue with phone OTP, Wix app / GBP menu link / upload, owner override of community versions (Phase 3 milestone C) | 5, 7 | L |
| 13 | Community menu photos: versions, provenance, review hold, dedup, freshness badge, takedown | 6, 12 | L |
| 14 | Discovery seed from OSM `website` / `website:menu` for venues Wolt does not list | 5 | S |

Steps 1–3 are captures, not code, and the same thirty-minute session on one
laptop can do all three plus the two pending fixture recorders (#22, #44).

**Filed on GitHub (2026-09-24).** The 2026-09-24 roadmap re-plan had already
filed several of these steps, so only the new ones were created:

| Step | Issue |
|---|---|
| 0 | #179 (new) |
| 1, 11 | #177 (existing; findings added as a comment) |
| 2, 10 | #176 (existing; findings added as a comment) |
| 3 | #180 (new) |
| 4 | #170 (existing; PDFs go to Gemini as `application/pdf`, so no rasteriser) |
| 5 | #181 (new) |
| 6 | #88 and #89 (existing; Hebrew and PDF findings added to #88) |
| 7 | folded into #180's recommendation |
| 8 | #82 (existing Scan tab) plus #182 (new, the QR-code classifier) |
| 9 | #183 (new, as research first) |
| 12, 13 | deferred by #164 (findings added as a comment) |
| 14 | #184 (new) |

## 8. What only a machine with network access can settle

Each of these was blocked here and changes a ranking in §5 if the answer goes
the other way:

1. Whether Ontopo's `/slug_content` returns `menus[]` for ordinary venues or
   only a PDF URL (§3.1). Ten calls.
2. Tabit's real menu endpoint, headers and token flow on a
   `tabitisrael.co.il/tabit-order?siteName=…` page (§3.1). One DevTools
   capture.
3. Whether a Wix restaurant site's `_api/restaurants-menus-*` routes answer an
   anonymous visitor token from a foreign origin, and whether they send CORS
   headers (§3.1). One DevTools capture on any Wix restaurant site.
4. The share of Israeli restaurant websites that are Wix, and of those, that
   use the Menus app rather than a PDF or image (§3.1). A sample of 50 venues
   from a Wolt city listing.
5. Whether `static.rest.co.il` menu PDFs carry a Hebrew text layer, and
   whether it is reversed (§3.2, §3.6). Three downloads and the final-letter
   check.
6. What the McDonald's Israel nutrition calculator fetches (§3.8). One
   network tab.
7. Web Data Commons' `Menu` / `MenuItem` subset counts and taginfo's
   `website:menu` count, plus an Overpass count for Israel (§3.2, §3.4).
8. Gemini's vision accuracy on Hebrew menus: read GlotOCR Bench (arXiv
   2604.12978) for the Hebrew row, then run the M16 photographed menu through
   the backend and score it the way §10.2 of that document scored Tesseract.
9. The `gemini-2.5-flash` retirement date on
   `ai.google.dev/gemini-api/docs/deprecations`, and the price of its
   successor.
10. The terms pages that were unreachable (§4 lists them), read in full rather
    than through snippets.

## 9. Sources

Grouped by section; dates are the day read (all 2026-09-24 unless noted).
Items marked † were reached only through search-engine snippets.

**Israeli platforms (§3.1).** Wix SDK packages on npm: `@wix/restaurants`,
`@wix/restaurants_menus`, `_items`, `_sections`, `_item-modifier-groups`,
`_item-modifiers`, `_item-variants`, `_item-labels` (type definitions and HTTP
resolvers). https://github.com/wix/wix-restaurants-api (Authorization.md,
deprecation notice). https://github.com/wix/skills (headless restaurants
reference). Anonymous Wix visitor tokens in use:
https://github.com/alltheplaces/alltheplaces, https://github.com/harkin/gigs,
https://github.com/glottologist/brickborrow-watch. †https://www.wix.com/about/terms-of-use.
†https://www.timesofisrael.com/new-wix-acquisition-a-life-raft-for-small-restaurants/.
Ontopo clients: https://github.com/erezd/ontopo-mcp,
https://github.com/alexpolonsky/agent-skill-ontopo. Tabit:
https://github.com/api-evangelist/tabit (2026-06-21);
†https://www.tabit.cloud/products/tabitorder/; †https://www.tabitorder.co.il/;
†https://support-us.tabit.cloud/hc/en-us/sections/11135819842834-Introduction-to-Tabit-Pay;
†https://www.linkedin.com/company/tabit---restaurant-technologies. Zap Rest:
†https://www.rest.co.il/about/; `static.rest.co.il` PDF listings. Cibus:
https://github.com/arieluchka/auto_cibus_v1, https://github.com/t0mer/cubit,
https://github.com/Foody-isr/backoffice. QR vendors: †https://www.cmenu.co.il/,
†https://ourmenu.co.il/, †https://qrmenu.co.il/en/, †https://menu.tafryt.co.il/greg,
†https://orders.beecommcloud.com/.

**Open web and structured data (§3.2, §3.4).** †https://schema.org/Menu,
†https://schema.org/MenuItem; †https://webdatacommons.org/structureddata/schemaorg/;
https://www.uni-mannheim.de/media/Einrichtungen/dws/Files_Research/Web-based_Systems/pub/Brinkmann-etal-TheWDCSchemaorgDataSetSeries-WWW2023.pdf;
https://github.com/tbsisan/restaurant-menu-search (DoorDash JSON-LD note,
Square scraper); https://github.com/moyyyy3333/restaurant-ai-bot (menu
locator); https://github.com/feder-cr/invisible_playwright (XHR interception);
https://github.com/CaptainStabs/BountyScrapers (Toast GraphQL);
https://github.com/bagelbotdev/api; https://github.com/mysite-ai/website-template
(Toast Cloudflare note, 2026); https://github.com/dldx/kissaten (Square store
API); https://github.com/aasuper1/chawkeats (platform detection);
https://github.com/api-evangelist/popmenu, https://github.com/api-evangelist/bentobox,
https://github.com/api-evangelist/toast; †https://help.getbento.com/hc/en-us/articles/360005071273-A-Brief-Guide-to-SEO;
†https://support.squarespace.com/hc/en-us/articles/206544087-Menu-blocks;
†https://www.malou.io/en-us/blog/structured-data-for-restaurants;
†https://developers.google.com/search/docs/appearance/structured-data/local-business.
Hebrew PDF reversal: https://github.com/firecrawl/pdf-inspector/pull/303
(2026-08-07) and PR #440 (2026-08-21); †https://github.com/pymupdf/PyMuPDF/issues/2199;
†https://github.com/py-pdf/pypdf/pull/4077. Tools: https://github.com/unclecode/crawl4ai,
https://github.com/datalab-to/marker, https://github.com/docling-project/docling,
†https://spider.cloud/blog/best-firecrawl-alternatives/. Open data:
†https://wiki.openstreetmap.org/wiki/Key:website:menu;
https://github.com/oleganryb/tel-aviv-restaurants-scraper;
†https://www.kaggle.com/datasets/ahmedshahriarsakib/uber-eats-usa-restaurants-menus;
†https://openbigdata.org/resource/yelp-open-dataset/; †https://world.openfoodfacts.org/data.

**Licensed and commercial APIs (§3.3).** Google Maps Platform service terms
(fetched): https://cloud.google.com/maps-platform/terms/maps-service-terms/index-20240522;
†https://developers.google.com/maps/documentation/places/web-service/data-fields;
†https://developers.google.com/maps/documentation/places/web-service/usage-and-billing;
†https://developers.google.com/my-business/reference/rest/v4/FoodMenus;
†https://developers.google.com/my-business/content/sunset-dates. Foursquare:
†https://docs.foursquare.com/developer/reference/upcoming-changes;
†https://docs.foursquare.com/data-products/docs/places-pro-and-premium.
Tripadvisor: https://github.com/api-evangelist/tripadvisor;
†https://docs.terra.tripadvisor.com/docs/overview;
†https://supergood.ai/api-report-card/tripadvisor;
https://ir.tripadvisor.com/news-releases/news-release-details/tripadvisor-acquires-singleplatform-endurance-international (2019-12-05).
Yelp: †https://docs.developer.yelp.com/docs/plans;
†https://terms.yelp.com/developers/api_terms/20250113_en_us/;
†https://docs.developer.yelp.com/docs/resources-supported-locales. Others:
†https://docs.mealme.ai/, †https://datarade.ai/data-providers/mealme/profile;
†https://calorieapi.com/blog/nutritionix-api-pricing;
†https://spoonacular.com/food-api/pricing; †https://platform.fatsecret.com/api-editions;
https://github.com/api-evangelist/openmenu (2026-06-02);
https://github.com/api-evangelist/datafiniti; †https://outscraper.com/scrape-menu-links-from-google-maps/;
†https://apify.com/needy_hammock/wolt-restaurant-menu-scraper and sibling
actors; https://github.com/luminati-io/wolt-price-tracker (Bright Data);
https://github.com/api-evangelist/cloudkitchens, https://github.com/api-evangelist/chowly,
https://github.com/api-evangelist/olo; †https://developers.deliverect.com/reference/commerce-channel-api;
†https://developer.wolt.com/docs/api/menu.

**Vision, QR, community, chains (§3.6–3.8).** `m16_menu_scanner_research.md`
§5 and §10.2 (this repo). https://github.com/opendatalab/OmniDocBench (v1.6
table); †https://benchmarking.nanonets.com/models/gemini-3-flash;
†https://ai.google.dev/gemini-api/docs/pricing;
†https://ai.google.dev/gemini-api/docs/document-processing;
https://github.com/google-gemini/cookbook/blob/main/quickstarts/PDF_Files.ipynb;
https://raw.githubusercontent.com/MicrosoftDocs/azure-ai-docs/main/articles/ai-services/document-intelligence/language-support/ocr.md;
†https://aws.amazon.com/textract/faqs/; †https://www.therundown.ai/tools/mistral-ocr-3;
https://github.com/PaddlePaddle/PaddleOCR (PP-OCRv5 language list);
https://github.com/datalab-to/surya/blob/master/static/docs/multilingual.md;
https://github.com/allenai/olmocr; https://github.com/tesseract-ocr/tessdata_best;
https://github.com/tesseract-ocr/tesseract/issues/361;
†https://www.extend.ai/resources/ocr-benchmarks-real-world-documents;
†https://www.llamaindex.ai/blog/llm-ocr;
†https://blog.bytebytego.com/p/how-doordash-uses-ai-models-to-understand;
†https://www.yelp-support.com/article/What-is-Menu-Vision?l=en_US;
†https://www.zomato.com/developer/integration/docs/glossary/menu-moderation/;
†https://www.happycow.net/members/faq; †https://utfb.untappd.com/get-verified-on-untappd/;
https://github.com/openfoodfacts/openfoodfacts-server (photo upload tutorial),
https://github.com/openfoodfacts/robotoff;
†https://support.google.com/business/answer/9455840. Chains:
†https://www.mcdonalds.co.il/מהפיכת_התזונה/מחשבון_תזונה;
†https://www.aroma.co.il/menus/, †https://www.aroma.co.il/מידע-תזונתי-ואזהרות/;
†https://www.kfc.co.il/wp-content/uploads/2024/05/28068_Allergic_Table_he.pdf;
†https://foodiepedia.co.il/company/ארומה/;
†https://www.foodnavigator.com/Article/2020/01/27/Israel-introduces-mandatory-HFSS-warnings-front-of-pack/.
Model retirement: †https://benchr.org/deprecations/gemini-2-5-pro,
†https://vorplabs.com/models/google-model-retirements,
†https://www.cloudzero.com/blog/gemini-pricing/.

**Legal and terms (§4).** Fetched in full: Google Maps Platform Terms of
Service https://cloud.google.com/maps-platform/terms (last modified
2026-08-26) and Service Specific Terms
https://cloud.google.com/maps-platform/terms/maps-service-terms (2026-06-10);
the Places API (New) v1 schema from the googleapis Node client
(`src/apis/places/v1.ts`, raw GitHub). Mirrors: Wix Terms of Use text in
https://github.com/sonu-gupta/tosdr-terms-of-service-corpus; Meta Platform
Terms and Facebook Terms (effective 2025-01-01) in
https://github.com/OpenTermsArchive/pga-versions; Yelp, Foursquare and
Tripadvisor consumer terms (2018–2019 copies) in the same ToS;DR corpus;
`google.com/robots.txt` vendored copy in
https://github.com/owenblake38/Youtube2Mp4 (date unknown); Wolt browser-sniff
report (2026-05-23) in https://github.com/mvanhorn/printing-press-library;
https://github.com/abu-lina/uflow (Apify Wolt note, May 2026);
https://github.com/r1nnegann/wolt-easy (rate limiting). Snippets:
†https://wolt.com/en/terms, †https://explore.wolt.com/en/deu/terms,
†https://developer.wolt.com/docs/api/menu, †https://developer.wolt.com/docs/faq;
†https://shop.10bis.co.il/he-IL/content/terms-and-conditions;
†https://legal.tabit.cloud/; †https://club.ontopo.co.il/help/terms,
†https://ontopo.co.il/en/settings/terms;
†https://terms.yelp.com/developers/api_terms/20250113_en_us/ (quoted verbatim by
Yelp's GitHub issue #426 and two 2026 research repositories),
†https://terms.yelp.com/developers/display_requirements/;
†https://tripadvisor-content-api.readme.io/reference/api-master-terms-new,
†…/reference/caching-policy, †…/reference/display-requirements;
†https://foursquare.com/legal/terms/apilicenseagreement/;
†https://dev.wix.com/docs/rest/business-solutions/restaurants/menus/introduction;
†https://support.wix.com/en/article/blocking-ai-crawlers-from-your-site;
†https://developers.facebook.com/terms/. Law: †*Feist v. Rural*, 499 U.S. 340
(1991); †Israel Copyright Act 5768-2007 §§4(b), 5 via WIPO Lex
https://www.wipo.int/wipolex/en/legislation/details/11509 and
https://www.law.co.il/media/knowledge-centers/copyright_2020_israel.pdf;
†https://informationr.net/ir/6-4/paper110.html (*Interlego*);
†https://en.wikipedia.org/wiki/HiQ_Labs_v._LinkedIn, †https://blog.apify.com/hiq-v-linkedin/;
†https://www.zyte.com/blog/california-court-meta-ruling/ (*Meta v. Bright Data*);
†https://www.gblock.app/articles/linkedin-proapis-scraping-injunction-2026;
†https://www.plagiarismtoday.com/2013/02/21/israeli-court-rules-rss-scraping-legal/;
†https://legalblogs.wolterskluwer.com/copyright-blog/ryanair-ltd-v-pr-aviation-bv…;
†https://legalblogs.wolterskluwer.com/copyright-blog/the-new-copyright-directive-text-and-data-mining-articles-3-and-4/;
†https://www.mofo.com/resources/insights/241004-to-scrape-or-not-to-scrape-first-court-decision;
†https://arxiv.org/pdf/2503.06035 ("The liabilities of robots.txt");
†https://blog.ericgoldman.org/archives/2025/12/are-robots-txt-instructions-legally-binding-ziff-davis-v-openai.htm.
Unreachable and therefore unread: `wolt.com/robots.txt`, `10bis.co.il/next/terms`
and its robots.txt, Tabit's IL diner terms, Ontopo's full terms with section
numbers, Google's Places *policies* page, Meta's Automated Data Collection
Terms, and any Israeli court decision on scraping.
