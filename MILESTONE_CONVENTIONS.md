# Milestone Conventions

Guidelines for organizing work into milestones and tracking progress toward KetoClub's phases.

## Milestone Structure

Milestones correspond to **project phases** and **feature groups** within each phase.

### Naming Convention

```
Phase N: [Feature Group Name]
```

### Examples

- `Phase 1: Wolt API Integration`
- `Phase 1: Menu Classifier Engine`
- `Phase 2: Geolocation & Venue Search`
- `Phase 2: 10bis Integration`
- `Phase 3: Verified End to End`
- `Phase 5: Hosted Service`

> **These are the milestones actually created on GitHub** (verified against the
> repository's milestone list while closing issue #36), not an illustrative plan.
> An earlier draft of this document listed different names for several of
> them — e.g. a Phase 1 "API Client Infrastructure" and "Waiter Script Generation"
> and a Phase 4 "Meal Logging" — that were never created. `D8` in
> `architecture.md` §14 rules meal logging out of scope entirely ("nothing about
> the user is stored"), which is why no such milestone exists in any phase.

## Phase Breakdown

### Phase 1: Core Parsing & Classification

**Goal**: Build the restaurant menu ingestion and keto classification engine (no backend).
**Status**: built and merged — see `CLAUDE.md`'s status banner and `HANDOFF.md`.

**Milestones (as created on GitHub):**
1. `Phase 1: Domain Foundations` — models, service-boundary result types, the
   project skeleton and day-zero CI
2. `Phase 1: Menu Classifier Engine` — the bilingual heuristic engine and the
   OpenRouter-backed LLM classifier behind one `MenuClassifier` interface
3. `Phase 1: Wolt API Integration` — the Wolt adapter, mapper, cache and
   paste-a-URL resolution
4. `Phase 1: Core UI Screens` — venue search, the classified menu screen, the
   Waiter Card and Settings

**Success Criteria:**
- ✅ Fetch and classify menus from Wolt. **Not** 10bis — no 10bis adapter exists;
  a pasted 10bis link is recognised but fails with `unsupportedSource`
  (`architecture.md` §16 step 6, now tracked as its own `Phase 2: 10bis
  Integration` milestone rather than a Phase 1 one)
- ✅ Classify dishes 🟢/🟡/🔴 with an LLM primary engine and a rule-engine
  fallback, table-driven-tested against README's examples plus Hebrew equivalents
- ✅ Generate waiter scripts for modifiable (🟡) dishes, in the menu's language
- ✅ App builds for web, iOS, and Android (a physical-device run is still
  outstanding — see `HANDOFF.md`)
- ⏳ Each of these four milestones still has open issues on GitHub even though
  the code shipped — closing this documentation issue does not itself close them

### Phase 2: Mobile Interface & Discovery

**Goal**: Complete the user-facing mobile app with geolocation, the 10bis adapter,
and filtering. **Status**: built and merged (2026-09-24); what remains in its
open milestones is person-run recording and measurement.

**Milestones (as created on GitHub):**
1. `Phase 2: Geolocation & Venue Search` — device location + venue discovery.
   Built (#154, D13) against synthetic fixtures; open: #38 (the recording) and
   #155 (the web proxy header bug)
2. `Phase 2: 10bis Integration` — the 10bis adapter. Built (#134) against a
   synthetic fixture; open: #44 (the recording)
3. `Phase 2: Menu Display & Navigation` — closed
4. `Phase 2: Settings & Preferences` — closed (the three dietary toggles shipped
   here, #56)
5. `Phase 2: Polish & Performance` — open: #65 (phone timings) and #169
   (visual-audit follow-ups)

**Success Criteria:**
- ✅ Users can search nearby restaurants by location
- ✅ 10bis menus fetch and classify the same way Wolt's do
- ✅ App displays filtered results (Green/Yellow/Red)
- ✅ Works offline for cached menus
- ⏳ <3s load time on 4G network — unmeasured until #65 runs on a phone

### Phase 3: Community Database & Reviews

**Goal**: Add the CORS-forwarding backend (unblocking the web build), persistent
user feedback, and venue ratings. **Status**: the first two milestones are
**built and merged**; see `architecture.md` §14 D11/D12 and `backend_plan.md`
for the backend's design and its own issue range (#94–#109).

**Milestones (as created on GitHub):**
1. `Phase 3: Backend Foundations` — **shipped.** The menu-proxy backend that
   unblocks web fetching (`backend_plan.md` §1; `architecture.md` D11).
   Issue #98 (the `openrouter.ai` single-file boundary, since generalised to
   four host-string rules) was folded into #102's scope rather than done as
   its own issue; #99 (a Settings backend-URL override) is still open.
2. `Phase 3: Hosted Classification` — **shipped.** A backend-held Google Gemini
   key replaces bring-your-own-key entirely (`architecture.md` D12) — there is
   no fallback to a user-supplied key, unlike this milestone's original plan.
   Issue #104 (reword Settings and failure copy for a served model) was folded
   into #102's scope for the same reason as #98: one worker owning the whole
   reason-enum change made more sense than reviewing it twice.
3. `Phase 3: Verified End to End` — **the re-planned remainder of Phase 3**
   (2026-09-24, `ROADMAP.md`, D18): the personal backend proven against real
   Gemini, real Wolt and 10bis responses and a real phone (#178, #165, #166,
   #168), AI on by default (#167), the LAN URL override (#99, still filed under
   *Backend Foundations*)
4. ~~`Phase 3: Community API`~~, ~~`Phase 3: User Ratings & Reviews`~~,
   ~~`Phase 3: Venue Submission`~~, ~~`Phase 3: Verified Badges`~~ — **closed
   2026-09-24.** Community features are deferred until the backend is hosted
   (Phase 5) and redesigned so the server keeps no per-install record; #164
   carries the re-plan and lists the closed issues

**Success Criteria:**
- ✅ Web build fetches live menus through the local backend proxy when
  configured (not "without a local proxy" — a local proxy is exactly how this
  shipped; see `architecture.md` §13)
- ✅ Classification works with no key entered anywhere, hosted by the backend
- ⏳ The real prompt has run against the pinned Gemini model (#165)
- ⏳ A real Wolt and a real 10bis response are checked in as fixtures (#22, #44)
- ⏳ A phone has run the app against the LAN backend (#166, #99)
- ⏳ A fresh install uses AI analysis by default (#167)

### Phase 4: Advanced Features

**Goal**: Add OCR vision processing and advanced dietary customization.
**Status**: planned.

**Milestones (as created on GitHub):**
1. `Phase 4: Menu Scanning` (renamed from *OCR Menu Scanning*; absorbed the
   *Vision Classifier* milestone, now closed) — paste a menu (#83), then
   photographed and PDF pages sent as image parts on `POST /v1/chat` (#170) and
   read by a `ScannedMenuClassifier` (#89) behind the Scan tab (#82), with the
   vision smoke test (#88) as the go/no-go. On-device OCR is not built
   (`architecture.md` D15; `m16_menu_scanner_research.md` is superseded on
   the engine choice)
2. `Phase 4: Dietary Customization` — pesco-keto (#85; seed-oil, dairy-free and
   carnivore shipped in Phase 2), a custom constraint (#86), rule naming (#87)

**There is no Phase 4 "Meal Logging" milestone.** `architecture.md` D8 rules meal
logging and macro tracking out of scope for KetoClub entirely — that design in
`m15_meal_entry_research.md` belongs to a different application.

**Success Criteria:**
- A pasted menu classifies like a fetched one, with no prices shown
- Photographed and PDF pages are read by Gemini with dish-name recall measured
  on real Israeli menus (#88); no on-device OCR
- Users can switch between dietary rulesets

### Phase 5: Hosted Service

**Goal**: Run the backend on a public host so the primary classifier reaches
users without a LAN. **Status**: planned; #109 is the entry point.

**Milestone:** `Phase 5: Hosted Service` — deploy config, HTTPS and CORS
(#171), a persistent limiter and a global Gemini spend cap (#172), the abuse
posture for a spoofable install id (#173), the backend URL per build flavour
(#174), D13 option B (#175), then the community re-plan (#164).

### Phase 6: More Platforms

**Goal**: Tabit and Ontopo. **Status**: planned, research first.

**Milestone:** `Phase 6: More Platforms` — #176 (Tabit), #177 (Ontopo).

## Milestone Properties

### Due Date
- Set realistic due dates (typically 2-6 weeks per milestone)
- Account for review time and iteration

### Description
Include a brief overview of what the milestone covers:

```markdown
## Overview
Implement restaurant API clients for Wolt and 10bis to fetch live menus.

## Goals
- [ ] WoltApiClient fetches and parses menus
- [ ] 10bisApiClient fetches and parses menus
- [ ] Error handling for network failures
- [ ] Unit tests for both clients
- [ ] Documented in CLAUDE.md

## Issues Included
#1, #2, #3, #4, #5 (auto-populated as issues are linked)

## Timeline
- Start: Jan 15
- Target: Feb 15
```

### Tracking Progress

- Use GitHub's milestone progress bar
- Aim to close issues in order of priority
- Adjust scope if unexpected blockers arise
- Post weekly updates in milestone description

## Issue-to-Milestone Assignment

1. **Create issue** (see `ISSUE_CONVENTIONS.md`)
2. **Assign to phase** (label with Phase 1, 2, 3, or 4)
3. **Link to milestone** — Select the relevant milestone in the issue sidebar
4. **Prioritize within milestone** — Use priority labels (critical, high, medium, low)

## Milestone Workflow

### Planning Phase
- Define scope and goals
- Estimate effort for each issue
- Set realistic due date

### Active Development
- Track issue progress weekly
- Update milestone description with blockers
- Adjust scope if needed

### Closure
- Close all completed issues
- Mark milestone as complete
- Document lessons learned
- Plan next milestone

## Example Milestone

```markdown
# Phase 1: Wolt API Integration

## Overview
Implement the Wolt API client to fetch restaurant menus in real-time.
Wolt is the easiest entry point (no auth, standardized JSON).

## Goals
- [ ] Implement WoltApiClient class
- [ ] Parse JSON response into Menu/Dish models
- [ ] Handle network errors gracefully
- [ ] Add comprehensive unit tests
- [ ] Document in CLAUDE.md

## Progress
4 of 5 issues completed (80%)

## Timeline
- Start: January 8, 2025
- Target: January 22, 2025
- Status: On track ✅

## Blockers
None currently. Nice to have: consider caching for offline support (Phase 2).

## Related Issues
#1, #2, #3, #4, #5
#6 (depends on completion)

## Notes
- Wolt API is stable and well-documented
- Plan for 10bis integration in next milestone
- Consider reverse-engineering for other platforms (Phase 1 later)
```

## Milestone Labels

Use these labels alongside milestones to organize work:

- **Phase 1** … **Phase 6** — Indicates which phase the issue belongs to
- **priority: critical/high/medium/low** — Within a phase, indicates urgency
- **type: feature/bug/chore/docs** — Type of work
- **platform: web/ios/android** — Which platform(s) are affected

## Tips for Success

1. **Start small**: First milestone should be achievable in 2-4 weeks
2. **Communicate clearly**: Update milestone description weekly
3. **Be flexible**: Adjust scope if unexpected challenges arise
4. **Celebrate progress**: Close milestones publicly when complete
5. **Document lessons**: Note what went well and what to improve next time
6. **Plan buffer**: Leave 20% of capacity for unexpected issues
