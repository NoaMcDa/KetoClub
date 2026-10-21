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
where the phones stopped using it. **D25 then brought the phones back to it:** a
build with `KETOCLUB_BACKEND_URL` asks the backend first on every platform, for
a complete result (menu and analysis, scan, text menu, website menu, venue
search), with the device's own engines kept as the fallback.

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
through KetoClub's own backend, which holds a key no client ever sees, whenever
the build has a backend URL (D12, D25); otherwise on iOS and Android directly
with the user's own API key (D17); the web build has no other route. When there is no key
or backend, no consent, or no network, an on-device rule engine gives a coarser
answer. A small local FastAPI backend (D11) also proxies Wolt's menu API so the
web build can fetch a live menu despite CORS, and since D25 it reads, classifies
and scans on its own, returning complete results to every platform. The backend
is an accelerator, not a dependency: with none configured, or when it cannot
answer, the app behaves exactly as the fully client-only version did, and it
stores nothing about any individual user — see §11.

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
                               │ {KETOCLUB_BACKEND_URL}/v1/venue-menus, /classify │
                               │   /scan, /text-menu, /website-menu, /venues/…,   │
                               │   /chat, /proxy/wolt/…, /menus (D11/D12/D24/D25) │
                               └─────────────────────────────────────────────────┘
```

\* direct from iOS/Android when there is no backend, or as the fallback when it
cannot answer (D25); the web build reaches Wolt through the backend proxy when
`KETOCLUB_BACKEND_URL` is configured (D11, §13). Since D25 every platform built
with that define asks the backend's complete-result routes first, behind the same
service interfaces the diagram shows, and the direct Wolt and Gemini calls from
a phone are the fallback.

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
   as the fully client-only version did; since D25, with one configured, the
   backend is asked first on every platform and the device's own adapters and
   engines answer whenever it cannot. Every classified-menu result still lives
   on the user's device; the backend keeps short-lived proxy, completion and
   analysis caches and the shared menu store (§6.4, `backend_plan.md`), never a
   per-user record.
2. **One codebase, three targets.** Web, iOS and Android share all business logic.
   Platform differences are confined to permissions, HTTP transport and layout.
3. **The key belongs to whoever makes the call (D12, D17, D25).** On web the
   language model is reached through KetoClub's backend, which holds a Google
   Gemini key server-side, and the browser holds no key at all. On iOS and
   Android the app calls Gemini itself with a key the user pastes into Settings,
   kept in the Keychain or Keystore and sent to Google alone; since D25, when
   the build also has a backend, that key is used only if the backend cannot
   answer. Either way the consent toggle in Settings decides whether dish text
   leaves the device at all.
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
  venue another user already analysed can cost nothing either. Since D25 the
  complete-result routes have their own bucket (10/minute, 60/day, spent only
  on a Gemini call) and their own analysis cache (§6.4).

**With a backend (D25), the first three boxes can be one request.** Instead of
`adapter.fetch`, `normalise` and `classify` as separate steps, the adapter for
a Wolt, 10bis or website ref asks `GET /v1/venue-menus/…?classify=true` (or
`POST /v1/website-menu`) and receives the `Menu` and its `MenuAnalysed`
together. `MenuFetched.analysis` carries the analysis to the repository, which
caches it beside the menu; `MenuController` reuses it under the same
fingerprint-and-options check as any cached analysis and does not classify
again. When the backend cannot answer, the same adapter slot falls through to
the direct adapter and the pipeline above runs as drawn.

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
│   │   └── saved_screen.dart             # Recent tab (was "Saved"): the visit history joined to the cache,
│   │                                     # offline access, remove, rename a scan (#48, #251, #313, #315; D23)
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
│   │   ├── rename_menu_dialog.dart       # a scanned menu's name and city (#315, D23)
│   │   └── mobile_qr_scanner.dart        # MobileQrScanner + its camera page; the ONLY file importing
│   │                                     # package:mobile_scanner (#182); here, not in services/, since it owns a page
│   │
│   ├── state/                            # ChangeNotifiers; constructor-injected with interfaces
│   │   ├── app_dependencies.dart         # immutable holder of service interfaces; filled by di.dart
│   │   ├── venue_search_controller.dart  # the Discovery screen (issue #40, D13)
│   │   ├── menu_controller.dart
│   │   ├── saved_controller.dart         # the Recent tab (#48, #313): RecentEntry = VisitEntry + cached copy
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
│   │   │   ├── settings_store.dart       # interface + PrefsSettingsStore
│   │   │   └── visit_history_store.dart  # interface + HiveVisitHistoryStore: the menus opened on this
│   │   │                                 # device, `menu_history` box; never leaves it (D23, #307)
│   │   ├── llm/                          # rank 0
│   │   │   ├── llm_chat_client.dart      # interface, ChatResult, ChatFailureReason
│   │   │   ├── backend_chat_client.dart  # the ONLY file naming `/v1/chat`; the web build's client (D12)
│   │   │   ├── fallback_chat_client.dart # FallbackChatClient: backend first, the phone's own key second (D25, #331)
│   │   │   └── gemini_chat_client.dart   # the ONLY file naming Google's host; the phones' client (D17)
│   │   ├── location/                     # rank 0
│   │   │   ├── location_service.dart     # interface + sealed LocationResult (issue #37)
│   │   │   └── geolocator_location_service.dart # GeolocatorLocationService; the ONLY file importing package:geolocator
│   │   ├── venue/                        # rank 0
│   │   │   ├── venue_ref_resolver.dart   # pure: pasted URL / slug / ID → VenueRef
│   │   │   ├── qr_payload_router.dart    # pure: a scanned QR payload → QrVenue / QrUnsupportedSource / QrPhotographInstead (#182)
│   │   │   ├── venue_search_service.dart # interface only (issue #39)
│   │   │   ├── backend_venue_search_service.dart # BackendVenueSearchService + FallbackVenueSearchService;
│   │   │   │                             # the ONLY file naming `/v1/venues/nearby` and `/v1/venues/search` (D25, #329)
│   │   │   └── wolt/
│   │   │       ├── wolt_venue_search_service.dart # HTTP only; delegates to the mapper
│   │   │       └── wolt_venue_mapper.dart # pure: Wolt discovery JSON → Venue (fixture-tested, no I/O)
│   │   ├── community/                    # rank 0 — KetoClub's shared menu store (D24)
│   │   │   └── menu_store_client.dart    # interface + BackendMenuStoreClient; the ONLY file naming `/v1/menus` (#309)
│   │   ├── menu/                         # rank 1 — may import storage/ and platform/
│   │   │   ├── menu_repository.dart      # interface + CachedMenuRepository (cache-first, adapter registry)
│   │   │   ├── platform_menu_adapter.dart# interface: fetch(VenueRef) → MenuFetchResult
│   │   │   ├── fallback_menu_adapter.dart# FallbackMenuAdapter: backend adapter first, the direct one second (D25, #327)
│   │   │   ├── backend/
│   │   │   │   └── backend_menu_adapter.dart # menu + analysis in one request; the ONLY file naming
│   │   │   │                             # `/v1/venue-menus` and `/v1/website-menu` (D25, #327)
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
│   │       ├── backend_menu_classifier.dart # POST `/v1/classify` — the ONLY file naming it (D25, #328)
│   │       ├── backend_scanned_menu_classifier.dart # POST `/v1/scan` — the ONLY file naming it (D25, #328)
│   │       ├── fallback_classifiers.dart # FallbackMenuClassifier + FallbackScannedMenuClassifier (D25, #328)
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
│   │   ├── venue_route.dart              # venueRoutePath + VenueOpenHint {name, city}, the venue
│   │   │                                 # route's arguments; replaced a bare String (D23, #307)
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
│   ├── golden/                           # golden_drift_test.dart: committed goldens == a fresh export (D25)
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
│   ├── gen_coverage_helper.sh            # imports every lib/ file so untested files count
│   └── golden/                           # the golden parity corpus (D25, #320): golden_corpus.dart (inputs)
│                                         # and golden_export.dart (runs the real Dart code over them)
├── .github/workflows/ci.yml              # §18.5, gained a required `backend` job
├── ios/  android/  web/
├── pubspec.yaml
├── analysis_options.yaml                 # very_good_analysis + strict modes
│
└── backend/                              # D11 — Phase 3, optional at runtime
    ├── app/
    │   ├── main.py                       # app factory: CORS, lifespan, routers
    │   ├── config.py                     # pydantic-settings (GEMINI_*, WOLT_BASE_URL, ANALYSIS_*, …)
    │   ├── models.py                     # menu_cache, chat_cache, analysis_cache (D25), stored_menus (D24; no install-id column)
    │   ├── schemas.py                    # request/response models; the D25 bodies are camelCase
    │   ├── routers/                      # health, proxy, chat, discovery, website, menus (D24); the D25 routes:
    │   │                                 # venue_menus, classify, text_menu, scan, website_menu, venues
    │   ├── services/                     # wolt, gemini, chat_cache, rate_limit, menu_store (D24); D25: classify,
    │   │                                 # scan, analysis_cache, platform_menu, website_fetch, request_body
    │   ├── keto/                         # D25: the Python port of the Dart menu logic — vocabulary (vocabulary.json,
    │   │                                 # a byte copy of the golden), normaliser, rules, heuristic, prompt, parser,
    │   │                                 # text_menu, dish_kind, score, fingerprint, models; imports no web/HTTP/DB code
    │   ├── platforms/                    # D25: Wolt menu, 10bis menu and Wolt venue mappers (ports of the Dart mappers)
    │   └── website/                      # D25: the website locator, JSON-LD and HTML reader (port of services/menu/website/)
    ├── tests/                            # respx-mocked; no test reaches the network
    │   └── fixtures/golden/              # the 14 golden JSON documents the Python port replays (D25)
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
  `services/llm/backend_chat_client.dart`; `/v1/menus` only in
  `services/community/menu_store_client.dart` (D24); the D25 routes each in
  the one client that calls them — `/v1/venue-menus` and `/v1/website-menu` in
  `services/menu/backend/backend_menu_adapter.dart`, `/v1/classify` in
  `services/classifier/backend_menu_classifier.dart`, `/v1/scan` in
  `services/classifier/backend_scanned_menu_classifier.dart`, `/v1/venues/nearby`
  and `/v1/venues/search` in `services/venue/backend_venue_search_service.dart`;
  `KETOCLUB_BACKEND_URL` only in `di.dart`; `googleapis.com` and the `x-goog-api-key` header only in
  `services/llm/gemini_chat_client.dart`, the phones' direct client (D17);
  `package:flutter_secure_storage/` only in `services/storage/api_key_store.dart`;
  and `openrouter` and `sk-or-` appear nowhere under `lib/` at all. Concrete
  service classes are constructed in exactly one file: `di.dart`.

**Dependencies (initial `pubspec.yaml`):**

| Package | Why |
|---|---|
| `http` | Restaurant APIs; on web, since D11/D12, KetoClub's own backend (`/v1/proxy/wolt/…`, `/v1/chat`); on phones, since D17, Google's Gemini API; on every platform with a backend URL, since D25, the backend's complete-result routes. Small, works on all three targets. |
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
final class MenuFetched extends MenuFetchResult { final Menu menu; final MenuAnalysed? analysis; } // analysis: D19 PDF, D25 backend
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

*(D25)* With a backend URL configured, each registered adapter is a
`FallbackMenuAdapter` over two adapters for the same source: a
`BackendMenuAdapter` (`services/menu/backend/`), which reads the menu **and its
analysis** in one request — `GET /v1/venue-menus/{wolt|tenbis}/{id}?classify=true&
netCarbLimitGrams=N&constraints=…` (one repeated `constraints` parameter per
prompt fragment, never comma-joined) or `POST /v1/website-menu {url, options}`,
under a 120 s timeout (`backendMenuTimeout`: a cold analysis was measured at
33.5 s, §17.1) — and the direct adapter the app used before. The backend's
analysis rides on `MenuFetched.analysis` only when it carries the options the
menu screen would build now and `schemaVersion` 1; otherwise it is dropped and
the device classifies as usual. `CachedMenuRepository` caches it beside the
menu and passes it on, so `MenuController` knows it arrived with the fetch
(and skips the D24 upload, which the server's own write made redundant). The
backend is asked only while the user's AI-analysis consent is on
(`FallbackMenuAdapter.usePrimary`), because these routes analyse what they
read; without consent the device reads the menu its own way. The fallback
fires on `backendUnreachable` (no answer, a timeout, or a reply outside the
route contract) and on `offline` (the backend could not reach the platform,
which another network may still do); every other reason is the platform's or
the site's own answer and stands. Discovery's quick score (D13, D21) is
exempt: `AppDependencies.estimateMenuRepository` is a second
`CachedMenuRepository` over the **direct** adapters and the **same** Hive
cache, so scoring a screenful of cards never asks the server to classify.

**Web caveat (important):** the restaurant platform APIs do not send CORS headers
for arbitrary origins. Native iOS and Android HTTP stacks do not enforce CORS, so the
adapters work there as written. In a browser they will be blocked unless the request
goes through KetoClub's own backend proxy (D11, §13) — `WoltMenuAdapter` takes an
optional `proxyBase` for exactly this, wired in `di.dart` only when the web build was
compiled with `--dart-define=KETOCLUB_BACKEND_URL=…` and a proxy is not otherwise
used. With no backend configured, live menu fetching on the web build is still
blocked and paste-a-menu (Phase 4) remains the fallback path; see §13. Since D25
the web build asks the backend's `/v1/venue-menus` first, and the raw proxy
routes above are what its fallback adapter calls.

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
Gemini key server-side (D12). With a backend URL configured it is no longer the
first engine asked but the **device engine** behind one (D25, below).

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
`DrinksGuideScreen`) is reachable from a card under the Explore search field
(shown in the empty state and above results, hidden while loading; #257). Its content lives in `drinks_guide_data.dart` as Dart literals
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
3. Otherwise → the LLM path. With no backend URL: `GeminiChatClient` on a phone
   or `BackendChatClient` on web (D17). With one (D25): a `FallbackMenuClassifier`
   asking a `BackendMenuClassifier` (`POST /v1/classify`) first and that same
   device engine second — see the D25 paragraph below.
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

**The backend as the first LLM engine (D25).** `RoutingMenuClassifier` is
unchanged: its "LLM engine" slot is now, with a backend URL,
`FallbackMenuClassifier(primary: BackendMenuClassifier, fallback:
LlmMenuClassifier)` (`fallback_classifiers.dart`; built by `llmClassifierFor` in
`di.dart`). Consent and connectivity are still checked by the router *before*
anything leaves the device, so withheld consent sends nothing to the backend
either. The chain, in order:

1. `BackendMenuClassifier` posts `{menu, options}` to `/v1/classify`. The server
   runs the ported prompt, Gemini and the ported parser — or, when Gemini
   fails, the ported heuristic — and answers a `MenuAnalysed` whose engine is
   `llm` or `rules(reason)`. A **rules answer from the server stands**: the
   device does not retry the model, because the server has already told the
   user why (`rules(timeout)` and so on). The client rejects a reply that names
   a dish the menu does not hold.
2. Only when the backend **could not answer at all** does the device engine
   run: `notConfigured` (no backend URL), `backendUnreachable`,
   `timeout`, or `rateLimited` (the 10/minute, 60/day analysis bucket is empty).
   `offline`, `badResponse`, `noDishesFound` and the key reasons are about the
   menu or the connection itself and are returned as they are. The switch is
   exhaustive with no `default`, so a new reason must be placed deliberately.
3. If the device engine fails too, the **primary's** failure is reported, unless
   it was only `notConfigured`, in which case the fallback's is — the one that
   actually tried. Hence `apiKeyMissing` still reaches a phone with no backend
   and no key, and `backendUnreachable` a phone with a dead backend and no key.

The question answerer (§9.5) gets the same shape one level down: on a phone
with a backend, `FallbackChatClient(BackendChatClient, GeminiChatClient)` over
`/v1/chat`, with the same four fall-through reasons; on web it is the
`BackendChatClient` alone.

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
`LlmMenuClassifier` holds. *(D25: with a backend URL the vision slot is
`FallbackScannedMenuClassifier(BackendScannedMenuClassifier, VisionMenuClassifier)`
— `POST /v1/scan {pages: [{mimeType, data}], options}` first, the device's own
vision call under the same four fall-through reasons second. The router in front
still applies consent and connectivity before any page leaves the device. The
server's `/v1/scan` has **no rules fallback** either: a Gemini failure is
its chat status and reason, an empty analysis bucket is 429, and every scan
spends the bucket because images are never cached.)*

**`VisionMenuClassifier`** sends one request per scan (D6), all pages in it as
`images` in reading order. The system prompt is
`MenuAnalysisPrompt.visionSystemPrompt`: a vision preamble ("the user message
holds N pages of one menu; transcribe every dish name exactly as printed, in
the menu's language, ids `v1..vN` in reading order, then classify each"),
then the text path's `systemPrompt` byte for byte. The user prompt is one
short line; the response schema and `schemaName` are the text path's,
unchanged, so the backend's schema conversion is untouched. The reply goes to
`MenuResponseParser.parseScanned` (§9.4), which returns the transcribed `Menu`
and its `MenuAnalysed` together: `VenueRef(scan, <8 hex digits of
TextNormaliser.menuFingerprint of the transcription>)` — the paste scheme
(D18), so reading the same pages twice is one entry (D23, #308; the clock
stamps only `fetchedAt` and `analysedAt`) — one category `scanned` (named
"Scanned menu" / "תפריט סרוק" in the menu's own language, §12), every dish `price: 0` with no
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

**Banto: the allergen rules pass, the one place rules outrank the model
(D26, ALG-04).** With `--dart-define=BANTO_MODE=true` and a profile holding
more than keto, the classifier above still answers the keto verdict and,
with `restrictionsRequested`, an ingredient list per dish (§9.6). The
profile is applied afterwards, on the device only (C1):
`ClassificationRules.allergenFindings` runs the allergen vocabulary over the
dish's name, description and non-removal option values, and
`ProfileEvaluator.evaluate` unions those findings — always recomputed from
the dish, never trusted from a cache or a server — with the analysis's own
concerns and the concerns read from its ingredients. A model result can add
or raise a concern, never remove one. A `stated` or `likely` concern moves
the state for every entry, strict or flexible (D26's #346 amendment). Only a
strict entry (an allergen,
celiac disease, the user's own words) turns a suspected finding into "ask"
or takes a kitchen-signal demotion; a flexible entry lists it. The derived
`DishState` (fits, with a change, ask, avoid) is the UI's; the wire verdict
is never rewritten, and the keto verdict stays the model's whenever it
answered. The heuristic classifier attaches the same rules concerns only
when `restrictionsRequested`, so keto output is byte-identical.

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
| `SettingsStore` | `shared_preferences` | UI language, filter defaults, consent flag, last venue, appearance, net-carb limit (2–25 g, default 6), dietary toggles (seed-oil free, dairy-free, carnivore only; all off by default, a missing key reads as off), the Banto restriction profile (`dietaryProfile`, written only when non-empty; a missing or unreadable value reads as empty; D26) and the other people's profiles and which are combined (`profileName`, `groupProfiles`, `activeProfiles`, each written only when not its default; ALG-12) | until cleared |
| `VisitHistoryStore` | `hive` (`menu_history` box) | one `VisitEntry` per `VenueRef` opened on this device (D23): the name and city it was shown under, first and last opened, open count, and the dish count, score and green/yellow counts it last had | until the row is removed or Settings clears saved menus |

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
an install id alongside its content (§11, `backend_plan.md` §3.5). *(D25 adds a
third, below.)*

**Server-side, the analysis cache (D25).** `analysis_cache` holds one complete
**language-model** analysis per `sha256(menu fingerprint | GEMINI_MODEL |
schemaVersion | netCarbLimitGrams | dietaryConstraints)`, for
`ANALYSIS_CACHE_TTL_SECONDS` (default 7 days, against the chat cache's 24 h:
a menu's dish text rarely changes, and a changed one is a different
fingerprint). Only an `llm` analysis is ever written — a rules fallback never
is, so a Gemini outage cannot pin rules verdicts for a week — and a scan, whose
input is images, never touches it. The fingerprint is the 32-bit dish-text hash
a scan is addressed by, so a hit is re-checked before it is served: the same
engine, schema version and options, and every verdict naming a dish id and name
the menu holds. Two venues with the same dishes under different ids (a chain on
two platforms) therefore miss rather than get verdicts for ids they lack. A
hit spends no Gemini call and no analysis bucket. It is keyed by neither the
install id nor the prompt text (see D25's costs).

**Server-side, and not a cache (D24).** The `stored_menus` table keeps one row
per `(source, platform_id)` that a consenting device opened: the menu, its
language-model analysis without `options`, the venue name and city, and
first/last-seen times with an upload count. It has no expiry and no install-id
column; the id `POST /v1/menus` requires spends the rate limiter and is
deleted before anything is stored or logged.

Cache rules:

- A cached **menu** is fresh for 24 hours. After that it is refetched; the old
  analysis is discarded only if the refetched menu differs (compare a hash of the
  normalised dish text).
- A cached **analysis** produced by the **heuristic** engine is replaced the next time
  the LLM engine is available, without asking, because it was always the weaker
  answer.
- The cache never stores the raw platform JSON, only the normalised `Menu`.
- The user can clear the cache from Settings; since D23 (#314) the same Clear
  empties the visit history too, so the Recent tab is empty afterwards.
- **The Recent tab lists the visit history, not the cache** (D23, #313). A
  visit is recorded only by `MenuController.open`, never by Discovery's quick
  score, which writes cache entries for venues nobody opened. Each history entry
  is joined to its cached copy by `VenueRef` into a `RecentEntry` whose numbers
  prefer the cached copy and fall back to the visit's snapshot, and whose
  availability is one of four states: kept (pinned), the expiry countdown
  ("Expired, refreshes when opened" once past), "Not on this device, opens
  online" (no cached copy), or, for a scan with no cached copy, "No longer on
  this device" — inert, since no platform can serve a scan again, but still
  removable. Removing a row removes both the history entry and the cached copy.
- A cached menu can be **pinned** (the Recent tab's "Keep" toggle, issue #253;
  `MenuCache.pin`): a pinned entry is served from the cache without a refetch
  however old it is, until the user asks for a refresh (`forceRefresh` still
  refetches, and the pin survives it). The pin is a set of cache keys in a
  second Hive box (`menu_cache_pins`), so the entries' stored shape is untouched
  and no migration is needed; it flags a menu, never a user record (D8). Removing
  an entry unpins it, and Settings' "Clear" clears pinned entries too. The
  Recent tab shows each unpinned row's remaining time (`fetchedAt` plus
  `menuCacheTtl`, bucketed like the age label) and "Expired, refreshes when
  opened" once the window has passed.
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

No health data, no diary, no user profile is stored. KetoClub's storage is a
cache, one secret, and a list of the menus opened on this device (D23).

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
   result card shows before its menu is opened is D13 as amended by D21: a
   score and counts from an analysis already in the device cache, or from the
   capped rules-only quick score that runs when a list arrives; no menu fetch
   on scroll.

   *(D25)* With a backend URL, the service in `AppDependencies` is a
   `FallbackVenueSearchService(BackendVenueSearchService, WoltVenueSearchService)`.
   `GET /v1/venues/nearby?lat&lon&lang` and `POST /v1/venues/search {query,
   lang, lat?, lon?}` answer `{venues: [Venue JSON]}` already mapped by the
   Python port of `WoltVenueMapper`, in Wolt's order; the device still sorts
   nearest-first. The fallback fires on `backendUnreachable`, `timeout` and
   `rateLimited` only — `offline` and `platformChanged` mean the backend
   reached Wolt and that is what Wolt did. Venue search is **not** consent-gated
   (it never sent dish text), but a phone's position now reaches KetoClub's
   server on the way to Wolt, as the web build's always did (D11): the routes
   share the discovery proxy's cache rows (a coordinate key at four decimals,
   no install id beside it) and its 20/minute bucket.

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
| `VenueSearchScreen` | `/` | Locate, search, or paste; opens a venue; a card under the search field opens the drinks guide (#257) |
| `MenuScreen` | `/venue/:source/:id` | Classified menu with filters and engine chip; `/venue/scan/{id}` opens a pasted menu (D18). The route's `arguments` are a `VenueOpenHint {name, city}` (D23). For a scan, the overflow's "Rename" sets the name and city kept in the visit history (#315) |
| `WaiterCardSheet` | modal | Large-type script with copy |
| `SettingsScreen` | `/settings` | In this order (#255, `docs/UX_REVIEW.md` §2.6): Language, Appearance, Your keto rules, Net carb limit, Default filter; then "AI & privacy" — the consent text collapsed behind a "What leaves this device" disclosure with the "Allow AI analysis" checkbox always visible, and the Gemini key entry on iOS and Android (D17); then "Recent menus" (the cache count and clear, labelled after the tab, #251; the clear empties the visit history too, D23, #314); then nothing: the drinks guide moved to an Explore card (#257) |
| `ScanScreen` | `/scan` | Collects menu pages from the camera, the photo library or a PDF, or a menu's text pasted into a field (D18). Analyse hands the pages to `ScannedMenuClassifier` in one call (D15), or the parsed paste to `MenuRepository.store`, and opens `/venue/scan/{id}` (#82, #83). "Scan QR code" (not on web) reads a table's QR code through `QrScanner`; `QrPayloadRouter` sends a Wolt, 10bis, website or PDF link to that venue's `/venue/{source}/{id}` route, and answers a Tabit code ("not supported yet") or an Instagram, Linktree or non-URL code ("photograph the menu instead") with copy on the Scan tab (#182) |
| `SavedScreen` | `/saved` | The "Recent" tab: since D23 (#313) the visit history of every menu opened, pasted, scanned or read from a website on this device, most recent first, each joined to its cached copy for offline access, with remove, and rename on a long-press of a scan row (#315). Titled "Recent menus" with a history (clock) icon, not "Saved": nothing is saved by the user (#251). The route path and class names stay `/saved` / `SavedScreen` |

**The keto score badge's tone** *(issue #241)* follows the score's band, not a fixed green, so a low score never reads as a positive claim: 7 and above is `green.ink`, 4 up to 7 is `amber.ink`, below 4 is the muted `ink3` (`scoreTone`, judged on the score as printed to one decimal), in the menu header and on the venue card alike; `contrast_test.dart` pins each tone against the page background in both themes.

**The bottom-navigation shell** *(issue #11, Phase 1)*, not in this document when
the four screens above were written: `AppShell` wraps all four tab-root routes
(Explore `/`, Scan `/scan`, Recent `/saved`, Settings `/settings`) with a
`NavigationBar`. It is purely presentational — it takes an already-built `child`
and the `currentIndex` `app.dart`'s `generateRoute` supplies, and switches tabs
by replacing the whole stack with the new tab root
(`pushNamedAndRemoveUntil`) rather than an `IndexedStack`, so the stack never
grows — Settings pushed over a menu leaves no menu beneath the next tab (audit
G8) — and each visit to a tab rebuilds its controller from scratch. Back from a
lone tab root other than Explore — the browser's Back button, which a
`Router`-less `Navigator` turns into a pop, or Android's — switches to Explore
instead of leaving the app; Back from Explore leaves it (issue #262). `Scan`
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

**The menu splits into two panes on a wide window** *(issue #225, Phase 8)*.
At `menuTwoPaneMinWidth` (1080px of window) and above, a loaded menu with at
least one dish is laid out as two panes inside a wider cap,
`menuTwoPaneMaxWidth` (1200px), which the menu route passes to `ContentWidth`
in place of 680. The side pane, a fixed 380px (the artboard's column), holds
what decides what the list shows: the header with the keto score, the verdict
tiles, the "Showing" label and source line (with its refresh and open-on
actions), the Filters row and the category chips, which wrap rather than
scroll sideways there, since a mouse cannot drag a row. It scrolls on its own
only when an open Filters row makes it taller than the window. Beside it, past
a divider, the dish list scrolls alone: the progress row, the analysis and
cache notices, the rules banner or engine chip, the dishes and the
unclassified section. The dish list keeps the screen's one `ScrollController`
and the pull-to-refresh, so a chip jump, a tile filter, a search, a refresh
and the Waiter Card work as they do on a phone. The header never scrolls under
the app bar there, so the bar shows no venue name (issue #237 applies below
1080px only). Below 1080px, and for the loading, failed-fetch and empty-menu
states at any width, the screen is the single capped column above, unchanged.

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
| **KetoClub backend — chat** | `POST {KETOCLUB_BACKEND_URL}/v1/chat` | `X-KetoClub-Install-Id` (no model key from the client) | Phase 3 (D12) | Forwards one completion per menu to Google Gemini; see §9. Since D25 the web build's menu-question and fallback-classifier path, and a phone's first choice for menu questions; classification itself goes through the routes below |
| **KetoClub backend — venue menus** (D25) | `GET {KETOCLUB_BACKEND_URL}/v1/venue-menus/{wolt\|tenbis}/{id}?classify=true&netCarbLimitGrams=N&constraints=…` | `X-KetoClub-Install-Id` (analysis bucket); no `Authorization` | D25 (#333, #327) | The platform's menu mapped to a `Menu` and, with `classify`, its `MenuAnalysed`: `{menu, analysis \| null, fromCache, fetchedAt}`. Reads the menu proxy's own cache. 404 `notFound`, 502 `platformChanged`/`offline`, 504 `timeout`. Upserts `stored_menus` |
| **KetoClub backend — classify** (D25) | `POST {KETOCLUB_BACKEND_URL}/v1/classify` `{menu, options}` | as above | D25 (#333, #328) | `{analysis}` for a menu the client holds (≤ 768 KiB, else 413). A Gemini failure is a 200 with rules stamped `{kind: rules, reason}`; an empty analysis bucket is 429; never writes `stored_menus` |
| **KetoClub backend — text menu** (D25) | `POST {KETOCLUB_BACKEND_URL}/v1/text-menu` `{text, options}` | as above | D25 (#333) | A pasted menu read by the ported `TextMenuSource` and analysed: `{menu, analysis}`, ref `scan/<fingerprint>`. 422 `noDishesFound`. The shipped client still pastes on the device; this route has no caller in `lib/` |
| **KetoClub backend — scan** (D25) | `POST {KETOCLUB_BACKEND_URL}/v1/scan` `{pages: [{mimeType, data}], options}` | as above | D25 (#334, #328) | Pages read and classified in one Gemini request: `{menu, analysis}`, every dish with its `page`. No rules fallback; every scan spends the bucket; pages are forwarded and dropped |
| **KetoClub backend — website menu** (D25) | `POST {KETOCLUB_BACKEND_URL}/v1/website-menu` `{url, options}` | as above, plus the website install and per-site buckets | D25 (#334, #327) | A restaurant's site fetched, read and analysed server-side: `{menu, analysis \| null}`, ref `website/<url>`; the `/v1/website/fetch` reasons, plus 404 `menuNotFound`. A linked PDF goes through the scan path. Upserts `stored_menus` |
| **KetoClub backend — venue search** (D25) | `GET {KETOCLUB_BACKEND_URL}/v1/venues/nearby?lat&lon&lang`; `POST …/v1/venues/search` `{query, lang, lat?, lon?}` | `X-KetoClub-Install-Id` (discovery bucket) | D25 (#335, #329) | `{venues: [Venue]}` in Wolt's order, mapped server-side. 429, 502 `platformChanged`/`offline`, 504 |
| **KetoClub backend — menu store** (D24) | `POST {KETOCLUB_BACKEND_URL}/v1/menus` `{source, platform_id, venue_name, city, menu, analysis}`; `GET …/v1/menus/{source}/{platform_id}` | `X-KetoClub-Install-Id` on the POST, for the rate limiter only (the `/v1/chat` bucket); none on the GET | Phase 3 (#310, #312) | Upserts one opened menu keyed by venue: 201 new, 200 refreshed. Called on **every** platform built with a backend URL, phones included, and only with the AI-analysis consent; the analysis travels without its `options`. The app does not call the GET |

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

**Since D25 the prompt and the parser exist twice, and the goldens keep them
equal.** The complete-result routes (`/v1/classify`, `/v1/venue-menus`,
`/v1/text-menu`, `/v1/scan`, `/v1/website-menu`) build the prompt and parse
the reply on the server, so `backend/app/keto/prompt.py` and `parser.py` are
ports of `menu_analysis_prompt.dart` and `menu_response_parser.dart`. Dart is
the source of truth: `tool/golden` runs the real Dart code over a fixed corpus
and writes `backend/tests/fixtures/golden/prompt.json` (every system prompt
and both schemas, byte for byte) and `parser.json` (63 text replies and 34
scanned ones, each with its expected analysis or failure), and the Python
tests replay them. Everything in §9.1 to §9.4 therefore holds on the server
unchanged, with one deliberate difference: the server's parser never throws
either, but a reply it cannot use is not an error to the client — the route
answers the ported heuristic stamped `rules(badResponse)`, as the router would
have (`/v1/scan` has no such answer and returns 502 `badResponse`). The system
prompt is also part of `/v1/chat`'s completion-cache key (§9.3), so a prompt
that drifts between the two languages would silently fork that cache, not just
change the model's input.

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
`responseSchema` dialect exists. The scan path sends this schema plus one
more dish property, `page`; see D22 (§14).

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
client's** (D12; and since D25 the same Gemini client, `app.services.gemini`,
also serves the complete-result routes, with their own cache and bucket — a
D25 classification does not read or write the chat cache described below). `BackendChatClient` does one thing: `POST {baseUrl}/v1/chat`
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
body, {required DateTime analysedAt, required AnalysisEngine engine, int
netCarbLimitGrams, int? pageCount})` returns a `ScannedMenuResult`
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
- **A page rule is added (D22).** A kept element's `page` becomes `Dish.page`
  only when it is a whole number from 1 to the scan's page count; anything
  else leaves it null and is never a rejection.
