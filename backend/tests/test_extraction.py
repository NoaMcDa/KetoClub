"""The profile-independent ingredient extraction on the server (Banto; ALG-03,
D26 C1-C2).

``restrictionsRequested`` is the one Banto key an options body accepts: it
adds the extraction section to the prompt, ``ingredients`` to the schema and
to the parsed dishes, and a suffix to the analysis-cache key, and it changes
nothing when false. The profile itself is never accepted (C1). Gemini and
Wolt are respx routes; nothing leaves the sandbox.
"""

import base64
import hashlib
import json
from collections.abc import Iterator
from typing import Any

import httpx
import pytest
import respx
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.keto import prompt
from app.keto.fingerprint import fingerprint_hex
from app.keto.models import AnalysisOptionsSnapshot, Menu, to_json
from app.keto.parser import SCHEMA_VERSION
from app.schemas import ClassificationOptionsBody
from app.services import analysis_cache
from tests.analysis_support import (
    GEMINI_URL,
    HEADERS,
    client,
    gemini_answer,
    golden,
    golden_entry,
    settings,
)

_KETO = {"netCarbLimitGrams": 6, "dietaryConstraints": []}
_EXTRACT = {**_KETO, "restrictionsRequested": True}
_WOLT_URL = (
    "https://consumer-api.wolt.com/consumer-api/consumer-assortment/v1/venues/slug/"
    "hamosad/assortment"
)


@pytest.fixture
def upstream() -> Iterator[respx.MockRouter]:
    with respx.mock(assert_all_called=False) as router:
        yield router


@pytest.fixture
def app_client() -> Iterator[TestClient]:
    with client(settings()) as test_client:
        yield test_client


def _extract_entry(name: str) -> dict[str, Any]:
    entry: dict[str, Any] = next(
        e for e in golden("parser.json")["extractText"] if e["name"] == name
    )
    return entry


def _sent(route: respx.Route) -> tuple[str, dict[str, Any]]:
    """The system prompt and response schema of the last Gemini request."""
    body = json.loads(route.calls.last.request.content)
    system = body["system_instruction"]["parts"][0]["text"]
    schema: dict[str, Any] = body["generationConfig"]["responseSchema"]
    return system, schema


def _dish_properties(schema: dict[str, Any]) -> dict[str, Any]:
    properties: dict[str, Any] = schema["properties"]["dishes"]["items"]["properties"]
    return properties


# --- the options body --------------------------------------------------------


@pytest.mark.parametrize("key", ["restrictionsRequested", "restrictions_requested"])
def test_the_body_accepts_the_flag_by_either_name(key: str) -> None:
    body = ClassificationOptionsBody.model_validate({"netCarbLimitGrams": 6, key: True})
    assert body.restrictions_requested is True
    snapshot = body.snapshot()
    assert snapshot.restrictions_requested is True
    assert to_json(snapshot) == _EXTRACT


def test_the_flag_defaults_to_false_and_a_keto_snapshot_is_unchanged() -> None:
    body = ClassificationOptionsBody.model_validate(_KETO)
    assert body.restrictions_requested is False
    assert to_json(body.snapshot()) == _KETO


@pytest.mark.parametrize("value", ["true", 1, None, ["sesame"]])
def test_the_flag_is_a_strict_bool(value: object) -> None:
    with pytest.raises(ValidationError):
        ClassificationOptionsBody.model_validate(
            {**_KETO, "restrictionsRequested": value}
        )


@pytest.mark.parametrize(
    "key", ["profile", "dietaryProfile", "restrictions", "restrictionIds"]
)
def test_a_profile_in_the_options_is_refused(key: str) -> None:
    with pytest.raises(ValidationError):
        ClassificationOptionsBody.model_validate({**_EXTRACT, key: ["sesame"]})


# --- the analysis-cache key --------------------------------------------------


def _menu() -> Menu:
    entry = _extract_entry("hand_extract_support_cap")
    return Menu.model_validate(entry["sourceMenu"])


def test_a_keto_key_is_the_five_part_key_it_always_was() -> None:
    menu = _menu()
    options = AnalysisOptionsSnapshot(net_carb_limit_grams=6, dietary_constraints=[])
    material = "|".join([fingerprint_hex(menu), "m", str(SCHEMA_VERSION), "6", "[]"])

    key = analysis_cache.cache_key(
        menu, model="m", schema_version=SCHEMA_VERSION, options=options
    )

    assert key == hashlib.sha256(material.encode("utf-8")).hexdigest()


def test_an_extracting_key_adds_a_restrictions_part() -> None:
    menu = _menu()
    options = AnalysisOptionsSnapshot(
        net_carb_limit_grams=6, dietary_constraints=[], restrictions_requested=True
    )
    material = "|".join(
        [fingerprint_hex(menu), "m", str(SCHEMA_VERSION), "6", "[]", "restrictions"]
    )

    key = analysis_cache.cache_key(
        menu, model="m", schema_version=SCHEMA_VERSION, options=options
    )

    assert key == hashlib.sha256(material.encode("utf-8")).hexdigest()


# --- POST /v1/classify -------------------------------------------------------


