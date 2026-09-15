# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**KetoClub** is a restaurant menu analysis platform designed to help keto dieters find safe dining options. The app ingests live menus from restaurant delivery platforms, classifies dishes by keto-compatibility, and generates automatic waiter instructions for modifications.

> **Status: Phase 1 is built and merged.** Build-order steps 1–5 of
> `architecture.md` §16 ship: models and service contracts, the bilingual heuristic
> engine, Wolt ingestion with a Hive cache, the classified menu screen and Waiter
> Card, and the OpenRouter client with its router and Settings. 1707 tests, 98.5% of
> 2331 instrumented lines (six flow tests in `integration_test/flows/`). Three
> recorded decisions were reversed in this close-out pass (`architecture.md`): D10
> reinstates `Connectivity`, §17.4 now renders `net_carbs_estimate` as a labelled
> chip, and §6.6's collapsed red-dish group is gone — the verdict counter tiles are
> the filter now.
>
> **Read `architecture.md` first — it is authoritative.** This file and `README.md`
> predate the code in places; where any of them disagrees with `architecture.md`,
> architecture.md wins. **`HANDOFF.md` is the fastest way in**: what exists, what is
> deliberately unfinished, and the traps that already cost time.

## Architecture & Core Components

### Client-Only Architecture (No Backend)

Single Flutter codebase for web, iOS, and Android with:
- **Classification Engine**: **a hosted language model is the primary classifier, with
  an on-device rule engine as the fallback** (`architecture.md` D2). The user supplies
  their own OpenRouter key; when there is no key, no consent, or no network, the rule
  engine answers and the UI labels the result "rules". Both sit behind one
  `MenuClassifier` interface and a router picks per call. A `Connectivity` pre-check
  (`architecture.md` D10, reinstated in this pass) asks the device whether it looks
  online before ever spending an OpenRouter request; it is a hint, never a verdict,
  so a failed call still reports `offline` exactly as it did before this check
  existed.
- **API Integration**: Direct calls to restaurant platform APIs from the client.
  **Only Wolt is implemented**; 10bis, Tabit and Ontopo are not built.
- **Local Storage**: Hive caches the normalised menu and its analysis for 24 hours;
  `flutter_secure_storage` holds the OpenRouter key; `shared_preferences` holds
  non-secret settings.
- **No server, no database**: All menu analysis and data processing happens on the
  user's device.

### Menu Ingestion & API Integration

KetoClub integrates with four restaurant platform APIs:

| Platform | Auth | Data Format | Primary Use |
|----------|------|-------------|------------|
| **Wolt** | None (slug-based) | Standardized JSON (items, categories, options) | Primary delivery aggregator |
| **10bis** | None (restaurant ID) | Hierarchical JSON (categories → dishes) | Israeli corporate delivery |
| **Tabit** | Session token via QR | POS-level JSON (modifiers, kitchen groups) | Restaurant dine-in QR ordering |
| **Ontopo** | Anonymous bearer token | PDF/S3-hosted links (OCR-capable) | Reservation platform with menu links |

Key fetch patterns:
- **Wolt**: `GET https://restaurant-api.wolt.com/v4/venues/slug/{venue_slug}/menu/data`
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

Future additions: user ratings, review feedback loop, OCR/vision processing for physical menus.

## Development Workflow

### Current status

Phase 1 is built and merged (see the banner at the top). The repository holds a
working Flutter app plus the planning documents it was built from.

### Actual project structure