- **The ref is derived from the content, not passed in (D23, #308).** The
  transcribed menu is addressed `VenueRef(scan, <8 hex digits of
  TextNormaliser.menuFingerprint>)`, the scheme `TextMenuSource` uses for a
  paste (D18): a provisional menu is fingerprinted and the final one built
  under that ref. The fingerprint reads dish text only, so `Dish.page` and
  `analysedAt` never move it, and the same dishes read twice, or read once and
  pasted once, are one entry. It replaced a ref the caller built from the
  clock, which made every re-read a new entry.

### 9.6 Banto: extract, then evaluate on the device (D26, ALG-03)

The epic weighed two ways to ask the model about a restriction profile:
**A**, send the profile and ask for a verdict per restriction, and **B**,
ask once per menu, independently of the profile, for each dish's
ingredients, and evaluate the profile against them deterministically.
**B was chosen**: one extraction serves every profile, so the analysis
cache and the shared store stay useful; the result is reproducible and
testable without a model; the rules can be the authority for strict
entries by construction; and "why" can quote the exact ingredient. D26
then tightened B with C1: the evaluation runs **on the device only**,
so the profile never leaves it, not even as ids, and the backend performs
only the two profile-independent steps (the extraction and the rules
concerns).

- **The request.** `ClassificationOptions.restrictionsRequested` is the one
  thing that leaves the device (C2): true with `bantoMode` on and an active
  profile holding a non-keto entry. Only then does `systemPrompt` append
  the extraction section, `responseSchema` add `ingredients`
  (`{name, certainty, role}`), and the vision prompt and schema add
  `ingredients` and each dish's printed `description`. The menu screen and
  the Scan tab build these options alike, so a scan's stored analysis is the
  one the menu screen reuses. Discovery's quick score stays keto-only. With
  the flag off, the prompt, schema, snapshot and cache key are today's,
  byte for byte, and there is no `concerns` property in any schema.
- **The parser.** §9.4's rules hold, plus: an ingredient with a bad name or
  certainty is dropped, an unknown role reads as `unknown`, at most 40 are
  kept, and an ingredient the dish's own text does not support is capped at
  `suspected`. A described dish with an empty list keeps its keto verdict;
  the rules pass is then its only source of concerns (no per-dish
  `badResponse`, an amendment of the epic). No `schemaVersion` bump (C3):
  the new fields read tolerantly and the flag is part of `matches`.
- **The evaluation.** `ProfileEvaluator` (§6.2) on every analysed dish,
  then the kitchen signals and declarations (D26). A profile change is
  re-evaluated from the cached analysis with no request; only a change that
  flips `restrictionsRequested` (keto-only to a first restriction, or back)
  asks for a new analysis on the next open.

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

**What D25 changes in this table.** No reason is added; where a reason can now
arise changes. A backend-served menu or analysis that cannot be had falls to the
device's own engine first (§6.1, §6.2), so `MenuFetch.backendUnreachable` and
`Analysis.backendUnreachable`/`timeout`/`rateLimited`/`notConfigured` reach the
user only when the fallback fails too (the primary's reason is the one
reported, except that a primary that only said `notConfigured` yields to the
fallback's). `Analysis.rateLimited` now has a second source on every platform
— the analysis bucket (10/minute, 60/day) — and a *server-stamped* rules result
(`rules(timeout)`, `rules(rateLimited)`, `rules(badResponse)`, …) is shown
as it is, never retried on the device. `Analysis.notConfigured` is no longer
"web only": it is also what an unconfigured phone's primary says before the
fallback runs, and a scan whose *server* has no key now has its own copy
(`scanScreenFailureServerNotConfigured`: "KetoClub's server is not set up to
read menu pages yet"). `apiKeyMissing` and `apiKeyRejected` come only from the
device engine, so a phone sees them only when the backend could not answer.

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
    sends no install id anywhere for analysis — until D25, when a phone built
    with a backend URL sends it too, to the complete-result routes, where it
    keys the analysis bucket and nothing else (never stored, never logged
    beside content). No location and no user identity go to the model, ever;
    the venue name and city leave only for the shared menu store, below (D24).
    Since D25 the dish text of a backend-served analysis is also sent to
    KetoClub's server from a phone, which forwards it to Google exactly as it
    does for web; the phone's own key reaches Google only as the fallback.
  - Menu pages, when the user scans one (D15): the photographs or PDF go to
    Google Gemini as `inline_data` parts, the same two routes as dish text —
    straight from a phone with the user's key (D17), or on web through the
    backend's `/v1/chat`. The backend forwards them and drops them: a page is
    never stored server-side, never enters the completion cache or its key,
    and never reaches a log line — the chat log carries an image count, never
    bytes, a media type or base64. A photograph can hold more than the menu
    (a hand, a face, a receipt); what is in the frame is sent as taken.
  - To KetoClub's shared menu store (D24, `POST /v1/menus`), on every
    platform built with a backend URL — phones included, the one backend
    route a phone calls — and only under the AI-analysis consent: the menu as
    the device normalised it, its analysis when the language model made it
    (without `options`, so no net-carb limit or dietary toggle), and the
    venue's name and city (Wolt's, or what the user typed when renaming a
    scan). Never a position. The install id goes in the same request for the
    rate limiter only and is deleted before anything is stored or logged:
    `stored_menus` has no column for it and no log line puts it beside the
    content. The consent copy in Settings and the Scan tab's disclosure, on
    both builds, says what is stored.
  - To KetoClub's server for venue search (D25), on every platform with a
    backend URL: the typed query and, for "near me", the device position. The
    server forwards them to Wolt and returns venues; the position appears only
    as a four-decimal key of a response cached for five minutes, never beside an
    install id. This does not depend on the AI consent, since no dish text is
    involved. Settings' consent copy says, on every build, that the position
    goes "to Wolt" and is "not stored"; the web build already sent it through
    the backend under that wording, and D25 did not reword it (§17.7).
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
  Where the text goes depends on the build (D17, D25): on iOS and Android
  without a backend URL it goes straight from the phone to Google's Gemini API
  with the user's own key; on a phone with one it goes to KetoClub's server
  first, and the user's key is the fallback (`settingsConsentBodyDirectViaBackend`,
  `scanScreenDisclosureDirectViaBackend`, selected by
  `AppDependencies.backendConfigured`, issue #330); on web it goes through
  KetoClub's server as above. The banner and Settings disclosure say which.
- **The model's output is data.** It is parsed by rules and rendered as text. No
  field is ever executed, used as a URL, or used to choose code paths beyond the
  three-valued verdict.
- **Menu content is untrusted too.** A dish named "ignore previous instructions" is
  a dish with an odd name; it is sent in the user turn, never the system turn, and
  it fails or passes the parser like any other.
- **No secrets in the repo.** `.gitignore` already excludes `.env*`; there is nothing
  to put in one.
- **Banto (C1): the restriction profile never leaves the device, not even as ids.**
  Only the menu text, the keto settings and, when the profile holds more than
  keto, `restrictionsRequested: true` (a request to list ingredients) are
  sent; exceptions and the user's own words stay on the device too. The
  disclosure says so in both languages (`whatLeavesDeviceBanto`, in the
  Explore banner and Settings' privacy text), and a Banto build shows the
  banner once more to anyone who acknowledged only the keto text
  (`AppSettings.disclosureCopyVersion`, ALG-11). Two tests pin it:
  `test/architecture/no_profile_on_the_wire_test.dart` (no file under
  `lib/services/` can name a restriction id, a dietary profile or a severity,
  save the allowlisted ALG-14 confirmation client, whose one fact names a single
  restriction id; D26) and
  `backend/tests/test_menus_profile_rejected.py` (`POST /v1/menus` answers 422 to a
  body that carries one). The product is a helper tool that makes no accuracy or
  medical claim; see `docs/TERMS_NOTES.md`.

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
  - **Since D25 the web build asks the complete-result routes first.** The
    menu fetch is `GET /v1/venue-menus/…?classify=true` (or `POST
    /v1/website-menu`), the analysis `POST /v1/classify`, a scan `POST /v1/scan`
    and venue search `/v1/venues/…`, all with the same CORS rules as the routes
    above (`X-KetoClub-Install-Id` is an allowed header; `X-KetoClub-Cache`
    is exposed). The raw proxy, website-fetch and `/v1/chat` routes remain as
    the fallback each of those chains falls through to.
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
*(D11 amends this; D24 adds the first server-side record that outlives a
cache, `stored_menus`: opened menus keyed by venue, never by user; D25 makes
the backend the first thing every platform asks, with the client-only app as
its fallback.)*

**D2 — The LLM is the primary classifier; rules are the fallback.**
Supersedes README §3/§6 and `CLAUDE.md`'s "heuristic-based classification". Follows
`feature_prioratization` Tier A and the engine analysis in
`m16_menu_scanner_research.md` §4: a rule table cannot explain *why* or write a
dish-specific instruction, and cannot read a dish it has never seen. The rule engine
stays because it answers offline and without a key, behind the same interface.
*(D25 amends this: the rule engine now exists twice, in Dart and in a Python port
on the backend, which uses it for its own fallback; the model is still primary
and the Dart engine is still the one the device falls back to.)*

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
here. *(D23 and D24 keep this true by what they key on: the visit history is a
list of the menus opened on this device, like pins and notes, and the shared
menu store holds menus keyed by venue with no install id beside them. Neither is
a record of the user.)*

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

*(D25 amends this: the backend is still an accelerator, but no longer a
passthrough. "Nothing above the seam knows the backend exists" now holds for
the screens and the parser, not for `MenuFetched.analysis` and the estimate
repository, and `backend_plan.md` §2's "deliberately dumb: it does not
normalise Wolt JSON, build prompts or parse model replies" is reversed — it
does all three, from a Python port pinned to the Dart code by a golden corpus.)*

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

*(D24 amends this: `POST /v1/menus` spends the same per-install bucket as
`/v1/chat`, and the backend now keeps one table that is not a cache,
`stored_menus`, beside its two caches. D25 adds a third cache, `analysis_cache`,
and a second per-install bucket, for the complete-result routes.)*

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
- **A, bounded, since D21.** As decided here, A was never background
  behaviour: an explicit "Estimate this list" tap only. D21 reverses that
  one point — the first `venueAutoEstimateLimit` visible venues are scored on
  their own when a list arrives — and keeps every bound: the rules engine
  only, `venueEstimateConcurrency` fetches at a time, each venue once per
  result set, cancelled when the list changes, never on scroll. The tap
  remains, as "Quick score the rest", for the venues past the cap.

**The score formula is kept exactly as `utils/keto_score.dart` computes it**:
`10 × (green + 0.5 × yellow) / (green + yellow + red)`, rounded to one
decimal, with unclassified dishes in neither numerator nor denominator, and
null — nothing rendered — when no dish was placed. Since D21 only *food*
dishes feed those counts: a drink, a sauce or add-on, or a notice line is
listed but not counted. The card reuses that
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
performance budget gains a hard rule: **no menu fetch on scroll** — scrolling
reads the device cache and nothing else. (On load, D21's capped rules run is
the one fetch this rule now allows.)

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

*(D22 amends this: the pages are budgeted as a whole before the request, and
the vision reply's schema gains a per-dish `page`. D23 supersedes the scan's
clock-stamped ref: a read menu is `VenueRef(scan, <menuFingerprint hex>)`, the
paste scheme, so reading the same pages twice is one entry. D25 puts the
backend's `POST /v1/scan` in front of the device's vision call, still with no
rules fallback; see D25.)*

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
already web-only. **Amended by D24 for one route only:** a phone built with
`KETOCLUB_BACKEND_URL` posts the menus it opens to the shared menu store,
`/v1/menus`; it still calls Wolt and Gemini directly. **Amended again by
D25:** a phone built with a backend URL asks the backend first for menus,
analyses, scans and venue search, and calls Wolt and Gemini itself only as the
fallback; the rules below describe a phone with no backend URL, and the
fallback path of one with it. "Has no effect there even when it is set" is no
longer true.)* D11 promised that
the backend is "an accelerator, never a dependency", but D12 made every platform's AI analysis depend on it: a phone
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

*(D23 amends this: a scan read from photographs now takes the same
content-addressed ref, a scan can be given a name and a city through "Rename"
(kept in the visit history, never on the `Menu`), and its Recent row outlives
its cache entry as an inert "No longer on this device".)*

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

*(D25 amends this: `POST /v1/website-menu` does the whole read on the server —
fetch through the same hygiene, locator, JSON-LD and text reading from a Python
port, one link hop, a PDF through the scan path — and returns `{menu,
analysis}`; `/v1/website/fetch` stays as the raw fetch the fallback web
fetcher uses. The hygiene rules now live once, in
`backend/app/services/website_fetch.py`, shared by both routes. Still no real
site has been read.)*

### D20 — Phase 8: one content width, a responsive Discovery grid, a rail, and the rest of `docs/UX_REVIEW.md`

*(Issues #221–#264, PR #266; `docs/UX_REVIEW.md` is the record of the review
and `MILESTONE_CONVENTIONS.md` the milestone.)* The artboards are 390px phone
frames and nothing constrained width, so the web build on a computer stretched
every card and photo across the window. **Decision:** every screen body sits in
`ContentWidth` (top-aligned, 680px; Discovery 1080px for its grid; the menu
route wider for two panes), the venue list is a `VenueGrid` (1/2/3 columns by
width, 3:2 photos only in the grid, a card surface), `AppShell` shows a
`NavigationRail` at 840px and wider and handles Back with a `PopScope` (Back
from a lone non-Explore tab goes to Explore), sheets open through
`showKetoClubSheet` capped at 560px, and the web shell gets a splash, `--bg`
manifest colours, path URLs and per-route titles. The per-screen decisions the
review left open were taken as the issues recorded: the standing open button
is gone (D8), prices are whole shekels (M12), the menu screen shows the rules
banner and not the chip (M14), Language and Appearance are segmented (S6),
Noto Sans Hebrew is bundled (G7), the yellow verdict has one name, the keto
score is toned by band, and "Saved" is "Recent" with an expiry countdown and a
Keep pin kept in a second Hive box. **What it costs:** more layout code paths
(phone, rail, two-pane) that only widget tests at 390/1200/1440px and CI's
1600px Chrome run exercise; no real browser or phone has shown any of it.

### D21 — The quick score runs on its own for the first cards, and scores count food only

*(Reverses one bullet of D13; answers the owner's review of the Discovery
screen on 2026-10-05.)*

**What changed.** D13 kept option A — fetch the visible venues' menus and
score them with the rule engine — behind an explicit "Estimate this list"
tap, so that fetching N menus in the background was never something the app
did on its own. In practice most cards on a first visit showed no score at
all, which was further from the artboard than the terms risk warranted, and
the tap was mistaken for an AI action that spent tokens (it never did: the
quick score has only ever run `HeuristicMenuClassifier`). Two decisions:

1. **The quick score starts on its own.** When a result list lands (nearby
   or by name), and after a chip change puts venues in view,
   `VenueSearchController` scores the first `venueAutoEstimateLimit` (12)
   visible venues that have no numbers and that no run has fetched in this
   result set. The explicit tap stays as "Quick score the rest" for the
   venues past the cap. Opening a venue is unchanged: `MenuController`
   reuses only an `LlmEngine` analysis, so the AI still runs on open and
   its result overwrites the estimate.
2. **Scores and counts cover food only.** `utils/dish_kind.dart` reads
   each dish's kind — food, drink, extra (sauces, add-ons, cutlery,
   deposits, delivery, gift cards) or notice ("לקוחות יקרים", "coming
   soon") — from the category heading first and the dish name second, never
   the description, and `utils/verdict_counts.dart` is the one place an
   analysis is reduced to counts: the menu header and tiles, the Discovery
   card and the Recent tab all read it. A non-food line is still classified
   and listed under its heading and its verdict filter; it just moves no
   number. On doubt a dish is food, and a dish the menu does not hold is
   food. The kind is computed, never stored: no field on `Dish`, no cache
   schema change.

**What it accepts.** The background fetches are the "systematic retrieval"
pattern D13 refused. The owner accepted that exposure with these bounds: at
most 12 menus per list, 3 in flight, each venue once per result set, cancelled
on any list change, nothing on scroll, nothing when the remembered nearby
list is put back, and on web every fetch goes through the backend's 1 h
menu cache. `/v1/chat` spend stays zero: the rule engine is the only
classifier the quick score may hold (`estimateClassifier` in `di.dart`).

**Vocabulary decisions.** `תוספות` is *not* an extras heading: on an Israeli
menu it means sides, which are food. A heading that names food beside a
drink or extras word — "תוספות ורטבים", "Sauces & Sides", "קפה ומאפה",
"Beers & Burgers" — decides nothing, and each dish under it is read by its
own name, so the croissant counts and the latte does not. Hebrew headings
are matched without the permissive grammatical prefix so `ורטבים` cannot
fire the sauces word. A
drink word in a dish name is an ingredient, not the dish, when a guard word
sits beside it ("beer-battered", "wine-braised", "ברוטב יין"). The drink
lists reuse the classifier's own (`nonKetoDrinkBasesEn/He`, the drink keys of
`carbModifiers`) plus the plain drinks the rules never trigger on (water,
coffee, tea, dry wine, spirits).

**Known limitation.** While *Keto 8+* is on, venues without numbers are
hidden, so a run started by a chip change has nothing to score until the chip
is turned off. Tiles count food only while a tile's filter still lists every
dish of that verdict, drinks included; the legend says so.

**What it costs.** Cards past the cap are still blank until the tap; a 30-venue
nearby list is scored to the twelfth card. The automatic run adds up to 12
Wolt fetches per list, which D13's reading of Wolt's terms counted as a
different category from one fetch per user action.

### D22 — A scan is budgeted as a whole before it is sent, and every transcribed dish remembers its page

*(Amends D15 and the scanned variant of §9.4; adds one vision-only property to
§9.2. Issues #294 (the 503 on a multi-page scan), #295, #296 and #297–#303.)*

**What changed.** D15 sent the pages as they came, each shrunk on its own to
`inlineImageByteTarget` (900 KiB). That limit is per request, not per page:
Gemini answered 503 UNAVAILABLE once the body passed about 1.5 MB on the wire,
so three pages each just under the target still failed together (#294). And
the transcription threw away where a dish came from: a six-page menu was one
flat list, and the only way to check a dish was to open every page. Two
decisions:

1. **A scan is budgeted as a whole (#295, #298).** `ScanBudget`
   (`services/platform/scan_budget.dart`) holds `scanInlineByteBudget`, the
   same 900 KiB as the per-page target but summed over every image page of
   the request. `ScanController.analysePages` runs `fit` before the
   classifier is called. A scan already within budget goes through as the
   same object. Otherwise each image page is shrunk towards an even share of
   the budget (never below `minScanPageTargetBytes`, 120 KiB, under which
   printed text stops being legible) by `ImageDownscaler.downscaleTo`, which
   walks `downscaleLadder` — (1280 px, q75), (1024, 70), (900, 65), (768, 60),
   (640, 55) — decoding once and keeping the first rung at or below the
   target, else the smallest, never anything larger than the input. If the
   shrunk pages still exceed the budget, nothing is sent: `fit` answers
   `ScanTooLarge` and the controller sets `pagesTooLarge`. What is sent, and
   what `ScannedPagesRegistry` keeps, is the fitted scan; the controller's
   own page list keeps the originals.
   - **`pagesTooLarge` is its own state, not a `MenuAnalysisFailureReason`.**
     No request was made, so nothing failed at a service boundary, and the
     failure vocabulary (§10) stays a list of things a call can do. It also
     has no Retry: retrying would send the same pages. The Scan tab says so
     and the way out is to remove a page.
   - **PDFs are exempt, a known limit.** The downscaler cannot shrink one,
     and the backend and the direct client already cap a PDF on its own
     (`VISION_MAX_IMAGE_BYTES`, `maxScanPageBytes`). A PDF is neither counted
     nor refused here, so a large PDF can still meet the 503 this decision
     removes for images.
2. **Every transcribed dish remembers its page (#296, #299–#303).**
   `Dish.page` is a nullable 1-based number. On the wire:
   - **`visionResponseSchema` is the one vision-only divergence from §9.2.**
     It is `responseSchema` plus a `page` property, `["integer", "null"]` and
     in `required` like every other (strict mode has no "optional"), and the
     vision preamble asks for "the number of the page it is printed on, 1 to
     N in the order given, or null". The text schema keeps exactly seven
     properties: a platform or pasted menu has no pages, and a shared schema
     would put a meaningless field in front of every text reply and move the
     backend's completion-cache key for a request that did not change.
   - **The page rule (§9.4, scanned variant).** `parseScanned` keeps an
     element's `page` only when it is a whole number from 1 to the scan's
     page count; `2.0` counts, `2.5`, `0`, `N+1`, a string and `null` do not.
     A bad page leaves the dish's `page` null and is never a rejection: the
     dish keeps its verdict, because a wrong page costs a header, a wrong
     rejection costs a dish.
   - **`schemaVersion` is deliberately not bumped.** `page` lives on `Menu`
     and `Dish`, not in the analysis cache's shape, and an older cached scan
     simply has dishes with no page. Bumping the version would re-analyse
     every cached scan through the text classifier, which has no pages to
     read, and lose the page numbers of every scan that has them. A field
     that lives on `Menu`/`Dish` never needs the bump.
   - **The menu screen groups by page (§6.6).** `MenuController` derives
     `attributedPages` (the distinct pages dishes name, ascending; empty for a
     platform menu), `hasUnattributedDishes` and `pageFilter` (null for every
     page, a page number, or `scanPageUnknown`, 0, for the dishes no page was
     matched to). `visibleRows` applies the page filter last and stably sorts
     by page, unknown last, so each page's dishes sit together in their
     transcribed order. `ScannedPageHeader` heads each group with the page's
     thumbnail, "Page n of N" and its dish count, and opens that page;
     `ScannedPageHeader.unknown` heads the unplaced dishes and is plain
     information. `ScannedPageChips` filters by page and offers "unknown" only
     when some dish has no page. **A one-page scan, a scan whose dishes name
     no page and every platform or pasted menu are unchanged**: no header, no
     chips, category headers as before.
   - **When the registry no longer holds the pages** (a restart, or eviction
     past the last few scans), the headers still number the dishes but cannot
     show a thumbnail or open a page; the page count is then the highest page
     a dish names, and an info notice says the pages are gone.

**What it accepts.** Page provenance is only as good as the model's `page`,
and it has not been observed on a real request (#88). A dish the model could
not place falls under the unknown header, which is honest but unhelpful on a
scan where the model never fills it. Shrinking harder than 640 px is refused
rather than attempted, so a scan of many dense pages may be told it is too
large where a lossier encoding would have gone through.

**What it costs.** Up to five decode-and-encode passes per oversize page on
the device before every analysis of an oversize scan; a vision reply carries
one more integer per dish; the registry holds the fitted, lower-resolution
pages, so "View pages" shows what the model saw, not the original photograph.
The Scan tab gained a state with no failure reason behind it.

### D23 — A permanent on-device history of opened menus, and a scan is addressed by its content

*(Amends §6.4, D8's framing, D15's scan addressing and D18. Issues #305,
#307, #308, #312, #313, #314 and #315.)*

**What changed.** The Recent tab was the menu cache under another name. A
menu was listed while its cached copy lived, so an unpinned venue dropped off
the list a day after it was last opened, and Discovery's quick score (D21), which
writes cache entries for venues the user never opened, put menus nobody had
looked at in it. A scan had a second problem: its ref was the clock's
millisecond stamp, so reading the same pages twice made two entries. Seven
decisions:

1. **A visit history, separate from the cache (#307).** `VisitHistoryStore`
   (`services/storage/visit_history_store.dart`) holds one `VisitEntry` per
   `VenueRef`: the name and city the menu was shown under, when it was first
   and last opened, how often, and the dish count, keto score and green and
   yellow counts it last had. `HiveVisitHistoryStore` keeps it in a third
   Hive box, `menu_history`, opened by a closure on first use like the
   cache's. An entry never expires. Every method never throws: a broken box
   reads as an empty history, so a bad history degrades the Recent list
   rather than the screen above it. It is a list of menus, like pins and
   notes; nothing in it names who opened them, and it leaves the device
   through nothing (D8).
2. **A visit is recorded only in `MenuController.open` (#312).** "In the
   cache" is not "visited". One successful `open` records one visit, once the
   analysis is settled: the name the menu carries, else the opener's hint;
   the hint's city; the dish count; and, for a completed analysis, its score
   and counts through `VerdictCounts.of`. A null never erases a value an
   earlier visit recorded. A failed fetch records nothing, and neither does
   `refresh`. Before fetching, `open` reads the entry so the header can name
   the venue while the menu loads.
3. **`VenueOpenHint` replaces the route's `String` argument (#307).** The
   venue route's `arguments` were the venue's name as a bare string (#169);
   they are now a `VenueOpenHint {name, city}` (`utils/venue_route.dart`),
   passed by a Discovery card and a Recent row and handed by `app.dart`'s
   route builder to `MenuController.open(hint:)`. A deep link carries none.
   Because names and cities are persisted in the history and read back, a
   menu reopened from Recent shows its name, not its slug, cached or not.
4. **The Recent tab lists the history (#313).** `SavedController` joins
   `VisitHistoryStore.entries()` to the cache by ref into `RecentEntry`s,
   most recently opened first; a cached menu with no visit is not listed.
   A row's numbers prefer the cached copy (the menu as it is now) and fall
   back to the visit's snapshot. Its availability is one of four states:
   kept (pinned); the expiry countdown, "Expired, refreshes when opened"
   once past; "Not on this device, opens online" when nothing is cached; and
   "No longer on this device" for a scan whose cached copy has gone. No
   platform can serve a scan again, so that last row is inert: it cannot
   open, but it can be removed. Removing a row removes both the history
   entry and the cached copy.
5. **A scan can be renamed (#315).** A scan has no name of its own (D18).
   The menu screen's overflow offers "Rename" for a `scan` ref, and a
   long-press on a scan row in Recent does the same: a dialog takes a name
   and a city, each trimmed and blank meaning none, written by
   `VisitHistoryStore.rename`, which never creates an entry. The name and
   city live in the history, never on the `Menu`, so the cache, the
   fingerprint and the ref are untouched. Renaming from the menu screen
   uploads the menu again under the new name and city when the user consents
   (D24); renaming from Recent writes the history only.
6. **Settings' Clear clears the history (#314).** "Recent menus → Clear"
   empties the cache and the history together, so the tab it is labelled
   after is empty afterwards.
7. **A scan is addressed by its content (#308).**
   `MenuResponseParser.parseScanned` derives the ref the way
   `TextMenuSource` does for a paste (D18): `VenueRef(scan, <8 hex digits of
   TextNormaliser.menuFingerprint of the transcription>)`. The fingerprint
   reads dish text only, so `Dish.page` and the read time never move it; the
   clock now stamps only `Menu.fetchedAt` and `analysedAt`. The same pages
   read twice, or a photograph and a paste of the same dishes, are one cache
   entry and one Recent row.

**What it accepts.**

- **No backfill.** Menus cached before this change have no visit and are not
  listed until they are opened again, and a scan stored under a clock ref is
  listed nowhere unless the same pages are read again, under the new ref.
- **Collisions.** The fingerprint is 32-bit FNV-1a, so two different
  transcriptions could share an entry, exactly as two pastes already could
  (D18); a collision shows the other menu's dishes, never an invented one.
- **`refresh` does not re-snapshot.** A refresh that changes the menu leaves
  the visit's numbers as they were at open; the Recent row shows fresh ones
  only while the cached copy lasts, because it prefers that copy.
- **Scan-gone rows are inert.** A scan's Recent row outlives its only copy
  and says so; the way back is to scan or paste the menu again.

**What it costs.** One more Hive box, and one more interface threaded
through `di.dart` into `AppDependencies.visitHistory` and three controllers
(menu, Recent, Settings). Two store calls per open: one read before the
fetch, one write after. The Recent tab now joins two stores instead of
reading one.

### D24 — A shared menu store: opened menus, keyed by venue, on KetoClub's backend

*(Amends §11, D1's and D8's "no server database" framing, D12 and D17.
Issues #306, #309, #310, #311 and #312.)*

**What changed.** Nothing the app saw used to outlive the backend's short
caches: every analysis of a venue lived on one device, and Phase 3's
community work (`backend_plan.md` §5, milestone C) has nothing to attach a
rating to until a venue's menu exists server-side. Seven decisions:

1. **One table, `stored_menus` (#310).** One row per `(source,
   platform_id)`: `venue_name`, `city`, `menu_json` (the client's normalised
   `Menu`), `analysis_json`, `dish_count`, `score`, `first_seen_at`,
   `last_seen_at` and `submission_count` (uploads, not installs). **There is
   no install-id column.** `menu_json` and `dish_count` are replaced on every
   upload; `analysis_json` and `score`, `venue_name` and `city` only when the
   upload carries one, so a rules-only upload never erases a stored model
   analysis.
2. **Two routes (#310).** `POST /v1/menus` upserts: 201 when the row is new,
   200 when it was refreshed. It rejects an `Authorization` header as
   `/v1/chat` does, and checks the body against `MENU_STORE_MAX_BODY_BYTES`
   (1 MiB; `Content-Length` first, then the bytes actually read) before
   anything parses it, answering 413 `payloadTooLarge`. It requires
   `X-KetoClub-Install-Id`, which spends the per-install limiter — the same
   `RATE_LIMIT_*` bucket as `/v1/chat` — and is then deleted from scope: it
   is never passed to `services/menu_store.py` and never logged, not even
   truncated. `GET /v1/menus/{source}/{platform_id}` reads a row back with no
   install id and no quota; the app does not call it yet.
   `MENU_STORE_ENABLED` (default true) mounts the router; false makes both
   routes a plain 404.
3. **One client, `MenuStoreClient` (#309),** in a new rank-0 sub-package,
   `services/community/`, and the only file under `lib/` that may name
   `/v1/menus` (an architecture-test boundary). `BackendMenuStoreClient`
   sends one POST per upload — no retries, no pre-check, a 20 s timeout — and
   refuses a body over `maxMenuUploadBytes` (768 KiB) on the device. It
   answers a sealed `MenuStoreResult` with seven distinct failure reasons,
   none collapsed into another (§10), and logs one line per failure, never a
   body or the install id.
   `MenuUpload.toJson` strips the analysis's `options`: the net-carb limit and
   dietary toggles are personal settings and never travel.
   `NoMenuStoreClient` is the default for any dependency set that does not
   name one.
4. **Every platform uploads (amends D17 for this route only).** `di.dart`
   builds the client from `backendBaseUrl(KETOCLUB_BACKEND_URL)` on every
   platform, not from `menuProxyBase`, which is null off the web. So a phone
   built with a backend URL posts here while still calling Wolt and Gemini
   itself, and reads the install id for this alone. With no URL the client
   answers `notConfigured` with no I/O at all.
5. **When it uploads (#312).** In `MenuController.open`, right after the
   visit is recorded (D23), in the background, and only when the user
   consents to AI analysis and the store is configured — and then only when
   the visit is new, or a language-model (`LlmEngine`) analysis was freshly
   classified in this open, or the cached `LlmEngine` analysis is newer than
   the previous visit (a scan or a background fetch saved it since). The
   analysis rides along only when the model made it, so a menu only the
   rules judged uploads once, on its first visit, with `analysis` null: a
   rules result is never reused, and counting it as news would upload on
   every open. Renaming a scan from its menu screen (D23) uploads it again
   under the new name and city. The result is never shown.
6. **The AI consent covers it.** There is no second switch: the consent D16
   defaults on gates the upload, and its copy now says what is stored —
   `settingsConsentBody` and `settingsConsentBodyDirect` ("The menu, its
   analysis, the venue name and city are also stored on KetoClub's server,
   with nothing that identifies you, so others can find them"), and the Scan
   tab's `scanScreenDisclosureWeb` and `scanScreenDisclosureDirect`.
7. **A venue knows its city (#311).** `Venue.city` is read from Wolt's
   discovery items by `WoltVenueMapper` and carried by `VenueOpenHint` into
   the history and the upload. A scan's city is whatever the user types into
   the rename dialog. No platform menu payload carries a city of its own.

**What it accepts.**

- **Over-disclosure on a phone build without a backend URL.** The consent
  copy is chosen per route (web or direct), not per configuration, so such a
  build says menus are stored on KetoClub's server while it sends nothing.
- **Two limiter hits per open on web.** The upload shares the 5/minute,
  40/day bucket with `/v1/chat`, so a first open spends two units where it
  used to spend one, and an upload can leave the next open's analysis
  rate-limited into a rules fallback.
- **A rules-only menu is stored without an analysis.** The row holds the
  dishes and nothing judged until a consenting device with a model opens it.
- **No hosting yet (#109, §17.6).** The store lives in whichever backend a
  build points at, so until the backend is hosted it is shared only by the
  builds pointed at one developer's `localhost`.
- **Fire-and-forget.** A failed upload is neither retried nor surfaced; the
  next qualifying open sends again.
- **The content is unverified and the guard is spoofable.** Any client can
  post any menu for any venue; the install id is random and spoofable
  (`backend_plan.md` §3.4), which is acceptable while the backend is local
  and is #109's to revisit.
- **A stored name can be replaced, not removed.** A rename that clears a
  scan's name or city uploads null, which the store reads as "keep the last
  one".
- **`score` is null for every upload the app makes.** The backend copies a
  top-level `score` from the analysis and computes none; `MenuAnalysed`
  carries no such field.

**What it costs.** A new `services/` sub-package and its rank entry in the
architecture test, one boundary string, one table, one client, and one more
`AppDependencies` field (`menuStoreClient`) and `MenuController` argument.
A phone build with a backend URL now depends on the backend for something,
though nothing the user sees waits on it.

*(D25 amends rules 4 and 5 of this decision: when a menu's analysis arrived
with its fetch from `/v1/venue-menus` or `/v1/website-menu`, the server wrote
the row itself, so `MenuController.open` uploads nothing unless a
language-model analysis was freshly made on the device in that same open. That
also removes the "two limiter hits per open on web" cost above for backend-served
menus. `/v1/classify`, `/v1/text-menu` and `/v1/scan` never write the store;
the client's own upload covers a pasted or scanned menu.)*

### D25 — The backend serves complete results on every platform; the device stays the fallback

*(Amends D2, D11, D15, D17, D19 and D24. Issues #318 and #319 and their
sub-issues #320–#335. Written after waves 0–4 landed on `claude/d25-wave-4`.)*

**What changed.** Until D25 the backend was a passthrough that only the web
build used for menus and analysis: it forwarded Wolt's bytes and one Gemini
completion, and every parser, prompt and rule lived in Dart on the device. A
phone with no Gemini key was rules-only, and nothing a device computed was
shared. D25 moves the whole read-and-classify pipeline behind the backend, so a
client with a backend URL asks for a *complete result* in one request, on
every platform, and keeps the Dart code as its fallback. Nine decisions:

1. **Seven routes, camelCase bodies (#321, #333–#335).** All require
   `X-KetoClub-Install-Id` and refuse an `Authorization` header; the contract
   is `backend_plan.md` §3.3.
   - `GET /v1/venue-menus/{wolt|tenbis}/{id}?classify&netCarbLimitGrams&constraints`
     — the platform's menu, mapped, and with `classify=true` analysed.
   - `POST /v1/classify {menu, options}` — an analysis of a menu the client holds.
   - `POST /v1/scan {pages, options}` — photographed or PDF pages, transcribed
     and classified in one Gemini request (D15, D22).
   - `POST /v1/text-menu {text, options}` — a pasted menu (D18), read and
     analysed. **No caller in `lib/` yet:** the Scan tab still pastes on the
     device, so this route exists for the day it should not.
   - `POST /v1/website-menu {url, options}` — a restaurant's own site (D19).
   - `GET /v1/venues/nearby` and `POST /v1/venues/search` — Wolt discovery,
     mapped to `{venues: [Venue]}`.

   The bodies carry the Dart `Menu`, `MenuAnalysed` and `Venue` JSON key for key
   (nulls included), so the client's `tryFrom` reads them as if it had made
   them. The returned analysis carries the **request's own options** and
   `schemaVersion` 1, which is what lets `MenuController`'s reuse check accept
   it. Options are `{netCarbLimitGrams: 1..50, dietaryConstraints}`, each
   constraint one of the three Dart prompt fragments verbatim (422 otherwise:
   free text would otherwise reach the system prompt under the server's key).
   Consent is not a field: calling a route that analyses *is* the consent, so
   the client never calls one without it (point 5).
2. **A Python port, pinned by a golden corpus, with Dart as the source of
   truth (#320, #322–#326).** `backend/app/keto` (vocabulary, normaliser,
   fingerprint, rules, heuristic, prompt, parser, text menu, dish kind, score,
   wire models), `backend/app/platforms` (the Wolt and 10bis menu mappers and
   the Wolt venue mapper) and `backend/app/website` (locator, JSON-LD, HTML
   reader) reproduce the Dart behaviour. Nothing in Python is the reference:
   `tool/golden` runs the **real Dart code** over a fixed corpus and writes 14
   JSON documents to `backend/tests/fixtures/golden/`; `test/golden/
   golden_drift_test.dart` fails when the committed files differ from a fresh
   export (so CI catches a Dart change that forgot the goldens), and
   `flutter test --dart-define=UPDATE_GOLDEN=true test/golden` regenerates them.
   The Python tests (`backend/tests/test_golden_*.py`, run by `backend/check.sh`)
   replay every entry — thousands of strings, dishes, menus, replies and
   pages — and must reproduce them with no skips. `backend/app/keto/
   vocabulary.json` is a byte copy of the golden `vocabulary.json`, so the
   Dart `constants.dart` stays the one place the keto vocabulary is written.
   The port had to reproduce Dart's quirks rather than Python's (`re.ASCII` for
   Latin `\b`; the `regex` module for `\p{}`; UTF-16 code units for lengths,
   caps and the FNV fingerprint; Dart's `trim`, lowercasing and rounding); the
   list is in the module docstrings and the golden tests. Building the corpus
   found one Dart bug, fixed in the same wave: the 300-unit caps on `why` and
   a question's answer could cut a surrogate pair in half, leaving a lone
   surrogate that is not valid UTF-8 and so could not be sent to or stored by
   the backend (#320). The cut now backs off one unit.
3. **The fallback rule: fall through only when the backend could not answer at
   all (#327, #328, #329, #331).** Wrapped in the same interface the app
   already used, each chain asks the backend first (`di.dart`'s `*For` selectors):
   menus `FallbackMenuAdapter` (§6.1), text classification and scans
   `FallbackMenuClassifier`/`FallbackScannedMenuClassifier` behind their
   routers (§6.2), venue search `FallbackVenueSearchService` (§6.5), menu
   questions `FallbackChatClient`. What falls through, and what is reported:
   - Menus: `backendUnreachable` and `offline`. Every other reason is the
     platform's or the site's own answer, which the device would only hear again.
   - Classifiers and chat: `notConfigured`, `backendUnreachable`, `timeout`,
     `rateLimited`. `offline`, `badResponse`, `noDishesFound`, `consentWithheld`
     and the key reasons are returned as they are.
   - Venue search: `backendUnreachable`, `timeout`, `rateLimited`.
   - If the fallback fails too, the **primary's** failure is reported (it was
     the first and better explanation) — except a primary that only said
     `notConfigured` (no backend URL, or the fallback is the only engine that
     tried), where the fallback's is. A venue search always reports the primary's.
   - A **server-stamped rules result is an answer**, not a failure: when
     Gemini fails on the server, the text routes return the ported heuristic
     stamped `{kind: rules, reason}` (`notConfigured`, `offline`, `timeout`,
     `rateLimited`, `badResponse`) exactly as `RoutingMenuClassifier` would, and
     the device does not ask the model again. Only an empty analysis bucket on
     a route whose sole product is the analysis (`/v1/classify`, `/v1/text-menu`,
     `/v1/scan`) is a 429 that sends the device to its own engine; on
     `/v1/venue-menus` and `/v1/website-menu`, which also fetched a menu, the
     menu is kept and the rules are stamped `rateLimited`.
4. **No rules fallback for a scan, as in D15.** `/v1/scan` has none: the rule
   engine needs text, so a Gemini failure is `/v1/chat`'s status and reason
   (503 `notConfigured`, 502 `offline`/`badResponse`, 504 `timeout`, 429
   `rateLimited`), a reply naming no dish is 422 `noDishesFound`, and every scan
   spends the analysis bucket, since images never reach a cache. The pages are
   forwarded to Gemini and dropped; no log line carries more than their count.
   `scanScreenFailureServerNotConfigured` is the copy for a server with no key.
5. **Consent is still checked first, on the device.** Both routers
   (`RoutingMenuClassifier`, `RoutingScannedMenuClassifier`) run their consent
   and connectivity rules *before* the backend chain, so withheld consent sends
   nothing anywhere. A menu fetch has no router in front of it, so
   `FallbackMenuAdapter.usePrimary` reads the user's AI-analysis consent per
   fetch: the backend's menu routes analyse what they read, and without consent
   the device reads the menu its own way. Venue search is not consent-gated
   (it carries no dish text) but does send a position to the server (§6.5, §11).
6. **The quick score is exempt (#331).** Discovery's rules-only quick score
   (D13, D21) must never cause a server classification for a venue nobody opened.
   `AppDependencies.estimateMenuRepository` is a second `CachedMenuRepository`
   over the **direct** adapters and the **same** Hive cache as the menu
   repository (with no backend URL the two are one object), so a menu the quick
   score read is the menu screen's too and the reverse.
7. **The analysis cache and the analysis bucket (#333).** `analysis_cache` holds
   a complete **language-model** analysis per menu fingerprint, model, schema
   version and options for 7 days (`ANALYSIS_CACHE_TTL_SECONDS`, §6.4); only
   LLM results are written. A separate per-install bucket, 10/minute and
   60/day (`ANALYSIS_RATE_LIMIT_PER_MINUTE`/`_PER_DAY`), is spent **only
   when a Gemini call is about to be made** — never on an analysis-cache hit,
   never for a rules-only result, never for an empty menu, never when the
   server has no key. It is separate from the chat bucket (5/minute, 40/day,
   shared with `POST /v1/menus`), which is why a first open no longer spends
   two units of one bucket. `POST /v1/classify` is capped at 768 KiB
   (`CLASSIFY_MAX_BODY_BYTES`, 413 `payloadTooLarge`) and `/v1/scan` at a body
   sized from `VISION_MAX_IMAGES` × `VISION_MAX_IMAGE_BYTES`, both before any
   parsing.
8. **The D24 upload is skipped when the analysis came with the fetch (#331).**
   `/v1/venue-menus` and `/v1/website-menu` write `stored_menus` themselves when
   they return an analysis (the menu and the analysis without `options`, keyed
   by venue, never by install id; a store failure is logged and swallowed).
   As in D24's client rule, only a model analysis is stored: a rules result
   refreshes the menu but never replaces a stored model analysis.
   `MenuFetched.analysis` tells `MenuController.open` the analysis arrived with
   the fetch, so it uploads nothing unless a model analysis was freshly made
   on the device in the same open. `/v1/classify`, `/v1/text-menu` and `/v1/scan`
   never write the store.
9. **Disclosure follows the route (#330).** `AppDependencies.backendConfigured`
   selects `settingsConsentBodyDirectViaBackend`, `settingsKeyBodyViaBackend`
   and `scanScreenDisclosureDirectViaBackend` on a phone with a backend URL: dish
   text and scan pages go to KetoClub's server first and the user's own key is
   used only if the server cannot be reached.

**What it accepts.**

- **Wolt may throttle datacenter IPs.** The platform fetch now leaves from
  wherever the backend runs, not from the user's phone. The direct adapters stay,
  deliberately, as the fallback, and `FallbackMenuAdapter` falls back on
  `offline` (a connect failure or timeout reaching the platform) for this
  reason. But the server answers any non-2xx from the platform other than a 404
  (a 403 or 429 from a blocked IP, Wolt's 410) as 502 `platformChanged`, which
  does **not** fall through: a Wolt block of the server's address would show the
  user "Wolt changed its menu format" instead of reading the menu from the
  phone. Whether Wolt does this to a server is unobserved.
- **The venue and 10bis goldens are synthetic.** `wolt_venues.json` and
  `tenbis_menu.json` replay synthetic payloads (#38, #44 are still open); the
  Wolt menu golden uses the one real recording. The port is proven equal to
  the Dart mappers on those inputs, not equal to what Wolt or 10bis really send.
- **The server pays for every analysis.** Every platform's classification is
  now the operator's Gemini quota (the trade D12 made for web, extended to
  phones), rationed by the 10/60 bucket and softened by the 7-day cache. A phone
  with a key still has a way out of an empty bucket (its own quota); a web
  build's is the chat route's smaller bucket, then rules.
- **The backend is still unhosted (#109, §17.6).** A build with a backend URL
  works only against a backend someone runs; with an unreachable one every
  call is one failed round trip before the device engine starts (the call is
  the probe, D11), up to the 120 s menu timeout in the worst case.
- **`prompt.py` is byte-coupled to the Dart prompt.** The system prompt is part
  of `/v1/chat`'s completion-cache key, and the model must see what the goldens
  pin. The analysis cache's key omits the prompt text, so a prompt or parser
  change that should retire stored analyses needs a `schemaVersion` bump (and
  D22's cost of losing cached scan pages) or waits out the 7 days.
- **Two copies of the logic in two languages.** Each Dart behaviour change to the
  vocabulary, normaliser, rules, prompt or parser is a Python change too. The
  drift test catches the Dart side forgetting the goldens; the replay catches
  the Python side forgetting the port; nothing catches someone editing both
  to agree on a wrong answer.
- **Known gaps in the port.** Dart's `List.sort` is an unstable quicksort above
  33 elements and Python's is stable, so a dish with more than 33 rule matches
  and two at one offset could order its sentences differently (no corpus dish
  reaches it, `app/keto/rules.py`); the 10bis mapper's category-id fallback for
  a name with no letter or digit uses Dart's `String.hashCode`, which was
  hand-ported and is verified by no golden (`app/platforms/_dart.py`).
- **Unverified end to end.** No backend-served menu, classification, scan or
  website read has run against a live backend with live Wolt and Gemini.
  `flutter drive` could not complete in the build environment, so the two flows
  `backend_classify_flow_test.dart` and `backend_fallback_flow_test.dart` are
  proven under `flutter-tester` only (`CLAUDE.md`, "What is NOT verified yet").
- **The consent copy says the position goes "to Wolt" and is "not stored"**
  on every build; with a backend, the position passes through KetoClub's
  server first (§11, §17.7).

**What it costs.** About 7,400 lines of Python (`backend/app/keto`,
`platforms`, `website`, the services and six routers) and 14 committed golden
documents of about 137,000 lines that must be regenerated on any change to the
Dart logic; a second test suite that replays them; six new client files
(`BackendMenuAdapter`, `FallbackMenuAdapter`, `BackendMenuClassifier`,
`BackendScannedMenuClassifier`, `fallback_classifiers.dart`,
`BackendVenueSearchService`) and a `FallbackChatClient`; six new
architecture-test host-string boundaries; one `AppDependencies` field for the
estimate repository and one for `backendConfigured`; and `MenuFetched.analysis`
now meaning "the backend answered with this" as well as "a website PDF was read".

### D26 — Banto: a profile for every restriction (in progress)

*Stub; the decision grows with the Banto work.* Banto extends the menu
analysis from keto alone to a profile of dietary restrictions. Everything it
adds sits behind one compile-time flag, `--dart-define=BANTO_MODE=true`, read
in exactly one file, `lib/utils/banto_mode.dart` (`BantoMode.enabled`; the
display name `BantoMode.appName` is "Banto" with the flag and "KetoClub"
without). Without the define the app is KetoClub byte for byte. The web build
of Banto is `tool/build_web.sh --banto`, with its own manifest
(`web/manifest.banto.json`) and its own CI build target.

**Convention.** Every gated widget or function takes
`bool bantoMode = BantoMode.enabled` as a parameter (the
`backendBaseUrl(configured)` precedent in `lib/di.dart`), so tests exercise
both branches with no define.

**Contract decisions.**

- **C1:** The restriction profile never leaves the device, not even as ids.
  The model extracts ingredients per dish independently of the profile; the
  rules pass emits concerns for every taxonomy id it finds; the device
  filters by the profile and derives the state. The backend performs the same
  two profile-independent steps.
- **C2:** The extraction prompt section and the `ingredients` schema property
  are added only when `ClassificationOptions.restrictionsRequested` is true
  (flag on and the profile has a non-keto entry); the options snapshot writes
  that key only when true, so a keto-only profile's prompt, schema, snapshot
  and cache key are byte-identical to today's.
- **C3:** No `schemaVersion` bump: new `AnalysedDish` fields are read
  tolerantly (absent → empty), and a Banto profile's stale cache is retired by
  `restrictionsRequested` entering `AnalysisOptionsSnapshot.matches`.

**The restriction taxonomy, the allergen vocabulary and its golden (ALG-01a,
#343).** `lib/models/restriction.dart` names the 20 restrictions a profile can
hold (`RestrictionId`, wire form by name; a test pins the list) and their
`RestrictionKind`. There are no severity levels: a restriction is **strict**
when its kind is `allergen` or `autoimmune` (celiac, the `gluten` id, distinct
from the `wheat` allergy) and **flexible** otherwise (`lactose` is an
intolerance, `vegan`/`vegetarian` lifestyle, `keto` keto); strictness is derived
from the kind, never stored or asked. `lib/utils/allergens/taxonomy.dart`
holds one entry per id with the jurisdictions whose labelling law names it
(file 02) and English/Hebrew names, which follow the menu's language as the
waiter sentences do (§12). Each restriction's triggers — direct, hidden with a
`likely`/`suspected` certainty, guards on a stated side, and Hebrew terms that
take no prefix — live in six group files assembled by
`utils/allergens/vocabulary.dart`; every source cites file 11 or 12. Nothing in
`constants.dart` changes. `AllergenMatcher` compiles them with the keto
engine's own `latinTriggerPattern`, `hebrewTriggerPattern`, normaliser and
guard window (`ClassificationRules.isGuarded`, made public for it) and reports
every restriction it finds, whatever the profile (C1); a dish is read as
`dishRulesText`, so removal options are skipped. A new golden,
`allergens.json`, carries the taxonomy, the compiled vocabulary and the
matcher's hits over `tool/golden/allergen_corpus.dart` and over a fixture
vocabulary that pins the matcher before the groups are filled;
`backend/app/keto/allergens.py` replays it, and its packaged copy is pinned
byte-equal. Nothing consults the matcher yet (ALG-04 will); no keto golden
changed.

**The dietary profile and the flagged "My restrictions" section (ALG-02a,
#344).** `lib/models/dietary_profile.dart` holds the profile: a
`DietaryProfile` of `ProfileEntry`s, one per `RestrictionId`, in the order
added, each with at most five free-text exceptions of at most 60 code points
(trimmed, de-duplicated). It has no severity field, and "does it hold a strict
entry" is the `hasStrictEntry` extension in
`lib/utils/dietary_profile_strictness.dart`, which reads the kind from the
taxonomy, because a model may not import `utils/` and storing the kind on the
entry would copy the taxonomy. `AppSettings.profile` keeps it in
`SettingsStore` (§6.4) under the JSON key `dietaryProfile`, read tolerantly
(absent, not a list, unknown ids and repeats are dropped or read as empty,
never invalidating the record) and **written only when non-empty**, so a
keto-only install's stored settings and `const AppSettings().toJson()` (pinned
by `keto_unchanged_test`) are byte-identical; `AppSettings.toString` prints
only the entry count. `settings_store.dart` is the one allowlisted file in
`no_profile_on_the_wire_test`: storage on the device is where C1 puts the
profile, and the file builds no request. `SettingsController` gains
`addRestriction`, `removeRestriction` and `setExceptions`. With `bantoMode`
on, `SettingsScreen` shows a "My restrictions" section between Appearance and
"Your keto rules": the helper-tool sentence, one row per entry (the name in
the UI language, its kind, a remove button) or an empty state, and "Add
restriction", which opens `RestrictionPickerSheet` (the taxonomy grouped by
kind, strict kinds first, each with the official allergen lists that name it;
keto and added ids left out; the app sheet width). Keto stays the existing
toggles, and nothing reads the profile for classification yet
(`ClassificationOptions` is unchanged; Wave 2 does that).

**The Wave 2 contract (W2-0, #345, #346).** `lib/models/concern.dart` holds
the wire types the allergen engine will fill: `Concern {restrictionId,
source, certainty, tier, matchedText?, waiterQuestion?}` and
`ExtractedIngredient {name, certainty, role}`, over `ConcernSource` (name,
description, option, hidden, model), `Certainty` (stated, likely, suspected:
the vocabulary's `TriggerCertainty` names, which a model may not import, so a
trigger converts by name and a test pins the two equal), `EvidenceTier`
(declared, stated, inferred, suspected, confirmed, denied; ALG-06) and
`ComponentRole` (base, protein, side, sauce, garnish, option, unknown). Each
reads tolerantly: an unknown enum name fails the entry and the list drops it,
except an unknown role, which reads as `unknown` so an ingredient is never
lost over it. `AnalysedDish` gains `ingredients` and `concerns` (absent →
empty, written only when non-empty) and `ClassificationOptions` and
`AnalysisOptionsSnapshot` gain `restrictionsRequested` (the snapshot key
written only when true, part of `matches`); `fromSettings` leaves it false and
nothing produces a concern yet. `backend/app/keto/models.py` mirrors all of
it, omitting the same keys through a `model_serializer`. Per C3 there is no
`schemaVersion` bump, and no golden or keto baseline changed.

**The profile-only chef card (ALG-08a, #350).** With `bantoMode` on and a
non-empty profile, the "My restrictions" section gains a "Show my chef card"
button that pushes `ChefCardScreen`: a full-screen page that mirrors the Waiter
Card's shell (brightness raised through `ScreenBrightness` while open, the
numbered large-type lines and Copy button of `WaiterScriptWidget`, a pinned
Done) and adds a Hebrew/English toggle, starting in the app's language, and
Share as text through `MenuSharer`. `SettingsScreen` takes `screenBrightness`
and `menuSharer` for it; `generateRoute` passes the app's. Its sentences come
from `ChefCardText.compose` (`lib/utils/allergens/chef_card_templates.dart`),
pure and in the language of the card, not the UI's, so like the waiter
templates they live in Dart (§6.3's exception, §12) and only the chrome (title,
button, empty message, toggle accessibility label) is in ARB: an intro line,
one line per entry by kind (an allergen "please check every ingredient,
including sauces, oils and garnishes", celiac its own gluten and cross-contact
sentence, every flexible kind "please tell me which dishes contain it", the
entry's exceptions appended to its line) and a closing line that asks the
kitchen to confirm cross-contact precautions when the profile holds a strict
entry. The card states what the person is and asks; it never says "safe" or
"בטוח" (a table test pins every restriction in both languages), and no
severity exists to vary it. The card needs no menu and sends nothing anywhere
(C1). The per-dish card with a dish's name, modification and questions, and the
cross-contact closing line driven by ALG-07 signals, are ALG-08b.

**Kitchen cross-contact signals, the pure part (ALG-07, #349).**
`KitchenSignals.of(menu)` in `lib/utils/allergens/kitchen_signals.dart`
(twin: `backend/app/keto/kitchen_signals.py`) is a rules-only pass over a
whole menu, never a dish, that reports what the menu reveals about its
kitchen as `KitchenSignal`s in `KitchenSignalKind` order: `fryer`, `wok`,
`sharedGrill`, `bakery`, `nuts`, `sesame`. Each carries the restrictions it
threatens (taxonomy order), up to three dish names as evidence and one
standard question for the staff in both languages. The questions live in Dart
beside the term lists (the §6.3 exception, as the waiter templates do), are
questions and never assurances, and pass the banned-words list. A dish shows
a kind when its own rules text or its category heading does; the term lists
compile as the keto vocabulary does (`latinTriggerPattern`,
`hebrewTriggerPattern`, `isGuarded`), with guards for "stir fried", "pan
fried", "air fried" and "fried rice" (a wok dish, not a fryer one),
"chocolate chips" and plant-based burgers. The nuts, sesame and seafood facts
come from `AllergenMatcher` (any certainty), never from a list of this file.
`sharedGrill` needs a grilled meat dish and a grilled fish dish. The mapping
is a fryer to wheat and gluten plus fish, crustaceans or molluscs when a fried
dish names that seafood, a wok to peanuts, soy, wheat, gluten, crustaceans,
molluscs and sesame, a shared grill to the seafood three, a bakery to milk,
eggs, wheat, gluten and sesame, nuts to peanuts and tree nuts, sesame to
sesame; wheat is added beside gluten wherever flour is the cause, because a
wheat allergy shares the cause with celiac disease. A signal is a menu-level
fact beside the per-dish answer: it changes no verdict, and nothing consults
it yet (the notice, the demotion of green dishes for strict entries and the
keto-only no-op are ALG-07's later part). A new golden, `kitchen_signals.json`,
carries the term lists, guards, threat table and questions and the signals of
every golden menu, the allergen corpus menus and menus built for each rule,
all under a small nuts, sesame and seafood vocabulary of its own
(`tool/golden/kitchen_signals_corpus.dart`) so it does not move when the group
vocabulary files are filled; no other golden changed.

**The Why sheet (ALG-06, #348).** `lib/widgets/why_sheet.dart` is the "why this
result" bottom sheet, built and tested on its own and wired into no screen
yet. `WhySheet` takes a dish name, a list of `Concern` and whether the profile
is strict, and shows one row per concern: the restriction's name in the UI
language, the evidence tier as a phrase (declared by the platform, stated on
the menu, inferred from a typical recipe, suspected (please ask), confirmed by
you, ruled out by you), where it was found, the matched text quoted and the
waiter question. Confidence is words, never a number or a percentage. An empty
list says nothing in the menu text points to the profile, adding "still ask the
restaurant" for a strict profile, and never says the dish is fine; the footer
is `helperToolSentence`. `showWhySheet` opens it through `showKetoClubSheet`
(560 px cap) and, like the widget, does nothing with `bantoMode` off. The
strings are new ARB keys (`why*`), so the banned-words test covers them.

ALG-02b (#344) adds the profile's two other surfaces, both behind `bantoMode`.
`AppSettings.onboardingSeen` (JSON key `restrictionOnboardingSeen`, **written
only when true**, so the keto record stays byte-identical) records that the
first-run "What do you avoid?" screen was completed or skipped.
`RestrictionOnboardingGate` wraps the `/` route: with the flag off it returns
its child at once and builds no controller; with it on it reads the settings
once and shows `RestrictionOnboardingScreen` (the taxonomy as chips grouped by
kind, no severity question, the helper-tool sentence, "Continue" which saves
the picks in tap order, "Skip" which saves none, both marking it seen) only
when it was not seen and the profile is still empty, so a user who added
restrictions in Settings first is never asked. Deep links to a venue skip it.
On the menu screen `MenuFiltersRow` takes an optional `summary` line kept
visible under the disclosure row; with the flag on and a non-empty profile
`ProfileSummaryLine` fills it with "Checking for: sesame, lactose" in the UI
language, naming restrictions only and never calling a menu safe. Tapping it
opens Settings and `MenuController.refreshProfile` re-reads the profile on
return. `MenuController.profile` is read from the device's settings in `open`
and goes nowhere else.

**Ingredient extraction: prompt, schema and parser (ALG-03, #345).**
`ClassificationOptions.fromSettings(settings, {bantoMode})` sets
`restrictionsRequested` when the flag is on and the profile holds an entry
other than keto (`DietaryProfile.hasNonKetoEntry`, a model getter, because a
service may not name the profile's types); the quick score and the Scan tab
build their own options and stay keto-only. Only then does `systemPrompt`
append a last, profile-independent extraction section (each dish's
`ingredients` as `{name, certainty, role}`, hidden sources a standard recipe
implies, honest certainty, the menu's own language, never a new dish; no
restriction is named), `visionSystemPrompt` add a paragraph asking for each
dish's printed `description`, `responseSchema(extract:)` add `ingredients`
last in `required`, and `visionResponseSchema(extract:)` add `ingredients`
and, after `page`, a nullable `description`; with the flag off all four are
byte for byte today's, which `keto_unchanged_test`'s banto layer pins through
`fromSettings` with an empty and a keto-only profile. There is no `concerns`
property: concerns are computed on the device (C1). `MenuResponseParser`
reads `ingredients` only with `extract`: an entry with a non-string, blank or
over-100-unit name or an unknown certainty is dropped, an unknown role reads as
`unknown`, names that normalise alike keep the first, at most 40 are kept, and
an ingredient whose normalised name is not a substring of the dish's
`dishRulesText` (removal options skipped) is kept but capped at `suspected`;
`parseScanned` keeps the description (trimmed, cut at 1000 units), which
enters the scan's fingerprint. A described dish whose extraction came back
empty keeps its keto verdict and an empty list; `extractionMissing` computes
that mark rather than storing it or demoting the dish, so ALG-04's rules pass
is its only source of concerns. The backend clients send
`restrictionsRequested: true` (`restrictionsRequested=true` on the venue
route) only when true; `ClassificationOptionsBody` accepts that strict bool
and still forbids every other key, the services pass it to the same prompt,
schema and parser (`backend/app/keto/prompt.py`, `parser.py`), and the
analysis-cache key gains a `|restrictions` part only when it is true. The
goldens gain a `restrictions` option set in `prompt.json`, the two extracting
schemas and `extractText`/`extractScanned` in `parser.json`, replayed by
Python; no existing entry changed and `schemaVersion` stays 1.


**The matcher's guards lower, sit beside their term, and read the maqaf
(ALG-04a, related to #346).** Three allergen-only rules replace the keto guard
window inside `AllergenMatcher`, and its Python twin follows them. **A guard
lowers, never cancels** (file 11 §0): a guarded trigger ("peanut-free", "oat
milk" beside dairy milk) is still a hit, `suspected` with a new
`AllergenHit.guarded` flag (in equality, `toString` and the golden), because
the app never tells an allergic person something is absent on a heuristic.
**A guard counts only in the slot adjacent to its term**: a `before` phrase
must end on the word just before the match and an `after` phrase start on
the word just after it, so "no sesame or tahini" lowers sesame and leaves
tahini stated; a Hebrew guard's first word may carry one or two prefix
letters before its term ("וללא טחינה") but only the article ה after it ("חלב
השקדים"; "חלב וסויה" is milk *and* soy). `ClassificationRules.isGuarded` and
its two-word window are unchanged and keto's alone. **Per-term guards**,
`RestrictionVocabulary.termGuards` (term as written → `AllergenGuards`,
default empty), add to the restriction's guards for that one term, for the
compounds that name another food: rice flour, coconut/almond/oat/soy milk,
oyster mushroom, crab apple; a compound that names an allergen of its own
stays a stated trigger of it ("almond milk" is tree nuts). **The maqaf
U+05BE reads as a space** before the matcher normalises
(`AllergenMatcher.matchText`, `dishMatchText`), where `TextNormaliser`
deletes it as a Hebrew point and glues "חמאת־בוטנים" into one word; the
normaliser itself is untouched, the replacement is length-preserving, and
offsets index the match text, which equals the normalised text wherever
there is no maqaf; terms and guard phrases are read the same way, so a term
written with a maqaf ("סויה־דבש") still matches. The filled group vocabularies
follow the rules: compound guards moved into `termGuards` (the plant bases on
the dairy words, the flours that are not wheat on `flour`/`קמח`, coffee,
cocoa and jelly on `bean`, apple on `crab`, mushroom on `oyster`), and phrases
the old window reached from two words away are listed whole ("dairy free",
"peanut free" and the like after a term, "no added", "ללא גלוטן", "ללא
מוצרי" before one). `KitchenSignals` counts only unguarded hits: an
"almond-free" dish is no evidence that the kitchen handles nuts.
`allergens.json` gains `termGuards`, each hit's `guarded` and each case's
`matchText`; no keto golden changed.

**Rules concerns and the on-device `ProfileEvaluator` (ALG-04b, related to
#346).** `ClassificationRules.allergenFindings(dish)` runs `AllergenMatcher.find`
over the name, the description and each non-removal option value on its own
(group names are not read; a maqaf-joined removal value is still a removal)
and returns one `Concern` per hit, profile-independent (C1): source `hidden`
for a hidden-list trigger (a new `AllergenHit.hidden` flag, kept out of
`allergens.json` so that golden did not change) and the part's otherwise,
the hit's certainty, tier `stated` for a direct unguarded trigger and
`inferred` for a hidden or guarded one, and `matchedText` the menu's own
slice ("TAHINI", "בַּטְּחִינָה"), recovered by binary search because the match
text of a raw prefix is a prefix of the whole. `allergenConcerns` keeps one per
restriction, the surest and the earliest at a tie, in taxonomy order; the
heuristic classifier attaches it to every dish only when
`restrictionsRequested`, so keto output is byte-identical, and
`backend/app/keto/rules.py`/`heuristic.py` do the same, replayed through a new
golden, `allergen_concerns.json` (the hand-written dishes, six labelled corpus
menus and the three golden menus classified with the flag on). To keep the
import graph acyclic the two trigger patterns moved to
`utils/trigger_patterns.dart`, which `classification_rules.dart` re-exports.
`utils/allergens/profile_evaluator.dart` is device-only: `ProfileEvaluator.evaluate(analysed,
dish, profile)` unions the rule findings (always recomputed from the dish),
the analysis's own concerns and concerns read from its `ingredients` (source
`model`, the weaker of the two certainties, the role carried); keeps the
profile's ids, never keto, dropping a concern whose matched text holds one of
its entry's exceptions as whole words; and derives `DishState`, worst first:
a stated/likely concern on a part that cannot be left off (base, protein,
unknown role, name, description, hidden source), or `nonKeto` with keto in
the profile → `avoid`; a suspected concern on a strict entry → `ask`; a
stated/likely concern only on removable parts (side, sauce, garnish,
option), or `modifiable` with keto in the profile → `fitsWithChange`, with
keto's script and then "Ask for it without X" / "לבקש את המנה בלי X" in the
menu's language (§6.3's exception); else `fits`. A flexible entry's suspected
concern is listed and moves nothing; an empty profile holds keto and is the
identity of today's verdicts; the wire verdict is never rewritten. The state
is computed from every finding, so a removable stated mention cannot mask a
likely one in the name. `MenuController.evaluatedRows` pairs each analysed
visible row with its evaluation for the profile recorded when the menu was
last classified; nothing renders it yet (ALG-05).



**The rules-recall gate over the corpus (ALG-10, closes #352).**
`test/utils/allergens/corpus_recall_test.dart` replays every dish of
`test/fixtures/allergens/menus/` through `ClassificationRules.allergenConcerns`
(no model, no network) and holds one rule per strict restriction (every id
whose `RestrictionKind` is `allergen` or `autoimmune`): a `contains` label
needs a concern of at least `likely` certainty and a `may_contain` label one
of at least `suspected`. A concern on a `free` or unlabelled dish is printed
as a false-positive count and never fails. Its twin,
`backend/tests/test_allergen_corpus_recall.py`, runs the same corpus through
`app.keto.rules.allergen_concerns` and must agree, and both print the same
per-restriction table so the denominator travels with every figure. The
vocabulary does not close every label yet, and the gate is not weakened and no
label is edited to pass it: the misses that remain are listed one by one, with
a reason and the vocabulary addition that would close it, in
`test/fixtures/allergens/known_misses.json`, which both twins read. A miss not
on the list fails the build, and so does a listed entry that no longer misses
(delete it), so the list can only shrink; it is the visible debt, counted in
every run. The labels are still unreviewed desk research, so a recall figure
is a question for the labels as much as for the engine until a clinical
reviewer reads them. The person-run half, `backend/tools/allergen_eval.py`
(like `vision_smoke.py`, #88, imported by no gate), sends each corpus menu
through the extraction request with the backend's own model client and
reports recall per restriction for the model alone, the rules alone and the
merge of the two, splicing the result into `docs/ALLERGEN_EVAL.md`, which
says "not yet run" until a person with a key has run it. Its scoring
functions are pure and unit-tested offline, and a model's ingredient list is
scored through the same matcher the on-device evaluator uses, cut to the
weaker of the two certainties.

The first vocabulary pass over the recall gate (#343, #352) closed 34 of its
35 `contains` misses, leaving the allowlist at 142 entries from 176 and
`contains` recall at 99.9% (825 of 826) from 95.8% (791 of 826); wheat, gluten,
soy, eggs, mustard and legumes reached 100%, sesame 97.6%. `may_contain`
recall did not move (359 of 500, 71.8%), and the gate's false-positive counts
did not move either. Most of it is hidden sources at `likely`: egg rolls, bread
rolls, loaves, wholemeal, crackers, hoagie, Israeli beer brands, `פנה`
(penne, compiled with no prefix letter), the compound `גלייז סויה` (plain
`סויה` stays soy only) and Beyond Meat (soy and legumes), plus `pie`, `hoisin`
(sesame), `tartare` and `vinaigrette` raised from `suspected`. The dish names
khachapuri, focaccia (`פוקאצ׳ה`), biscuits and hoagie join the direct lists,
`stated`, beside their English siblings. A bare `roll` is bread unless a
term guard names another food (sushi, spring, rice paper, lettuce and the
fish of a sushi menu), which lowers it to `suspected`, never drops it. The
one `contains` miss left is the filled Bamba's sesame, a label question.

**The four-state menu screen and the Why sheet on the card (ALG-05, #347).**
`ProfileWording` (`utils/profile_wording.dart`) is `ketoOnly` unless the
screen's `bantoMode` is on and the profile holds a restriction besides keto,
then `strict` with an allergen or celiac entry and `flexible` otherwise.
`MenuController.open` takes `bantoMode` and records it with the profile;
with a wording that uses states, `evaluations` (memoised per menu, analysis
and profile) feed the dish cards, `stateCounts` (`VerdictCounts.ofStates`,
food only, with a new `ask` field defaulting to 0, so keto counts and their
equality and `toString` are unchanged), the filter and the share text,
while the keto counts and score stay on the wire verdicts. `MenuFilter`
gains `askOnly` (a keto screen reads it as `all`); in state mode
`greenOnly`/`yellowOnly`/`redOnly` mean fits/with a change/avoid and
`greenAndYellow` means "everything but avoid", which is the strict
profile's opening filter unless one was last chosen. Every word comes from
`widgets/verdict_copy.dart`: keto-only returns today's ARB strings
verbatim (now also pinned through `keto_unchanged_test`'s `bantoMode`
seams), a strict "fits" reads "No trigger found — ask the restaurant", the
state legend ends on `helperToolSentence`, the header shows "N fit · M
with a change · K to ask" instead of the keto score unless keto is in the
profile, and a test sweeps every state, wording, filter and locale for
"safe"/"בטוח". The share headings and a fallback "Does this dish contain
X?" question follow the menu's language and so live in Dart
(`MenuShareText.stateHeading`, `VerdictCopy.askQuestionFor`; §6.3's
exception); the shared text names no restriction and copies no question.
`StateBadge` pairs an icon and a word per state, ask drawn outlined in a
new orange `VerdictColors.ask` tone (tokens `lightAsk*`/`darkAsk*`, every
text pair pinned by `contrast_test`). In state mode `DishCard` lists one
line per concern (the restriction from the taxonomy in the dish's own
language, where it was found and how sure in words), a "Why?" button that
opens `showWhySheet`, and one waiter row with the evaluator's change or
the question to ask; the net-carb chip and hidden-carb flags stay only
while keto is in the profile, as on the Waiter Card. The tiles become four,
and a "Rules checked" chip sits beside the AI chip when the rules pass
found something for the profile in a model result. `KetoClubApp` and
`generateRoute` take `bantoMode` for the menu and Settings screens, so a
flow test pumps Banto with no define.

**The four-state menu's visual pass and the owner's copy (ALG-05, closes
#347).** Two copy decisions of the owner: a strict profile's Hebrew "fits"
is "ללא חשש" on the tile and in the header ("N ללא חשש · M עם שינוי · K
לשאול"), while the card's pill keeps "לא נמצא חשש — לשאול את המסעדה" and
English is unchanged; and the evaluator's change sentence quotes the menu's
own words, "Ask for it without '{item}'" / "לבקש את המנה בלי '{item}'"
(straight single quotes), where the item is the matched slice
(`ProfileEvaluator.quotedItem`, device-only, so no golden or Python twin
moves) run through the next word when the slice ends in a construct form's
ת ("גבינת שמנת"), at most three words and never past a comma, a full stop,
`|`, a line break or the field's end; an item another item already quotes
as whole words is not asked for twice. The pass rendered the Banto web
build with a sesame + lactose profile against the audit's stubs
(`docs/VISUAL_AUDIT.md`, "Banto four-state menu", which lists every finding)
and fixed five things, all inside state-mode paths: the strict pill and the
"add a note" icon share one row (the keto header `Wrap` dropped the icon to
a line of its own), the "Why?" button, each concern line and the state
waiter row are semantics nodes of their own (merged, they made the whole
card one button that opened the Why sheet), the AI and "Rules checked" chips
scale down rather than overflow at a narrow width and large text, and the
Why sheet lays the dish name and the waiter question out in their own
direction, and the "Why?" button draws the keyboard `FocusRing` of #264. `tool/visual_audit/serve_spa.py` gives the driver the
single-page-app fallback the path URLs of #226 need. The keto build's menu
renders the same before and after.

**Recorded decision: platform and restaurant declarations as evidence
(ALG-09, closes #351).** `Dish.declaredTags` holds the platform's own dietary
labels, raw: Wolt's item `dietary_preferences` (a string as written, a map's
`id` or else `name`) and `kosher` for a 10bis dish with `kosher: true`; it is
read tolerantly and written only when non-empty, so per the `Dish` trap and
C3 there is no `schemaVersion` bump and the Hive cache carries it as is.
`backend/app/keto/models.py` and both Python mappers follow; the only golden
bytes that moved are the input menus holding the synthetic 10bis dish `1003`.
The one recorded Wolt payload has an empty `dietary_preferences` on all 56
items but four items saying "טבעוני" (three with 🌱) in their names
(`test/fixtures/README.md`), so the feature's main path is text: the pure
`utils/allergens/declarations.dart` (twin `app/keto/declarations.py`, golden
`declarations.json`) reads tags, the dish's name and description, and its
category heading (the D21 precedent) through one table of six absence rules
(vegan, vegetarian, gluten-free, dairy-free, lactose-free, egg-free; terms
compiled as the keto vocabulary is, 🌱 and 🌾 matched on the raw text) into
`Declaration {rule, restrictionIds, polarity, source, matchedText}`. A
negation or an offer within two words ("לא", "ניתן לקבל", "לפי בקשה",
"בתוספת", "option", "available", "can be made") makes a phrase no
declaration, since withholding a lowering is the safe direction.
Gluten-free speaks for gluten only, never wheat, and "parve" is not read as
dairy-free. `ProfileEvaluator.evaluate` takes the dish's `heading` (passed by
`MenuController`) and, in one step after the profile filter
(`_applyDeclarations`), lowers every concern about a declared-absent
restriction by one step, once per restriction, to tier `declared`: never
below `suspected` and never removed for a strict entry (file 09), while a
flexible entry's suspected concern is cleared; a declaration with no concern
adds nothing, and `present` (reserved for ALG-16's matrix) changes nothing.
`EvaluatedDish.declarations` keeps the ones applied, and the Why sheet says
"declared by the platform" or "declared by the restaurant" and quotes the
declaration as lowering, never ruling out, the finding. Declarations stay on
the device (C1): neither the server nor the heuristic reads them. With
`bantoMode` and a profile that uses states, a dish whose platform flags it
kosher shows "declared kosher by the platform" beside its price, the only
kosher statement the app makes and never its own.

**Waiter questions, the per-dish chef card and the allergy note (ALG-08b,
closes #350; ALG-15, closes #357).** Every concern an evaluation keeps now
carries a waiter question: `ProfileEvaluator.evaluate` passes its kept
concerns once through `WaiterQuestions.fill` (`utils/allergens/
waiter_questions.dart`), which keeps a question the model wrote and fills
the rest from Dart templates per source and certainty in the dish's language
(§6.3's exception, as the "without" sentence): an option → "Can this be
served without '{item}', so there is no X in it?", stated in the dish →
"Can this be made without X?", a model ingredient → "Is there '{item}' in
this dish, and does it contain X?", a hidden source or a likely or
suspected finding → "The menu says '{item}': does it contain X?", and with
nothing worth quoting (no text, over 40 characters, or the restriction's
own name, as a guarded "ללא שומשום" leaves) the general question. X is
`WaiterQuestions.subject`, the thing avoided (vegan reads "animal
products", vegetarian "meat, poultry or fish"); `VerdictCopy.askQuestionFor`
uses it too. It is device-only, after the profile chose: the wire, the
Python twin and the goldens do not move (C1). The dish card still shows one
question, now the asking concern's own; the Waiter Card shows the change
and every question (`VerdictCopy.waiterCardScript`; an option's question is
dropped when the change already asks for it) and a "Chef card" action that
pushes `ChefCardScreen` for the dish with no brightness of its own (the
Waiter Card under it keeps it raised). The dish card
(`ChefCardText.composeForDish`) reads the introduction, the profile's strict
lines (every line for a profile with none), "The dish I would like:" and the
name as printed, the change, every question, and the cross-contact closing
only when a `KitchenSignals.of(menu)` signal threatens a strict entry, else
thanks; it opens in the menu's language and the toggle re-evaluates the
dish in the other. The menu overflow's "Copy allergy note" (Banto and a
profile with more than keto; every source, scans included) copies
`ChefCardText.allergyNote` in the menu's language
(`MenuShareText.menuIsHebrew`, now public) and a snack bar's Share sends it:
one paragraph of allergens, celiac disease and the flexible entries with a
"check every ingredient … no cross-contact" or "leave them out" closing, no
severity word (the epic's "אלרגיה חמורה" example is dropped per D-b), and
under 280 characters by dropping the flexible sentence, never an allergen.
Translating the card for a menu in neither Hebrew nor English (through the
menu-question path, #214) is deferred: the language test is Hebrew or not,
so such a menu gets English.

**The kitchen notice and the strict-entry demotion (ALG-07, closes #349).**
`KitchenReach.of(menu)` (`utils/allergens/kitchen_reach.dart`, device-only,
memoised per menu as `MenuController.kitchen`) holds the menu's
`KitchenSignals`, the dishes each kind reaches and the menu's language. The
reach is `KitchenSignals.scopeOf`, which reuses the signal term lists and
needs no golden or Python twin: a fryer reaches the fried dishes, a shared
grill the grilled ones and a bakery the bread, pastry and pizza dishes (each
by the dish's rules text or its heading, as `of` reads them), a wok every dish
of a section that holds a wok dish or is headed by one; nuts and sesame reach
no dish. Their only honest reach would be the whole menu, and on an Israeli
menu (tahini everywhere) that made every dish "ask" and "fits" disappear, so
by the coordinator's decision (reversible, pending the owner) they are named
in the notice with their staff question and demote nothing. `KitchenReach.of`
then drops drinks and notices (`dishKindsOf`, D21), which share no fryer or
counter, from the reach and from each signal's evidence, so a placeholder line
("💙") is never shown as a fried dish. `strictThreats(profile)`
keeps the signals that threaten a **strict** entry (an allergen or celiac
disease): cross-contact is a trace, which an intolerance or a diet does not
turn on, so a signal that threatens only flexible entries is not shown at all
(today every threatened id is strict anyway). `applyKitchenSignals`, an
isolated step after `ProfileEvaluator.evaluate` in both
`MenuController.evaluations` and (with `bantoMode`) `evaluatedRows`, turns a
`fits` dish that such a signal reaches into `ask`, adding for each threatened
strict entry it has no concern for a `Concern` with the new
`ConcernSource.kitchen` (made on the device only, so written nowhere unless
one is; `backend/app/keto/models.py`'s `ConcernSource` gains the name),
certainty `suspected`, tier `inferred`, the kind's name as `matchedText` and
the signal's staff question in the dish's language as `waiterQuestion`; the
first kind in `KitchenSignalKind` order speaks when several reach one entry.
A dish with a change, to ask or to avoid is left as it is, flexible entries are
never touched, the wire verdict never moves, and a keto-only profile holds no
strict entry, so nothing changes for it (and `evaluations` is empty for it
anyway). With `bantoMode` on,
`KitchenNotice` (`widgets/kitchen_notice.dart`) sits among the menu screen's
notices: one `AppNotice.info` line, "This kitchen has a fryer and a bakery —
ask about cross-contact" in the UI language, whose "Show questions" action
expands one row per threatening signal (its name, the strict entries it
matters for, the dishes that show it and its question in the menu's language,
`KitchenSignals`' Dart text per §6.3, with a Copy button). The dish card reads
a kitchen concern as "kitchen: a fryer" and the Why sheet as "This kitchen has
a fryer — ask about cross-contact", with no "Matched" line; the new strings
are `kitchen*`, `concernSourceKitchen` and `whySourceKitchen*` ARB keys, swept
for "safe"/"בטוח".

**Group profiles: what fits everyone (ALG-12, #354).** A device holds
several named profiles (`models/named_profile.dart`, at most 8): the user's
own is still `AppSettings.profile` under `dietaryProfile`, now also the
primary `NamedProfile` "me" whose empty name the UI shows as "Me"/"אני",
which is the whole migration; the others are `otherProfiles`
(`groupProfiles`), the user's renamed name `primaryProfileName`
(`profileName`) and the subset a menu is read for `activeProfileIds`
(`activeProfiles`, default `["me"]`). Each new key is written only when it
differs from its default and read tolerantly, so a single-profile record
and a keto record (`keto_unchanged_test`) are byte-identical to before; ids
are `p1`, `p2`, … (the first unused, no clock). C1 holds: profiles and names
stay in `shared_preferences`, `toString`s print counts, sharing is JSON the
user sends themselves (`utils/allergens/profile_transfer.dart`, after a
dialog naming it health data) and an import is saved only after a screen
that says so asks, and only the extraction flag leaves the device: it is
now true when any *active* profile holds a non-keto entry
(`AppSettings.activeHasNonKetoEntry`). Evaluation stays one analysis per
menu: `GroupEvaluator` (`utils/allergens/group_evaluator.dart`) runs
the single-profile pipeline once per active person — `ProfileEvaluator.evaluate`
with the section heading (ALG-09's declarations), then `applyKitchenSignals`
with the menu's `KitchenReach` (ALG-07) for that person's profile — and shows
the strictest state (avoid > ask > fits with a change > fits), every concern
once (the surest) and each waiter line once; `MenuController` words,
filters and counts by the union of the active profiles (an entry keeps only
the exceptions every holder shares, and keto stays when any member holds
it), so a group with an allergen is strict. With more than one active
person each dish card carries a breakdown ("Me: Avoid · Dana: Fits", each
state in its person's own wording, so a strict "fits" still never reads
"fits") and the header adds "N dishes fit everyone" (strict: "N dishes
with no trigger found for anyone"). Settings lists the people under "My
restrictions" (add, rename, edit through the same picker, share, delete;
the owner's own cannot be deleted, and a profile with no entry reads "Keto
only", as it is evaluated); the menu's Filters row shows "Checking for: Me,
Dana" in place of the restriction summary once a second profile exists,
opening a sheet of checkboxes (at least one stays checked) that saves the
choice without re-classifying, and a chef card with one section per checked
person (`GroupChefCardText`: the ALG-08a lines under each name, one
greeting, one closing). `ChefCardScreen` gives the per-dish card (ALG-08b)
precedence over the group card; a dish card opened in a group is built from
the union profile, and one section per person on it is a follow-up. Discovery's quick score is untouched.

The per-dish group card is built (the follow-up above, issues #354 and
#350): with more than one person checked and a dish with its analysis,
`ChefCardScreen` composes `GroupChefCardText.composeForDish` instead of the
union profile's card. One greeting; then "The dish we would like: {name}"
once, so every question below reads after the dish is named; then a section
per person under their name with their own restriction lines (their strict
entries, or all of them when they hold none; keto for an empty profile),
followed by the change and every question that apply to *them* for that
dish; then one closing, the cross-contact request when a
kitchen signal threatens a strict entry of anyone and thanks otherwise. A
person the dish raises nothing for keeps their restriction lines and has no
question under them, so the kitchen knows they are at the table. The
per-person results come from `GroupEvaluator.evaluate`, the same pipeline the
menu screen runs (evaluator with the section heading, then
`applyKitchenSignals`), re-run in the card's language so the language toggle
follows; the sentences' pure composer takes plain parts and imports no
widget. With one person, or none, the dish card is the single-profile one
as before.

**Hidden sources for the `may_contain` misses (#352, #343).** A second
vocabulary pass over the recall gate added hidden triggers, all
`suspected` and each citing the section of file 11 or 12 it comes from, to
close the `may_contain` misses the first pass left: the Asian, baked and
processed-meat carriers of soy; condiments, sushi rice and beer brands for
sulphites; creamy dressings, `tartar`, `coleslaw` and pickled (`כבוש`) for
mustard; egg-bound doughs and wrappers; bread classes and Asian dishes for
sesame; roux and flour sauces, risotto and deep-fried food for wheat and
gluten; curry pastes, `massaman`, `tentsuyu` and paella for fish; the garlic
and stir-fry sauces for molluscs; `חריימה` for molluscs; enriched dough,
canned tuna and the vegan-mayonnaise substitute for milk; chili con carne
for peanuts; `chowder` for celery; and croissants, quiche and rolls for
lupin. `legumes` now carries every hidden source of soy, peanuts and lupin,
not only soy's (`peanutHiddenEn`/`He` and `lupinHiddenEn`/`He` are public
for it, the way the direct lists already were), so a term the soy list
shares with the peanut list lives in the soy restriction's own list to keep
"no term listed twice" true, and `satay` left the legumes direct extras to
arrive as peanut's `likely` hidden source. `may_contain` recall went from
359 of 500 (71.8%) to 484 of 500 (96.8%) and the allowlist from 142 entries
to 17; `contains` recall is unchanged at 825 of 826. The false-positive
counts moved little where it matters: on dishes labelled `free` they went
from 10 to 12 (milk, from `מיונז טבעוני` on two side dishes that list it as
an add-on sauce), and on unlabelled dishes from 87 to 147, most of it lupin, legumes,
soy and sesame on bread, bun and pastry dishes. Not added on purpose: a bare
`פסטה` or `pasta` for eggs (dried pasta is egg-free), `seafood` and
`פירות ים` for fish (they name crustaceans and molluscs, a decision the sea
tests pin), a bare `dressing` for mustard, and a bun or `לחמנייה` for soy
(it would flag every burger). The 17 that remain are the two label
questions (the filled Bamba's sesame, the tofu scramble's egg), the three
shared-fryer dishes, which belong to the kitchen signals (ALG-07), the
secret-sauce wings and the burger whose aioli is only an option to remove,
and six dishes with no word in their text to match.

**Extended restrictions: alpha-gal, FODMAP, histamine, small portions and
the user's own words (ALG-17, closes #359).** `RestrictionId` gains
`alphaGal` (an allergen: strict), `fodmap` and `histamine` (intolerances),
`glp1` ("Small portions (GLP-1)", a lifestyle) and `custom` (the user's own
restriction, kind allergen, so strict: file 10's "an allergy by the user's
word is an allergy"); legumes and mustard were already ids. Their triggers
live in a seventh group file, `utils/allergens/vocab_extended.dart`, sourced
to new desk-research sections (file 11 §21 FODMAP, §22 histamine, §23 GLP-1
eating beside the existing §17 alpha-gal, and file 12 §7 for the Hebrew,
marked as unreviewed background reading), with Hebrew no-prefix traps
(`משום`, `כפול`, `מבקר`, `מעגל`, `מטלה`, `מחזיר`, `בציר`, `מענק`). Alpha-gal's
certainties are honest — a named mammal meat stated, a burger or kebab
likely and lowered beside chicken or turkey, a casing or stock suspected —
and dairy is left to the Milk entry, which a dairy-reactive person adds too
(the picker says so), in place of the epic's "includes dairy" toggle.
FODMAP, histamine and small portions are `headsUpRestrictions`: the matcher
reports their triggers as written (C1), and `ProfileEvaluator` lowers every
such concern to `suspected`, which a flexible entry lists and lets move
nothing, so none of them ever makes a dish "avoid"; the dish card words
them "may be high in it — a heads-up, not a measurement", their waiter
questions ask for less or for a smaller, lighter version ("I go easy on
…"), and the GLP-1 chef-card line names no medicine. The epic's
"protein-forward · small portion" sort tag is a follow-up. The user's own
words are `ProfileEntry.terms` on the `custom` entry (at most 10 of at most
40 code points, de-duplicated ignoring case, written only when present, so
older records are byte-identical and an entry with no words is dropped on
read); the picker's "Add your own" field adds one, and Settings and the
profile editor list one removable row per word. Contrary to the epic, which
sent them to the model, **they never leave the device** (C1, the
coordinator's decision): `custom_terms.dart` compiles them on the device
into a one-restriction vocabulary (English with its plural and singular,
Hebrew through `hebrewTriggerPattern`'s prefixes, "no"/"without"/"-free"/
`ללא`/`בלי` as lowering guards), and the evaluator runs the rule pass and the
model-ingredient pass once more over it, one concern per word
(`ProfileEvaluator.concernKey`), each asking about the word as the user wrote
it; a group's union holds every person's words. The corpus gains five
alpha-gal `contains` labels (5/5 found); `custom` is left out of the recall
gate's strict ids, having no vocabulary to measure. `allergens.json` and
`allergen_concerns.json` gained the new ids' entries and hits only (every
existing case unchanged), the Python twin's id lists follow, and no keto
golden moved.

**ALG-14 backend half (#356).** `POST /v1/confirmations` takes one fact a
kitchen confirmed, `{venue: {source, platform_id}, dishFingerprint,
restrictionId, polarity: present|absent}`, and counts it in the new
`dish_confirmations` table beside `stored_menus`, keyed by the same venue key,
the dish fingerprint, the restriction id and the polarity: a distinct count, a
raw submission count and a first and last UTC **date** (days, not timestamps,
so a row cannot be lined up with a request log by the second). It follows the
D24 rule and C1: no install id column, no note column, nothing profile-shaped.
`installId`/`install_id`, `note`/`notes`, any profile key and any unknown
field are a 422 that spends no quota; the fingerprint is an opaque token of
`A-Za-z0-9._:-` up to 64 characters, so prose cannot ride in it, and the
restriction id must be in the shipped taxonomy (`custom` excluded: its meaning
is the user's words). The install id is read for the rate limit (a bucket of
its own, `CONFIRMATION_RATE_LIMIT_*`) and for **distinct counting without
storing it**: the route turns it into `HMAC-SHA256(pepper, install id | venue |
dish | restriction | polarity)`, deletes it, and the service stores only that
token in `confirmation_voters`, a one-column table with no timestamp or key to
the counts. Because the token covers the fact, one install has an unrelated
token for every fact, so tokens cannot be grouped by install, and a repeat of
a fact finds its token and counts only as a submission. `GET /v1/venue-menus`
gains an optional `confirmations` list `[{dishFingerprint, restrictionId,
present, absent, first, last}]`, a polarity listed only when its own row has
three distinct confirmations (the other reads 0 until it too has three), and
the key is absent when there is nothing to list, so no existing response moves.
Honest limits: a confirmation names one restriction id about one dish, so a
server that logged request order could infer that some install cares about it;
none is logged, and the profile as a whole (the set, the severity, the
people) never travels. A single person with many installs can still reach
three; the per-install limit and the threshold raise the cost, not remove it.
The Dart `ConfirmationClient` (`lib/services/community/confirmation_client.dart`)
is the one file naming `/v1/confirmations`; `no_profile_on_the_wire_test.dart`
allows `restrictionId` there alone, with the reason. Nothing consumes it yet.

**Trip mode (ALG-13, related to #355).** `TripDestination`
(`lib/models/trip_destination.dart`: Israel, the US, the UK, France, Italy,
Spain, Germany, Japan, each with its `Jurisdiction`) is stored beside the
profile as `AppSettings.tripDestination` under the key `tripDestination`,
**written only while a trip is on** and read tolerantly (an unknown value is
no trip), so `const AppSettings().toJson()` is unchanged; `toString` says
only whether a trip is on, and `tripJurisdiction` is derived. Like the
profile it never leaves the device (C1): nothing on the wire, in a prompt,
in the options snapshot or in a golden changes. The taxonomy gains
`jurisdictionListScope`, which tells a list that binds restaurants (the EU,
the UK) from one that binds packaged food only (Israel's 2028 rule, Japan)
and from the US (packaged food; large Californian chains under SB 68);
`TripRegulation.hintFor` reads it with `Restriction.jurisdictions` into one
`RegulationHint` per strict entry and none for a flexible one, so both home
markets read "ask every time" and even a restaurant duty ends on "still ask
the restaurant". `utils/allergens/trip_lexicon.dart` holds a short sourced
lexicon per destination (romanised or Latin-script terms, Hebrew for
Israel; glosses in both languages; fish and mammal-meat entries also hide
vegetarian and vegan, milk and eggs vegan, milk lactose), whose
country-specific facts are file 12 §8, **unreviewed desk research to check in
a browser before its wording ships** (checked in part on 2026-10-19; see the
fact-check paragraph at the end of this decision). While a trip is on and the screen is
Banto, `MenuController` passes it to `ProfileEvaluator.evaluate` (and through
`GroupEvaluator.evaluate` and the dish chef card), whose one hook,
`TripLexicon.withTrip`, adds the destination's terms to the pass that already
reads the user's own words: every term a `suspected` hidden source, so a
strict entry's dish becomes "ask" and a flexible one only lists it; keto, the
classification options and the classifier calls are untouched, and turning
the trip off re-evaluates on `refreshProfile` without re-classifying.
Settings gains a "Trip mode" section (`settings_trip_section.dart`: pick a
destination, change it, turn it off in one tap) and `TripBriefingScreen`
lists the hints, the profile's lexicon entries and the chef card. The card is
composed on the device from the stored profile, so it opens with no
connection (a `flutter-tester` flow proves it); the epic's card **in the local
language** (French, Italian, Spanish, German, Japanese) is not built, so the
card stays Hebrew or English and nothing is pre-generated by a model.

**Restaurant allergen matrices, the first slice, and the "no rating" rule
(ALG-16, related to #358).** A matrix is a restaurant's own table of what
each dish contains, may contain or is free of: rows are dishes by printed
name (plus up to five aliases), columns the EU 14 by taxonomy id (sesame is
one of them; "cereals containing gluten" is `gluten`, never `wheat`), cells
`contains`, `may_contain`, `free` or blank, with `source` (`restaurant`,
`printed`, `website`), `enteredBy` and `validFrom`/`validUntil`; the JSON and
CSV forms are in `backend/README.md`. The backend keeps it in a new table,
`allergen_matrices`, beside D24's `stored_menus` and keyed the same way, by
venue (`source`, `platform_id`) plus `valid_from`, with no install-id column,
and returns the one that holds today (UTC, the latest `validFrom` wins) on
`GET /v1/venue-menus` as an optional `allergenMatrix` key that is omitted
when there is none, so no golden and no existing answer moved; `enteredBy`
never leaves the server and nothing near the read touches the install id.
Intake is manual for now: the maintainer's `backend/tools/allergen_matrix.py`
(`template`, `import` of a `.json` or a `.csv` with flags, `list`, `remove`)
validates a whole document before writing and refuses two rows whose names
normalise alike. There is no write route and no account. With `bantoMode`,
`BackendMenuAdapter` reads the key tolerantly (`models/allergen_matrix.dart`:
absent or unreadable is none, an unknown cell is dropped) onto
`MenuFetched.allergenMatrix`; the menu cache keeps it beside the menu (written
only when present, so other entries are byte-identical) and a fresh answer
replaces it. **Matching is on the device only** (`utils/allergens/
allergen_matrix.dart`, no Python twin, no golden): a row speaks for a dish
when one of its names normalises exactly (`TextNormaliser.normalise`, the
key §9.4 dedups names by) to the dish's name; §9.4 rule 3's shared-word test
is how the parser rejects inventions and is far too loose to say whose
allergens a dish has. A row naming no dish, or only a dish another row also
names, is listed in `AllergenMatrixMatch.unmatched` and applied to nothing:
never guessed. A matched row's `contains` cell is a stated concern and its
`may_contain` a suspected one, both the new device-only
`ConcernSource.matrix` at tier `declared` on a part that cannot be left off
(so avoid, and ask for a strict entry), and its `free` cells are one absent
`Declaration` (the new `DeclarationSource.allergenMatrix`, the row's name as
the matched text) that `ProfileEvaluator.evaluate`'s one new parameter,
`matrix`, hands to ALG-09's `_applyDeclarations`: one step lower, never below
`suspected` and never removed for a strict entry, and every EU 14 column is
strict. `MenuController` applies the matrix only while it holds on the
menu's `fetchedAt` day, to single and group evaluations alike. The menu
screen's `AllergenMatrixNotice` says "Allergen information from the
restaurant, dated 1 Oct 2026" and lists the unmatched rows as printed; the
dish card reads "restaurant's allergen information" and the Why sheet
"Declared in the restaurant's allergen information". **The "no rating"
rule:** a matrix, and anything a restaurant later supplies or pays for, is
evidence about dishes and a dated fact about where it came from, never a
badge, a rank, a score or a rating of the venue; no restaurant can buy a
rating, a placement or a better state, and no copy for it says "verified"
or "safe" (file 07's B2B rule). Out of this slice: reading a photographed
printed matrix through the vision path, user-submitted matrix photos held
as `suspected` and the restaurant-facing upload page. (The per-dish chef
card's re-evaluation, left out of this slice, now takes the matrix: see
"The Banto leftovers" below.)

**Close-out of ALG-03, ALG-04, ALG-06 and ALG-11, and the GLP-1 tag (#345,
#346, #348, #353, #359).** Option B and its reasons are now in §9.6 and the
allergen pass in §6.2. Three fixes: `MenuController` builds its options with
the screen's own `bantoMode`, not the compile-time default, and the Scan tab
builds them through `ClassificationOptions.fromSettings` with its own
(`ScanController.bantoMode`), so a Banto scan asks for ingredients and
printed descriptions and its stored analysis is the one the menu screen
reuses instead of re-reading the scan as text (this replaces "the Scan tab
stays keto-only" above). ALG-11: `whatLeavesDeviceBanto` now also names the
request for ingredients and the user's own words, and is shown in the
Explore banner and both privacy texts in Settings; `AppSettings` gains
`disclosureCopyVersion` (`disclosureCopyVersion`, written only when above 0)
and `helperToolSeen` (`helperToolSeen`, written only when true), so a keto
record is byte-identical. A Banto build shows the banner while the stored
version is below `bantoDisclosureCopyVersion` (1) and records it on either
button; the first restriction added in Settings opens `HelperToolSheet`
("A helper, not a guarantee" and the helper-tool sentence) once, and the
onboarding, which carries the sentence, marks it seen when it saves a pick.
ALG-06: the Why sheet takes a `WhyCoverage` (`WhyCoverage.of(dish,
analysed)`): what the menu gave (name, description, options) and who read
it — "AI listed its ingredients, and the rules read the menu text too", or
"Only the rules read the menu text, with no AI ingredient list. Ask the
restaurant.", which is ALG-04's stricter rules-only wording on the sheet.
ALG-17's follow-up: `Glp1Tags.of(dish, analysed, heading:)`
(`utils/allergens/glp1_tag.dart`, device-only, no golden or Python twin)
tags a dish "Protein-forward" when the model's extraction holds a protein at
stated or likely and no base the keto rules flag (where no model listed
ingredients, when the dish's name names a protein and the keto rules do not
find it built on a starch), and "Small portion" when its name, description
or heading says starter, small, half portion or kids' and neither its name
nor description says large; the dish card shows it as one neutral outlined
chip only for a profile holding `glp1`, never as a colour, a state, an order
or a number. The sort the epic names is not built. Amendments recorded here
against the epic: the evaluator and the merge are device-only (C1), so there
is no Python evaluator and no profile in `options`; an empty extraction keeps
the dish's keto verdict rather than failing it; and the flow test of
"שמנת" in a description reads it as avoid, since a description is not a
part to leave off (only an option is).

**Premium gating and the paywall (ALG-18, closes #360).** The owner chose a
full paywall. `services/platform/entitlement.dart` is the seam: an
`Entitlement` with `sellsPremium`, `isPremium`, a `changes` stream,
`refresh()`, `purchase()`, `restore()` and the store's own
`localizedPrice()`, every call a sealed `EntitlementResult`
(`PremiumActive`, `PremiumInactive`, `PurchaseCancelled`,
`PurchasePending`, `EntitlementFailed(reason)`) and never a throw.
`NullEntitlement` sells nothing and gates nothing: it is the web build's
(free; its quota stays the backend's rate limit), KetoClub's and every
test's default. `StoreEntitlement` (`store_entitlement.dart`, the one file
`import_rules_test` lets import `in_app_purchase`) sells one monthly
product, `banto_premium_monthly`, through StoreKit 2 and Play Billing; the
plugin is reached on first use only, so `di.dart`'s `entitlementFor` (store
on a Banto phone, null otherwise) does no plugin I/O. There is no receipt
server and no account, and the backend learns nothing: a refresh is the
plugin's restore, which on both stores reads only what is active now
(StoreKit 2's current entitlements, Play's owned purchases, neither
prompting a sign-in), so a lapsed subscription simply reads as inactive.
`state/premium_controller.dart` is app-lifetime, provided above every
route, and reads the store once per session, the first time a gate or the
paywall needs it, never at start-up. The decisions are pure,
`utils/premium_gates.dart`: only a Banto build that sells Premium without it
is limited, to `freeRestrictionCount` (1, keto never counted) and
`freeScansPerMonth` (5: file 07 says "up to X", so the issue's default
holds until the owner picks one); the four gates are adding a second
restriction (Settings, a person's editor, the onboarding chips), adding or
importing a person and checking a new person into a menu's group, picking
a trip destination, and a scan (photos, PDF or pasted text) past the
month's count. `screens/premium_gate.dart`'s `passPremiumGate` opens
`PaywallScreen` when one trips, never failing silently, and the action goes
ahead once Premium is active. **Only adding is gated**: a person whose
Premium lapsed keeps every saved restriction, person, active group and
trip, each still evaluated on every menu and removable, and the chef cards,
the helper copy, confirmations, waiter questions, the Why sheet and the
trip briefing never mention Premium (`premium_gate_usage_test` pins the
callers and those files; a flow walks a lapsed user through all of them).
The month's count is `AppSettings.scanMonth`/`scanCount` (UTC `YYYY-MM`,
key `monthlyScans`, written only while it counts a scan and only by a
Banto `ScanController`, after a read that produced a menu), so
`const AppSettings().toJson()` is unchanged. The paywall's price line is
always the store's string, never a figure in the app; its copy (ARB keys
`premiumTitle`, `paywall*`, `settingsPremium*`, `scanFreeScansLeft`) says
what Premium adds and that nothing already in a profile is ever locked,
and never "safe". No real purchase has been made: no device, no store
account and no store product exist yet.

**Fact-check, 2026-10-19 (#355, #342).** The research behind the trip
hints and lexicons was checked against web search results (no page could
be opened in full from this environment; each claim's URL and date sit in
file 12 §8.1 and the "checked 2026-10-19" lines of files 02, 06, 11 and
12). Confirmed, so `jurisdictionListScope` and every `RegulationHint` are
unchanged: California's SB 68 was signed on 13 October 2025 and took
effect on 1 July 2026 for chains of 20 or more locations (the nine
allergens each item holds as an ingredient, in writing, on the menu or
digitally — no cross-contact duty, so file 06's "misdemeanour for not
disclosing cross-contact" was corrected); Japan's labelling rules leave
restaurants out; the EU's Article 44 and the UK's 2014 regulations make
restaurants give allergen information (the FSA's 2025 written-information
advice is guidance, not law); and Israel's rule is mandatory for
prepacked food from 1 January 2028, with non-prepacked food deferred (a
2032 date seen once, unconfirmed). Corrected in the data: Japan's
mandatory list gained cashew on 1 April 2026 (doc comments only — tree
nuts were already tagged), and gluten is now tagged for Australia / New
Zealand, whose PEAL rules declare it, which changes the `allergens.json`
golden and its backend copy by one tag and nothing a user sees (neither is
a trip destination, and the picker shows only US and EU tags). In
`trip_lexicon.dart` five glosses were softened, none strengthened and no
term or hidden restriction removed: dashi is "usually" bonito or dried
sardine (kelp-only dashi exists), "standard" soy sauce holds wheat and goes
into "many" sauces, "some" falafel batters hold sesame, Senf is served
with sausages rather than "on every sausage", and Bamba's soy is named
(Osem lists it; export packs print "may contain"). Still unreviewed and
marked so: the Spain, Italy and UK lexicon rows, most French, German and
Japanese rows, SIGHI's per-food ratings, the GLP-1 advisory's own food
advice, and every Hebrew spelling in file 12 §7.

**Amendment: a flexible entry's firm rules finding moves its state (#346;
the owner's decision, 2026-10-19).** The epic's ALG-04 says that "for a
flexible entry the model's verdict stands and the rules concern is shown as
evidence only". That sentence was written for option A, in which the model
gives a verdict per restriction and the rules could defer to it. Option B
(§9.6), which shipped, has no per-restriction model verdict to defer to: the
model only extracts ingredients, and `ProfileEvaluator` derives every state
from the union of concerns. So the rule is now: for **every** entry, strict
or flexible, a `stated` or `likely` concern moves the dish's state, to
`avoid` on a part that cannot be left off and to `fitsWithChange` on a
removable one, whether the rules or the model's extraction found it; only a
**`suspected`** concern of a flexible entry moves nothing (it is listed, and
the Why sheet explains it), while a strict entry's suspected concern still
turns the dish to `ask`. This is what `ProfileEvaluator` has done since
ALG-04b; the amendment records it as a decision rather than an accident,
and the epic's ALG-04 text is corrected to match. The keto verdict on the
wire is still the model's and is never rewritten.

**The Banto leftovers (related to #350, #352, #356, #358; ALG-15).** Four
small pieces close gaps the slices above left. *The per-dish chef card
evaluates like the menu:* `MenuController.matrixEvidenceFor(dishId)` and
`confirmationsFor(dishId)` hand the dish's `MatrixEvidence` and
`Confirmations.forDish` to `ChefCardScreen` (`matrix:`, `confirmations:`),
which passes them, with the dish's section heading, to
`ProfileEvaluator.evaluate` for one profile and to `GroupEvaluator.evaluate`
for a group, so a matrix `contains` cell or a staff answer asks the same
question on the card as on the menu. *A dish-level allergy note (ALG-15):*
`ChefCardText.dishAllergyNote(profile, dishName:, concerns:, hebrew:)`
reuses `allergyNote`'s profile sentences (now one private `_NoteParts`) and
adds "For {dish}: please make it without '{the menu's words}'" for each
stated or likely concern and "please check whether it contains {subject}"
for each suspected one (`WaiterQuestions.subject`), closing for a strict
profile with "make sure nothing touches {its strict restrictions} in
preparation"; it stays within `allergyNoteMaxLength` by dropping, in order,
the flexible sentence, that list (for "no cross-contact in preparation") and
the dish's name, and never an allergen, an item or a question. The per-dish
chef card shows it, in the card's language, with Copy and Share; the menu's
overflow keeps the profile-level note. No severity word ("Severe sesame
allergy" in the epic's example is not used: there are no severity levels).
*The change answer on reopen (D27 §4's "recorded but not yet shown"):*
`MenuController.open` reads `VisitEntry.changeConfirmations` with the
concern answers, and `changeConfirmationFor(dishId)` returns the latest
day's; with `bantoMode` the dish card dates it under its concern lines ("The
staff changed it as you asked, May 12", "הצוות שינה את המנה כפי שביקשת, 12
במאי", or that they did not) and the Why sheet adds a line saying the change
was for that visit. It enters no evaluation, so it never alters a state.
*Recall:* the vocabulary closed ten of the seventeen known misses (soy for
sesame noodles and a sweet wing glaze, wheat and gluten for crisp coatings,
mustard for a pickled option and a sweet glaze, legumes through soy,
sulphites for named sushi rolls, milk for grilled beef skewers, eggs for a
salad spread), every term `suspected` and cited to file 11 or 12, with no
change to either false-positive count; `may_contain` recall rose from 484
to 494 of 500. Seven remain: the two label questions, the three shared-fryer
dishes, the cream-sauce pasta (no source says it is fresh pasta, and dried
pasta is egg-free) and the seafood cream dish for fish (`פירות ים` names
crustaceans and molluscs, a decision the sea tests pin).
*Kosher and halal (related to #342):* the first two entries of
`RestrictionKind.religiousComponent` (flexible), ids `kosher` and `halal`
after `glp1`, **components only, never certification** (file 03; file 10's
non-goals). `vocab_religious.dart` flags pork, shellfish (the sea group's
crustacean and mollusc lists, split into public pieces in their old order,
so every existing golden entry is byte-identical), fish without fins and
scales, rabbit, blood and gelatin for kosher, and pork, alcohol (every term
hidden and likely; "שרי" left out as the cherry tomato), blood and gelatin
for halal, each term cited to file 11 §24–§25 or file 12 §9. Kosher's meat
with dairy is a rule, not a word: `ClassificationRules.allergenFindings`
(and its Python twin in `rules.py`) appends one kosher concern when a dish
names an unguarded meat or poultry word (`meatWithDairyMeatVocabulary`,
alpha-gal's mammal lists spread, exported as `meatWithDairy` in
`allergens.json`) and an unguarded stated or likely Milk word that do not
overlap — stated when both are stated in the dish, suspected otherwise or
when one side is only an option; fish never counts. Declarations gain
`DeclarationRule.tagsOnly`: a platform's `kosher` or `halal` tag lowers that
restriction alone, and menu text ("kosher salt") declares nothing. Waiter
questions name the component ("Can this be made without pork?", "The menu
says 'wine': does it contain alcohol?"; meat with dairy asks about the dairy
or, from an option, whether one can be left off), never the word; the chef
card adds "I keep kosher …" / "I eat halal …" and a certificate question on
its own line; and a profile holding either uses the strict wording, so a
dish with nothing found reads "No trigger found — ask the restaurant", never
"Fits". The only kosher statement stays ALG-09's attributed chip, which
`test/l10n/religious_words_test.dart` pins. No `schemaVersion` bump (C3):
the concerns are computed, never stored.

**The research restrictions: ids first, words later (related to #342).**
Every restriction the allergen documentation names that the taxonomy did
not model gets an id, inserted before `keto` (ids are stored by name, so
nothing moves): *strict allergens* `buckwheat` (Japan's mandatory list,
tagged `jp` alone); `kiwi`, `peach`, `apple`, `banana`, `orange`, `beef`,
`pork`, `chicken`, `gelatin` and `yam` (yamaimo, not sweet potato), from
Japan's *recommended* list and untagged, since `jp` means the mandatory
list (`japanRecommendedOnly`); `corn`, `sunflower` and `flax` (file 02,
"Less common allergens"); and `chickpea`, `lentil`, `pea` and `fenugreek`,
each its own toggle under `legumes` (`restrictionParent`, file 11 §16.5).
`fava`, for G6PD deficiency, gets a new strict kind,
`RestrictionKind.medical` ("Health condition"): favism is haemolysis, not
an allergy, and the allergy sentences ("I have an allergy to …") would
misstate it; Israel's fava marking is not an allergen list, so it carries
no `il` tag. *Heads-up sensitivities* (kind `intolerance`, in
`headsUpRestrictions`, so a finding is only ever `suspected` and moves
nothing): `nightshades`, `msg`, `caffeine`, `salicylates` and
`oralAllergy` (file 03, "The map"; file 02), the last asking whether an
item is raw and can be served cooked. *Diets*: `pescatarian`, `paleo`,
`whole30` and `aip` (`lifestyle`) and `jain` (`religiousComponent`, so it
sits under kosher's and halal's "Religious diet" heading and, since
`hasReligiousEntry` reads the kind, takes their strict wording). Each
has its names, picker hint, waiter subject and chef card line in both
languages. Their vocabularies are five new group files, **empty** in this
step (`vocab_foods_extra`, `vocab_seeds_extra`, `vocab_legume_parts`,
`vocab_sensitivities`, `vocab_diets_extra`), so no menu verdict and no
golden concern changes; and `restrictionOffered` keeps a restriction out
of the picker and the onboarding until its vocabulary holds a term, since
a strict entry that can find nothing would read every dish as free of it.
Each follow-up fills one file, with sources and corpus labels, and its ids
appear. The picker gains a search over both languages' names, a "Health
condition" heading, and single legumes indented under legumes; soba in
the Japan trip lexicon now hides `buckwheat`. Left out on purpose: the
medical diets that need nutrient numbers a menu does not carry (kidney,
PKU, gout, diabetes, pregnancy, GERD, IBD, EoE; file 10, file 03), and
kosher or halal *certification*, which no app can verify (file 03; their
components are a separate pull request). Chestnut is no id: it stays a
tree-nut question for that vocabulary (file 11 §2.5).

### D27 — Post-meal confirmations, no ratings

*(Banto, the Allergens epic's ALG-14, issue #356. Amends D23's visit
history; builds on D26's evidence tiers. The device half is recorded
here; the shared half, `POST /v1/confirmations`, the `dish_confirmations`
table and `ConfirmationClient`, is D26's last paragraph, "ALG-14 backend
half".)*

**What changed.** The evidence tiers `confirmed` and `denied` (ALG-06) had
no source: nothing on the device knew what a kitchen had said. After a
meal a person can now say, per dish and per concern, what the staff told
them, and the next time the menu opens the dish shows it. Six decisions:

1. **The prompt lives on the Recent tab, never in a notification.** With
   `bantoMode` on, `MenuController.open` records `VisitEntry.openedStrict`
   (written only when true, and never cleared by a later open) when the
   menu was read under a strict wording (an allergen or celiac disease in
   the profile). Such a Recent row, while its cached copy is on the
   device, offers "Did you ask the staff?", which opens
   `ConfirmationSheet` (`widgets/confirmation_sheet.dart`) over a
   `ConfirmationController` (`state/confirmation_controller.dart`). It
   lists every analysed dish the active profiles have a concern about,
   with the concern exactly as the menu finds it before any answer, and
   per concern asks "Did you ask about *sesame* in *סלט חצילים*?" —
   *confirmed present · confirmed absent · didn't ask* — plus "they
   changed the dish as requested — yes / no" for a dish that carried a
   change, and a note that is the dish's ordinary `NotesStore` note. No
   local-notification plugin was added: the epic's "a few hours later"
   notification is left out.
2. **The answers are kept with the visit history (D23), on the device.**
   `VisitEntry.confirmations` holds `DishConfirmation {dishId,
   restrictionId, polarity (present | absent), day, source?,
   matchedText?}` and `VisitEntry.changeConfirmations` holds
   `ChangeConfirmation {dishId, honoured, day}`
   (`models/dish_confirmation.dart`), keyed by the venue (the entry), the
   dish id the notes already pair with the venue, the restriction, the
   polarity and the calendar day — never the time. "Didn't ask" is recorded
   as nothing. Both lists are read tolerantly (not a list → empty; a
   malformed answer or a repeat is dropped) and written only when
   non-empty, so a keto build's history entries are byte for byte as
   before; there is no `schemaVersion` bump (C3). Today's answers reopen in
   the prompt and can be corrected; an earlier day's are history and are
   never rewritten. `VisitHistoryStore.setConfirmations` replaces them and
   never creates an entry; `recordVisit` and `rename` keep them; Settings'
   Clear and removing the Recent row delete them with the entry. An entry
   keeps at most 200 of each, the oldest days dropped first. The store
   names `DishConfirmation`, never a restriction token, so
   `no_profile_on_the_wire_test` needed no allowance: like everything in
   the history, the answers leave the device through nothing (C1).
3. **One rule, in one helper, called once from the evaluator.**
   `utils/allergens/confirmations.dart` (device-only, pure, no golden and
   no Python twin) holds `ConfirmationEvidence` and `Confirmations.apply`,
   which `ProfileEvaluator.evaluate` calls once, after the declarations
   step (ALG-09), with the dish's evidence (`Confirmations.forDish`,
   passed by `MenuController` and through `GroupEvaluator.evaluate` to
   every person, since an answer is a fact about the dish). **Confirmed
   present** raises every concern about that restriction to `stated` at
   tier `confirmed` (a heads-up restriction's certainty stays suspected,
   ALG-17), and re-adds the concern where it had been found when a later
   analysis no longer finds it. **Confirmed absent** moves it to tier
   `denied` at `suspected` — **never lower, and never removed, for any
   entry**: a strict entry's dish therefore still reads "ask" (file 09: a
   kitchen's answer holds for one visit, and the app never tells an
   allergic person something is absent), and a flexible entry's suspected
   concern is listed and moves nothing, so the Why sheet can still say
   what the staff said. The person's latest answer decides, present at a
   tie. `EvaluatedDish.confirmations` keeps the pieces that decided
   something, and `GroupEvaluator.combine` unions them.
4. **The date is shown, in words.** The dish card's concern line reads
   "you confirmed it with the staff, May 12" or "the staff said it is not
   there, May 12 — still ask" in place of the certainty words, and the Why
   sheet adds "You confirmed with the staff on May 12" or "On May 12 the
   staff told you it is not in the dish. That holds for that visit only,
   so ask again each time" (Hebrew: "אישרת עם הצוות ב־12 במאי"); the date
   is an ARB `DateTime` placeholder in the UI's locale. Neither says
   "safe" or "בטוח". The change answer is shown too, dated, on the dish
   card and the Why sheet, and moves nothing (D26, "The Banto
   leftovers").
5. **Ready for shared counts, with no network code.** `ConfirmationEvidence`
   carries `shared` and `count`, so the same rule can read counts other
   people shared: a shared piece counts only from
   `sharedConfirmationThreshold` (3) people, a shared denial lowers one
   step rather than straight to suspected, a shared present outranks a
   shared absent, and the person's own answer always outranks any shared
   count. For the shared store, `DishConfirmation.dishKey` is
   `dishFingerprint(dishId)`, eight hex digits of 32-bit FNV-1a (the D23
   hash), which matches the backend's `[A-Za-z0-9._:-]{1,64}`, and
   `isShareable` is false for the user's own words (`custom`, ALG-17): they
   are recorded and shown locally and are never uploaded. Nothing on the
   device calls `ConfirmationClient` or reads `/v1/venue-menus`'
   `confirmations` yet: the opt-in upload with its own consent, and turning
   those counts into `ConfirmationEvidence(shared: true)`, are the wiring
   left for a later change.
6. **No rating, ever.** An answer is a fact about one dish, one
   restriction and one day. Nothing on the device, and nothing the shared
   half adds, sums a venue into a number, a star or a score: that is the
   whole difference from AllergyEats and Spokin (file 10, Non-goals), and
   the keto score of §6 is untouched by any answer.

**What it accepts.** A dish id that a platform reassigns orphans its
answers (they apply to nothing, as a note does); a scan's ids are stable
because its ref is its content (D23). A confirmed present with no
recorded source (only possible for a shared piece) is not re-added. The
prompt asks about the profile as it is now, not as it was at the visit.

**What it costs.** One more interface method on `VisitHistoryStore` and
one optional `recordVisit` parameter, threaded through four
implementations; one more optional parameter on the evaluator and the
group evaluator; one more list on `EvaluatedDish`.

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
- **The golden parity corpus (D25):** `tool/golden` builds 14 JSON documents by
  running the real Dart code (vocabulary, normaliser, fingerprint, rules,
  heuristic, prompt, parser, text menu, website locator, the platform mappers,
  dish kind, score); `test/golden/golden_drift_test.dart` fails when the
  committed copies in `backend/tests/fixtures/golden/` differ from a fresh
  export, and `flutter test --dart-define=UPDATE_GOLDEN=true test/golden`
  regenerates them. The Python replay is `backend/tests/test_golden_*.py`,
  part of `backend/check.sh`. After regenerating, copy the new
  `vocabulary.json` to `backend/app/keto/vocabulary.json` (a test pins them
  byte-equal).
- **The backend chains (D25):** `BackendMenuAdapter`, `BackendMenuClassifier`,
  `BackendScannedMenuClassifier` and `BackendVenueSearchService` over a fake
  `http.Client` (request shape, headers, every status and body-`reason`
  mapping, the options-and-schema check on a returned analysis); the three
  Fallback wrappers over scripted engines (which reasons fall through, which
  failure is reported); `di_test` for the selectors (`menuAdaptersFor`,
  `llmClassifierFor`, `scannedClassifierFor`, `venueSearchFor`,
  `chatClientFor`) and for the estimate repository sharing the cache; and
  `MenuController` for the skipped upload. The Python routes are respx-mocked
  tests (`test_classify_route.py`, `test_venue_menus_route.py`,
  `test_scan_route.py`, `test_website_menu_route.py`, `test_venues_route.py`,
  `test_text_menu_route.py`, `test_analysis_cache.py`).
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
  the backend (a build with no backend URL; D25 added the backend-configured
  cases below), and with no key saved see the `apiKeyMissing` copy, follow it to
  Settings and save a key (`direct_gemini_analysis_flow_test.dart`); with a
  backend URL on a phone, a Discovery card opens a menu that arrived already
  classified, in one request, with nothing uploaded to the shared store
  (`backend_classify_flow_test.dart`); and with that backend unreachable, the
  menu is read from Wolt and classified on the device, by rules with the
  server-unreachable banner when no key is saved and by Gemini directly when
  one is (`backend_fallback_flow_test.dart`). Both D25 flows are proven under
  `flutter-tester` only: `flutter drive` could not complete in the build
  environment.
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

**Phase 8 steps (UI polish and the desktop web layout).** Steps 18 to 25 are
done on the `phase-8` branch (PR #266); each issue in the GitHub milestone
"Phase 8: UI Polish & Desktop Web" is one feature branch; D20 (§14) is the
record of the decisions and `docs/UX_REVIEW.md` the review they came from.

18. ✅ **Width and shell** (#221, #224, #226, #248, #261, #263, #242) —
    `ContentWidth`, `showKetoClubSheet`, the web splash/manifest/path URLs/tab
    titles, `FilledButton` only with themed fields (architecture test), the
    bundled Hebrew face, the legend's engine line, whole-shekel prices.
19. ✅ **Discovery** (#222, #227, #228, #229, #230, #231, #232, #233) —
    `VenueGrid`, the "Closed" tag, the pre-location invitation, the link icon
    instead of a standing button, distance, multi-select chips, the logo mark,
    an app-lifetime `VenueSearchController`.
20. ✅ **Menu** (#234, #235, #236, #237, #238, #239, #240, #241, #243, #244,
    #245) — `MenuFiltersRow`, no budget notice for rules, banner not chip,
    venue name in the bar once scrolled, overflow actions, one waiter action,
    note row only with a note, score bands, one name per verdict, unclassified
    cards with retry, a flexible source line.
21. ✅ **Waiter Card, Scan, Recent** (#246, #247, #249, #250, #251, #252, #253,
    #254) — Done bar and inline "Copied", three Scan modes, no camera button on
    web, reorder and preview pages, "Recent" with score, counts, expiry and
    Keep, red remove icon.
22. ✅ **Settings and Drinks** (#255, #256, #257, #258, #259) — reorder with a
    collapsed AI & privacy group, segmented Language/Appearance, the drinks
    guide on Explore, an About group over `AppInfo`, verdict-toned drink
    sections and a shared `NetCarbsChip`.
23. ✅ **Cross-cutting** (#260, #262, #264) — `AppNotice`, Back to Explore via
    `PopScope`, `FocusRing` and desktop autofocus.
24. ✅ **Navigation rail** (#223) — `NavigationRail` at 840px and wider.
25. ✅ **Two-pane menu** (#225) — header, tiles, Filters row and chips beside
    the scrolling dish list at 1080px and wider.

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
   this open safe — every build works with no backend configured at all. Since
   D24 the shared menu store lives in that same backend, so until this is
   answered the store is shared only by the builds pointed at one developer's
   `localhost`. Since D25 the same is true of every complete-result route: a
   phone with a backend URL reaches them only if someone runs a backend it can
   address, and otherwise falls back, after one failed round trip, to the
   device engines.
7. **Does the consent copy still describe where a position goes?** Settings and
   the first-launch banner say a position "is sent to Wolt only when you search
   nearby, and is not stored". With a backend URL (web since D11, phones since
   D25) it goes to KetoClub's server first, which forwards it to Wolt and
   keeps a four-decimal coordinate in the key of a response it caches for five
   minutes (`DISCOVERY_CACHE_TTL_SECONDS`), never beside an install id. Default: leave
   the wording as it is until the backend is hosted for anyone but its owner,
   then reword the venue-search sentence in all three consent strings.

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
- **A keto-only profile is today's app, byte for byte.**
  `test/architecture/keto_unchanged_test.dart` pins its prompt, schemas,
  cache-key material, rules verdicts, score, verdict copy and share text
  against hand-edited files in `test/fixtures/keto_baseline/`. It has no
  update switch: an intended keto change edits a fixture by hand, in review.

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
