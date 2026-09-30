# Test audit: unnecessary and redundant tests

Scope: every `test(` / `testWidgets(` / `def test_` in `test/`, `integration_test/`
and `backend/tests/` (about 2,300 Dart tests and 190 Python tests, 50k lines).
Eight reviewers worked in parallel, one per slice, all read-only.

Criteria (Khorikov, Google Testing Blog, Fowler, Beck; see the earlier note):

- **A trivial** — asserts a constructor default, a getter over a field, a const
  equal to its own literal, `toString` contains a field, or two enum members differ.
- **B change-detector** — recomputes the expected value with the implementation's
  own expression, or asserts structure/order; breaks only on refactor.
- **C framework** — tests Dart, Flutter, SQLite, `lru_cache` or `Random`, not project code.
- **D duplicate** — another named test asserts the same behaviour at the same level.
- **E assertion-weak** — asserts only `isNotNull`, `completes`, `findsOneWidget` on
  the root, or something the type system already guarantees.

Deliberately **not** flagged: contract suites (`*_contract.dart`), architecture and
layer tests, fixture-shape tests, the failure-copy uniqueness test, contrast/token
pins, one RTL test per screen, "no plugin I/O in constructors" tests, enum
exhaustiveness guards, "never leaks the key/body" tests and golden-prompt tests.

Totals: **249 flagged** (A 100, B 25, C 4, D 105, E 15) and about 180 borderline.
The borderline items are listed at the end; act on the flagged ones first.

---

## 1. Cross-cutting patterns (the highest-value fixes)

1. **Const-canonicalised equality tests cannot fail.** In Dart two `const`
   expressions with equal arguments are the *same instance*, so
   `expect(constA, equals(constB))` and the matching `hashCode` assertion pass
   whatever `==` does. `test/models/venue_test.dart:217` already does it right
   with non-const objects. Affected: `analysis_test` 276, 316, 350, 882;
   `menu_test` 125, 403; `venue_test` 160, 192, 240; `verdict_colors_test` 59;
   `classification_rules_test` 397 (hand-built, but same shape). Either make one
   side non-const or delete.
2. **Proxy-variant duplicates in the adapters.** Only 502/504 and `ClientException`
   are proxy-conditional in `wolt_adapter.dart` and `tenbis_adapter.dart`; the
   404, 500, timeout and "carries the ref" cases run the same lines with or
   without a proxy. 10 tests.
3. **Backend proxy routes share one function.** `test_proxy_tenbis.py` repeats
   `test_proxy.py` for `_proxy_menu`; the search half of `test_proxy_discovery.py`
   repeats the nearby half for `_proxy_discovery`. 14 tests.
4. **Hebrew-copy twins with no RTL assertion.** One RTL test per screen is policy;
   the extra "renders the Hebrew title" twins only test the ARB delegate. 8 tests.
5. **Screen tests re-asserting a controller decision** (verdict filters, QR
   payload kinds, toggle isolation, `canAnalyse`) already pinned in
   `test/state/*`. About 10 tests.
6. **`toString mentions X` and constructor-default tests** across models and
   fakes. About 35 tests; pure category A.
7. **Vocabulary count pins** in `constants_test.dart` (`has 62 triggers` and
   three siblings): every vocabulary change breaks them and they prove nothing
   the per-trigger loops do not.
8. **Store round-trips repeated outside the contract suite** in
   `prefs_settings_store_test` and `hive_menu_cache_test`. 6 tests.

---

## 2. Flagged tests by file

### test/models

**analysis_test.dart**
- 276 `== returns true for rows with equal fields` — B (const canonicalisation)
- 295 `analysis defaults to null when the menu is unanalysed` — A
- 316 `== returns true for engines with the same model` — B
- 350 `== returns true for engines with the same reason` — B
- 371 `LlmEngine and RulesEngine are never equal to each other` — A (different classes)
- 872 `detail defaults to null` — A
- 882 `== returns true for failures with equal fields` — B
- 249, 303, 337, 380, 610, 841, 911 `toString mentions …` — A

