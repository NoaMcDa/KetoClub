# KetoClub Phase 2 execution plan

Written 2026-09-23, after the backend landed. It groups every open Phase 2
issue into dependency-ordered waves of parallel worker PRs, the way the
Phase 3 backend work ran. Workers do not run tests locally. CI is the judge.

Where this plan and an issue body disagree, the issue body was rewritten in
the same pass and should now agree. Where this plan and `architecture.md`
disagree, PR #120 (issue #97, waiting on CI) is reconciling the documents;
the merged code on `main` at `0f2d037` wins in the meantime.

## 1. Context

Phase 2 is "Mobile Interface & Discovery" (`MILESTONE_CONVENTIONS.md`,
README roadmap). Five milestones on GitHub:

| Milestone | Open issues | Goal |
|---|---|---|
| Phase 2: Geolocation & Venue Search | #37 #38 #39 #40 #41 #42 #43 | Find venues near me, not only by pasted link |
| Phase 2: 10bis Integration | #44 #45 #46 #47 | 10bis menus fetch and classify like Wolt's |
| Phase 2: Menu Display & Navigation | #48 #49 #50 #51 #52 #53 #54 #55 | Saved tab, refresh, search, photos, notes |
| Phase 2: Settings & Preferences | #56 #57 #58 #59 #60 #61 #62 | Dietary rules, carb limit, appearance, cache |
| Phase 2: Polish & Performance | #63 #64 #65 #66 #68 #69 | Skeletons, a11y, budget, platform setup, release |
| (no milestone) | #119 | Show why a menu degraded to rules |

`feature_prioratization` places nearby search (Tier B), filtering (Tier B,
shipped as the counter tiles), dietary toggles (Tier C), 10bis (Tier C),
notes (Tier C) and the shareable card (Tier D) here.

### What the backend changes

The app is no longer client-only. What shipped this session:

