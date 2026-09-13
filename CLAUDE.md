# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**KetoClub** is a restaurant menu analysis platform designed to help keto dieters find safe dining options. The app ingests live menus from restaurant delivery platforms, classifies dishes by keto-compatibility, and generates automatic waiter instructions for modifications.

## Architecture & Core Components

### Client-Only Architecture (No Backend)

Single Flutter codebase for web, iOS, and Android with:
- **Classification Engine**: Heuristic-based keto dish classifier running client-side in Dart
- **API Integration**: Direct calls to restaurant platform APIs (Wolt, 10bis, Tabit, Ontopo) from the client
- **Local Storage**: Device-level caching using Hive or SharedPreferences (optional, for offline access)
- **No server, no database**: All menu analysis and data processing happens on the user's device

### Menu Ingestion & API Integration

KetoClub integrates with four restaurant platform APIs:

| Platform | Auth | Data Format | Primary Use |
|----------|------|-------------|------------|
| **Wolt** | None (slug-based) | Standardized JSON (items, categories, options) | Primary delivery aggregator |
| **10bis** | None (restaurant ID) | Hierarchical JSON (categories → dishes) | Israeli corporate delivery |
| **Tabit** | Session token via QR | POS-level JSON (modifiers, kitchen groups) | Restaurant dine-in QR ordering |
| **Ontopo** | Anonymous bearer token | PDF/S3-hosted links (OCR-capable) | Reservation platform with menu links |

Key fetch patterns:
- **Wolt**: `GET https://restaurant-api.wolt.com/v4/venues/slug/{venue_slug}/menu/data`
- **10bis**: `GET https://www.10bis.co.il/api/v1.0/Restaurants/{restaurantId}/Menu`
- **Tabit**: `GET https://tgp-api.tabit.cloud/menu/v2/{site_id}`
- **Ontopo**: `POST /api/loginAnonymously` → `GET /api/venue/{venue_id}` with bearer token

All APIs return unstructured dish names/descriptions that feed into the classification engine.

### Keto Classification Engine

Every dish is evaluated against regex-based heuristics and classified:

- **🟢 GREEN**: Net carbs ≤6g, healthy fat/protein, no starchy sides/sauces → Order as-is
- **🟡 YELLOW**: Salvageable core (protein/salad) but includes carb sides/sauces → Order with modifications
- **🔴 RED**: Fundamentally high-carb (pasta, pizza, risotto, etc.) → Filtered from display

