# KetoClub backend — plan, API contract and prioritisation

> **Status: Backend Foundations and Hosted Classification have landed.**
> Decided 2026-09-13. The issues are #94–#109 in three milestones: *Phase 3:
> Backend Foundations* (#94–#99), *Phase 3: Hosted Classification* (#100–#104)
> and *Phase 3: Community API* (#105–#109). Shipped: #94 (`backend/` scaffold,
> its own gate and a required CI job), #95/#96 (the Wolt menu proxy and the
> Dart `proxyBase` wiring that unblocks the web build's CORS problem), #100
> (`POST /v1/chat` against Google Gemini), #101 (the anonymous
> `InstallIdStore`), #102 (`BackendChatClient` replaces `OpenRouterClient`
> entirely — there is no bring-your-own-key fallback chain, §4 below is
> corrected accordingly) and #103 (the shared, server-side completion cache).
> #98 and #104 were folded into #102's scope rather than done separately (see
> `MILESTONE_CONVENTIONS.md`). `KETOCLUB_BACKEND_URL` is read in `lib/di.dart`
> and the web build fetches live Wolt menus and hosted-model analysis through
> it when configured; with no backend URL the app is exactly the client-only
> app D1 first described. **D25 (#318, #319, #320–#335) then made the backend
> serve complete results to every platform** (§3.3's seven routes, a Python
> port of the Dart menu logic pinned by a golden corpus, an analysis cache and
> bucket), with the device's own adapters and engines as the fallback; §2, §3.3
> and §4 below are corrected where they said the backend was a dumb passthrough
> or web-only. **This document's design is now largely history**:
> `architecture.md` is authoritative (D11, D12 in §14) and this plan is kept
> for the reasoning and the milestone/issue breakdown, corrected below where it
> named OpenRouter or a bring-your-own-key path that no longer exists. Still
> open: #105–#109 (community API, hosting beyond `localhost`).

## 1. Why a backend, and why now

The web build cannot fetch Wolt menus. `restaurant-api.wolt.com` sends no CORS
headers, so the browser refuses the request before it leaves and the app shows
`MenuFetchFailureReason.blockedByBrowser` ("open this in the phone app").
Native HTTP stacks do not enforce CORS, so iOS and Android work as written. Wolt
needs no auth and nothing in this repository shows Wolt blocking phones; the
only 403s ever seen were the build sandbox's own egress proxy.

`architecture.md` §13 already names the fix: "a tiny CORS-forwarding proxy … is
the first thing the Phase 3 backend does, and it is the only reason to add one
before community features." That reason has arrived. The decision widens it to
the full Phase 3 backend so the work is planned once.

## 2. Decisions

| Question | Decision |
|---|---|
| Trigger | The web build is blocked by CORS |
| Scope | Full Phase 3 backend: menu proxy, hosted model key, shared analysis cache, community data |
| Stack | Python 3.11+, FastAPI, in `backend/` of this repository; run locally on `localhost:8000` for now; hosting is #109 |
| Routing | The **web** build fetches menus through the backend. **Mobile keeps calling Wolt directly**; the backend URL is simply not defined in mobile builds. **Amended by D25 (architecture.md §14): every platform built with a backend URL asks the backend's complete-result routes first (§3.3), and the direct adapters and engines are the fallback** |
| Model owner | **Decided (D12), supersedes the row below as originally written.** The backend holds one Google Gemini key. There is no bring-your-own-key fallback: the app never holds a model key at all, `KeyStore` and `flutter_secure_storage` are removed, and the on-device rules engine is the only fallback, reached through the router exactly as it always was for every other failure reason |
| ~~Model owner (original)~~ | ~~The backend holds one OpenRouter key. The user's own key (BYOK, D3) stays as the fallback; the on-device rules engine stays as the last fallback~~ — superseded by D12 before #100 was built; struck through rather than deleted so the decision that was reversed stays visible |
| Identity | Anonymous per-install ID sent as a header. No accounts, no login |
| Old issues | #67, #70–#73 closed; this plan replaces them |

**Principle: the backend is an accelerator, never a dependency.** With no
backend URL the app behaves exactly as it does today, including the web build's
paste path. ~~The backend is deliberately dumb: it forwards, holds a key, caches
and stores community data. It does **not** normalise Wolt JSON, build prompts
or parse model replies. Those stay in Dart, where 1418 tests already cover them,
so nothing is duplicated in Python.~~ **Reversed by D25:** the backend now
normalises Wolt and 10bis JSON, builds the prompt, parses the model's reply and
runs the rule engine, from a Python port (`backend/app/keto`, `platforms`,
`website`) that is proven equal to the Dart code by a golden corpus
(`tool/golden`, `backend/tests/fixtures/golden/`). Dart remains the source of
truth; the duplication is the price of a complete result in one request. D10
extends to the backend: the call is the probe, and the client never pre-checks
whether the server is up.

## 3. Backend service (`backend/`)

### 3.1 Tooling and layout

- Python ≥ 3.11, FastAPI, uvicorn, httpx, SQLAlchemy 2, pydantic-settings.
- `uv` for the lockfile and virtualenv (`uv.lock` committed), ruff for lint and
  format, mypy strict, pytest with pytest-cov and an 80% floor, respx to fake
  Wolt and Gemini. No test makes a network call (constraint 12 applies).
- `backend/check.sh` is the gate, mirroring `tool/check.sh`:
  `uv sync --frozen && ruff check && ruff format --check && mypy app && pytest --cov=app --cov-fail-under=80`.
- A `backend` job in `.github/workflows/ci.yml` that **always runs** (about a
  minute with `astral-sh/setup-uv` and its cache). It is not path-filtered: a
  required check that does not run stays "Expected" forever and blocks
  Flutter-only pull requests.

```
backend/
├── pyproject.toml, uv.lock, .env.example, README.md, check.sh
├── app/
│   ├── main.py          # app factory; lifespan: create_all, one shared httpx.AsyncClient; CORS
│   ├── config.py        # pydantic-settings
│   ├── db.py            # sync engine, check_same_thread=False, WAL, session per request
│   ├── models.py        # menu_cache, chat_cache, venues, ratings, dish_feedback, submissions
│   ├── schemas.py
│   ├── routers/         # health, proxy, chat, discovery, website, menus; D25: venue_menus, classify,
│   │                    # text_menu, scan, website_menu, venues (submissions, admin still planned)
│   ├── services/        # wolt, gemini, chat_cache, rate_limit, install_id; D25: classify, scan,
│   │                    # analysis_cache, platform_menu, website_fetch, request_body
│   ├── keto/            # D25: the Python port of the Dart menu logic (vocabulary.json, normaliser, rules,
│   │                    # heuristic, prompt, parser, text_menu, dish_kind, score, fingerprint, wire models)
│   ├── platforms/       # D25: Wolt menu, 10bis menu and Wolt venue mappers
│   └── website/         # D25: website locator, JSON-LD and HTML reader
└── tests/               # conftest: app over in-memory SQLite (StaticPool) + respx router;
                         # fixtures/golden/ holds the 14 documents the port replays
```

### 3.2 Configuration (`.env`)

| Variable | Default | Meaning |
|---|---|---|
| `GEMINI_API_KEY` | unset | The server's key, sent only as `x-goog-api-key`. Unset means `/v1/chat` answers `notConfigured` (superseded `OPENROUTER_API_KEY`, D12) |
| `GEMINI_MODEL` | `gemini-3.5-flash` | Model requested at `generateContent` (superseded `OPENROUTER_MODEL`; superseded: see architecture.md D12 note for the default) |
| `GEMINI_BASE_URL` | `https://generativelanguage.googleapis.com` | Upstream host; never taken from a request |
| `GEMINI_MAX_OUTPUT_TOKENS` | `65536` | `generationConfig.maxOutputTokens` (was `8192`; see `config.py`) |
| `GEMINI_THINKING_BUDGET` | `0` | Thinking tokens count against the output budget, and this is a classification task |
| `WOLT_BASE_URL` | `https://restaurant-api.wolt.com` | Upstream host for the proxy; never taken from a request |
| `DATABASE_URL` | `sqlite:///./ketoclub.db` | Postgres is an env-var swap later; Alembic arrives with it |
| `CORS_ORIGIN_REGEX` | `^https?://(localhost\|127\.0\.0\.1)(:\d+)?$` | Flutter's dev server picks a random port |
| `ADMIN_TOKEN` | unset | Required by `/v1/admin/*`; unset means 503 |
| `MENU_CACHE_TTL_SECONDS` | 3600 | Raw Wolt body cache |
| `CHAT_CACHE_TTL_SECONDS` | 86400 | Equal to the app's `menuCacheTtl` |
| `RATE_LIMIT_PER_MINUTE`, `RATE_LIMIT_PER_DAY` | 5, 40 | Per install ID, on `/v1/chat` and the write endpoints |
| `ANALYSIS_RATE_LIMIT_PER_MINUTE`, `ANALYSIS_RATE_LIMIT_PER_DAY` | 10, 60 | Per install ID, the D25 analysis bucket (§3.3): spent only when a Gemini call is about to be made (#333) |
| `ANALYSIS_CACHE_TTL_SECONDS` | 604800 | The D25 analysis cache (§3.3, #333) |
| `CLASSIFY_MAX_BODY_BYTES` | 786432 | Largest `POST /v1/classify` body (768 KiB); over it → 413 `payloadTooLarge` (#333) |

CORS: `allow_origin_regex` from config, `allow_methods=[GET, POST]`,
`allow_headers=[Content-Type, Accept, X-KetoClub-Install-Id]`, no credentials.
The custom header forces a preflight; the middleware answers it.

### 3.3 API contract (all under `/v1`)

> **Rewritten for D25 (#321); all seven D25 routes are built (#333–#335) and
> wired in the client (#327–#329, #331).** The route table below is the
> contract the thin-client work (#318, #319) built against: every route the
> backend serves, then the seven D25 routes that serve complete results. Where
> this section and the code disagree, the code (and `architecture.md`) wins.
> The `/v1/venues/{source}/{platform_id}` community endpoints
> this section used to list were never built and are no longer planned under
> that path (it now names venue search); milestone C (#105–#108) will pick
> its own paths.

**Conventions every route shares.**

- Every error the backend itself originates is `{reason, status_code}`
  (`app.errors.BackendError`); a body or query that fails validation is
  FastAPI's 422 `{detail: [{type, loc, msg}]}`, which never echoes the input.
- `X-KetoClub-Install-Id` (32 lowercase hex, §3.4) is required wherever a
  rate limiter is listed below; missing or malformed is 400 `badResponse`.
  An inbound `Authorization` header is 400 `badResponse` on every route
  marked "no auth header". The install id is read for limiting only: no
  route stores it, and only `install_id[:8]` is ever logged (none at all on
  `/v1/menus`, D24).
- `X-KetoClub-Cache: hit|miss|bypass` reports the route's own cache where
  it has one; CORS exposes it.
- The pre-D25 bodies (`/v1/chat`, `/v1/website/fetch`, `/v1/menus`, the
  discovery search) are **snake_case**. The D25 bodies are **camelCase**:
  they carry the Dart `Menu`, `MenuAnalysed` and `Venue` JSON verbatim
  (`app.keto.models`, byte-identical to the Dart `toJson`, every key present
  and null ones included), so one casing runs through each body. Their
  pydantic models are in `app/schemas.py`.

**Rate-limit buckets** (all in memory, per install id unless noted):

| Bucket | Limit | Spent by |
|---|---|---|
| chat (`RATE_LIMIT_*`) | 5/min, 40/day | `/v1/chat` cache misses, `POST /v1/menus` |
| discovery (`DISCOVERY_RATE_LIMIT_PER_MINUTE`) | 20/min, no daily cap | discovery-proxy and `/v1/venues/*` cache misses |
| website install / host (`WEBSITE_*`) | 10/min per install; 6/min per site across installs | `/v1/website/fetch`, `/v1/website-menu` (every upstream fetch, link hops included) |
| analysis (`ANALYSIS_RATE_LIMIT_*`, D25) | 10/min, 60/day | only when a Gemini call is about to be made: never on an analysis-cache hit, never for a rules-only result |

#### Routes that exist today

| Route | Request | Success | Errors | Limiter / cache |
|---|---|---|---|---|
| `GET /health` | — | 200 `{status, version, llm_configured}` | — | — |
| `POST /chat` (#100, D12; images D15) | `{system_prompt, user_prompt, response_schema?, schema_name?, images?: [{mime_type, data}]}`; no auth header | 200 `{content, model}` | 400, 422, 429 `rateLimited`, 502 `offline`/`badResponse`, 503 `notConfigured`, 504 `timeout` (table below) | chat bucket on a miss; completion cache keyed by request hash, `CHAT_CACHE_TTL_SECONDS`; a request with images bypasses it |
| `GET /proxy/wolt/venues/slug/{slug}/assortment` (#95, #168) | `slug` `^[a-z0-9][a-z0-9-]{0,99}$` | Wolt's status, body and `Content-Type`, unchanged (404 included) | 502 `offline`, 504 `timeout` | none; 2xx bodies cached per slug, `MENU_CACHE_TTL_SECONDS` |
| `GET /proxy/tenbis/api/v1.0/Restaurants/{restaurant_id}/Menu` (#122) | `restaurant_id` `^[0-9]{1,12}$` | 10bis's status, body and `Content-Type`, unchanged | 502 `offline`, 504 `timeout` | as the Wolt proxy |
| `GET /proxy/wolt/pages/restaurants?lat&lon&lang` (#123) | `lat` −90..90, `lon` −180..180, `lang` `en`\|`he` | Wolt's status and body, unchanged (410 included) | 400, 422, 429 `rateLimited`, 502 `offline`, 504 `timeout` | discovery bucket on a miss; 2xx cached, `DISCOVERY_CACHE_TTL_SECONDS` |
| `POST /proxy/wolt/pages/search` (#123) | `{q (1..80, trimmed), lat?, lon? (together or neither), lang}` | as above | as above | as above |
| `POST /website/fetch` (D19, #181) | `{url (1..2048)}` | 200 `{kind: html\|pdf, content_type, body, final_url}` (`body` is base64 for a PDF) | 400 `invalidUrl`, 403 `disallowedByRobots`/`aiReserved`, 404 `notFound`, 413 `tooLarge`, 415 `unsupportedContent`, 422 `jsOnlyPage`, 429 `rateLimited`, 502 `offline`/`upstreamStatus`, 504 `timeout` | website install and host buckets; nothing cached; public hosts only, robots.txt and AI opt-outs honoured |
| `POST /menus` (D24, #310) | `{source, platform_id, venue_name?, city?, menu, analysis?}`, ≤ `MENU_STORE_MAX_BODY_BYTES`; no auth header | 201 (new) / 200 (refreshed) `{created, submission_count}` | 400, 413 `payloadTooLarge`, 422, 429 `rateLimited` | chat bucket; keyed by `(source, platform_id)`, never by install id |
| `GET /menus/{source}/{platform_id}` (D24) | — | 200 the stored row | 404 `menuNotFound` | — |

`/v1/chat`'s own errors, `reason` a `ChatFailureReason` name:

| Status | `reason` | When |
|---|---|---|
| 503 | `notConfigured` | No server key, or upstream 400 `API_KEY_INVALID`/401/403 |
| 502 | `offline` | Upstream connect error |
| 504 | `timeout` | Upstream read timeout |
| 429 | `rateLimited` | Upstream 429, or the install's chat bucket |
| 502 | `badResponse` | Any other upstream status, a non-`STOP` finish reason, or an unusable body |

Gemini is called as `POST {GEMINI_BASE_URL}/v1beta/models/{GEMINI_MODEL}
:generateContent` with `x-goog-api-key` (never `?key=`), `temperature: 0`,
the configured output and thinking budgets, and a read timeout of 110 s.
Strict `responseSchema` first; on an upstream 400 that is not
`API_KEY_INVALID`, exactly one re-send without the schema; 401, 403, 429 and
5xx are never retried. The D25 routes reuse this client (`app.services.gemini`)
and its failure mapping.

#### D25 routes: complete results (#318; built by #333, #334, #335)

Shared rules for the four routes that analyse a menu:

- **Options** are `ClassificationOptionsBody`: `{netCarbLimitGrams: int
  1..50, dietaryConstraints: [string] (≤ 3)}`. Each constraint is one of the
  Dart prompt fragments verbatim (`seedOilFreePromptFragment`,
  `dairyFreePromptFragment`, `carnivoreOnlyPromptFragment`); anything else
  is 422, because free text would reach the system prompt under the
  server's key. Consent is not a field: calling a route that analyses is the
  consent, so a client without it does not call one.
- **The returned analysis** is a Dart `MenuAnalysed`: `options` is the
  request's options as an `AnalysisOptionsSnapshot` (`ClassificationOptionsBody
  .snapshot()`), `schemaVersion` is 1, and `engine` is `{"kind": "llm",
  "model": …}` from Gemini or `{"kind": "rules", "reason": …}` from the
  ported heuristic — so the client's `_reusableAnalysis` accepts it as if it
  had made it.
- **A Gemini failure is not an error** on the text routes: the server runs
  the ported heuristic and stamps it `{"kind": "rules", "reason": <the
  failure's name>}` (`offline`, `timeout`, `rateLimited`, `badResponse`,
  `notConfigured`), exactly as the client's `RoutingMenuClassifier` falls
  back.
- **An empty analysis bucket**: a route whose only product is the analysis
  (`/v1/classify`, `/v1/text-menu`, `/v1/scan`) answers 429 `rateLimited`
  and the client falls back on device; a route that also fetched a menu
  (`/v1/venue-menus`, `/v1/website-menu`) keeps the menu and returns the
  heuristic stamped `{"kind": "rules", "reason": "rateLimited"}`.
- **Analysis cache** (`analysis_cache`, `ANALYSIS_CACHE_TTL_SECONDS`, 7 days):
  key `sha256(fingerprint|model|schemaVersion|netCarbLimitGrams|constraints)`
  over the menu's dish-text fingerprint. A hit spends nothing; only an `llm`
  analysis is written. Scans (images) never touch it.
- All seven routes require `X-KetoClub-Install-Id` and refuse an
  `Authorization` header.

| Route | Request | Success | Errors |
|---|---|---|---|
| `GET /venue-menus/{source}/{platform_id}` | `source` `wolt`\|`tenbis` (else 422); `platform_id` the proxy's slug or restaurant-id pattern. Query: `classify` (bool, default `false`), `netCarbLimitGrams` (int 1..50, default 6), `constraints` (repeated, ≤ 3, the fragment rule above; repeated rather than comma-joined because a fragment contains commas) | 200 `VenueMenuResponse {menu, analysis \| null, fromCache, fetchedAt}`; `analysis` is null when `classify` is false or the menu has no dish to classify; `fetchedAt` is the upstream fetch time (= `menu.fetchedAt`); `X-KetoClub-Cache` reports the menu cache | 404 `notFound` (platform 404), 502 `platformChanged` (other upstream status, or a payload the mapper cannot read), 502 `offline`, 504 `timeout`, 422 |
| `POST /classify` | `ClassifyRequest {menu, options}`, ≤ 768 KiB | 200 `ClassifyResponse {analysis}` | 413 `payloadTooLarge`, 422 (incl. `noDishesFound` as a `{reason, status_code}` body when the menu has no dish), 429 `rateLimited` |
| `POST /text-menu` | `TextMenuRequest {text (1..100,000 chars), options}` | 200 `ScannedMenuResponse {menu, analysis}`; `menu.venueRef` is `scan/<fingerprint hex>` (D18, D23) | 422 `noDishesFound` (nothing parses; no bucket spent), 429 `rateLimited` |
| `POST /scan` | `ScanRequest {pages: [{mimeType: image/jpeg\|png\|webp\|application/pdf, data: base64}] (1..6), options}`; each page ≤ `VISION_MAX_IMAGE_BYTES` decoded, at most `VISION_MAX_IMAGES` pages (422 otherwise) | 200 `ScannedMenuResponse {menu, analysis}`; `menu.venueRef` is `scan/<fingerprint hex>`; every dish carries its `page` (D22) | **no rules fallback** (D15): the `/v1/chat` statuses and reasons (503 `notConfigured`, 502 `offline`/`badResponse`, 504 `timeout`, 429 `rateLimited`), 422 `noDishesFound` |
| `POST /website-menu` | `WebsiteMenuRequest {url (1..2048), options}` | 200 `WebsiteMenuResponse {menu, analysis \| null}`; `menu.venueRef` is `website/<normalised url>`; `analysis` is null only when the menu has no dish to classify | every `/v1/website/fetch` reason and status above, plus 404 `menuNotFound` (no menu on the site or its one linked page), 502 with the `/v1/scan` reasons when a linked PDF cannot be read |
| `GET /venues/nearby?lat&lon&lang` | the discovery proxy's query rules | 200 `VenuesResponse {venues: [Venue]}`, Wolt's order (the client sorts nearest-first); `X-KetoClub-Cache` | 429 `rateLimited` (discovery bucket), 502 `platformChanged` (non-2xx upstream, 410 included, or a payload the mapper cannot read), 502 `offline`, 504 `timeout` |
| `POST /venues/search` | `VenueSearchRequest {query (1..100, trimmed), lang, lat?, lon? (together or neither)}` | as `/venues/nearby` | as `/venues/nearby` |

Limiters and caches on the D25 routes: `/v1/venue-menus` shares the menu
proxy's per-venue body cache and spends the analysis bucket only for a
Gemini call; `/v1/classify`, `/v1/text-menu` and `/v1/scan` spend only the
analysis bucket (a scan always, since it is never cached); `/v1/website-menu`
spends the website buckets for every fetch and the analysis bucket for a
Gemini call (a linked PDF is read through the `/v1/scan` path); the two
venue routes reuse the discovery routes' cache keys and the discovery bucket.
`/v1/venue-menus` and `/v1/website-menu` upsert `stored_menus` (D24) when
they return an analysis; `/v1/classify`, `/v1/text-menu` and `/v1/scan`
never do — the client's own upload rule covers those.

### 3.4 Install ID and rate limiting

The app generates 16 bytes from `Random.secure()` once per install, stores the
hex in `shared_preferences`, and sends it as `X-KetoClub-Install-Id` (32
lowercase hex; missing or malformed → 400). The backend keeps in-memory
limiters per ID — the chat bucket, the discovery bucket, the website buckets and
(D25) the analysis bucket, §3.3's table — and uses the ID for one-vote-per-install upserts. It is random
and unlinkable to a person, so D8 ("nothing about the user is stored") holds in
spirit. It is spoofable, which is acceptable while the backend is local; #109
revisits abuse posture for a public host.

### 3.5 Privacy and logging

Three kinds of content are ever stored, and never an install ID alongside
any. `chat_cache` holds dish text and model verdicts. Since D25 (#333),
`analysis_cache` holds one complete language-model `MenuAnalysed` per
`sha256(menu fingerprint | model | schemaVersion | netCarbLimitGrams |
constraints)` for `ANALYSIS_CACHE_TTL_SECONDS` (7 days): the verdicts for a
menu's dish text, with the options they were made under and nothing about
who asked. Only an `llm` analysis is written. Since
`architecture.md` D24 (#310), `stored_menus` holds the menus consenting
devices opened: the normalised menu, its analysis without `options` (no
net-carb limit, no dietary toggle), the venue name and city, first/last-seen
times and an upload count — one row per `(source, platform_id)`, keyed by
venue, never by install ID, and with no column that could hold one.
`POST /v1/menus` reads the ID for the rate limiter (the `/v1/chat` bucket) and
deletes it before the store is called. One structured log line per request:
request id, route, status, latency, `install_id[:8]`, upstream status, cache
hit — except on `/v1/menus` and the D25 routes, which log no part of the ID at
all (on those it keys the analysis, discovery or website bucket and nothing
else). Never the server key, an `Authorization` header, an upstream error body,
prompt text, a scanned page's bytes (a page count only) or a website URL
(§10, §11 carried over). `/v1/venue-menus` and `/v1/website-menu` also write
`stored_menus` when they return an analysis, without its `options` and keyed
by venue, so the D24 store fills without the client uploading.

### 3.6 SQLite notes

Sync engine with `connect_args={"check_same_thread": False}`, `PRAGMA
journal_mode=WAL` on connect, a session per request via `Depends`, `create_all`
in the lifespan. Database routes are plain `def` (threadpool); the httpx routes
are `async def`, and the chat-cache write from an async route goes through
`run_in_threadpool`. Tests use `sqlite:///:memory:` with `StaticPool`.

## 4. Client seams (Flutter)

Everything plugs into seams that already exist. Nothing above the adapters
(repository, cache, controllers, screens) changes for the proxy.

1. **Menu proxy** (#96). `WoltMenuAdapter` gains `Uri? proxyBase`; null means
   direct, so every existing call site stays valid. With a proxy the request is
   `proxyBase + /v4/venues/slug/{slug}/menu/data`. Mapping with a proxy:
   `ClientException` → new `MenuFetchFailureReason.backendUnreachable`; 502 and
   504 → `offline` (retry is the way out); `TimeoutException` → `offline`; 404
   → `notFound`; other non-2xx → `platformChanged`. Without a proxy nothing
   changes, `blockedByBrowser` included.
2. **Backend URL** (#96, #99). `const String.fromEnvironment('KETOCLUB_BACKEND_URL')`,
   read only in `lib/di.dart`, which stays synchronous and plugin-free. The
   "proxy or direct" decision is a pure function `menuProxyBase({runsInBrowser,
   configured})` so `di_test` covers it without a dart-define; the proxy is used
   only when both hold. Run the web build with
   `flutter run -d chrome --dart-define=KETOCLUB_BACKEND_URL=http://localhost:8000`.
   A Settings override for LAN testing from a phone is #99.
3. **Hosted classification** (#102). **No fallback chain — corrected from this
   section's original design, which planned a `FallbackChatClient` trying the
   backend and then the user's own OpenRouter key. D12 removed the
   bring-your-own-key path entirely, so there is no secondary client to fall
   back to.** `BackendChatClient implements LlmChatClient` posts to `/v1/chat`
   with an `X-KetoClub-Install-Id` header and no `Authorization` header ever; a
   null `baseUrl` (no `KETOCLUB_BACKEND_URL` configured) answers
   `ChatFailed(notConfigured)` with no I/O. Non-2xx responses map by the
   backend's `reason` name; `ClientException` → `backendUnreachable`;
   `TimeoutException` → `timeout`. `ChatFailureReason` loses `unauthorised`
   (there is no key left to reject) and gains `notConfigured` and
   `backendUnreachable`. `OpenRouterClient` and `KeyStore` are deleted, not kept
   as a fallback.
   `MenuAnalysisFailureReason` loses `unauthorised`, gains `backendUnreachable`
   and `consentWithheld`; both fall back to rules with the reason carried, like
   `offline`.
4. **Router** (#102). `RoutingMenuClassifier` drops its `KeyStore` entirely (not
   just its use as a fallback secondary). Rule 1 is "consent withheld → rules
   stamped `consentWithheld`"; `notConfigured` now means "no backend URL
   compiled in, or the server has no key" and arrives through the LLM-path
   branch that already exists, exactly like every other backend failure reason.
   `di.dart` wires `BackendChatClient(baseUrl: backendBaseUrl(...), ...)`
   directly — no fallback wrapper.
5. **Install ID** (#101). `lib/services/storage/install_id_store.dart`,
   interface + `PrefsInstallIdStore` with the lazy `load` closure copied from
   `PrefsSettingsStore`; generated on first `id()` call, never in a constructor.
   Not added to `AppDependencies`: only the HTTP clients built in `di.dart` use it.
6. **Community** (#108). New models `VenueCommunitySummary` and
   `DishFeedbackSummary` (`Venue` is constructed nowhere in `lib/` today, so its
   rating fields wait for Phase 2 search). `lib/services/community/` with
   interface, `HttpCommunityClient`, fake and contract suite;
   `import_rules_test.dart` gains `community: 0`. `AppDependencies` gains a
   **required** `communityClient`, constructed in `test/fakes/fake_app_dependencies.dart`
   and, with its own same-directory fake, in `integration_test/flows/flow_support.dart`.
7. **Failure copy** (#96, #102 — #104 folded into #102's scope, not done as a
   separate issue). New reasons need distinct strings in both ARB files,
   distinct across both enums (the uniqueness test spans them): fetch
   "KetoClub's server could not be reached, so the menu could not be read." and
   analysis "KetoClub's server could not be reached. Showing rule-based
   results." plus `analysisConsentWithheld`. Regenerate `lib/l10n/generated/`
   with `flutter gen-l10n`. The key-related strings this bullet originally
   flagged as merely needing a reword (`settingsKeyAbsent` and friends) are
   removed outright instead, along with the Settings key section they belonged
   to — there is no key to have a string about.
8. **Boundary test** (#98 — folded into #102's scope, not done as a separate
   issue). §5's single-file rule is now four host-string rules, all enforced by
   `import_rules_test.dart`: `restaurant-api.wolt.com` only in
   `wolt_adapter.dart`, `/v1/chat` only in `backend_chat_client.dart`,
   `KETOCLUB_BACKEND_URL` only in `di.dart`, and `openrouter`, `sk-or-` and
   `googleapis.com` nowhere under `lib/` at all. (D25 adds six more, one per
   complete-result route, each pinned to the one client file that calls it.)
9. **Complete results on every platform (D25, #327–#331).** The Dart side of
   §3.3's routes: `BackendMenuAdapter` (`/v1/venue-menus`, `/v1/website-menu`,
   120 s timeout), `BackendMenuClassifier` (`/v1/classify`),
   `BackendScannedMenuClassifier` (`/v1/scan`) and `BackendVenueSearchService`
   (`/v1/venues/*`), each paired with the engine the app used before in a
   `Fallback*` wrapper that hands over only when the backend could not answer
   (`backendUnreachable`, `timeout`, `rateLimited`, `notConfigured`; for menus
   `backendUnreachable` and `offline`). `di.dart` builds the chains on every
   platform when a URL is configured, behind the routers that check consent and
   connectivity; a `FallbackChatClient` does the same for menu questions.
   `/v1/text-menu` has no client yet. Discovery's quick score reads through
   `estimateMenuRepository` over the direct adapters, so it never spends the
   analysis bucket. This reverses §2's "mobile keeps calling Wolt directly", and item 3's "no
   fallback chain" (true of web only since D17): a phone with a URL now has the
   backend as its primary and its own key as the secondary.

## 5. Milestones, issues and priority

Phase labels are feature groups, not calendar order: the backend keeps the
`Phase 3` label but is scheduled **before** the remaining Phase 2 milestones,
because milestone A is what makes Wolt work on web.

### A — Phase 3: Backend Foundations (target 2026-10-04)

| # | Issue | Priority | Status |
|---|---|---|---|
| #94 | Scaffold the Python backend and the CI job | critical | ✅ shipped |
| #95 | Wolt menu proxy route | critical | ✅ shipped |
| #96 | `WoltMenuAdapter` proxy base; web build routes through the backend | critical | ✅ shipped |
| #97 | Record the decision: D11, D12 and the document reconciliation | high | ✅ shipped (this document) |
| #98 | Enforce the host-string boundaries | medium | folded into #102 |
| #99 | Backend URL override in Settings | low | open |

### B — Phase 3: Hosted Classification (target 2026-10-25)

| # | Issue | Priority | Status |
|---|---|---|---|
| #100 | `POST /v1/chat` with the server key and the strict-schema retry, against Google Gemini | critical | ✅ shipped |
| #101 | Anonymous install ID and per-install rate limit | high | ✅ shipped |
| #102 | `BackendChatClient` replaces `OpenRouterClient` entirely (no BYOK fallback, D12), the router change | critical | ✅ shipped |
| #103 | Server-side completion cache by request hash | high | ✅ shipped |
| #104 | Reword Settings and failure copy for a served model | medium | folded into #102 |

### C — Phase 3: Community API (target 2026-11-15)

| # | Issue | Priority |
|---|---|---|
| #105 | Venue records and the community summary endpoint | high |
| #106 | Ratings and per-dish feedback endpoints | high |
| #107 | Submissions and admin endpoints | medium |
| #108 | `CommunityClient` and `VenueCommunitySummary` in the app | high |
| #109 | Hosting beyond localhost (research) | low |

### D — D25: complete results on every platform (waves 0–4)

| # | Issue | Status |
|---|---|---|
| #318, #319 | Epics: the backend serves complete results; the thin client | ✅ shipped |
| #320 | Golden parity corpus (`tool/golden`, `test/golden`, `backend/tests/fixtures/golden/`) and the surrogate-pair fix | ✅ shipped |
| #321 | Route contracts, wire models, Venue codec, boundary pins, this document's §3.3 | ✅ shipped |
| #322–#326 | The Python port: normaliser and fingerprint, mappers, rules and heuristic, prompt and parser, text menu and website locator | ✅ shipped |
| #327–#329 | `BackendMenuAdapter`, the backend and fallback classifiers, `BackendVenueSearchService` | ✅ shipped |
| #330 | Disclosure copy branches on backend configuration | ✅ shipped |
| #331 | `di.dart` wiring, estimate repository, upload skip, backend flow tests | ✅ shipped (flows proven under `flutter-tester` only) |
| #332 | This documentation pass | ✅ shipped |
| #333–#335 | The routes: analysis cache and `/v1/classify`, `/v1/venue-menus`, `/v1/text-menu`; `/v1/scan` and `/v1/website-menu`; `/v1/venues/*` | ✅ shipped |

### Build order

1. **#94 → #95 → #96.** ✅ Done. `flutter run -d chrome` with the define shows a
   live Wolt menu.
2. **#100 → #101 → #102** (#98 and #104 folded into #102). ✅ Done. Web and
   mobile users never enter a key at all.
3. **#103.** ✅ Done. Shared cache.
4. **#97.** ✅ Done — this document.
5. **#105, #106, #108, then #107.** Community data, which unblocks the existing
   Phase 3 UI issues #74–#80. Still open.
6. **#99, #109.** Still open.
7. Then the existing Phase 2 milestones resume unchanged.

Dependency edges are recorded on each issue ("Blocked by" / "Blocks").

## 6. Verification, end to end

```
cd backend && uv run uvicorn app.main:app --reload --port 8000
flutter run -d chrome --dart-define=KETOCLUB_BACKEND_URL=http://localhost:8000
```

Paste a Wolt link: the menu loads and is classified with the "AI" chip — there
is no key to enter anywhere (D12; milestone B shipped this). Stop the backend:
the fetch shows "KetoClub's server could not be reached, so the menu could not
be read", and a fresh classification falls back to rules with the
`backendUnreachable` reason. There is no user-key path to fall back to instead
— that design was superseded by D12 before it was built. `backend/README.md`'s
manual end-to-end check has the full walkthrough with exact commands.
`backend/check.sh` and `tool/check.sh` are both green, and a web-proxy flow
test under `integration_test/flows/` runs with the adapter faked.

## 7. Superseded issues

#67 (decide proxy now or later), #70 (backend options), #71 (deploy a CORS
proxy), #72 (shared analysis cache) and #73 (community client, `Venue` rating
fields) were closed on 2026-09-13 with a comment each pointing here. Milestone
#10 "Phase 3: Backend Infrastructure" is closed.
