"""Tests for ``app.keto.models`` and the D25 bodies in ``app.schemas`` (#321).

The samples below are written the way Dart's ``jsonEncode`` writes the
``toJson`` maps of ``lib/models/{menu,analysis,venue}.dart``: compact, every
key present, doubles with a fractional part (the Dart VM's ``5.0``), and
non-ASCII left unescaped. ``_dart_encode`` is that encoding in Python, so
"round-trips" here means the very bytes, not just equal values.
"""

import ast
import json
from pathlib import Path
from typing import Any

import pytest
from pydantic import BaseModel, ValidationError

from app.keto.models import (
    AnalysedDish,
    AnalysisOptionsSnapshot,
    Dish,
    DishOption,
    HiddenCarb,
    LlmEngine,
    Menu,
    MenuAnalysed,
    MenuCategory,
    RulesEngine,
    Venue,
    VenueRef,
    to_json,
)
from app.schemas import (
    ClassificationOptionsBody,
    ClassifyRequest,
    ClassifyResponse,
    ScannedMenuResponse,
    ScanRequest,
    TextMenuRequest,
    VenueMenuResponse,
    VenueSearchRequest,
    VenuesResponse,
    WebsiteMenuRequest,
    WebsiteMenuResponse,
)

_BACKEND = Path(__file__).resolve().parent.parent
_GOLDEN = _BACKEND / "tests" / "fixtures" / "golden"


def _dart_encode(value: Any) -> str:
    """``value`` as Dart's ``jsonEncode`` writes it: compact, UTF-8 as-is."""
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False)


def _round_trip(model: type[BaseModel], text: str) -> str:
    return _dart_encode(to_json(model.model_validate(json.loads(text))))


# --- Dart-shaped samples -------------------------------------------------------

_WOLT_MENU = (
    '{"venueRef":{"source":"wolt","platformId":"hamosad"},"currency":"ILS",'
    '"fetchedAt":"2026-09-25T10:15:30.123Z","categories":['
    '{"id":"c1","name":"Steaks","dishes":['
    '{"id":"d1","name":"Entrecôte 300g","description":"With potato purée",'
    '"price":118.0,"options":[{"name":"Choice of side",'
    '"values":["Potato purée","Green salad"]},'
    '{"name":"Doneness","values":[]}],'
    '"imageUrl":"https://imageproxy.wolt.com/menu/d1.jpg","page":null},'
    '{"id":"d2","name":"סלט ירוק","description":"","price":0.0,"options":[],'
    '"imageUrl":null,"page":null}]},'
    '{"id":"c2","name":"Drinks","dishes":[]}],'
    '"venueName":"HaMosad"}'
)

_SCANNED_MENU = (
    '{"venueRef":{"source":"scan","platformId":"9f3a5c0e1b2d4f60"},'
    '"currency":"ILS","fetchedAt":"2026-10-08T09:00:00.000",'
    '"categories":[{"id":"scan-0","name":"עיקריות","dishes":['
    '{"id":"scan-0-0","name":"שניצל","description":"עם צ\'יפס",'
    '"price":64.5,"options":[],"imageUrl":null,"page":1},'
    '{"id":"scan-0-1","name":"Caesar salad","description":"",'
    '"price":52.0,"options":[],"imageUrl":null,"page":2}]}],'
    '"venueName":null}'
)

_LLM_ANALYSIS = (
    '{"dishes":['
    '{"dishId":"d1","name":"Entrecôte 300g","verdict":"modifiable",'
    '"why":"The purée is starch.",'
    '"modification":"Replace the potato purée with a green salad.",'
    '"netCarbsEstimate":4.5,"hiddenCarbs":['
    '{"source":"house glaze","certainty":"likely",'
    '"waiterQuestion":"Is the glaze made with honey?"}]},'
    '{"dishId":"d2","name":"סלט ירוק","verdict":"orderAsIs",'
    '"why":"ירקות בלבד.","modification":null,"netCarbsEstimate":3.0,'
    '"hiddenCarbs":[]},'
    '{"dishId":"d3","name":"Spaghetti","verdict":"nonKeto",'
    '"why":"Pasta base.","modification":null,"netCarbsEstimate":null,'
    '"hiddenCarbs":[]}],'
    '"unclassified":["Chef\'s special"],'
    '"engine":{"kind":"llm","model":"gemini-3.5-flash"},'
    '"analysedAt":"2026-09-25T10:16:02.456789Z",'
    '"options":{"netCarbLimitGrams":6,"dietaryConstraints":["Dairy-free keto"]},'
    '"schemaVersion":1}'
)

