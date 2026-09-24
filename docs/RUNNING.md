# Running KetoClub

How to run the Flutter app (web, iOS, Android) and the optional FastAPI
backend on your own machine. `CLAUDE.md` and `architecture.md` explain *why*
things are shaped this way; this page is only the commands.

## What you need

| Tool | Version | Why |
|---|---|---|
| Flutter | **3.47.4** (Dart 3.13.3) — pinned in `pubspec.yaml` and `.github/workflows/ci.yml` | the app |
| Chrome | any current | `flutter run -d chrome` and the flow tests |
| Python | ≥ 3.12 (`backend/pyproject.toml`) | the backend |
| [uv](https://docs.astral.sh/uv/) | any current | backend dependencies and scripts |
| Xcode / Android Studio | current | only for a phone or simulator run |

Check the Flutter version with `flutter --version`; if it differs, `flutter
downgrade 3.47.4` or use `fvm`.

## 1. The app on its own (no backend)

The backend is an accelerator, never a dependency (`architecture.md` D11).
With no backend configured the app still runs everywhere; what changes is
what it can reach:

| Platform | Menus (Wolt, 10bis) | Nearby / by-name search | AI analysis |
|---|---|---|---|
| iOS, Android | direct calls to the platform | direct calls to Wolt | **no** — rules engine only (labelled "rules") |
| Web (Chrome) | **blocked by CORS** — paste-a-link shows the "open in the phone app" message | blocked by CORS | no |

```bash
git clone https://github.com/NoaMcDa/KetoClub.git
cd KetoClub
flutter pub get
flutter gen-l10n            # regenerates lib/l10n/generated/ (committed, but harmless)

flutter run -d chrome       # web
flutter run -d <device-id>  # phone or simulator; `flutter devices` lists ids
```

## 2. The backend

The backend gives the web build live menus and search (it forwards the
requests Wolt and 10bis refuse from a browser) and gives **every** platform AI
analysis, because it holds the Gemini key server-side — the app never holds a
model key (D12).

```bash
cd backend
cp .env.example .env         # then set GEMINI_API_KEY=... (Google AI Studio key)
uv sync                      # creates .venv from uv.lock
uv run uvicorn app.main:app --reload --port 8000
```

Check it: `curl http://localhost:8000/v1/health` → `{"status":"ok","version":…,
"llm_configured":true}` (`false` means `GEMINI_API_KEY` is unset; the app then
falls back to the rules engine and says so).

Everything else in `.env` has a safe default. `DATABASE_URL` defaults to a
local SQLite file (`backend/ketoclub.db`, gitignored) holding only the
menu/search/completion caches. `backend/README.md` documents every route,
error and cache.

## 3. The app talking to the backend

The backend URL is compiled in with a `--dart-define`; there is no in-app
setting for it.

```bash
# web, backend on the same machine
flutter run -d chrome --dart-define=KETOCLUB_BACKEND_URL=http://localhost:8000

# a phone on the same Wi-Fi: use the machine's LAN address, not localhost
flutter run -d <device-id> --dart-define=KETOCLUB_BACKEND_URL=http://192.168.1.23:8000
```

For a phone, also let the backend accept that origin: the default
`CORS_ORIGIN_REGEX` in `.env` allows `localhost`/`127.0.0.1` only, which is
enough for the web build; native apps send no `Origin`, so nothing changes for
them. On iOS, a plain `http://` LAN URL needs an ATS exception for local
networking — a simulator does not.

Then in the app: open **Settings → allow AI analysis** (consent is off by
default and is the only thing gating the AI path once a backend is configured),
paste a Wolt link on the Discovery tab or tap the location button to search
nearby.

### Builds

```bash
flutter build web --release      # build/web — serve with any static server
flutter build apk --debug        # build/app/outputs/flutter-apk/app-debug.apk
flutter build ios --no-codesign  # needs Xcode
```

Add the same `--dart-define=KETOCLUB_BACKEND_URL=…` to a build that should
talk to a backend.

## 4. Tests and the gate

```bash
tool/check.sh          # everything CI runs for the app: format, analyze, tests, 80 % coverage
backend/check.sh       # everything CI runs for the backend: ruff, mypy, pytest, coverage
```

Pieces, when you want one thing:

```bash
dart format --set-exit-if-changed lib test integration_test test_driver
flutter analyze --fatal-infos --fatal-warnings    # an info-level lint fails CI
flutter test                                      # unit, widget, architecture
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/flows/menu_display_flow_test.dart -d chrome   # one flow test
cd backend && uv run pytest
```

`test/` and `integration_test/` are held to the same lints as `lib/`
(80 columns, `public_member_api_docs`).

## 5. Things that need a real network path

The CI runners and the cloud sandbox cannot reach `restaurant-api.wolt.com`,
`consumer-api.wolt.com` or `www.10bis.co.il`, so the checked-in fixtures are
synthetic. From a normal machine:

```bash
tool/record_wolt_fixture.sh vitrina-lilinblum     # real Wolt menu fixture (issue #22)
```

`phase2_discovery_research.md` §2.4 has the two discovery requests to record
for issue #38, and `backend/README.md` the 10bis curl for issue #44.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Web: "A web browser cannot read Wolt menus" | no backend configured | run §2 and add the `--dart-define` (§3) |
| "AI analysis is not available on this build or server" | no backend URL compiled in, or `GEMINI_API_KEY` unset | §3 / `.env` |
| "Showing rule-based results" after a wait | backend unreachable or Gemini timed out | `curl /v1/health`; check the LAN address on a phone |
| Nearby search says "blocked by browser" | web without a backend | §3 |
| `flutter analyze` fails on an info | intended — CI runs `--fatal-infos` | fix the lint |
| Location button does nothing on web | browser Geolocation needs `https://` or `localhost` | use `localhost`, not a LAN IP, for the web build |
