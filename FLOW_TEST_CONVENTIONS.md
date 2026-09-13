# Flow Test Conventions

Guidelines for writing integration and flow tests in KetoClub's Flutter application.

## Overview

Flow tests (integration tests) verify that multiple components work together correctly. Unlike unit tests that test in isolation, flow tests exercise real code paths and user interactions.

### When to Use Flow Tests

- **User journeys**: Search venue → View menu → See classifications
- **Multi-screen navigation**: HomeScreen → VenueSearchScreen → MenuDetailScreen
- **API integration**: Fetch menu from API → Parse → Display in UI
- **Error recovery**: Handle network error → Show error message → Retry
- **Platform-specific behavior**: Geolocation permissions on iOS vs Android

### When to Use Unit Tests Instead

- Individual function logic
- Data transformation and parsing
- Error handling in isolation
- Model serialization/deserialization

## Test File Organization

Flow tests live in a separate `integration_test/` directory:

```
integration_test/
  ├── flows/
  │   ├── venue_search_flow_test.dart
  │   ├── menu_display_flow_test.dart
  │   └── api_integration_flow_test.dart
  └── fixtures/
      ├── mock_responses.dart
      └── test_data.dart

test/
  ├── services/
  │   └── *_test.dart (unit tests)
  └── models/
      └── *_test.dart (unit tests)
```

## Flow Test Structure

### Basic Flow Test Template

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Venue Search Flow', () {
    testWidgets('User can search for restaurants and view menu', (WidgetTester tester) async {
      // Setup
      app.main();
      await tester.pumpAndSettle();

      // Act & Assert
      // (See detailed example below)
    });
  });
}
```

## Flow Test Examples

### Example 1: Complete Venue Search and Menu View

```dart
testWidgets('User completes full flow: location → search → menu', 
  (WidgetTester tester) async {
  // Setup: Launch app
  app.main();
  await tester.pumpAndSettle();

  // Assert initial state
  expect(find.byType(HomeScreen), findsOneWidget);

  // Step 1: User enables geolocation (mock)
  // (In real testing, use mock geolocation)
  await tester.tap(find.byTooltip('Enable Location'));
  await tester.pumpAndSettle();

  // Step 2: Location is retrieved and venue list appears
  expect(find.byType(VenueListScreen), findsOneWidget);
  expect(find.byType(VenueCard), findsWidgets);

  // Step 3: User taps on a venue
  await tester.tap(find.byType(VenueCard).first);
  await tester.pumpAndSettle();

  // Step 4: Menu loads and displays classified dishes
  expect(find.byType(MenuDetailScreen), findsOneWidget);
  expect(find.byType(DishCard), findsWidgets);

  // Step 5: User sees status badges (🟢, 🟡, 🔴)
  expect(find.byType(StatusBadge), findsWidgets);

  // Step 6: User taps on a YELLOW dish to see modifications
  final yellowDish = find.byWidgetPredicate(
    (widget) => widget is DishCard && widget.status == 'YELLOW',
  ).first;
  await tester.tap(yellowDish);
  await tester.pumpAndSettle();

  // Step 7: Waiter script is displayed
  expect(find.byType(WaiterScriptWidget), findsOneWidget);
  expect(find.text('Waiter Script'), findsOneWidget);
});
```

### Example 2: API Failure and Recovery

```dart
testWidgets('App handles API failure gracefully', 
  (WidgetTester tester) async {
  app.main();
  await tester.pumpAndSettle();

  // Step 1: User searches for venue
  await tester.tap(find.byType(SearchField));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(SearchField), 'Test Restaurant');
  await tester.tap(find.byText('Search'));
  await tester.pumpAndSettle();

  // Step 2: Network error occurs (simulate timeout)
  // (Use mock HTTP client that returns error)
  
  // Step 3: Error message appears
  expect(find.byType(ErrorMessage), findsOneWidget);
  expect(find.text('Failed to load menu. Please try again.'), findsOneWidget);

  // Step 4: User taps retry button
  await tester.tap(find.byType(RetryButton));
  await tester.pumpAndSettle();

  // Step 5: Menu loads successfully (mock returns success)
  expect(find.byType(MenuDetailScreen), findsOneWidget);
});
```

### Example 3: Platform-Specific Behavior

```dart
group('Platform-Specific Tests', () {
  testWidgets('iOS uses Cupertino-style navigation', 
    (WidgetTester tester) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      app.main();
      await tester.pumpAndSettle();

      // Expect Cupertino navigation
      expect(find.byType(CupertinoTabScaffold), findsOneWidget);
    }
  });

  testWidgets('Android uses Material navigation', 
    (WidgetTester tester) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      app.main();
      await tester.pumpAndSettle();

      // Expect Material navigation
      expect(find.byType(Scaffold), findsOneWidget);
    }
  });
});
```

## Common Flow Test Patterns

### Pattern: Search and Filter

```dart
testWidgets('User can search and filter results', 
  (WidgetTester tester) async {
  app.main();
  await tester.pumpAndSettle();

  // Open search
  await tester.tap(find.byIcon(Icons.search));
  await tester.pumpAndSettle();

  // Type search query
  await tester.enterText(find.byType(TextField), 'steakhouse');
  await tester.pumpAndSettle();

  // Filter by GREEN only
  await tester.tap(find.byTooltip('Filter'));
  await tester.pumpAndSettle();
  await tester.tap(find.byText('Only Green'));
  await tester.pumpAndSettle();

  // Verify filtered results
  expect(find.byType(VenueCard), findsWidgets);
  // (All cards should show venues with GREEN dishes)
});
```

### Pattern: Scroll and Interact

```dart
testWidgets('User can scroll menu and tap items', 
  (WidgetTester tester) async {
  app.main();
  await tester.pumpAndSettle();
  
  // Navigate to menu
  // ... (setup steps omitted)

  // Scroll down to find more dishes
  await tester.scroll(find.byType(MenuDetailScreen), const Offset(0, -500));
  await tester.pumpAndSettle();

  // Verify more dishes are visible
  expect(find.byType(DishCard), findsWidgets);

  // Tap a dish card
  await tester.tap(find.byType(DishCard).at(5));
  await tester.pumpAndSettle();

  // Verify detail view opened
  expect(find.byType(DishDetailView), findsOneWidget);
});
```

### Pattern: Navigation Stack

```dart
testWidgets('User can navigate back through screens', 
  (WidgetTester tester) async {
  app.main();
  await tester.pumpAndSettle();

  // Navigate through screens
  await tester.tap(find.byType(VenueCard).first);
  await tester.pumpAndSettle();
  await tester.tap(find.byType(DishCard).first);
  await tester.pumpAndSettle();

  // Now on detail screen
  expect(find.byType(DishDetailView), findsOneWidget);

  // Go back
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();
  expect(find.byType(MenuDetailScreen), findsOneWidget);

  // Go back again
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();
  expect(find.byType(VenueListScreen), findsOneWidget);
});
```

## Helpers & Fixtures

### Mock Responses

```dart
// integration_test/fixtures/mock_responses.dart

