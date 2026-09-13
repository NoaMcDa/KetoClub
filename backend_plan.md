# KetoClub backend — plan, API contract and prioritisation

> **Status: milestone A is built; B and C are not.** Decided 2026-09-13. The issues
> are #94–#109 in three milestones: *Phase 3: Backend Foundations* (#94–#99, built),
> *Phase 3: Hosted Classification* (#100–#104) and *Phase 3: Community API*
> (#105–#109).
>
> **`architecture.md` is authoritative**, as always: D11 records the decision and §13
> describes what shipped. This document is the fuller design the issues cite. Where
> the two disagree about what exists, believe `architecture.md`; where this one
> describes something unbuilt, it is a plan, not a claim.

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
| Model owner | The backend holds one OpenRouter key. The user's own key (BYOK, D3) stays as the fallback; the on-device rules engine stays as the last fallback |
| Identity | Anonymous per-install ID sent as a header. No accounts, no login |
| Old issues | #67, #70–#73 closed; this plan replaces them |

**Principle: the backend is an accelerator, never a dependency.** With no
backend URL the app behaves exactly as it does today, including the web build's
paste path. The backend is deliberately dumb: it forwards, holds a key, caches
and stores community data. It does **not** normalise Wolt JSON, build prompts
or parse model replies. Those stay in Dart, where they are already tested,
so nothing is duplicated in Python. D10 extends to the backend: the call is the
probe, and the client never pre-checks whether the server is up.

## 3. Backend service (`backend/`)

### 3.1 Tooling and layout

- Python ≥ 3.11, FastAPI, uvicorn, httpx, SQLAlchemy 2, pydantic-settings.
- `uv` for the lockfile and virtualenv (`uv.lock` committed), ruff for lint and
  format, mypy strict, pytest with pytest-cov and an 80% floor, respx to fake
  Wolt and OpenRouter. No test makes a network call (constraint 12 applies).
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
│   └── services/        # wolt, openrouter, cache, rate_limit, install_id
└── tests/               # conftest: app over in-memory SQLite (StaticPool) + respx router
```

### 3.2 Configuration (`.env`)

| Variable | Default | Meaning |
|---|---|---|
| `OPENROUTER_API_KEY` | unset | The server's key. Unset means `/v1/chat` answers `notConfigured` |
| `OPENROUTER_MODEL` | the pinned id in `open_router_client.dart` | Model requested upstream |
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

**`POST /chat`** — the hosted-key endpoint. The body mirrors
`LlmChatClient.complete` one to one: `{system_prompt, user_prompt,
response_schema?, schema_name?}`, with `max_length` bounds (422). Any inbound
`Authorization` header is rejected with 400.
- Forwarded with `Authorization: Bearer <server key>`, `HTTP-Referer` and
  `X-Title` as the Dart client sends them, model from config, read timeout 110 s
  (the Dart client's 120 s is the outer bound).
- Same retry rule as `OpenRouterClient`: strict `json_schema` first; on 400, 404
  or 422 exactly one re-send with `response_format: json_object`; 401, 403, 429
  and 5xx are never retried (§9.3).
- 200 → `{content, model}`, `model` from the upstream reply.
- Errors → `{reason, status_code}` with `reason` a `ChatFailureReason` name:

| Status | `reason` | When |
|---|---|---|
| 503 | `notConfigured` | No server key, **or** upstream 401/403. Never `unauthorised`: that client copy says "*your* key was rejected" |
| 502 | `offline` | Upstream connect error |
| 504 | `timeout` | Upstream read timeout |
| 429 | `rateLimited` | Upstream 429, or the per-install limit |
| 502 | `badResponse` | Any other upstream status, or an unusable body |

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
3. **Hosted classification** (#102). `BackendChatClient implements LlmChatClient`
   posts to `/v1/chat`; `FallbackChatClient(primary, secondary)` tries the
   backend, then the user's key: on primary `backendUnreachable`,
   `notConfigured` or `rateLimited` it tries the secondary, and if the secondary
   answers `notConfigured` (no user key) it returns the primary's failure so the
   user reads "server unreachable" rather than "add a key", unless the primary's
   own failure was `notConfigured`. `timeout`, `badResponse` and `unauthorised`
   from the primary return as-is. Neither client needs a `KeyStore` beyond what
   `OpenRouterClient` already holds.
   `ChatFailureReason` gains `notConfigured` and `backendUnreachable`;
   `OpenRouterClient` with no stored key answers `notConfigured` (it answered
   `unauthorised`, unreachable in practice because the router pre-checked).
   `MenuAnalysisFailureReason` gains `backendUnreachable`, which falls back to
   rules with the reason carried, like `offline`.
4. **Router** (#102). `RoutingMenuClassifier` drops its `KeyStore`. Rule 1 is
   only "no consent → rules stamped `notConfigured`"; `notConfigured` from the
   LLM path arrives through the branch that already exists. Credentials live
   inside `LlmChatClient` implementations, which is what §6.2 already claims.
   `di.dart` wires `url.isEmpty ? OpenRouterClient : FallbackChatClient(BackendChatClient, OpenRouterClient)`.
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
7. **Failure copy** (#96, #102, #104). New reasons need distinct strings in both
   ARB files, distinct across both enums (the uniqueness test spans them): fetch
   "KetoClub's server could not be reached, so the menu could not be read." and
   analysis "KetoClub's server could not be reached. Showing rule-based
   results." Regenerate `lib/l10n/generated/` with `flutter gen-l10n`. Three
   strings become false with a backend and are reworded in #104:
   `settingsKeyAbsent`, `settingsConsentBody` ("there is no other server"),
   `analysisRateLimited` ("for this key").
8. **Boundary test** (#98). §5 says `openrouter.ai` appears in one file only;
   nothing enforces it. `import_rules_test.dart` gains that check, and the same
   for `restaurant-api.wolt.com`.

## 5. Milestones, issues and priority

Phase labels are feature groups, not calendar order: the backend keeps the
`Phase 3` label but is scheduled **before** the remaining Phase 2 milestones,
because milestone A is what makes Wolt work on web.

### A — Phase 3: Backend Foundations (target 2026-10-04)

| # | Issue | Priority |
|---|---|---|
| #94 | ✅ Scaffold the Python backend and the CI job | critical |
| #95 | ✅ Wolt menu proxy route | critical |
| #96 | ✅ `WoltMenuAdapter` proxy base; web build routes through the backend | critical |
| #97 | Record the decision: D11 and the document reconciliation | high |
| #98 | Enforce the `openrouter.ai` single-file boundary | medium |
| #99 | Backend URL override in Settings | low |

### B — Phase 3: Hosted Classification (target 2026-10-25)

| # | Issue | Priority |
|---|---|---|
| #100 | `POST /v1/chat` with the server key and the strict-schema retry | critical |
| #101 | Anonymous install ID and per-install rate limit | high |
| #102 | `BackendChatClient`, the BYOK fallback chain, the router change | critical |
| #103 | Server-side completion cache by request hash | high |
| #104 | Reword Settings and failure copy for a served model | medium |

### C — Phase 3: Community API (target 2026-11-15)

| # | Issue | Priority |
|---|---|---|
| #105 | Venue records and the community summary endpoint | high |
| #106 | Ratings and per-dish feedback endpoints | high |
| #107 | Submissions and admin endpoints | medium |
| #108 | `CommunityClient` and `VenueCommunitySummary` in the app | high |
| #109 | Hosting beyond localhost (research) | low |

### Build order

1. **#94 → #95 → #96.** After these, `flutter run -d chrome` with the define
   shows a live Wolt menu. That is the stated goal.
2. **#97, #98.** The decision record and the boundary test before more backend
   code lands.
3. **#100 → #101 → #102.** Web users no longer paste a key.
4. **#103, #104.** Shared cache; honest copy.
5. **#105, #106, #108, then #107.** Community data, which unblocks the existing
   Phase 3 UI issues #74–#80.
6. **#99, #109.**
7. Then the existing Phase 2 milestones resume unchanged.

Dependency edges are recorded on each issue ("Blocked by" / "Blocks").

## 6. Verification, end to end

```
cd backend && uv run uvicorn app.main:app --reload --port 8000
flutter run -d chrome --dart-define=KETOCLUB_BACKEND_URL=http://localhost:8000
```

Paste a Wolt link: the menu loads and is classified with the "AI" chip and no
key entered (after milestone B). Stop the backend: the fetch shows "KetoClub's
server could not be reached"; with a key entered, classification still works
through the user's key; with none, rules. `backend/check.sh` and `tool/check.sh`
are both green, and a web-proxy flow test under `integration_test/flows/` runs
with the adapter faked.

## 7. Superseded issues

#67 (decide proxy now or later), #70 (backend options), #71 (deploy a CORS
proxy), #72 (shared analysis cache) and #73 (community client, `Venue` rating
fields) were closed on 2026-09-13 with a comment each pointing here. Milestone
#10 "Phase 3: Backend Infrastructure" is closed.
