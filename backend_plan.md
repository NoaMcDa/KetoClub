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
> app D1 first described. **This document's design is now largely history**:
> `architecture.md` is authoritative (D11, D12 in §14) and this plan is kept
> for the reasoning and the milestone/issue breakdown, corrected below where it
> named OpenRouter or a bring-your-own-key path that no longer exists.
> **2026-09-24 (`ROADMAP.md`, D18):** milestone C (#105–#108) was closed as
> not planned — its per-install upserts contradicted D8/§11 and it had no
> population without a host; #164 carries the re-plan. Hosting (#109) is now
> the Phase 5 entry point with #171–#175 as the work. Since this document was
> written the backend also gained a 10bis menu proxy (#126) and two Wolt
> discovery proxy routes (#149), so "the only proxy route" in §3.3 is stale.

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
| Routing | The **web** build fetches menus through the backend. **Mobile keeps calling Wolt directly**; the backend URL is simply not defined in mobile builds |
| Model owner | **Decided (D12), supersedes the row below as originally written.** The backend holds one Google Gemini key. There is no bring-your-own-key fallback: the app never holds a model key at all, `KeyStore` and `flutter_secure_storage` are removed, and the on-device rules engine is the only fallback, reached through the router exactly as it always was for every other failure reason |
| ~~Model owner (original)~~ | ~~The backend holds one OpenRouter key. The user's own key (BYOK, D3) stays as the fallback; the on-device rules engine stays as the last fallback~~ — superseded by D12 before #100 was built; struck through rather than deleted so the decision that was reversed stays visible |
| Identity | Anonymous per-install ID sent as a header. No accounts, no login |
| Old issues | #67, #70–#73 closed; this plan replaces them |

**Principle: the backend is an accelerator, never a dependency.** With no
backend URL the app behaves exactly as it does today, including the web build's
paste path. The backend is deliberately dumb: it forwards, holds a key, caches
and stores community data. It does **not** normalise Wolt JSON, build prompts
or parse model replies. Those stay in Dart, where 1418 tests already cover them,
so nothing is duplicated in Python. D10 extends to the backend: the call is the
probe, and the client never pre-checks whether the server is up.

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
│   ├── routers/         # health, proxy, chat, venues, submissions, admin
│   └── services/        # wolt, gemini, cache, rate_limit, install_id
└── tests/               # conftest: app over in-memory SQLite (StaticPool) + respx router
```

### 3.2 Configuration (`.env`)

| Variable | Default | Meaning |
|---|---|---|
| `GEMINI_API_KEY` | unset | The server's key, sent only as `x-goog-api-key`. Unset means `/v1/chat` answers `notConfigured` (superseded `OPENROUTER_API_KEY`, D12) |
| `GEMINI_MODEL` | `gemini-2.5-flash` | Model requested at `generateContent` (superseded `OPENROUTER_MODEL`) |
| `GEMINI_BASE_URL` | `https://generativelanguage.googleapis.com` | Upstream host; never taken from a request |
| `GEMINI_MAX_OUTPUT_TOKENS` | `8192` | `generationConfig.maxOutputTokens` |
| `GEMINI_THINKING_BUDGET` | `0` | Thinking tokens count against the output budget, and this is a classification task |
| `WOLT_BASE_URL` | `https://restaurant-api.wolt.com` | Upstream host for the proxy; never taken from a request |
| `DATABASE_URL` | `sqlite:///./ketoclub.db` | Postgres is an env-var swap later; Alembic arrives with it |
| `CORS_ORIGIN_REGEX` | `^https?://(localhost\|127\.0\.0\.1)(:\d+)?$` | Flutter's dev server picks a random port |
| `ADMIN_TOKEN` | unset | Required by `/v1/admin/*`; unset means 503 |
| `MENU_CACHE_TTL_SECONDS` | 3600 | Raw Wolt body cache |
| `CHAT_CACHE_TTL_SECONDS` | 86400 | Equal to the app's `menuCacheTtl` |
| `RATE_LIMIT_PER_MINUTE`, `RATE_LIMIT_PER_DAY` | 5, 40 | Per install ID, on `/v1/chat` and the write endpoints |

CORS: `allow_origin_regex` from config, `allow_methods=[GET, POST]`,
`allow_headers=[Content-Type, Accept, X-KetoClub-Install-Id]`, no credentials.
The custom header forces a preflight; the middleware answers it.

### 3.3 API contract (all under `/v1`)

**`GET /health`** → `{status, version, llm_configured}`.

**`GET /proxy/wolt/v4/venues/slug/{slug}/menu/data`** — the only proxy route.
- `slug` must match `^[a-z0-9][a-z0-9-]{0,99}$`, else 422.
- Upstream request headers are built from scratch: `User-Agent` equal to the
  Dart `browserUserAgent` (duplicated on purpose, because a browser cannot set
  it; both sides carry a comment) and `Accept: application/json`. Nothing from
  the browser (`Origin`, `Cookie`, `Authorization`, the install ID) is forwarded.
- **Transparent passthrough**: Wolt's status, body and `Content-Type` come back
  unchanged, 404 included. The Dart adapter's mapping (404 → `notFound`, other
  non-2xx → `platformChanged` with the status) therefore needs no change.
- Proxy-originated statuses are exactly two: 502 (Wolt unreachable) and 504
  (Wolt timed out), both with a `{reason, status_code}` body. httpx timeouts:
  connect 5 s, read 15 s.
- 2xx bodies are cached per slug for `MENU_CACHE_TTL_SECONDS`; the response
  carries `X-KetoClub-Cache: hit|miss`. Failures are never cached.

**`POST /chat`** — the hosted-key endpoint, **built against Google Gemini, not
OpenRouter (D12 — this whole section was written before that decision and is
corrected here)**. The body mirrors `LlmChatClient.complete` one to one:
`{system_prompt, user_prompt, response_schema?, schema_name?}`, with
`max_length` bounds (422). Any inbound `Authorization` header is rejected with
400: the server holds the only key there is, and the client never sends one.
- Forwarded as `POST {GEMINI_BASE_URL}/v1beta/models/{GEMINI_MODEL}
  :generateContent` with header `x-goog-api-key` (never a `?key=` query
  parameter), `generationConfig.maxOutputTokens` and `.thinkingConfig
  .thinkingBudget` from config, `temperature: 0`; read timeout 110 s (the Dart
  client's 120 s is the outer bound).
- Retry rule: strict `responseSchema` first; on an upstream 400 whose error body
  is **not** `API_KEY_INVALID`, exactly one re-send with `responseMimeType`
  only and no schema; 401, 403, 429 and 5xx are never retried (§9.3). The JSON
  schema Dart sends is converted to Gemini's `responseSchema` subset by a pure
  `to_gemini_schema` function before either attempt.
- 200 → `{content, model}`, `model` from the upstream `modelVersion`, else the
  configured `GEMINI_MODEL`.
- Errors → `{reason, status_code}` with `reason` a `ChatFailureReason` name:

| Status | `reason` | When |
|---|---|---|
| 503 | `notConfigured` | No server key, or upstream 400 `API_KEY_INVALID`/401/403. There is no `unauthorised` reason — a rejected server key is the operator's problem, not something client copy can tell the user to fix |
| 502 | `offline` | Upstream connect error |
| 504 | `timeout` | Upstream read timeout |
| 429 | `rateLimited` | Upstream 429, or the per-install limit |
| 502 | `badResponse` | Any other upstream status, a non-`STOP` finish reason, or an unusable body |

- **Shared cache** (`feature_prioratization` Tier D, for free): key = sha256 of
  canonical JSON `{model, system_prompt, user_prompt, response_schema,
  schema_name}`. Identical menus produce identical prompts, so one completion
  serves every user of that venue. Only 200s are cached, for
  `CHAT_CACHE_TTL_SECONDS`; hits bypass the rate limiter and carry
  `X-KetoClub-Cache: hit`.

**Community endpoints**

| Endpoint | Body / reply |
|---|---|
| `GET /venues/{source}/{platform_id}` | 200 `{keto_rating_score: float\|null, rating_count, is_verified_keto_friendly, dish_feedback: {dish_id: {accepted, rejected}}}`. Unknown venue → 200 with the empty summary; the client needs no `notFound` branch |
| `POST /venues/{source}/{platform_id}/rating` | `{score: 1..5}`; upsert on `(source, platform_id, install_id)` |
| `POST /venues/{source}/{platform_id}/feedback` | `{dish_id, dish_name, accepted}`; upsert on `(source, platform_id, dish_id, install_id)`. Keyed by the platform dish id (stable per venue); `dish_name` is display only |
| `POST /submissions` | `{name, address?, link}` → 201 `pending`; duplicate link → 409 |
| `GET /admin/submissions?status=`, `POST /admin/submissions/{id}/approve`, `…/reject`, `POST /admin/venues/{source}/{platform_id}/verify` | `X-Admin-Token`, compared with `secrets.compare_digest`. A curl cookbook in `backend/README.md` is the admin UI while the backend is local |

`source` is validated against `wolt|tenbis|tabit|ontopo` everywhere.

### 3.4 Install ID and rate limiting

The app generates 16 bytes from `Random.secure()` once per install, stores the
hex in `shared_preferences`, and sends it as `X-KetoClub-Install-Id` (32
lowercase hex; missing or malformed → 400). The backend keeps an in-memory
limiter per ID and uses the ID for one-vote-per-install upserts. It is random
and unlinkable to a person, so D8 ("nothing about the user is stored") holds in
spirit. It is spoofable, which is acceptable while the backend is local; #109
revisits abuse posture for a public host.

### 3.5 Privacy and logging

Only dish text and model verdicts are ever stored (in `chat_cache`), never an
install ID alongside them. One structured log line per request: request id,
route, status, latency, `install_id[:8]`, upstream status, cache hit. Never the
server key, an `Authorization` header, an upstream error body or prompt text
(§10, §11 carried over).

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
   `googleapis.com` nowhere under `lib/` at all.

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