```
lib/
├── main.dart                  # runApp(KetoClubApp(dependencies: buildDependencies()))
├── di.dart                    # composition root: the ONLY file constructing concrete services
├── app.dart                   # MaterialApp, localisation delegates, generateRoute
├── l10n/                      # app_en.arb, app_he.arb + committed generated/ output
├── models/                    # venue, menu, analysis, failures — plain immutable Dart
├── utils/                     # constants (the keto vocabulary), text_normaliser,
│                              # classification_rules, price_format, keto_score
├── services/
│   ├── platform/              # clock, app_logger, connectivity (D10), screen_brightness
│   ├── storage/               # key_store, menu_cache, settings_store (interface + impl each)
│   ├── llm/                   # llm_chat_client, open_router_client
│   ├── venue/                 # venue_ref_resolver (paste-a-URL, pure)
│   ├── menu/                  # platform_menu_adapter, menu_repository, wolt/
│   └── classifier/            # menu_classifier, heuristic, llm, router, prompt, parser
├── theme/                     # app_tokens, verdict_colors, app_typography, app_theme
├── state/                     # app_dependencies, locale_controller + one ChangeNotifier per screen
├── widgets/                   # dish_card, status_badge, engine_chip, waiter_script,
│                              # verdict_counter_tiles, keto_score_badge, app_shell, failure_copy
└── screens/                   # venue_search, menu, waiter_card_sheet, settings,
                               # scan and saved (bottom-nav placeholders, issue #11)

test/                          # mirrors lib/, plus architecture/, fakes/, fixtures/, l10n/, tool/
integration_test/flows/        # six flow tests + flow_support.dart (same-directory helper)
tool/                          # check.sh (the gate), coverage_gate.sh, gen_coverage_helper.sh,
                                # measure_model_latency.dart (issue #16), record_wolt_fixture.sh (issue #22)
```

`architecture.md` §5 carries the same tree with the layer-rank rules the
architecture test enforces.

### Setup and the gate

```bash
flutter pub get
tool/check.sh          # format, analyze --fatal-infos --fatal-warnings, tests, 80% coverage gate
flutter run -d chrome  # web; live menu fetching is blocked by CORS, see architecture.md §13
flutter run -d <device>
```

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
   call per menu, never one per dish — the OpenRouter free tier is 50 requests a day
   (D6). `RoutingMenuClassifier` chooses: no key or no consent means the heuristic
   stamped `notConfigured`; otherwise the LLM, falling back to the heuristic on
   `offline`, `timeout`, `rateLimited` and `badResponse` with that reason carried
   through so the UI can say why. **`unauthorised` does not fall back** — a rejected
   key must be visible, not quietly answered with a weaker result.
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
   lives in "choice of side", not the description.
6. **Everything at a service boundary returns a sealed result**, never throws, and
   every failure reason is distinct. Collapsing two reasons into one message is the
   bug §10 names; `failure_copy.dart` has a test asserting no two of the eleven
   reasons share copy in either language.
7. **`di.dart` is the only file that constructs a concrete service**, and nothing it
   calls performs plugin I/O — see the traps above.
8. **The key** lives in `flutter_secure_storage`, is read only by `OpenRouterClient`,
   and never reaches a log, a failure value, the cache or the widget tree. Settings
   exposes `hasKey`, never the key; there are tests asserting the string appears
   nowhere it should not.

## Planning & Research Documents

**Core Documentation:**
- `architecture.md`: The authoritative architecture (client-only Flutter app, LLM-primary classifier with heuristic fallback, adapters, storage, failure handling, decisions log). Read this before the README where they disagree
- `README.md`: Full project narrative, API endpoints, database schema, keto classification rules, Phase roadmap
- Engineering standards (SOLID, acyclic imports, clean code, tests, CI) are `architecture.md` §18. Run `tool/check.sh` before pushing; it runs exactly what CI runs.

- `backend_plan.md`: The planned Python (FastAPI) backend — why (CORS on web), the
  API contract, the client seams, and issues #94–#109 in priority order.
  Scaffolding has started (`backend/`, issue #94: a health endpoint, its own
  `check.sh` and a required CI job) but the menu proxy is not built and nothing
  in `lib/` talks to it yet — the Flutter app is still client-only in practice.
  `architecture.md` gains D11 when #97 lands

**Research & Analysis:**
- `m16_menu_scanner_research.md`: Computer vision and OCR strategy for physical menu scanning (Phase 4)
- `m15_meal_entry_research.md`: User flow design for meal logging and macro tracking
- `m15_openrouter_models_fix.md` / `m16_structured_output_fix.md`: LLM model evaluation and structured output schemas (if integrating AI for edge cases)
- `menu_api_research`: Platform API comparison and reverse-engineering notes
- `feature_prioratization`: Phase breakdown and feature prioritization

**Conventions:**
When reading research docs (m15/m16), note that prefixes indicate iteration/milestone markers—not all research conclusions are adopted, so verify against the `feature_prioratization` document and README roadmap before implementing.

## Project Phases