_RULES_ANALYSIS = (
    '{"dishes":[{"dishId":"d1","name":"Entrecôte 300g","verdict":"orderAsIs",'
    '"why":"Protein, no carb trigger.","modification":null,'
    '"netCarbsEstimate":null,"hiddenCarbs":[]}],'
    '"unclassified":[],"engine":{"kind":"rules","reason":"consentWithheld"},'
    '"analysedAt":"2026-09-25T10:16:02.000Z","options":null,"schemaVersion":0}'
)

_FULL_VENUE = (
    '{"ref":{"source":"wolt","platformId":"hamosad"},"name":"HaMosad",'
    '"address":"Dizengoff 1","latitude":32.0853,"longitude":34.7818,'
    '"sourceUrl":"https://wolt.com/en/isr/tel-aviv/restaurant/hamosad",'
    '"cuisineTags":["steak","grill"],"isOnline":true,'
    '"imageUrl":"https://imageproxy.wolt.com/venue/hamosad.jpg",'
    '"shortDescription":"Grill house","platformRating":9.2,'
    '"estimateMinutes":35,"city":"Tel Aviv"}'
)

_MINIMAL_VENUE = (
    '{"ref":{"source":"tenbis","platformId":"12345"},"name":"בורגר",'
    '"address":null,"latitude":null,"longitude":null,"sourceUrl":null,'
    '"cuisineTags":[],"isOnline":null,"imageUrl":null,'
    '"shortDescription":null,"platformRating":null,"estimateMinutes":null,'
    '"city":null}'
)


@pytest.mark.parametrize(
    ("model", "text"),
    [
        (Menu, _WOLT_MENU),
        (Menu, _SCANNED_MENU),
        (MenuAnalysed, _LLM_ANALYSIS),
        (MenuAnalysed, _RULES_ANALYSIS),
        (Venue, _FULL_VENUE),
        (Venue, _MINIMAL_VENUE),
    ],
    ids=["wolt-menu", "scanned-menu", "llm", "rules", "venue", "minimal-venue"],
)
def test_dart_samples_round_trip_byte_for_byte(
    model: type[BaseModel], text: str
) -> None:
    assert _round_trip(model, text) == text


def test_models_read_the_samples_into_python_names() -> None:
    menu = Menu.model_validate(json.loads(_SCANNED_MENU))
    assert menu.venue_ref.cache_key == "scan/9f3a5c0e1b2d4f60"
    assert [dish.page for dish in menu.all_dishes()] == [1, 2]
    assert menu.venue_name is None

    analysis = MenuAnalysed.model_validate(json.loads(_LLM_ANALYSIS))
    assert isinstance(analysis.engine, LlmEngine)
    assert analysis.engine.model == "gemini-3.5-flash"
    assert analysis.dishes[0].hidden_carbs[0].certainty == "likely"
    assert analysis.options == AnalysisOptionsSnapshot(
        net_carb_limit_grams=6, dietary_constraints=["Dairy-free keto"]
    )

    rules = MenuAnalysed.model_validate(json.loads(_RULES_ANALYSIS))
    assert rules.engine == RulesEngine(reason="consentWithheld")


