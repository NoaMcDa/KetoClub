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
- `Phase 3: User Ratings & Reviews`

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
and filtering. **Status**: built, apart from fixture recordings and a physical-device
run — see `CLAUDE.md`'s status banner and `HANDOFF.md`.

**Milestones (as created on GitHub):**
1. `Phase 2: Geolocation & Venue Search` — device location + venue discovery.
   Blocked on discovery: no Wolt venue-search endpoint is known
   (`architecture.md` §17 open question 2)
2. `Phase 2: 10bis Integration` — the 10bis adapter. Blocked on a live capture:
   `dishOptionsList`'s shape, a stable category id, and a real restaurant id/URL
   are all unverified (`HANDOFF.md`)
3. `Phase 2: Menu Display & Navigation` — improved UI, search filtering, bookmarks
4. `Phase 2: Settings & Preferences` — user settings, dietary rule customization
5. `Phase 2: Polish & Performance` — responsive design, loading states, error handling

**Success Criteria:**
- Users can search nearby restaurants by location
- 10bis menus fetch and classify the same way Wolt's do
- App displays filtered results (Green/Yellow/Red)
- Works offline for cached menus
- <3s load time on 4G network

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
3. `Phase 3: Community API` — the server side of ratings, reviews and submissions
4. `Phase 3: User Ratings & Reviews` — post-visit feedback mechanism
5. `Phase 3: Venue Submission` — crowdsourced venue directory
6. `Phase 3: Verified Badges` — keto-friendly venue verification

**Success Criteria:**
- ✅ Web build fetches live menus through the local backend proxy when
  configured (not "without a local proxy" — a local proxy is exactly how this
  shipped; see `architecture.md` §13)
- ✅ Classification works with no key entered anywhere, hosted by the backend
- Users can rate venues after dining — not built (milestone 3–6 territory)
- Community ratings influence venue ranking — not built
- Verified keto-friendly badges visible to users — not built
- Support for user submissions of new venues — not built

### Phase 4: Menu Scanning

**Goal**: Let a user get the same color-coded breakdown for a menu no delivery
platform serves: text they paste, photographs of a physical menu, or a PDF.
**Status**: core built and merged; see `architecture.md` §16's Phase 4 steps.

**Milestone (as created on GitHub):**
1. `Phase 4: Menu Scanning` — the only Phase 4 milestone. It absorbed the
   separate "Vision Classifier" milestone an earlier draft listed, because the
   vision engine is the scan path itself and not a second engine behind
   `MenuClassifier` (`architecture.md` D15 — Gemini reads the pages, so there is
   no on-device OCR and the old "OCR Menu Scanning" milestone name no longer
   describes anything). Shipped: paste-a-menu (#83, D18), image parts on the chat
   clients (#170), `VisionMenuClassifier` behind a sibling `ScannedMenuClassifier`
   (#89) and the Scan tab's photo, image and PDF pickers (#82). Open: #84 (flow
   tests), #88 (a person-run Gemini vision smoke test), #181 (website menus) and
   #182 (QR codes).

Dietary customisation (carnivore, dairy-free, seed-oil-free toggles; Tier C in
`feature_prioratization`) is **shipped** and lives under
`Phase 2: Settings & Preferences` (#56, #143); there is no Phase 4 milestone for
it, and a pesco-keto mode was never built.

**There is no Phase 4 "Meal Logging" milestone.** `architecture.md` D8 rules meal
logging and macro tracking out of scope for KetoClub entirely — that design in
`m15_meal_entry_research.md` belongs to a different application.

**Success Criteria:**
- ✅ A pasted menu is classified like a fetched one
- ✅ Photographed or PDF pages are read and classified by a vision model in one
  request, with a way to check the transcription against the pages ("View
  pages") — no on-device OCR, so the old "95%+ of readable text" criterion is
  gone; its replacement is a transcription check on real menus, which is #88
- ✅ Users can switch between dietary rulesets (shipped under Phase 2)
- ⏳ A real Gemini request carrying images has been observed working (#88); flow
  tests cover each scan path (#84)
- Menus from a website or a QR code — not built (#181, #182)

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

- **Phase 1**, **Phase 2**, **Phase 3**, **Phase 4** — Indicates which phase the issue belongs to
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
