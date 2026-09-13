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
- `Phase 1: Waiter Script Generation`
- `Phase 2: Geolocation & Venue Search`
- `Phase 2: Menu Display UI`
- `Phase 3: User Ratings & Reviews`

## Phase Breakdown

### Phase 1: Core Parsing & Classification

**Goal**: Build the restaurant menu ingestion and keto classification engine (no backend).

**Milestones:**
1. `Phase 1: API Client Infrastructure` — HTTP clients for Wolt, 10bis, Tabit, Ontopo
2. `Phase 1: Menu Classifier Engine` — Heuristic-based dish classification (🟢/🟡/🔴)
3. `Phase 1: Waiter Script Generation` — Auto-generated modification instructions
4. `Phase 1: Core UI Screens` — Home, venue search, menu display

**Success Criteria:**
- ✅ Fetch menus from at least Wolt and 10bis APIs
- ✅ Classify dishes with >90% accuracy on common cases
- ✅ Generate accurate waiter scripts for Yellow dishes
- ✅ App is usable on web, iOS, and Android

### Phase 2: Mobile Interface & Discovery

**Goal**: Complete the user-facing mobile app with geolocation and filtering.

**Milestones:**
1. `Phase 2: Geolocation & Venue Search` — Device location + venue discovery
2. `Phase 2: Menu Display & Navigation` — Improved UI, search filtering, bookmarks
3. `Phase 2: Settings & Preferences` — User settings, dietary rule customization
4. `Phase 2: Polish & Performance` — Responsive design, loading states, error handling

**Success Criteria:**
- ✅ Users can search nearby restaurants by location
- ✅ App displays filtered results (Green/Yellow/Red)
- ✅ Smooth navigation between screens
- ✅ Works offline for cached menus
- ✅ <3s load time on 4G network

### Phase 3: Community Database & Reviews

**Goal**: Add persistent user feedback and venue ratings.

**Milestones:**
1. `Phase 3: Backend Infrastructure` — Basic server + database (if needed)
2. `Phase 3: User Ratings & Reviews` — Post-visit feedback mechanism
3. `Phase 3: Venue Submission` — Crowdsourced venue directory
4. `Phase 3: Verified Badges` — Keto-friendly venue verification

**Success Criteria:**
- ✅ Users can rate venues after dining
- ✅ Community ratings influence venue ranking
- ✅ Verified keto-friendly badges visible to users
- ✅ Support for user submissions of new venues

### Phase 4: Advanced Features

**Goal**: Add OCR vision processing and advanced dietary customization.

**Milestones:**
1. `Phase 4: OCR Menu Scanning` — Snap photo of physical menu, extract text
2. `Phase 4: Dietary Customization` — Carnivore, pesco-keto, seed-oil avoidance modes
3. `Phase 4: LLM Integration` — AI-powered edge case classification
4. `Phase 4: Meal Logging` — Track consumed meals, macro tracking

**Success Criteria:**
- ✅ OCR extracts 95%+ of readable text from menu photos
- ✅ Users can switch between dietary rulesets
- ✅ LLM fallback handles ambiguous dishes
- ✅ Macro tracking integrated with meal log

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
