# KetoClub — Architecture

**Status:** living design document. **Phase 1 is built** — build-order steps 1 to 5
(§16): the models and service contracts, the bilingual heuristic engine, Wolt
ingestion with a Hive cache, the classified menu screen and Waiter Card, and the
LLM client with its router and Settings. **Phase 3 backend foundations and hosted
classification landed next** (D11, D12): a local FastAPI backend (`backend/`)
proxies Wolt for the web build and forwards one chat completion per menu to
Google Gemini. **Since D17, iOS and Android call Wolt and Gemini themselves**:
the backend's proxy and chat routes serve the web build only, and a phone calls
Gemini directly with an API key the user pastes into Settings. Phase 2 (10bis,
nearby search) is still to come. When code and this document disagree, fix one of
them in the same pull request; the entries marked *(Phase 1)* below record where
that already happened, D11/D12 in §14 record the backend addition, and D17 records
where the phones stopped using it.

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
18. [Engineering standards](#18-engineering-standards)
    - 18.1 SOLID, as concrete rules for this codebase
    - 18.2 The import graph is a DAG
    - 18.3 Clean-code rules
    - 18.4 Tests from day one
    - 18.5 Continuous integration
    - 18.6 Definition of Done for a pull request
    - 18.7 What these standards changed in the architecture

---

## 1. What KetoClub is, in one paragraph

KetoClub is a Flutter app (web, iOS, Android) for people on a ketogenic diet who
want to know what they can order at a restaurant. The user picks a venue, the app
pulls that venue's live menu straight from a delivery or POS platform (Wolt first,
then 10bis, later Tabit and Ontopo), classifies every dish as 🟢 order-as-is,
🟡 order-with-a-change, or 🔴 not keto, and for every yellow dish produces an exact
sentence to say to the waiter. Classification is done by Google's Gemini model:
on iOS and Android the app calls it directly with the user's own API key (D17);
on web it goes through KetoClub's own backend, which holds a key the browser
never sees (D12). When there is no key or backend, no consent, or no network,
an on-device rule engine gives a coarser answer. A small local FastAPI backend
(D11) also proxies Wolt's menu API so the web build can fetch a live menu despite
CORS. The backend is an accelerator, not a dependency: with none configured the
app behaves exactly as the fully client-only version did, and it stores nothing
about any individual user — see §11.

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
│  │  MenuClassifier ── RoutingMenuClassifier ┬── LlmMenuClassifier ── LlmChatClient│ │
│  │                                       │     (GeminiChatClient on a phone,   │ │
│  │                                       │      BackendChatClient on web, D17) │ │
│  │                                       └── HeuristicMenuClassifier           │ │
│  │                                                                             │ │
│  │  LocationService   VenueSearchService   MenuCache   InstallIdStore          │ │
│  │  ApiKeyStore (phones only, D17)                                             │ │
│  └───────────────┬──────────────────┬────────────────┬──────────────┬──────────┘ │
│                  │                  │                │              │             │
│           geolocator           http client      Hive (cache)  shared_preferences │
└──────────────────┼──────────────────┼──────────────────────────────────────────────┘
                   │                  │
        OS location services   ┌──────┴──────────────────────────────────────────┐
                               │ consumer-api.wolt.com*    www.10bis.co.il        │
                               │ tgp-api.tabit.cloud       ontopo.com             │
                               │ generativelanguage.googleapis.com  (phones, D17) │
                               │ {KETOCLUB_BACKEND_URL}/v1/chat, /v1/proxy/wolt/… │
                               │   (web only; backend holds its key, D11/D12)    │
                               └─────────────────────────────────────────────────┘
```

\* direct from iOS/Android; the web build reaches Wolt through the backend proxy
when `KETOCLUB_BACKEND_URL` is configured (D11, §13). iOS and Android never call
the backend at all, even when the define is set (D17).

Three layers, one direction of dependency: **presentation → state → services**.
Services never import Flutter widgets. Models are plain Dart and are shared by all
three layers.

---

## 3. Guiding constraints

These are the rules every component in this document obeys. They are numbered so
issues and reviews can cite them.

1. **Client-first, backend-optional (D11).** The Phase 3 backend
   (`backend/`, run locally on `localhost:8000`) is an accelerator, never a
   dependency: with no `KETOCLUB_BACKEND_URL` configured, the app behaves exactly
   as the fully client-only version did. Every classified-menu result still lives
   on the user's device; the backend keeps a short-lived proxy cache and a shared
   completion cache (§6.4, `backend_plan.md`), never a per-user record.
2. **One codebase, three targets.** Web, iOS and Android share all business logic.
   Platform differences are confined to permissions, HTTP transport and layout.
3. **The key belongs to whoever makes the call (D12, D17).** On web the language
   model is reached through KetoClub's backend, which holds a Google Gemini key
   server-side, and the browser holds no key at all. On iOS and Android the app
   calls Gemini itself with a key the user pastes into Settings, kept in the
   Keychain or Keystore and sent to Google alone. Either way the consent toggle
   in Settings decides whether dish text leaves the device at all.
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
13. **Engineering standards apply from the first commit.** SOLID, an acyclic
    import graph, clean-code rules, unit and flow tests, and a CI pipeline that
    gates every pull request are defined in §18 and are not deferred to "after the
    MVP". The workflow, lint configuration and architecture test landed with the
    first skeleton, before any feature code.

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
 MenuClassifier.classify(menu)           RoutingMenuClassifier picks the engine (§6.2)
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
     🟢 green  ·  🟡 yellow (expandable waiter script)  ·  🔴 red (inline; counter tile filters)
     ⚪ unclassified (listed, no colour)  ·  chip showing which engine produced the result
```

Two properties of this pipeline are load-bearing:

- **Text is the one input shape for the classifier.** Whether a menu came from Wolt,
  10bis, Tabit, or (in Phase 4) a photographed page, the classifier receives a
  normalised `Menu` of strings. One prompt, one parser, one fake in every test.