def test_models_built_by_python_name_write_the_dart_shape() -> None:
    dish = Dish(
        id="d1",
        name="Steak",
        price=90,
        options=[DishOption(name="Side", values=["Fries"])],
    )
    menu = Menu(
        venue_ref=VenueRef(source="website", platform_id="example.com/menu"),
        currency="ILS",
        fetched_at="2026-10-08T12:00:00.000Z",
        categories=[MenuCategory(id="c", name="Mains", dishes=[dish])],
    )
    assert _dart_encode(to_json(menu)) == (
        '{"venueRef":{"source":"website","platformId":"example.com/menu"},'
        '"currency":"ILS","fetchedAt":"2026-10-08T12:00:00.000Z",'
        '"categories":[{"id":"c","name":"Mains","dishes":[{"id":"d1",'
        '"name":"Steak","description":"","price":90.0,"options":'
        '[{"name":"Side","values":["Fries"]}],"imageUrl":null,"page":null}]}],'
        '"venueName":null}'
    )

    analysis = MenuAnalysed(
        dishes=[
            AnalysedDish(
                dish_id="d1",
                name="Steak",
                verdict="modifiable",
                why="Fries.",
                modification="No fries, salad instead.",
                hidden_carbs=[
                    HiddenCarb(
                        source="marinade", certainty="suspected", waiter_question="?"
                    )
                ],
            )
        ],
        unclassified=[],
        engine=RulesEngine(reason="offline"),
        analysed_at="2026-10-08T12:00:01.000Z",
        options=AnalysisOptionsSnapshot(net_carb_limit_grams=10),
        schema_version=1,
    )
    assert _dart_encode(to_json(analysis)) == (
        '{"dishes":[{"dishId":"d1","name":"Steak","verdict":"modifiable",'
        '"why":"Fries.","modification":"No fries, salad instead.",'
        '"netCarbsEstimate":null,"hiddenCarbs":[{"source":"marinade",'
        '"certainty":"suspected","waiterQuestion":"?"}]}],"unclassified":[],'
        '"engine":{"kind":"rules","reason":"offline"},'
        '"analysedAt":"2026-10-08T12:00:01.000Z","options":'
        '{"netCarbLimitGrams":10,"dietaryConstraints":[]},"schemaVersion":1}'
    )

    venue = Venue(ref=VenueRef(source="wolt", platform_id="x"), name="X")
    assert list(to_json(venue)) == [
        "ref",
        "name",
        "address",
        "latitude",
        "longitude",
        "sourceUrl",
        "cuisineTags",
        "isOnline",
        "imageUrl",
        "shortDescription",
        "platformRating",
        "estimateMinutes",
        "city",
    ]


# --- tolerant reads, as Dart's tryFrom ----------------------------------------


def _dish(**overrides: Any) -> dict[str, Any]:
    raw: dict[str, Any] = {
        "id": "d1",
        "name": "Steak",
        "description": "Grilled",
        "price": 10.0,
        "options": [],
        "imageUrl": None,
        "page": None,
    }
    raw.update(overrides)
    return raw


def _analysed(**overrides: Any) -> dict[str, Any]:
    raw: dict[str, Any] = {
        "dishId": "d1",
        "name": "Steak",
        "verdict": "orderAsIs",
        "why": "Protein.",
        "modification": None,
        "netCarbsEstimate": None,
        "hiddenCarbs": [],
    }
    raw.update(overrides)
    return raw


def _analysis(**overrides: Any) -> dict[str, Any]:
    raw: dict[str, Any] = {
        "dishes": [],
        "unclassified": [],
        "engine": {"kind": "llm", "model": "m"},
        "analysedAt": "2026-10-08T12:00:00.000Z",
        "options": None,
        "schemaVersion": 1,
    }
    raw.update(overrides)
    return raw


def test_an_integer_price_reads_as_a_double() -> None:
    assert to_json(Dish.model_validate(_dish(price=5)))["price"] == 5.0
    assert _dart_encode(to_json(Dish.model_validate(_dish(price=5)))).count(
        '"price":5.0'
    )


@pytest.mark.parametrize("value", [None, "", 7, ["x"]])
def test_a_missing_or_malformed_image_url_reads_as_null(value: object) -> None:
    assert Dish.model_validate(_dish(imageUrl=value)).image_url is None


@pytest.mark.parametrize("value", [None, 0, -1, "2", 2.0, True])
def test_a_missing_or_malformed_page_reads_as_null(value: object) -> None:
    assert Dish.model_validate(_dish(page=value)).page is None


def test_absent_optional_keys_read_as_their_defaults() -> None:
    raw = _dish()
    for key in ("description", "imageUrl", "page"):
        del raw[key]
    dish = Dish.model_validate(raw)
    assert (dish.description, dish.image_url, dish.page) == ("", None, None)
    assert Dish.model_validate(_dish(description=None)).description == ""

    menu = json.loads(_WOLT_MENU)
    del menu["venueName"]
    assert Menu.model_validate(menu).venue_name is None