**failures_test.dart**
- 58 `consentWithheld is distinct from notConfigured` — A (two enum members)

**menu_test.dart**
- 125 `== returns true for options with equal fields` — B
- 403 `== returns true for dishes with equal fields` — B
- 135, 425, 564, 861 `toString mentions …` — A

**scanned_menu_test.dart**
- 20 `a page equals itself` — A (reflexivity)

**venue_test.dart**
- 160 `== returns true for two refs with equal fields` — B
- 192 `== returns true for two venues with equal fields` — B/D of 217
- 240 `== treats absent optional fields (all null) as equal` — B/D of 217
- 286 `defaults the venue-search fields to empty or null` — A
- 179, 302 `toString mentions …` — A

### test/utils

**classification_rules_test.dart**
- 397 `RuleMatch equality holds for two equivalent results` — A (exercised by 796)
- 406, 414 `RuleMatch.toString describes …` — A

**constants_test.dart**
- 6 `appName is KetoClub`; 24, 29, 34, 39, 44, 49 (`menuCacheTtl`, `llmRequestTimeout`,
  `maxAnalysedDishes`, `maxWhyLength`, `maxModificationLength`, `minOverlapWordLength`) — A
- 117 `the default is 6 g inside a 2..25 g range` — A (clamping is tested at 124/131)
- 142, 148 `…WhyEn and …WhyHe are non-empty` — A/E
- 162, 191, 224, 263 `has N triggers` — B (count pins)
- 327 `noodle is labelled noodles and battered fish is named` — A/D of
  classification_rules_test 316/323

**menu_share_text_test.dart**
- 175 `never mentions a personal note — build is never given one` — E (input never passed in)

**text_normaliser_test.dart**
- 295 `menuFingerprint is stable across repeated calls` — A/D of 247
- 305 `menuFingerprint handles a menu with no dishes` — E (`isA<int>` on an `int`)

**wolt_headers_test.dart**
- 57 `woltWebClientId is deterministic for a seeded source` — C (`Random(seed)`)

### test/theme

**app_theme_test.dart**
- 37, 53 `AppTheme.light/dark registers a VerdictColors extension that resolves` — E
  (non-nullable fields, and `VerdictColors.of` falls back anyway; registration is
  proven by verdict_colors_test 162)
- 199, 215 `bilingual fonts renders Hebrew text in the light/dark theme` — B/E/D
  (probe text is English; asserts the constant passed through; brightness irrelevant)

**verdict_colors_test.dart**
- 47 `lerp at t=0.5 interpolates every field with Color.lerp` — B (mirrors the impl)
- 59 `equal tones compare equal and share a hashCode` — B (positive half)

### test/ root

**app_test.dart**
- 50 `follows the device locale before any tag has loaded` — D of 29 (identical assertion)

**di_test.dart**
- 36 `returns an AppDependencies for the production app` — A/D of 44
- 337, 354 `menuProxyBase returns null for a malformed url / non-http scheme` — D of
  280/288 (one-line delegate to `backendBaseUrl`)

### test/services/classifier and test/services/llm

**menu_classifier_contract_test.dart**
- 72 `the net-carb limit defaults to 6 g` — A

**scanned_menu_classifier_test.dart**
- 80 `== compares the menu and the analysis`; 98 `== compares the reason` — A
- 90 `toString names the scan reference`; 108 `toString names the reason` — A

**menu_response_parser_test.dart**
- 199 `parse given dishes as a valid empty list does not fail with badResponse` — D of 602
- 353 `parse given a valid verdict and non-empty why places the dish` — D of 97 + 229
- 570 `parse given a reply that mentions every source dish leaves unclassified empty` — D of 353/229
- 618 `parse given an all-unclassified reply … still returns MenuAnalysed` — D of 369

