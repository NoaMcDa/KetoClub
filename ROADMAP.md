# KetoClub roadmap — re-planned 2026-09-24

This is the record of the roadmap challenge that closed the Phase 2 build:
what was found when the remaining features, the architecture and the phase
design were assessed against the code, the decisions the owner took, the
phases as they now stand, and where every open issue went. `architecture.md`
stays authoritative for design (D14–D18 in §14 record the decisions below);
this file is the order of work.

## 1. What the assessment found

The two audits (the planning documents; the code at `cbc1ce9`) and the full
issue list turned up nine things that change the plan.

1. **The primary classifier reached nobody.** D2 makes the language model
   primary, but the backend URL came only from `--dart-define`, no CI build
   passed it, no hosted backend existed, and consent defaulted to off. Every
   installable build was rules-only. Hosting (#109) was filed as low-priority
   research.
2. **The Wolt menu path may already be dead.** Two 2025–2026 clients report
   the shipped `/v4/venues/slug/{slug}/menu/data` returning `200` with an
   empty body anonymously (`phase2_discovery_research.md` §2.5). Nobody had
   run `tool/record_wolt_fixture.sh`, and no issue existed for the port to
   the assortment endpoint.
3. **The community milestone contradicted the privacy architecture.** Ratings
   and dish feedback were to be upserted on `install_id`; constraint 1, D8,
   D11 and §11 all say the backend keeps caches, never a per-user record, and
   the id exists for rate limiting only. It also had no population without a
   host, and the id is spoofable. Eleven issues hung off it.
4. **The OCR plan was designed for a different model contract.** m16 chose
   on-device Tesseract because the user's own OpenRouter key had a 50-a-day
   quota and free vision models rotated. Under D12 the operator's Gemini 2.5
   Flash key is multimodal. On-device Hebrew OCR was the weakest link (9 of 23
   names exact, prices wrong) and would have added heavy native dependencies.
   The "Vision Classifier" milestone was incoherent as filed ("a vision model
   for OCR'd text"; `MenuClassifier.classify(Menu)` cannot carry images). No
   paste-a-menu path existed although three documents called it the web
   fallback.
5. **A third of Phase 4 had already shipped**: the seed-oil-free, dairy-free
   and carnivore toggles landed in Phase 2 (#56) in both engines, while #85
   still asked to build them and #86/#87 were "blocked by" closed issues.
6. **Nobody had called Gemini, run a phone or measured performance, and no
   issue tracked the first two.** #16 was closed with OpenRouter; the smoke
   test and the device run lived only in prose.
7. **Tabit and Ontopo** existed only as README claims and enum slots.
8. **Several documents still said Phase 2 was unbuilt**, and six code
   comments were stale.
9. **The session handoff listed follow-ups never filed** and asked to be
   deleted once they were.

## 2. Decisions

| # | Decision | Recorded as |
|---|---|---|
| 1 | Scanning is vision via Gemini: paste-text first, then photo and PDF pages as image parts through the backend. On-device OCR is dropped. | D14, D15 |
| 2 | All community work is deferred until the backend is hosted and the storage keeps no per-install record. | D18, #164 |
| 3 | The owner runs the person-only checks (Wolt fixture, discovery capture, 10bis capture, Gemini smoke test, phone run). | #178 |
| 4 | The backend stays personal-use (laptop/LAN) for now; a hosted service is Phase 5. | D18, #109 |
| 5 | AI analysis is on by default with the disclosure shown; a stored refusal wins. | D16, #167 |
| 6 | Tabit and Ontopo are Phase 6. | #176, #177 |
| 7 | A runtime backend URL override in Settings, so a phone reaches the LAN backend. | D17, #99 |

## 3. The phases now

| Phase | Meaning | GitHub milestones |
|---|---|---|
| 1–2 | Built. Only person-run recordings remain. | `Phase 1: Wolt API Integration` (#22), `Phase 2: Geolocation & Venue Search` (#38, #155), `Phase 2: 10bis Integration` (#44), `Phase 2: Polish & Performance` (#65, #169). The other Phase 1–2 milestones are closed. |
| 3 | The personal backend, verified end to end. | `Phase 3: Backend Foundations` (#99), `Phase 3: Verified End to End` (#178, #165, #166, #167, #168). *Hosted Classification* is closed (done); *Community API*, *User Ratings & Reviews*, *Venue Submission*, *Verified Badges* are closed (deferred). |
| 4 | Menu scanning via Gemini vision; dietary customisation. | `Phase 4: Menu Scanning` (#83, #170, #88, #89, #82, #84), `Phase 4: Dietary Customization` (#85, #86, #87). *Vision Classifier* is closed (absorbed). |
| 5 | The hosted service, then community on top. | `Phase 5: Hosted Service` (#109, #171, #172, #173, #174, #175, #164). |
| 6 | More platforms. | `Phase 6: More Platforms` (#176, #177). |

## 4. Order of work

1. **#155** — the web Discovery header bug. Without it the only runnable
   Discovery path is broken.
2. **#178** — the person-run checklist. **#22 first**: its result decides
   whether the Wolt menu adapter must be ported (#168) or #168 is closed.
   Then #38, #44, #165 (Gemini smoke test), #166 (phone run, with #65's
   timings).
3. **#167** — AI on by default (D16).
4. **#99** — the LAN backend URL override (D17).
5. **#83** — paste a menu (D14). No blockers, no new dependencies.
6. **#170** — image parts on `/v1/chat`; **#88** — the vision smoke test.
7. **#89** — the vision classifier; **#82** — the Scan tab; **#84** — the flows.
8. **#85, #86, #87** — dietary customisation, any time after #167.
9. **Phase 5** when the owner decides to host: #109, then #171–#175, then #164.
10. **Phase 6**: #176, #177.

## 5. What was closed and why

| Issues | Reason |
|---|---|
| #74, #75, #76, #77, #78, #79, #80, #105, #106, #107, #108 | Community features deferred (D18). Each carries a comment; #164 lists them for the re-plan. |
| #81 | On-device OCR research superseded by D15; the measurement now happens in #88 against Gemini's vision. |

## 6. What was rewritten

| Issue | Change |
|---|---|
| #22 | Critical: settles the empty-body question; blocks #168. |
| #38, #44 | Trimmed to the recording; the code no longer waits on them. |
| #65 | Medium: the code half is done; the phone numbers are the deliverable. |
| #99 | High, Phase 3: the LAN override, with the resolver design (D17). |
| #109 | The Phase 5 entry point, with its sub-issues and the Wolt IP-reputation risk. |
| #82, #83, #84, #88, #89 | Rewritten for vision-first scanning (D14, D15). |
| #85, #86, #87 | Narrowed to what has not shipped; blockers on closed issues removed. |
| #155 | Adds the proxy-route contract check. |

## 7. Repository changes made with this re-plan

`architecture.md` (status header, §16 extension table, D14–D18, §17 items 7
and 8), `CLAUDE.md`, `README.md`, `HANDOFF.md`, `MILESTONE_CONVENTIONS.md`,
`ISSUE_CONVENTIONS.md`, `backend_plan.md`, `docs/RELEASE.md`; six stale code
comments; `SESSION_HANDOFF.md` deleted (its process rules moved to
`HANDOFF.md`, its follow-ups filed as #169 and #178).
