# KetoClub backend

A small FastAPI service that the KetoClub app talks to. It exists because
`restaurant-api.wolt.com` sends no CORS headers, so a browser refuses the
request before it leaves and the web build cannot read a menu at all
(`architecture.md` §13, D9). This service makes the same request from a server,
where CORS does not apply.

**It is an accelerator, never a dependency.** With no backend URL configured the
app behaves exactly as it does with this service switched off. Mobile builds do
not use it: they call Wolt directly, as they always have.

The full design, including the endpoints not yet built, is `backend_plan.md` in
the repository root. Issues: #94 (this scaffold), #95 (the proxy), #96 (the app
side).

## Run it

```bash
cd backend
uv sync                       # first time only
uv run uvicorn app.main:app --reload --port 8000
```

Then run the app against it:

```bash
flutter run -d chrome --dart-define=KETOCLUB_BACKEND_URL=http://localhost:8000
```

No `.env` is needed to start; every setting has a working default. Copy
`.env.example` to `.env` to change one.

### From a phone or emulator

`localhost` on a device is the device itself. Use the machine's address on the
network instead:

| Target | URL |
|---|---|
| Android emulator | `http://10.0.2.2:8000` |
| iOS simulator | `http://localhost:8000` |
| Physical device | `http://<your-machine-ip>:8000`, both on the same network |

Mobile does not need the backend for menus. This is only for testing the proxy
path from a device.

## The gate

```bash
./check.sh
```

Runs exactly what the `backend` CI job runs: `ruff check`, `ruff format
--check`, `mypy` in strict mode, and `pytest` with an 80% coverage floor. Run it
before pushing, the same way `tool/check.sh` works for the Flutter side.

No test makes a network call. Upstream responses are faked with `respx` and the
database is in-memory SQLite, matching `architecture.md` constraint 12.

## Endpoints

Everything lives under `/v1`.

### `GET /health`

```bash
curl -s http://localhost:8000/v1/health
# {"status":"ok","version":"0.1.0","llm_configured":false}
```

`llm_configured` reports whether a model key is present. The key itself is never
returned, logged or included in an error.

### `GET /proxy/wolt/v4/venues/slug/{slug}/menu/data`

Forwards one menu request to Wolt and returns the answer unchanged.

```bash
curl -i http://localhost:8000/v1/proxy/wolt/v4/venues/slug/vitrina-lilinblum/menu/data
```

- The path deliberately mirrors Wolt's own, so the app only swaps a base URL.
- The slug must match `^[a-z0-9][a-z0-9-]{0,99}$`; anything else is a 422 and no
  upstream request is made.
- The upstream host comes from `WOLT_BASE_URL`, never from the request. This is
  one allow-listed route, not a general proxy.
- Request headers are built from scratch. Nothing a caller sends is forwarded,
  so an `Origin`, `Cookie` or `Authorization` header cannot be relayed to Wolt.
- **Wolt's status, body and content type pass through unchanged**, 404
  included. The only statuses this service invents are `502` (Wolt unreachable)
  and `504` (Wolt timed out), each with a `{"reason", "status_code"}` body.
- A 2xx body is cached for `MENU_CACHE_TTL_SECONDS`. The response carries
  `X-KetoClub-Cache: hit` or `miss`. Failures are never cached.

## Recording a real Wolt fixture

`test/fixtures/wolt_vitrina_lilinblum_menu.json` in the Flutter tree is
synthetic: the build sandbox cannot reach Wolt, so no real response was ever
recorded (`HANDOFF.md`, outstanding item 2). This service can, from a machine
with normal network access:

```bash
curl -s http://localhost:8000/v1/proxy/wolt/v4/venues/slug/<slug>/menu/data \
  | python3 -m json.tool > /tmp/wolt_real.json
```

Review it for anything personal before committing, and follow
`test/fixtures/README.md`. That is issue #22, and it is what would tell us
whether `wolt_menu_mapper.dart` survives a real payload.

## What is not built yet

`POST /v1/chat` (the hosted model key, #100), the install-id rate limit (#101),
the shared completion cache (#103) and every community endpoint (#105 to #107).
The configuration for them is already in `.env.example`, marked as unused.