- **Phase 1**: menu ingestion, classification and waiter scripts → **Built and merged**
- **Phase 2**: geolocation and nearby search, plus the 10bis adapter → **Next.**
  Nearby search is blocked on discovery: no Wolt venue-search endpoint is known
  (`architecture.md` §17.2). See `MILESTONE_CONVENTIONS.md` for the real GitHub
  milestone names — they differ from earlier drafts of this document.
- **Phase 3**: Community database, user reviews, restaurant submissions, and the
  CORS-forwarding backend the web build needs (`backend_plan.md`) → **Planned**
- **Phase 4**: OCR/vision, configurable dietary rules → **Planned**

Phase 1 is built. Phase 2 is next; `feature_prioratization` has the tier breakdown.

## What is NOT built yet

- 10bis, Tabit and Ontopo adapters. Only Wolt ships. `VenueRefResolver` already
  recognises a pasted 10bis URL or bare restaurant id, but `MenuRepository` has no
  adapter registered for it, so it fails with `unsupportedSource` — paste
  recognition and platform support are independent claims. The `PlatformMenuAdapter`
  interface and its shared contract suite already exist, so a new platform is a new
  adapter plus a registration in `di.dart`. (10bis is its own GitHub milestone,
  `Phase 2: 10bis Integration` — not Phase 1.)
- Nearby venue search and any geolocation. `geolocator` is in `pubspec.yaml` but no
  code uses it. Paste-a-link (Tier A) is what ships.
- OCR and the photographed-menu path (Phase 4), community features and any backend
  (Phase 3). The Scan and Saved bottom-nav tabs exist only as localized placeholder
  screens explaining that (issue #11) — they are not stubs left blank.
- The pinned OpenRouter model has never been run against the real prompt from this
  environment: `openrouter.ai` is unreachable through the egress proxy here. See
  "What is NOT verified yet" below.

Nothing above is stubbed — the files simply do not exist, which keeps them out of
the coverage denominator.

## What is NOT verified yet

Built, but not confirmed end to end, and not to be reported as done:

- **The pinned OpenRouter model** (`architecture.md` §17 open question 1).
  `tool/measure_model_latency.dart` and `tool/README.md` now make this a one
  command job (`OPENROUTER_API_KEY=... dart run tool/measure_model_latency.dart`)
  for anyone with a network path to `openrouter.ai` — this container does not have
  one. Until someone runs it, the pinned model's latency and structured-output
  behaviour are still carried over from `m15_openrouter_models_fix.md`, not
  measured against this app's real prompt.
- **The Wolt fixture is synthetic**, not a recorded response (issue #22).
  `tool/record_wolt_fixture.sh` exists to re-record it from a real venue, but has
  never been run — `restaurant-api.wolt.com` is also unreachable here.
- **No physical iOS or Android device has ever run this app.** Screen-brightness
  raising for the Waiter Card in particular is evidenced only by a mocked method
  channel and a fake.
- **No screenshot or narrow-width run has confirmed the UI against the artboards.**
  Token fidelity (colours, spacing) is enforced by a test; pixel fidelity is not.
- **No human has reviewed this code.**
- Two light-mode colour pairs in `lib/theme/app_tokens.dart` fail WCAG AA contrast
  (green-on-green at 4.08:1, ink3-on-bg at 2.78:1) — tracked as issue #64, not fixed.

## Getting started

1. **`HANDOFF.md`** — what exists, what is unfinished and why, the traps.
2. **`architecture.md`** — the authoritative design. §16 is the build order (continue
   at step 6, the 10bis adapter), §14 the decisions log D1–D10, §17 the open
   questions with the default the code follows.
3. The convention documents: `PR_CONVENTIONS.md`, `ISSUE_CONVENTIONS.md`,
   `MILESTONE_CONVENTIONS.md`, `UNIT_TEST_CONVENTIONS.md`, `FLOW_TEST_CONVENTIONS.md`.
   **Caveat:** the test-convention documents contain illustrative examples referencing
   screens and workflow files that do not exist (`HomeScreen`, `VenueListScreen`, a
   `test.yml` workflow). Their rules apply; their sample code does not compile.
4. `README.md` for the product narrative and the original keto vocabulary. Its
   classification pseudo-code is superseded — see `architecture.md` §6.2 and
   `lib/utils/constants.dart`, which fixed several defects in it.
