# Issue Conventions

Guidelines for creating and managing issues in the KetoClub repository.

## Issue Types

Use one of these labels to categorize each issue:

- **bug**: Something is broken or not working as expected
- **feature**: New functionality or enhancement to existing features
- **research**: Investigation, analysis, or exploration of a topic
- **documentation**: Updates to docs, README, or developer guides
- **chore**: Internal maintenance, tooling, or dependency updates
- **performance**: Optimization or performance improvements

## Naming Convention

Issues should have clear, descriptive titles in this format:

```
[Type] Brief description of the issue
```

### Examples

- `[feature] Add Wolt API client for menu fetching`
- `[bug] Geolocation permission denied on iOS crashes app`
- `[research] Evaluate OCR libraries for menu scanning`
- `[documentation] Update CLAUDE.md with API endpoints`
- `[chore] Upgrade Flutter SDK to latest version`

## Issue Template

When creating an issue, include:

### 1. **Description**
   - What is the issue or feature request?
   - Why is it important?

### 2. **Context**
   - Where does this occur? (which screen, service, or component)
   - Are there any related issues or PRs?

### 3. **Acceptance Criteria** (for features)
   - What needs to be true for this issue to be considered complete?
   - List specific, measurable outcomes

### 4. **Steps to Reproduce** (for bugs)
   - What triggers the bug?
   - Platform(s) affected: Web / iOS / Android / All
   - Include error messages, logs, or screenshots if applicable

### 5. **Related Issues**
   - Link to any dependent or related issues
   - Example: `Blocks #123`, `Related to #456`

## Tests Required

**All feature issues MUST include unit and flow tests.** Specify in the acceptance criteria:

- **Unit Tests**: What functionality needs isolated testing?
  - Example: "Test WoltApiClient.fetchMenu() with valid/invalid JSON"
  - See `UNIT_TEST_CONVENTIONS.md` for guidelines
  
- **Flow Tests**: What user journeys validate this feature?
  - Example: "User searches venue → views menu → sees classifications"
  - See `FLOW_TEST_CONVENTIONS.md` for guidelines

- **Coverage Target**: Specify expected code coverage
  - Services: 80%+
  - Models: 90%+
  - Utilities: 75%+

### Example

```
## Acceptance Criteria
- [x] WoltApiClient fetches menu from API
- [x] Response is parsed into Dart models
- [x] Network errors are handled gracefully
- [ ] Unit tests pass with 80%+ coverage
- [ ] Flow test: User views Wolt menu successfully
- [ ] Documentation updated in CLAUDE.md
```

## Technology Research

**If an issue requires new libraries, APIs, or integrations, include research:**

- **Library Evaluation**: Compare options (e.g., geolocator vs. location package)
- **API Documentation**: Research external service requirements
- **Integration Challenges**: Note any known compatibility issues
- **Decision Record**: Document which technology was chosen and why

### Example

```
## Technology Research
- [ ] Research geolocator package for iOS/Android/Web support
- [ ] Verify Wolt API rate limits and CORS requirements
- [ ] Confirm http package version compatibility with Flutter 3.x
- [ ] Check if location permissions differ between platforms

## Decision
Use `geolocator` because:
- Supports web, iOS, Android from single codebase
- Well-maintained with good documentation
- Permission handling built-in for all platforms
```

## Phase Assignment

Assign issues to one of the six project phases (re-planned 2026-09-24,
`ROADMAP.md`):

- **Phase 1**: Core parsing, heuristic engine, waiter script generation (built)
- **Phase 2**: Mobile interface, geolocation, search filtering (built)
- **Phase 3**: The personal backend, verified end to end (backend foundations
  and hosted classification are built; the person-run checks, AI on by
  default and the LAN URL override remain)
- **Phase 4**: Menu scanning via Gemini's vision, configurable dietary rules
- **Phase 5**: The hosted service, then community features re-planned on it
- **Phase 6**: More platforms (Tabit, Ontopo)

See `ROADMAP.md` and `CLAUDE.md` for phase details.

## Priority Labels

Add one priority label:

- **priority: critical** — Blocks other work or major functionality
- **priority: high** — Important but not blocking
- **priority: medium** — Nice to have, can be deferred
- **priority: low** — Polish or future consideration

## Example Issue

```
Title: [feature] Implement Wolt API client

Description:
Fetch restaurant menus directly from Wolt's API and parse the JSON response into Dart models.

Context:
This is the first API integration and should be completed in Phase 1. Wolt has no auth 
requirements, making it the ideal starting point.

Acceptance Criteria:
- WoltApiClient class fetches menu data from https://restaurant-api.wolt.com/v4/venues/slug/{venue_slug}/menu/data
- JSON response is parsed into Menu, Dish, and DishModifier models
- Handles network errors gracefully (timeout, 404, 500)
- Unit tests cover successful fetch and error cases (80%+ coverage)
- Flow test: User can load Wolt menu and see dish classifications
- Documented in code with example usage

Technology Research:
- [x] Reviewed Wolt API documentation and endpoint structure
- [x] Confirmed http package compatibility with Flutter 3.x
- [x] Verified no CORS issues for web platform
- Decision: Use http package (lightweight, no additional dependencies)

Tests Required:
- Unit: WoltApiClient.fetchMenu() with valid JSON, malformed JSON, timeout, 404
- Unit: Menu.fromJson() serialization/deserialization
- Flow: User navigates to venue with Wolt menu, verifies dishes display

Related Issues:
Blocks #2 (Menu classifier), Related to #1 (Restaurant API research)

Labels: feature, Phase 1, priority: high
```

## Issue Lifecycle

1. **Open** → Issue is identified and described
2. **In Progress** → Assigned to someone and they start work
3. **In Review** → PR is open and waiting for review
4. **Done** → PR is merged and issue is resolved

Use GitHub project boards to track status across the lifecycle.