def _classify(test_client: TestClient, menu: Any, options: Any) -> httpx.Response:
    return test_client.post(
        "/v1/classify",
        content=json.dumps({"menu": menu, "options": options}).encode(),
        headers={"Content-Type": "application/json", **HEADERS},
    )


def test_classify_with_the_flag_extracts_as_the_golden_does(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    entry = _extract_entry("hand_extract_support_cap")
    route = upstream.post(GEMINI_URL).respond(200, json=gemini_answer(entry["reply"]))

    response = _classify(app_client, entry["sourceMenu"], _EXTRACT)

    assert response.status_code == 200
    analysis = response.json()["analysis"]
    assert analysis["options"] == _EXTRACT
    assert analysis["dishes"] == entry["result"]["analysed"]["dishes"]
    assert any(dish.get("ingredients") for dish in analysis["dishes"])
    system, schema = _sent(route)
    assert system.endswith(prompt.EXTRACTION_SECTION)
    assert "ingredients" in _dish_properties(schema)


def test_classify_without_the_flag_neither_asks_nor_reads(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    entry = _extract_entry("hand_extract_support_cap")
    route = upstream.post(GEMINI_URL).respond(200, json=gemini_answer(entry["reply"]))

    response = _classify(app_client, entry["sourceMenu"], _KETO)

    assert response.status_code == 200
    analysis = response.json()["analysis"]
    assert analysis["options"] == _KETO
    assert all("ingredients" not in dish for dish in analysis["dishes"])
    system, schema = _sent(route)
    assert system == prompt.system_prompt()
    assert "ingredients" not in _dish_properties(schema)


def test_a_keto_and_an_extracting_analysis_are_two_cache_entries(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    entry = _extract_entry("hand_extract_support_cap")
    route = upstream.post(GEMINI_URL).respond(200, json=gemini_answer(entry["reply"]))

    keto = _classify(app_client, entry["sourceMenu"], _KETO)
    extracting = _classify(app_client, entry["sourceMenu"], _EXTRACT)
    again = _classify(app_client, entry["sourceMenu"], _EXTRACT)

    assert keto.headers["X-KetoClub-Cache"] == "miss"
    assert extracting.headers["X-KetoClub-Cache"] == "miss"
    assert again.headers["X-KetoClub-Cache"] == "hit"
    assert again.json() == extracting.json()
    assert route.call_count == 2


def test_classify_refuses_a_profile_in_the_options(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    route = upstream.post(GEMINI_URL).respond(500)
    entry = _extract_entry("hand_extract_support_cap")

    response = _classify(
        app_client, entry["sourceMenu"], {**_EXTRACT, "profile": [{"id": "sesame"}]}
    )

    assert response.status_code == 422
    assert "sesame" not in response.text
    assert not route.called


# --- GET /v1/venue-menus -----------------------------------------------------


@pytest.mark.parametrize(("flag", "extracts"), [(None, False), ("true", True)])
def test_the_venue_route_takes_the_flag_as_a_query_parameter(
    app_client: TestClient,
    upstream: respx.MockRouter,
    flag: str | None,
    extracts: bool,
) -> None:
    wolt = golden_entry("wolt_menu.json", "synthetic_options_and_labels")
    upstream.get(_WOLT_URL).respond(200, json=wolt["raw"])
    route = upstream.post(GEMINI_URL).respond(200, json=gemini_answer('{"dishes": []}'))
    params = [("classify", "true"), ("netCarbLimitGrams", "6")]
    if flag is not None:
        params.append(("restrictionsRequested", flag))

    response = app_client.get(
        "/v1/venue-menus/wolt/hamosad", params=params, headers=HEADERS
    )

    assert response.status_code == 200
    options = response.json()["analysis"]["options"]
    assert options == (_EXTRACT if extracts else _KETO)
    system, schema = _sent(route)
    assert system.endswith(prompt.EXTRACTION_SECTION) is extracts
    assert ("ingredients" in _dish_properties(schema)) is extracts


# --- POST /v1/scan -----------------------------------------------------------


def test_scan_with_the_flag_asks_for_descriptions_and_reads_them(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    entry = next(
        e
        for e in golden("parser.json")["extractScanned"]
        if e["name"] == "hand_extract_scanned_descriptions"
    )
    route = upstream.post(GEMINI_URL).respond(200, json=gemini_answer(entry["reply"]))
    page = base64.b64encode(b"\xff\xd8\xff\xe0 a page").decode()

    response = app_client.post(
        "/v1/scan",
        json={"pages": [{"mimeType": "image/jpeg", "data": page}], "options": _EXTRACT},
        headers=HEADERS,
    )

    assert response.status_code == 200
    body = response.json()
    expected = entry["result"]
    assert [d["description"] for d in body["menu"]["categories"][0]["dishes"]] == [
        d["description"] for d in expected["menu"]["categories"][0]["dishes"]
    ]
    assert body["analysis"]["dishes"] == expected["analysis"]["dishes"]
    assert body["analysis"]["options"] == _EXTRACT
    system, schema = _sent(route)
    assert system.endswith(prompt.VISION_DESCRIPTION_SECTION)
    assert {"ingredients", "description"} <= set(_dish_properties(schema))