def test_hidden_carbs_are_read_tolerantly() -> None:
    raw = _analysed()
    del raw["hiddenCarbs"]
    assert AnalysedDish.model_validate(raw).hidden_carbs == []
    assert AnalysedDish.model_validate(_analysed(hiddenCarbs=None)).hidden_carbs == []
    kept = {"source": "glaze", "certainty": "likely", "waiterQuestion": "Honey?"}
    mixed = [
        kept,
        {"source": " ", "certainty": "likely", "waiterQuestion": "Honey?"},
        {"source": "glaze", "certainty": "certain", "waiterQuestion": "Honey?"},
        "glaze",
        HiddenCarb.model_validate(kept),
    ]
    dish = AnalysedDish.model_validate(_analysed(hiddenCarbs=mixed))
    assert [h.source for h in dish.hidden_carbs] == ["glaze", "glaze"]


@pytest.mark.parametrize("value", [None, "1", 1.0, True])
def test_a_missing_or_non_int_schema_version_reads_as_zero(value: object) -> None:
    assert (
        MenuAnalysed.model_validate(_analysis(schemaVersion=value)).schema_version == 0
    )
    raw = _analysis()
    del raw["schemaVersion"]
    del raw["options"]
    analysis = MenuAnalysed.model_validate(raw)
    assert (analysis.schema_version, analysis.options) == (0, None)


def test_absent_dietary_constraints_and_cuisine_tags_read_as_empty() -> None:
    snapshot = AnalysisOptionsSnapshot.model_validate(
        {"netCarbLimitGrams": 6, "dietaryConstraints": None}
    )
    assert snapshot.dietary_constraints == []
    venue = Venue.model_validate(
        {"ref": {"source": "wolt", "platformId": "x"}, "name": "X", "cuisineTags": None}
    )
    assert venue.cuisine_tags == []
    assert Venue.model_validate(
        {"ref": {"source": "wolt", "platformId": "x"}, "name": "X", "latitude": 32}
    ).latitude == pytest.approx(32.0)


# --- rejections, as Dart's tryFrom returns null -------------------------------


@pytest.mark.parametrize(
    ("model", "raw"),
    [
        (Dish, _dish(id="")),
        (Dish, _dish(name="")),
        (Dish, _dish(price=-1.0)),
        (Dish, _dish(price="5")),
        (Dish, _dish(price=True)),
        (Dish, _dish(price=float("nan"))),
        (Dish, _dish(description=3)),
        (Dish, _dish(options=[{"name": "", "values": []}])),
        (Dish, _dish(options=[{"name": "Side", "values": [1]}])),
        (Dish, _dish(extra="unknown key")),
        (VenueRef, {"source": "deliveroo", "platformId": "x"}),
        (VenueRef, {"source": "wolt", "platformId": ""}),
        (Menu, {**json.loads(_WOLT_MENU), "fetchedAt": "yesterday"}),
        (Menu, {**json.loads(_WOLT_MENU), "currency": ""}),
        (Menu, {**json.loads(_WOLT_MENU), "venueName": 3}),
        (AnalysedDish, _analysed(verdict="green")),
        (AnalysedDish, _analysed(why="")),
        (AnalysedDish, _analysed(verdict="modifiable")),
        (AnalysedDish, _analysed(verdict="modifiable", modification="")),
        (AnalysedDish, _analysed(modification="Swap the side.")),
        (AnalysedDish, _analysed(netCarbsEstimate="4")),
        (MenuAnalysed, _analysis(engine={"kind": "gpt", "model": "m"})),
        (MenuAnalysed, _analysis(engine={"kind": "llm", "model": ""})),
        (MenuAnalysed, _analysis(engine={"kind": "rules", "reason": "unknown"})),
        (MenuAnalysed, _analysis(analysedAt="not a date")),
        (MenuAnalysed, _analysis(options={"netCarbLimitGrams": 6.0})),
        (MenuAnalysed, _analysis(options={"netCarbLimitGrams": True})),
        (MenuAnalysed, _analysis(unclassified=[1])),
        (Venue, {"ref": {"source": "wolt", "platformId": "x"}, "name": ""}),
        (Venue, {"name": "X"}),
        (Venue, {**json.loads(_FULL_VENUE), "latitude": "32.1"}),
        (Venue, {**json.loads(_FULL_VENUE), "estimateMinutes": 35.0}),
        (Venue, {**json.loads(_FULL_VENUE), "cuisineTags": "steak"}),
        (Venue, {**json.loads(_FULL_VENUE), "cuisineTags": [1]}),
        (Venue, {**json.loads(_FULL_VENUE), "isOnline": "yes"}),
        (Venue, {**json.loads(_FULL_VENUE), "city": 7}),
    ],
)
def test_a_shape_dart_rejects_is_rejected(
    model: type[BaseModel], raw: dict[str, Any]
) -> None:
    with pytest.raises(ValidationError):
        model.model_validate(raw)


