KetoClub 🥑

Have you ever been on keto and struggled to decipher what you could actually order from a restaurant?

Well, fear no more! Introducing KetoClub — the app designed to make a day out eating easy, stress-free, and accessible to keto pals like us!
⸻
Table of Contents

1. Overview & Core Value
2. End-to-End User Experience
3. The Traffic-Light Classification Engine
4. Waiter Instruction Generator
5. Menu Data Ingestion & API Research
    - Platform Architectural Comparison
    - Wolt Integration
    - 10bis Integration
    - Tabit Cloud POS Integration
    - Ontopo Integration
    - Reverse Engineering Protocol
6. Ingestion & Normalization Engine (Python Implementation)
7. Persistent Database & Data Architecture
8. Roadmap & Milestone Tracking
9. Development Setup & Installation
⸻
Overview & Core Value

Dining out on a strict ketogenic diet is notoriously challenging:
* Hidden Sugars & Carbohydrates: Sauces, dressings, marinades, and glazes frequently contain hidden honey, cornstarch, flour, or brown sugar.
* Default Starch Pairings: Steaks, fish, and burgers are almost universally served alongside French fries, potato purée, rice, or glazed carrots.
* Ordering Anxiety: Guests often feel uncomfortable negotiating substitutions or asking waitstaff repeated questions about food preparation.

KetoClub solves this by pulling real-time restaurant menus across your local area, analyzing the ingredients and modifiers of every item, and presenting an intuitive, color-coded menu that tells you precisely what to order and what modifications to request.
⸻
End-to-End User Experience

 ┌────────────────────────────────────────────────────────┐
 │                      Discovery                         │
 │   Search local venues by Name, Neighborhood, Address   │
 └──────────────────────────┬─────────────────────────────┘
                            │ Select Restaurant
                            ▼
 ┌────────────────────────────────────────────────────────┐
 │                    Menu Fetching                       │
 │      Direct API Ingestion (Wolt, 10bis, Tabit)         │
 └──────────────────────────┬─────────────────────────────┘
                            │ Raw Menu JSON
                            ▼
 ┌────────────────────────────────────────────────────────┐
 │                Keto Engine Analysis                    │
 │  Scans proteins, cuts, starches, seed oils & sauces    │
 └──────────────────────────┬─────────────────────────────┘
                            │ Evaluated Dishes
                            ▼
 ┌────────────────────────────────────────────────────────┐
 │                  Interactive Menu UI                   │
 │   🟢 Green: Order As-Is    🟡 Yellow: Modify + Script  │
 └────────────────────────────────────────────────────────┘
1. Search & Geo-Filtering: Search nearby eateries by name, street address, or geographic district.
2. Venue Selection: Selecting a restaurant opens its live menu page.
3. Automated Analysis: The engine evaluates every item, parsing its title, description, and available modifiers.
4. Color-Coded Output: The menu displays clear visual badges:
    * Green items: Zero changes needed.
    * Yellow items: Display an expandable box with exact waitstaff instructions (e.g., "Hold the purée," "Omit carrots from the side salad").