class MockResponses {
  static const String woltMenuJson = '''
  {
    "currency": "ILS",
    "categories": [
      {"id": "cat_1", "name": "Steaks", "item_ids": ["dish_1", "dish_2"]}
    ],
    "items": [
      {
        "id": "dish_1",
        "name": "Ribeye 300g",
        "description": "Served with butter and vegetables",
        "price": 14200
      },
      {
        "id": "dish_2",
        "name": "Sirloin with Fries",
        "description": "Served with French fries and salad",
        "price": 12000
      }
    ],
    "options": []
  }
  ''';

  static const String errorResponse = '''
  {"error": "Not Found"}
  ''';
}
```

### Test Data Factory

```dart
// integration_test/fixtures/test_data.dart

class TestDataFactory {
  static Venue createTestVenue({
    String id = 'test_1',
    String name = 'Test Restaurant',
    double lat = 32.0853,
    double lng = 34.7818,
  }) {
    return Venue(
      id: id,
      name: name,
      address: '123 Test Street',
      latitude: lat,
      longitude: lng,
      ketoRatingScore: 4.5,
    );
  }

  static Menu createTestMenu({
    String venueId = 'test_1',
    int dishCount = 5,
  }) {
    final dishes = List.generate(
      dishCount,
      (i) => Dish(
        id: 'dish_$i',
        name: 'Dish $i',
        description: 'Test description',
        price: 25.0 + i,
        status: i % 2 == 0 ? 'GREEN' : 'YELLOW',
      ),
    );

    return Menu(
      id: 'menu_1',
      venueId: venueId,
      dishes: dishes,
    );
  }
}
```

### Common Test Helpers

```dart
// integration_test/test_helpers.dart