def test_wire_models_are_immutable() -> None:
    ref = VenueRef(source="wolt", platform_id="x")
    with pytest.raises(ValidationError):
        ref.platform_id = "y"  # type: ignore[misc]


# --- the package stays pure ----------------------------------------------------

_FORBIDDEN_ROOTS = {"fastapi", "starlette", "httpx", "sqlalchemy", "app"}
_ALLOWED_APP_MODULES = ("app.keto",)


def test_the_keto_package_imports_no_framework() -> None:
    offenders: list[str] = []
    for path in sorted((_BACKEND / "app" / "keto").glob("*.py")):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            names: list[str] = []
            if isinstance(node, ast.Import):
                names = [alias.name for alias in node.names]
            elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
                names = [node.module]
            for name in names:
                if name.startswith(_ALLOWED_APP_MODULES):
                    continue
                if name.split(".")[0] in _FORBIDDEN_ROOTS:
                    offenders.append(f"{path.name}: {name}")
    assert offenders == []


# --- the golden corpus (#320), when it exists ----------------------------------

_MENU_KEYS = {"venueRef", "currency", "fetchedAt", "categories", "venueName"}
_ANALYSIS_KEYS = {
    "dishes",
    "unclassified",
    "engine",
    "analysedAt",
    "options",
    "schemaVersion",
}
_VENUE_KEYS = {
    "ref",
    "name",
    "address",
    "latitude",
    "longitude",
    "sourceUrl",
    "cuisineTags",
    "isOnline",
    "imageUrl",
    "shortDescription",
    "platformRating",
    "estimateMinutes",
    "city",
}
_NAMED_GOLDEN_FILES = ("fingerprint.json", "heuristic.json", "parser.json")
"""The files #321 names; any other golden file is replayed too when present."""


def _golden_files() -> list[str]:
    present = {path.name for path in _GOLDEN.glob("*.json")}
    return sorted(present | set(_NAMED_GOLDEN_FILES))


def _wire_objects(node: Any) -> list[tuple[type[BaseModel], dict[str, Any]]]:
    """Every Dart ``Menu``/``MenuAnalysed``/``Venue`` JSON inside ``node``,
    recognised by having exactly that model's key set."""
    found: list[tuple[type[BaseModel], dict[str, Any]]] = []
    if isinstance(node, dict):
        keys = set(node)
        if keys == _MENU_KEYS:
            return [(Menu, node)]
        if keys == _ANALYSIS_KEYS:
            return [(MenuAnalysed, node)]
        if keys == _VENUE_KEYS:
            return [(Venue, node)]
        for value in node.values():
            found.extend(_wire_objects(value))
    elif isinstance(node, list):
        for value in node:
            found.extend(_wire_objects(value))
    return found


def _has_lone_surrogate(node: Any) -> bool:
    """Whether any string in ``node`` holds an unpaired UTF-16 surrogate."""
    if isinstance(node, str):
        return any(0xD800 <= ord(char) <= 0xDFFF for char in node)
    if isinstance(node, dict):
        return any(_has_lone_surrogate(value) for value in node.values())
    if isinstance(node, list):
        return any(_has_lone_surrogate(value) for value in node)
    return False


def _dart_reader_rejects(model: type[BaseModel], raw: dict[str, Any]) -> bool:
    """Whether Dart's own ``tryFrom`` refuses ``raw``: a corpus case built
    with the Dart constructor (which checks nothing) around an empty dish
    id or name, e.g. ``dish_kind.json``'s ``empty-1``."""
    if model is not Menu:
        return False
    return any(
        not dish.get("id") or not dish.get("name")
        for category in raw.get("categories", [])
        for dish in category.get("dishes", [])
    )


