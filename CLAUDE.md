# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**KetoClub** is a restaurant menu analysis platform designed to help keto dieters find safe dining options. The app ingests live menus from restaurant delivery platforms, classifies dishes by keto-compatibility, and generates automatic waiter instructions for modifications.

> **Status: Phase 1 and Phase 2 are built and merged, Phase 3 backend
> foundations and hosted classification have landed underneath both, and
> Phase 4 ("Menu Scanning") has its core built.**
> Build-order steps 1–7 of `architecture.md` §16 (models and service
> contracts, the bilingual heuristic engine, Wolt ingestion with a Hive
> cache, the classified menu screen and Waiter Card, the LLM client with its
> router and Settings, and a local FastAPI backend (`backend/`, D11) that
> proxies Wolt for the web build and forwards one chat completion per menu to
> Google Gemini, D12) shipped first. Steps 8–10 landed on top in Phase 2's
> run: the 10bis adapter (`TenBisAdapter`, registered in `di.dart` — 10bis
> links resolve and fetch end to end, not just parse), location and nearby
> search (`LocationService` over `geolocator`, `WoltVenueSearchService`, and
> a real Discovery screen at `venue_search_screen.dart` with a location
> header, search, filter chips and venue cards — `architecture.md` D13), and
> platform setup (icons, splash, bundle ids, permissions). The same run also
> built a real Saved tab, dish/venue photos, and several Settings features
> (appearance, net-carb limit, dietary rule toggles, saved-menus management)
> that build-order steps 8–10 do not individually name. `BackendChatClient`
> replaced `OpenRouterClient` for the web build. Since D17 (issue #194) iOS and
> Android call Wolt and Gemini themselves: `GeminiChatClient` calls Google
> directly with a key the user pastes into Settings, kept by `ApiKeyStore` over
> `flutter_secure_storage`, and the backend serves the web build only. Three earlier decisions were reversed in the Phase 1 close-out pass
> (`architecture.md`): D10 reinstates `Connectivity`, §17.4 now renders
> `net_carbs_estimate` as a labelled chip, and §6.6's collapsed red-dish group
> is gone — the verdict counter tiles are the filter now. Phase 4's core has
> shipped on top: a menu no platform serves can come from text pasted into the
> Scan tab (`TextMenuSource`, D18), or from photographs or a PDF that Gemini
> reads and classifies in one request (D15 — image parts on `/v1/chat` and on
> both chat clients, `VisionMenuClassifier` behind `RoutingScannedMenuClassifier`,
> the Scan tab's photo/gallery/PDF pickers). There is no on-device OCR. A
> restaurant's own website is a menu source too (#181, D19): paste any
> restaurant URL and its menu page, JSON-LD or PDF is found and classified.
> A table's QR code is a menu source too (#182): the Scan tab's "Scan QR code"
> action (phones, not web) reads it with the camera and routes a Wolt, 10bis,
> website or PDF link to that menu. No real Gemini request carrying images
> has been sent yet (#88).
> **Phase 8 ("UI Polish & Desktop Web", issues #221–#264, `docs/UX_REVIEW.md`)
> shipped on top of all of that, on the `phase-8` branch (PR #266):** every
> screen body sits in a `ContentWidth` cap (680px; Discovery 1080px), Discovery
> is a 1/2/3-column venue grid with a card surface, a `NavigationRail` replaces
> the bottom bar at 840px and wider, modal sheets are capped at 560px, the menu
> screen goes two-pane at 1080px, the web shell has a splash, cream manifest
> colours, path URLs and per-route tab titles, and Noto Sans Hebrew is bundled.
> Per screen: the menu puts header, tiles, chips and dishes first with search,
> budget and legend in a collapsible Filters row, names the venue in the app
> bar once scrolled, keeps Share in an overflow, shows one waiter action per
> yellow dish and unclassified dishes as cards; Explore shows a "Closed" tag,
> distance, multi-select filter chips, a drinks-guide card and keeps its search
> across tabs; "Saved" is now "Recent" with score, counts, an expiry countdown
> and a Keep pin; Scan has three modes and reorderable pages; Settings opens on
> Language and Appearance (segmented), collapses the AI disclosure and ends
> with an About group. Cross-cutting: `FilledButton` only, themed field
> borders, one `AppNotice` banner vocabulary, one name per verdict, the keto
> score toned by band, focus rings, and browser Back that returns to Explore.
>
> **Read `architecture.md` first — it is authoritative.** This file and `README.md`
> predate the code in places; where any of them disagrees with `architecture.md`,
> architecture.md wins. **`HANDOFF.md` is the fastest way in**: what exists, what is
> deliberately unfinished, and the traps that already cost time.

## Architecture & Core Components

### Client + optional local backend

Single Flutter codebase for web, iOS, and Android, plus a small optional FastAPI
backend (`backend/`, D11) that is an accelerator, never a dependency — with no
`KETOCLUB_BACKEND_URL` define, the app behaves exactly as it would with none:
- **Classification Engine**: **a hosted language model is the primary classifier, with
  an on-device rule engine as the fallback** (`architecture.md` D2). The model is
  Google Gemini. **On iOS and Android the app calls it directly** with the user's
  own API key, pasted into Settings (D17); **on web it goes through KetoClub's own
  backend**, which holds the Gemini key server-side, so the browser never holds
  one (D12). When there is no key (phone) or no backend (web), no consent, or no
  network, the rule engine answers and the UI labels the result "rules". Both sit behind one `MenuClassifier` interface
  and a router picks per call. A `Connectivity` pre-check (`architecture.md` D10,
  reinstated in the Phase 1 close-out pass, extended to the backend call by D11)
  asks the device whether it looks online before ever spending a model request;
  it is a hint, never a verdict, so a failed call still reports `offline` exactly
  as it did before this check existed. D11's "the call is the probe" applies to
  the backend itself too: nothing pre-checks whether the server is up, so an
  unreachable backend surfaces as `backendUnreachable` from the failing call. On
  a phone there is no server in between: a failed call to Google is `offline`.
- **API Integration**: Direct calls to restaurant platform APIs from the client on
  iOS/Android, which never call the backend even when `KETOCLUB_BACKEND_URL` is
  set (D17); the web build routes Wolt and 10bis through the backend's proxy
  routes when configured (D11), because neither platform's API sends CORS
  headers. **Wolt and 10bis are implemented**; Tabit and Ontopo are not built.
  The backend also proxies Wolt's discovery ("nearby"/"by name") endpoints for
  the web build (`architecture.md` §16 step 9, D13).
- **Local Storage**: Hive caches the normalised menu and its analysis for 24 hours;
  `shared_preferences` holds non-secret settings and, since D12, an anonymous
  install id (`InstallIdStore`) the web build sends to the backend only for rate
  limiting. On iOS and Android, `flutter_secure_storage` (reinstated by D17)
  holds the user's Gemini key through `ApiKeyStore`; web has no key store.
- **No client-side database**: menu analysis happens on the user's device; the
  backend, when configured, keeps only a short-lived Wolt-proxy cache and a
  shared completion cache keyed by request hash (D12, issue #103), never a
  per-user record.

### Menu Ingestion & API Integration

KetoClub integrates with four restaurant platform APIs:

| Platform | Auth | Data Format | Primary Use |
|----------|------|-------------|------------|
| **Wolt** | None (slug-based) | Standardized JSON (items, categories, options) | Primary delivery aggregator |
| **10bis** | None (restaurant ID) | Hierarchical JSON (categories → dishes) | Israeli corporate delivery |
| **Tabit** | Session token via QR | POS-level JSON (modifiers, kitchen groups) | Restaurant dine-in QR ordering |
| **Ontopo** | Anonymous bearer token | PDF/S3-hosted links (OCR-capable) | Reservation platform with menu links |

Key fetch patterns:
- **Wolt**: `GET https://consumer-api.wolt.com/consumer-api/consumer-assortment/v1/venues/slug/{venue_slug}/assortment`
  with the web-client header set (`lib/utils/wolt_headers.dart`; issue #168). The older
  `restaurant-api.wolt.com/v4/venues/slug/{slug}/menu/data` answers every anonymous
  caller with `200` and an empty body and is no longer called
- **10bis**: `GET https://www.10bis.co.il/api/v1.0/Restaurants/{restaurantId}/Menu`
- **Tabit**: `GET https://tgp-api.tabit.cloud/menu/v2/{site_id}`
- **Ontopo**: `POST /api/loginAnonymously` → `GET /api/venue/{venue_id}` with bearer token

All APIs return unstructured dish names/descriptions that feed into the classification engine.

### Keto Classification Engine

Every dish is evaluated against regex-based heuristics and classified:

- **🟢 GREEN**: Net carbs ≤6g, healthy fat/protein, no starchy sides/sauces → Order as-is
- **🟡 YELLOW**: Salvageable core (protein/salad) but includes carb sides/sauces → Order with modifications
- **🔴 RED**: Fundamentally high-carb (pasta, pizza, risotto, etc.) → Filtered from display

**Carb triggers** (partial list from README's `CARB_MODIFIERS`):
- Starch: puree, mashed potatoes, fries, chips, rice, corn, beets, sweet potato
- Sugary sauces: teriyaki, honey, BBQ

**Non-keto bases** that auto-fail:
- pasta, spaghetti, pizza, calzone, risotto, noodles, ramen, brioche, sandwich, pancake, waffle

The pastry counter also auto-fails: danish, pastry, muffin, scone, and Hebrew
מאפה/שמרים/דניש (issue #190), since a plain bakery-counter dish has no other
trigger to catch it.

Classification generates automatic waiter scripts for Yellow dishes (e.g., "Replace potato purée with green salad or steamed vegetables").

### Database Schema

Three core entities:

**Venues** (restaurants)
- `id`, `name`, `address`, `latitude`, `longitude`
- `keto_rating_score`: Community-derived score
- `is_verified_keto_friendly`: Flag for venues offering deliberate keto options (cloud bread, cauliflower rice, tallow)

**Menus** (per-venue, per-platform)
- `id`, `venue_id`, `last_scraped_at`, `data_source` (enum: wolt, 10bis, tabit, ontopo)
- Cache expiration tracking for stale menu detection

**Dishes** (menu items)
- `id`, `menu_id`, `name`, `description`, `price`, `status` (GREEN/YELLOW/RED)
- `waiter_script`: Auto-generated modification instructions
- `net_carbs_estimate`: An LLM-only estimate (the rule engine never sets it) shown
  in the UI as a labelled "estimate" chip, never a bare number — see
  `architecture.md` §17.4, reversed in this pass from "never rendered"

Future additions: user ratings and a review feedback loop. A scanned or pasted
menu is stored under `MenuSource.scan` (D18) and is otherwise an ordinary `Menu`
(no venue, no prices).

## Development Workflow

### Current status

Phase 1 and Phase 2 are built and merged, Phase 3 backend foundations and
hosted classification have landed underneath both, and Phase 4's menu-scanning
core is built (see the banner at the top). The repository holds a working Flutter app, an optional local FastAPI
backend (`backend/`), plus the planning documents all three were built from.

### Actual project structure

```
lib/
├── main.dart                  # runApp(KetoClubApp(dependencies: buildDependencies()))
├── di.dart                    # composition root: the ONLY file constructing concrete services
├── app.dart                   # MaterialApp, localisation delegates, generateRoute
├── l10n/                      # app_en.arb, app_he.arb + committed generated/ output
├── models/                    # venue, menu, analysis, failures, scanned_menu (the pages of
│                              # one scan, in memory only) — plain immutable Dart
├── utils/                     # constants (the keto vocabulary), text_normaliser,
│                              # classification_rules, price_format, keto_score,
│                              # wolt_headers (the web-client header set, #168)
├── services/
│   ├── platform/              # clock, app_logger, connectivity (D10), screen_brightness,
│   │                          # page_picker (interface + a null picker) and
│   │                          # device_page_picker (camera, gallery and PDF over
│   │                          # image_picker and file_picker, #82) and qr_scanner
│   │                          # (interface + a null scanner, #182)
│   ├── storage/               # install_id_store, menu_cache, settings_store, notes_store,
│   │                          # api_key_store (the user's Gemini key, phones only, D17)
│   ├── llm/                   # llm_chat_client, backend_chat_client (web, D12),
│   │                          # gemini_chat_client (phones, direct to Google, D17)
│   ├── location/              # location_service, geolocator_location_service (issue #37)
│   ├── venue/                 # venue_ref_resolver (paste-a-URL, pure), qr_payload_router
│   │                          # (a scanned QR payload → venue / unsupported / photograph, pure, #182),
│   │                          # venue_search_service
│   │                          # (interface), wolt/ (WoltVenueSearchService + mapper, issue #39)
│   ├── menu/                  # platform_menu_adapter, menu_repository, wolt/ and tenbis/
│   │                          # (each split HTTP-adapter + pure mapper, proxyBase, D11),
│   │                          # text/ (TextMenuSource: pasted text to a Menu, pure, D18) and
│   │                          # website/ (a restaurant's own site: locator, fetchers, D19)
│   └── classifier/            # menu_classifier, heuristic, llm, router, prompt, parser, and
│                              # the scan path's siblings: scanned_menu_classifier (interface),
│                              # vision_menu_classifier, scanned_classifier_router (D15)
├── theme/                     # app_tokens, verdict_colors, app_typography, app_theme
├── state/                     # app_dependencies, locale_controller + one ChangeNotifier per
│                              # screen, including venue_search_controller and saved_controller,
│                              # scan_controller and scanned_pages_registry (the in-memory
│                              # page thumbnails behind "View pages")
├── widgets/                   # dish_card, status_badge, engine_chip, waiter_script,
│                              # verdict_counter_tiles, keto_score_badge, app_shell, failure_copy,
│                              # venue_card, category_chips, photo_tile, offline_banner,
│                              # fetch_failure_action, analysis_progress_row, menu_search_field,
│                              # note_editor_sheet, rules_reason_banner, scanned_pages_sheet,
│                              # scan_failure_copy, mobile_qr_scanner (the QR camera page and
│                              # its QrScanner, the one file over mobile_scanner, #182)
└── screens/                   # venue_search (the Discovery screen, D13), menu,
                               # waiter_card_sheet, settings (a Gemini key section on
                               # phones only, D17), saved (a real
                               # cached-menus tab, issue #48) and scan (real now: photograph
                               # pages, pick images, pick a PDF, or paste; #82, #83)

test/                          # mirrors lib/, plus architecture/, fakes/, fixtures/, l10n/
integration_test/flows/        # flow tests + flow_support.dart (same-directory helper)
tool/                          # check.sh (the gate), coverage_gate.sh, gen_coverage_helper.sh,
                                # record_wolt_fixture.sh (issue #22)

backend/                       # optional local FastAPI service (D11, D12) — see backend/README.md
├── app/                       # main.py, config.py, routers/ (health, proxy, chat, website), services/
├── tools/                     # vision_smoke.py: the person-run image smoke check (#88)
├── tests/                     # respx-mocked; no real network call
└── check.sh                   # mirrors tool/check.sh; its own required CI job
```

`architecture.md` §5 carries the same `lib/` tree with the layer-rank rules the
architecture test enforces.

### Setup and the gate

See `docs/RUNNING.md` for the full run guide (the app, the backend, the
`--dart-define`, builds and troubleshooting); the essentials:

```bash
flutter pub get
tool/check.sh          # format, analyze --fatal-infos --fatal-warnings, tests, 80% coverage gate
flutter run -d chrome  # web; live menu fetching needs the backend running, see architecture.md §13
flutter run -d <device>
```

For live Wolt menus (and AI analysis) on the web build, run the backend first
(`backend/README.md` has the full setup and a manual end-to-end check):

```bash
cd backend && cp .env.example .env   # set GEMINI_API_KEY
uv sync
uv run uvicorn app.main:app --reload --port 8000
```

```bash
flutter run -d chrome --dart-define=KETOCLUB_BACKEND_URL=http://localhost:8000
```

With no backend running and no define set, the app still works exactly as the
fully client-only version did (D11): iOS/Android fetch Wolt directly, and every
platform falls back to the on-device rule engine for classification.

**Flutter 3.47.4 / Dart 3.13.3**, pinned in `.github/workflows/ci.yml` and
`pubspec.yaml`; bump both in one commit. `tool/check.sh` runs exactly what the
`quality` and `test` CI jobs run — run it before pushing.

An **info-level lint fails the build** (`--fatal-infos`), including the 80-column
limit and `public_member_api_docs`, in `test/` and `integration_test/` too.

### Traps that already cost time

The long form is in `HANDOFF.md`; these are the ones that bite while writing code.

- **Dart's `\b` is ASCII-only.** `RegExp(r'\bפסטה\b')` matches nothing, so a Hebrew
  vocabulary built that way is silently dead while English tests pass. Hebrew triggers
  use unicode lookarounds: permissive left (grammatical particles), strict right.
- **`material.dart` exports its own `MenuController`** in this SDK. Import it with
  `hide MenuController` when you also need ours from `state/`.
- **`services/` may import neither `dart:io`** (breaks `flutter build web`) **nor
  `package:flutter/services.dart`** (breaks the architecture test). So no
  `SocketException` — use `ClientException` — and no `PlatformException` by name.
- **No constructor reached from `di.dart` may perform plugin I/O.** Pass a closure
  invoked on first use, as the Hive and preferences wiring does; `di_test` asserts it.
- **A `ListView` builds lazily**, so widgets below the fold are absent from the element
  tree and `find.text` finds nothing. Scroll first, or use a `Column` for short screens.
- **A web flow test's imports must be same-directory or `package:`** — `flutter drive`
  roots the compile at the test file's own directory. Only `flutter drive` catches a
  violation; `flutter test` and `flutter build web --target=…` both pass regardless.
- **Serialise test runs when several agents share a worktree:**
  `flock /tmp/ketoclub.lock -c 'flutter test …'`.

## Implementation notes — how it actually works

The section this replaces described a heuristic-first design that predates the code.
`architecture.md` §6 and §9 are the real reference; this is the short version.

1. **Two classifiers behind one interface.** `MenuClassifier.classify(menu)` is one
   call per menu, never one per dish — the backend's per-install rate limit is
   5/minute, 40/day on web (D6, D12), and a phone spends its user's own quota.
   `RoutingMenuClassifier` chooses: consent withheld means the heuristic stamped
   `consentWithheld`; offline means the heuristic stamped `offline`; otherwise the
   LLM path via `GeminiChatClient` on a phone or `BackendChatClient` on web (D17),
   falling back to the heuristic on `offline`, `timeout`, `rateLimited`,
   `badResponse`, `backendUnreachable`, `notConfigured`, `apiKeyMissing` and
   `apiKeyRejected` with that reason carried through so the UI can say why.
   `apiKeyMissing` (no key saved; nothing sent) and `apiKeyRejected` (Google
   refused it) exist only on phones and point the user to Settings; a web
   server-side key problem still reads as `notConfigured`. A **sibling interface,
   `ScannedMenuClassifier`**, serves the Scan tab's photographs and PDFs (D15):
   `VisionMenuClassifier` sends all pages plus one prompt in a single request and
   `RoutingScannedMenuClassifier` applies consent and connectivity, but there is
   **no rules fallback** — the rule engine needs text a photo does not have — and
   the page bytes live only in memory (`ScannedPagesRegistry`), never in the Hive
   cache. Pasted text needs no sibling: it becomes an ordinary `Menu` through
   `TextMenuSource` (D18).
2. **The model's reply is untrusted input.** `MenuResponseParser` is static, pure and
   never throws, and implements §9.4's eight rules: a dish the menu does not contain
   is an invention and is never given a verdict; a yellow whose instruction is
   missing or blank is demoted rather than promoted; dishes the model skipped are
   listed by name, so "could not place it" never looks like "did not see it".
3. **The waiter script *is* `AnalysedDish.modification`** — there is no separate
   generator. It is written in the **menu's** language, detected from the dish text,
   not the UI locale (§12): it gets read aloud to a waiter in that restaurant. That
   is why the heuristic's templates live bilingually in `constants.dart` rather than
   in ARB, a documented exception to "no user-facing literal in Dart".
4. **Adapters are split in two.** `wolt_adapter.dart` does HTTP; `wolt_menu_mapper.dart`
   is a pure JSON→`Menu` function tested against a fixture with no HTTP at all. A URL
   change touches one file, a schema change the other.
5. **Option text is part of what the classifier reads.** A dish's yellow-ness often
   lives in "choice of side", not the description. Refined by issues #191/#192:
   a non-keto base is matched only against the dish's own name and description,
   never its options, and an option value that names a removal ("No onions") is
   dropped rather than read as an ingredient.
6. **Everything at a service boundary returns a sealed result**, never throws, and
   every failure reason is distinct. Collapsing two reasons into one message is the
   bug §10 names; `failure_copy.dart` has a test asserting no two reasons share
   copy in either language.
7. **`di.dart` is the only file that constructs a concrete service**, and nothing it
   calls performs plugin I/O — see the traps above.
8. **The key belongs to whoever calls Gemini (D12, D17).** On web the key lives
   only in the backend's `GEMINI_API_KEY` environment variable, and
   `BackendChatClient` sends an install id, never a key, and never an
   `Authorization` header. On iOS and Android the user's own key lives in the
   Keychain/Keystore via `ApiKeyStore`; `GeminiChatClient` reads it per call and
   sends it only as `x-goog-api-key` to Google — never in a URL, a log, a
   failure value, the cache or the widget tree, and Settings shows only whether
   one is saved. The architecture test pins `googleapis.com` to
   `gemini_chat_client.dart` alone and asserts `openrouter` and `sk-or-` appear
   nowhere under `lib/`.

## Planning & Research Documents

**Core Documentation:**
- `architecture.md`: The authoritative architecture (a client app with an optional
  local backend, D11; a hosted Gemini classifier reached only through that backend
  with an on-device heuristic fallback, D2/D12; adapters, storage, failure
  handling, decisions log). Read this before the README where they disagree
- `README.md`: Full project narrative, API endpoints, database schema, keto classification rules, Phase roadmap
- Engineering standards (SOLID, acyclic imports, clean code, tests, CI) are `architecture.md` §18. Run `tool/check.sh` before pushing; it runs exactly what CI runs.

- `backend_plan.md`: The Python (FastAPI) backend's design — why (CORS on web),
  the API contract, the client seams, and issues #94–#109 in priority order.
  `backend/` now serves `GET /v1/health`, the Wolt menu proxy (#95) and
  `POST /v1/chat` against Google Gemini (#100); the Flutter app talks to it when
  `KETOCLUB_BACKEND_URL` is configured (#96, #102) and behaves exactly as
  client-only otherwise. `architecture.md` D11 and D12 (§14) are the authoritative
  record of what shipped; `backend_plan.md` is design history and its status
  banner may lag behind them.

**Research & Analysis:**
- `m16_menu_scanner_research.md`: Computer vision and OCR strategy for physical menu scanning
  (Phase 4). Its on-device OCR conclusion was **not** adopted: D15 has Gemini read the
  pages itself, so read it for the menu-photo failure modes, not the architecture
- `m15_meal_entry_research.md`: User flow design for meal logging and macro tracking
- `m15_openrouter_models_fix.md` / `m16_structured_output_fix.md`: LLM model evaluation and structured output schemas (if integrating AI for edge cases)
- `menu_api_research`: Platform API comparison and reverse-engineering notes
- `feature_prioratization`: Phase breakdown and feature prioritization

**Conventions:**
When reading research docs (m15/m16), note that prefixes indicate iteration/milestone markers—not all research conclusions are adopted, so verify against the `feature_prioratization` document and README roadmap before implementing.

## Project Phases

- **Phase 1**: menu ingestion, classification and waiter scripts → **Built and merged**
- **Phase 2**: geolocation and nearby search, plus the 10bis adapter → **Built.**
  `TenBisAdapter` is registered in `di.dart` (#134); `LocationService` (#37),
  the Wolt venue-search proxy (#123, #149) and `WoltVenueSearchService` (#39,
  #150) back a real Discovery screen (#40, #154; `architecture.md` D13). What's
  left is recordings, not code: the discovery and 10bis fixtures are still
  synthetic (#38, #44) and the performance numbers (#65) need a real phone —
  see "What is NOT verified yet". See `MILESTONE_CONVENTIONS.md` for the real
  GitHub milestone names — they differ from earlier drafts of this document.
- **Phase 3**: the backend (`backend_plan.md`) → **Foundations and hosted
  classification landed** (D11, D12: the Wolt CORS proxy and Gemini-backed
  chat). Community database, user reviews, restaurant submissions and hosting
  beyond `localhost` → **Planned**
- **Phase 4**: Menu Scanning (one GitHub milestone, "Phase 4: Menu Scanning") →
  **Core built.** Paste-a-menu (#83, D18), image parts on `/v1/chat` and both chat
  clients (#170, D15), the `ScannedMenuClassifier` seam with `VisionMenuClassifier`
  and `RoutingScannedMenuClassifier` (#89), and the Scan tab's photo, image and PDF
  pickers alongside paste (#82), flow tests for the scan paths (#84), and website
  menus (#181, D19), and table QR codes (#182). Still open in the milestone: #88
  (the person-run Gemini vision smoke test, `backend/tools/vision_smoke.py`).
  On-device OCR was dropped (D15; #81 closed as not planned). Configurable dietary
  rules are not Phase 4 work: they shipped earlier under Phase 2 (#56, #143).

- **Phase 8**: UI Polish & Desktop Web (one GitHub milestone, issues #221–#264,
  from `docs/UX_REVIEW.md`) → **Built on the `phase-8` branch, PR #266.** The
  desktop web layout (content-width cap, venue grid, navigation rail, sheet
  width, two-pane menu, web shell) and the per-screen polish listed in the
  status banner above. Phases 5–7 exist on GitHub as milestones; see
  `MILESTONE_CONVENTIONS.md`.

Phase 1 and Phase 2 are built; `feature_prioratization` has the tier breakdown
for what Phase 3's remaining milestone (#105–#108) and Phase 4's open issues pick
up next.

## What is NOT built yet

- Tabit and Ontopo adapters. Wolt and 10bis ship; `MenuRepository` has an
  adapter registered for each (`di.dart`). The `PlatformMenuAdapter`
  interface and its shared contract suite already exist, so a new platform is
  a new adapter plus a registration in `di.dart`.
- Menu scanning's sources are all built: paste, photographs, gallery images, a
  PDF, a restaurant's own website (#181, `architecture.md` D19) and a table's
  QR code (#182). There is no on-device OCR by design (D15), and a Tabit QR
  code answers "not supported yet" until the Tabit adapter exists (#176).
  Also not built: community features — venue ratings, reviews, submissions
  (Phase 3, `backend_plan.md` §5's milestone C).
- Backend hosting beyond `localhost` (issue #109, `architecture.md` §17.6). The
  backend is designed to be run locally by whoever has the repository checked
  out; nothing yet says where it runs for anyone else.
- The pinned Gemini model has answered the real prompt only through the
  backend, from a laptop (the #165 smoke test); the phones' direct client has
  never been run with a real key. See "What is NOT verified yet" below.

Nothing above is stubbed — the files simply do not exist, which keeps them out of
the coverage denominator.

## What is NOT verified yet

Built, but not confirmed end to end, and not to be reported as done:

- **Gemini smoke test run 2026-09-28** (`architecture.md` §17.1, #165). The
  network is reachable from this environment after all. Findings changed the
  default model: `gemini-2.5-flash` is 404 for new users (Google recommends
  `gemini-3.8-flash`), so `GEMINI_MODEL` moved to `gemini-3.5-flash`
  (`gemini-3.8-flash` and `gemini-flash-latest` return 503 for structured
  output; `gemini-flash-lite-latest` rejects `thinkingConfig`). Measured on
  a laptop through the local backend: 33.5 s cold for a 20-dish English
  menu, 8.8 s for a 10-dish Hebrew menu (Hebrew `why`/`modification` came
  back in Hebrew), 4 ms for a repeat via the shared completion cache. What
  is still unverified: phone latency (#65 numbers) and a real 60-dish or
  bigger menu (Gemini returned 503 UNAVAILABLE for the 56-dish attempt).
  Redacted responses under `test/fixtures/llm/smoke_*.json`.
- **The phones' direct Gemini client (D17) has never completed a real
  request.** Google's real invalid-key reply (a 400 naming
  `API_KEY_INVALID`) was recorded and pinned in
  `gemini_chat_client_test.dart`, but no valid key has been used with
  `GeminiChatClient`: the smoke test above went through the backend only.
  Whether Google accepts `toGeminiSchema`'s output for the real prompt's
  schema, and the direct path's latency on a phone, are unobserved.
- **No real Gemini request carrying images has been sent** (#88). The vision
  path (D15, `VisionMenuClassifier`) is proven against fakes and recorded-shape
  fixtures only: whether `gemini-3.5-flash` accepts `image/*` and
  `application/pdf` parts with the real prompt and schema, how long a multi-page
  scan takes, and how accurate the transcription is on a real printed or Hebrew
  menu are all unobserved. `backend/tools/vision_smoke.py` is the person-run check.
- **QR scanning is evidenced by a fake scanner only; no device has run the
  camera.** `MobileQrScanner` (over `mobile_scanner`, in
  `lib/widgets/mobile_qr_scanner.dart`) is tested with a stand-in camera view,
  and `QrPayloadRouter` against a table of URL kinds; whether the plugin builds
  for Android and iOS is known only from CI, and how it decodes a real table QR
  code, in Hebrew or a small print, is unobserved.
- **The Scan tab's pickers and permissions are evidenced by fakes only.**
  `DevicePagePicker` (over `image_picker` and `file_picker`) and the iOS camera and
  photo-library permission strings (English and Hebrew `InfoPlist.strings`, not
  yet registered in Xcode, see below) have never run on a phone or a simulator.
- **The Wolt menu fixture is real** (`wolt_hamosad_menu.json`, recorded
  2026-09-25 from the consumer-assortment endpoint the app now calls; issues
  #22, #168), but only one venue was recorded and only from a laptop — this
  environment still cannot reach `consumer-api.wolt.com`. It carries no
  currency (the mapper defaults to `ILS`) and every `subcategories` list in it
  is empty, so how the mapper flattens a populated one is inferred, not
  observed. The app itself has not yet fetched a live assortment on a phone.
- **The Wolt discovery fixtures are still synthetic** (`wolt_pages_restaurants.json`,
  `wolt_pages_search.json`; issue #38). Neither `consumer-api.wolt.com` nor
  `restaurant-api.wolt.com` is reachable from this environment, so both were
  hand-built from third-party documentation rather than recorded
  (`test/fixtures/README.md`, `phase2_discovery_research.md` §2).
- **The 10bis fixture is synthetic** (`tenbis_synthetic_menu.json`; issue #44,
  tracked separately from #22). `www.10bis.co.il` is blocked the same way; see
  `test/fixtures/README.md` for the curl to run once a machine can reach it.
- **Website menus (#181, D19) have never read a real restaurant site.** The
  locator, page reader and both fetchers are tested against synthetic HTML
  (`test/fixtures/website/`) and mocked HTTP only; no browser has run the web
  path and no phone the direct one. How often real Israeli sites carry
  JSON-LD menus, link a menu page or PDF, or render only with JavaScript is
  unmeasured, and a website PDF has never been sent to Gemini.
- **No physical iOS or Android device has ever run this app.** Screen-brightness
  raising for the Waiter Card in particular is evidenced only by a mocked method
  channel and a fake, and the location-permission prompt (approximate/precise on
  Android 12+, the "Never" path on iOS) is evidenced only by fakes. The Hebrew
  iOS permission strings (location, camera, photo library) exist on disk in
  `ios/Runner/{en,he}.lproj/InfoPlist.strings` (#169, #196, #205), but the
  one-time Xcode step that registers them with the Runner target
  (`docs/RUNNING_IOS.md`, "iOS Hebrew permission string") has not been done or
  checked, so until it is a Hebrew phone may still see the English prompt.
- **The performance budget numbers are unmeasured on a real device** (issue
  #65). `tool/perf_menu.dart` and its 16 ms-per-frame budget table
  (`tool/README.md`) exist, but the measurement itself needs a real phone on
  a real network — see `docs/RELEASE.md` §5.
- **The UI has been compared with the artboards on the web build only.**
  `docs/VISUAL_AUDIT.md` rendered every reachable screen at 390px, light and
  dark, English and Hebrew, against stubbed upstreams, fixed what diverged
  and lists what it left and why. It saw only rules-engine results (no
  model is reachable here) and no phone; token fidelity is enforced by a
  test, pixel fidelity by no test at all.
- **No human has reviewed this code.**
- The three colour pairs that failed WCAG AA contrast (green-on-green at
  4.08:1, light `ink3`-on-bg at 2.78:1, dark `ink3`-on-bg at 4.02:1) were
  fixed and are now pinned by `test/theme/contrast_test.dart`, along with
  every other `on`/surface pair `VerdictColors` produces — see the
  "Contrast fixes" note in `lib/theme/app_tokens.dart` (issue #64, the
  contrast half; semantics/RTL/large text are a later PR).

## Getting started

1. **`HANDOFF.md`** — what exists, what is unfinished and why, the traps.
2. **`architecture.md`** — the authoritative design. §16 is the build order —
   steps 6–7 added the backend, and steps 8–10 (the 10bis adapter, location and
   nearby search, platform setup) are now done too, modulo the fixture
   recordings and phone run in "What is NOT verified yet" above. What's next
   is Phase 3's remaining milestone (community database, reviews, submissions;
   `backend_plan.md` §5 milestone C, issues #105–#108) and Phase 4's open
   scan issue (#88; §16's Phase 4 steps). §14 has the decisions
   log D1–D19, §17 the open questions with the default the code follows.
3. The convention documents: `PR_CONVENTIONS.md`, `ISSUE_CONVENTIONS.md`,
   `MILESTONE_CONVENTIONS.md`, `UNIT_TEST_CONVENTIONS.md`, `FLOW_TEST_CONVENTIONS.md`.
   **Caveat:** the test-convention documents contain illustrative examples referencing
   screens and workflow files that do not exist (`HomeScreen`, `VenueListScreen`, a
   `test.yml` workflow). Their rules apply; their sample code does not compile.
4. `README.md` for the product narrative and the original keto vocabulary. Its
   classification pseudo-code is superseded — see `architecture.md` §6.2 and
   `lib/utils/constants.dart`, which fixed several defects in it.
5. `docs/RELEASE.md` — the pre-release checklist and device test matrix, for
   when a release is actually being cut.
