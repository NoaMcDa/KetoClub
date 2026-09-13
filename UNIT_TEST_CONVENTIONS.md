# Unit Test Conventions

Guidelines for writing unit tests in KetoClub's Dart/Flutter codebase.

## Overview

Unit tests verify individual functions, classes, and methods in isolation. They should be:
- **Fast**: Run in milliseconds
- **Independent**: No shared state between tests
- **Deterministic**: Same result every time
- **Focused**: Test one thing per test

## Test File Organization

### Naming Convention

Test files mirror source files with `_test.dart` suffix:

```
lib/
  ├── services/
  │   ├── restaurant_api_client.dart
  │   └── menu_classifier.dart
  └── models/
      └── dish.dart

test/
  ├── services/
  │   ├── restaurant_api_client_test.dart
  │   └── menu_classifier_test.dart
  └── models/
      └── dish_test.dart
```

### File Structure

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/restaurant_api_client.dart';
import 'package:mockito/mockito.dart';

void main() {
  group('WoltApiClient', () {
    late WoltApiClient client;

    setUp(() {
      client = WoltApiClient();
    });

    tearDown(() {
      // Clean up if needed
    });

    test('description of what is being tested', () {
      // Arrange
      final slug = 'test-restaurant';

      // Act
      final result = client.parseVenueSlug(slug);

      // Assert
      expect(result, equals('test-restaurant'));
    });
  });
}
```

## Test Naming Convention

Use descriptive test names that read like sentences:

### Format
```
test('{method/class} {condition} {expected result}', () {});
```

### Examples

**Good:**
```dart
test('fetchWoltMenu returns Menu when response is valid JSON', () {});
test('parseMenu throws FormatException when JSON is malformed', () {});
test('classifyDish returns GREEN status for keto-safe dishes', () {});
test('generateWaiterScript includes all matching modifications', () {});
```

**Bad:**
```dart
test('test fetch', () {});
test('works correctly', () {});
test('null check', () {});
```

## Test Structure: Arrange-Act-Assert

Every test should follow this pattern:

```dart
test('classifyDish returns YELLOW for steak with fries', () {
  // Arrange: Set up test data and mocks
  final dish = Dish(
    name: 'Grilled Steak',
    description: 'Served with French fries and garlic butter',
    price: 45.00,
  );

  // Act: Execute the function being tested
  final classification = MenuClassifier.classifyDish(
    name: dish.name,
    description: dish.description,
  );

  // Assert: Verify the result
  expect(classification.status, equals('YELLOW'));
  expect(classification.waiterInstructions, contains('Replace French fries'));
});
```

## Testing Different Components

### Services & API Clients

**What to test:**
- Successful API calls and data parsing
- Error handling (network errors, invalid JSON, timeouts)
- Request parameters and headers
- Response transformation

**Example:**

```dart
void main() {
  group('WoltApiClient', () {
    late WoltApiClient client;
    late MockHttpClient mockHttp;

    setUp(() {
      mockHttp = MockHttpClient();
      client = WoltApiClient(httpClient: mockHttp);
    });

    test('fetchMenu parses Wolt JSON response correctly', () async {
      // Arrange
      const venueSlug = 'vitrina-lilinblum';
      final mockResponse = '''
      {
        "currency": "ILS",
        "categories": [{"id": "cat_1", "name": "Steaks", "item_ids": ["dish_1"]}],
        "items": [{"id": "dish_1", "name": "Ribeye", "description": "300g", "price": 14200}],
        "options": []
      }
      ''';

      when(mockHttp.get(any))
          .thenAnswer((_) async => http.Response(mockResponse, 200));

      // Act
      final menu = await client.fetchMenu(venueSlug);

      // Assert
      expect(menu.items, hasLength(1));
      expect(menu.items[0].name, equals('Ribeye'));
    });

    test('fetchMenu throws SocketException on network error', () async {
      // Arrange
      when(mockHttp.get(any))
          .thenThrow(SocketException('No internet'));

      // Act & Assert
      expect(
        () => client.fetchMenu('any-slug'),
        throwsA(isA<SocketException>()),
      );
    });
  });
}
```

### Classification Logic

**What to test:**
- Regex pattern matching for carb triggers
- Status assignment (GREEN/YELLOW/RED)
- Waiter script generation
- Edge cases (empty strings, special characters, case sensitivity)

**Example:**

```dart
void main() {
  group('MenuClassifier', () {
    test('classifyDish returns RED for pasta-based dishes', () {
      final classification = MenuClassifier.classifyDish(
        name: 'Penne Carbonara',
        description: 'Classic Italian pasta with eggs and bacon',
      );

      expect(classification.status, equals('RED'));
      expect(classification.badge, equals('🔴'));
    });

    test('classifyDish identifies all carb modifiers in description', () {
      final classification = MenuClassifier.classifyDish(
        name: 'Grilled Salmon',
        description: 'Served with mashed potatoes, rice, and carrots',
      );

      expect(classification.status, equals('YELLOW'));
      expect(classification.waiterInstructions, hasLength(greaterThan(1)));
      expect(
        classification.waiterInstructions.join(' '),
        contains('mashed potatoes'),
      );
      expect(
        classification.waiterInstructions.join(' '),
        contains('rice'),
      );
    });

    test('classifyDish is case-insensitive', () {
      final lowercase = MenuClassifier.classifyDish(
        name: 'steak',
        description: 'with fries',
      );

      final uppercase = MenuClassifier.classifyDish(
        name: 'STEAK',
        description: 'WITH FRIES',
      );

      expect(lowercase.status, equals(uppercase.status));
    });

    test('classifyDish handles empty description gracefully', () {
      final classification = MenuClassifier.classifyDish(
        name: 'Grilled Chicken',
        description: '',
      );

      expect(classification.status, equals('GREEN'));
    });
  });
}
```

### Models & Data Classes

**What to test:**
- Serialization/deserialization (JSON parsing)
- Validation logic
- Equality and hashing
- toString() representation

**Example:**

```dart
void main() {
  group('Dish Model', () {
    test('fromJson creates Dish from valid JSON', () {
      final json = {
        'id': 'dish_1',
        'name': 'Ribeye Steak',
        'description': 'Prime cut',
        'price': 45.50,
        'status': 'GREEN',
      };

      final dish = Dish.fromJson(json);

      expect(dish.id, equals('dish_1'));
      expect(dish.name, equals('Ribeye Steak'));
      expect(dish.price, equals(45.50));
    });

    test('toJson serializes Dish correctly', () {
      final dish = Dish(
        id: 'dish_1',
        name: 'Ribeye Steak',
        price: 45.50,
        status: 'GREEN',
      );

      final json = dish.toJson();

      expect(json['id'], equals('dish_1'));
      expect(json['status'], equals('GREEN'));
    });

    test('two Dishes with same data are equal', () {
      final dish1 = Dish(id: '1', name: 'Steak', price: 45.0);
      final dish2 = Dish(id: '1', name: 'Steak', price: 45.0);

      expect(dish1, equals(dish2));
    });
  });
}
```

## Mocking & Dependencies

### Using Mockito

For testing code that depends on external services:

```dart
import 'package:mockito/mockito.dart';