@pytest.mark.parametrize("name", _golden_files())
def test_every_golden_menu_analysis_and_venue_round_trips(name: str) -> None:
    """Every wire object in the golden corpus reads and writes back equal.

    The corpus is written with sorted keys (#320), so this compares sorted
    dumps: the same keys, nulls and values, float spelling included. Key
    order is pinned by the Dart-shaped samples above instead.

    Two kinds of object are refused rather than round-tripped, each pinned
    by ``test_what_the_wire_refuses_from_the_corpus`` below: one Dart's own
    ``tryFrom`` refuses too, and one holding a lone UTF-16 surrogate, which
    a Dart string can hold (a 300-unit cap that splits an emoji) but a
    pydantic string cannot.
    """
    path = _GOLDEN / name
    if not path.exists():
        pytest.skip(f"{name} is not exported yet (golden corpus, #320)")
    objects = _wire_objects(json.loads(path.read_text(encoding="utf-8")))
    if not objects:
        pytest.skip(f"{name} holds no Menu, MenuAnalysed or Venue JSON")
    for model, raw in objects:
        if _dart_reader_rejects(model, raw) or _has_lone_surrogate(raw):
            with pytest.raises(ValidationError):
                model.model_validate(raw)
            continue
        written = to_json(model.model_validate(raw))
        assert json.dumps(written, sort_keys=True) == json.dumps(raw, sort_keys=True)


def test_what_the_wire_refuses_from_the_corpus() -> None:
    # An empty dish name: Dart's Dish.tryFrom returns null for it too.
    menu = json.loads(_WOLT_MENU)
    menu["categories"][0]["dishes"][0]["name"] = ""
    assert _dart_reader_rejects(Menu, menu)
    with pytest.raises(ValidationError):
        Menu.model_validate(menu)
    # A lone surrogate (half of an emoji cut at a UTF-16 cap): Dart reads
    # it; pydantic-core cannot hold it, so the port must never produce one.
    analysis = json.loads(_RULES_ANALYSIS)
    analysis["dishes"][0]["why"] = "Steak \ud83d"
    assert _has_lone_surrogate(analysis)
    with pytest.raises(ValidationError):
        MenuAnalysed.model_validate(analysis)


# --- the D25 request and response bodies --------------------------------------

_OPTIONS = {"netCarbLimitGrams": 6, "dietaryConstraints": []}
_PNG = "iVBORw0KGgo="  # the 8-byte PNG signature


def test_classification_options_bounds() -> None:
    body = ClassificationOptionsBody.model_validate(
        {"netCarbLimitGrams": 50, "dietaryConstraints": ["a", "b", "c"]}
    )
    assert body.snapshot() == AnalysisOptionsSnapshot(
        net_carb_limit_grams=50, dietary_constraints=["a", "b", "c"]
    )
    assert (
        ClassificationOptionsBody.model_validate(
            {"netCarbLimitGrams": 1}
        ).dietary_constraints
        == []
    )
    for bad in (
        {"netCarbLimitGrams": 0},
        {"netCarbLimitGrams": 51},
        {"netCarbLimitGrams": 6.0},
        {"netCarbLimitGrams": "6"},
        {"netCarbLimitGrams": 6, "dietaryConstraints": ["a", "b", "c", "d"]},
        {"netCarbLimitGrams": 6, "dietaryConstraints": [""]},
        {"netCarbLimitGrams": 6, "dietaryConstraints": ["x" * 1001]},
        {"net_carb_limit_grams": 6, "consent": True},
    ):
        with pytest.raises(ValidationError):
            ClassificationOptionsBody.model_validate(bad)


def test_classify_bodies_carry_the_dart_shapes() -> None:
    request = ClassifyRequest.model_validate(
        {"menu": json.loads(_WOLT_MENU), "options": _OPTIONS}
    )
    assert request.menu.venue_name == "HaMosad"
    response = ClassifyResponse(
        analysis=MenuAnalysed.model_validate(json.loads(_LLM_ANALYSIS))
    )
    assert _dart_encode(to_json(response)) == '{"analysis":' + _LLM_ANALYSIS + "}"


