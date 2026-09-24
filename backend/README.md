# KetoClub backend

A small FastAPI service that makes live Wolt menus work in the web build.
`restaurant-api.wolt.com` sends no CORS headers, so a browser refuses the
request before it leaves; this service forwards it (`backend_plan.md` §1).

**The backend is an accelerator, never a dependency.** With no backend URL
configured, the app behaves exactly as it does without one, including the
web build's paste-a-link path.

Routes shipped so far:

| Route | Issue | What it does |
|---|---|---|
| `GET /v1/health` | #94 | `{status, version, llm_configured}` |
| `GET /v1/proxy/wolt/v4/venues/slug/{slug}/menu/data` | #95 | The Wolt menu proxy for the web build, see below |
| `GET /v1/proxy/tenbis/api/v1.0/Restaurants/{restaurantId}/Menu` | #122 | The 10bis menu proxy for the web build, see below |
| `POST /v1/chat` | #100 | Hosted classification: forwards one completion to Gemini `generateContent` with the server's key |
| `GET /v1/proxy/wolt/pages/restaurants` | #123 | Nearby-venue search for the web build, see below |
| `POST /v1/proxy/wolt/pages/search` | #123 | By-name venue search for the web build, see below |

Community routes are later issues (`backend_plan.md` §5).

### `POST /v1/chat`

Body `{system_prompt, user_prompt, response_schema?, schema_name?}`, the
Dart `LlmChatClient.complete` parameters one to one; `200` answers
`{content, model}`. Every request needs `X-KetoClub-Install-Id` (32 lowercase
hex characters) and must **not** carry `Authorization`: the server holds the
key. `response_schema` is a strict JSON schema; the backend converts it to
Gemini's `responseSchema` subset (no `additionalProperties`, `nullable`
instead of `["T", "null"]`). A 400 on a schema-carrying request is re-sent
once without the schema, unless it is an invalid key.

Every error the route originates is `{reason, status_code}`:

| Status | `reason` | When |
|---|---|---|
| 400 | `badResponse` | Missing or malformed install id, or an inbound `Authorization` header |
| 429 | `rateLimited` | Over `RATE_LIMIT_PER_MINUTE` / `RATE_LIMIT_PER_DAY` for this install, or Gemini answered 429 |
| 502 | `offline` | Gemini unreachable |
| 502 | `badResponse` | Any other upstream status, or a reply with no usable text (`finishReason` not `STOP`, no candidates, not JSON) |
| 503 | `notConfigured` | No `GEMINI_API_KEY`, or Gemini rejected it (400 `API_KEY_INVALID`, 401, 403) |
| 504 | `timeout` | Gemini did not answer within 110 s |

A body that fails validation (empty prompt, prompt over its bound) is
FastAPI's own 422. Logs carry the install id's first 8 characters, the
`cache=hit|miss` outcome and upstream status codes only: never the key,
prompt text or an upstream body.

#### The shared completion cache (#103)

Identical menus produce identical prompts, so a completion is cached
server-side by request hash and served to every caller who asks the same
question — the free-tier quota (D6, 50 requests a day in the app's own
router) goes much further this way.

- **Key**: sha256 of the canonical JSON (sorted keys, no whitespace) of
  `{model, system_prompt, user_prompt, response_schema, schema_name}`,
  using the server's own `GEMINI_MODEL`. The key is stable across dict key
  order, including inside a nested `response_schema`.
- **Lookup order**: the cache is checked first — before the Authorization
  rejection's sibling checks have any cost, before the rate limiter and
  before the "no key configured" check. A hit answers directly and spends
  no install quota; a miss falls through to the limiter and then Gemini as
  before.
- **TTL**: `CHAT_CACHE_TTL_SECONDS` (default 86400, matching the app's own
  `menuCacheTtl`). A row older than the TTL is a miss and is replaced.
- **What is cached**: only a successful (200) completion — `content` and
  `model`, exactly what `ChatResponse` holds. A `BackendError` (any failure
  reason) is never cached. The stored row holds no install id and no
  install-identifying data at all; the cache serves every install
  identically once warm.
- **Header**: every `/v1/chat` response carries `X-KetoClub-Cache: hit` or
  `miss`, exposed to browser JS via CORS `expose_headers`.

## The Wolt menu proxy

`GET /v1/proxy/wolt/v4/venues/slug/{slug}/menu/data` forwards to
`{WOLT_BASE_URL}/v4/venues/slug/{slug}/menu/data` and returns Wolt's status,
body and `Content-Type` unchanged, 404 included — the Dart adapter's status
mapping needs no change whether it talks to Wolt directly or through this
proxy. It is the **only** proxy route: the upstream host always comes from
`WOLT_BASE_URL` in config, never from the request.

