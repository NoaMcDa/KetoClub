"""A stand-in for Wolt and 10bis that serves this repository's fixtures, so
the real web build can be rendered end to end with no network at all
(docs/VISUAL_AUDIT.md).

    python3 tool/visual_audit/stub_upstream.py [port]      # default 9999

Point the backend's upstream hosts at it (WOLT_BASE_URL,
WOLT_CONSUMER_BASE_URL, TENBIS_BASE_URL); the backend itself is unchanged.

Routes, at the paths backend/app/services/{wolt,tenbis}.py call:
  GET  /v4/venues/slug/vitrina-lilinblum/menu/data  the Wolt menu fixture
  GET  /v4/venues/slug/<any other>/menu/data        a menu mirroring
                                                    .design/Main.dc.html
  GET  /v1/pages/restaurants                        wolt_pages_restaurants
  POST /v1/pages/search                             wolt_pages_search
  GET  /api/v1.0/Restaurants/<id>/Menu              the 10bis fixture
  GET  /img/<name>.png                              a generated dish photo

Needs Pillow only for /img/ (every other route is standard library).
"""

import io
import json
import pathlib
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FIXTURES = pathlib.Path(__file__).resolve().parents[2] / "test" / "fixtures"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9999

# The dishes .design/Main.dc.html draws, as a Wolt-shaped menu, plus three
# more so every verdict and the photo placeholder all appear.
_DISHES = [
    ("entrecote", "Prime Entrecôte 300g",
     "Aged 300g cut over charcoal, herb butter, grilled onion.", 14200, True),
    ("seabass", "Sea Bass Fillet",
     "Whole fillet, lemon and thyme, served with potato purée and baby "
     "carrots.", 12800, True),
    ("carpaccio", "Beef Carpaccio",
     "Thin sliced sirloin, olive oil, aged parmesan, rocket.", 6400, False),
    ("chicken", "Charcoal Chicken Thigh",
     "Boneless thigh in a honey-teriyaki glaze, served over rice.", 9600,
     True),
    ("gnocchi", "Truffle Gnocchi", "Potato gnocchi, cream, black truffle.",
     8800, False),
    ("burger", "Smash Burger",
     "Two patties, cheddar, pickles, brioche bun, fries.", 7200, True),
    ("salad", "Greek Salad",
     "Tomato, cucumber, feta, olives, oregano, olive oil.", 5200, False),
    ("salmon", "Grilled Salmon",
     "Salmon fillet with mashed potatoes and grilled asparagus.", 11800,
     False),
]


def _artboard_menu() -> bytes:
    items = []
    for dish_id, name, description, price, photo in _DISHES:
        item = {"id": dish_id, "name": name, "description": description,
                "price": price, "options": []}
        if photo:
            item["image"] = f"http://127.0.0.1:{PORT}/img/{dish_id}.png"
        items.append(item)
    ids = [d[0] for d in _DISHES]
    menu = {
        "currency": "ILS",
        "categories": [
            {"id": "mains", "name": "Mains", "item_ids": ids[:5]},
            {"id": "more", "name": "More", "item_ids": ids[5:]},
        ],
        "items": items,
        "options": [],
    }
    return json.dumps(menu, ensure_ascii=False).encode()


def _photo(name: str) -> bytes:
    from PIL import Image, ImageDraw

    seed = sum(map(ord, name))
    img = Image.new("RGB", (240, 240), (120 + seed % 80, 90 + seed % 60, 60))
    draw = ImageDraw.Draw(img)
    draw.ellipse((50, 50, 190, 190), fill=(230, 220, 200))
    draw.ellipse((90, 90, 150, 150), fill=(150 + seed % 60, 70, 50))
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue()


class Handler(BaseHTTPRequestHandler):
    """Answers the routes listed in the module docstring."""

    def _send(self, body: bytes, ctype: str = "application/json") -> None:
        self.send_response(200)
        self.send_header("content-type", ctype)
        self.send_header("access-control-allow-origin", "*")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _missing(self) -> None:
        self.send_response(404)
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802 - http.server's naming
        path = self.path.split("?")[0]
        if path.startswith("/v4/venues/slug/") and path.endswith("/menu/data"):
            if path.split("/")[4] == "vitrina-lilinblum":
                fixture = FIXTURES / "wolt_vitrina_lilinblum_menu.json"
                return self._send(fixture.read_bytes())
            return self._send(_artboard_menu())
        if path == "/v1/pages/restaurants":
            fixture = FIXTURES / "wolt_pages_restaurants.json"
            return self._send(fixture.read_bytes())
        if path.startswith("/api/v1.0/Restaurants/"):
            fixture = FIXTURES / "tenbis_synthetic_menu.json"
            return self._send(fixture.read_bytes())
        if path.startswith("/img/"):
            return self._send(_photo(path), "image/png")
        return self._missing()

    def do_POST(self) -> None:  # noqa: N802 - http.server's naming
        self.rfile.read(int(self.headers.get("content-length", "0")))
        if self.path.split("?")[0] == "/v1/pages/search":
            fixture = FIXTURES / "wolt_pages_search.json"
            return self._send(fixture.read_bytes())
        return self._missing()


if __name__ == "__main__":
    print(f"stub upstream on http://127.0.0.1:{PORT}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
