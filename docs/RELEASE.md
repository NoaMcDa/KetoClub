# Release checklist

What a release verifies by hand: CI, the backend smoke test, real fixtures,
the two release builds, and a walk of the core flows on real devices. This
is a checklist, not a design document; see `architecture.md` for the design
and `HANDOFF.md` for what is still unfinished.

The model check used to be `tool/measure_model_latency.dart` against
OpenRouter. That tool and OpenRouter are both gone (#102, #116). The model
check today is the Gemini smoke curl in `backend/README.md`, against
KetoClub's own backend.

## 1. Pre-release checklist

### CI

- [ ] `main` is green on all required checks: `backend`, `quality`, `test`,
      `integration`, `build (web)`, `build (apk)`.
- [ ] The `ios` job (builds `flutter build ios --release --no-codesign`) is
      green on the latest push to `main`. It only runs on push to `main`,
      not on pull requests, so check it separately after merging.

### Backend

- [ ] `cd backend && cp .env.example .env` (if not already done) and set a
      real `GEMINI_API_KEY`.
- [ ] Start it: `uv sync && uv run uvicorn app.main:app --reload --port 8000`.
- [ ] `curl -sS localhost:8000/v1/health` answers `"llm_configured":true`.
      `false` means the key was not picked up (check `.env` is in
      `backend/`, not the repository root).
- [ ] Run the `/v1/chat` smoke curl in `backend/README.md`'s "Smoke test
      against the real API" section. A real completion comes back as
      `{"content":"{\"dishes\": [...]}","model":"gemini-2.5-flash"}` (or
      whatever `GEMINI_MODEL` names). This needs a real network path to
      `generativelanguage.googleapis.com`, which CI and this repository's
      own build environment do not have.
- [ ] `backend/check.sh` passes locally (mirrors the `backend` CI job).

### Fixtures (#22, #44)

The Wolt and 10bis fixtures in `test/fixtures/` are synthetic until
recorded from a real response. Re-record them when the upstream shape may
have drifted, or at least once before a release that changes either
adapter or mapper.

- [ ] Wolt, through the proxy (needs the backend running, above):
      ```bash
      curl -sS localhost:8000/v1/proxy/wolt/v4/venues/slug/vitrina-lilinblum/menu/data \
        -o test/fixtures/wolt_vitrina_lilinblum_menu.json
      ```
      or `tool/record_wolt_fixture.sh <venue-slug>` directly against Wolt.
- [ ] 10bis, through the proxy:
      ```bash
      curl -sS localhost:8000/v1/proxy/tenbis/api/v1.0/Restaurants/{restaurantId}/Menu \
        -o test/fixtures/tenbis_{id}_menu.json
      ```
      As of this writing the 10bis proxy route and `TenBisMenuMapper` are
      merged, but `TenBisAdapter` is not registered in `di.dart` yet (#46).
      Recording the fixture ahead of the adapter is still useful: it is
      what the mapper's fixture test runs against once re-pointed at the
      real file.
- [ ] Both curls need a machine with a real network path to
      `restaurant-api.wolt.com` and `www.10bis.co.il`; neither is reachable
      from this repository's sandbox or CI.

### Release builds

- [ ] Web:
      ```bash
      flutter build web --release --dart-define=KETOCLUB_BACKEND_URL=<host>
      ```
      `<host>` is `http://localhost:8000` for a local run, or wherever the
      backend is hosted. There is no hosted backend today (#109); a
      released web build without a reachable `<host>` falls back to
      paste-a-link with no live Wolt or 10bis fetch and no AI analysis,
      exactly as an unconfigured build does.
- [ ] Android:
      ```bash
      flutter build apk --release
      ```
      `android/app/build.gradle.kts`'s `release` block still points
      `signingConfig` at the debug config (its own comment says so). A real
      release needs a keystore the user supplies and a proper
      `signingConfig` swapped in before this build is store-ready; until
      then the command succeeds but produces a debug-signed APK.
- [ ] iOS:
      ```bash
      flutter build ipa
      ```
      Needs, supplied by the user, not in this repository: an active Apple
      Developer Program membership, a distribution certificate and
      provisioning profile for bundle id `club.keto.app`, and Xcode signed
      in to that team (the Runner target's `CODE_SIGN_STYLE` is
      `Automatic`, so Xcode can pick the profile once a team is set). CI's
      `ios` job only proves `--no-codesign` builds; it does not exercise
      signing at all.

### Version

- [ ] Bump `version:` in `pubspec.yaml` (currently `1.0.0+1`, `x.y.z+build`).
      Bump both the semantic version and the build number in one commit.

### Gates

- [ ] `test/architecture/import_rules_test.dart` passes: the boundary test
      that keeps `restaurant-api.wolt.com` inside `wolt_adapter.dart`,
      `/v1/chat` inside `backend_chat_client.dart`, and
      `KETOCLUB_BACKEND_URL` inside `di.dart` only, and asserts `openrouter`,
      `sk-or-` and `googleapis.com` appear nowhere in `lib/`.
- [ ] `tool/check.sh` passes: format, `flutter analyze --fatal-infos
      --fatal-warnings`, the full test suite, and the 80% coverage gate.
- [ ] `backend/check.sh` passes: `ruff check`, `ruff format --check`, `mypy
      app` (strict), and `pytest --cov=app --cov-fail-under=80`.

## 2. Device test matrix

### Targets

| Target | How to reach it | Backend URL |
|---|---|---|
| Web, Chrome, desktop width | `flutter run -d chrome --dart-define=KETOCLUB_BACKEND_URL=http://localhost:8000` | localhost, backend on the same machine |
| Web, Chrome, mobile width | Same build, DevTools device toolbar at ~390px | localhost |
| One iOS device | `flutter run -d <device> --dart-define=KETOCLUB_BACKEND_URL=http://<lan-ip>:8000` | the host machine's LAN IP; `localhost` on the phone means the phone itself |
| One Android device | Same as iOS. An Android **emulator** uses `http://10.0.2.2:8000` instead, not a real LAN IP | LAN IP for a real device, `10.0.2.2` for the emulator |

Find `<lan-ip>` with `ipconfig getifaddr en0` (macOS) or `ip addr` (Linux),
on the same network as the phone. There is no hosted backend yet (#109);
`--dart-define` is the only way to point a phone at one today.

### Flows to walk

| Flow | Steps | What "pass" looks like | Platforms |
|---|---|---|---|
| Paste a Wolt link | Open the app, paste a real Wolt venue URL | Menu loads, dishes are classified, engine chip reads "AI · {model}" when the backend is up | All four targets |
| Paste a 10bis link | Paste a real 10bis venue URL or restaurant id | Until #46 (`TenBisAdapter`) ships: fails with "KetoClub cannot read menus from this site yet." After #46: a live menu loads like Wolt's | All four targets |
| Saved tab offline | Open a menu, let it cache, turn off networking (airplane mode on a phone, DevTools offline on web), open the Saved tab | The cached menu opens and reads normally with no network error | All four targets |
| Settings: appearance | Settings → Appearance, switch Light / Dark / System | The whole app re-themes immediately, choice persists across a restart | All four targets |
| Settings: language | Settings → Language, switch English / Hebrew / System | UI text switches language and layout direction (see RTL row); choice persists across a restart | All four targets |
| Waiter Card brightness | Open a dish's Waiter Card | Screen brightness visibly rises while the card is open and returns to normal on close | iOS and Android only; the `screen_brightness` plugin has no effect on web |
| RTL in Hebrew | Set language to Hebrew, open a menu and the Waiter Card | Layout mirrors right to left: nav, verdict tiles, text alignment, icons that imply direction | All four targets |
| Rules-fallback banner | Stop the backend (or use a build with no `KETOCLUB_BACKEND_URL`), open or refresh a menu | Engine chip reads "Rules ({reason})", e.g. `notConfigured` or `backendUnreachable`; dishes are still classified, never blank | All four targets |

Repeat the whole matrix once per target; do not assume a pass on one
target predicts another; the brightness and RTL rows in particular have no
web equivalent or behave differently there.

## 3. Rollback

There is no hosted deployment yet (#109), so "rollback" means: do not
publish a broken artifact, and undo what was published if one slipped
through.

- **Before publishing**: if a build or device check fails, stop. Do not
  bump `pubspec.yaml`'s version further or tag a release; fix the issue
  and restart this checklist from the pre-release section.
- **Store builds already submitted**: use the App Store Connect / Google
  Play Console "halt rollout" or "unpublish" action for that platform, and
  re-promote the previous accepted build. This repository does not
  automate either; both consoles are the source of truth for what is live.
- **Web build already deployed** (once #109 lands): redeploy the previous
  `flutter build web --release` artifact rather than patching the new one
  in place; keep the last three build outputs on hand for exactly this.
- **The version bump commit**: `git revert` it rather than editing
  `pubspec.yaml` back by hand, so the bump and its revert are both in the
  history.

## 4. Known limitations to state in release notes

| Limitation | Detail |
|---|---|
| Discovery not built | No nearby venue search or geolocation. Paste-a-link is the only way in. Blocked on finding a Wolt venue-search endpoint (`architecture.md` §17.2) |
| 10bis fixture is synthetic | `test/fixtures/tenbis_synthetic_menu.json` says so in its first key. Re-record through the 10bis proxy (#122, merged) once a real restaurant id is captured (#44) |
| Mobile without the backend define is rules-only | iOS and Android call Wolt directly for menus, but AI classification always goes through the backend (`/v1/chat`). With no `KETOCLUB_BACKEND_URL` set at build time, every platform, including phones, falls back to the on-device rule engine and shows "Rules (notConfigured)" |
| WCAG AA contrast failures | Fixed (issue #64, contrast half): the green status pill's own text on its green fill, light-mode `ink3` on `bg`, and dark-mode `ink3` on `bg` all now clear 4.5:1. Pinned by `test/theme/contrast_test.dart`; see `lib/theme/app_tokens.dart` |

Also worth a line if still true at release time: no human has reviewed the
code (`HANDOFF.md`), and the pinned Gemini model's behaviour against the
real prompt is only as trustworthy as the last time someone actually ran
the smoke curl in §1 above.

## 5. Performance budget (#65)

The Phase 2 success criterion. Nothing below has been measured yet: every
cell is blank until someone runs it on the target and writes the number in.
Do not copy a number from one target into another.

### Budgets

| What | Budget |
|---|---|
| Re-opening a menu whose analysis is already in the Hive cache, on 4G | under 3 s from tap to classified dishes |
| Decode + map of a 60-dish payload, and parsing a 60-dish AI reply, on a phone | 16 ms each (one frame at 60 Hz) |
| Any single frame while a menu renders | 32 ms |
| AI analysis | no fixed budget (the backend waits up to 110 s for the model, the client 120 s), but the screen must say "Asking the AI…" or "Applying the rules…" the whole time |

### How to take each number

Use a 60-dish menu. Run the app with `flutter run --profile` (not debug)
and the backend define from §2. On web, throttle to "Fast 4G" in the
DevTools network panel; on a phone, use a real 4G connection with Wi-Fi off.
Time from the tap that opens the menu to the frame where verdicts appear
(the DevTools Performance view, or a screen recording, both work).

- **Cold fetch**: Settings → "Clear saved menus", and restart the backend
  so its Wolt proxy cache is empty, then open the menu.
- **Proxy-cached fetch** (web only): "Clear saved menus" again but leave the
  backend running, then reopen within the hour. The response carries
  `X-KetoClub-Cache: hit`.
- **Hive-cached open**: reopen the same menu within 24 hours without
  clearing anything. This is the one held to the 3 s budget. It measures
  a cached *analysis* only when `MenuController.open` reuses one (#57):
  the cached result must come from the AI, consent must still be on, the
  dish text must be unchanged and the net-carb limit must be the same. A
  rules result is never reused, so with consent off this open runs the
  rule engine again. Note the engine chip next to the number.
- **AI analysis cold**: a menu the backend's completion cache has not seen.
  Time how long "Asking the AI…" stays on screen.
- **AI analysis server-cached**: "Clear saved menus", then reopen the same
  menu so the app asks again and the backend answers from its completion
  cache (#103). Same measurement.

| Target | Cold fetch | Proxy-cached fetch | Hive-cached open | AI analysis cold | AI analysis server-cached |
|---|---|---|---|---|---|
| Web via local backend | | | | | |
| iOS | | n/a unless via backend | | | |
| Android | | n/a unless via backend | | | |

iOS and Android fetch Wolt directly unless the build routes them through
the backend, so the proxy-cached column only applies to them in that case.

### Main-thread steps on a phone

`tool/perf_menu.dart` times decode + map (Wolt and 10bis), the menu
fingerprint, the rules engine and the AI-reply parser over generated 60-dish
menus. `tool/README.md` has the commands. Only a `--profile` run on the
device counts; the host numbers from `flutter test` do not.

| Step (60 dishes) | iOS median / max ms | Android median / max ms |
|---|---|---|
| decode + map (Wolt, synthetic) | | |
| decode + map (10bis, synthetic) | | |
| fingerprint | | |
| rules engine | | |
| reply parse | | |

If a decode + map or reply-parse median exceeds 16 ms on either phone,
that step moves to `compute` (the last criterion of #65). Until a phone
says so, nothing moves: `compute` runs on the main thread on web anyway, and
the move is only worth its cost against a measured stall.

### Frame check (32 ms)

With `flutter run --profile`, open the DevTools Performance view, record
while a 60-dish menu opens and scrolls from top to bottom, and read the
slowest frame (UI and raster).

| Target | Slowest frame while rendering (ms) | Pass (under 32 ms)? |
|---|---|---|
| Web via local backend | | |
| iOS | | |
| Android | | |
