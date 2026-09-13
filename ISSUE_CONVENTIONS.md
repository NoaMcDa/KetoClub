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

## Phase Assignment

Assign issues to one of the four project phases:

- **Phase 1**: Core parsing, heuristic engine, waiter script generation
- **Phase 2**: Mobile interface, geolocation, search filtering
- **Phase 3**: Community database, user reviews, restaurant submissions
- **Phase 4**: OCR/vision, configurable dietary rules

See `feature_prioratization` and `CLAUDE.md` for phase details.

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
This is the first API integration and should be completed in Phase 1. Wolt has no auth requirements, making it the ideal starting point.

Acceptance Criteria:
- WoltApiClient class fetches menu data from https://restaurant-api.wolt.com/v4/venues/slug/{venue_slug}/menu/data
- JSON response is parsed into Menu, Dish, and DishModifier models
- Handles network errors gracefully (timeout, 404, 500)
- Unit tests cover successful fetch and error cases
- Documented in code with example usage

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
