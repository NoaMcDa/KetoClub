# KetoClub — Architecture

**Status:** design document. No application code exists yet; this file is the
blueprint the first implementation follows. When code and this document disagree,
fix one of them in the same pull request.

**Audience:** anyone about to write the first line of Dart for KetoClub, and anyone
reviewing it.

This document resolves the contradictions between the older planning documents
(`README.md`, `feature_prioratization`, `CLAUDE.md`, and the m15/m16 research
notes). The resolutions are recorded in §14 so nobody has to re-derive them.

---

## Table of contents

1. [What KetoClub is, in one paragraph](#1-what-ketoclub-is-in-one-paragraph)
2. [Architecture at a glance](#2-architecture-at-a-glance)
3. [Guiding constraints](#3-guiding-constraints)
4. [The runtime pipeline](#4-the-runtime-pipeline)
5. [Project structure](#5-project-structure)
6. [Components](#6-components)
   - 6.1 Menu ingestion (platform adapters)
   - 6.2 Classification engine
   - 6.3 Waiter script generation
   - 6.4 Local storage
   - 6.5 Location and venue search
   - 6.6 UI and state management
7. [Domain model](#7-domain-model)
8. [External integrations](#8-external-integrations)
9. [LLM integration contract](#9-llm-integration-contract)
10. [Failure handling](#10-failure-handling)
11. [Security and privacy](#11-security-and-privacy)
12. [Localisation](#12-localisation)
13. [Platform notes](#13-platform-notes)
14. [Decisions log](#14-decisions-log)
15. [Testing strategy](#15-testing-strategy)
16. [Build order and extension points](#16-build-order-and-extension-points)
17. [Open questions](#17-open-questions)

---

## 1. What KetoClub is, in one paragraph

KetoClub is a Flutter app (web, iOS, Android) for people on a ketogenic diet who
want to know what they can order at a restaurant. The user picks a venue, the app
pulls that venue's live menu straight from a delivery or POS platform (Wolt first,
then 10bis, later Tabit and Ontopo), classifies every dish as 🟢 order-as-is,
🟡 order-with-a-change, or 🔴 not keto, and for every yellow dish produces an exact
sentence to say to the waiter. Classification is done by a hosted language model the
user reaches with their own OpenRouter key; when there is no key or no network, an
on-device rule engine gives a coarser answer. There is no backend and no server-side
database: everything runs on the device.

---

## 2. Architecture at a glance

```
┌──────────────────────────────── Device (Flutter) ────────────────────────────────┐
│                                                                                  │
│  ┌───────────── Presentation ─────────────┐   ┌────────── State (provider) ────┐ │
│  │ VenueSearchScreen  MenuScreen           │◄──│ VenueSearchController          │ │
│  │ SettingsScreen     WaiterCardSheet      │   │ MenuController                 │ │
│  │ DishCard  StatusBadge  WaiterScript     │   │ SettingsController             │ │
│  └────────────────────────────────────────┘   └───────────────┬────────────────┘ │
│                                                               │                  │
│  ┌──────────────────────────── Services ─────────────────────▼────────────────┐ │
│  │                                                                             │ │
│  │  MenuRepository ── PlatformMenuAdapter ── WoltAdapter / TenBisAdapter / …   │ │
│  │        │                                                                    │ │
│  │        ▼                                                                    │ │
│  │  MenuClassifier ── ClassifierRouter ──┬── LlmMenuClassifier ── LlmChatClient│ │
│  │                                       └── HeuristicMenuClassifier           │ │
│  │                                                                             │ │
│  │  LocationService      VenueSearchService      MenuCache      KeyStore       │ │
│  └───────────────┬──────────────────┬────────────────┬──────────────┬──────────┘ │
│                  │                  │                │              │             │
│           geolocator           http client      Hive (cache)   secure storage    │
└──────────────────┼──────────────────┼──────────────────────────────────────────────┘
                   │                  │
        OS location services   ┌──────┴──────────────────────────────────────────┐
                               │ restaurant-api.wolt.com   www.10bis.co.il       │
                               │ tgp-api.tabit.cloud       ontopo.com            │
                               │ openrouter.ai  (user's own key)                 │
                               └─────────────────────────────────────────────────┘
```

Three layers, one direction of dependency: **presentation → state → services**.
Services never import Flutter widgets. Models are plain Dart and are shared by all
three layers.

---

## 3. Guiding constraints

These are the rules every component in this document obeys. They are numbered so
issues and reviews can cite them.

1. **Client-only.** No server, no server-side database, no shared secret. Every
   network call originates from the user's device and every result lives on it.
   A backend is an explicit Phase 3+ addition (§16), not something the MVP quietly
   depends on.
2. **One codebase, three targets.** Web, iOS and Android share all business logic.
   Platform differences are confined to permissions, HTTP transport and layout.
3. **Bring your own key.** The language model is reached with an OpenRouter key the
   user pastes into Settings. The app ships no key. The key is stored in platform
   secure storage and is never logged, printed, or included in an error value.
4. **The engine is swappable.** Every classifier implements the same `MenuClassifier`
   interface. Exactly one file names the concrete implementations (§6.2). Swapping
   the LLM for rules, or adding a vision model later, touches that file and nothing
   in the UI.
5. **A wrong green is the failure that matters.** The user is at a table about to
   order. Rules 6 to 9 exist to make a wrong green rare and visible.
6. **Never invent a dish.** A classified dish must be traceable to the menu the app
   fetched. A dish the model names that the menu does not contain is not shown as a
   verdict.
7. **A yellow without an instruction does not exist.** The parser demotes a
   "modifiable" dish with an empty instruction to *unclassified*. It never promotes
   it to green and never renders a yellow card with a blank script.
8. **Unclassified is rendered, never dropped. Red is grouped, never hidden.** "The
   pizza was seen and is red" and "the pizza was not read" must not look alike.
9. **The model's answer is untrusted input.** It is JSON from a third party, shaped
   by text a restaurant typed. The parser validates shape, caps sizes, checks
   provenance, and never interprets any field as an instruction.
10. **Failures are distinct and named.** A timeout, a bad key, a rate limit, a
    retired model and a torn socket are five different things and get five
    different messages. Collapsing them into "no internet" cost the m15 team three
    investigations (`m15_openrouter_models_fix.md`); KetoClub does not repeat that.
11. **Only text leaves the device for classification.** Dish names, descriptions
    and option labels are sent. Nothing about the user, their location, or their
    history is sent to the model.
12. **No test makes a network call.** Every adapter and the LLM client sit behind
    an interface with a fake; fixtures are checked-in JSON.

---

## 4. The runtime pipeline

```
 user picks venue (search, or pastes a Wolt URL / slug / 10bis ID)
          │
          ▼
 MenuRepository.load(VenueRef)
          │  cache hit (fresh)? ── yes ──► Menu (from Hive)
          │ no
          ▼
 PlatformMenuAdapter.fetch(ref)          one adapter per platform (§6.1)
          │  raw platform JSON
          ▼
 adapter.normalise(json) ──► Menu { categories[ Dish{name, description, price, options} ] }
          │
          ▼
 MenuClassifier.classify(menu)           ClassifierRouter picks the engine (§6.2)
          │
          ├─ key present + online ──► LlmMenuClassifier
          │                              → MenuAnalysisPrompt (system + user + schema)
          │                              → LlmChatClient.complete()   ONE request per menu
          │                              → MenuResponseParser        (§9.4 rules)
          │
          └─ otherwise ───────────────► HeuristicMenuClassifier
                                         → regex over CARB_MODIFIERS / NON_KETO_BASES
                                         → template waiter scripts
          │
          ▼
 MenuAnalysis (sealed)                   Analysed{dishes, unclassified, engine} | Failed{reason}
          │
          ├──► MenuCache.put(venueRef, menu, analysis)     so a revisit costs no request
          │
          ▼
 MenuController ──► MenuScreen
     🟢 green  ·  🟡 yellow (expandable waiter script)  ·  🔴 red (collapsed group, with count)
     ⚪ unclassified (listed, no colour)  ·  chip showing which engine produced the result
```

Two properties of this pipeline are load-bearing:

- **Text is the one input shape for the classifier.** Whether a menu came from Wolt,
  10bis, Tabit, or (in Phase 4) a photographed page, the classifier receives a
  normalised `Menu` of strings. One prompt, one parser, one fake in every test.
- **One request per menu, not per dish.** OpenRouter's free tier is 50 requests a day
  on an unfunded key. A whole menu is one call; the cache (§6.4) makes the second look
  at the same menu cost nothing.

---

## 5. Project structure

The layout below extends the one in `CLAUDE.md` with the pieces the LLM engine, the
key store and the cache need. Keep it flat; the app is small enough that a
feature-per-directory split would be ceremony.

```
ketoclub/
├── lib/
│   ├── main.dart                         # MaterialApp, provider wiring, localisation setup
│   ├── app.dart                          # routes, theme, RTL/LTR handling
│   │
│   ├── screens/
│   │   ├── venue_search_screen.dart      # location + name search, paste-a-URL field
│   │   ├── menu_screen.dart              # classified menu, filters (green / green+yellow / all)
│   │   ├── waiter_card_sheet.dart        # full-screen high-contrast script + copy button
│   │   └── settings_screen.dart          # OpenRouter key, consent text, dietary toggles (later)
│   │
│   ├── widgets/
│   │   ├── dish_card.dart                # name, price, badge, expandable script
│   │   ├── status_badge.dart             # icon + colour, never colour alone
│   │   ├── waiter_script_widget.dart     # copyable instruction text
│   │   └── engine_chip.dart              # "AI" / "rules (offline)" indicator
│   │
│   ├── state/                            # ChangeNotifiers consumed by screens via provider
│   │   ├── venue_search_controller.dart
│   │   ├── menu_controller.dart
│   │   └── settings_controller.dart
│   │
│   ├── services/
│   │   ├── menu/
│   │   │   ├── menu_repository.dart      # cache-first load; owns the adapter registry
│   │   │   ├── platform_menu_adapter.dart# interface: fetch + normalise
│   │   │   ├── wolt_adapter.dart
│   │   │   ├── tenbis_adapter.dart
│   │   │   ├── tabit_adapter.dart        # Phase 2+
│   │   │   └── ontopo_adapter.dart       # Phase 4 (PDF links only)
│   │   ├── classifier/
│   │   │   ├── menu_classifier.dart      # interface + ClassifierRouter
│   │   │   ├── llm_menu_classifier.dart
│   │   │   ├── menu_analysis_prompt.dart # system prompt, user prompt builder, JSON schema
│   │   │   ├── menu_response_parser.dart # §9.4 — pure, static, never throws
│   │   │   └── heuristic_menu_classifier.dart
│   │   ├── llm/
│   │   │   ├── llm_chat_client.dart      # interface, ChatResult, ChatFailureReason
│   │   │   └── open_router_client.dart   # the ONLY file that knows the OpenRouter URL
│   │   ├── location_service.dart         # geolocator wrapper with manual fallback
│   │   ├── venue_search_service.dart     # Wolt venue search + paste-a-URL resolver
│   │   └── storage/
│   │       ├── key_store.dart            # flutter_secure_storage wrapper
│   │       ├── menu_cache.dart           # Hive box: venueRef → (menu, analysis, fetchedAt)
│   │       └── settings_store.dart       # shared_preferences wrapper
│   │
│   ├── models/
│   │   ├── venue.dart
│   │   ├── menu.dart                     # Menu, MenuCategory, Dish, DishOption
│   │   ├── analysis.dart                 # DishVerdict, AnalysedDish, MenuAnalysis (sealed)
│   │   └── failures.dart                 # MenuFetchFailureReason, MenuAnalysisFailureReason
│   │
│   ├── utils/
│   │   ├── constants.dart                # CARB_MODIFIERS, NON_KETO_BASES, templates, caps
│   │   ├── classification_rules.dart     # compiled regexes for the heuristic engine
│   │   ├── text_normaliser.dart          # lowercase, strip niqqud/punctuation, for provenance
│   │   └── price_format.dart             # agorot → ILS, locale-aware formatting
│   │
│   └── l10n/
│       ├── app_en.arb
│       └── app_he.arb
│
├── test/
│   ├── fixtures/                         # checked-in platform JSON + menu transcripts
│   ├── services/                         # adapter, parser, heuristic, router tests
│   └── widgets/
├── integration_test/                     # end-to-end flows with the classifier faked
├── ios/  android/  web/
├── pubspec.yaml
└── analysis_options.yaml
```

**Dependency rules, enforced by review:**

- `models/` and `utils/` import nothing from `services/`, `state/`, `screens/`, or
  `widgets/`, and nothing from Flutter beyond `foundation.dart`.
- `services/` never imports `package:flutter/widgets.dart`.
- `screens/` and `widgets/` reach services only through a controller in `state/`.
- The string `openrouter.ai` appears in exactly one file under `lib/`. The concrete
  classifier classes are named in exactly one file: `menu_classifier.dart`'s router.

**Dependencies (initial `pubspec.yaml`):**

| Package | Why |
|---|---|
| `http` | Restaurant APIs and OpenRouter. Small, works on all three targets. |
| `provider` | State management. `ChangeNotifier` per screen is enough at this size. |
| `geolocator` | Device location on web, iOS, Android. |
| `hive` + `hive_flutter` | Menu and analysis cache. |
| `flutter_secure_storage` | The OpenRouter key. Keychain / Keystore / browser storage. |
| `shared_preferences` | Non-secret settings (filters, language, last venue). |
| `flutter_localizations` + `intl` | Hebrew and English UI, RTL, number formatting. |
| `url_launcher` | Open the venue on the source platform. |

Nothing else until a concrete need appears. In particular no code generation, no
`freezed`, no `riverpod`: the app is small, and each of those adds a build step.

---

## 6. Components

### 6.1 Menu ingestion (platform adapters)

One adapter per platform, all behind one interface:

```dart
abstract interface class PlatformMenuAdapter {
  MenuSource get source;                       // wolt, tenbis, tabit, ontopo
  bool canHandle(VenueRef ref);                // by source, or by parsing a pasted URL
  Future<MenuFetchResult> fetch(VenueRef ref); // never throws
}

sealed class MenuFetchResult {}
final class MenuFetched extends MenuFetchResult { final Menu menu; }
final class MenuFetchFailed extends MenuFetchResult { final MenuFetchFailureReason reason; }
```

Each adapter does two things and only two: an HTTP GET (or the token dance Tabit and
Ontopo need), and normalisation of the platform's JSON into the shared `Menu` model.
The normalisation rules that matter:

| Platform | Identifier | Price unit | Structure to flatten | Options |
|---|---|---|---|---|
| Wolt | `venue_slug` from the public URL | integer agorot → divide by 100 | `categories[].item_ids` → `items[]` by id | `options[]` by id; each value's `name` is appended to the dish's option text |
| 10bis | numeric `restaurantId` | decimal ILS as-is | `categoriesList[].dishList[]` | `dishOptionsList[]` |
| Tabit | `siteId` | check on first real payload | POS kitchen groups → categories | forced questions and modifiers |
| Ontopo | `venue_id` | n/a | returns `menu_pdf_url` / `external_menu_url`, not items | n/a |

Option labels ("Choice of side: potato purée / green salad") are part of the text the
classifier sees, because a dish's yellow-ness often lives in the options, not the
description.

`MenuRepository` owns the adapter registry, resolves a pasted URL to a `VenueRef`,
checks the cache first (§6.4), and is the only thing the controllers call.

**Web caveat (important):** the restaurant platform APIs do not send CORS headers
for arbitrary origins. Native iOS and Android HTTP stacks do not enforce CORS, so the
adapters work there as written. In a browser they will be blocked. See §13 for the
options; the MVP treats mobile as the primary target for live menu fetching and the
web build as primary for the paste-a-menu path.

### 6.2 Classification engine

```dart
abstract interface class MenuClassifier {
  /// Never throws. One call per menu.
  Future<MenuAnalysis> classify(Menu menu, {ClassificationOptions options});
}
```

Three implementations, one router:

**`LlmMenuClassifier`** — the primary engine. Builds one prompt from the whole
menu (§9.1), sends it through `LlmChatClient`, and hands the reply to
`MenuResponseParser`. It never touches `http` directly and never sees the API key;
both belong to the client.

**`HeuristicMenuClassifier`** — the fallback. A Dart port of the README's
`analyze_dish`: word-boundary regex over `NON_KETO_BASES` → red; over
`CARB_MODIFIERS` → yellow with the mapped template sentences; else green. It runs
on-device, offline, in milliseconds, and its vocabulary is deliberately small, so its
result is labelled as "rules" in the UI (`engine_chip.dart`) and its greens carry a
"not AI-verified" hint. Hebrew triggers live next to the English ones in
`constants.dart` (פירה, צ'יפס, אורז, תפוח אדמה, פסטה, פיצה, לחמנייה, …).

**`ClassifierRouter`** — decides, per call, in this order:

1. No key stored, or estimation consent not given → heuristic, with
   `engine = rules(reason: notConfigured)`.
2. Device reports offline → heuristic, `engine = rules(reason: offline)`.
3. Otherwise → LLM. If the LLM call fails with `offline`, `rateLimited`, or
   `timeout`, fall back to heuristic and surface the reason in the result so the
   UI can say "showing rule-based results; AI analysis failed because …".
   A `badResponse` or `unauthorised` failure is **not** silently papered over with
   rules: the user must see that their key or the model is the problem.

The router is the one file that names concrete classifiers (constraint 4).

Dish-level output is the same from either engine:

```dart
enum DishVerdict { orderAsIs, modifiable, nonKeto }

class AnalysedDish {
  final String dishId;         // links back to Menu.dish
  final String name;           // exactly as printed on the menu
  final DishVerdict verdict;
  final String why;            // never empty
  final String? modification;  // non-null iff verdict == modifiable
  final double? netCarbsEstimate;  // LLM only, optional, never shown as fact
}
```

### 6.3 Waiter script generation

The waiter script *is* `AnalysedDish.modification`. There is no separate generator
step:

- The LLM engine writes it per dish, in the menu's language, following the prompt's
  style rules (§9.1): polite, one or two sentences, names the exact component to
  remove and the exact substitute to ask for.
- The heuristic engine composes it from `CARB_MODIFIERS` templates in
  `constants.dart`, deduplicated, in the UI language.

The Waiter Card (`waiter_card_sheet.dart`) renders the script full-screen in large
high-contrast type with a copy button, so the phone can be shown to the server.

### 6.4 Local storage

| Store | Package | Holds | Lifetime |
|---|---|---|---|
| `KeyStore` | `flutter_secure_storage` | OpenRouter key | until the user removes it |
| `MenuCache` | `hive` | `venueRef → {menu, analysis, fetchedAt, engine}` | 24 h for the menu; analysis kept as long as the menu it was computed from |
| `SettingsStore` | `shared_preferences` | UI language, filter defaults, consent flag, last venue | until cleared |

Cache rules:

- A cached **menu** is fresh for 24 hours. After that it is refetched; the old
  analysis is discarded only if the refetched menu differs (compare a hash of the
  normalised dish text).
- A cached **analysis** produced by the **heuristic** engine is replaced the next time
  the LLM engine is available, without asking, because it was always the weaker
  answer.
- The cache never stores the raw platform JSON, only the normalised `Menu`.
- The user can clear the cache from Settings.

No health data, no diary, no user profile is stored. KetoClub's storage is a cache
and one secret.

### 6.5 Location and venue search

`LocationService` wraps `geolocator`: request permission, get one position, degrade
gracefully to "type an address or a venue name" on denial or on web without HTTPS.

`VenueSearchService` has two entry points, both Tier A/B in
`feature_prioratization`:

1. **Paste a URL or ID** (Tier A, ships first). Recognises Wolt venue URLs
   (`wolt.com/…/restaurant/{slug}`), bare slugs, and 10bis restaurant IDs, and returns
   a `VenueRef`. No network needed for the resolution itself.
2. **Search nearby** (Tier B). Queries Wolt's venue search with the device position
   or a typed string and lists results with a name, address, and distance. Results are
   filtered client-side; no radius endpoint is assumed.

Venues are not persisted beyond "last opened" until Phase 3 adds a community
directory.

### 6.6 UI and state management

`provider` with one `ChangeNotifier` per screen:

- `VenueSearchController` — location state, query, results, pasted-URL resolution.
- `MenuController` — loads a venue via `MenuRepository`, runs `MenuClassifier`,
  exposes `MenuAnalysis` plus the active filter (green / green+yellow / all) and
  the engine chip state. Holds the menu and the analysis separately so a failed
  analysis still shows the raw menu.
- `SettingsController` — key present/absent (never the key value), consent flag,
  language.

Screens:

| Screen | Route | Purpose |
|---|---|---|
| `VenueSearchScreen` | `/` | Locate, search, or paste; opens a venue |
| `MenuScreen` | `/venue/:source/:id` | Classified menu with filters and engine chip |
| `WaiterCardSheet` | modal | Large-type script with copy |
| `SettingsScreen` | `/settings` | Key entry, disclosure text, cache clear, language |

Visual rules: a verdict is always icon **and** colour, never colour alone
(accessibility). Red dishes are a collapsed group with a count at the bottom of the
list. Unclassified dishes are listed under their own neutral heading. The engine
chip is always visible on a classified menu.

---

## 7. Domain model

Plain Dart, immutable, no code generation.

```dart
enum MenuSource { wolt, tenbis, tabit, ontopo }

class VenueRef {                       // how we address a venue on a platform
  final MenuSource source;
  final String platformId;             // slug, restaurantId, siteId, venue_id
}

class Venue {
  final VenueRef ref;
  final String name;
  final String? address;
  final double? latitude, longitude;
  final String? sourceUrl;             // deep link back to the platform page
}

class Menu {
  final VenueRef venueRef;
  final String currency;               // "ILS"
  final DateTime fetchedAt;
  final List<MenuCategory> categories;
}

class MenuCategory { final String id, name; final List<Dish> dishes; }

class Dish {
  final String id;                     // platform id, stable across refetches
  final String name;
  final String description;            // "" when absent
  final double price;                  // major units (ILS), already converted
  final List<DishOption> options;      // "Choice of side: purée | salad"
}

class DishOption { final String name; final List<String> values; }

sealed class MenuAnalysis {}
final class MenuAnalysed extends MenuAnalysis {
  final List<AnalysedDish> dishes;     // never empty
  final List<String> unclassified;     // names seen but not placeable — shown, never silent
  final AnalysisEngine engine;         // llm(model) | rules(reason)
  final DateTime analysedAt;
}
final class MenuAnalysisFailed extends MenuAnalysis {
  final MenuAnalysisFailureReason reason;
}
```

Relationship to the README's ER diagram: the three README entities (Venues, Menus,
Dishes) are the three classes above. They are **cache records on the device**, not
tables on a server. `keto_rating_score` and `is_verified_keto_friendly` are Phase 3
fields and are not modelled until then.

---

## 8. External integrations

| Service | Endpoint | Auth | Priority | Notes |
|---|---|---|---|---|
| **Wolt** | `GET https://restaurant-api.wolt.com/v4/venues/slug/{slug}/menu/data` | none | Phase 1 | Cleanest schema; prices in agorot |
| **10bis** | `GET https://www.10bis.co.il/api/v1.0/Restaurants/{restaurantId}/Menu` | none | Phase 1–2 | `categoriesList → dishList`; decimal prices |
| **Tabit** | `GET https://tgp-api.tabit.cloud/menu/v2/{siteId}` (alt: `online.tabit.cloud/api/v1/ordering/menu?siteId=`) | session / anonymous token from the QR landing | Phase 2+ | Dine-in venues absent from delivery apps |
| **Ontopo** | `POST https://ontopo.com/api/loginAnonymously` → `GET https://ontopo.com/api/venue/{venueId}` | anonymous bearer | Phase 4 | Returns PDF/image links, needs the OCR path |
| **OpenRouter** | `POST https://openrouter.ai/api/v1/chat/completions` | `Authorization: Bearer <user key>` | Phase 1 | See §9 |

All restaurant endpoints are undocumented internal APIs discovered by network
inspection (`menu_api_research`). Each adapter therefore:

- sends a browser-like `User-Agent` and `Accept: application/json`;
- treats any non-2xx or non-JSON body as `MenuFetchFailureReason.platformChanged`,
  with the status code, so a schema change is diagnosable from the failure copy;
- is covered by a fixture test against a checked-in real response, so a schema
  drift is caught by re-recording the fixture, not by a user.

---

## 9. LLM integration contract

### 9.1 The prompt

One request per menu. The **system** prompt (in `menu_analysis_prompt.dart`) states:

- The three verdicts and their definitions, taken verbatim from `constants.dart` so
  the model and the UI legend say the same thing.
- The keto rules: net carbs ≤ 6 g per dish for green; starchy sides, root vegetables,
  sugary sauces and glazes, breading and buns make a dish yellow when the core is
  compliant; pasta, pizza, rice bowls, noodles, breaded proteins, pastry, sandwiches
  on bread are red.
- Output rules: return only dishes present in the input; use the dish `id` and the
  exact printed `name`; every `modifiable` dish must carry a `modification`; write
  `why` and `modification` in the language the menu is written in; keep each under
  300 characters; return JSON matching the schema and nothing else.
- Optional dietary constraints appended from Settings (Tier C: seed-oil free,
  dairy-free, carnivore).

The **user** prompt is the normalised menu, one line per dish:
`id | category | name | description | options`. Prices are omitted; they are
irrelevant to the verdict and waste tokens.

### 9.2 The response schema

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["dishes"],
  "properties": {
    "dishes": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["id", "name", "verdict", "why", "modification", "net_carbs_estimate"],
        "properties": {
          "id":        { "type": "string" },
          "name":      { "type": "string" },
          "verdict":   { "type": "string", "enum": ["orderAsIs", "modifiable", "nonKeto"] },
          "why":       { "type": "string" },
          "modification":       { "type": ["string", "null"] },
          "net_carbs_estimate": { "type": ["number", "null"] }
        }
      }
    }
  }
}
```

Every property is in `required` and every object has `additionalProperties: false`,
which is what OpenAI-style strict mode demands; nullable fields are typed
`["string","null"]` rather than omitted. (`m16_structured_output_fix.md` records
the outage caused by getting this wrong.)

### 9.3 Request strategy

- `response_format: {type: "json_schema", json_schema: {name, strict: true, schema}}`
  is sent first. If the gateway answers 400, 404 or 422, the **same** request is
  re-sent once with `response_format: {type: "json_object"}`. Nothing else is
  retried: 401, 403, 429 and 5xx are answers about the key, the quota and the
  provider, and are surfaced as such.
- `max_tokens` is set explicitly (start at 6000; a 60-dish menu is several thousand
  output tokens and a truncated array is an unrecoverable `badResponse`).
- Timeout **120 seconds** per request. A slow model is not an offline device; the
  timeout maps to `timeout`, never to `offline`.
- The model id is a constant in `open_router_client.dart` with a documented fallback
  list. Free-tier ids retire without notice; before every release, run the real
  system prompt against the pinned id and confirm it answers in under 20 seconds.
  A 404 on the pinned model is `badResponse` with copy that names the model, so the
  user learns "the model changed", not "no internet".
- Headers: `HTTP-Referer` and `X-Title` identifying KetoClub, which OpenRouter asks
  for and which lets the request work from a browser origin.

### 9.4 The parser rules

`MenuResponseParser.parse(String body, {required Menu source})` is static, pure,
and never throws. In order:

1. Strip a markdown fence if present. `jsonDecode` inside `try`; any throw →
   `badResponse`.
2. Root not a map, or `dishes` missing or not a list → `badResponse`.
3. Per element: `id` must match a dish in `source` **or** `name` must share at least
   one word of ≥ 3 letters with a source dish name after `text_normaliser` on both
   sides. Otherwise the element is an invention and its name goes to `unclassified`
   (constraint 6).
4. `verdict` matched by string, never by ordinal; `why` non-empty. Either failing →
   `unclassified`.
5. `verdict == modifiable` with a null, blank, or over-length `modification` →
   `unclassified` (constraint 7). A green or red carrying a `modification` keeps the
   verdict and drops the field.
6. Caps: more than 150 dishes → `badResponse`; `why` and `modification` truncated at
   300 characters, never rejected for length alone.
7. Source dishes the model did not mention at all go to `unclassified` by name, so
   the user sees the model skipped them.
8. `dishes` empty and `unclassified` empty → `MenuAnalysisFailed(noDishesFound)`;
   `dishes` empty but `unclassified` non-empty → `MenuAnalysed` with an empty list,
   because "the model saw the dishes and could place none" is a result to show, not a
   failure to retry.

All caps and verdict names live in `constants.dart`.

---

## 10. Failure handling

Every service returns a sealed result; nothing in `services/` throws across its
boundary. Failure reasons are enums, and each reason has its own copy in both
languages. Collapsing reasons is a bug.

| Reason | Where it arises | What the user sees | Way out |
|---|---|---|---|
| `MenuFetch.offline` | adapter, socket/DNS error | "No connection. Showing the cached menu from {date}." (if any) | retry |
| `MenuFetch.notFound` | adapter, 404 | "Venue not found on {platform}. Check the link." | edit input |
| `MenuFetch.platformChanged` | adapter, non-JSON / unexpected shape | "{platform} changed its menu format. Please report this." | report |
| `MenuFetch.unsupportedSource` | repository | "KetoClub cannot read menus from this site yet." | paste text (Phase 4) |
| `Analysis.notConfigured` | router, no key or no consent | rules result + "Add an OpenRouter key in Settings for AI analysis." | settings |
| `Analysis.offline` | router / client, no route | rules result + "Offline. Showing rule-based results." | retry |
| `Analysis.timeout` | client, > 120 s | rules result + "The AI model was too slow. Showing rule-based results." | retry |
| `Analysis.rateLimited` | client, 429 | rules result + "Daily AI limit reached for this key." | wait |
| `Analysis.unauthorised` | client, 401/403 | "Your OpenRouter key was rejected." **no rules fallback** | settings |
| `Analysis.badResponse` | client (4xx/5xx other), parser | "AI analysis failed ({detail}). Showing rule-based results." | retry / report |
| `Analysis.noDishesFound` | parser | "The AI could not identify any dishes on this menu." | try rules |

`ChatFailed` carries a status code and a short category, never the upstream body:
an upstream error body can echo request headers, including the bearer token.

---

## 11. Security and privacy

- **The key.** Stored in `flutter_secure_storage` (Keychain on iOS, Keystore-backed
  on Android, browser storage on web with an explicit note in Settings that web
  storage is weaker). Read only by `OpenRouterClient`. Never in logs, never in a
  failure value, never in analytics (there are none), never in the cache.
- **What leaves the device, and to whom.**
  - To the restaurant platform: the venue identifier. Nothing else.
  - To OpenRouter: dish names, descriptions, option labels, and the optional dietary
    constraints from Settings. No location, no venue name, no user identity.
  - Nowhere else. There is no telemetry.
- **Consent.** The first time a key is entered, Settings shows one disclosure stating
  the above in plain language, and the user confirms once. The router treats
  "no consent" exactly like "no key".
- **The model's output is data.** It is parsed by rules and rendered as text. No
  field is ever executed, used as a URL, or used to choose code paths beyond the
  three-valued verdict.
- **Menu content is untrusted too.** A dish named "ignore previous instructions" is
  a dish with an odd name; it is sent in the user turn, never the system turn, and
  it fails or passes the parser like any other.
- **No secrets in the repo.** `.gitignore` already excludes `.env*`; there is nothing
  to put in one.

---

## 12. Localisation

- **UI languages:** Hebrew and English, selected in Settings, defaulting to the device
  locale. `flutter_localizations` with ARB files in `lib/l10n/`. Hebrew is RTL;
  layouts use `start`/`end`, never `left`/`right`.
- **Waiter scripts follow the menu, not the UI.** A Hebrew menu gets a Hebrew script,
  an English menu an English one, because the script is read to a waiter in a
  specific restaurant. The prompt says so; the heuristic engine picks its template
  language by detecting Hebrew letters in the dish text.
- **Dish names are shown exactly as the platform prints them**, untranslated, so the
  user can point at the same line on the physical or in-app menu.
- **Heuristic vocabulary is bilingual.** Every English trigger in `constants.dart`
  has its Hebrew equivalents beside it. Matching runs on text normalised by
  `text_normaliser.dart` (lowercase, niqqud and punctuation stripped, final-form
  letters folded).
- **Prices** are formatted with `intl` for the UI locale, in ILS.

---

## 13. Platform notes

### Web

- **CORS blocks the restaurant adapters in a browser.** The platform APIs answer
  browser requests from foreign origins without `Access-Control-Allow-Origin`. This
  is a property of those services, not of the app. Consequences for the MVP:
  - Live menu fetching is a **mobile** feature first.
  - The web build ships with the classifier fully working (OpenRouter permits
    browser-origin calls) and takes menus by paste or, once Phase 4 lands, by file.
  - For local development, run Chrome with web security disabled
    (`flutter run -d chrome --web-browser-flag=--disable-web-security`); never ship
    with that.
  - The clean fix is a tiny CORS-forwarding proxy (a single edge function) that
    passes the request through unchanged and adds the header. That is the first
    thing the Phase 3 backend does, and it is the only reason to add one before
    community features.
- Geolocation requires HTTPS.
- Secure storage on web is `localStorage`-backed; say so in Settings.

### iOS

- `NSLocationWhenInUseUsageDescription` in `Info.plist`.
- App Transport Security: all endpoints are HTTPS; no exceptions needed.

### Android

- `ACCESS_FINE_LOCATION` and `INTERNET` in `AndroidManifest.xml`.
- `minSdk` 21 or higher for `flutter_secure_storage`.

---

## 14. Decisions log

Short ADR-style records of the choices that resolve the contradictions in the older
documents. Each names what was decided, why, and what it supersedes.

**D1 — Client-only. No backend, no server database.**
Supersedes README §9 ("Backend Service Setup", PostgreSQL). The MVP has nothing a
server would do better, and a server would need a hosted key and a data policy. A
backend enters at Phase 3 for community data and, optionally, a CORS proxy for web.

**D2 — The LLM is the primary classifier; rules are the fallback.**
Supersedes README §3/§6 and `CLAUDE.md`'s "heuristic-based classification". Follows
`feature_prioratization` Tier A and the engine analysis in
`m16_menu_scanner_research.md` §4: a rule table cannot explain *why* or write a
dish-specific instruction, and cannot read a dish it has never seen. The rule engine
stays because it answers offline and without a key, behind the same interface.

**D3 — Bring your own OpenRouter key.**
Follows `feature_prioratization` Tier A. Shipping a key in a client is not an option,
and a proxy is D1's backend. Free-tier quota is 50 requests a day, which one request
per menu plus a cache makes workable.

**D4 — Standalone app with a flat layout and `provider`.**
The m15/m16 documents describe a separate, existing Flutter application (Keto Lens,
diary, riverpod, sembast, Tesseract, milestones M2–M16). KetoClub is **not** a module
of that app and does not adopt its feature-first layering, riverpod, or sembast. Its
post-mortems are still the best evidence available on OpenRouter behaviour, and their
lessons are carried over as rules: distinct failure reasons (constraint 10), the
120-second timeout, strict-schema shape with a `json_object` fallback, verifying the
model with the real prompt before release, the parser discipline in §9.4.

**D5 — Text is the one classifier input.**
Every source, including future OCR, is normalised to dish text before
classification. One prompt, one parser, one fake. A vision-model path is a second
`MenuClassifier`, not a change to this one.

**D6 — One request per menu.**
Per-dish requests would burn the free quota on a single restaurant and cost the
user latency per card.

**D7 — Hebrew and English, Israel first.**
The four platforms are Israeli; menus are Hebrew, English, or mixed. Waiter scripts
are generated in the menu's language.

**D8 — Nothing about the user is stored.**
No diary, no macro tracking, no profile. The meal-logging design in
`m15_meal_entry_research.md` belongs to the other application and is out of scope
here.

**D9 — Web is a first-class target for classification and a second-class target for
live fetching**, until a CORS proxy exists (§13).

---

## 15. Testing strategy

- **Adapters:** one checked-in real JSON fixture per platform in `test/fixtures/`,
  and a normalisation test that pins category count, dish count, price conversion,
  and option flattening. Re-record the fixture when the platform changes; the test
  failing is the alarm.
- **Heuristic classifier:** table-driven tests over the README examples plus Hebrew
  equivalents. Every entry in `CARB_MODIFIERS` and `NON_KETO_BASES` has at least one
  positive case and one word-boundary negative case (`rice` must not match `price`).
- **Parser:** the eight rules of §9.4, each with a positive and a negative fixture,
  including: fenced JSON, invented dish, yellow without instruction, green with
  instruction, over-cap list, model skipped a dish, all-unclassified.
- **LLM client:** a fake `http.Client` asserting the request body (model, schema,
  `max_tokens`, no key in the body), the `json_schema` → `json_object` single
  fallback, and that 401/429/5xx are not retried.
- **Router:** no key → rules; offline → rules; LLM `timeout` → rules with reason;
  LLM `unauthorised` → failure, no rules.
- **Widgets:** a red group collapses with a count; an unclassified section renders;
  a yellow card always has script text; the engine chip reflects the result.
- **Integration:** two flows with `MenuClassifier` faked at the interface — paste a
  Wolt URL and see a classified menu; open Settings, enter a key, confirm consent.
- **Rule:** no test opens a socket. CI runs `flutter analyze`, `dart format --set-exit-if-changed`,
  and `flutter test`.

---

## 16. Build order and extension points

Build in this order; each step is demonstrable on its own.

1. **Skeleton** — `flutter create`, dependencies, `analysis_options.yaml`, ARB files,
   the `models/` package, the sealed result types. No screens yet.
2. **Heuristic classifier** — `constants.dart`, `classification_rules.dart`,
   `HeuristicMenuClassifier`, and its tests. Validates the model shapes before any
   network code exists.
3. **Wolt adapter + repository + cache** — fixture-tested normalisation, Hive cache,
   paste-a-URL resolution.
4. **Menu screen** — `MenuController`, `DishCard`, `StatusBadge`, filters, red group,
   unclassified section, engine chip, Waiter Card. At this point the app is usable
   offline with the rules engine.
5. **OpenRouter client + LLM classifier + router + Settings** — key store, consent,
   prompt, schema, parser, fallback logic, failure copy. Verify the pinned model
   against the real prompt before merging.
6. **10bis adapter.**
7. **Location and nearby search.**
8. **Platform setup** — permissions, icons, store metadata; test on a physical iOS
   and Android device with a real Wolt venue.

Extension points already designed in:

| Future feature | Where it plugs in | What must not change |
|---|---|---|
| Tabit, Ontopo | a new `PlatformMenuAdapter` | `Menu` model, classifier |
| Photographed or PDF menus (Phase 4) | a new source that yields `Menu` from OCR text; the M16 research is the reference | the prompt and parser |
| Vision-model classification | a second `MenuClassifier`; router chooses | the UI |
| Custom dietary rules (Tier C) | `ClassificationOptions` → appended to the system prompt and to the rules table | schema |
| Community ratings, venue directory (Phase 3) | a backend with its own client under `services/community/`; `Venue` gains the README's rating fields | everything above stays client-only |
| CORS proxy for web | one edge function; adapters get a configurable base URL | adapter logic |
| Shared analysis cache (Tier D) | the same backend; `MenuCache` gains a remote tier | parser, models |

---

## 17. Open questions

Things this document could not settle from the available material. Each has a
default the implementation follows until answered.

1. **Which OpenRouter model to pin.** Free-tier ids rotate. Default: choose at
   implementation time by running the real system prompt against candidates and
   pinning the fastest one that returns valid JSON in under 20 seconds; record the
   measurement in the client's doc comment.
2. **Exact Wolt venue-search endpoint** for nearby search. `menu_api_research` covers
   menus only. Default: ship paste-a-URL first (Tier A) and discover the search
   endpoint with the reverse-engineering protocol in `README.md` when building
   step 7.
3. **Tabit token flow details.** Unverified beyond "a session token is issued on the
   QR landing page". Default: defer the adapter until a real payload has been
   captured.
4. **Whether to show `net_carbs_estimate` at all.** The model can produce a number;
   it cannot be trusted as fact. Default: keep it in the model, do not render it in
   the MVP.
5. **Cache freshness window.** 24 hours is a guess. Default: 24 hours, configurable
   in `constants.dart`.