**Carb triggers** (partial list from README's `CARB_MODIFIERS`):
- Starch: puree, mashed potatoes, fries, chips, rice, corn, beets, sweet potato
- Sugary sauces: teriyaki, honey, BBQ

**Non-keto bases** that auto-fail:
- pasta, spaghetti, pizza, calzone, risotto, noodles, ramen, brioche, sandwich, pancake, waffle

Classification generates automatic waiter scripts for Yellow dishes (e.g., "Replace potato purée with green salad or steamed vegetables").

### Database Schema

Three core entities:

**Venues** (restaurants)
- `id`, `name`, `address`, `latitude`, `longitude`
- `keto_rating_score`: Community-derived score
- `is_verified_keto_friendly`: Flag for venues offering deliberate keto options (cloud bread, cauliflower rice, tallow)

**Menus** (per-venue, per-platform)
- `id`, `venue_id`, `last_scraped_at`, `data_source` (enum: wolt, 10bis, tabit, ontopo)
- Cache expiration tracking for stale menu detection

**Dishes** (menu items)
- `id`, `menu_id`, `name`, `description`, `price`, `status` (GREEN/YELLOW/RED)
- `waiter_script`: Auto-generated modification instructions
- `net_carbs_estimate`: Heuristic-derived carb count

Future additions: user ratings, review feedback loop, OCR/vision processing for physical menus.

## Development Workflow

### Current Status: Research & Planning Phase

⚠️ **No code has been implemented yet.** The repository contains:
- Detailed architectural documentation (README.md)
- API endpoint specifications and reverse-engineering notes
- Keto classification heuristics and waiter script templates
- Database entity definitions and ER diagrams
- Research documents on AI/LLM integration (OpenRouter, structured output)
- Feature prioritization and phase roadmap

### Expected Project Structure (to build)

When implementation begins, follow this layout:

```
ketoclub/
├── lib/
│   ├── main.dart                     # Flutter app entry point
│   ├── screens/
│   │   ├── venue_search_screen.dart  # Location/restaurant search
│   │   ├── menu_detail_screen.dart   # Display classified menu
│   │   └── settings_screen.dart      # User preferences
│   ├── widgets/
│   │   ├── dish_card.dart            # Reusable dish card with status badge
│   │   ├── status_badge.dart         # GREEN/YELLOW/RED badge
│   │   └── waiter_script_widget.dart # Expandable waiter instructions
│   ├── services/
│   │   ├── restaurant_api_client.dart    # Direct calls to Wolt, 10bis, Tabit, Ontopo
│   │   ├── location_service.dart        # Device geolocation
│   │   └── menu_classifier.dart         # Client-side keto classification logic
│   ├── models/
│   │   ├── dish.dart                 # Dish data class
│   │   ├── menu.dart                 # Menu data class
│   │   └── venue.dart                # Venue data class
│   └── utils/
│       ├── constants.dart            # Carb modifiers, non-keto bases, waiter templates
│       ├── classification_rules.dart # Regex patterns, heuristic matchers
│       └── local_storage.dart        # Hive/SharedPreferences wrapper (optional)
├── ios/                              # iOS-specific configuration
│   ├── Podfile
│   └── Runner.xcodeproj/
├── android/                          # Android-specific configuration
│   ├── app/
│   └── AndroidManifest.xml
├── web/                              # Web-specific files
│   └── index.html
├── pubspec.yaml                      # Flutter dependencies
├── pubspec.lock
└── analysis_options.yaml             # Dart analysis settings
```

### Setup (when code exists)

**Flutter Application (web, iOS, Android):**
```bash
flutter pub get                          # Install dependencies

# Run on web (localhost:8080)
flutter run -d chrome                    # Or 'web' for headless web build

# Run on iOS (macOS only)
flutter run -d "iPhone 15"              # Or use simulator ID from 'flutter devices'

# Run on Android
flutter run -d emulator                  # Or use connected device ID

# Build for production
flutter build web                        # Build web (output in build/web/)
flutter build ios                        # Build iOS app
flutter build apk                        # Build Android APK
flutter build appbundle                 # Build Android App Bundle for Play Store
```

**No backend or database setup required** — all data processing and API calls happen on the client device.

## Implementation Notes & Design Decisions

### Client-Only Architecture (from README & research docs)

1. **Heuristic-based classification (client-side)**: 
   - Implement regex patterns on dish name + description in Dart (see `CARB_MODIFIERS` and `NON_KETO_BASES` in README)
   - Build `MenuClassifier` service that evaluates dishes and returns status (GREEN/YELLOW/RED) + waiter script
   - No backend needed; logic lives in `lib/services/menu_classifier.dart`

2. **Restaurant API clients (direct from device)**:
   - Wolt: Slug-based, no auth required (easiest starting point)
   - 10bis: Restaurant ID lookup, no auth needed
   - Tabit: Session token via QR endpoint (more complex, can defer to later)
   - Ontopo: Bearer token + PDF links (lowest priority)
   - All calls made directly from Flutter app using `http` package or `dio`

3. **Waiter script generation (client-side)**:
   - Pre-composed template strings in `lib/utils/constants.dart` (see README examples)
   - `MenuClassifier` returns both status and matching waiter instructions
   - No NLG or backend processing needed

4. **Single codebase for all platforms** (Flutter):
   - One directory targeting web, iOS, and Android
   - Responsive UI using Flutter's adaptive widgets (`ResponsiveBuilder`, `LayoutBuilder`)
   - Share all business logic: API clients, classifier, constants across platforms

5. **Geolocation strategy**:
   - Use `geolocator` package for cross-platform device location
   - Web: Browser Geolocation API with permission handling
   - iOS/Android: Native OS permissions with graceful fallback to manual input
   - Once user provides location, search for nearby venues (no radius endpoint needed; filter results client-side)

6. **Local caching (optional)**:
   - Use `hive` or `shared_preferences` to cache fetched menus locally on device
   - Enables offline viewing of previously loaded menus
   - Optional for MVP; can skip if not needed initially

7. **Platform-specific considerations**:
   - **iOS**: Configure `Info.plist` for location permission prompts
   - **Android**: Configure `AndroidManifest.xml` for location + internet permissions
   - **Web**: Responsive layout for desktop/tablet/mobile browsers
   - Use `kIsWeb`, `Platform`, and conditional rendering to handle platform differences

8. **Future backend (Phase 3+)**: 
   - If user ratings and venue reviews are added later, a backend can be introduced
   - For now, all MVP features work client-side with no server infrastructure

## Planning & Research Documents

**Core Documentation:**
- `architecture.md`: The authoritative architecture (client-only Flutter app, LLM-primary classifier with heuristic fallback, adapters, storage, failure handling, decisions log). Read this before the README where they disagree
- `README.md`: Full project narrative, API endpoints, database schema, keto classification rules, Phase roadmap

**Research & Analysis:**
- `m16_menu_scanner_research.md`: Computer vision and OCR strategy for physical menu scanning (Phase 4)
- `m15_meal_entry_research.md`: User flow design for meal logging and macro tracking
- `m15_openrouter_models_fix.md` / `m16_structured_output_fix.md`: LLM model evaluation and structured output schemas (if integrating AI for edge cases)
- `menu_api_research`: Platform API comparison and reverse-engineering notes
- `feature_prioratization`: Phase breakdown and feature prioritization

**Conventions:**
When reading research docs (m15/m16), note that prefixes indicate iteration/milestone markers—not all research conclusions are adopted, so verify against the `feature_prioratization` document and README roadmap before implementing.

## Project Phases

- **Phase 1**: Core parsing, heuristic engine, waiter script generation → **Designed (README documented), not implemented**
- **Phase 2**: Mobile interface, geolocation, search filtering → **Planned**
- **Phase 3**: Community database, user reviews, restaurant submissions → **Planned**
- **Phase 4**: OCR/vision, configurable dietary rules → **Planned**

Currently, only Phase 1 is specified and planned. Phase 2 is next priority (see `feature_prioratization`).

## What's NOT in This Repository

- ❌ No backend (Python, Node, etc.) — not needed for MVP
- ❌ No database (PostgreSQL, etc.) — not needed for MVP
- ❌ No Flutter app code (web, iOS, Android)
- ❌ No API client implementations for restaurant platforms
- ❌ No tests or CI/CD configuration
- ❌ No Flutter dependencies installed (no `.packages`, no build artifacts)

**Build order (client-only MVP):**
1. Flutter project structure with dependencies
2. Restaurant API clients (Wolt, 10bis, Tabit, Ontopo)
3. Menu classifier and waiter script generator
4. UI screens and widgets
5. Geolocation and venue search

A backend can be added later (Phase 3+) when user ratings/community features are needed.

## Getting Started (New Developer)

### Before Writing Code

1. **Read the full narrative**: `README.md` (sections 1–8) covers core value, UX flow, classification engine, API details, and database schema
2. **Understand the classification rules**: Memorize the `CARB_MODIFIERS` and `NON_KETO_BASES` lists (README lines 183–204); these drive dish evaluation
3. **Map the APIs**: Review the Platform Architectural Comparison table (README lines 79–82) and endpoint specs for each platform
4. **Review the ER schema**: Diagram in README (around line 318)—three entities, one menu per venue per platform
5. **Check feature priorities**: Read `feature_prioratization` to understand Phase 1 scope vs. Phase 2–4 deferred work

### Starting Implementation (Client-Only MVP)

**Phase 1: Flutter Project Setup**

1. **Initialize Flutter project**
   ```bash
   flutter create --org com.ketoclub ketoclub
   cd ketoclub
   flutter config --enable-web
   ```

2. **Add dependencies** to `pubspec.yaml`:
   - `http` or `dio` → HTTP client for restaurant APIs
   - `geolocator` → Cross-platform geolocation (device location)
   - `provider` → State management for menu caching
   - `intl` → Date/number formatting (optional)

**Phase 2: Core Business Logic**

1. **API Clients** (`lib/services/restaurant_api_client.dart`)
   - Implement Wolt client first (simplest, no auth):
     - `fetchWoltMenu(venueSlug)` → HTTP GET to Wolt API
     - Parse JSON response into Dart models
   - Add 10bis client next
   - Defer Tabit, Ontopo to later phase

2. **Menu Classifier** (`lib/services/menu_classifier.dart`)
   - Implement the logic from README's `KetoMenuIngestionService` class (lines 181–296) in Dart
   - Take dish name + description, return `DishClassification`:
     ```dart
     class DishClassification {
       String status;  // GREEN, YELLOW, RED
       String badge;   // 🟢, 🟡, 🔴
       List<String> waiterInstructions;
     }
     ```
   - Use regex matching against `CARB_MODIFIERS` and `NON_KETO_BASES` from README

3. **Models** (`lib/models/`)
   - `dish.dart` → Name, description, price, status, waiter script
   - `menu.dart` → List of dishes, venue info
   - `venue.dart` → Name, address, latitude, longitude

**Phase 3: UI & Screens**

1. **Main entry point** (`lib/main.dart`)
   - Set up MaterialApp with home screen

2. **Venue Search Screen** (`lib/screens/venue_search_screen.dart`)
   - Get user's device location via `geolocator`
   - Display list of nearby restaurants (from hardcoded list or Wolt venue search)
   - Allow manual search by restaurant name

3. **Menu Detail Screen** (`lib/screens/menu_detail_screen.dart`)
   - Fetch menu from restaurant API (Wolt, 10bis, etc.)
   - Run classifier on each dish
   - Display in scrollable list with color-coded cards

4. **Widgets** (`lib/widgets/`)
   - `dish_card.dart` → Show dish name, price, status badge (🟢/🟡/🔴)
   - `status_badge.dart` → Colored badge widget
   - `waiter_script_widget.dart` → Expandable box with waiter instructions (copyable text)

5. **Utils** (`lib/utils/`)
   - `constants.dart` → CARB_MODIFIERS, NON_KETO_BASES, waiter script templates (from README)
   - `classification_rules.dart` → Regex patterns and matching logic

**Phase 4: Platform-Specific Setup**

1. **iOS** (`ios/Runner/Info.plist`)
   - Add location permission prompt:
     ```xml
     <key>NSLocationWhenInUseUsageDescription</key>
     <string>KetoClub needs your location to find nearby restaurants</string>
     ```

2. **Android** (`android/app/src/main/AndroidManifest.xml`)
   - Add location and internet permissions:
     ```xml
     <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
     <uses-permission android:name="android.permission.INTERNET" />
     ```

3. **Web** (no special setup needed)
   - Uses browser Geolocation API automatically via `geolocator`

**Development Workflow**

1. Start with web for fast iteration: `flutter run -d chrome`
2. Build classifier first (no UI needed to test), validate against README examples
3. Add Wolt API client and test with real restaurant data
4. Build UI screens incrementally
5. Test on iOS simulator: `flutter run -d "iPhone 15"`
6. Test on Android emulator: `flutter run -d emulator`
7. Verify across all platforms: geolocation works, menus load, classification is correct

**All three platforms share:** API clients, classifier logic, models, and utilities. Only UI/platform-specific code differs (geolocation permissions, screen layouts).