- **One request per menu, not per dish.** The backend's per-install rate limit
  (D12: 5/minute, 40/day) is the current shape of the same pressure D6 first
  named against OpenRouter's free tier. A whole menu is one call; the cache
  (§6.4) makes the second look at the same menu cost nothing, and the backend's
  own shared completion cache (D12, issue #103) means the *first* look at a
  venue another user already analysed can cost nothing either.

---

## 5. Project structure

The layout below extends the one in `CLAUDE.md` with the pieces the LLM engine, the
key store and the cache need. Keep it flat; the app is small enough that a
feature-per-directory split would be ceremony.

```
ketoclub/
├── lib/
│   ├── main.dart                         # runApp(buildApp(buildDependencies()))
│   ├── di.dart                           # composition root: the ONLY file that constructs concrete services
│   ├── app.dart                          # MaterialApp, routes, theme, RTL/LTR, provider tree
│   │
│   ├── screens/
│   │   ├── venue_search_screen.dart      # the Discovery screen (issue #40, D13): location
│   │   │                                 # header, search, filter chips, venue cards
│   │   ├── menu_screen.dart              # classified menu, filters (green / green+yellow / all)
│   │   ├── waiter_card_sheet.dart        # full-screen high-contrast script + copy button
│   │   ├── settings_screen.dart          # consent text, net-carb limit, dietary toggles (#56) — no key section (D12)
│   │   ├── scan_screen.dart              # Scan tab placeholder (Phase 4, issue #11)
│   │   └── saved_screen.dart             # Recent tab (was "Saved"): cached menus, offline access, remove (#48, #251)
│   │
│   ├── theme/                            # design tokens as the app theme (rank 4, see below)
│   │   ├── app_tokens.dart               # raw sRGB constants converted from the artboard's oklch tokens
│   │   ├── verdict_colors.dart           # ThemeExtension<VerdictColors>: green/amber/red tones
│   │   ├── app_typography.dart           # TextTheme over the bundled fonts, with Hebrew fallbacks
│   │   └── app_theme.dart                # AppTheme.light() / AppTheme.dark()
│   │
│   ├── widgets/
│   │   ├── dish_card.dart                # name, price, badge, expandable script, net-carb chip
│   │   ├── status_badge.dart             # icon + colour, never colour alone
│   │   ├── waiter_script_widget.dart     # copyable instruction text
│   │   ├── engine_chip.dart              # "AI" / "rules (offline)" indicator
│   │   ├── verdict_counter_tiles.dart    # the three counters double as the green/yellow/red filter (§6.6)
│   │   ├── keto_score_badge.dart         # renders nothing when the score is null, never a fallback 0.0
│   │   ├── app_shell.dart                # bottom-nav shell around the four tab-root routes (issue #11)
│   │   ├── failure_copy.dart             # pure: failure reason → message; exhaustive, no default
│   │   ├── venue_card.dart               # Discovery result card; numbers only per D13
│   │   ├── category_chips.dart           # jump-to-category chips above a menu's dish list (#140)
│   │   ├── photo_tile.dart               # dish/venue photo with a placeholder tile (#50)
│   │   ├── offline_banner.dart           # persistent offline banner (issue #68)
│   │   ├── fetch_failure_action.dart     # retry action for a failed fetch (#144)
│   │   ├── analysis_progress_row.dart    # names the engine while a menu is analysed (#137)
│   │   ├── menu_search_field.dart        # search within a loaded menu (#140)
│   │   ├── note_editor_sheet.dart        # personal, local-only notes on a dish (#131)
│   │   ├── rules_reason_banner.dart      # why a menu fell back to the rule engine (#125)
│   │   └── mobile_qr_scanner.dart        # MobileQrScanner + its camera page; the ONLY file importing
│   │                                     # package:mobile_scanner (#182); here, not in services/, since it owns a page
│   │
│   ├── state/                            # ChangeNotifiers; constructor-injected with interfaces
│   │   ├── app_dependencies.dart         # immutable holder of service interfaces; filled by di.dart
│   │   ├── venue_search_controller.dart  # the Discovery screen (issue #40, D13)
│   │   ├── menu_controller.dart
│   │   ├── saved_controller.dart         # the Recent tab (issue #48)
│   │   ├── scanned_pages_registry.dart   # a scan's pages, in memory only, for "View pages" (#89)
│   │   ├── settings_controller.dart
│   │   ├── theme_mode_controller.dart    # Light/Dark/System appearance setting (#129)
│   │   └── locale_controller.dart        # the app-wide language switch (not tied to one screen)
│   │
│   ├── services/                         # every folder: interface(s) + implementations + fakes-friendly seams
│   │   ├── platform/                     # rank 0 — abstractions over the device/runtime
│   │   │   ├── clock.dart                # abstract Clock { DateTime now(); }  (cache freshness, tests)
│   │   │   ├── app_logger.dart           # abstract AppLogger; never sees the key or an upstream body
│   │   │   ├── connectivity.dart         # abstract Connectivity { Future<bool> isOnline(); } — a hint, never a verdict (§14 D10)
│   │   │   ├── screen_brightness.dart    # raises brightness for the Waiter Card, restores it on close
│   │   │   └── qr_scanner.dart           # interface QrScanner { scan() → String? } + NoQrScanner (#182)
│   │   ├── storage/                      # rank 0
│   │   │   ├── api_key_store.dart        # interface + SecureApiKeyStore: the user's Gemini key, phones only (D17)
│   │   │   ├── install_id_store.dart     # interface + PrefsInstallIdStore; replaces key_store.dart (D12)
│   │   │   ├── menu_cache.dart           # interface + HiveMenuCache
│   │   │   ├── notes_store.dart          # interface + PrefsNotesStore: personal, local-only dish notes (#131)
│   │   │   └── settings_store.dart       # interface + PrefsSettingsStore
│   │   ├── llm/                          # rank 0
│   │   │   ├── llm_chat_client.dart      # interface, ChatResult, ChatFailureReason
│   │   │   ├── backend_chat_client.dart  # the ONLY file naming `/v1/chat`; the web build's client (D12)
│   │   │   └── gemini_chat_client.dart   # the ONLY file naming Google's host; the phones' client (D17)
│   │   ├── location/                     # rank 0
│   │   │   ├── location_service.dart     # interface + sealed LocationResult (issue #37)
│   │   │   └── geolocator_location_service.dart # GeolocatorLocationService; the ONLY file importing package:geolocator
│   │   ├── venue/                        # rank 0
│   │   │   ├── venue_ref_resolver.dart   # pure: pasted URL / slug / ID → VenueRef
│   │   │   ├── qr_payload_router.dart    # pure: a scanned QR payload → QrVenue / QrUnsupportedSource / QrPhotographInstead (#182)
│   │   │   ├── venue_search_service.dart # interface only (issue #39)
│   │   │   └── wolt/
│   │   │       ├── wolt_venue_search_service.dart # HTTP only; delegates to the mapper
│   │   │       └── wolt_venue_mapper.dart # pure: Wolt discovery JSON → Venue (fixture-tested, no I/O)
│   │   ├── menu/                         # rank 1 — may import storage/ and platform/
│   │   │   ├── menu_repository.dart      # interface + CachedMenuRepository (cache-first, adapter registry)
│   │   │   ├── platform_menu_adapter.dart# interface: fetch(VenueRef) → MenuFetchResult
│   │   │   ├── wolt/
│   │   │   │   ├── wolt_adapter.dart     # HTTP only; delegates to the mapper
│   │   │   │   └── wolt_menu_mapper.dart # pure: Wolt JSON → Menu (fixture-tested, no I/O)
│   │   │   ├── tenbis/                   # same split: TenBisAdapter + TenBisMenuMapper (#126, #127, #134)
│   │   │   ├── website/                  # D19 (#181): WebsiteMenuAdapter; pure locator, JSON-LD mapper,
│   │   │   │                             # HTML reader, robots.txt; direct and backend fetchers
│   │   │   ├── tabit/                    # not built; a future phase
│   │   │   └── ontopo/                   # Phase 4 (PDF links only), not built
│   │   └── classifier/                   # rank 1 — may import llm/ and platform/
│   │       ├── menu_classifier.dart      # interface only
│   │       ├── classifier_router.dart    # RoutingMenuClassifier: picks LLM or rules per call
│   │       ├── llm_menu_classifier.dart
│   │       ├── menu_analysis_prompt.dart # system prompt, user prompt builder, JSON schema
│   │       ├── menu_response_parser.dart # §9.4 — pure, static, never throws; parse + parseScanned
│   │       ├── heuristic_menu_classifier.dart
│   │       ├── scanned_menu_classifier.dart   # the scan path's sibling interface (D15)
│   │       ├── vision_menu_classifier.dart    # pages → one vision request → Menu + analysis (#89)
│   │       └── scanned_classifier_router.dart # consent + connectivity, no rules fallback (#89)
│   │
│   ├── models/                           # plain Dart, immutable, no Flutter beyond foundation
│   │   ├── venue.dart
│   │   ├── menu.dart                     # Menu, MenuCategory, Dish, DishOption
│   │   ├── analysis.dart                 # DishVerdict, AnalysedDish, MenuAnalysis (sealed)
│   │   └── failures.dart                 # MenuFetchFailureReason, MenuAnalysisFailureReason
│   │
│   ├── utils/
│   │   ├── constants.dart                # CARB_MODIFIERS, NON_KETO_BASES, templates, caps
│   │   ├── classification_rules.dart     # compiled regexes for the heuristic engine
│   │   ├── text_normaliser.dart          # lowercase, strip niqqud/punctuation, for provenance
│   │   ├── price_format.dart             # agorot → ILS, locale-aware formatting
│   │   ├── wolt_headers.dart             # wolt.com's web-client header set (#168)
│   │   └── keto_score.dart               # menu-level score from the dish verdicts, for KetoScoreBadge
│   │
│   └── l10n/
│       ├── app_en.arb
│       ├── app_he.arb
│       └── generated/                    # `flutter gen-l10n` output, committed; excluded from
│                                         # the analyzer, the coverage gate, the all-imports
│                                         # helper and the architecture test (§18.2)
│
├── test/
│   ├── architecture/
│   │   └── import_rules_test.dart        # §18.2: layer order + cycle detection over lib/
│   ├── fixtures/                         # checked-in platform JSON + menu transcripts
│   ├── fakes/                            # one fake per interface, shared by unit and flow tests
│   ├── services/                         # mirrors lib/services/ one-to-one
│   ├── state/
│   ├── utils/
│   ├── screens/                          # one widget test per screen, dependencies faked
│   └── widgets/
├── integration_test/
│   └── flows/                            # §18.4: user journeys on a real browser/device (FLOW_TEST_CONVENTIONS.md)
├── test_driver/integration_test.dart     # driver for `flutter drive` on web
├── tool/
│   ├── check.sh                          # runs exactly what CI runs
│   ├── coverage_gate.sh                  # fails below the coverage threshold
│   └── gen_coverage_helper.sh            # imports every lib/ file so untested files count
├── .github/workflows/ci.yml              # §18.5, gained a required `backend` job
├── ios/  android/  web/
├── pubspec.yaml
├── analysis_options.yaml                 # very_good_analysis + strict modes
│
└── backend/                              # D11 — Phase 3, optional at runtime
    ├── app/
    │   ├── main.py                       # app factory: CORS, lifespan, routers
    │   ├── config.py                     # pydantic-settings (GEMINI_*, WOLT_BASE_URL, …)
    │   ├── routers/                      # health.py, proxy.py, chat.py
    │   └── services/                     # wolt.py, gemini.py, cache.py, rate_limit.py
    ├── tests/                            # respx-mocked; no test reaches the network
    ├── check.sh                          # mirrors tool/check.sh; its own required CI job
    └── README.md                         # setup, routes, the manual end-to-end check
```

**The `theme/` layer (issue #9):** rank 4, the same rank as `widgets/`. It holds the
design tokens (`app_tokens.dart`), the `ThemeExtension<VerdictColors>` the verdict
palette lives on, the bundled-font `TextTheme` and `AppTheme.light()` /
`AppTheme.dark()`. It sits at 4 rather than lower because a theme is themable UI
configuration, not a service or a piece of app state: it depends on nothing in
`state/` or `services/` (an `AppTheme` is built from constants alone, with no
injected dependency), and nothing below `widgets/` should ever need to read it —
`state/` controllers hold data, not colours. Rank 4 gives `widgets/` (4), `screens/`
(5) and `app.dart` (6) the read access they need to theme their output, while
keeping `state/` (3) and `services/` (2) from importing it, which would be a sign
that colour had leaked into a layer that must stay presentation-agnostic. The
`Colors.*`/`Color(0x...)` grep test (`test/architecture/theme_tokens_test.dart`)
enforces the flip side: no file outside `theme/` may declare its own colour
literal.

**Dependency rules, enforced by `test/architecture/import_rules_test.dart` (§18.2):**

- Layer order, lowest first: `models`, `l10n` → `utils` → `services` → `state` →
  `widgets`, `theme` → `screens` → `app.dart` → `di.dart`, `main.dart`. A file may
  import only files in its own layer or a lower one.
- Inside `services/`, sub-packages have a rank (shown in the tree). A sub-package
  may import only sub-packages of equal or lower rank. Within one sub-package the
  cycle check still applies.
- `models/`, `utils/` and `services/` import nothing from Flutter beyond
  `package:flutter/foundation.dart`.
- `screens/` and `widgets/` reach services only through a controller in `state/`.
- The full import graph of `lib/` has no cycles.
- Four host-string rules, enforced by `test/architecture/import_rules_test.dart`
  (D11, D12 — supersedes the single `openrouter.ai` rule this bullet used to
  state): `restaurant-api.wolt.com` appears under `lib/` only in the venue
  search (`services/venue/wolt/wolt_venue_search_service.dart`, its by-name
  POST); `consumer-api.wolt.com` only there and in
  `services/menu/wolt/wolt_adapter.dart`, whose consumer-assortment path
  (direct and through `/v1/proxy/wolt/venues/…`) appears nowhere else, and
  the retired `menu/data` path nowhere at all (#168); `/v1/chat` only in
  `services/llm/backend_chat_client.dart`; `KETOCLUB_BACKEND_URL` only in
  `di.dart`; `googleapis.com` and the `x-goog-api-key` header only in
  `services/llm/gemini_chat_client.dart`, the phones' direct client (D17);
  `package:flutter_secure_storage/` only in `services/storage/api_key_store.dart`;
  and `openrouter` and `sk-or-` appear nowhere under `lib/` at all. Concrete
  service classes are constructed in exactly one file: `di.dart`.

**Dependencies (initial `pubspec.yaml`):**

| Package | Why |
|---|---|
| `http` | Restaurant APIs; on web, since D11/D12, KetoClub's own backend (`/v1/proxy/wolt/…`, `/v1/chat`); on phones, since D17, Google's Gemini API. Small, works on all three targets. |
| `provider` | State management. `ChangeNotifier` per screen is enough at this size. |
| `geolocator` | Device location on web, iOS, Android. |
| `hive` + `hive_flutter` | Menu and analysis cache. |
| `shared_preferences` | Non-secret settings (filters, language, last venue) and, since D12, the anonymous install id the web build sends to the backend. |
| `flutter_secure_storage` | The user's own Gemini API key on iOS and Android (D17): Keychain on iOS, Keystore-backed on Android. Dropped by D12, reinstated by D17; never used on web. |
| `flutter_localizations` + `intl` | Hebrew and English UI, RTL, number formatting. |
| `url_launcher` | Open the venue on the source platform. |
| `connectivity_plus` | Backs `Connectivity`, the pre-flight hint `RoutingMenuClassifier` consults before spending a backend chat request (§6.2, §8, §14 D10 — reinstated in Phase 1, extended to the backend by D11). |

Dev dependencies: `flutter_test` and `integration_test` (SDK), `very_good_analysis`
(lints, §18.3). Add `fake_async` when the first timeout is under test (§18.4).

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
| Wolt | `venue_slug` from the public URL | integer agorot → divide by 100; no currency in the payload, `ILS` assumed | `categories[].item_ids`, then each `subcategories[].item_ids` flattened into the parent → `items[]` by id | `items[].options[].option_id` → `options[]` by id; each value's `name` is appended to the dish's option text |
| 10bis | numeric `restaurantId` | decimal ILS as-is | `categoriesList[].dishList[]` | `dishOptionsList[]` |
| Tabit | `siteId` | check on first real payload | POS kitchen groups → categories | forced questions and modifiers |
| Ontopo | `venue_id` | n/a | returns `menu_pdf_url` / `external_menu_url`, not items | n/a |
| Website (D19) | the normalised pasted URL | never read: `price: 0`, no price shown | JSON-LD `MenuSection`s; else page text or a PDF read by vision | none |

Option labels ("Choice of side: potato purée / green salad") are part of the text the
classifier sees, because a dish's yellow-ness often lives in the options, not the
description — refined by D14 (§14): a non-keto **base** is never matched inside
option text, only within the dish's own name and description, and an option
**value** that names a removal ("No onions", "ללא אלף האיים") is dropped
entirely rather than read as an ingredient the dish arrives with. §6.2 has the
exact rule order the heuristic engine runs.

*(Phase 1)* Two normalisation rules the Wolt payload forced, both in
`wolt_menu_mapper.dart`: an `item_id` a category lists but `items[]` does not
contain is **skipped**, not an error; and a dish id appearing in two categories is
**deduplicated, first category winning**, because Wolt does list one item twice and
a duplicate id would break the parser's provenance and skipped-dish rules (§9.4
rules 3 and 7). An individually malformed `items[]` entry currently fails the whole
fetch as `platformChanged`, on the grounds that a loud schema-drift signal beats a
silently missing dish; if real payloads ship the occasional odd entry — a null price
on a "call for price" item — that trade should be revisited against a real
recording. *(#168)* The one real recording, `wolt_hamosad_menu.json`, has no such
entry, so the trade stands.

*(#168)* Wolt's `/v4/venues/slug/{slug}/menu/data` endpoint began answering every
anonymous caller with `200` and a zero-byte body (measured 2026-09-25 against two
venues, with and without the web-client headers), so the Wolt adapter now reads the
**consumer-assortment** endpoint wolt.com's own web app uses —
`GET consumer-api.wolt.com/consumer-api/consumer-assortment/v1/venues/slug/{slug}/assortment`
— sending the web-client header set §6.5's venue search already sent, now shared
from `lib/utils/wolt_headers.dart`. The payload keeps the three flat collections, so
the mapper's join survived; what changed is recorded in `wolt_menu_mapper.dart`'s
class doc comment: no top-level `currency` (the mapper assumes `ILS`, the currency of
every Wolt Israel venue), item options are objects whose `option_id` points into
`options[]` (the item-level `name` labels the group when it differs), photos move to
`images[0].url`, categories may carry `subcategories` (flattened into the parent,
inferred — every recorded one is empty), a `disabled_info` item is kept, and no venue
name is carried. An empty or non-JSON `2xx` body is still `platformChanged`, never an
empty menu. Device cache keys (`wolt/<slug>`) did not change, so Saved entries and
`lastVenue` survive the port.

`MenuRepository` owns the adapter registry, resolves a pasted URL to a `VenueRef`,
checks the cache first (§6.4), and is the only thing the controllers call.

**Web caveat (important):** the restaurant platform APIs do not send CORS headers
for arbitrary origins. Native iOS and Android HTTP stacks do not enforce CORS, so the
adapters work there as written. In a browser they will be blocked unless the request
goes through KetoClub's own backend proxy (D11, §13) — `WoltMenuAdapter` takes an
optional `proxyBase` for exactly this, wired in `di.dart` only when the web build was
compiled with `--dart-define=KETOCLUB_BACKEND_URL=…` and a proxy is not otherwise
used. With no backend configured, live menu fetching on the web build is still
blocked and paste-a-menu (Phase 4) remains the fallback path; see §13.

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
`MenuResponseParser`. It never touches `http` directly and never sees a model
key. `di.dart` hands it one of two `LlmChatClient`s (D17): on iOS and Android a
`GeminiChatClient` that calls Google directly with the key in `ApiKeyStore`; on
web a `BackendChatClient` that posts to KetoClub's own backend, which holds the
Gemini key server-side (D12).

**`HeuristicMenuClassifier`** — the fallback. A Dart port of the README's
`analyze_dish`, run per dish through `ClassificationRules.matchDish` (D14, §14;
issues #191, #192), in this order:

1. A dish **name** that is nothing but an unguarded carb-modifier trigger plus
   portion/qualifier words (`carbOnlyQualifiers{En,He}` — portion, bag, tray,
   plain, regular, large, sourdough, gluten free, מנת, מגש, שקית, רגילה, ללא
   גלוטן, מחמצת…) is red, labelled with the trigger itself: "Portion of
   fries", "פיתה רגילה". Only the starches and breads in
   `carbOnlyEligibleTriggers` can fire it — never a sauce or root vegetable
   ("Carrots" is not "built on carrots"), and never the bread-carried
   families (burger, sandwich, wrap, toast), which stay a D-V3 yellow. And
   never when the description or a non-removal option names a filling
   (`describesFilling`: a protein, a plant or dairy word): "לאפה" described
   as "שווארמה, חומוס, סלט" is the dish D-V3 means, not the carb itself.
2. Otherwise, `NON_KETO_BASES` is matched against
   `TextNormaliser.dishCoreText` — the dish's name and description only,
   never its options — so an option group named after a red base (an "ארוחת
   נאגטס" meal upgrade on a burger) can never redden the dish on its own.
3. Otherwise, `CARB_MODIFIERS` is matched against
   `TextNormaliser.dishRulesText`: the core text plus every option group's
   name and non-removal values (a "choice of side" value still counts, per
   §6.1) but with every removal value dropped — one whose first word is
   `no`/`without`/`skip`/`ללא`/`בלי` (`optionRemovalWordsEn/He`) — giving a
   yellow with the mapped template sentence. Otherwise the dish is green.

None of this changes `TextNormaliser.dishSearchText` or `menuFingerprint`
(§6.4), which still hash the dish's full text including every option value
regardless of removal wording, so no cached analysis is invalidated by D14.

It runs on-device, offline, in milliseconds, and its result is labelled as "rules"
in the UI (`engine_chip.dart`) with its greens carrying a "not AI-verified" hint.
Hebrew triggers live next to the English ones in `constants.dart` (פירה, צ'יפס,
אורז, תפוח אדמה, פסטה, פיצה, לחמנייה, …).

*(Phase 1)* The vocabulary is no longer "deliberately small", and it needed three
relations this section did not anticipate, all in `constants.dart`:

- **`ketoQualifierGuards{En,He}`** cancel a trigger when a rescuing word sits
  beside it. Without them `cauliflower rice`, `spaghetti squash`, `zucchini
  noodles`, `kale chips` and `לחם ענן` all turned red and were hidden — the very
  dishes the app exists to surface, and the ones §7's `is_verified_keto_friendly`
  names. The Hebrew guards look both ways, because a Hebrew adjective follows its
  noun: `פיצה כרובית` is "cauliflower pizza".
- **`triggerSuppresses`** lets the more specific phrase win, so `sweet potato` does
  not also emit the generic potato sentence.
- **`nonKetoBaseLabels{En,He}`** render `{base}` in the red `why`. Required, not
  decoration: the matched substring is the *normalised* form, so without them the
  text read aloud to a waiter would be `ציפס`, `תפוא`, `ראמנ`.

Four scope decisions, recorded as D-V1 to D-V4 in the constants' doc comments:
guards exist (above); **breading is red** (`fish and chips` previously returned
yellow with "replace the chips" and left the batter, an instruction that cannot make
the dish keto); **bread that merely carries a dish is yellow and removable**, which
makes README's own "serve the burger without the bun" template reachable for the
first time; and the Israeli trap list is adopted in full, so שווארמה בפיתה no longer
classifies green.

**Dart's `\b` is ASCII-only.** `RegExp(r'\bפסטה\b')` matches nothing at all, so a
literal port of README's `rf"\b{base}\b"` leaves the entire Hebrew vocabulary dead
while every English test passes. Hebrew triggers compile to a lookaround that is
permissive on the left — ב/ה/ו/כ/ל/מ/ש are grammatical particles, so `הפסטה` must
match — and strict on the right, because a suffix is a different word and folded
`לחמ` must not match inside `לחמנייה`. Latin triggers keep a plain word boundary and
must never be loosened: `toasted almonds` and `Sacramento tomato salad` would turn
red. `text_normaliser.dart` also folds diacritics, without which README's own worked
example, "butter-infused potato purée", failed its own `puree` trigger.

*(Issue #56)* The three "Your keto rules" toggles in Settings each add one more
rule here, active only while on — seed-oil, dairy and plant vocabularies that make
a green dish yellow with their own bilingual sentence and never touch a red one.
The table in §9.1 lists each toggle's prompt fragment, rule and hint copy side by
side.

*(Issue #216)* Drinks vocabulary added to both language sets. Sugary drinks are
red (`nonKetoBases{En,He}`): cola, coke, pepsi, sprite, fanta, juice, lemonade,
beer, lager, stout, ale, smoothie, liqueur, sweet wine, moscato, port wine, and
their Hebrew counterparts (קולה, קוקה קולה, ספרייט, פאנטה, פריגת, מיץ, לימונדה,
בירה, בירה שחורה, שיכר, ליקר, סמוטי, יין מתוק). Coffee drinks and tonic are yellow
(`carbModifiers{En,He}`): latte, iced latte, cappuccino, iced coffee, frappe, tonic,
tonic water, syrup, and Hebrew twins (הפוך, הפוך קר, לאטה, קפוצ'ינו, קפה קר, סירופ,
טוניק). Zero/diet/sugar-free labels rescue a red base via `ketoQualifierGuards{En,He}`:
"Coca-Cola Zero" and "קוקה קולה זירו" are green, not red. `הפוך` ("hafuch",
the Israeli upside-down latte) is compiled without a permissive prefix — its
prefixed forms mean "to flip/reverse" in Hebrew, and `_noPrefixHebrewTriggers`
already excluded `חלה` and `שמרים` for the same idiom-collision reason. The
`מיץ` bare trigger is intentionally included; if it produces a false positive
on a fixture dish, drop it and keep only the compound forms `מיץ תפוזים` /
`מיץ ענבים`. An offline bilingual reference screen (`/drinks`,
`DrinksGuideScreen`) is reachable from the menu screen's app bar and from
Settings. Its content lives in `drinks_guide_data.dart` as Dart literals
(the §6.3 exception), never in ARB.

**`RoutingMenuClassifier`** — decides, per call, in this order (revised by D12
and D17; the router itself checks only consent and connectivity — whether a key
is saved is the phone's chat client's answer, not a router rule):

1. Estimation consent not given → heuristic, with
   `engine = rules(reason: consentWithheld)`. This is client-only — fixable by
   the user in Settings without needing the server — and its copy must not
   mention the backend.
2. `Connectivity.isOnline()` answers false → heuristic, with
   `engine = rules(reason: offline)`, and the backend is never called. This is
   the same pre-check D10 (reinstated) describes; D11 extends it unchanged to
   the backend call: the pre-check exists solely to avoid spending a request —
   and the per-install rate-limit quota (§6.4 backend notes) — on a call that
   cannot succeed. `isOnline()` is a hint, not a verdict (documented on the
   interface itself), so this rule only ever produces a false *negative*: it can
   skip a call that would have worked, but never claims a call will fail when it
   would not have. A false positive (`isOnline()` says true, the call fails
   anyway) is simply rule 4 below, which stamps the exact same `offline` reason
   — the UI's copy cannot tell the two paths apart. Per D11 "the call is the
   probe": nothing pre-checks whether the *backend itself* is reachable: a
   `ClientException` posting to `/v1/chat` is simply `backendUnreachable`,
   handled by rule 4 like any other LLM-path failure.
3. Otherwise → the LLM path, via `GeminiChatClient` on a phone or
   `BackendChatClient` on web (D17).
4. If the call fails with `offline`, `timeout`, `rateLimited`, `badResponse`,
   `backendUnreachable` or `notConfigured` (web: no backend URL compiled in, or
   the server has no Gemini key), or — on a phone — `apiKeyMissing` (no key
   saved; nothing was sent) or `apiKeyRejected` (Google refused the saved key),
   fall back to the heuristic and
   surface that reason in the result, so the UI can say "showing rule-based
   results; AI analysis failed because …". A `badResponse` is shown with its
   reason named, never silently — which is what §6.2 and §10's table together
   require. Every reason but `noDishesFound` degrades to rules this way; there
   is no `unauthorised` reason any more (D12 removes it along with the key it
   described) — a web build with no `KETOCLUB_BACKEND_URL` define answers
   `notConfigured` and falls back the same way. A phone with no key saved
   answers `apiKeyMissing` the same way, which is how a fresh install reads
   until the user pastes a key (D17).
5. `noDishesFound` is returned as a failure rather than swapped for rules — §10
   gives that row "try rules" as a way out the user takes, not as an automatic
   degradation.

`RoutingMenuClassifier` receives both engines and `Connectivity` through its
constructor — no `KeyStore` any more, since D12 removed it entirely; `di.dart` is
where the concrete engines and the connectivity check are built and handed to it
(constraint 4, §18.1). Consent arrives per call in `ClassificationOptions`, not
as a dependency.

**`ScannedMenuClassifier`** — the scan path's sibling interface (D15; issue
#89), in `scanned_menu_classifier.dart`:

```dart
abstract interface class ScannedMenuClassifier {
  /// Never throws. One call per scan: all pages in one request (D6).
  Future<ScannedMenuResult> classify(
    ScannedMenu scan, {
    required ClassificationOptions options,
  });
}
// ScannedMenuResult = ScannedMenuRead(menu, analysis) | ScannedMenuFailed(reason)
```

It is not a `MenuClassifier` because a photograph has no `Menu` until it is
read, and putting page bytes on `Menu` or `VenueRef` would push them into the
Hive JSON cache. A `ScannedMenu` (`lib/models/scanned_menu.dart`, pages of
`{mimeType, bytes}`) has no `toJson` and lives only in memory; the `Menu` a
`ScannedMenuRead` returns is `MenuSource.scan`-sourced and carries no byte of
it, so it is stored and cached like a pasted menu. The Scan tab's pages come
from a `PagePicker` (`services/platform/page_picker.dart`, #82). The bounds
`maxScanPages` (6) and `maxScanPageBytes` (3 MiB) in `constants.dart` match
the backend's `VISION_MAX_IMAGES` and `VISION_MAX_IMAGE_BYTES`.

Two implementations (#89), wired in `di.dart` as
`RoutingScannedMenuClassifier(vision: VisionMenuClassifier(client, clock),
connectivity)`, over the **same** `LlmChatClient` instance the text
`LlmMenuClassifier` holds:

**`VisionMenuClassifier`** sends one request per scan (D6), all pages in it as
`images` in reading order. The system prompt is
`MenuAnalysisPrompt.visionSystemPrompt`: a vision preamble ("the user message
holds N pages of one menu; transcribe every dish name exactly as printed, in
the menu's language, ids `v1..vN` in reading order, then classify each"),
then the text path's `systemPrompt` byte for byte. The user prompt is one
short line; the response schema and `schemaName` are the text path's,
unchanged, so the backend's schema conversion is untouched. The reply goes to
`MenuResponseParser.parseScanned` (§9.4), which returns the transcribed `Menu`
and its `MenuAnalysed` together: `VenueRef(scan, <hex of the clock's
millisecond stamp>)`, one category `scanned` (named "Scanned menu" /
"תפריט סרוק" in the menu's own language, §12), every dish `price: 0` with no
description or options, and no `venueName`. The analysis is stamped
`LlmEngine(model)` with the model the provider reported and records the
options snapshot, exactly as the text path does. Chat failures map one to one
through the same `menuFailureReasonFor` the text classifier uses. An empty
scan sends nothing and is `noDishesFound`. A two-request design (transcribe,
then the text path) was rejected: checking provenance against a transcript
the model wrote checks the model against itself, and spends two of the day's
calls.

**`RoutingScannedMenuClassifier`** applies the text router's first two rules
and nothing else: consent withheld → `consentWithheld` with the chat client
never called (no page leaves the device); `Connectivity.isOnline()` false →
`offline`; otherwise the vision result as it is. **There is no rules
fallback for a photograph** — the heuristic needs dish text the pages do not
have — so every failure reaches the Scan tab as a `ScannedMenuFailed`, whose
copy `failure_copy.dart` already carries.

**Hand-off and "View pages".** The Scan controller (#82) calls the router,
then `repository.store(menu)` and `saveAnalysis(ref, analysis)`, puts the
pages in `ScannedPagesRegistry` (`state/`, on `AppDependencies.scannedPages`)
and opens `/venue/scan/{id}`. `MenuController.open` reuses that analysis
through the existing fingerprint-and-options check and never re-classifies a
scan; if consent is later withdrawn the reuse check fails and the text router
runs the heuristic over the transcription, which is correct by construction.
The registry holds the last few scans' pages in memory only — never Hive,
never JSON, never a log — so while it has a scan's pages the menu header
says "Read by AI from your pages" and offers "View pages" (a bottom sheet of
thumbnails; a PDF shows as a labelled tile), letting the user check the
transcription against the photograph. After a restart the pages are gone and
the menu reads as a pasted one.

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
  `constants.dart`, deduplicated, **in the menu's language** — detected per §12 from
  the dish's own text, not from the UI locale — one template per line: a newline
  is the script's instruction separator, which `WaiterScriptWidget` numbers, and
  the templates carry no terminal punctuation to separate them any other way
  (the visual audit, `docs/VISUAL_AUDIT.md`, found them joined by a space into one
  run-on line). *(Phase 1: this sentence used to say
  "in the UI language", which contradicted §12. §12 wins: the script is read aloud
  to a waiter in that restaurant, and the LLM engine already writes in the menu's
  language, so both engines now agree. The consequence is that the template
  sentences and the green/yellow/red `why` text live bilingually in
  `constants.dart` rather than in ARB — a deliberate, documented exception to
  §18.6's "no user-facing literal in Dart", because they are selected by menu
  language while `AppLocalizations` only ever yields the UI locale.)*

The Waiter Card (`waiter_card_sheet.dart`) renders the script full-screen in large
high-contrast type with a copy button, so the phone can be shown to the server.
*(Phase 1)* It also raises the device's screen brightness to full while open,
through `services/platform/screen_brightness.dart`, and restores it on close —
a hint the sheet acts on, never a guarantee: `ScreenBrightness.raise`/`restore`
never throw, so a platform that cannot change brightness (web among them) or a
plugin call that fails simply leaves brightness unchanged rather than breaking
the card. This is evidenced in tests only by a mocked method channel and a fake;
no physical device has exercised it (`HANDOFF.md`).

### 6.4 Local storage

| Store | Package | Holds | Lifetime |
|---|---|---|---|
| `InstallIdStore` | `shared_preferences` | a random 32-hex-character anonymous install id (D12), generated on first use, never in a constructor | until the app's storage is cleared |
| `MenuCache` | `hive` | `venueRef → {menu, analysis, fetchedAt, engine}`; the analysis also records the options it was made under (net-carb limit, dietary constraints; issue #57) | 24 h for the menu; analysis kept as long as the menu it was computed from, and reused by `MenuController` only for an unchanged menu, an AI result, consent still given and matching options |
| `SettingsStore` | `shared_preferences` | UI language, filter defaults, consent flag, last venue, appearance, net-carb limit (2–25 g, default 6), dietary toggles (seed-oil free, dairy-free, carnivore only; all off by default, a missing key reads as off) | until cleared |

The install id is unlinkable to a person (D8 stays true in spirit) and is sent
only as `X-KetoClub-Install-Id` to KetoClub's own backend, for its per-install
rate limiter (§6.2 rule 2 note, `backend_plan.md` §3.4) — never to a restaurant
platform, never to Google. There is no device-side secret store any more: D12
removed the one thing (`KeyStore`) that needed one.

**Server-side, not on the device.** The backend keeps two short-lived caches of
its own, described here because they replace what `KeyStore`'s removal might
otherwise seem to leave uncovered: a per-slug Wolt-proxy body cache
(`MENU_CACHE_TTL_SECONDS`, default 1 h) and a shared chat-completion cache keyed
by a hash of the request (`CHAT_CACHE_TTL_SECONDS`, default 24 h, equal to
`menuCacheTtl`) so one venue's analysis serves every user of it. Neither stores
an install id alongside its content (§11, `backend_plan.md` §3.5).

Cache rules:

- A cached **menu** is fresh for 24 hours. After that it is refetched; the old
  analysis is discarded only if the refetched menu differs (compare a hash of the
  normalised dish text).
- A cached **analysis** produced by the **heuristic** engine is replaced the next time
  the LLM engine is available, without asking, because it was always the weaker
  answer.
- The cache never stores the raw platform JSON, only the normalised `Menu`.
- The user can clear the cache from Settings.
- `MenuCache.size()` reports how many menus are cached — a count of entries, one
  per distinct `VenueRef`, never a byte figure. Hive's `Box` exposes how many keys
  it holds, not the on-disk size of the box file, and on web the box lives in
  IndexedDB with no file to size at all, so a byte count would be fabricated on at
  least one platform this app ships on. Issue #61's Settings "Saved menus" section
  ("count, size, clear") reads this as the count: how many menus there are to
  clear, not their storage footprint.

*(Phase 1)* Two things this list left open, both now decided and tested. The
freshness boundary is **exclusive**: a menu exactly 24 hours old refetches, because
"fresh for 24 hours" means younger than 24 hours. And `forceRefresh` skips only the
early return, not the cache *read*, so a forced refetch that fails still falls back
to whatever is cached and is never worse than the ordinary path.

No health data, no diary, no user profile is stored. KetoClub's storage is a cache
and one secret.

### 6.5 Location and venue search

`LocationService` wraps `geolocator`: request permission, get one position, degrade
gracefully to "type an address or a venue name" on denial or on web without HTTPS.

`VenueSearchService` has two entry points, both Tier A/B in
`feature_prioratization`:

1. **Paste a URL or ID** (Tier A, ships first). Recognises Wolt venue URLs
   (`wolt.com/…/restaurant/{slug}`), bare Wolt slugs, 10bis restaurant URLs
   (`10bis.co.il/…/restaurants/…/{numeric id}/…`, the id landing wherever the
   `restaurants` path segment is followed by a purely-numeric one — mirroring the
   `Restaurants/{id}/Menu` API shape from `menu_api_research` §3.2, since
   `10bis.co.il` was unreachable to record a page from directly), and bare 10bis
   restaurant IDs, and returns a `VenueRef`. No network needed for the resolution
   itself. A resolved 10bis `VenueRef` still fails with `unsupportedSource` once it
   reaches `MenuRepository` — no 10bis adapter exists yet (§16 build-order step 8)
   — so paste recognition and platform support are independent claims.
2. **Search nearby** (Tier B). Queries Wolt's venue search with the device position
   or a typed string and lists results with a name, address, and distance. Results are
   filtered client-side; no radius endpoint is assumed. The endpoints are
   documented from third-party evidence in `phase2_discovery_research.md` §2.1 —
   `GET consumer-api.wolt.com/v1/pages/restaurants?lat=&lon=` for "near me" and
   `POST restaurant-api.wolt.com/v1/pages/search` for a typed name, both
   anonymous, origin-locked (so the web build goes through the backend, as menus
   do under D11) and not yet confirmed by a recording (§17 question 2). What a
   result card shows before its menu is opened is D13: a score and counts only
   from an analysis already in the device cache, and no menu fetch on scroll or
   on load.

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
| `MenuScreen` | `/venue/:source/:id` | Classified menu with filters and engine chip; `/venue/scan/{id}` opens a pasted menu (D18) |
| `WaiterCardSheet` | modal | Large-type script with copy |
| `SettingsScreen` | `/settings` | Key entry, disclosure text, cache clear, language |
| `ScanScreen` | `/scan` | Collects menu pages from the camera, the photo library or a PDF, or a menu's text pasted into a field (D18). Analyse hands the pages to `ScannedMenuClassifier` in one call (D15), or the parsed paste to `MenuRepository.store`, and opens `/venue/scan/{id}` (#82, #83). "Scan QR code" (not on web) reads a table's QR code through `QrScanner`; `QrPayloadRouter` sends a Wolt, 10bis, website or PDF link to that venue's `/venue/{source}/{id}` route, and answers a Tabit code ("not supported yet") or an Instagram, Linktree or non-URL code ("photograph the menu instead") with copy on the Scan tab (#182) |
| `SavedScreen` | `/saved` | The "Recent" tab: the automatic 24-hour cache of every menu opened, pasted, scanned or read from a website, with offline access and remove (#48). Titled "Recent menus" with a history (clock) icon, not "Saved": nothing is saved by the user (#251). The route path and class names stay `/saved` / `SavedScreen` |

**The keto score badge's tone** *(issue #241)* follows the score's band, not a fixed green, so a low score never reads as a positive claim: 7 and above is `green.ink`, 4 up to 7 is `amber.ink`, below 4 is the muted `ink3` (`scoreTone`, judged on the score as printed to one decimal), in the menu header and on the venue card alike; `contrast_test.dart` pins each tone against the page background in both themes.

**The bottom-navigation shell** *(issue #11, Phase 1)*, not in this document when
the four screens above were written: `AppShell` wraps all four tab-root routes
(Explore `/`, Scan `/scan`, Recent `/saved`, Settings `/settings`) with a
`NavigationBar`. It is purely presentational — it takes an already-built `child`
and the `currentIndex` `app.dart`'s `generateRoute` supplies, and switches tabs
with `Navigator.pushReplacementNamed` rather than an `IndexedStack`, so the stack
never grows and each visit to a tab rebuilds its controller from scratch. `Scan`
and `SavedScreen` are stateless placeholders with localized copy explaining what
is missing, not stubs left silently blank; `MenuScreen` (reached from a search
result, not a tab) and `WaiterCardSheet` (a modal) sit outside the shell.

**Content is capped at 680px on a wide window** *(issue #221, Phase 8)*. Every
screen was drawn on a 390px artboard, and on a desktop browser a full-width
column turned the venue photo into a letterbox strip and stretched every button
across the monitor. `ContentWidth` (`widgets/content_width.dart`) centres a
screen's body and caps it at `contentMaxWidth` (680 logical pixels); it sits
just inside each `Scaffold` — Discovery, the menu route (its loading,
fetch-failure and empty states included), Scan, Saved, Settings and the drinks
guide — so the `Scaffold` background and app bar stay full-bleed and only the
content column is capped. At or below the cap it passes its child through
unchanged, so nothing moves on a phone. The body is pinned to the top, not
centred vertically. A screen may pass a wider cap: Discovery passes
`discoveryMaxWidth` (1080) for its venue grid.

**Discovery lays its venue cards out in a grid on a wide window** *(issue
#222, Phase 8)*. `VenueGrid` (`widgets/venue_grid.dart`) shows one card per
row below 680px of list, two from 680px (a 720px window less the 20px
gutters) and three from 1000px, and the loading skeletons follow the same
grid. In a single column the photo keeps the artboard's fixed 118px banner,
so a phone looks as before; in two or three columns it is 3:2, so a card is a
photo tile rather than a strip, and the cards in a row are stretched to one
height. Every venue card is drawn on a `Card`, taking the theme's
`CardThemeData` shape and `--line` edge, with its ink well laid over the
whole card so a hover or keyboard focus on the web lights up the photo too.

Visual rules: a verdict is always icon **and** colour, never colour alone
(accessibility). Unclassified dishes are listed under their own neutral heading.
The engine chip is always visible on a classified menu.

**Red dishes are no longer a collapsed group** *(issue #29, Phase 1)*. The original
rule put them in a count-labelled group at the bottom of the list. The artboard the
screen was built to (`.design/Main.dc.html`) instead makes the three verdict counters
the filter — tap "Skip" and non-keto dishes are the list, shown inline with the same
rail, tint and pill every other verdict gets. A dish hidden inside a collapsed group
cannot also be the result of a filter that selects it, so the group went and
`MenuController.redRows` went with it. The count survives where it now belongs: on
the Skip counter tile.

**One name per verdict** *(issue #243)*. The tile, the badge, the Settings
default-filter segment, the legend and the shared text all say the same noun
phrase, so the filter and the pill on a card never disagree. "Ask your waiter"
is the name of an action (the dish card's disclosure), not of a verdict.

| Verdict | English | Hebrew | ARB keys | Shared text heading |
| --- | --- | --- | --- | --- |
| Green | Order as-is | להזמין כמו שהוא | `verdictOrderAsIs`, `tileGreenLabel` | `shareGreenHeading{En,He}` |
| Yellow | With changes | עם שינויים | `verdictModifiable`, `tileYellowLabel` | `shareYellowHeading{En,He}` |
| Red | Skip | לדלג | `verdictNonKeto`, `tileRedLabel`, `redGroupTitle` | none (red is not shared) |

The keys of each row keep their separate names (a badge and a tile are different
widgets) but must hold the same words; the shared-text headings are Dart
constants because they follow the menu's language, not the UI locale.

**One button hierarchy and one field style** *(issue #248, Phase 8)*. Each screen
has one `FilledButton` for its primary action, `OutlinedButton` for a secondary
one, and `TextButton` for an inline link; `ElevatedButton` is not used anywhere.
A text field takes its look (the 14px `--line` border, the accent focus border,
the error borders) from `inputDecorationTheme` in `lib/theme/app_theme.dart` and
passes no `border` of its own. `test/architecture/import_rules_test.dart` asserts
both: `ElevatedButton` appears nowhere under `lib/`, and `OutlineInputBorder(`
only in `theme/app_theme.dart`.

**The menu header shows a keto score out of 10** *(issue #29, Phase 1)*, computed
by `utils/keto_score.dart` from the analysis's verdict counts (green counts full,
yellow at half weight, red at none) and rendered by `KetoScoreBadge`. It is a
`MenuAnalysed`-only figure — a raw menu with no analysis, or an analysis that
failed, has no verdicts to score — so `MenuController.ketoScoreOutOfTen` is
nullable and the badge **renders nothing when it is null**, never a fallback
`0.0`, which would misreport "this menu is zero keto-friendly" rather than "not
computable".

---

## 7. Domain model

Plain Dart, immutable, no code generation.

```dart
enum MenuSource { wolt, tenbis, tabit, ontopo, scan, website }
// scan: text the user supplied (D18); website: a restaurant's own site (D19)

class VenueRef {                       // how we address a venue on a platform
  final MenuSource source;
  final String platformId;             // slug, restaurantId, siteId, venue_id, URL
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
  final List<AnalysedDish> dishes;     // may be empty; see §9.4 rule 8
  final List<String> unclassified;     // names seen but not placeable — shown, never silent
  final AnalysisEngine engine;         // llm(model) | rules(reason)
  final DateTime analysedAt;
}
final class MenuAnalysisFailed extends MenuAnalysis {
  final MenuAnalysisFailureReason reason;
}
```

*(Phase 1)* Two notes on making these work as cache records. "No code generation"
means every cached model carries a hand-written `toJson()` and a
`static X? tryFrom(Map<String, Object?>)` that **returns null rather than throwing**
on any shape mismatch — that is what lets the Hive cache treat a corrupt or stale
entry as a miss without the bare `catch` §18.3 forbids. Enums are matched by string
name, never by ordinal, so reordering a variant cannot silently re-point data already
on disk. And `MenuAnalysed.dishes` **may be empty**: the sketch above said "never
empty", but §9.4 rule 8 is the more specific rule, and "the model saw the dishes and
could place none" is a result to show rather than a failure to retry.

Relationship to the README's ER diagram: the three README entities (Venues, Menus,
Dishes) are the three classes above. They are **cache records on the device**, not
tables on a server. `keto_rating_score` and `is_verified_keto_friendly` are Phase 3
fields and are not modelled until then.

---

## 8. External integrations

| Service | Endpoint | Auth | Priority | Notes |
|---|---|---|---|---|
| **Wolt** | `GET https://consumer-api.wolt.com/consumer-api/consumer-assortment/v1/venues/slug/{slug}/assortment` | none; the web-client header set (`platform: Web`, `app-language`, client version, a per-process `x-wolt-web-clientid`) | Phase 1, ported in #168 | Cleanest schema; prices in agorot; no currency (`ILS` assumed). iOS/Android call this directly; the web build calls it through the backend proxy below when configured (D11). Replaced `restaurant-api.wolt.com/v4/venues/slug/{slug}/menu/data`, which answers every anonymous caller with an empty `200` |
| **10bis** | `GET https://www.10bis.co.il/api/v1.0/Restaurants/{restaurantId}/Menu` | none | Phase 1–2 | `categoriesList → dishList`; decimal prices |
| **Tabit** | `GET https://tgp-api.tabit.cloud/menu/v2/{siteId}` (alt: `online.tabit.cloud/api/v1/ordering/menu?siteId=`) | session / anonymous token from the QR landing | Phase 2+ | Dine-in venues absent from delivery apps |
| **Ontopo** | `POST https://ontopo.com/api/loginAnonymously` → `GET https://ontopo.com/api/venue/{venueId}` | anonymous bearer | Phase 4 | Returns PDF/image links, needs the OCR path |
| **KetoClub backend — Wolt proxy** | `GET {KETOCLUB_BACKEND_URL}/v1/proxy/wolt/venues/slug/{slug}/assortment` | none | Phase 3 (D11), path moved in #168 | Allow-listed passthrough only — Wolt's status, body and `Content-Type` unchanged, 1 h server cache of non-empty `2xx` bodies; used only by the web build with a backend configured |
| **Restaurant website** (D19) | `GET` the pasted URL, then at most one linked menu page or PDF, plus `/robots.txt` | none; logged out, `KetoClubBot/1.0 (+contact URL)` | Phase 4 (#181) | Phones fetch directly; web goes through the route below. `robots.txt`, `noai` and TDM reservations honoured; size-capped |
| **KetoClub backend — website fetch** | `POST {KETOCLUB_BACKEND_URL}/v1/website/fetch` `{"url"}` | `X-KetoClub-Install-Id` | Phase 4 (D19) | Fetches one public page or PDF: `{kind, content_type, body, final_url}` or a distinct `{reason, status_code}`; public hosts only, per-host and per-install limits, nothing cached |
| **KetoClub backend — chat** | `POST {KETOCLUB_BACKEND_URL}/v1/chat` | `X-KetoClub-Install-Id` (no model key from the client) | Phase 3 (D12) | Forwards one completion per menu to Google Gemini; see §9 |

All restaurant endpoints are undocumented internal APIs discovered by network
inspection (`menu_api_research`). Each adapter therefore:

- sends a browser-like `User-Agent` and `Accept: application/json`;
- treats any non-2xx or non-JSON body as `MenuFetchFailureReason.platformChanged`,
  with the status code, so a schema change is diagnosable from the failure copy;
- is covered by a fixture test against a checked-in real response, so a schema
  drift is caught by re-recording the fixture, not by a user.

**One local dependency, not an external endpoint.** `Connectivity`
(`services/platform/connectivity.dart`, backed by `connectivity_plus` — §5) checks
the device's own network status before `RoutingMenuClassifier` calls the backend
(§6.2, §14 D10 — reinstated, and extended to the backend call by D11). It
contacts no host, needs no auth, and is not another row in the table above:
nothing about it ever leaves the device. It is listed here because it exists only
to gate the rows above that do.

---

## 9. LLM integration contract

**Since D12, the model behind this contract is Google Gemini** (`GEMINI_MODEL`,
default `gemini-3.5-flash`, a backend config value on web), reached on web
through KetoClub's own backend and, since D17, directly from iOS and Android
by `GeminiChatClient`, whose `defaultModel` is the one Dart constant naming the
same id. `MenuAnalysisPrompt` and
`MenuResponseParser` are unchanged by that move: they build and read text, not
HTTP, so the prompt (§9.1) and the schema (§9.2) are exactly what
`BackendChatClient` sends the backend, which is exactly what the backend forwards
to Gemini's `generateContent`, translated only as far as §9.3 below describes.
One prompt, one parser, one fake — same claim as before, now with a server hop
in between that neither of them knows about.

### 9.1 The prompt

One request per menu. The **system** prompt (in `menu_analysis_prompt.dart`) states:

- The three verdicts and their definitions, taken verbatim from `constants.dart` so
  the model and the UI legend say the same thing.
- The keto rules: net carbs ≤ the user's limit per dish for green (6 g unless changed
  in Settings, issue #57; `MenuResponseParser` also demotes a green whose own
  `net_carbs_estimate` exceeds it — to yellow when an instruction came with it,
  otherwise to unclassified); starchy sides, root vegetables,
  sugary sauces and glazes, breading and buns make a dish yellow when the core is
  compliant; pasta, pizza, rice bowls, noodles, breaded proteins, pastry, sandwiches
  on bread are red. *(Issue #216)* A drinks line is also in `promptKetoRulesTemplate`:
  sugary drinks (cola, sprite, juice, lemonade, beer, sweet wine, liqueur) are red;
  iced coffee, latte, cappuccino, and tonic are yellow (ask for black coffee,
  unsweetened almond milk, or soda water); zero/diet and water/plain coffee/dry
  wine/spirits are green.
- Output rules: return only dishes present in the input; use the dish `id` and the
  exact printed `name`; every `modifiable` dish must carry a `modification`; write
  `why` and `modification` in the language the menu is written in; keep each under
  300 characters; return JSON matching the schema and nothing else.
- Optional dietary constraints appended from Settings (Tier C: seed-oil free,
  dairy-free, carnivore). *(Issue #56)* Each "Your keto rules" toggle that is
  on appends one fixed English fragment from `constants.dart`, as a `- ` line
  under the section preamble in `menu_analysis_prompt.dart`, always in the
  order below (`ClassificationOptions.dietaryConstraintsFor`). With every
  toggle off no section is written, so the prompt — and the server's chat
  cache key — is byte-for-byte the default one; each combination that is on
  is its own cache key (`phase2_plan.md` open question 7). The fragments are
  also what a cached analysis's options snapshot records, so turning a toggle
  on or off re-analyses the next menu opened, exactly as a changed net-carb
  limit does (issue #57). The same toggles switch on one rule each in
  `HeuristicMenuClassifier`, so a rules result honours them too:

  | Toggle | Prompt fragment (`constants.dart`) | Rules engine (`constants.dart`, `classification_rules.dart`) | Hint (en / he) |
  |---|---|---|---|
  | Strict seed-oil free | `seedOilFreePromptFragment`: avoid canola, rapeseed, soybean, sunflower, corn, cottonseed and generic vegetable oil; a fried, deep-fried or seed-oil dish is modifiable, asking for olive oil, butter or tallow, unless already nonKeto | `seedOilTriggers{En,He}` (fried/`מטוגן`, `טיגון`, canola/`קנולה`, soybean/sunflower/vegetable oil, `שמן סויה`, …) → yellow with `seedOilFreeModification{En,He}` | "Flags canola, sunflower and soybean oil in fried dishes." / "מסמן שמן קנולה, חמניות וסויה במנות מטוגנות." |
  | Dairy-free keto | `dairyFreePromptFragment`: no dairy; a dish with cheese, cream, butter, milk or yogurt is modifiable, asking for it without the dairy, unless already nonKeto | `dairyTriggers{En,He}` (cheese/`גבינה`, cream/`שמנת`, butter/`חמאה`, yogurt, milk, named cheeses), with `dairyGuards{En,He}` sparing coconut cream, almond milk, peanut butter, vegan cheese, `קרם בלסמי` → yellow with `dairyFreeModification{En,He}` | "Treats cream, butter and cheese as a modification." / "שמנת, חמאה וגבינה יסומנו כמנה שדורשת שינוי." |
  | Carnivore only | `carnivoreOnlyPromptFragment`: animal foods only; any vegetable, salad, fruit, legume, herb or other plant makes a dish modifiable, asking for only the meat, fish or eggs, unless already nonKeto | `plantTriggers{En,He}` (salad/`סלט`, vegetables/`ירקות`, tomato, onion, mushrooms, avocado, tahini, …; not bare pepper or olive oil) → yellow with `carnivoreOnlyModification{En,He}` | "Greens only meat, fish, eggs — vegetables become yellow." / "רק בשר, דגים וביצים בירוק — ירקות הופכים לצהוב." |

  In the rules engine a red dish stays red with no script; a green dish a
  rule catches turns yellow with the rule's sentence and a dietary `why`
  (`dietaryRuleWhy{En,He}`, since the carb-component `why` would be untrue);
  a yellow dish keeps its carb sentences and gains the rule's after them.
  Sentences are chosen by the dish's language (§6.3, §12). Hebrew triggers
  use the same unicode lookaround as the carb vocabulary, never `\b`.

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
the outage caused by getting this wrong.) This is the schema Dart still builds
and sends as `response_schema` in the `/v1/chat` body; it is not Gemini's own
shape. The backend's `to_gemini_schema` is a pure function that converts it —
dropping `additionalProperties`, rewriting `["T", "null"]` to `{type: T,
nullable: true}`, recursing into `properties` and `items`, leaving `enum` and
`required` untouched — so this schema, the parser, and the Dart-side contract
tests stay exactly as they were before D12; only the backend knows Gemini's
`responseSchema` dialect exists.

*(Phase 1)* **A `description` property is deliberately absent, and should stay
absent.** `m16_structured_output_fix.md` lists `description` among its nullable
required fields, which reads like a defect here — it is not. That was a different
project whose analyser echoed the dish description back to be re-displayed.
KetoClub's parser (§9.4) never reads a description from the reply; it already has
one, from the menu it fetched. Because strict mode forces every property into
`required`, adding it would oblige the model to emit a field we discard, spending
output tokens against the exact `max_tokens` budget m16 flags as its remaining
suspect for that outage. The `verdict` enum in the shipped schema is derived from
`DishVerdict.values` rather than retyped, so the schema cannot drift from the model.

### 9.3 Request strategy

**This entire section now describes the backend's behaviour, not the Dart
client's** (D12). `BackendChatClient` does one thing: `POST {baseUrl}/v1/chat`
with `{system_prompt, user_prompt, response_schema, schema_name}` — plus
`images` when the call carries menu pages (D15) — a
`X-KetoClub-Install-Id` header, no `Authorization` header ever, and a client-side
timeout (`llmRequestTimeout`, 120 s, unchanged) that simply gives up and reports
`timeout` if the backend never answers. Everything below is what the backend
does with that request against Gemini, kept here because it is the same
contract this section always described, only moved server-side:

- The backend calls `POST {GEMINI_BASE_URL}/v1beta/models/{GEMINI_MODEL}
  :generateContent` with `x-goog-api-key` (never a `?key=` query parameter) and
  `generationConfig.responseSchema` set from the converted schema (§9.2),
  `temperature: 0` and `thinkingConfig.thinkingBudget: 0` — this is a
  classification task with a strict schema, not a reasoning one, and thinking
  tokens would otherwise compete with the answer for `maxOutputTokens`.
- **Menu pages (D15, issue #170).** `LlmChatClient.complete` takes an optional
  `images` list of `ChatImagePart {mimeType, bytes}` — `image/jpeg`,
  `image/png`, `image/webp` or `application/pdf`. Each becomes an
  `inline_data` part (`{mime_type, data}`, base64) after the user prompt's
  text part, in order: `BackendChatClient` sends them as the body's `images`
  and the backend forwards them; `GeminiChatClient` (phones, D17) puts them in
  its own request to Google. With no images, neither client sends anything
  new — the text-only body, and so the backend's cache key for it, is byte for
  byte what it was. The backend bounds them (`VISION_MAX_IMAGES`, default 6;
  `VISION_MAX_IMAGE_BYTES`, default 3 MiB decoded) and answers 422 — read by
  the app as `badResponse` — to more parts, a bigger part, malformed base64 or
  any other type, before any upstream call. A request with images never reads
  or writes the completion cache (#103) and answers `X-KetoClub-Cache:
  bypass`; the per-install limiter counts it like any other.
- On an upstream 400 whose error body is **not** `API_KEY_INVALID`, the backend
  re-sends the **same** request exactly once with `responseMimeType` only and no
  schema. 401, 403, 429 and 5xx are never retried — they are answers about the
  key, the quota and the provider, and are surfaced as such. Never a second
  retry.
- `maxOutputTokens` is `GEMINI_MAX_OUTPUT_TOKENS` (default 65536, the 2.5
  Flash family's ceiling — it was 8192, which a 118-dish Hebrew menu's
  verdicts overran, #188); a reply that hits it ends with `finishReason:
  MAX_TOKENS`, which is `badResponse` — a truncated dish array is
  unrecoverable the same way it always was.
- Backend-side upstream timeout: connect 5 s, read 110 s — inside the Dart
  client's 120 s outer bound, so the backend's own `timeout` reason reaches the
  UI before the client's timeout would fire on a healthy connection.
- On web the model id is `GEMINI_MODEL` in the backend's config (default
  `gemini-3.5-flash`), never a Dart constant — swapping it is an environment
  variable, not a code change or a release. On phones (D17) it is
  `GeminiChatClient.defaultModel`, so swapping it there is a release. §17 open question 1's "verify the
  pinned model" check is still owed, against this id (see §17).
- The reason vocabulary on the wire is exactly `notConfigured`, `offline`,
  `timeout`, `rateLimited`, `badResponse` — §10's table gives the mapping. There
  is no `unauthorised`: a rejected or absent key is the *server's* problem, so it
  reads as `notConfigured`, the same reason a build with no backend URL produces,
  and `RoutingMenuClassifier` falls back to rules for both exactly the same way
  (§6.2).

### 9.4 The parser rules

`MenuResponseParser.parse` is static, pure, and never throws. *(Phase 1: the
signature is `parse(String body, {required Menu source, required DateTime
analysedAt, required AnalysisEngine engine})`. The two extra arguments are not
optional extras — `MenuAnalysed` cannot be constructed without them, and taking the
clock and the engine stamp as arguments is what keeps this function pure and its
tests free of a real clock.)* In order:

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
6. Caps: more than `maxAnalysedDishes` (1000; a sanity bound against a
   runaway reply, not a menu size — raised from 150, which real Israeli Wolt
   venues exceed, #188) dishes → `badResponse`; `why` truncated at 300
   characters, never rejected for length alone.

   *(Phase 1)* Rules 5 and 6 read as contradicting each other on an over-length
   `modification`: rule 5 demotes the dish, rule 6 says to truncate rather than
   reject. **The rules apply in order, so rule 5 disposes of every `modification`
   case and rule 6's truncation is live only for `why`.** Truncating a waiter script
   mid-sentence would leave it reading as a complete, correct instruction while
   being neither — the same wrong-green failure constraint 5 names, just wearing
   yellow.
7. Source dishes the model did not mention at all go to `unclassified` by name, so
   the user sees the model skipped them.
8. `dishes` empty and `unclassified` empty → `MenuAnalysisFailed(noDishesFound)`;
   `dishes` empty but `unclassified` non-empty → `MenuAnalysed` with an empty list,
   because "the model saw the dishes and could place none" is a result to show, not a
   failure to retry.

All caps and verdict names live in `constants.dart`.

**The scanned variant (D15, #89).** `MenuResponseParser.parseScanned(String
body, {required VenueRef ref, required DateTime analysedAt, required
AnalysisEngine engine, int netCarbLimitGrams})` returns a `ScannedMenuResult`
— the transcribed `Menu` and its `MenuAnalysed` together, or a failure. It
shares `_decode`, the `badResponse` path and the per-element verdict rules
with `parse`; only how an element finds its dish differs. A scan has no source
menu to check against — the pages are the source, and "View pages" is the
honest substitute — so:

- **Rule 3 is replaced.** An element with no non-empty `name` (after
  trimming, or not a string, or not an object) is dropped. Of several
  elements whose names normalise alike (`TextNormaliser.normalise`), the
  first is kept and the rest dropped, verdict and all. Every kept element
  becomes a transcribed `Dish` with the id `v1`, `v2`, … assigned by the
  parser in reply order — the model's own ids are not trusted.
- **Rule 7 does not apply**: there is no source dish the model could have
  skipped. A dish demoted by rules 4–5 stays in the transcription, so the
  menu still lists it and the rule engine can judge it later.
- **Rules 1, 2, 4, 5, 6, the #57 net-carb post-rule and rule 8 apply
  verbatim**: the text path's own `llm_*.json` fixtures are run through
  `parseScanned` to prove it, alongside `llm/llm_scanned_{valid,
  duplicate_names,nameless_element,over_cap,empty}.json` for the replaced
  rules. Rule 8 reads as: no kept element → `noDishesFound`.

---

## 10. Failure handling

Every service returns a sealed result; nothing in `services/` throws across its
boundary. Failure reasons are enums, and each reason has its own copy in both
languages. Collapsing reasons is a bug.

| Reason | Where it arises | What the user sees | Way out |
|---|---|---|---|
| `MenuFetch.offline` | adapter, socket/DNS error; also a proxy 502/504 (Wolt unreachable or timed out through the backend, D11 — retry is the same way out either way) | "No connection. Showing the cached menu from {date}." (if any) | retry |
| `MenuFetch.blockedByBrowser` | adapter, request refused by the browser (CORS, §13), only when no backend proxy is configured | "A web browser cannot read {platform} menus. Open this link in the KetoClub phone app." | phone app |
| `MenuFetch.notFound` | adapter, 404 (passed through unchanged by the proxy) | "Venue not found on {platform}. Check the link." | edit input |
| `MenuFetch.platformChanged` | adapter, non-JSON / unexpected shape | "{platform} changed its menu format. Please report this." | report |
| `MenuFetch.unsupportedSource` | repository | "KetoClub cannot read menus from this site yet." | paste text (Phase 4) |
| `MenuFetch.backendUnreachable` | adapter, `ClientException` reaching the backend itself (D11) | "KetoClub's server could not be reached, so the menu could not be read." | retry, or unset the backend define |
| `MenuFetch.scanNotSaved` | repository, a `MenuSource.scan` ref whose cache entry is gone (D18) | "This pasted menu is no longer saved on this device. Paste it again to analyse it." | back, paste again |
| `MenuFetch.menuNotFound` | website adapter: no JSON-LD menu, no menu link or PDF, and fewer than three priced lines; or the text read as reversed Hebrew (D19) | "KetoClub could not find a menu it can read on {site}." | back, paste another link |
| `MenuFetch.disallowedByRobots` | website fetch: `robots.txt` disallows KetoClub, or the page opts out of AI use (`noai`, `tdm-reservation`) (D19) | "{site} asks apps like KetoClub not to read its pages, so KetoClub does not." | back |
| `MenuFetch.jsOnlyPage` | website fetch or adapter: the page renders only with JavaScript (D19) | "{site} only shows its menu with JavaScript, which KetoClub cannot read yet." | back, paste the menu text |
| `MenuFetch.websiteUnreachable` | website fetch: the site timed out, failed or answered a non-404 error, or its `robots.txt` did (D19) | "{site} did not answer. Try again later." | retry |
| `MenuFetch.websiteTooLarge` | website fetch: a page over 2 MiB or a PDF over 3 MiB (D19) | "The menu on {site} is too large for KetoClub to read." | back |
| `MenuFetch.websiteRateLimited` | backend website route: the per-host or per-install limit (D19) | "KetoClub read {site} a moment ago. Wait a minute, then try again." | retry |
| `MenuFetch.websitePdfUnread` | website adapter: a PDF menu the vision path could not read, was not allowed to, or found nothing in (D19, D15) | "The menu on {site} is a PDF, which only AI analysis can read, and it could not be read now. Check AI analysis in Settings, then try again." | retry, settings |
| `Analysis.notConfigured` | web only: no backend URL compiled in, or the backend has no Gemini key (D12) | rules result + "AI analysis is not available on this build or server. Showing rule-based results." | none from the app |
| `Analysis.consentWithheld` | router, consent toggle off (client-only, §11) | rules result + "Allow AI analysis in Settings to analyse this menu. Showing rule-based results." | settings |
| `Analysis.apiKeyMissing` | phones only: `GeminiChatClient` found no key saved, so nothing was sent (D17) | rules result + "Add your Gemini API key in Settings to analyse this menu. Showing rule-based results." | settings |
| `Analysis.apiKeyRejected` | phones only: Google answered 401, 403, or a 400 naming an invalid key (D17) | rules result + "Gemini rejected your API key. Check it in Settings. Showing rule-based results." | settings |
| `Analysis.offline` | router / client, no route: a phone's `ClientException` calling Google, or on web the backend's own 502 (Gemini unreachable) | rules result + "Offline. Showing rule-based results." | retry |
| `Analysis.timeout` | client, > 120 s, or the backend's 504 (Gemini did not answer within its own budget) | rules result + "The AI model was too slow. Showing rule-based results." | retry |
| `Analysis.rateLimited` | client, 429 — on a phone, the user's own key's Gemini quota; on web, Gemini's limit or the backend's per-install limiter | rules result + "Daily AI limit reached." | wait |
| `Analysis.backendUnreachable` | client, `ClientException` posting to `/v1/chat` (D11's "the call is the probe": nothing pre-checks the backend) | rules result + "KetoClub's server could not be reached. Showing rule-based results." | retry |
| `Analysis.badResponse` | client (4xx/5xx other), parser, or an unusable Gemini reply (non-`STOP` finish, no candidates, unparseable body) | rules result + "AI analysis failed ({detail}). Showing rule-based results." | retry / report |
| `Analysis.noDishesFound` | parser | "The AI could not identify any dishes on this menu." | try rules |

**`unauthorised` no longer exists (D12).** It described a rejected user-supplied
key; there is no user-supplied key any more, so a rejected or absent server key
now reads as `notConfigured` — the same reason a build with no backend URL
produces — and both fall back to rules like every reason but `noDishesFound`.
There is no "no rules fallback" case left in the analysis table: a rejected
server key is the operator's problem, not something the user can be shown as a
dead end.

**Where the rules-result copy appears today.** A rules result carrying a reason
currently shows that reason only on the engine chip ("Rules (server unreachable)");
the full sentences in the table above are rendered only for a hard
`MenuAnalysisFailed`. Showing them as a banner on a degraded result is issue #119.

`ChatFailed` carries a status code and a short category, never the upstream
body: an upstream error body can still echo prompt text or other detail that
should not reach a log or a widget, even with no bearer token left to leak.

---

## 11. Security and privacy

- **Whose key, and where it lives (D12, D17).** On web there is no key in the
  browser: the Gemini key lives only in the backend's `GEMINI_API_KEY`
  environment variable. On iOS and Android the user pastes their own Gemini key
  into Settings; `SecureApiKeyStore` keeps it in the Keychain or Keystore, and
  `GeminiChatClient` reads it per call and sends it only as the
  `x-goog-api-key` header to `generativelanguage.googleapis.com` — never in a
  URL, a failure value, a log, the cache or the widget tree. Settings shows only
  whether a key is saved, never the key, and the field is obscured and cleared
  after saving.
- **What leaves the device, and to whom.**
  - To the restaurant platform: the venue identifier (or, with a backend
    configured on web, to KetoClub's backend instead, which then talks to the
    platform — see D11).
  - To Google Gemini — directly from a phone with the user's key (D17), or on
    web through KetoClub's backend (D12): dish names, descriptions, option
    labels, and the optional dietary constraints from Settings. On web the
    anonymous install id also goes to the backend, for rate limiting only — it
    is never forwarded to Google, and the backend's completion cache never
    stores it alongside the cached content, `backend_plan.md` §3.5. A phone
    sends no install id anywhere for analysis. No location, no venue name, no
    user identity, ever.
  - Menu pages, when the user scans one (D15): the photographs or PDF go to
    Google Gemini as `inline_data` parts, the same two routes as dish text —
    straight from a phone with the user's key (D17), or on web through the
    backend's `/v1/chat`. The backend forwards them and drops them: a page is
    never stored server-side, never enters the completion cache or its key,
    and never reaches a log line — the chat log carries an image count, never
    bytes, a media type or base64. A photograph can hold more than the menu
    (a hand, a face, a receipt); what is in the frame is sent as taken.
  - Nowhere else. There is no telemetry.
- **Consent (D16, issue #167).** AI analysis is **on by default** on a
  fresh install: `AppSettings.estimationConsentGiven` defaults to `true`.
  A one-off `ConsentDisclosureBanner` shown on Explore states in plain
  language what leaves the device — dish text to KetoClub's server, which
  forwards it to Google's Gemini API, and nothing else about the user —
  and offers two buttons: **OK** acknowledges without changing consent;
  **Turn off** sets consent to `false`. Either button persists
  `AppSettings.disclosureSeen: true`, so the banner never appears twice
  on the same install. The Settings toggle mirrors the same choice at
  any later point. A stored `false` from before D16 (or one written by
  "Turn off") always wins over the new default: an install that already
  refused keeps its refusal. The router treats withheld consent as its
  own reason, `consentWithheld` (§10), distinct from a server-side
  `notConfigured`. `ClassificationOptions.estimationConsentGiven` keeps
  its `false` default so a caller that forgets to pass consent still
  never sends text — only the *settings-level* default flipped.
  Where the text goes depends on the build (D17): on iOS and Android it
  goes straight from the phone to Google's Gemini API with the user's own
  key, and both the banner and the Settings disclosure say so; on web it
  goes through KetoClub's server as above.
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

- **CORS blocks the restaurant adapters in a browser — the backend proxy now
  fixes it (D11).** The platform APIs answer browser requests from foreign
  origins without `Access-Control-Allow-Origin`. This is a property of those
  services, not of the app.
  - **With a backend configured**, the web build fetches live Wolt menus like
    any other target: `flutter run -d chrome
    --dart-define=KETOCLUB_BACKEND_URL=http://localhost:8000` against a running
    `cd backend && uv run uvicorn app.main:app --reload --port 8000` (see
    `backend/README.md` for the full setup and its manual end-to-end check).
    `GET /v1/proxy/wolt/venues/slug/{slug}/assortment` (#168; `/v4/venues/
    slug/{slug}/menu/data` until Wolt emptied that endpoint) forwards to Wolt's
    consumer-assortment endpoint with the web-client header set and passes its
    status, body and `Content-Type` back unchanged, so
    `WoltMenuAdapter`'s existing 404/`notFound` and other-status/
    `platformChanged` mapping needs no change; a proxy-side 502/504 (Wolt itself
    unreachable or slow) maps to `offline`, and the backend being unreachable at
    all maps to the new `backendUnreachable` (§10).
  - **Without a backend configured**, live menu fetching is still a **mobile**
    feature: the block surfaces as a client-side request failure
    indistinguishable from a dead network, so the adapters report
    `MenuFetch.blockedByBrowser` (§10) when built for web rather than as
    `offline`, and the web build takes menus by paste instead, or once Phase 4
    lands, by file.
  - The classifier itself never needed a browser-origin exception even before
    D11/D12: it always went through the app's own backend or (pre-D12)
    OpenRouter, both of which permit browser-origin calls.
  - Running Chrome with web security disabled
    (`flutter run -d chrome --web-browser-flag=--disable-web-security`) is now a
    fallback for working **without** a backend, not the recommended path; never
    ship with that flag either way.
- Geolocation requires HTTPS.
- Secure storage on web is `localStorage`-backed; say so in Settings.

### iOS

- `NSLocationWhenInUseUsageDescription` in `Info.plist`.
- App Transport Security: all endpoints are HTTPS; no exceptions needed.

### Android

- `ACCESS_FINE_LOCATION` and `INTERNET` in `AndroidManifest.xml`. `INTERNET` must
  sit in the **main** manifest: the debug and profile manifests Flutter generates
  grant it only to those build types, and a release build without it fails every
  fetch as `MenuFetch.offline`.

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

**D3 — Bring your own OpenRouter key.** *(Superseded by D12.)*
Follows `feature_prioratization` Tier A. Shipping a key in a client is not an option,
and a proxy is D1's backend. Free-tier quota is 50 requests a day, which one request
per menu plus a cache makes workable. D12 replaces the user's own OpenRouter key
with a backend-held Google Gemini key; the reasoning about not shipping a key in
the client and about one-request-per-menu quota pressure carries over unchanged,
it is simply the operator's quota now instead of the user's.

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
classification. One prompt, one parser, one fake. A vision-model path is a sibling
interface, `ScannedMenuClassifier`, not a second `MenuClassifier` and not a change
to this one: a photograph has no `Menu` to pass in until the model reads it
(D15, §6.2).

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
live fetching**, until a CORS proxy exists (§13). *(D11 delivers that proxy. With
`KETOCLUB_BACKEND_URL` configured, live fetching on web is first-class too; with
none configured — including every build before D11 — this decision's original
text still holds exactly as written.)*

**D10 — Connectivity pre-check, reinstated.** *(Reverses this decision's own
Phase 1 text below; §18.6 forbids the code and this document disagreeing, so
the old paragraph is replaced rather than left standing beside the new one.)*
`services/platform/connectivity.dart` now exists: `Connectivity` is a
one-method interface (`isOnline()`), backed in production by `DeviceConnectivity`
over the `connectivity_plus` plugin (added to the §5 dependency table and named
in §8 as the one dependency that is local rather than an external endpoint), with
a settable `FakeConnectivity` in `test/fakes/`. `RoutingMenuClassifier`'s rule 2
(§6.2, restored to its original position) asks it before ever building an
model request (OpenRouter then, the backend since D12), falling back to the heuristic — stamped `offline`, the same
reason a failed call already produced — when it answers false.

**The cost:** one more plugin (§5), one more service threaded through
`di.dart` and the router's constructor (four arguments then; three since D12
removed the `KeyStore`), and one more
abstraction whose fake can disagree with the device it stands in for.
`isOnline()` is documented on the interface itself as a hint, never a verdict,
precisely because of that last point: a `true` reading can still be followed by
a request that fails. That failure still reports `offline` through the ordinary
post-call path (§6.2 rule 4), exactly as it did before this decision existed —
the pre-check narrows *when* the LLM is tried, it never changes what a failure
means.

**What it buys:** the device being plainly offline — a lift, a restaurant with
a dead signal, the app opened before the phone reconnects — used to cost one
model request every time, which was one unit of the user's 50-a-day OpenRouter
quota (D3, D6) and is now one unit of the per-install limit (D12) spent on a call that could not have succeeded. That
case is common enough that the recurring cost of the wasted requests it
prevents was judged larger than the cost of the extra abstraction. `Clock`
stayed injected throughout both versions of this decision — cache freshness
genuinely cannot be tested without it — and this reversal changes nothing
about that.

**D11 — A backend exists, as an accelerator.** *(Amends D1, D9 and D10.)*
`backend/` is a small FastAPI service, run locally on `localhost:8000` (hosting
beyond that is still open, §17). It ships three routes: `GET /v1/health`;
`GET /v1/proxy/wolt/v4/venues/slug/{slug}/menu/data` — since #168
`GET /v1/proxy/wolt/venues/slug/{slug}/assortment`, forwarding to Wolt's
consumer-assortment endpoint on `WOLT_CONSUMER_BASE_URL`, because the `/v4` one
began answering every anonymous caller with an empty `200` — an allow-listed
passthrough that returns Wolt's status, body and `Content-Type` unchanged (404
included),
with a 1 h per-slug server cache (`X-KetoClub-Cache: hit|miss`) and its own
originated statuses — 502 on a connect failure, 504 on an upstream timeout,
never anything else; and `POST /v1/chat` (D12, below). The web build fetches
Wolt menus through the proxy when built with
`--dart-define=KETOCLUB_BACKEND_URL=…`; iOS and Android keep calling Wolt
directly — D1's "client-only" constraint is amended, not repealed: nothing the
backend does requires a server-side record of who is using it, and with no
backend URL configured the app is exactly the client-only app D1 described.
D9's "web is second-class for live fetching" is resolved for any build that
configures a backend (see D9's own note). D10 extends unchanged to the backend
call: `Connectivity.isOnline()` still only gates *whether the call is tried*;
once it is, "the call is the probe" — nothing pre-checks whether the backend
itself is up, so a backend that has gone away is discovered the same way an
unreachable OpenRouter used to be, by the call failing (now as
`backendUnreachable`, §10).

**What it costs:** a second project in the repository (`backend/`, its own
`check.sh`, its own always-run CI job — `architecture.md` §18.5's reasoning
about a path-filtered required check applies here too), a host string
(`KETOCLUB_BACKEND_URL`) threaded through `di.dart` and nowhere else (§5), and
one more failure mode per client seam (`backendUnreachable` on both the fetch
and analysis failure enums, §10). Nothing above the seam — the repository,
the controllers, the screens, the parser — knows the backend exists; `Menu` and
`MenuAnalysis` are unchanged.

**D12 — The backend serves Google Gemini; the bring-your-own-key path is
removed.** *(Supersedes D3; closes §17 open question 1 as originally posed —
"which OpenRouter model to pin" no longer applies. **Superseded on iOS and
Android by D17**, which puts a user-supplied key back on phones; D12 still
describes the web build exactly.)* The backend holds a
Gemini key server-side (`GEMINI_API_KEY`, model `GEMINI_MODEL`, default
`gemini-2.5-flash`) and the app never holds a model key at all:
`flutter_secure_storage` and `KeyStore` are gone, and so is the Settings key
section. `BackendChatClient` posts `{system_prompt, user_prompt,
response_schema, schema_name}` to `/v1/chat` with an `X-KetoClub-Install-Id`
header and no `Authorization` header; the backend converts the strict JSON
schema to Gemini's `responseSchema` subset, retries once without a schema on a
non-key-related 400, and answers only with `notConfigured`, `offline`,
`timeout`, `rateLimited` or `badResponse` (§9.3, §10) — `unauthorised` no
longer exists, because a rejected key is now the operator's problem, not the
user's: it reads as `notConfigured` and falls back to rules like every other
reason but `noDishesFound`. A per-install in-memory rate limiter (5/minute,
40/day) replaces the free-tier-quota pressure D3 and D6 described; a shared
completion cache, keyed by a hash of the request, serves identical menus to
every user of a venue without spending the limiter (`backend_plan.md` §3,
issue #103). Privacy shifts accordingly (§11): dish text now leaves the device
for KetoClub's own server, which forwards it to Google, rather than leaving for
OpenRouter directly — the Settings disclosure says so.

**What it costs:** an operator now pays for every classification instead of
each user paying with their own free-tier quota, which is the trade D12 makes
deliberately — it is what lets Settings lose its key section and the app work
for someone who has never heard of OpenRouter. `notConfigured` becomes a wider
reason than it was (no backend URL compiled in, *or* the server has no key),
which is a coarser signal than the old "you have no key" but is the honest one:
the user cannot fix a missing server key either way.

**D13 — Venue cards show only numbers already computed.** *(Answers issue
#41; rescopes #42; extends §6.5's "Search nearby" to what a result card may
show. The comparison behind it is `phase2_discovery_research.md` §7.)* The
Discovery artboard (`.design/Discovery.dc.html`) shows a keto score and green/yellow counts on
every venue card, before any menu has been opened. Two facts make that
expensive to honour literally. Each AI analysis is one `POST /v1/chat`,
limited to 5 a minute and 40 a day per install (D12), so AI numbers for a list
of twenty venues would spend half a day's allowance on menus nobody asked to
see. And Wolt's user terms forbid "systematic retrieval, such as use of any
robot, spider, web crawler, extraction software, automated process and/or
device to scrape, copy and/or monitor" the service
(`phase2_discovery_research.md` §2.3): one fetch per user action is the
exposure the shipped menu fetch already carries, but fetching N menus in the
background for every list is a different category, and bursty callers are the
ones Wolt throttles.

Three options were compared:

| Option | Cost | Accuracy | Latency | Privacy / terms |
|---|---|---|---|---|
| **A. Rules pre-analysis** — fetch every visible venue's menu in the background, run `HeuristicMenuClassifier` | N Wolt menu calls per list (proxied and 1 h-cached on web, direct on phones); no `/v1/chat` spend | Rules only, so a card promises a score the menu screen then revises | Numbers pop in over seconds (20 cards at concurrency 3) | The "systematic retrieval" pattern; every scroll fans out to Wolt |
| **B. Server-cached AI analyses** — the backend reports which slugs have a fresh shared completion (#103) and their counts | One backend call per list; phones would need the backend for this, a first | AI-grade, identical to the menu screen | One call, no popping | No Wolt traffic; needs a new route mapping slug → cached counts, which a cache keyed by request hash does not have today |
| **C. Cached-only** — numbers only for venues whose analysis is already in the device cache | Zero | Exact for what it shows; shows nothing it cannot back | None | None |

**Decision: C now, B later, A only on request.**

- **C ships now.** A venue card shows a score and counts **only** when
  `MenuRepository.cached(ref)` holds a `MenuAnalysed` for that venue;
  otherwise the card shows neither, never a placeholder `0`. Reading the
  device cache performs no network call.
- **B follows once the backend is hosted (#109)**: a backend route mapping a
  Wolt slug to the verdict counts of a fresh shared completion, so "someone
  analysed it" has a population behind it. Until the backend runs somewhere
  other than `localhost` (§17 question 6), that population is one developer.
- **A is never background behaviour.** At most it is an explicit "Estimate
  this list" action the user taps: it fetches the visible venues' menus once,
  bounded by a concurrency constant in `constants.dart`, runs only the
  heuristic classifier, and is cancelled when the list changes. It never runs
  on scroll or on load, so the retrieval is something the user asked for.

**The score formula is kept exactly as `utils/keto_score.dart` computes it**:
`10 × (green + 0.5 × yellow) / (green + yellow + red)`, rounded to one
decimal, with unclassified dishes in neither numerator nor denominator, and
null — nothing rendered — when no dish was placed. The card reuses that
function; there is no second formula. Its status is stated plainly: **it is a
UI ranking heuristic with no nutrition basis, never a health claim.** No
source says a dish needing one swap is worth half a safe one; #41 was meant
to give the 0.5 weight a basis and found none, so the weight stays as a
ranking convenience rather than being dressed up as evidence. Numbers that
came from the rules engine always carry the "estimate" marker, through the
existing engine label (`RulesEngine` → the rules variant of `EngineChip`'s
copy) rather than a new one — under C that happens whenever the cached
analysis was rules-only, and under A it is always the case.

**Consequences.** #40's *Keto 8+* chip filters on the card score, so it is
disabled (with a tooltip saying why) until at least one visible card has
numbers, rather than offered as a filter that always returns an empty list;
it stays on screen so the chip row never changes shape (issue #231). The
chips are multi-select and combine; "Nearby" is the default order, not a
filter, so it has no chip. #42 is rescoped from "fetch menus
for the visible venues in the background" to "read cached analyses for the
visible venues, plus the explicit estimate action". The Discovery list's
performance budget gains a hard rule: **no menu fetch on scroll or on load** —
scrolling reads the device cache and nothing else.

**What it costs:** most cards on a first visit show no score, which is further
from the artboard than any other option; the artboard's every-card score is
honoured only as far as the device (and, after B, the backend) has actually
analysed. That gap is the point: a number on a card is a claim about food
someone is about to order, and D13 only makes claims it can back.

**D14 — The heuristic engine judges a whole dish, not one flat string.**
*(Amends §6.1's "option labels are part of the text the classifier sees" and
D-V3's bread-carrier rule; answers issues #190, #191, #192.)* Two real-menu
misreads showed `ClassificationRules.match(String)` was too blunt: an
"ארוחת נאגטס" (nuggets meal) option group on a burger reddened the whole
dish from its option text alone, and a plain "פיתה רגילה" or "Portion of
fries" with no other words came out yellow with "serve it without the pita"
— an instruction that cannot be followed — because nothing told the engine
a dish could *be* the carb rather than merely contain one. Fixing both from one flat string
was not possible — the fix needs to know which part of the dish a word came
from — so `ClassificationRules.matchDish(Dish)` replaces `match` as the
heuristic's entry point and runs three steps in order: (1) a dish **name**
made only of unguarded carb-modifier triggers plus portion/qualifier words
(`carbOnlyQualifiers{En,He}`) is red, labelled with the trigger, when the
trigger is a starch or bread in `carbOnlyEligibleTriggers` (never a sauce or
vegetable, never the bread-carried burger, sandwich, wrap and toast families
— D-V3's yellow) and nothing in the description or options names a filling
(`describesFilling`); (2) a
non-keto base is matched on `TextNormaliser.dishCoreText` — name and
description, never options; (3) a carb modifier is matched on
`TextNormaliser.dishRulesText` — the core text plus option group names and
values, with a removal value (first word `no`/`without`/`skip`/`ללא`/`בלי`)
dropped, and a red base found only among the options ("Choice of side:
pasta / salad") is a yellow asking for the other option, never a red.
`match(String)` is kept for callers with only a string. The same
pass also filled two vocabulary gaps the same real menus exposed: the pastry
counter (danish, pastry, muffin, scone, מאפה, שמרים, דניש, …) as a red base,
and the burger word families (`burger`, `hamburger`, `בורגר`, …) as bun
carriers, so a bare "Cheeseburger" gets the bun sentence instead of reading
green for want of the literal word "bun".

**What it costs:** three ordered rules instead of one flat regex pass, and a
`Dish` parameter where a `String` used to do — every heuristic call site now
needs the whole dish object, not just its joined text. **What it does not
touch:** `TextNormaliser.dishSearchText` and `menuFingerprint` (§6.4) are
unchanged and still hash every option value regardless of removal wording,
so no cached analysis is invalidated by this decision.

**D15 — Menu scanning goes through Gemini's own vision, not on-device
OCR.** *(Decided 2026-09-24, recorded 2026-09-29; answers issue #81, closed
as not planned, and #170. Amends D5 for the Phase 4 scan path and §16's
"Photographed or PDF menus" row, which both assumed OCR text.)* The default
model, `gemini-3.5-flash`, reads photographs and PDFs natively, so a separate
OCR stage (the M16 research's on-device text recognition, then text into the
existing prompt) would add a second engine whose errors the model can no
longer see past: a misread price column or a dish name split across two
lines is lost before classification starts. Instead a menu page travels as an
image part of the same one-request-per-menu chat call (D6): `LlmChatClient.
complete` gained `images` (`ChatImagePart {mimeType, bytes}`), and both
clients carry them as `inline_data` parts after the user prompt (§9.3).

- **Web** posts them to `/v1/chat` as `images: [{mime_type, data}]`, bounded
  by `VISION_MAX_IMAGES` (6) and `VISION_MAX_IMAGE_BYTES` (3 MiB decoded); the
  install id, the `Authorization` rejection, the limiter and the error
  vocabulary are the route's own, not a second copy.
- **Phones** (D17) send them straight to Google in `GeminiChatClient`'s own
  request, with the user's key.
- **Never kept.** Pages are forwarded and dropped: never stored server-side,
  never cached — a request with images bypasses the completion cache (#103)
  both ways and images never enter its key — and never logged beyond a count
  (§11).
- **A text-only call is unchanged.** Both clients send nothing new when
  `images` is empty, so no server cache key moves and no existing prompt is
  touched.

**What it costs:** the scan path depends on a network and a model, with no
offline OCR fallback to degrade to — the rules engine needs text a photo does
not have. A page costs more tokens than its text would, and no two scans ever
share a cached answer. The default model has not yet been confirmed to accept
image and `application/pdf` parts with the real prompt (#179), and the Scan
screen that produces pages (#89) and the person-run smoke check
(`backend/tools/vision_smoke.py`, #88) come after this transport change.

**The classifier on top (#89, 2026-09-29).** The pages are read and
classified by `VisionMenuClassifier` behind `RoutingScannedMenuClassifier`
(§6.2), a sibling of `MenuClassifier` rather than one of its implementations,
in **one** request: the text path's system prompt behind a vision preamble,
the pages as image parts, and the unchanged response schema. The reply is
parsed by `MenuResponseParser.parseScanned` (§9.4), which replaces "never
invent a dish" — there is no source menu to check against — with "drop a
nameless element; keep the first of duplicate names", and applies every other
rule verbatim. The honest substitute for provenance is the page itself: the
menu header says "Read by AI from your pages" and offers "View pages" from an
in-memory `ScannedPagesRegistry`, so the user can check the transcription
against the photograph. Consent withheld means no page is sent; offline means
no request is spent; and there is no rules fallback. No real image request
has yet been sent with this prompt (#88).

**D16 — AI analysis is on by default.** *(2026-09-28; answers issue #167;
amends §11.)* D2 makes the language model the primary classifier, but
`AppSettings.estimationConsentGiven` defaulted to `false`, so a fresh
install always saw rules-engine verdicts and the "why not AI" banner until
the user hunted for the Settings switch. That defeated the point of D2 for
every new user and turned the model into an opt-in feature the app is not
scoped around. The flip: on a fresh install `estimationConsentGiven`
defaults to `true`, and a one-off `ConsentDisclosureBanner` on Explore
tells the user in plain language what leaves the device (dish text to
KetoClub's backend, on to Google Gemini) with two buttons — **OK**
acknowledges, **Turn off** sets consent to `false`. Either dismisses the
banner permanently through a new `AppSettings.disclosureSeen: true`. A
stored `false` from before D16 (or one written by "Turn off") always wins
over the new default; the Settings toggle mirrors the same choice at any
later point. `ClassificationOptions.estimationConsentGiven` keeps its
`false` default: a caller that forgets to pass consent still never sends
text — only the *settings-level* default flipped, not the classifier's
own contract.

**D17 — iOS and Android call Wolt and Gemini themselves; the backend is for
the web build only.** *(Issue #194. Supersedes D12 on iOS and Android; D12
still describes the web build. Leaves D11 unchanged: the menu proxy was
already web-only.)* D11 promised that the backend is "an accelerator, never a
dependency", but D12 made every platform's AI analysis depend on it: a phone
with no backend compiled in was rules-only by construction, and there is still
no hosted backend (§17.6, issue #109). The CORS problem that justifies the
proxy does not exist in native HTTP either. So on iOS and Android every request
to Wolt — menu and discovery — and to Gemini now leaves from the app itself,
and `KETOCLUB_BACKEND_URL` has no effect there even when it is set.

- **Wolt and 10bis.** Already true before this decision: `menuProxyBase`
  answers null whenever `runsInBrowser` is false, and `di.dart` passes that to
  both menu adapters and to `WoltVenueSearchService`. D17 only records it as a
  rule, pinned by `di_test.dart` and the phone flow test.
- **Gemini.** `di.dart`'s `chatClientFor` builds a `GeminiChatClient` whenever
  it is given an `ApiKeyStore`, and `apiKeyStoreFor` gives one only off the
  web. The client is a Dart port of the backend's `services/gemini.py`: the
  same `generateContent` body, the same strict-schema-to-`responseSchema`
  conversion (`toGeminiSchema`), the same model default (`gemini-3.5-flash`, the
  `GEMINI_MODEL` that `backend/.env.example` sets since #165),
  output budget and zero thinking budget, the same single retry without the
  schema on a non-key 400, and the same `finishReason == STOP` and
  thought-part rules for reading the reply. Keying the choice on the store,
  not on `kIsWeb` a second time, is what keeps "the key field Settings shows"
  and "the client that reads the key" from ever disagreeing.
- **Whose key.** For now, the user's own: they create one in Google AI Studio
  and paste it into a Settings section shown only on phones. It is stored with
  `flutter_secure_storage` (Keychain on iOS, Keystore-backed on Android),
  reinstated for this, and read per call. A bundled key (extractable from any
  release binary) and a backend-minted short-lived token (which would bring the
  backend dependency straight back for the first call) were the alternatives
  weighed in the issue; a user-supplied key was chosen as the one that needs no
  server and puts no shared secret in the binary.
- **Two new failure reasons.** `apiKeyMissing` (no key saved; the client sends
  nothing) and `apiKeyRejected` (401, 403, or a 400 naming `API_KEY_INVALID`)
  exist only on the phone path. They are distinct from `notConfigured`, which
  still means "this web build or its server has no model", because the user can
  fix these two themselves: both fall back to rules, both banners offer "Open
  Settings", neither offers Retry. A `ClientException` calling Google is
  `offline`, not `backendUnreachable`, because there is no KetoClub server in
  between. The backend client never trusts either new reason from the wire.
- **Privacy.** Dish text now goes from a phone straight to Google, with no
  install id; Settings' disclosure and D16's first-launch banner say so on
  phones and keep the via-server wording on web.

**What it costs:** a phone user must now get a Gemini key before AI analysis
works, where D12's plan was that nobody would ever have to — though D12's plan
only worked with a hosted backend that does not exist. Each phone user spends
their own key's quota rather than the backend's per-install limiter (5/minute,
40/day), and phones no longer benefit from the backend's shared completion
cache (#103), so the same menu opened on two phones is two model calls. The
backend's `/v1/chat` remains the web build's only path to a model, unchanged.

**D18 — Paste-a-menu: a menu can come from text the user supplies, stored
under `MenuSource.scan`.** *(Issue #83; the first Phase 4 item and the only one
with no blocker: no OCR, no new dependency, no backend change.)* Text is the one
classifier input (D5), so a pasted menu needs no engine of its own, only a
way to become dishes. Three documents already named paste-a-menu as the web
fallback when a platform blocks the browser (§6, §13); this builds it.

- **The source.** `MenuSource` gains `scan`, the wire value `scan`. A new pure
  `TextMenuSource.parse(text, {required now})` in `services/menu/text/` turns
  lines into a `Menu`: lines are trimmed and blank ones dropped; a trailing price
  (`₪`, `NIS`, `ILS`, or a bare trailing number, one regex in `constants.dart`) is
  stripped before anything else reads the line, so no price reaches a dish, a
  prompt or a cache entry; a line ending in `:` is a section header; a line that
  starts with `-`, `(` or a lowercase letter straight after a dish is that dish's
  description continued; every other line is a dish with `price: 0`, no options and
  an id `p1..pN` in line order. At most `maxAnalysedDishes` dishes are kept, and
  the result is null when none survived. The one refinement of the issue's "a short
  line before a blank line is a header" is that the line must also stand alone (a
  blank line, or the start of the text, above it): the last dish of every group is
  also followed by a blank line, and without this it would read as a header. A paste
  where every line is separated by a blank one switches the rule off, since every
  dish would otherwise be a header.
- **The reference.** A paste's `VenueRef` is `scan/<hex of
  TextNormaliser.menuFingerprint(menu)>`, eight digits, so the same dishes pasted
  again are the same cache entry (the price does not enter the fingerprint) and
  the same prompt, and the backend's `chat_cache` (D12) answers the second one.
  The fingerprint is 32 bits, so two different pastes could in principle collide
  and share an entry; at a person's own paste volume that is accepted, and a
  collision would show as the other paste's dishes, never as an invented dish.
  `venueName` is null, and the screens read "Pasted menu" (`sourceScanned`)
  instead of the hash.
- **The repository.** `MenuRepository` gains `store(Menu)`, which writes the menu
  under its own ref and keeps an analysis already cached for the same dish text.
  `CachedMenuRepository.load` answers a `scan` ref from the cache alone, served
  `fromCache: true` and never stale: there is no platform to ask again, so
  freshness is meaningless, and `refresh` re-serves the entry. A miss is a new
  `MenuFetchFailureReason.scanNotSaved` with its own copy in both languages and
  a back-to-search action rather than Retry, because retrying finds nothing
  either. Nothing evicts a cache entry by age, so a scan stays until the user
  removes it from Saved or clears the cache; only then is it `scanNotSaved`.
- **No price for a scan.** `DishCard` gains `showPrice` (default true), and the
  menu screen passes `false` for a scan. The share text already carries no price,
  and the classifier prompt omits it (§9).
- **The entry point.** The Scan tab's body is a multi-line paste field and an
  Analyse button (`ScanController`), which stores the parsed menu and pushes
  `/venue/scan/{id}`; from there the menu is loaded, classified by the router and
  cached like any other venue. Consent (D16) is unchanged, and Settings' disclosure
  now says "open or paste". Photo actions around the field arrive with #82.
- **What it does not do.** No OCR, no language detection beyond what the
  classifier already does, and no editing of a stored paste: to change one, paste
  it again. Pasted text is treated exactly as untrusted as a fetched menu.

**D19 — Website menu source: a restaurant's own site, read politely.**
*(Issue #181, 2026-09-29; follows `docs/menu_sources_research.md` §1, §3.2,
§3.6 and §6, which found no licensed menu API for Israeli restaurants and the
restaurant's own site or PDF the only source that covers them all.)* Wolt and
10bis cover delivery; the dine-in restaurants a keto diner actually sits in
often appear on neither.

- **The source.** `MenuSource` gains `website`, wire value `website`.
  `VenueRefResolver.resolve` returns it for any `http`/`https` URL on a dotted
  host it does not otherwise recognise and with no user info; Wolt and 10bis
  keep priority (a Wolt URL that is not a venue page is still null), and the
  bare-word guard of #169 is unchanged. `platformId` is the URL normalised by
  `normaliseWebsiteUrl` (lower-case scheme and host, no fragment, no default
  port, no trailing `/`), and `platformUrl` returns it. The route path
  percent-encodes it (`utils/venue_route.dart`) so a URL stays one segment.
- **Finding the menu** (`services/menu/website/`, pure, every platform).
  `WebsiteMenuLocator.locate` tries, in order: (1) JSON-LD `Menu` /
  `MenuSection` / `MenuItem` with named items, mapped straight to categories by
  `JsonLdMenuMapper`; (2) a link to the menu — JSON-LD `hasMenu` first, then a
  page link whose address or text says `menu` or `תפריט`, or that ends in
  `.pdf` (a menu-named PDF, then a menu-named page, then any PDF; a page link
  must stay on the same site, a PDF may be on a file host); (3) the page's own
  text. A link is followed **once**, never a second hop, and a linked page that
  yields nothing falls back to the first page's own text.
- **Reading it.** Page text becomes `TextMenuSource` input (D18) through
  `WebsiteMenuLocator.menuText`, which reads only the stretch between the first
  and last priced line (so navigation and footers never become dishes), needs at
  least three priced lines to call a page a menu, and handles both "price on its
  own line" and "price at the end of the line" layouts. A **PDF goes to the
  vision path** (`ScannedMenuClassifier`, D15) as one `application/pdf` page —
  **never through a text layer**, which reverses most Hebrew PDFs. The
  transcription and its analysis come back from the same one request (D6); the
  analysis rides on the new `MenuFetched.analysis`, the repository caches it
  beside the menu, and the menu screen reuses it because both build their
  options with `ClassificationOptions.fromSettings`. Any text that is read (page
  text or JSON-LD) is rejected as `menuNotFound` when a Hebrew word in it starts
  with a final-form letter (ך ם ן ף ץ) — `utils/hebrew_order.dart` — since that
  is proof of reversed text.
- **Fetching it (crawl hygiene).** Web goes through the backend's new
  `POST /v1/website/fetch` (`{"url"}` in the body, so no URL reaches a request
  log; answers `{kind: html|pdf, content_type, body, final_url}`, a PDF's body in
  base64). Phones (D17) fetch the site themselves through
  `DirectWebsiteFetcher` with the same rules; a web build with no backend meets
  the site's cross-origin block and says so (`blockedByBrowser`). The rules,
  both ways: logged out, no cookies; a named User-Agent with a contact URL
  (`KetoClubBot/1.0 (+https://github.com/NoaMcDa/KetoClub; menu reader)`, where
  the platform lets a request set one); `robots.txt` honoured for `ketoclubbot`,
  else `*` (RFC 9309 longest match; a 4xx means no rules, a 5xx or no answer
  means the site is not read); `X-Robots-Tag: noai`, `tdm-reservation: 1` and
  their `<meta>` forms honoured; at most five redirects, each re-checked; 2 MiB
  for a page and `maxScanPageBytes` (3 MiB) for a PDF. The backend adds a
  public-address check on every hop (no private, loopback or link-local
  address, so the route cannot reach its own network), only default ports, a
  per-host limit (6 a minute across all installs), a per-install limit (10 a
  minute) and an in-memory `robots.txt` cache (1 h); it keeps no page and logs
  the host and outcome only. A page that renders only with JavaScript fails
  with its own reason: no headless browser is in scope. **No Wix `_api` calls**
  (#180 decides that route).
- **Showing it.** Every dish has `price: 0` and `DishCard.showPrice` is false
  for a website (M16: a scraped price is unverified); the source line, header
  and Saved entry show the site's host. The menu is cached 24 hours like any
  other and nothing is republished (research §4.4).
- **Seven new fetch reasons** (§10), each with its own copy in both languages:
  `menuNotFound`, `disallowedByRobots` (robots.txt or an AI opt-out: the user's
  way out is the same), `jsOnlyPage`, `websiteUnreachable`, `websiteTooLarge`,
  `websiteRateLimited` and `websitePdfUnread` (the vision read failed, was not
  allowed, or found nothing — there is no rules fallback for a PDF).

**What it costs:** a second, looser proxy on the backend — the upstream host
comes from the request, which the Wolt and 10bis proxies never allow — fenced
by the public-address check and the limits above; two fetchers applying the
same hygiene rules, in Dart and in Python, that must be kept in step; and a
text heuristic that will misread some page layouts (the model then sees a few
wrong "dishes", or none). **What it does not do:** no headless browser, no
sitemap crawl, no second hop, no Wix structured route, and no real site has
been fetched yet — the fixtures under `test/fixtures/website/` are synthetic.

---

## 15. Testing strategy

The pyramid, the coverage gate, and the CI wiring are defined in §18.4 and §18.5.
This section lists what each part of the system must be tested for.

- **Adapters:** one checked-in real JSON fixture per platform in `test/fixtures/`,
  and a mapper test that pins category count, dish count, price conversion, and
  option flattening. The mapper is pure, so it is tested with no HTTP at all; the
  adapter is tested with a fake `http.Client` for status handling only. Re-record
  the fixture when the platform changes; the test failing is the alarm.
- **Website source (D19):** the locator, JSON-LD mapper and page-text reader
  against synthetic HTML fixtures (`test/fixtures/website/`: JSON-LD, a
  `/menu` link, a Hebrew `תפריט` link, a PDF link, none, and both price
  layouts) with no HTTP; `robots.txt` matching; both fetchers over a fake
  `http.Client`; the adapter over a scripted fetcher, including the PDF's
  one vision call and the reversed-Hebrew guard. The backend route's hygiene
  rules are Python tests (`backend/tests/test_website_*.py`).
- **Heuristic classifier:** table-driven tests over the README examples plus Hebrew
  equivalents. Every entry in `CARB_MODIFIERS` and `NON_KETO_BASES` has at least one
  positive case and one word-boundary negative case (`rice` must not match `price`).
- **Parser:** the eight rules of §9.4, each with a positive and a negative fixture,
  including: fenced JSON, invented dish, yellow without instruction, green with
  instruction, over-cap list, model skipped a dish, all-unclassified.
- **`BackendChatClient`:** a fake `http.Client` asserting the request body
  (`system_prompt`, `user_prompt`, `response_schema`, `schema_name`), the
  `X-KetoClub-Install-Id` header, that no `Authorization` header is ever sent,
  and the reason mapping from each non-2xx status and from `ClientException`
  (`backendUnreachable`) and `TimeoutException` (`timeout`). The
  `json_schema`/`responseSchema` fallback and the Gemini retry rule are backend
  (Python) tests, not Dart ones — see `backend/tests/test_chat.py`,
  `test_gemini_schema.py`.
- **`GeminiChatClient` (D17):** a fake `http.Client` asserting the endpoint,
  the key only in `x-goog-api-key` (trimmed, never in the URL or body, no
  install id), the `generateContent` body and generation config, the schema
  conversion (`toGeminiSchema`, pinned rule by rule with no HTTP), the single
  retry without the schema, `apiKeyMissing` with no request, and every status
  and transport mapping; it also runs the shared `LlmChatClient` contract.
- **Router:** consent withheld → rules (`consentWithheld`); offline → rules
  (`offline`); backend `timeout` → rules with reason; backend `notConfigured`
  (no backend URL, or the server has no key) → rules with reason; a phone's
  `apiKeyMissing` / `apiKeyRejected` → rules with reason; no case returns a
  bare failure except `noDishesFound`.
- **Contract tests:** every `MenuClassifier` and every `PlatformMenuAdapter`
  implementation runs the same shared contract suite (never throws, returns a sealed
  result, honours the interface's documented invariants). See §18.1 (Liskov).
- **Widgets:** the counter tiles filter and carry each verdict's count; an
  unclassified section renders;
  a yellow card always has script text; the engine chip reflects the result.
- **Flows** (`integration_test/flows/`): paste a Wolt URL and see a classified
  menu; go offline and see rule-based results with the reason; toggle consent on
  in Settings (there is no key to enter) and see the engine chip switch to AI;
  toggle consent off and see rules with the `consentWithheld` message; with a
  backend URL configured and the LLM classifier faked as `backendUnreachable`,
  see that copy; on a phone build (D17), with a backend URL compiled in, see
  the menu fetched from Wolt and the verdicts from Gemini with nothing sent to
  the backend, and with no key saved see the `apiKeyMissing` copy, follow it to
  Settings and save a key (`direct_gemini_analysis_flow_test.dart`).
- **Screens** (`test/screens/`): each screen with its controller and faked
  dependencies, asserting what the flow tests assert but in milliseconds.
- **Rule:** no test opens a socket or uses a real clock.

---

## 16. Build order and extension points

Build in this order; each step is demonstrable on its own. **Steps 0 to 5 are
done** *(Phase 1)*, the backend steps below them (D11, D12) are done, and
**steps 8 to 10 (Phase 2) are done too** — see each step below for the PRs
and what is still owed (fixture recordings, a phone run).

0. **Day zero (already committed)** — `.github/workflows/ci.yml`,
   `analysis_options.yaml`, `test/architecture/import_rules_test.dart`,
   `test_driver/integration_test.dart`, `tool/check.sh`, `tool/coverage_gate.sh`,
   `tool/gen_coverage_helper.sh`.
   CI is red until step 1 makes it green; that is intended.
1. **Skeleton** — `flutter create` (done on `main`), `di.dart` with an empty
   dependency set, `app.dart`, a placeholder first screen, one widget test and
   one flow test so every CI job runs and passes (done in the pull request that
   added §18). Still open in this step: ARB files, the `models/` package and the
   sealed result types. **Branch protection is switched on when this step
   merges.**
2. ✅ **Heuristic classifier** — `constants.dart`, `classification_rules.dart`,
   `HeuristicMenuClassifier`, and its tests. Validates the model shapes before any
   network code exists.
3. ✅ **Wolt adapter + repository + cache** — fixture-tested normalisation, Hive cache,
   paste-a-URL resolution.
4. ✅ **Menu screen** — `MenuController`, `DishCard`, `StatusBadge`, filters (the
   verdict counter tiles, §6.6), unclassified section, engine chip, Waiter Card. At
   this point the app is usable offline with the rules engine.
5. ✅ **LLM client + LLM classifier + router + Settings** — consent, prompt, schema,
   parser, fallback logic, failure copy. Originally the OpenRouter client with a
   user-supplied key; superseded in place by steps 6 and 7 below (D12), not left
   standing beside them.
6. ✅ **Backend foundations (D11)** — `backend/` scaffolded with its own gate and
   CI job (#94); `GET /v1/proxy/wolt/…` (#95) with the allow-listed passthrough
   and 1 h cache; `WoltMenuAdapter` gains `proxyBase` and the web build routes
   through it when `KETOCLUB_BACKEND_URL` is configured (#96). After this step,
   `flutter run -d chrome --dart-define=KETOCLUB_BACKEND_URL=http://localhost:8000`
   shows a live Wolt menu in a browser for the first time.
7. ✅ **Hosted classification (D12)** — `POST /v1/chat` forwards to Google Gemini
   with the server's key, the strict-schema retry, the install-id header and the
   per-install rate limit (#100); the anonymous `InstallIdStore` (#101);
   `BackendChatClient` replaces `OpenRouterClient` everywhere, `KeyStore` and
   `flutter_secure_storage` are deleted, the router drops its key dependency, and
   Settings loses its key section (#102); a server-side completion cache shared
   across users (#103). This is the step this document (#97) reconciles against.
8. ✅ **10bis adapter** (#126 proxy route, #127 `TenBisMenuMapper`, #134
   `TenBisAdapter` + `di.dart` registration). `VenueRefResolver`'s existing
   10bis recognition now reaches a real adapter instead of
   `unsupportedSource`. Built against a synthetic fixture
   (`tenbis_synthetic_menu.json`, issue #44) — the live capture this step
   once said was required turned out not to block the code, only the
   pre-release confidence in it.
9. ✅ **Location and nearby search** (#37/#151 `LocationService`, #123/#149
   the Wolt venue-search proxy, #39/#150 `WoltVenueSearchService`, #40/#154
   the Discovery screen, #147 D13). §17.2's "no Wolt venue-search endpoint is
   known" was answered by `phase2_discovery_research.md`'s third-party
   research rather than a live capture; both discovery fixtures
   (`wolt_pages_restaurants.json`, `wolt_pages_search.json`) are synthetic
   pending that recording (issue #38).
10. ✅ **Platform setup** (#130) — permissions, icons, splash, bundle ids for
   iOS, Android and web. Still owed: a test on a physical iOS and Android
   device with a real Wolt venue (`docs/RELEASE.md`'s device matrix).

**Phase 4 steps (menu scanning).** Steps 11 to 17 are done.
Each has its own issue in the GitHub milestone "Phase 4: Menu Scanning"; D15,
D18 and D19 (§14) are the record of the decisions.

11. ✅ **Image parts** (#170, D15) — `LlmChatClient.complete` takes `images`;
    `/v1/chat` accepts them with the `VISION_MAX_*` bounds and both chat clients
    forward them as `inline_data`. A text-only call is byte-for-byte unchanged.
12. ✅ **Paste-a-menu** (#83, D18) — `MenuSource.scan`, the pure `TextMenuSource`,
    `MenuRepository.store`, and the Scan tab's paste field.
13. ✅ **Scan seams and the vision classifier** (#89) — `ScannedMenuClassifier`,
    `VisionMenuClassifier`, `RoutingScannedMenuClassifier`,
    `MenuResponseParser.parseScanned` and the in-memory `ScannedPagesRegistry`.
14. ✅ **The Scan tab** (#82) — photograph pages, pick images or a PDF through
    `DevicePagePicker` (`image_picker`, `file_picker`), the iOS camera and
    photo-library permission strings, and the menu header's "View pages".
15. ✅ **Flow tests for the scan paths** (#84) — paste, photograph and PDF driven
    end to end with the chat client faked.
16. ✅ **A website menu source** (#181, D19) — `MenuSource.website`, the pure
    locator and page reader, `WebsiteMenuAdapter` over a direct or backend
    fetcher, `POST /v1/website/fetch`, and a PDF read by the vision path.
    Still owed: a real restaurant site fetched, on the web build and a phone.
17. ✅ **QR codes** (#182) — a menu reached from a scanned QR code. The Scan
    tab's "Scan QR code" action reads one code through `QrScanner`
    (`MobileQrScanner` over `mobile_scanner`, off the web; `NoQrScanner` on
    web, where the action is hidden). The pure `QrPayloadRouter` classifies the
    payload: Wolt, 10bis, website and PDF links become a `VenueRef` and open
    the menu screen exactly as a pasted link does; a Tabit code answers "not
    supported yet" (#176 is the adapter); Instagram, Linktree and any non-URL
    payload suggest photographing the menu. Still owed: a physical phone with
    a real QR code (the camera is evidenced by a fake only).

The person-run vision smoke test (#88, `backend/tools/vision_smoke.py`) is a
verification step for 11 to 14, not a build step: no real image request has been
sent yet (§17.1).

Extension points already designed in:

| Future feature | Where it plugs in | What must not change |
|---|---|---|
| Tabit, Ontopo | a new `PlatformMenuAdapter` | `Menu` model, classifier |
| A restaurant's own website | **Shipped (D19, issue #181).** `WebsiteMenuAdapter` over a `WebsiteFetcher` (the backend's `/v1/website/fetch` on web, direct on phones); page text through `TextMenuSource`, a PDF through `ScannedMenuClassifier` | `Menu` model, the text classifiers, the vision prompt |
| Pasted text | **Shipped (D18, issue #83).** `TextMenuSource.parse` yields a `Menu` from lines of text under `MenuSource.scan`; `MenuRepository.store` puts it in the cache | the prompt and parser (unchanged, as predicted) |
| Photographed or PDF menus (Phase 4) | **Built (D15, #89, #82); the real model has not yet been called with images (#88).** The pages are read and classified by Gemini's own vision in one request — no OCR stage — through `ScannedMenuClassifier` (`VisionMenuClassifier` behind `RoutingScannedMenuClassifier`); the transcription is stored under `MenuSource.scan` like a paste (D18) | the text prompt (the vision preamble sits in front of it), the response schema, `MenuClassifier` |
| Vision-model classification | **Built (#89)** as the sibling `ScannedMenuClassifier`, not a second `MenuClassifier`; its own router applies consent and connectivity, with no rules fallback | the UI's menu screen, which shows a scan like any other menu |
| Custom dietary rules (Tier C) | **Shipped (#56, #143).** `ClassificationOptions` → appended to the system prompt and to the rules table | schema |
| Community ratings, venue directory (Phase 3) | a backend with its own client under `services/community/`; `Venue` gains the README's rating fields | everything above stays client-only |
| CORS proxy for web | **Shipped (D11).** `backend/`'s `/v1/proxy/wolt/…` route; `WoltMenuAdapter` took a configurable `proxyBase`, exactly as this row predicted | adapter logic (unchanged, as predicted) |
| Shared analysis cache (Tier D) | **Shipped (D12, issue #103).** The backend's own `chat_cache`, keyed by a hash of the request — not a remote tier of the device's `MenuCache`, which stays exactly as before; each device still caches its own `Menu` and `MenuAnalysis` locally | parser, models (unchanged — the cache sits below `LlmChatClient`, invisible to both) |

---

## 17. Open questions

Things this document could not settle from the available material. Each has a
default the implementation follows until answered.

1. **Which OpenRouter model to pin.** *(Closed by D12 and then verified on
   2026-09-28: the question no longer applies as posed — there is no
   OpenRouter model to pin, no free-tier id to rotate, and no per-user quota.
   D12 pins `GEMINI_MODEL` (default now `gemini-3.5-flash`) as a backend
   environment variable instead of a Dart constant, so changing it is a
   redeploy, not a release. The smoke test #165 ran on 2026-09-28 against
   the real prompt: `gemini-2.5-flash` (the D12 default) is 404 for new
   users — Google's API recommends `gemini-3.8-flash` as the successor, but
   both `-3.8-flash` and `gemini-flash-latest` currently answer 503
   UNAVAILABLE for structured-output requests, and `gemini-flash-lite-latest`
   answers 400 INVALID_ARGUMENT for `generationConfig.thinkingConfig`. The
   default was moved to `gemini-3.5-flash` on the same day. Round-trip
   latencies from a laptop through the local backend: 33.5 s cold for a
   20-dish English menu, 8.8 s for a 10-dish Hebrew menu, 4 ms for a cache
   hit; the responses (redacted) are under `test/fixtures/llm/smoke_*.json`
   and Hebrew `why`/`modification` came back in Hebrew. Phone numbers are
   still #65, and the successor picking under #179 has not chosen a
   permanent home yet.)*
2. **Exact Wolt venue-search endpoint** for nearby search. `menu_api_research` covers
   menus only. Default: ship paste-a-URL first (Tier A) and discover the search
   endpoint with the reverse-engineering protocol in `README.md` when building
   step 9. *(Answered as far as third-party evidence goes — see
   `phase2_discovery_research.md` §2: `GET /v1/pages/restaurants?lat=&lon=` for
   nearby venues and `POST /v1/pages/search` for a typed name, anonymous, with
   CORS locked to `https://wolt.com`, so the web build proxies them through the
   backend as D11 does for menus. Nothing there was verified by a live call from
   this environment; the browser recording (#38) that confirms the shape and
   supplies a recorded fixture is still outstanding. What the resulting cards may
   show before a menu is opened is D13.)*
3. **Tabit token flow details.** Unverified beyond "a session token is issued on the
   QR landing page". Default: defer the adapter until a real payload has been
   captured.
4. **Whether to show `net_carbs_estimate` at all.** The model can produce a number;
   it cannot be trusted as fact. *(Issue #30: reversed. `DishCard`'s net-carb chip
   now renders it — "~{n}g net carbs (estimate)", never a bare number — and is
   **hidden entirely** when `AnalysedDish.netCarbsEstimate` is null, which is
   always true for a rules-engine result: `HeuristicMenuClassifier` never sets the
   field, so a rules verdict shows no chip at all. The chip's own copy and its
   `Semantics` label both say "estimate", not a fact, which is the constraint this
   answer is conditioned on — see `lib/widgets/dish_card.dart` and the
   `netCarbsChip*` keys in `lib/l10n/app_en.arb` / `app_he.arb`.)*
5. **Cache freshness window.** 24 hours is a guess. *(Phase 1: settled at 24 hours
   in `menuCacheTtl`, with an exclusive boundary — see §6.4. Still a guess, but now
   a guess in one named place.)*
6. **Hosting the backend beyond `localhost`.** D11 ships `backend/` to be run
   locally; nothing yet says where it runs for anyone other than a developer
   with the repository checked out. Default: `localhost:8000` only, tracked as
   its own issue (#109, `backend_plan.md` §5), and the app's "the backend is an
   accelerator, never a dependency" property (D11) is exactly what makes leaving
   this open safe — every build works with no backend configured at all.

---

## 18. Engineering standards

These standards are part of the architecture, not a style preference. They are
enforced by tooling wherever tooling can enforce them (§18.2, §18.5) and by review
where it cannot. They apply from the first commit of application code.

They sit on top of the repository's convention documents on `main`:
`ISSUE_CONVENTIONS.md`, `PR_CONVENTIONS.md`, `MILESTONE_CONVENTIONS.md`,
`UNIT_TEST_CONVENTIONS.md` and `FLOW_TEST_CONVENTIONS.md`. Where this section is
stricter (the coverage gate, fakes for project interfaces, the layer test), this
section wins; everything else in those documents applies as written.

### 18.1 SOLID, as concrete rules for this codebase

**Single responsibility.** Each class has one reason to change, and the split points
are fixed:

- A platform adapter does HTTP and nothing else; its mapper turns JSON into `Menu`
  and does no I/O. A change to Wolt's URL touches `wolt_adapter.dart`; a change to
  Wolt's JSON touches `wolt_menu_mapper.dart`.
- `MenuResponseParser` validates; `MenuAnalysisPrompt` builds text;
  `LlmMenuClassifier` sequences the two through the client. None of them knows the
  key, the URL, or a widget.
- A controller holds screen state and delegates. It never parses JSON, formats a
  price, or builds a regex. A widget renders; it never calls a service.
- `constants.dart` is the only home for thresholds, caps and vocabularies.

**Open/closed.** Adding a platform is a new `PlatformMenuAdapter` registered in
`di.dart`. Adding an engine is a new `MenuClassifier` handed to the router in
`di.dart`. No `switch` on `MenuSource` or on engine type exists outside the adapter
registry and the router. If a feature requires editing three existing classes to add
a fourth case, the abstraction is wrong and the pull request says so.

**Liskov substitution.** Every implementation of an interface obeys the interface's
documented contract, and the contract is executable: `test/services/` holds one
shared contract suite per interface (`menu_classifier_contract.dart`,
`platform_menu_adapter_contract.dart`, `menu_cache_contract.dart`) that every
implementation, including the fakes in `test/fakes/`, is run through. "Never
throws", "returns a sealed result", "a yellow carries an instruction" are contract
assertions, not comments.

**Interface segregation.** Interfaces are small and consumer-shaped: `LlmChatClient`
has `complete`; `InstallIdStore` has `id`; `Clock` has `now`;
`AppLogger` has `info` and `warn`. A controller depends on the two or three interfaces
it uses, never on a "services" bag. A widget depends on its controller, never on a
service.

**Dependency inversion.** Every service is depended on as an abstraction and
supplied by constructor injection. `di.dart` is the composition root and the only
file under `lib/` that constructs a concrete service, an `http.Client`, a Hive box,
or a plugin wrapper. No service locators, no global singletons, no static state
except compile-time constants. `http.Client` and `Clock` are injected so that tests
control I/O and time. Flow tests call `buildDependencies` with fakes
and get the real app on top.

### 18.2 The import graph is a DAG

The `lib/` import graph must be a directed acyclic graph with a fixed layer order.
The rules are in §5; the enforcement is `test/architecture/import_rules_test.dart`,
which runs in the ordinary unit-test job and:

1. resolves every `import`, `export` and `part` in `lib/` that points inside the
   package;
2. fails if any import points to a higher layer, or to a higher-ranked sub-package
   inside `services/`;
3. fails if `models/`, `utils/` or `services/` import Flutter beyond
   `foundation.dart`;
4. runs a cycle detection over the whole graph and prints the cycle if one exists.

The test landed with the first skeleton, so the first file that breaks the
layering fails CI rather than starting a habit. Adding a layer or a sub-package
means editing the rank tables in that test in the same pull request, and saying why.

*(Phase 1)* The test skips generated paths — currently `l10n/generated/`. These
rules police the layering of code a person wrote, and `flutter gen-l10n` emits a
base class and one subclass per locale that import each other, a cycle no author
can remove. It is the fourth gate to exclude that directory: the analyzer, the
coverage gate and the all-imports helper already did, and the exclusion is named
and explained in one place in the test. That was the only edit this phase made to
the rank tables, and it added no layer.

### 18.3 Clean-code rules

- **Lints.** `very_good_analysis` with `strict-casts`, `strict-inference` and
  `strict-raw-types`. `flutter analyze --fatal-infos --fatal-warnings` in CI, so an
  info-level lint fails the build. Suppressions (`// ignore:`) need a reason on the
  same line and are counted in review.
- **Formatting.** `dart format` with the default page width. CI fails on a diff.
- **Immutability by default.** `final` fields, `const` constructors, unmodifiable
  collections at service boundaries. Models are value objects with `==` and
  `hashCode`.
- **Errors as values at boundaries.** A service returns a sealed result. Exceptions
  are allowed inside a service and must be caught before its boundary. `catch (e)`
  without a type is not allowed; `on ClientException`, `on TimeoutException`,
  `on FormatException`, and so on, each mapped to a named reason.
- **No `dart:io` under `lib/`.** *(Phase 1: this replaces the `on SocketException`
  example above, which cannot be written here — `SocketException` is `dart:io`, and
  importing `dart:io` anywhere in `lib/` fails `flutter build web`. `package:http`'s
  `IOClient` already wraps socket errors as `ClientException`, so nothing is lost.
  A test file may import `dart:io` freely; the restriction is on `lib/`.)* One
  consequence worth knowing: `PlatformException` and `MissingPluginException` live
  in `package:flutter/services.dart`, which `services/` may not import either, so
  the two plugin-backed stores catch `Exception` and say why at the top of the file.
- **No `dynamic` past the parser.** JSON is `Map<String, Object?>` until the
  mapper or parser has produced a typed model. Nothing typed `dynamic` leaves
  `services/`.
- **No magic values.** Every number and string with meaning lives in
  `constants.dart` or an enum, with a name and a doc comment saying where it came
  from.
- **Small units.** Functions fit on a screen (about 40 lines); a class with more
  than five constructor dependencies is doing two jobs. Prefer a pure function to a
  class when there is no state.
- **Naming.** Interfaces are nouns (`MenuCache`), implementations say how
  (`HiveMenuCache`), fakes say so (`FakeMenuCache`). Booleans read as predicates
  (`isOnline`, `hasKey`). No abbreviations that are not in this document.
- **Doc comments** on every public class and method in `services/` and `models/`,
  stating the contract: what it returns on failure, what it never does.
- **Logging.** `dart:developer` `log` through one `AppLogger` interface in
  `services/platform/`; no `print`. Nothing logged ever includes the key, a
  bearer header, or an upstream error body.
- **No dead ends.** No `TODO` without an issue number. No commented-out code. No
  feature flags without a removal issue.
- **Pull requests are small.** One concern per pull request; a refactor and a
  behaviour change are two pull requests.

### 18.4 Tests from day one

Three kinds of test, all present from step 1 of the build order (§16), all run on
every pull request:

| Kind | Where | What it exercises | Runs in |
|---|---|---|---|
| **Unit** | `test/` mirroring `lib/` | one class or pure function, dependencies faked at their interface | `flutter test`, seconds |
| **Widget** | `test/screens/`, `test/widgets/` | one screen or widget with its controller, dependencies faked | `flutter test`, seconds |
| **Flow** | `integration_test/flows/*_flow_test.dart` (`FLOW_TEST_CONVENTIONS.md`) | a whole user journey through the real build: routing, localisation, plugins, platform channels; I/O faked through the composition root | `flutter drive` on headless Chrome in CI; on devices before a release |

Rules:

- **A change to `lib/` ships with its tests in the same pull request.** A new public
  method without a unit test, or a new screen without a flow test, is not
  reviewable.
- **Fakes for the project's own interfaces.** `test/fakes/` holds one hand-written
  fake per interface, passing the interface's contract suite; a fake that records
  calls is a few lines of Dart and is readable. `mockito`, as shown in
  `UNIT_TEST_CONVENTIONS.md`, is acceptable for third-party types such as
  `http.Client`, never for an interface this project defines.
- **Deterministic.** No network, no real timers, no real clock, no wall-clock
  `Duration` sleeps. `Clock` is injected; `fake_async` is used where a timeout is
  under test (the LLM client's 120-second one is tested that way).
- **Fixtures are real.** Platform JSON in `test/fixtures/` is a recorded real
  response, redacted only where a field is personal. Synthetic fixtures are labelled
  as such in a comment at the top of the file.
- **Coverage gate: 80% of lines across all of `lib/`**, measured by
  `flutter test --coverage`, enforced by `tool/coverage_gate.sh`. The per-component
  targets in `UNIT_TEST_CONVENTIONS.md` are guidance underneath this gate, not a
  lower bar. Generated files
  (`*.g.dart`, `l10n/` output) are excluded. Because `lcov` only counts files that
  some test imported, `tool/check.sh` first generates a test file that imports every
  file under `lib/`, so an untested file counts as zero rather than disappearing.
- **The architecture test is a test.** `test/architecture/import_rules_test.dart`
  runs with the unit tests and is a required check.

### 18.5 Continuous integration

`.github/workflows/ci.yml` landed with the first skeleton. It runs on every pull request
and on every push to `main`, and every job is a required status check under branch
protection: nothing merges red, and nothing merges without a review.

| Job | Steps | Purpose |
|---|---|---|
| `quality` | `flutter pub get` · `dart format --output=none --set-exit-if-changed` · `flutter analyze --fatal-infos --fatal-warnings` | style and static correctness |
| `test` | generate the all-imports helper · `flutter test --coverage` (unit + flow + architecture) · `tool/coverage_gate.sh` · upload `lcov.info` | behaviour and the 80% gate |
| `integration` | headless Chrome + chromedriver · `flutter drive` for every file in `integration_test/` | the real build on a real browser |
| `build` | `flutter build web --release` · `flutter build apk --debug` | the app still compiles for the shipping targets |
| `ios` | `flutter build ios --no-codesign` on macOS, on pushes to `main` only | catches iOS-only breakage without spending macOS minutes on every push |

Conventions:

- The Flutter version is pinned in two places that must agree: `flutter-version`
  in the workflow and `environment: flutter:` in `pubspec.yaml` (3.47.4 today).
  Bump both in one commit.
- `tool/check.sh` runs `quality` and `test` locally with the same commands; run it
  before pushing. It is the pre-commit hook for anyone who wants one
  (`ln -s ../../tool/check.sh .git/hooks/pre-push`).
- A red `main` is the top priority for whoever broke it; no new work merges on top
  of a red `main`.
- Flaky tests are fixed or deleted the day they flake; there is no retry button.
- Dependencies are updated by a scheduled bot pull request, which goes through the
  same checks as any other.

### 18.6 Definition of Done for a pull request

- [ ] Title, commits and body follow `PR_CONVENTIONS.md` (`[type] description`,
      the five-section template); the pull request does one thing.
- [ ] `tool/check.sh` passes locally; all CI jobs green.
- [ ] New or changed behaviour has unit tests; a new or changed screen has a flow
      test; a new interface has a contract suite and a fake.
- [ ] No new `// ignore:` without a reason; no new `dynamic`, `print`, or bare
      `catch`.
- [ ] Concrete services constructed only in `di.dart`; no new import edge that the
      architecture test had to be edited to allow, unless the description explains
      the new layer.
- [ ] Strings in ARB files for both languages; no user-facing literal in Dart.
- [ ] Failure paths have a named reason and copy; nothing maps to "no internet"
      that is not a network failure.
- [ ] Nothing logs, stores, or sends the key or an upstream error body.
- [ ] `architecture.md` updated if a boundary, a layer, a dependency, or a decision
      changed.
- [ ] Reviewed by someone who did not write it.

### 18.7 What these standards changed in the architecture

The first version of this document already had interfaces for the adapters, the
classifier and the LLM client. Applying §18.1 and §18.2 uniformly changed the
following, and the rest of the document has been updated to match:

- **A composition root.** `lib/di.dart` is new and is the only place concrete
  services are constructed; `main.dart` calls it. Previously wiring was implied to
  live in `main.dart` with services free to construct their own dependencies.
- **Every service is an interface**, not only the three that had obvious
  alternatives. `MenuRepository`, `InstallIdStore`, `MenuCache`, `SettingsStore`,
  `LocationService`, `VenueSearchService` each have an interface, one production
  implementation, and one fake. This is what makes flow tests possible without a
  mocking library.
- **A `Clock` abstraction** in `services/platform/`, because cache freshness was
  reading the real clock, which made it untestable deterministically. *(Phase 1: a
  `Connectivity` abstraction was also listed here, dropped, and later reinstated
  — see D10's full history. `AppLogger` shares the folder with both.)*
- **Adapters split into adapter and mapper.** The mapper is a pure function over
  JSON, tested against fixtures with no HTTP; the adapter only does the request.
- **`services/` is organised into ranked sub-packages** so the DAG rule can be
  stated and checked mechanically rather than by reading.
- **`test/` grew `architecture/` and `fakes/`, `integration_test/` grew `flows/`**, and the repository grew
  `tool/`, `test_driver/` and `.github/workflows/`, all landed with the first skeleton, before any feature
  code.
- **Build order gained step 0**, and step 1 now ends with a green pipeline and
  branch protection rather than with "no screens yet".