| Piece | Status | Effect on Phase 2 |
|---|---|---|
| `GET /v1/proxy/wolt/v4/venues/slug/{slug}/menu/data` (#95) | merged | The web build fetches Wolt menus. A 10bis route can bypass CORS the same way |
| `WoltMenuAdapter(proxyBase:)`, `MenuFetchFailureReason.backendUnreachable`, `menuProxyBase()` in `di.dart` (#96) | merged | `TenBisAdapter` (#46) copies this shape |
| `POST /v1/chat` to Gemini, install-id header, 5/min 40/day per install (#100, #101) | merged | The prompt is still built on device; Settings features that change it (#56, #57) still work |
| Server-side chat cache by request hash, 24 h, hits bypass the limiter (#103) | merged | One analysis per distinct prompt serves every user. Prompt-changing settings fragment it |
| OpenRouter and BYOK removed. `BackendChatClient`, `RoutingMenuClassifier(llm, heuristic, connectivity)`, `backendUnreachable` and `consentWithheld`, no `unauthorised` (#102) | merged | #60 and #62 lose their premise. The chip already shows the served model |
| Boundary test: `restaurant-api.wolt.com` only in the Wolt adapter, `/v1/chat` only in `backend_chat_client.dart`, `KETOCLUB_BACKEND_URL` only in `di.dart`, `googleapis.com` nowhere in `lib/` (#98, in #102) | merged | `TenBisAdapter` (#46) must add `www.10bis.co.il` to the same allow-list |

Rules the user decided:

- The backend holds the model key. The app holds no key.
- Web fetches menus through the backend. iOS and Android call Wolt directly.
- The backend is localhost-only for now. Hosting is #109.
- Work runs as parallel worker PRs. CI is the judge. Workers do not run
  tests locally.

Environment limits: `restaurant-api.wolt.com`, `www.10bis.co.il`,
`generativelanguage.googleapis.com` and `openrouter.ai` are blocked from the
sandbox and from CI. A backend run on the user's machine is the way to reach
them.

## 2. Blockers and discovery

Three research items gate real work. All three need the user's machine.

| Issue | Blocks | How to unblock now | Only the user can |
|---|---|---|---|
| #38 Wolt venue search endpoint | #39, #40, and the venue-search proxy route (B2) | Open wolt.com in a browser with DevTools, search and pan the map, copy the request URLs and a redacted response into `menu_api_research`. No proxy exists for it yet, so this is a browser capture, not a curl | Run the capture. Decide the User-Agent that works |
| #44 real 10bis fixture | #45 (mapper), #46 (adapter) | Once the 10bis proxy route (B1) merges: `curl -sS localhost:8000/v1/proxy/tenbis/api/v1.0/Restaurants/{id}/Menu -o test/fixtures/tenbis_{id}_menu.json`. Until then, a direct curl from the user's machine works too | Run the curl. Pick a real restaurant id |
| #22 real Wolt fixture (Phase 1, still open) | Nothing hard. It settles `Menu.venueName` and the single-malformed-item trade-off | `curl -sS localhost:8000/v1/proxy/wolt/v4/venues/slug/vitrina-lilinblum/menu/data -o test/fixtures/wolt_vitrina_lilinblum_menu.json` with the backend running (`backend/README.md`) | Run the curl, then commit the redacted fixture or hand it to a worker |

Recommended default for #44: do not wait. Build #45 and #46 against a
synthetic 10bis fixture that says so in its first key, the way the Wolt
fixture does, and re-record through B1 when the user runs the curl. The
mapper test failing on the real payload is the alarm, which is the design
`architecture.md` §15 already asks for.

## 3. Waves

Worker model: Sonnet for contained work in one or two files. Opus for
changes that cross store, controller, prompt and screen, or that rewrite a
screen.

Each wave's PRs run in parallel. A wave starts when the previous wave's
blockers of its issues have merged, not when the whole previous wave has.

### Wave 0: housekeeping, no worker

| Item | Action |
|---|---|
| #60, #62 | Closed in this pass as not planned (see §4) |
| #59 | Already built. Verify the checklist in its updated body and close as completed |
| PR #120 (#97) | Merge before wave 1 so the one docs PR in it (#41) does not conflict with it |

### Wave 1: foundations, no cross-dependencies

| Issue | Scope | Depends on | Likely files | Conflict hotspots | Model |
|---|---|---|---|---|---|
| #119 | Banner with `analysisFailureMessage` for a rules result | none | `screens/menu_screen.dart`, `widgets/failure_copy.dart`, two flows | `menu_screen.dart` with #49 | Sonnet |
| #49 | Pull-to-refresh, stale refetch, keep analysis when the normalised hash matches | none | `state/menu_controller.dart`, `services/menu/menu_repository.dart`, `services/storage/menu_cache.dart`, `menu_screen.dart` | `menu_screen.dart` with #119; `menu_cache.dart` with #48 | Sonnet |
| #48 | Saved tab: list cached menus, open offline, remove. Adds `entries()` and `count()` to `MenuCache` so #61 can use them | none | `screens/saved_screen.dart`, new `state/saved_controller.dart`, `menu_cache.dart`, `app.dart`, ARBs, fakes | `menu_cache.dart` with #49 | Sonnet |
| #58 | Appearance: Light, Dark, System, persisted | none | `services/storage/settings_store.dart`, `state/settings_controller.dart`, `screens/settings_screen.dart`, `app.dart` | `AppSettings` with #57 (next wave) | Sonnet |
| #37 | `LocationService` over `geolocator`, sealed result, manual fallback | none | new `services/location/`, `di.dart`, `Info.plist`, `AndroidManifest.xml`, ARBs, fakes | `di.dart` with #46; manifests with #66 | Sonnet |
| #45 | `TenBisMenuMapper`, pure, fixture-tested | synthetic fixture (see §2) | new `services/menu/tenbis/tenbis_menu_mapper.dart`, `test/fixtures/` | none | Sonnet |
| B1 | Backend: 10bis menu proxy route | none | `backend/app/routers/proxy.py`, new `services/tenbis.py`, `config.py`, `models.py`, tests, README | none with Flutter work | Sonnet |
| #41 | Research: venue keto score before analysis. Records D13 | PR #120 merged | `architecture.md`, `utils/constants.dart` | `architecture.md` with PR #120 | Sonnet |

### Wave 2: first dependents

| Issue | Scope | Depends on | Likely files | Conflict hotspots | Model |
|---|---|---|---|---|---|
| #46 | `TenBisAdapter` with `proxyBase`, registered in `di.dart` | #45, B1 for the route shape | new `services/menu/tenbis/tenbis_adapter.dart`, `di.dart`, flow test | `di.dart` with #37 if still open | Sonnet |
| #57 | Net carb limit stepper feeding the prompt and the parser. Establishes "options change invalidates the cached analysis" | #58 merged (same `AppSettings`) | `settings_store.dart`, `settings_controller.dart`, `settings_screen.dart`, `menu_analysis_prompt.dart`, `menu_response_parser.dart`, `menu_controller.dart`, `constants.dart` | `settings_screen.dart` with #61; `menu_controller.dart` with #49 | Opus |
| #61 | Saved menus block in Settings: count, size, clear with confirmation | #48 | `settings_screen.dart`, `settings_controller.dart` | `settings_screen.dart` with #57 | Sonnet |
| #47 | Refresh action in the menu header. The source line itself already exists | #49 | `menu_screen.dart` | `menu_screen.dart` with #51, #53 (next wave) | Sonnet |
| #39 | `WoltVenueSearchService`: nearby and by-name, mapper over the recorded fixture | #38 (user), #37 | new `services/venue/venue_search_service.dart`, `models/venue.dart`, fixture, fakes | `models/venue.dart` with #53 | Opus |
| B2 | Backend: venue-search proxy route(s) for the web build | #38 | `backend/app/routers/proxy.py`, `services/wolt.py`, tests | B1 in `proxy.py` if not yet merged | Sonnet |
| #66 | Platform setup: permissions, icons, splash, bundle ids | #37 (manifests) | `ios/Runner/Info.plist`, `AndroidManifest.xml`, `build.gradle.kts`, `web/manifest.json`, icons | none once #37 is in | Sonnet |

### Wave 3: screens

| Issue | Scope | Depends on | Likely files | Conflict hotspots | Model |
|---|---|---|---|---|---|
| #40 | Discovery screen: location header, search, chips, venue cards | #39, #37 | `screens/venue_search_screen.dart`, `state/venue_search_controller.dart`, new `widgets/venue_card.dart`, ARBs | `venue_search_screen.dart` with #68 (next wave) | Opus |
| #56 | Dietary toggles: seed-oil free, dairy-free, carnivore, in prompt and rules | #57 | `settings_store.dart`, `settings_screen.dart`, `menu_analysis_prompt.dart`, `heuristic_menu_classifier.dart`, `constants.dart`, flow test | `settings_screen.dart` with #55; `constants.dart` with #41 | Opus |
| #51 | Search within a menu and category jump | #47 | `menu_controller.dart`, `menu_screen.dart` | `menu_screen.dart` with #53 | Sonnet |
| #53 | Open the venue on Wolt or 10bis. URL derived from `VenueRef` | #46 for the 10bis URL form | `menu_screen.dart`, `models/venue.dart` or `venue_ref_resolver.dart` | `menu_screen.dart` with #51 | Sonnet |
| #52 | Personal notes on dishes, local only | none | new `services/storage/notes_store.dart`, `widgets/dish_card.dart`, `waiter_card_sheet.dart`, `di.dart` | `dish_card.dart` with #50 (next wave) | Sonnet |
| #55 | Persist last filter and last venue, restore on launch | #57 (same `AppSettings`) | `settings_store.dart`, `menu_controller.dart`, `app.dart` | `app.dart` with #58 if still open | Sonnet |

### Wave 4: polish and measurement

| Issue | Scope | Depends on | Likely files | Conflict hotspots | Model |
|---|---|---|---|---|---|
| #42 | Rules-engine pre-scoring of visible venues, bounded concurrency | #41, #40 | `venue_search_controller.dart`, `widgets/venue_card.dart`, `constants.dart` | `venue_search_controller.dart` with #43 | Opus |
| #43 | Discovery flow tests | #40 | `integration_test/flows/`, `flow_support.dart` | `flow_support.dart` with every other flow PR | Sonnet |
| #50 | Dish and venue photos with placeholders | #40 | `dish_card.dart`, `venue_card.dart`, `pubspec.yaml` | `dish_card.dart` with #52 | Sonnet |
| #63 | Skeleton and empty states for Discovery, Menu, Saved | #40, #48 | new `widgets/skeletons.dart`, three screens | every screen file | Sonnet |
| #68 | Retry actions, offline banner, cached-menu copy, including `backendUnreachable` | #49, #119 | `menu_screen.dart`, `venue_search_screen.dart`, `menu_controller.dart`, flow test | `menu_screen.dart` with #63 | Sonnet |
| #64 | RTL and accessibility audit, contrast fixes (`app_tokens.dart` issue) | #40 | all widgets, `theme/app_tokens.dart`, semantics tests | every widget file | Opus |
| #65 | Performance budget and progress state during analysis | #49 | `menu_controller.dart`, new `tool/perf_menu.dart` | measurements need the user's devices | Opus |
| #54 | Shareable menu card | none | `menu_screen.dart`, `pubspec.yaml` (`share_plus`) | `menu_screen.dart` with #68 | Sonnet |
| #69 | Release checklist and device matrix | #66 | new `docs/RELEASE.md`, `CLAUDE.md` | none | Sonnet |

Rule for `flow_support.dart` and `fake_app_dependencies.dart`: any PR that
adds a required `AppDependencies` field (#37, #52, #39) must update both, and
siblings in the same wave will conflict there. Merge those first in their
wave, then rebase the rest.

## 4. Issues that are obsolete or changed

Every claim below was checked against `origin/main` at `0f2d037`, which
includes #117 and #118.

| Issue | Finding | Action taken |
|---|---|---|
| #60 model picker with cost | The model is `GEMINI_MODEL` on the server. The user has no key and pays nothing per menu. `EngineChip` already renders "AI · {model}" from the `{content, model}` reply | Closed, not planned |
| #62 key management | No `KeyStore`, no key section, no `unauthorised` reason on `main` | Closed, not planned |
| #59 UI language | Built. `SettingsScreen._languageSection` offers System, English, Hebrew; `LocaleController` applies it; `settings_screen_test.dart` pumps `Locale('he')` | Body updated to a verification checklist. Recommend closing as completed |
| #58 appearance | Not built. `app.dart` hardcodes `themeMode: ThemeMode.system` | Unchanged, wave 1 |
| #47 source and freshness | The "{platform} · {age}" line exists and is source-aware (`_platformName` names Wolt, 10bis, Tabit, Ontopo). Only the refresh action is missing, and it is #49's refetch surfaced in the header | Body narrowed to the refresh affordance, blocked by #49 |
| #55 last filter and venue | `AppSettings.lastVenue` exists in the store but nothing writes it. `MenuController.open` restores the default filter, not the last one | Body updated to say what exists |
| #61 saved menus block | `MenuCache.size()` and the Clear action exist. `count()` does not | Body updated; `count()` lands with #48 |
| #53 open on platform | `Venue.sourceUrl` exists but `Venue` is constructed nowhere. `MenuScreen` has only a `VenueRef` | Body updated: derive the URL from `VenueRef` |
| #46 10bis adapter | The resolver half is built (`tenbis_paste_flow_test.dart`). The adapter needs `proxyBase` like Wolt | Body updated |
| #41 keto score research | Said "a new decision D10" and "50/day free quota". D10 to D12 are taken; the quota is now the backend limiter plus the shared chat cache | Body updated: D13 |
| #66 platform setup | Said "minSdk for secure storage". `flutter_secure_storage` is gone | Body updated |
| #69 release checklist | Said "the model latency check from the research issue" and "the measurement script". #16 is closed, the script deleted. The replacement is the Gemini smoke test in `backend/README.md` | Body updated |
| #56, #57 | Assumed nothing about the key, but readers may think the prompt moved server-side. It did not | Bodies say: prompt built on device by `MenuAnalysisPrompt`, sent through `/v1/chat`, and every option change is a new chat-cache key |
| #65, #68 | Web fetch is now two hops (browser, backend, Wolt); `backendUnreachable` needs a retry action | Bodies updated lightly |
| #42 | Pre-scoring on web means N proxied fetches. The 1 h server cache absorbs repeats | Body updated |
| #119 | New this session | Unchanged |

Not changed because nothing in them is contradicted: #37, #38 (only the
unblock path added), #40, #43, #45, #48, #49, #50, #51, #52, #54, #63, #64.

## 5. Backend work Phase 2 needs

Two routes, drafted in issue form. They are not filed yet; see open question
4. Both follow `backend_plan.md` §3.3: allow-listed passthrough, upstream host
from config only, nothing from the inbound request forwarded, 502 and 504 the
only proxy-originated statuses, `X-KetoClub-Cache` on every reply.

### B1. `[feature] 10bis menu proxy route so the web build can fetch 10bis menus`

**Description.** The 10bis API sends no CORS headers, so a browser cannot
call `https://www.10bis.co.il/api/v1.0/Restaurants/{restaurantId}/Menu`.
Add the second allow-listed proxy route,
`GET /v1/proxy/tenbis/api/v1.0/Restaurants/{restaurantId}/Menu`, shaped
exactly like the Wolt route. It is also the one way to record a real 10bis
fixture (#44) from a machine that can reach 10bis.

**Context.** `backend/app/routers/proxy.py`, new
`backend/app/services/tenbis.py`, `backend/app/config.py`
(`TENBIS_BASE_URL`, default `https://www.10bis.co.il`),
`backend/app/models.py` (`menu_cache` gains a `source` column or the key is
prefixed `tenbis:`), `backend/tests/test_proxy_tenbis.py`,
`backend/README.md`.

**Acceptance criteria.**
- [ ] `restaurantId` validated as `^[0-9]{1,12}$`; anything else is 422 before any upstream call
- [ ] Transparent passthrough: 10bis status, body and `Content-Type` unchanged, 404 included
- [ ] Upstream headers built from scratch (`User-Agent`, `Accept`), nothing from the inbound request forwarded
- [ ] 502 `offline` on connect failure, 504 `timeout` on read timeout, `{reason, status_code}` bodies
- [ ] 2xx cached per restaurant id for `MENU_CACHE_TTL_SECONDS`; `X-KetoClub-Cache: hit|miss`; failures never cached; Wolt and 10bis entries cannot collide
- [ ] README: the route, and the curl that records `test/fixtures/tenbis_{id}_menu.json` for #44
- [ ] Coverage 80%+ in `backend/check.sh`

**Tests required.** respx-faked 10bis for 200, 404, 500, connect error,
timeout; cache hit and miss; validation.

**Related issues.** Blocks #44, #46. Related to #95, #96.

### B2. `[feature] Wolt venue-search proxy route(s) for nearby and by-name search on web`

**Description.** Whatever #38 discovers will be a Wolt endpoint without CORS
headers, so the web build can only call it through the backend. Add one
allow-listed route per discovered endpoint, forwarding only the parameters
#38 documents (position, query, language, page).

**Context.** `backend/app/routers/proxy.py`, `backend/app/services/wolt.py`,
`backend/app/config.py`, `backend/tests/test_proxy_search.py`,
`backend/README.md`. Cannot be written until #38 lands; the acceptance
criteria below are the fixed part.

**Acceptance criteria.**
- [ ] Route paths are literal allow-list entries; no wildcard passthrough
- [ ] Query parameters validated and bounded (lat, lon as floats in range; query length-capped)
- [ ] Same header, status and error rules as the menu proxy
- [ ] Short cache (5 min) keyed on the canonical query, `X-KetoClub-Cache` header
- [ ] Per-install rate limit applied if the endpoint proves expensive (decide in #38)
- [ ] Coverage 80%+

**Tests required.** respx-faked upstream for 200, 4xx, 5xx, connect error,
timeout; parameter validation; cache.

**Related issues.** Blocked by #38. Blocks #39 on web. Related to #40.

Not needed for Phase 2: a community endpoint (Phase 3, #105 to #108) and
hosting (#109). Nearby search on iOS and Android calls Wolt directly, the
same rule as menus.

## 6. Verification

Per PR, CI runs seven checks and is the only judge: `backend`
(`backend/check.sh`), `quality` (format, analyze with fatal infos),
`test` (unit, widget, architecture, 80% coverage gate), `integration`
(flows on headless Chrome), `build web`, `build apk`, and `build iOS` on
`main`. A worker's PR body says which checks it expects to exercise and
never claims a local run it did not make.

Manual steps only the user can run:

| Step | When | Command or action |
|---|---|---|
| Record the Wolt fixture (#22) | Now | `cd backend && uv run uvicorn app.main:app --port 8000`, then the curl in `backend/README.md` |
| Record the 10bis fixture (#44) | After B1 | The curl in B1's README section |
| Capture the venue-search requests (#38) | Now | Browser DevTools on wolt.com, redact, paste into `menu_api_research` |
| Gemini smoke test | Before the Phase 2 release | `GEMINI_API_KEY` in `backend/.env`, then the `/v1/chat` curl in `backend/README.md` |
| Web end to end | After each wave | `flutter run -d chrome --dart-define=KETOCLUB_BACKEND_URL=http://localhost:8000`, paste a Wolt link, see the "AI · gemini-2.5-flash" chip |
| Phone end to end | After #66 | `flutter run -d <device> --dart-define=KETOCLUB_BACKEND_URL=http://<lan-ip>:8000`. Needs #99 or the define, since the chat client uses the base URL on every platform |
| Performance numbers (#65) | Wave 4 | On a real phone on 4G, 60-dish fixture |
| Permission prompts (#37, #66) | Wave 2 | One iOS and one Android device |

## 7. Open questions

Each with the default this plan assumes.

| # | Question | Default |
|---|---|---|
| 1 | Build #45 and #46 against a synthetic 10bis fixture now, or wait for #44? | Build now, fixture marked synthetic, re-record through B1 |
| 2 | Close #59 as completed? | Yes, after the two-line check in its body |
| 3 | Keep #47 as a separate issue or fold it into #49? | Keep, narrowed to the header refresh affordance, blocked by #49 |
| 4 | File B1 and B2 as GitHub issues under the Phase 2 milestones? | Yes: B1 in `Phase 2: 10bis Integration`, B2 in `Phase 2: Geolocation & Venue Search`, label `Phase 2` |
| 5 | Should nearby search on phones call Wolt directly, like menus, or always use the backend? | Direct on phones, proxy on web. Same rule as menus, same `proxyBase` seam |
| 6 | #42 pre-scoring: how many concurrent fetches on web, where each is a proxied hop? | 3, cache-first, cancelled when the list changes |
| 7 | #56 and #57 change the system prompt, so every combination is its own chat-cache key. Accept the fragmentation? | Yes. The alternative, sending options as a separate field, would move prompt-building server-side, which `backend_plan.md` §2 rules out |
| 8 | Which model runs #40, #56, #57, #64, #42, #65? | Opus. Everything else Sonnet |
| 9 | Should the venue-search proxy (B2) be rate limited per install like `/v1/chat`? | Decide after #38 shows how heavy the endpoint is. Default no |
| 10 | #99 (Settings backend URL override) is Phase 3 and low priority, but the phone end-to-end check in §6 needs a LAN base URL. Pull it forward? | Use `--dart-define` for now. Pull #99 forward only if the user tests on a phone often |

## 8. Run 1 decisions (2026-09-23)

The user answered the open questions above before the first run. What run 1
does and does not cover:

| Question | Decision |
|---|---|
| 1, 10bis fixture | Build #45 and #46 now against a synthetic fixture; re-record through #122 when the user runs the curl |
| Discovery chain | **Deferred.** #38 is a browser capture only the user can do, so #37, #39, #40, #41, #42, #43, #50, #63, #64 and #123 stay open and untouched |
| 2, #59 | Closed as completed after checking the three radio labels in both ARB files |
| 4, B1 and B2 | Filed as #122 (runs in wave 1) and #123 (blocked by #38) |
| 5 to 10 | Plan defaults accepted |

Run 1 waves, in order of dependency, with the worker model per issue:

| Wave | Issues | Opus | Sonnet |
|---|---|---|---|
| 1 | #119, #49, #48, #58, #45, #122, #52, #66 | none | all |
| 2 | #46, #57, #61, #47, #69, #65 | #57, #65 | #46, #61, #47, #69 |
| 3 | #56, #55, #51, #53, #68, #54 | #56 | #55, #51, #53, #68, #54 |

Merge order inside a wave follows the conflict hotspots in §3: #119 before
#49, #48 before #49, #57 before #61 and #65, and the `menu_screen.dart` PRs of
wave 3 one at a time.