// Generate mocks with: flutter pub run build_runner build
class MockHttpClient extends Mock implements http.Client {}
class MockLocationService extends Mock implements LocationService {}

void main() {
  group('VenueSearchService', () {
    late VenueSearchService service;
    late MockLocationService mockLocation;

    setUp(() {
      mockLocation = MockLocationService();
      service = VenueSearchService(locationService: mockLocation);
    });

    test('searchNearby returns venues when location is available', () async {
      // Arrange
      when(mockLocation.getCurrentLocation())
          .thenAnswer((_) async => Location(lat: 32.0853, lng: 34.7818));

      // Act
      final venues = await service.searchNearby();

      // Assert
      expect(venues, isNotEmpty);
      verify(mockLocation.getCurrentLocation()).called(1);
    });
  });
}
```

## Test Organization with Groups

Use `group()` to organize related tests:

```dart
void main() {
  group('MenuClassifier', () {
    group('classifyDish - GREEN status', () {
      test('classifies simple salad as GREEN', () {});
      test('classifies steak without sides as GREEN', () {});
    });

    group('classifyDish - YELLOW status', () {
      test('detects starchy sides and returns YELLOW', () {});
      test('detects sugary sauces and returns YELLOW', () {});
    });

    group('classifyDish - RED status', () {
      test('classifies pasta dishes as RED', () {});
      test('classifies pizza as RED', () {});
    });

    group('generateWaiterScript', () {
      test('generates script for single modification', () {});
      test('generates script for multiple modifications', () {});
    });
  });
}
```

## Running Tests

### Run all tests
```bash
flutter test
```

### Run specific test file
```bash
flutter test test/services/menu_classifier_test.dart
```

### Run with coverage
```bash
flutter test --coverage
# View coverage report
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

### Run tests in watch mode (during development)
```bash
flutter test --watch
```

## Coverage Targets

Aim for these coverage goals by component:

- **Services (API clients, classifiers)**: 80%+ coverage
- **Models (data classes)**: 90%+ coverage
- **Utilities (helpers, constants)**: 75%+ coverage
- **UI/Screens**: 30-50% coverage (use flow tests instead)
- **Overall target**: 70%+ code coverage

## Best Practices

### ✅ Do

- Write tests **before or with** code (TDD is ideal)
- Test **one thing per test**
- Use **clear, descriptive names**
- Keep tests **fast** (mock external services)
- Test **edge cases** (null, empty, very large values)
- Use **setup/teardown** for common initialization
- Test **error cases** explicitly
- Keep tests **independent** (no shared state)

### ❌ Don't

- Test **implementation details** (test behavior, not code paths)
- Use **magic numbers** (use named variables)
- Write **long, complex tests** (break into smaller tests)
- Make tests **flaky** (avoid real network calls, timers)
- Ignore **error cases** (test what happens when things fail)
- Mock **everything** (mock only external dependencies)
- Repeat **test data** (use factories or fixtures)

## Example Test Suite

```dart
// test/services/menu_classifier_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/menu_classifier.dart';

void main() {
  group('MenuClassifier', () {
    group('classifyDish', () {
      test('returns GREEN for keto-safe steak', () {
        final result = MenuClassifier.classifyDish(
          name: 'Grilled Steak',
          description: 'Served with butter',
        );

        expect(result.status, equals('GREEN'));
      });

      test('returns YELLOW for steak with fries', () {
        final result = MenuClassifier.classifyDish(
          name: 'Ribeye',
          description: 'Served with French fries and vegetables',
        );

        expect(result.status, equals('YELLOW'));
        expect(result.waiterInstructions, contains('fries'));
      });

      test('returns RED for pasta', () {
        final result = MenuClassifier.classifyDish(
          name: 'Spaghetti Carbonara',
          description: 'With bacon and cream sauce',
        );

        expect(result.status, equals('RED'));
      });
    });
  });
}
```

## CI/CD Integration

Unit tests should run automatically on every PR:

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: flutter test --coverage
      - uses: codecov/codecov-action@v3
        with:
          files: ./coverage/lcov.info
```

## Continuous Improvement

- Review test coverage monthly
- Remove tests that don't catch regressions
- Refactor tests to reduce duplication
- Add tests when bugs are found
- Keep test execution time under 5 minutes