def test_venue_menu_response_shape() -> None:
    response = VenueMenuResponse.model_validate(
        {
            "menu": json.loads(_WOLT_MENU),
            "analysis": None,
            "fromCache": True,
            "fetchedAt": "2026-09-25T10:15:30.123Z",
        }
    )
    assert list(to_json(response)) == ["menu", "analysis", "fromCache", "fetchedAt"]
    assert to_json(response)["analysis"] is None
    with pytest.raises(ValidationError):
        VenueMenuResponse.model_validate({**to_json(response), "fetchedAt": "soon"})


def test_scan_request_validates_its_pages() -> None:
    page = {"mimeType": "image/png", "data": _PNG}
    request = ScanRequest.model_validate({"pages": [page], "options": _OPTIONS})
    assert request.pages[0].decoded_size == 8
    assert request.page_bound_violation(max_pages=6, max_bytes=8) is None
    assert request.page_bound_violation(max_pages=6, max_bytes=7) == (
        "page 0 is over 7 bytes once decoded"
    )
    two = ScanRequest.model_validate({"pages": [page, page], "options": _OPTIONS})
    assert two.page_bound_violation(max_pages=1, max_bytes=8) == (
        "at most 1 pages per request"
    )
    for bad_pages in (
        [],
        [page] * 7,
        [{"mimeType": "image/gif", "data": _PNG}],
        [{"mimeType": "image/png", "data": "not base64!"}],
        [{"mime_type": "image/png", "data": _PNG, "extra": 1}],
    ):
        with pytest.raises(ValidationError):
            ScanRequest.model_validate({"pages": bad_pages, "options": _OPTIONS})


def test_scanned_and_website_responses() -> None:
    menu = json.loads(_SCANNED_MENU)
    analysis = json.loads(_RULES_ANALYSIS)
    scanned = ScannedMenuResponse.model_validate({"menu": menu, "analysis": analysis})
    assert _dart_encode(to_json(scanned)) == (
        '{"menu":' + _SCANNED_MENU + ',"analysis":' + _RULES_ANALYSIS + "}"
    )
    with pytest.raises(ValidationError):
        ScannedMenuResponse.model_validate({"menu": menu, "analysis": None})
    website = WebsiteMenuResponse.model_validate({"menu": menu, "analysis": None})
    assert to_json(website)["analysis"] is None


def test_text_and_website_requests_are_bounded() -> None:
    assert TextMenuRequest.model_validate({"text": "Steak 90", "options": _OPTIONS})
    for text in ("", "x" * 100_001):
        with pytest.raises(ValidationError):
            TextMenuRequest.model_validate({"text": text, "options": _OPTIONS})
    assert WebsiteMenuRequest.model_validate(
        {"url": "https://example.com", "options": _OPTIONS}
    ).url == ("https://example.com")
    with pytest.raises(ValidationError):
        WebsiteMenuRequest.model_validate({"url": "", "options": _OPTIONS})


def test_venue_search_request() -> None:
    request = VenueSearchRequest.model_validate({"query": "  sushi  "})
    assert (request.query, request.lang, request.lat, request.lon) == (
        "sushi",
        "en",
        None,
        None,
    )
    located = VenueSearchRequest.model_validate(
        {"query": "sushi", "lang": "he", "lat": 32, "lon": 34.78}
    )
    assert located.lat == pytest.approx(32.0)
    for bad in (
        {"query": "   "},
        {"query": "x" * 101},
        {"query": "sushi", "lang": "fr"},
        {"query": "sushi", "lat": 32.0},
        {"query": "sushi", "lat": 91.0, "lon": 34.0},
        {"q": "sushi"},
    ):
        with pytest.raises(ValidationError):
            VenueSearchRequest.model_validate(bad)


def test_venues_response_writes_each_venue_in_the_dart_shape() -> None:
    response = VenuesResponse.model_validate(
        {"venues": [json.loads(_FULL_VENUE), json.loads(_MINIMAL_VENUE)]}
    )
    assert _dart_encode(to_json(response)) == (
        '{"venues":[' + _FULL_VENUE + "," + _MINIMAL_VENUE + "]}"
    )


def test_hidden_carb_blank_check_follows_dart_trim() -> None:
    """A source Dart keeps (U+001C is not whitespace to Dart) reads back."""
    carb = HiddenCarb.model_validate(
        {"source": "\x1c", "certainty": "likely", "waiterQuestion": "Is it?"}
    )
    assert carb.source == "\x1c"
