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

iOS-specific steps (simulator, a physical iPhone, signing, ATS for a LAN
backend) are in `docs/RUNNING_IOS.md`.

## 1. The app on its own (no backend)

The backend is for the web build only (`architecture.md` D11, D17). iOS and
Android never call it, even when it is configured: they call Wolt and
Google's Gemini API themselves. What each platform can reach with no backend:

| Platform | Menus (Wolt, 10bis) | Nearby / by-name search | AI analysis |
|---|---|---|---|
| iOS, Android | direct calls to the platform | direct calls to Wolt | **yes, with your own Gemini key** — see below; without one, rules engine only (labelled "rules") |
| Web (Chrome) | **blocked by CORS** — paste-a-link shows the "open in the phone app" message | blocked by CORS | no |

**AI analysis on a phone (D17).** Create a free API key in
[Google AI Studio](https://aistudio.google.com/apikey), then in the app open
**Settings**, paste it under **Gemini API key** and tap **Save key**; AI
analysis itself is on by default (D16), so nothing else needs ticking. The key is kept in the Keychain (iOS) or Keystore
(Android) and sent only to Google, as the `x-goog-api-key` header. Without a
key, a menu shows rule-based verdicts with "Add your Gemini API key in
Settings" and a shortcut there.

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
requests Wolt and 10bis refuse from a browser) and AI analysis, because it
holds the Gemini key server-side, so the browser never holds one (D12). Phones
do not use it (D17).

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

## 3. The web app talking to the backend

The backend URL is compiled in with a `--dart-define`; there is no in-app
setting for it. Only the web build reads it: a phone build ignores it (D17).

```bash
# web, backend on the same machine
flutter run -d chrome --dart-define=KETOCLUB_BACKEND_URL=http://localhost:8000
```

Then in the app: **AI analysis is on by default** on a fresh install (D16,
issue #167). On first launch a one-off disclosure banner on the Discovery
tab tells you what leaves the device (dish text to KetoClub's backend, on
to Google Gemini) with two buttons: **OK** acknowledges without changing
anything, **Turn off** switches AI analysis off in the same tap. Either
button dismisses the banner permanently. You can flip the toggle any time
in **Settings → What leaves this device**; a stored refusal always wins
over the default, so an install that has already turned it off keeps it
off. The web Settings screen has no key field: the key is the backend's.

Paste a Wolt link on the Discovery tab or tap the location button to
search nearby.

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
`consumer-api.wolt.com` or `www.10bis.co.il`, so every checked-in fixture
but the Wolt menu one (`wolt_hamosad_menu.json`, recorded on a laptop for
issue #168) is synthetic. From a normal machine:

```bash
tool/record_wolt_fixture.sh hamosad     # re-record the real Wolt menu fixture
```

`phase2_discovery_research.md` §2.4 has the two discovery requests to record
for issue #38, and `backend/README.md` the 10bis curl for issue #44.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Web: "A web browser cannot read Wolt menus" | no backend configured | run §2 and add the `--dart-define` (§3) |
| Web: "AI analysis is not available on this build or server" | no backend URL compiled in, or `GEMINI_API_KEY` unset | §3 / `.env` |
| Phone: "Add your Gemini API key in Settings" | no key saved | §1, "AI analysis on a phone" |
| Phone: "Gemini rejected your API key" | the saved key is wrong, revoked, or not enabled for the Gemini API | paste a fresh key from Google AI Studio |
| "Showing rule-based results" after a wait | web: backend unreachable or Gemini timed out; phone: Gemini timed out | web: `curl /v1/health` |
| Nearby search says "blocked by browser" | web without a backend | §3 |
| `flutter analyze` fails on an info | intended — CI runs `--fatal-infos` | fix the lint |
| Location button does nothing on web | browser Geolocation needs `https://` or `localhost` | use `localhost`, not a LAN IP, for the web build |
| Backend terminal shows `gemini upstream_status=404` | `GEMINI_MODEL` is not served for this key or API version (#179) | list what the key can use: `curl -sS https://generativelanguage.googleapis.com/v1beta/models -H "x-goog-api-key: $GEMINI_API_KEY"`, then set `GEMINI_MODEL` in `backend/.env` |
| "AI analysis failed" on a very large menu | the `user_prompt` cap was 60,000 characters, raised to 400,000 (#188) | update to a build with the raised cap; a menu still past 400,000 characters needs #188's batching |