extension WidgetTesterHelper on WidgetTester {
  /// Finds and taps a button by its text label
  Future<void> tapButtonByText(String text) async {
    await tap(find.byWidgetPredicate(
      (widget) => widget is ElevatedButton && 
                  widget.child is Text &&
                  (widget.child as Text).data == text,
    ));
    await pumpAndSettle();
  }

  /// Enters text into the first TextField
  Future<void> enterTextInSearchField(String text) async {
    await tap(find.byType(TextField).first);
    await pumpAndSettle();
    await enterText(find.byType(TextField).first, text);
    await pumpAndSettle();
  }

  /// Waits for a widget to appear (with timeout)
  Future<void> waitForWidget(
    Finder finder, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    await pumpUntilFound(finder, timeout);
  }

  /// Scrolls to find a specific widget
  Future<void> scrollUntilVisible(
    Finder finder,
    double delta,
  ) async {
    await scrollUntilVisible(finder, delta);
  }
}
```

## Running Flow Tests

### Run all flow tests
```bash
flutter test integration_test/
```

### Run specific flow test
```bash
flutter test integration_test/flows/venue_search_flow_test.dart
```

### Run on iOS
```bash
flutter test integration_test/ -d ios
```

### Run on Android
```bash
flutter test integration_test/ -d android
```

### Run on Web
```bash
flutter test integration_test/ -d chrome
```

## Best Practices

### ✅ Do

- Test **complete user journeys** (not individual button taps)
- Use **meaningful wait times** (`pumpAndSettle()`)
- Test **across platforms** (web, iOS, Android)
- Use **fixtures and factories** to reduce duplication
- Test **error paths** explicitly
- Keep tests **focused** (one user story per test)
- Mock **external APIs** (network calls should be predictable)
- Test **accessibility** (can users navigate without vision?)

### ❌ Don't

- Test **implementation details** (test behavior, not code structure)
- Use **hard-coded delays** (use `pumpAndSettle()` instead)
- Write **flaky tests** (tests that pass/fail randomly)
- Ignore **edge cases** (test what happens when things fail)
- Make tests **interdependent** (each test should be independent)
- Test **UI pixel-perfect** (test functionality, not exact positioning)
- Skip **error scenarios** (errors happen in the real world)

## Coverage Goals for Flow Tests

- **Critical user journeys**: 100% coverage (every user path)
- **Error recovery paths**: 80%+ coverage
- **Platform-specific features**: 100% coverage per platform
- **Overall app flows**: 50%+ coverage

## CI/CD Integration

Flow tests should run on real devices/emulators in CI:

```yaml
# .github/workflows/integration_test.yml
name: Integration Tests
on: [push, pull_request]

jobs:
  integration_test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      
      # Run on iOS simulator
      - run: flutter test integration_test/ -d ios
      
      # Run on Android emulator (requires AVD setup)
      - name: Run Android tests
        run: |
          flutter test integration_test/ -d android
```

## Debugging Flow Tests

### Enable verbose output
```bash
flutter test integration_test/ -v
```

### Create screenshots on failure
```bash
flutter test integration_test/ --screenshots ./screenshots/
```

### Use `pumpAndSettle()` strategically
```dart
// Wait for animations and async operations
await tester.pumpAndSettle();

// Wait for specific duration
await tester.pump(Duration(milliseconds: 500));
```

### Inspect widget tree
```dart
// Find all widgets of a type
debugPrintBeginFrame = true;
await tester.pumpAndSettle();

// Print widget tree
print(find.byType(MenuDetailScreen).evaluate());
```

## Example Complete Test File

```dart
// integration_test/flows/venue_search_flow_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/main.dart' as app;
import '../fixtures/test_data.dart';
import '../test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Venue Search and Menu Display Flow', () {
    testWidgets(
      'User searches for venue and views classified menu',
      (WidgetTester tester) async {
        app.main();
        await tester.pumpAndSettle();

        // Verify home screen
        expect(find.byType(HomeScreen), findsOneWidget);

        // Search for restaurant
        await tester.enterTextInSearchField('Test Restaurant');
        await tester.tapButtonByText('Search');

        // Verify venue list
        expect(find.byType(VenueListScreen), findsOneWidget);
        expect(find.byType(VenueCard), findsWidgets);

        // Tap first venue
        await tester.tap(find.byType(VenueCard).first);
        await tester.pumpAndSettle();

        // Verify menu displays
        expect(find.byType(MenuDetailScreen), findsOneWidget);
        expect(find.byType(DishCard), findsWidgets);
        expect(find.byType(StatusBadge), findsWidgets);
      },
    );
  });
}
```