The Traffic-Light Classification Engine
Every dish on an ingested menu is categorized using strict ketogenic dietary heuristics:
Classification	Meaning	Nutritional Criteria	Customer Action
🟢 Green	Safe As-Is	Net carbohydrates ≤6g, healthy fat/protein foundation, zero starchy sides, no sweet marinades or flours.	Order directly off the menu without special requests.
🟡 Yellow	Safe with Modifications	The core protein or salad is keto-compliant, but accompanied by a starchy side (fries, purée), root vegetable (carrots, beets), or sugary dressing.	Order using the generated waiter script to substitute or remove carb components.
🔴 Excluded / Red	Not Keto-Compatible	Dishes built on high-carbohydrate fundamentals that cannot be customized (e.g., wheat pasta, pizza crust, grain bowls, breaded proteins).	Filtered out of view or flagged as non-keto.
Waiter Instruction Generator
For every dish flagged as 🟡 Yellow, KetoClub automatically generates actionable, polite, and precise requests you can read or show to your server:
* Starchy Sides: "Please replace the potato purée with a green salad, sautéed mushrooms, or extra steamed greens." 
* Salad Ingredients: "Could you please prepare the salad without carrots or sweet corn, and provide olive oil and fresh lemon on the side instead of the house vinaigrette?" 
* Glazes & Sauces: "Please ask the kitchen to grill the protein without the honey/sweet glaze, and serve any sauce in a ramekin on the side." 
* Burgers & Sandwiches: "Please serve the burger without the bun (naked / lettuce wrap), and swap the French fries for leafy greens or a fried egg." 
Menu Data Ingestion & API Research
To provide live menus, KetoClub taps into existing hospitality platform APIs. Because consumer menus are public data, these platforms supply structured feeds without requiring authenticated partner contracts.
Platform Architectural Comparison
Platform	Core Business Model	Menu Source of Truth	Data Format & Quality	API Accessibility
Wolt	Food Delivery & Marketplace	Restaurant portal validated by Wolt catalog operations.	Standardized, normalized JSON schema (items, categories, options).	Trivial (Slug-only, public GET, no token required).
10bis	Corporate & Retail Delivery	Merchant POS sync / manual portal uploads.	Hierarchical JSON tree (categoriesList → dishList).	Trivial (Numeric Restaurant ID, no auth).
Tabit	In-Restaurant POS & ERP	Point of Sale database configured directly by restaurant managers.	POS-level relational JSON (modifiers, kitchen groups, custom questions).	Moderate (Session tokens via tabit.cloud QR code endpoints).
Ontopo	Table Reservations & Seating	Hostess management with optional manual menu uploads.	Often static links (PDFs, S3-hosted JPG images, or external URLs).	Low utility (Requires anonymous bearer token; rarely structured).
Wolt Integration
Wolt offers the most uniform, structured REST endpoint.
* Method: GET
* Target Endpoint: HTTP  GET [https://restaurant-api.wolt.com/v4/venues/slug/](https://restaurant-api.wolt.com/v4/venues/slug/){venue_slug}/menu/data
*    
* Parameters: venue_slug (e.g., vitrina-lilinblum, extracted directly from the restaurant's public URL).
* Currency Formatting: Wolt stores prices in integer sub-units (cents/agorot). A price of 6400 represents 64.00 ILS. Divide by 100 for presentation.
* Payload Structure: JSON  {
*   "currency": "ILS",
*   "categories": [
*     {
*       "id": "cat_steaks",
*       "name": "Meat & Steaks",
*       "item_ids": ["dish_entrecote_300"]
*     }
*   ],
*   "items": [
*     {
*       "id": "dish_entrecote_300",
*       "name": "Prime Entrecôte 300g",
*       "description": "Served with butter-infused potato purée and baby carrots",
*       "price": 14200,
*       "options": ["opt_sides_choice"]
*     }
*   ],
*   "options": [
*     {
*       "id": "opt_sides_choice",
*       "name": "Choice of Side",
*       "type": "radio",
*       "values": [
*         { "id": "val_puree", "name": "Potato Purée", "price": 0 },
*         { "id": "val_salad", "name": "Green Salad", "price": 0 }
*       ]
*     }
*   ]
* }
*    
10bis Integration
10bis organizes dishes into nested category and item lists.
* Method: GET
* Target Endpoint: HTTP  GET [https://www.10bis.co.il/api/v1.0/Restaurants/](https://www.10bis.co.il/api/v1.0/Restaurants/){restaurantId}/Menu
*    
* Parameters: restaurantId (e.g., 12345, visible in page URLs and network queries).
* Payload Structure: JSON  {
*   "categoriesList": [
*     {
*       "categoryName": "Main Dishes",
*       "dishList": [
*         {
*           "dishId": 987654,
*           "dishName": "Grilled Chicken Breast",
*           "dishDescription": "Marinated in herbs, served with white rice and roasted root vegetables",
*           "dishPrice": 58.0,
*           "dishOptionsList": []
*         }
*       ]
*     }
*   ]
* }
*    
Tabit Cloud POS Integration
For dine-in venues where customers order or browse via QR code at tables, Tabit exposes live POS data.
* Target Endpoints: HTTP  GET [https://tgp-api.tabit.cloud/menu/v2/](https://tgp-api.tabit.cloud/menu/v2/){site_id}
* GET [https://online.tabit.cloud/api/v1/ordering/menu?siteId=](https://online.tabit.cloud/api/v1/ordering/menu?siteId=){site_id}
*    
* Payload Attributes: Items map 1:1 with internal POS kitchen categories, modifiers (forced choices, sides, temperatures), and ingredient-level exclusion flags.
Ontopo Integration
Ontopo focuses on reservation logistics. If menu data is present, it is often referenced as media links.
* Authentication Endpoint: HTTP  POST [https://ontopo.com/api/loginAnonymously](https://ontopo.com/api/loginAnonymously)
*    
* Venue Query: HTTP  GET [https://ontopo.com/api/venue/](https://ontopo.com/api/venue/){venue_id}
* Authorization: Bearer <ANONYMOUS_TOKEN>
*    
* Payload Response: JSON  {
*   "venue_name": "Brasserie Center",
*   "menu_pdf_url": "[https://s3.eu-central-1.amazonaws.com/ontopo-media/menus/brasserie_dinner.pdf](https://s3.eu-central-1.amazonaws.com/ontopo-media/menus/brasserie_dinner.pdf)",
*   "external_menu_url": "[https://restaurant-site.com/menu](https://restaurant-site.com/menu)"
* }
*     Note: Structured item extraction from Ontopo typically requires downstream OCR or PDF parsing models.
Reverse Engineering Protocol
To capture new or modified endpoints directly in a web browser:
1. Open Google Chrome or Firefox and press F12 to enter Developer Tools.
2. Select the Network tab and activate the Fetch/XHR filter.
3. Browse to the restaurant's online ordering or menu catalog page.
4. Filter by terms such as menu, catalog, venue, items, or ordering.
5. Locate the request returning HTTP status 200 with application/json Content-Type.
6. Right-click the record → select Copy as cURL to export the request, headers, and parameters directly into code or Postman.
Ingestion & Normalization Engine (Python Implementation — superseded, and NOT `backend/`)

> **Superseded by `architecture.md` D1 and D2.** Ingestion and normalisation are
> implemented in Dart, on the device (`lib/services/menu/`). The Python below is the
> original prototype and runs nowhere. In particular it is **not** what lives in
> `backend/`: that service deliberately does not parse menus, precisely so there is
> only one normaliser to keep correct. Read this section as history.

The following production-ready module demonstrates how to fetch a menu from Wolt, run it through the keto heuristic parser, assign 🟢 Green / 🟡 Yellow status, and generate custom waiter scripts:
Python

import re
from typing import Any, Dict, List, Optional
import requests


class KetoMenuIngestionService:
    # High-carb ingredients that trigger modifications
    CARB_MODIFIERS = {
        "puree": "Swap potato purée for green salad or steamed vegetables",
        "mashed potatoes": "Swap mashed potatoes for leafy greens",
        "fries": "Replace French fries with a fresh green salad or a fried egg",
        "chips": "Replace chips with fresh vegetables or salad",
        "rice": "Omit rice and request double vegetables or salad",
        "carrot": "Ask to leave out carrots from the dish/salad",
        "carrots": "Ask to leave out carrots from the dish/salad",
        "corn": "Ask to leave out sweet corn",
        "beets": "Omit beets from the dish",
        "sweet potato": "Omit sweet potato or substitute with zucchini/broccoli",
        "teriyaki": "Request without teriyaki sauce (contains sugar/mirin)",
        "honey": "Ask for the dish to be prepared without honey",
        "bbq": "Ask for barbecue glaze to be omitted (high in sugar)",
    }

    # High-carb base indicators that render dishes completely non-keto
    NON_KETO_BASES = [
        "pasta", "spaghetti", "penne", "fettuccine", "gnocchi",
        "pizza", "calzone", "risotto", "noodle", "noodles",
        "ramen", "brioche bun", "sandwich", "toast", "pancake", "waffle"
    ]

    def __init__(self, user_agent: Optional[str] = None):
        self.headers = {
            "User-Agent": user_agent or (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120.0.0.0 Safari/537.36"
            ),
            "Accept": "application/json"
        }

    def fetch_wolt_menu(self, venue_slug: str) -> Dict[str, Any]:
        """Fetches raw menu JSON from Wolt's internal API."""
        endpoint = f"[https://restaurant-api.wolt.com/v4/venues/slug/](https://restaurant-api.wolt.com/v4/venues/slug/){venue_slug}/menu/data"
        response = requests.get(endpoint, headers=self.headers, timeout=10)
        response.raise_for_status()
        return response.json()

    def analyze_dish(self, name: str, description: str) -> Dict[str, Any]:
        """Applies heuristic rules to categorize a dish and generate waiter prompts."""
        full_text = f"{name.lower()} {description.lower()}"

        # 1. Evaluate whether the item is unsalvageable (Red)
        for base in self.NON_KETO_BASES:
            if re.search(rf"\b{re.escape(base)}\b", full_text):
                return {
                    "status": "RED",
                    "badge": "🔴 Not Keto-Compatible",
                    "is_safe": False,
                    "instructions": []
                }

        # 2. Check for modifiable elements (Yellow)
        detected_modifications = []
        for trigger, prompt in self.CARB_MODIFIERS.items():
            if re.search(rf"\b{re.escape(trigger)}\b", full_text):
                detected_modifications.append(prompt)

        if detected_modifications:
            return {
                "status": "YELLOW",
                "badge": "🟡 Safe with Modifications",
                "is_safe": True,
                "instructions": list(set(detected_modifications))
            }

        # 3. Default to safe as-is (Green)
        return {
            "status": "GREEN",
            "badge": "🟢 Safe As-Is",
            "is_safe": True,
            "instructions": ["No adjustments needed. Order directly from the menu!"]
        }

    def process_wolt_venue(self, venue_slug: str) -> List[Dict[str, Any]]:
        """Ingests, parses, categorizes, and formats all dishes for display."""
        raw_data = self.fetch_wolt_menu(venue_slug)
        items_by_id = {item["id"]: item for item in raw_data.get("items", [])}
        processed_categories = []

        for category in raw_data.get("categories", []):
            category_dishes = []
            for item_id in category.get("item_ids", []):
                item = items_by_id.get(item_id)
                if not item:
                    continue

                name = item.get("name", "").strip()
                description = item.get("description", "").strip()
                price_ils = item.get("price", 0) / 100.0

                analysis = self.analyze_dish(name, description)

                category_dishes.append({
                    "id": item.get("id"),
                    "name": name,
                    "description": description,
                    "price_ils": price_ils,
                    "status": analysis["status"],
                    "badge": analysis["badge"],
                    "is_safe": analysis["is_safe"],
                    "waiter_instructions": analysis["instructions"]
                })

            if category_dishes:
                processed_categories.append({
                    "category_id": category.get("id"),
                    "category_name": category.get("name"),
                    "dishes": category_dishes
                })

        return processed_categories


if __name__ == "__main__":
    service = KetoMenuIngestionService()
    test_slug = "vitrina-lilinblum"
    print(f"Fetching and parsing menu for: {test_slug}...\n")
    
    try:
        menu_catalog = service.process_wolt_venue(test_slug)
        for cat in menu_catalog:
            print(f"\n==================== {cat['category_name']} ====================")
            for dish in cat["dishes"]:
                print(f"\n{dish['badge']} | {dish['name']} ({dish['price_ils']:.2f} ILS)")
                if dish["description"]:
                    print(f"  Description: {dish['description']}")
                for note in dish["waiter_instructions"]:
                    print(f"  👉 Waiter Script: {note}")
    except Exception as error:
        print(f"Failed to fetch venue data: {error}")
Persistent Database & Data Architecture (planned — NOT the backend's schema)

> **Superseded by `architecture.md` D1 and §7.** The PostgreSQL model below is the
> original design for Phase 3 community data. The backend that exists today stores
> exactly one table, a cache of raw upstream menu bodies, in SQLite.

To ensure speed and offline capabilities, KetoClub maintains a persistent database of reviewed, rated, and verified keto-accessible restaurants.
┌─────────────────────────────────┐       ┌───────────────────────────────────┐
│             Venues              │       │               Menus               │
├─────────────────────────────────┤       ├───────────────────────────────────┤
│ id: UUID (PK)                   │1     *│ id: UUID (PK)                     │
│ name: VARCHAR                   ├───────┤ venue_id: UUID (FK)               │
│ address: VARCHAR                │       │ last_scraped_at: TIMESTAMP        │
│ latitude: FLOAT                 │       │ data_source: ENUM                 │
│ longitude: FLOAT                │       └─────────────────┬─────────────────┘
│ keto_rating_score: FLOAT        │                         │ 1
│ is_verified_keto_friendly: BOOL │                         │
└─────────────────────────────────┘                         │ *
                                          ┌─────────────────┴─────────────────┐
                                          │             Dishes                │
                                          ├───────────────────────────────────┤
                                          │ id: UUID (PK)                     │
                                          │ menu_id: UUID (FK)                │
                                          │ name: VARCHAR                     │
                                          │ description: TEXT                 │
                                          │ price: DECIMAL                    │
                                          │ status: ENUM (GREEN, YELLOW, RED) │
                                          │ waiter_script: TEXT               │
                                          │ net_carbs_estimate: FLOAT         │
                                          └───────────────────────────────────┘
Database Entities
1. Venues:
    * Physical address, coordinates (for radius searches), city, and community score.
    * is_verified_keto_friendly: Flagged as true when a venue offers deliberate keto substitutes (e.g., cloud bread, cauliflower rice, tallow cooking fat).
2. Menus:
    * Tracks source platforms (wolt, 10bis, tabit, manual) and cache expiration dates.
3. Dishes & Modification Templates:
    * Normalized records of every dish, its detected category (🟢 / 🟡 / 🔴), and exact waiter instruction templates.
Roadmap & Milestone Tracking
* [x] Phase 1: Core Parsing & Prototype
    * [x] Reverse-engineer major delivery and POS API feeds (Wolt, 10bis, Tabit).
    * [x] Heuristic classification engine (Green vs. Yellow vs. Red).
    * [x] Dynamic generation of waitstaff modification instructions.
* [ ] Phase 2: Mobile Interface & Discovery Engine
    * [ ] Cross-platform mobile client (Flutter).
    * [ ] Geolocation integration and address-based venue search.
    * [ ] Search filtering by dish type (e.g., "Show only steakhouses with Green ratings").
* [ ] Phase 3: Backend & Persistent Community Database
    * [x] Backend foundations: a service that lets the web build fetch menus a browser would otherwise refuse.
    * [ ] Verified directory of keto-dedicated and keto-accessible restaurants.
    * [ ] User review feedback loop ("Did the restaurant accommodate your substitution?").
    * [ ] User submissions for unlisted restaurants and manual review tagging.
* [ ] Phase 4: Advanced Nutritional Intelligence
    * [ ] Computer Vision & OCR: Snap a photo of a physical printed paper menu to receive the same color-coded breakdown.
    * [ ] Configurable dietary rules: Support for carnivore, pesco-keto, and strict seed-oil avoidance modes.
Development Setup & Installation
**Prerequisites**
* Flutter SDK 3.47.4 — builds all three targets, web included. Pinned in `pubspec.yaml`
  and `.github/workflows/ci.yml`
* Python 3.11 or later, and [uv](https://docs.astral.sh/uv/) — only if you want the
  backend, which only the web build needs

No database to install: the backend uses SQLite and creates its file on first run.

**1. Clone**

```bash
git clone https://github.com/NoaMcDa/KetoClub.git
cd KetoClub
```

**2. Run the app**

The Flutter project is at the repository root, not in a `frontend/` directory.

```bash
flutter pub get
flutter run -d <device>      # iOS or Android: fetches menus directly, no backend
```

**3. The backend — web only**

A browser refuses a request to Wolt, because Wolt sends no CORS headers, so the web
build cannot fetch a menu on its own. The backend makes that call from a server and
relays the answer unchanged. Nothing else needs it, and nothing depends on it: with
no backend configured the app behaves exactly as it does without one.

```bash
cd backend
uv sync
uv run uvicorn app.main:app --reload --port 8000
```

Then, in another terminal:

```bash
flutter run -d chrome --dart-define=KETOCLUB_BACKEND_URL=http://localhost:8000
```

Routes live under `/v1` (`/v1/health`, `/v1/proxy/wolt/…`). See `backend/README.md`
for the endpoints and `architecture.md` D11 for why it exists.

**Checks**

```bash
tool/check.sh        # the app: format, analyze, tests, coverage
backend/check.sh     # the backend: ruff, mypy, pytest, coverage
```
License
Distributed under the MIT License. See LICENSE for details.