**menu_analysis_prompt_test.dart**
- 67 `schemaName is the literal menu_analysis` — A
- 73, 85 `systemPrompt contains the verdict definitions / keto rules … verbatim` — B/D
  (expected is the implementation's own call; goldens pin the prompt)
- 119 `systemPrompt states every modifiable dish must carry a modification` — E/D
- 138 `systemPrompt given default options omits any dietary constraint section` — D of 595
- 164 `systemPrompt given dietaryConstraints still contains …` — D of 619 loop
- 351 `userPrompt emits one line per dish, in menu order` — D of golden 189
- 450 `userPrompt joins more than one option group with a semicolon` — D of golden 189
- 551 `responseSchema has no description property on a dish` — D of 511
- 677 `the vision system prompt is the preamble, then the text system prompt` — B
  (expected is the impl's expression; vision_menu_classifier_test 95 covers it)

**heuristic_menu_classifier_test.dart**
- 282 `classify given a Hebrew dish returns a Hebrew why and modification` — D of loop 134
- 306 `classify given an English dish returns an English why and modification` — D of loop 98 / 165
- 749 `classify records the toggles it ran under in the result` — D of contract

**llm_menu_classifier_test.dart**
- 296 `classify records the options it was given on a placed result` — D of contract
- 519 `every toggle off posts the default prompt byte for byte` — D of 440

**scanned_classifier_router_test.dart**
- 153 `an empty transcription is noDishesFound` — D of vision_menu_classifier_test 223

**backend_chat_client_test.dart**
- 373 `a 422 for an out-of-bounds image is badResponse` — D of 683

**gemini_chat_client_test.dart**
- 976 `drops additionalProperties at every level` — D of 1022

### test/fakes/fakes_test.dart

Fake-restating (A unless noted): 40, 53, 62, 87, 93, 985; 119 `complete returns
fallback once the queue runs out` — B/D of 127.

Production value classes tested here (A unless noted): 329, 337, 349 (CachedMenu
`==`/`toString`); 548, 555, 563, 570, 590, 662, 669, 686, 746, 753 (AppSettings
`==`/`toString`/defaults); 763, 771, 778 (ChatCompleted); 786, 800, 810, 816
(ChatFailed); 440 `tryFrom returns null when filter is an unknown name` — D of
menu_controller_test 1645 (keep one of the two).

### test/services/menu, venue, location

**geolocator_location_service_test.dart**
- 62 `runsInBrowser defaults to kIsWeb` — A
- 308 `current maps a denial … when runsInBrowser is true` — D of 94 (`current` ignores the flag)
- 439 `current reflects result being changed after construction` — A

**location_result_test.dart**
- 130 `every LocationUnavailableReason value constructs and prints` — A + D of 139
- 139 `toString mentions the reason` — D of 130 (keep one)

**cached_menu_repository_test.dart**
- 89 `store writes the menu under its own ref` — D of contract 140
- 100 `load serves a stored scan menu from the cache` — D of contract 159 and of 113
- 140 `a scan menu removed from the cache is scanNotSaved again` — E (asserts only `isA<MenuFetchFailed>`)
- 344 `load with a ref resolved from a pasted 10bis.co.il URL still returns unsupportedSource` — D of 327

**tenbis_adapter_test.dart**
- 55 `source is tenbis` — A/D of contract
- 108 `fetch returns a menu carrying the requested ref` — D of contract 70
- 482 `… TimeoutException to offline with a proxy configured` — D of 286
- 504 `… proxied 404 to notFound` — D of 125
- 529 `… proxied 500 to platformChanged` — D of 148
- 556 `… carrying the requested ref through a proxy` — D of contract run at 315

**tenbis_menu_mapper_test.dart**
- 169 `toMenu derives the same category id across two calls` — A/B (pure function twice)
- 467 `toMenu returns platformChanged for the malformed fixture` — D of 487 (same shape)
- 785 `toMenu tolerates a dish with no dishOptionsList key at all` — D of 382

**text_menu_source_test.dart**
- 143 `a header is never a dish` — D of 130
- 151 `a short line alone between blank lines starts a category` — D of 182

**direct_website_fetcher_test.dart**
- 515 `a CR-only robots.txt still refuses` — D of robots_txt_test 26

**website_adapter_test.dart**
- 92 `is the website source` — A/D of contract
- 177 `a Hebrew תפריט link is followed` — D of locator 56 + 151
- 197 `a link encoded in windows-1255 is followed, never thrown` — D of locator 104 + 151

**wolt_adapter_test.dart**
- 63 `source is wolt` — A/D of contract
- 191 `fetch returns a menu carrying the requested ref` — D of contract 70
- 588 `… TimeoutException to offline with a proxy configured` — D of 373
- 610 `… proxied 404 to notFound` — D of 208
- 635 `… proxied 500 to platformChanged` — D of 231
- 662 `… carrying the requested ref through a proxy` — D of contract run at 401

**qr_payload_router_test.dart**
- 148 `names the platform a Tabit code belongs to` — D of table row 80

**venue_ref_resolver_test.dart**
- 220 `resolve is pure: the same input always resolves the same way` — A/B

**wolt_venue_search_service_test.dart**
- 624 `returns the venues nearest first` (proxy group) — D of contract run at 116

### test/services/platform, storage; test/state

**app_logger_test.dart** — 30 `info sends the sink a redacted message` — D of contract 47
**clock_test.dart** — 16 `two successive calls do not go backwards` — C
**connectivity_test.dart** — 112 `isOnline never throws regardless of the channel result` — D of 92
**hive_menu_cache_test.dart** — 53 `write then read round-trips an entry with an LlmEngine analysis` — D of contract 51
**prefs_settings_store_test.dart**
- 141 `write then read round-trips every field` — D of contract 27
- 402 `AppSettings JSON round-trips the dietary toggles` — D of contract 47
- 417 `AppSettings.tryFrom reads missing toggle keys as off` — D of 357
- 495 `write then read round-trips a non-default themeMode` — D of contract 100
- 507 `read never returns null even on a virgin store` — D of contract 18
**secure_api_key_store_test.dart** — 136 `a channel error carrying a message never surfaces it` — D of 66

**carb_budget_controller_test.dart**
- 48 `setBudget with a negative value clamps to 1` — D of 36
- 73 `setBudget with a different value notifies` — D of 54 + 29
- 112 `clear after clear does not notify again` — D of 103
- 123 `setBudget then clear then setBudget works correctly` — D/E
**theme_mode_controller_test.dart** — 104 `themeMode maps every AppThemeMode` — D of 10/19/60
**scanned_pages_registry_test.dart** — 73 `defaults to a small capacity` — A
**scan_controller_test.dart** — 50 `exposes the scanned-menu classifier it was built with` — A
**settings_controller_test.dart**
- 82 `load notifies listeners exactly twice` — D of 69
- 187, 203, 264 `initial themeMode / netCarbLimitGrams / cachedMenuCount before load …` — A
**menu_controller_test.dart**
- 683 `open notifies listeners exactly three times …` — D of 97 + 989
- 698 `open notifies listeners exactly twice on a failed fetch` — D of 1116
- 1131 `open hands the classifier an onEngineStarted listener` — D/E
- 1194 `isClassifying is true for exactly the three classifying phases` — B
- 1645 `a filter name AppSettings.tryFrom does not recognise degrades to null` — D of fakes_test 440
- 1810 `netCarbLimitGrams is the default before any analysis` — A
**venue_search_controller_test.dart** — 253 `a hyphenated slug still resolves as a Wolt slug` — D of 145

### test/widgets

**dish_card_test.dart**
- 284 `build shows the dish description when present` — A
- 435 `net-carb chip shows no suffix when no budget is set` — D of 368
**skeletons_test.dart**
- 91, 123 `build renders on the light/dark theme with no error` (DishCard, SavedEntry skeletons) — E
- 71, 103, 135 `build excludes its own semantics` — D of 150
**verdict_counter_tiles_test.dart** — 97 `each tile carries a semantic label naming its count` — D of 138
**rules_reason_banner_test.dart** — 223 `never renders empty parentheses` — D of 60 + failure_copy_test 238
**mobile_qr_scanner_test.dart** — 58 `is available` — A (constant getter)
**carb_budget_field_test.dart** — 54 `shows the hint text` — A

### test/screens

**waiter_card_sheet_test.dart**
- 151 `tapping copy shows the actionCopied confirmation` — D of waiter_script_widget_test 121 (the snackbar lives in the widget)
- 260 `never raises the brightness with no screenBrightness given` — E
**saved_screen_test.dart** — 434 `build under Locale(he) renders the Hebrew empty copy` — D/C of 167
**settings_screen_test.dart**
- 133 `build offers no field to enter a credential` — D of 843
- 396 `build shows 0 menus cached with nothing saved` — D of 469 + controller 264
- 407 `build shows the seeded count` — D of 445 + controller 269
- 522, 671 `the section sits under … and above …` — B (`getTopLeft` ordering)
- 608 `both buttons carry a localized tooltip` — A
- 799 `build under Locale(he) renders the Hebrew title` — D/C of 812
**scan_screen_test.dart**
- 169 `Analyse stays disabled for whitespace only` — D of scan_controller_test 72 (+160/181)
- 255 `the empty-paste copy is in Hebrew under Locale(he)` — D/C of 219
- 671 `on web notConfigured says scanning needs the server` — D of loop 649 + scan_failure_copy_test 28
- 716 `consent withheld says to allow AI analysis in Settings` — D of loop 649
- 812 `the Hebrew oversize copy is shown under Locale(he)` — D/C of 456
- 960 `a code that is not a URL suggests photographing too` — D of 943 + controller 708/720
**venue_search_screen_test.dart**
- 268 `an empty field shows no invalid message` — E/D of controller 183
- 786 `build under Locale(he) renders the Hebrew title` — D/C of 726
**menu_screen_test.dart**
- 398 `after an AI call falls back the screen names the rules, not the AI` — D of 375 + controller 1044
- 774 `the refresh action carries a semantics label / tooltip in Hebrew too` — A/C
- 907 `blockedByBrowser shows no action, only the copy …` — D of loop 850 (else branch) + 1120
- 1177 `build shows the filter the engine chip and a DishCard per visibleRows` — B/D of 444/1265/1763/2411
- 1811 `tapping the yellow tile filters to modifiable dishes only` — D of 1763 + controller 332/363/393
- 2159 `a dish with no note shows the "Add a note" prompt` — D of 2198 + 2238
- 2434 `a search with no matching dish shows menuNoResults` — D of 1903

### integration_test/flows

- **app_launch_flow_test.dart** 13 `user opens the app and sees the venue search screen` — E
  (only `find.text(appName)`); the sole flow through the real `di.dart`, so if kept,
  assert something the search screen shows.
- **appearance_flow_test.dart** 36 `choosing Dark in Settings re-themes the running app` — D of app_test 134
- **discovery_chips_flow_test.dart** 36 `Open now hides and restores … Keto 8+ …` — D of
  venue_search_screen_test 632/663/679 concatenated; never leaves the tab
- **dish_note_flow_test.dart** 133 `clearing a note in the editor removes it from the card` — D of menu_screen_test 2238
- **scan_paste_flow_test.dart** 132 `a paste with no dishes shows the empty-paste copy` — D of scan_screen_test 219
- **scan_qr_flow_test.dart** 168, 182, 197, 237 (Tabit, Instagram, non-link, no scanner) — D of
  scan_screen_test 928/943/960/861; the flow adds only the tab tap
- **tenbis_paste_flow_test.dart** 109 `pasting a bare 10bis id behaves the same way` — F/D of 81
  + venue_search_screen_test 315; 132 `… not-found message` — D of menu_screen_test 1120/850
- **backend_unreachable_fetch_flow_test.dart** 39 — D of menu_screen_test 822/850; the
  repository is stubbed, so nothing backend-related runs

### backend/tests

**test_config.py**
- 6 `test_defaults_match_documented_values` — A (19 literals; does not read `.env.example`)
- 29, 35 `test_llm_configured_is_false/true …` — A/D of test_health 13/24
- 41 `test_get_settings_is_cached` — C (`lru_cache`)
**test_db.py**
- 12 `test_sqlite_engine_enables_wal_journal_mode` — E (accepts `memory`, so the listener could be deleted)
- 37 `test_get_session_commits_on_success` — E (asserts `StopIteration` only)
- 53 `test_get_session_rolls_back_on_error` — E (asserts re-raise only)
**test_chat.py**
- 556 `test_over_the_per_install_limit_is_rate_limited` — D of test_chat_cache 207 + test_rate_limit 88
- 803 `test_a_request_with_images_still_requires_the_install_id` — D of 499 (dependency runs before body)
- 815 `test_a_request_with_images_still_rejects_authorization` — D of 473
**test_chat_cache.py** — 148 `test_second_identical_request_is_served_from_the_cache` — D of 207 + test_chat 687
**test_proxy_tenbis.py** — 58, 69, 111, 122, 133, 149, 168 — D of test_proxy 58, 69, 112, 123, 134, 150, 169 (shared `_proxy_menu`)
**test_proxy_discovery.py**
- 320 `test_over_the_per_install_limit_is_rate_limited` — D of 283 + test_rate_limit 88
- 373, 386, 399, 412, 542, 558 (search variants) — D of 69, 86, 101, 116, 161, 181 (shared `_proxy_discovery`)
**test_website_route.py** — 247 `test_a_missing_robots_txt_allows` — D/E (every success test uses `_no_robots`)

---

## 3. Borderline (judgement calls, not counted)

- **Parser rules re-run through `parseScanned`**: `menu_response_parser_scanned_test.dart`
  312–430 (about 15 tests) re-run text-path fixtures through the second entry point. Shared
  `_decode`/`_judge`, so D, but the file header says it is deliberate.
- **Contract-suite tautologies** (policy suites, owner's call): `menu_repository_contract`
  56, 82, 172, 188, 196, 208; `platform_menu_adapter_contract` 33, 39; `llm_chat_client_contract`
  18, 29, 42, 51, 83; the "never throws" siblings in `settings_store_contract` 18,
  `notes_store_contract` 128–146, `install_id_store_contract` 33, `menu_cache_contract`
  33, 151, 157, 212, 231, 309, 315.
- **Light/dark loops** whose second iteration asserts nothing theme-dependent:
  `saved_screen_test` 137/167, `menu_screen_test` 325/1639, `venue_search_screen_test` 147/178.
- **Hebrew-copy twins** left in: `settings_screen_test` 628, 779, 955;
  `venue_search_screen_test` 980; `menu_screen_test` 466, 2019.
- **Flow overlaps**: `backend_unreachable_analysis_flow` 110 vs `offline_analysis_flow` 163
  (parameterise); `consent_withheld_flow` 164 is a subset of 183; `menu_refresh_flow` 81 vs
  `error_recovery_flow` 91; `net_carb_limit_flow` 140; `scan_qr_flow` 112/130/150;
  `scan_pdf_flow` 41 vs `scan_photo_flow` 45.
- **Screen re-asserting controller**: `settings_screen_test` 723, 742, 761, 281, 921;
  `venue_search_screen_test` 315; `menu_screen_test` 615, 666, 822, 2175, 2604;
  `scan_screen_test` 852.
- **Single `findsNothing` on the default state**: `venue_search_screen_test` 513, 768, 804;
  `menu_screen_test` 1392.
- **Structure/order pins**: `settings_screen_test` 117; `venue_search_screen_test` 222;
  `waiter_card_sheet_test` 108; `skeletons_test` 58.
- **Data-mirroring vocabulary tests** in `constants_test` (207, 229, 236, 275, 281, 346,
  366, 442, 454) whose behaviour is asserted in `classification_rules_test`.
- **Model tests living in store or controller files**: `prefs_settings_store_test` 163, 180,
  272, 297, 316, 340, 518, 544 vs `fakes_test` 403, 416, 612, 635, 708, 717.
- **Initial-value tests on controllers**: `carb_budget` 21, 25; `locale` 10; `theme_mode` 10;
  `saved` 41; `menu_controller` 221, 227, 903, 983, 1317, 1458, 1634, 2243, 2424;
  `scan_controller` 65, 230, 642, 720; `settings_controller` 41, 406, 418, 441, 570;
  `venue_search_controller` 145, 157; `saved_controller` 172.
- **Null-implementation and fake-only tests**: `screen_brightness_test` 98, 104;
  `page_picker_test` 10; `qr_scanner_test` 10; `connectivity_test` 62, 71, 123–135;
  `app_logger_test` 6, 13, 20, 105; `clock_test` 6; `geolocator_location_service_test`
  297, 422–474; `fakes_test` 71, 77, 160, 369, 484, 532.
- **Classifier/LLM**: `menu_response_parser_test` 214, 704, 717; `menu_analysis_prompt_test`
  129, 147; `llm_menu_classifier_test` 527–557 vs prompt-test 619/631;
  `classifier_router_test` 326; `scanned_classifier_router_test` 131;
  `vision_menu_classifier_test` 186; `backend_chat_client_test` 354;
  `gemini_chat_client_test` 290, 355.
- **Services**: `cached_menu_repository_test` 263, 479, 585; `wolt_menu_mapper_test` 100,
  599; `tenbis_menu_mapper_test` 45; `wolt_venue_mapper_test` 47, 86;
  `wolt_venue_search_service_test` 662, 728; `website_adapter_test` 254;
  `venue_ref_resolver_test` 209; `price_format_test` 6, 63; `analysis_test` 810, 926,
  950, 737; `failures_test` 6, 34; `scanned_menu_test` 55; `app_theme_test` 110, 142;
  `contrast_test` 86–96 (helper self-test), 125, 130, 158 (exact-ratio pins);
  `verdict_colors_test` 36; `app_test` 277; `di_test` 120; `classification_rules_test` 385.
- **Widgets**: `dish_card_test` 303, 324; `category_chips_test` 31 (does not assert order
  despite its name); `app_shell_test` 52; `verdict_counter_tiles_test` 26; `venue_card_test`
  177; `engine_chip_test` 50; `carb_budget_field_test` 47, 60, 134.
- **Backend**: `test_db` 24, 30 (pool class, not behaviour); `test_chat` 499 params;
  `test_chat_cache` 127, 135; `test_proxy` 58, 213; `test_proxy_tenbis` 188;
  `test_proxy_discovery` 86, 453; `test_health` 57; `test_gemini_schema` 49, 55, 62 vs 75;
  `test_website_route` 172, 234; `test_rate_limit` 97.

---

## 4. Caveats

- `UNIT_TEST_CONVENTIONS.md` lists equality and `toString` as things to test on
  models, so the category-A findings on `==`/`toString` are a convention call. The
  const-canonicalised ones (pattern 1) are not: they cannot fail and should go or
  become non-const regardless.
- The 80% line-coverage gate in `tool/check.sh` may drop if the assertion-weak
  tests that are the only ones touching a line are removed (`app_logger_test` 6–20,
  the null implementations). Check coverage after any pass.
- Line numbers are as of this audit; they shift after any edit.