- `slug` is validated against `^[a-z0-9][a-z0-9-]{0,99}$`; anything else is
  422 before any upstream call is made.
- Upstream request headers are built from scratch (`User-Agent`, `Accept`)
  — nothing from the inbound request (`Origin`, `Cookie`, `Authorization`,
  the install id) is forwarded.
- A connect failure is 502 (`{"reason": "offline", ...}`); an upstream
  timeout is 504 (`{"reason": "timeout", ...}`).
- 2xx responses are cached per slug for `MENU_CACHE_TTL_SECONDS`; the
  response carries `X-KetoClub-Cache: hit` or `miss`. Failures are never
  cached.

The synthetic Wolt fixture used in `lib/` tests has never been recorded from
a real venue (issue #22); this proxy can do that from a machine that can
reach `restaurant-api.wolt.com` (the sandbox this backend was built in
cannot):

```bash
curl -sS localhost:8000/v1/proxy/wolt/v4/venues/slug/vitrina-lilinblum/menu/data \
  -o test/fixtures/wolt_vitrina_lilinblum_menu.json
```

## The 10bis menu proxy

`GET /v1/proxy/tenbis/api/v1.0/Restaurants/{restaurantId}/Menu` forwards to
`{TENBIS_BASE_URL}/api/v1.0/Restaurants/{restaurantId}/Menu` and returns
10bis's status, body and `Content-Type` unchanged, 404 included — shaped
exactly like the Wolt proxy above (issue #122). The upstream host always
comes from `TENBIS_BASE_URL` in config, never from the request.

- `restaurantId` is validated against `^[0-9]{1,12}$`; anything else is 422
  before any upstream call is made.
- Upstream request headers are built from scratch (`User-Agent`, `Accept`)
  — nothing from the inbound request is forwarded, the same rule as Wolt's.
- A connect failure is 502 (`{"reason": "offline", ...}`); an upstream
  timeout is 504 (`{"reason": "timeout", ...}`).
- 2xx responses are cached per restaurant id for `MENU_CACHE_TTL_SECONDS`;
  the response carries `X-KetoClub-Cache: hit` or `miss`. Failures are
  never cached. The cache table is shared with the Wolt proxy but keyed by
  `(source, id)`, so a Wolt slug and a 10bis id that happen to be the same
  string never collide.

The synthetic 10bis fixture used in `lib/` tests has never been recorded
from a real restaurant (issue #44); this proxy can do that from a machine
that can reach `www.10bis.co.il` (the sandbox this backend was built in
cannot):

```bash
curl -sS localhost:8000/v1/proxy/tenbis/api/v1.0/Restaurants/{restaurantId}/Menu \
  -o test/fixtures/tenbis_{id}_menu.json
```

## The Wolt venue-discovery proxies

`GET /v1/proxy/wolt/pages/restaurants?lat=&lon=&lang=` and
`POST /v1/proxy/wolt/pages/search` are the two routes the Discovery screen
uses on the web build (#123): Wolt's "pages" endpoints are unofficial,
origin-locked to `https://wolt.com` and are reported to answer 410 without
the full web-client header set
(`phase2_discovery_research.md` §2.2, §2.3). Both are literal allow-list
entries, forwarding only the parameters below — no wildcard passthrough.

- `GET` forwards to `{WOLT_CONSUMER_BASE_URL}/v1/pages/restaurants?lat=&lon=`.
  `lat` (`-90..90`) and `lon` (`-180..180`) are required floats; `lang` is
  `en` or `he` (default `en`). Any value outside those bounds is 422 before
  any upstream call is made.
- `POST` takes `{"q", "lat", "lon", "lang"}` and forwards to
  `{WOLT_BASE_URL}/v1/pages/search` as `{"q", "target": "venues", "lat",
  "lon"}` — `target` is fixed here, never taken from the client. `q` is
  trimmed and must be 1–80 characters after trimming; `lat`/`lon`/`lang`
  share the `GET` route's bounds.
- Upstream request headers are the Wolt web-client identity, built from
  scratch every call (`platform: Web`, `client-version` and
  `clientversionnumber` from `WOLT_CLIENT_VERSION`, `app-language` from
  `lang`, a per-process `x-wolt-web-clientid` uuid4 generated once at
  startup — never the KetoClub install id — `w-wolt-session-id:
  no-analytics-consent`, `Accept`, `User-Agent`). Nothing from the inbound
  request (`Origin`, `Cookie`, `Authorization`, the install id) is
  forwarded, the same rule as the menu proxies.
- Wolt's status, body and `Content-Type` come back unchanged, 410 included.
  A connect failure is 502 (`{"reason": "offline", ...}`); an upstream
  timeout is 504 (`{"reason": "timeout", ...}`).
- 2xx responses are cached for `DISCOVERY_CACHE_TTL_SECONDS` (default 300 s,
  shorter than the menu proxy's), keyed on the canonical query
  (`{lat},{lon},{lang}` or `{q lowercased},{lat},{lon},{lang}`); the
  response carries `X-KetoClub-Cache: hit|miss`. Failures are never cached.
- Every request needs `X-KetoClub-Install-Id`, the same rule as `/v1/chat`;
  missing or malformed is 400 `badResponse`. Each install is limited to
  `DISCOVERY_RATE_LIMIT_PER_MINUTE` (default 20, no daily cap) across both
  routes — a cache hit never spends the quota.

```bash
curl -sS 'localhost:8000/v1/proxy/wolt/pages/restaurants?lat=32.07&lon=34.77&lang=en' \
  -H 'X-KetoClub-Install-Id: 0123456789abcdef0123456789abcdef'

curl -sS localhost:8000/v1/proxy/wolt/pages/search \
  -H 'Content-Type: application/json' \
  -H 'X-KetoClub-Install-Id: 0123456789abcdef0123456789abcdef' \
  -d '{"q": "vitrina", "lat": 32.07, "lon": 34.77, "lang": "en"}'
```

## Running locally

```bash
cd backend
uv sync
uv run uvicorn app.main:app --reload --port 8000
curl http://localhost:8000/v1/health
# {"status":"ok","version":"0.1.0","llm_configured":false}
```

Point the Flutter web build at it:

```bash
flutter run -d chrome --dart-define=KETOCLUB_BACKEND_URL=http://localhost:8000
```

From an **Android emulator**, `localhost` on the host machine is not
reachable from the guest; use the emulator's host alias instead:

```bash
flutter run --dart-define=KETOCLUB_BACKEND_URL=http://10.0.2.2:8000
```

iOS simulators and physical devices are unaffected — see `backend_plan.md`
§4 for the client-side wiring once the proxy route lands.

## Configuration

Copy `.env.example` to `.env` and fill in values; every variable has a safe
default except `GEMINI_API_KEY` and `ADMIN_TOKEN`, which gate the routes
that need them (`/v1/chat`, and `/v1/admin/*` in a later issue). See
`.env.example` for the full list with defaults and descriptions.

| Variable | Default | Meaning |
|---|---|---|
| `GEMINI_API_KEY` | unset | The server's key, sent only as `x-goog-api-key`. Unset → `/v1/chat` answers `notConfigured` |
| `GEMINI_MODEL` | `gemini-2.5-flash` | Model in the `generateContent` path |
| `GEMINI_BASE_URL` | `https://generativelanguage.googleapis.com` | Upstream host; never taken from a request |
| `GEMINI_MAX_OUTPUT_TOKENS` | `8192` | `generationConfig.maxOutputTokens` |
| `GEMINI_THINKING_BUDGET` | `0` | Thinking tokens count against the output budget, and this is a classification task |
| `RATE_LIMIT_PER_MINUTE`, `RATE_LIMIT_PER_DAY` | `5`, `40` | Per install id on `/v1/chat`, in memory |
| `WOLT_BASE_URL` | `https://restaurant-api.wolt.com` | Upstream host for the Wolt menu proxy and the by-name discovery route; never taken from a request |
| `TENBIS_BASE_URL` | `https://www.10bis.co.il` | Upstream host for the 10bis proxy; never taken from a request |
| `WOLT_CONSUMER_BASE_URL` | `https://consumer-api.wolt.com` | Upstream host for the nearby-venue discovery route; never taken from a request |
| `WOLT_CLIENT_VERSION` | `1.16.125` | Wolt web-client version sent on discovery requests |
| `DISCOVERY_CACHE_TTL_SECONDS` | `300` | Discovery response cache TTL |
| `DISCOVERY_RATE_LIMIT_PER_MINUTE` | `20` | Per install id, across both discovery routes; no daily cap |

## Smoke test against the real API

`generativelanguage.googleapis.com` is unreachable from the sandbox and CI,
so every test mocks it; this is the one way to see a real completion. With
`GEMINI_API_KEY` set in `.env` and the server running:

```bash
curl -sS localhost:8000/v1/chat \
  -H 'Content-Type: application/json' \
  -H 'X-KetoClub-Install-Id: 0123456789abcdef0123456789abcdef' \
  -d '{
    "system_prompt": "You are a keto-diet menu analyst. Classify every dish as orderAsIs, modifiable or nonKeto. A modifiable dish names the swap in modification; otherwise modification is null.",
    "user_prompt": "1 | Mains | Entrecote | 300g steak with fries\n2 | Mains | Pasta | Spaghetti with tomato sauce",
    "response_schema": {
      "type": "object",
      "additionalProperties": false,
      "required": ["dishes"],
      "properties": {
        "dishes": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["id", "verdict", "modification"],
            "properties": {
              "id": {"type": "string"},
              "verdict": {"type": "string", "enum": ["orderAsIs", "modifiable", "nonKeto"]},
              "modification": {"type": ["string", "null"]}
            }
          }
        }
      }
    },
    "schema_name": "menu_analysis"
  }'
# {"content":"{\"dishes\": [...]}","model":"gemini-2.5-flash"}
```

The default limit is 5 requests a minute per install id; change the id to
keep going, or raise `RATE_LIMIT_PER_MINUTE`.

## The gate

```bash
backend/check.sh
```

Runs exactly what the CI `backend` job runs: `uv sync --frozen`, `ruff
check`, `ruff format --check`, `mypy app` (strict), then `pytest
--cov=app --cov-fail-under=80`. It is a required check on every pull
request, independent of whether the PR touches `backend/` — see
`architecture.md` §18.5 for why a path-filtered required check is worse than
an always-green one.

## Tests

`uv run pytest` runs the suite over an in-memory SQLite database
(`sqlite:///:memory:`, `StaticPool`) with respx blocking any real network
call — no test in this suite ever reaches the network
(`architecture.md` constraint 12).

## Manual end-to-end check

Every automated test above mocks Wolt and Gemini, because neither is reachable
from this repository's build environment. This is the one way to confirm the
whole path really works, from a machine that has a real network: linked from
`README.md` and `HANDOFF.md` as *the* place this check lives, so it is written
once.

1. **Set a real key.** `cp .env.example .env` (if not already done) and set
   `GEMINI_API_KEY` to a real Google Gemini API key.
2. **Start the backend.**
   ```bash
   cd backend
   uv sync
   uv run uvicorn app.main:app --reload --port 8000
   ```
3. **Health check.**
   ```bash
   curl -sS localhost:8000/v1/health
   # {"status":"ok","version":"0.1.0","llm_configured":true}
   ```
   `llm_configured` must read `true` — if it reads `false`, `GEMINI_API_KEY`
   was not picked up (check `.env` is in `backend/`, not the repository root).
4. **Proxy check**, against a real Wolt venue slug:
   ```bash
   curl -sS localhost:8000/v1/proxy/wolt/v4/venues/slug/vitrina-lilinblum/menu/data \
     -D - -o /dev/null
   # HTTP/1.1 200 OK
   # x-ketoclub-cache: miss
   ```
   Run it again: the second response carries `x-ketoclub-cache: hit`.
5. **Chat smoke test.** Use the curl in "Smoke test against the real API"
   above. A real completion comes back as `{"content":"{\"dishes\": [...]}",
   "model":"gemini-2.5-flash"}` (or whatever `GEMINI_MODEL` names).
5a. **Search for a venue on the web build**, against real Wolt discovery
   endpoints: use the two curls in "The Wolt venue-discovery proxies" above,
   or run the Flutter app and search by name or "near me" once #40 lands.
   A real response carries a `sections` list of venues; run either curl
   twice to see `x-ketoclub-cache` flip from `miss` to `hit`.
6. **The Flutter app, end to end:**
   ```bash
   flutter run -d chrome --dart-define=KETOCLUB_BACKEND_URL=http://localhost:8000
   ```
   Paste a real Wolt venue link. The menu loads live (not from the synthetic
   fixture) and is classified with the engine chip showing the Gemini model
   name — with no key entered anywhere in the app, because there is nowhere
   to enter one (D12).
7. **The unreachable-backend path.** Stop the `uvicorn` process (Ctrl-C) and
   retry the same paste in the still-running Flutter app: the fetch fails with
   "KetoClub's server could not be reached, so the menu could not be read.",
   and a fresh classification attempt falls back to the rule engine with the
   `backendUnreachable` reason shown on the engine chip — never a bare "no
   internet" message, per `architecture.md` constraint 10.

Nobody has run this checklist from inside this repository's build
environment: `restaurant-api.wolt.com` and `generativelanguage.googleapis.com`
are both unreachable through its egress proxy (`HANDOFF.md`, `architecture.md`
§17 open question 1). It is written here, once, for whoever next has a network
path to both.
