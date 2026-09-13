# Pull Request Conventions

Guidelines for creating, reviewing, and merging pull requests in the KetoClub repository.

## PR Naming Convention

PR titles should follow this format:

```
[Type] Brief description of changes
```

### Types

- `[feature]` — New functionality
- `[fix]` — Bug fix
- `[refactor]` — Code reorganization without behavior change
- `[docs]` — Documentation updates
- `[test]` — Test additions or improvements
- `[chore]` — Dependency updates, tooling, CI/CD

### Examples

- `[feature] Implement menu classifier with Green/Yellow/Red status`
- `[fix] Handle null venue names gracefully`
- `[refactor] Extract API client into separate service class`
- `[docs] Add geolocation setup guide for iOS`
- `[test] Add unit tests for CarModifier detection`

## PR Template

When creating a PR, use this structure:

### 1. **Linked Issue(s)**
   ```
   Closes #123
   Related to #456
   ```

### 2. **Summary**
   - What does this PR do?
   - Why is it needed?
   - What problem does it solve?
   - Keep to 2-3 sentences

### 3. **Changes Made**
   - Bulleted list of specific changes
   - File names and key functions modified
   - Example:
     ```
     - Created `lib/services/restaurant_api_client.dart` with WoltApiClient
     - Added Venue and Menu models to `lib/models/`
     - Updated pubspec.yaml with http dependency
     - Added unit tests in `test/services/`
     ```

### 4. **Testing**
   - What was tested and how?
   - Platforms tested: Web / iOS / Android
   - Manual test steps (if UI changes)
   - Example:
     ```
     ✅ Unit tests pass: `flutter test`
     ✅ Manual test on iOS simulator: fetches Wolt menu successfully
     ✅ Manual test on web: responsive layout verified
     ✅ Error handling: timeout and 404 responses handled gracefully
     ```

### 5. **Checklist**
   ```markdown
   - [ ] Code follows project conventions
   - [ ] Tests added/updated and passing
   - [ ] Documentation updated (comments, CLAUDE.md, etc.)
   - [ ] No breaking changes (or documented if intentional)
   - [ ] Commit messages are clear and descriptive
   - [ ] Tested on relevant platforms (web/iOS/Android)
   ```

## Commit Message Guidelines

Each commit should have a clear, descriptive message:

### Format
```
[Type] Brief description

Detailed explanation of the change (if needed).
- Bullet point 1
- Bullet point 2

Closes #123
```

### Examples

**Simple commit (no body needed):**
```
[feature] Add status badge widget for dish classification
```

**Complex commit (with explanation):**
```
[fix] Handle network timeout in Wolt API client

Previously, network timeouts would crash the app with an unhandled exception.
Now we catch TimeoutException and display a user-friendly error message.

- Wrapped HTTP request in try-catch for SocketException and TimeoutException
- Added error_message field to ApiResponse model
- Updated menu_detail_screen.dart to display error state
- Added unit tests for timeout scenarios

Closes #42
```

### Types (match PR type)
- `[feature]` — New functionality
- `[fix]` — Bug fix
- `[refactor]` — Code reorganization
- `[docs]` — Documentation
- `[test]` — Tests
- `[chore]` — Maintenance

## Code Review Standards

### For Authors

- **Keep PRs focused**: One feature or fix per PR (aim for <400 lines)
- **Self-review first**: Read through your own changes before requesting review
- **Add context**: Link to related issues and explain non-obvious decisions
- **Keep it updated**: Respond to feedback promptly and push updates regularly

### For Reviewers

- **Be respectful**: Critique code, not the person
- **Ask questions**: If something is unclear, ask rather than assume
- **Suggest improvements**: "Consider using X for clarity" vs. "This is wrong"
- **Approve clearly**: Use GitHub's approve button when satisfied
- **Test locally**: Run the code on relevant platforms if it affects behavior

### Approval Requirements

Before merging, a PR must have:
- ✅ At least 1 approval from a maintainer
- ✅ All tests passing (CI checks green)
- ✅ No merge conflicts
- ✅ Clear commit history (no "WIP" or "fix typo" commits)

## Size Guidelines

Aim for PR sizes that can be reviewed in 20-30 minutes:

- **Tiny** (< 50 lines): Documentation, single function, simple fix
- **Small** (50-200 lines): Single feature or refactor
- **Medium** (200-400 lines): Multiple related changes or significant refactor
- **Large** (400+ lines): Consider splitting into multiple PRs

If a PR exceeds 400 lines, split it or add detailed explanation.

## Merge Strategy

- Use **Squash and merge** for small features/fixes to keep history clean
- Use **Create a merge commit** for large features (to preserve sub-commit history)
- Use **Rebase and merge** rarely (only if PR has clean, independent commits)

## Handling Feedback

1. **Acknowledge**: Thank the reviewer for their time
2. **Discuss**: If you disagree, explain your reasoning respectfully
3. **Update**: Make requested changes and push new commits
4. **Re-request review**: Once updates are made
5. **Resolve**: Mark conversations as resolved when complete

## Post-Merge

- Delete the branch (GitHub offers this button after merge)
- Monitor CI/CD to ensure deployment succeeds
- If urgent issues arise, create a new issue and PR to fix

## Example PR

```markdown
# Add Wolt API Client

Closes #15

## Summary
Implements the first restaurant API client to fetch menus from Wolt. 
This enables Phase 1 menu ingestion without a backend server.

## Changes Made
- Created `lib/services/restaurant_api_client.dart` with `WoltApiClient` class
- Added `Venue`, `Menu`, and `Dish` models to `lib/models/`
- Updated `pubspec.yaml` with `http` dependency
- Added comprehensive unit tests in `test/services/restaurant_api_client_test.dart`

## Testing
- ✅ All unit tests passing: `flutter test`
- ✅ Manual test on web: successfully fetches and parses Wolt menu
- ✅ Manual test on iOS simulator: network request works, data displayed
- ✅ Error handling: timeout and 404 responses handled gracefully

## Checklist
- [x] Code follows project conventions
- [x] Tests added and passing
- [x] Documentation added (inline comments)
- [x] No breaking changes
- [x] Commit messages are clear
- [x] Tested on web and iOS
```
