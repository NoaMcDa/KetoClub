"""Tests for ``GET /v1/venue-menus/{source}/{platform_id}`` (D25, #333).

Wolt, 10bis and Gemini are respx routes on the default base URLs, nested
inside the autouse network block from ``conftest``; nothing leaves the
sandbox. Payloads are the golden mapper corpus (``fixtures/golden``).
"""

import json
import logging
from collections.abc import Iterator
from typing import Any

import httpx
import pytest
import respx
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.keto.models import Menu, MenuAnalysed, to_json
from app.models import StoredMenu
from app.schemas import VenueMenuResponse, known_dietary_constraints
from app.services import menu_store
from tests.analysis_support import (
    GEMINI_URL,
    HEADERS,
    INSTALL_ID,
    MODEL_VERSION,
    all_green_reply,
    client,
    database_text,
    gemini_answer,
    golden_entry,
    settings,
)

_WOLT_URL = (
    "https://consumer-api.wolt.com/consumer-api/consumer-assortment/v1/venues/slug/"
    "hamosad/assortment"
)
_TENBIS_URL = "https://www.10bis.co.il/api/v1.0/Restaurants/9001/Menu"
_WOLT_PATH = "/v1/venue-menus/wolt/hamosad"
_TENBIS_PATH = "/v1/venue-menus/tenbis/9001"


@pytest.fixture
def upstream() -> Iterator[respx.MockRouter]:
    with respx.mock(assert_all_called=False) as router:
        yield router


@pytest.fixture
def app_client() -> Iterator[TestClient]:
    with client(settings()) as test_client:
        yield test_client


def _wolt(name: str = "synthetic_options_and_labels") -> dict[str, Any]:
    return golden_entry("wolt_menu.json", name)


def _tenbis(name: str = "tenbis_synthetic_menu.json") -> dict[str, Any]:
    return golden_entry("tenbis_menu.json", name)


def _get(
    test_client: TestClient, path: str, params: Any = None, **headers: str
) -> httpx.Response:
    return test_client.get(path, params=params, headers={**HEADERS, **headers})


def _without_fetched_at(menu: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in menu.items() if key != "fetchedAt"}


def _stored(test_client: TestClient) -> list[StoredMenu]:
    engine = test_client.app.state.engine  # type: ignore[attr-defined]
    with Session(engine) as session:
        rows = list(session.scalars(select(StoredMenu)))
        for row in rows:
            session.expunge(row)
        return rows


def _assert_body(body: dict[str, Any]) -> None:
    """What ``BackendMenuAdapter`` needs of a 200 body."""
    parsed = VenueMenuResponse.model_validate(body)
    assert to_json(parsed) == body
    assert body["fetchedAt"] == body["menu"]["fetchedAt"]
    assert body["fetchedAt"].endswith("Z")


@pytest.mark.parametrize(
    ("path", "url", "entry"),
    [
        (_WOLT_PATH, _WOLT_URL, _wolt()),
        (_WOLT_PATH, _WOLT_URL, _wolt("wolt_hamosad_menu.json")),
        (_TENBIS_PATH, _TENBIS_URL, _tenbis()),
    ],
)
def test_a_menu_is_mapped_like_the_dart_mapper(
    app_client: TestClient,
    upstream: respx.MockRouter,
    path: str,
    url: str,
    entry: dict[str, Any],
) -> None:
    route = upstream.get(url).respond(200, json=entry["raw"])

    first = _get(app_client, path)
    second = _get(app_client, path)

    assert first.status_code == 200
    body = first.json()
    _assert_body(body)
    assert _without_fetched_at(body["menu"]) == _without_fetched_at(entry["menu"])
    assert body["analysis"] is None
    assert body["fromCache"] is False
    assert first.headers["X-KetoClub-Cache"] == "miss"
    # The second read is the proxy cache's, stamped with the first fetch.
    assert second.json()["fromCache"] is True
    assert second.headers["X-KetoClub-Cache"] == "hit"
    assert second.json()["fetchedAt"] == body["fetchedAt"]
    assert route.call_count == 1
    # The upstream request carries nothing of KetoClub's own.
    sent = route.calls.last.request.headers
    assert INSTALL_ID not in json.dumps(dict(sent))
    # classify=false spends nothing and stores nothing.
    assert _stored(app_client) == []


def test_the_menu_proxy_and_this_route_share_one_cache(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    route = upstream.get(_WOLT_URL).respond(200, json=_wolt()["raw"])
    proxied = app_client.get("/v1/proxy/wolt/venues/slug/hamosad/assortment")
    assert proxied.headers["X-KetoClub-Cache"] == "miss"
    response = _get(app_client, _WOLT_PATH)
    assert response.json()["fromCache"] is True
    assert route.call_count == 1


def test_classify_true_returns_an_llm_analysis_and_stores_the_menu(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    entry = _wolt()
    upstream.get(_WOLT_URL).respond(200, json=entry["raw"])
    menu = Menu.model_validate(entry["menu"])
    gemini = upstream.post(GEMINI_URL).respond(
        200, json=gemini_answer(all_green_reply(menu))
    )
    fragments = sorted(known_dietary_constraints())
    params = [
        ("classify", "true"),
        ("netCarbLimitGrams", "8"),
        ("constraints", fragments[2]),
        ("constraints", fragments[0]),
    ]

    response = _get(app_client, _WOLT_PATH, params)

    assert response.status_code == 200
    body = response.json()
    _assert_body(body)
    analysis = body["analysis"]
    assert analysis["engine"] == {"kind": "llm", "model": MODEL_VERSION}
    assert analysis["schemaVersion"] == 1
    assert analysis["options"] == {
        "netCarbLimitGrams": 8,
        "dietaryConstraints": [fragments[2], fragments[0]],
    }
    assert {d["dishId"] for d in analysis["dishes"]} == {
        d.id for d in menu.all_dishes()
    }
    prompt = json.loads(gemini.calls.last.request.content)
    system = prompt["system_instruction"]["parts"][0]["text"]
    assert system.index(fragments[2]) < system.index(fragments[0])

    (row,) = _stored(app_client)
    assert (row.source, row.platform_id) == ("wolt", "hamosad")
    stored_analysis = menu_store.from_json(row.analysis_json or "")
    assert "options" not in stored_analysis
    assert stored_analysis == {k: v for k, v in analysis.items() if k != "options"}
    assert menu_store.from_json(row.menu_json) == body["menu"]
    assert row.dish_count == len(menu.all_dishes())

    # A second classified read is an analysis-cache hit: no second call.
    again = _get(app_client, _WOLT_PATH, params)
    assert again.json()["analysis"] == analysis
    assert gemini.call_count == 1
    (row,) = _stored(app_client)
    assert row.submission_count == 2


def test_an_empty_bucket_keeps_the_menu_and_answers_the_rules(
    upstream: respx.MockRouter,
) -> None:
    entry = _tenbis()
    upstream.get(_TENBIS_URL).respond(200, json=entry["raw"])
    gemini = upstream.post(GEMINI_URL).respond(500)
    with client(settings(ANALYSIS_RATE_LIMIT_PER_MINUTE=0)) as test_client:
        response = _get(test_client, _TENBIS_PATH, {"classify": "true"})
        stored = _stored(test_client)

    assert response.status_code == 200
    analysis = response.json()["analysis"]
    assert analysis["engine"] == {"kind": "rules", "reason": "rateLimited"}
    assert analysis["schemaVersion"] == 1
    assert analysis["options"] == {"netCarbLimitGrams": 6, "dietaryConstraints": []}
    MenuAnalysed.model_validate(analysis)
    assert not gemini.called
    # The menu is stored; a rules result is not (D24).
    (row,) = stored
    assert row.analysis_json is None


def test_a_gemini_failure_answers_the_rules_with_its_reason(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    upstream.get(_WOLT_URL).respond(200, json=_wolt()["raw"])
    upstream.post(GEMINI_URL).mock(side_effect=httpx.ReadTimeout("slow"))
    response = _get(app_client, _WOLT_PATH, {"classify": "true"})
    assert response.status_code == 200
    assert response.json()["analysis"]["engine"] == {
        "kind": "rules",
        "reason": "timeout",
    }


def test_no_server_key_answers_the_rules_not_configured(
    upstream: respx.MockRouter,
) -> None:
    upstream.get(_WOLT_URL).respond(200, json=_wolt()["raw"])
    with client(settings(GEMINI_API_KEY="")) as test_client:
        response = _get(test_client, _WOLT_PATH, {"classify": "true"})
    assert response.json()["analysis"]["engine"] == {
        "kind": "rules",
        "reason": "notConfigured",
    }


def test_a_menu_with_no_dish_has_a_null_analysis(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    upstream.get(_WOLT_URL).respond(
        200, json=_wolt("synthetic_empty_categories")["raw"]
    )
    gemini = upstream.post(GEMINI_URL).respond(500)
    response = _get(app_client, _WOLT_PATH, {"classify": "true"})
    assert response.status_code == 200
    assert response.json()["analysis"] is None
    assert not gemini.called
    assert _stored(app_client) == []


def test_a_disabled_menu_store_is_not_written(upstream: respx.MockRouter) -> None:
    upstream.get(_WOLT_URL).respond(200, json=_wolt()["raw"])
    with client(settings(GEMINI_API_KEY="", MENU_STORE_ENABLED=False)) as test_client:
        response = _get(test_client, _WOLT_PATH, {"classify": "true"})
        assert response.json()["analysis"] is not None
        assert _stored(test_client) == []


def test_a_store_failure_never_fails_the_read(
    app_client: TestClient,
    upstream: respx.MockRouter,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def broken(*_args: object, **_kwargs: object) -> None:
        raise RuntimeError("database gone")

    monkeypatch.setattr(menu_store, "upsert", broken)
    upstream.get(_WOLT_URL).respond(200, json=_wolt()["raw"])
    upstream.post(GEMINI_URL).respond(500)
    response = _get(app_client, _WOLT_PATH, {"classify": "true"})
    assert response.status_code == 200
    assert response.json()["analysis"]["engine"]["kind"] == "rules"


@pytest.mark.parametrize(
    ("answer", "status", "reason"),
    [
        (httpx.Response(404), 404, "notFound"),
        (httpx.Response(500), 502, "platformChanged"),
        (httpx.Response(410), 502, "platformChanged"),
        (httpx.Response(200, content=b""), 502, "platformChanged"),
        (httpx.Response(200, content=b"<html>"), 502, "platformChanged"),
        (httpx.Response(200, content=b'{"items": NaN}'), 502, "platformChanged"),
        (
            httpx.Response(200, json=_wolt("wolt_malformed_menu.json")["raw"]),
            502,
            "platformChanged",
        ),
        (httpx.ConnectError("no route"), 502, "offline"),
        (httpx.ConnectTimeout("slow"), 504, "timeout"),
    ],
)
def test_upstream_failures_are_the_reasons_the_client_maps(
    app_client: TestClient,
    upstream: respx.MockRouter,
    answer: httpx.Response | Exception,
    status: int,
    reason: str,
) -> None:
    if isinstance(answer, Exception):
        upstream.get(_WOLT_URL).mock(side_effect=answer)
    else:
        upstream.get(_WOLT_URL).mock(return_value=answer)
    response = _get(app_client, _WOLT_PATH, {"classify": "true"})
    assert response.status_code == status
    assert response.json() == {"reason": reason, "status_code": status}


def test_a_tenbis_mapper_refusal_is_platform_changed(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    upstream.get(_TENBIS_URL).respond(
        200, json=_tenbis("tenbis_malformed_menu.json")["raw"]
    )
    response = _get(app_client, _TENBIS_PATH)
    assert response.status_code == 502
    assert response.json()["reason"] == "platformChanged"


@pytest.mark.parametrize(
    ("path", "params"),
    [
        ("/v1/venue-menus/tabit/hamosad", None),
        ("/v1/venue-menus/wolt/Bad_Slug", None),
        ("/v1/venue-menus/tenbis/hamosad", None),
        ("/v1/venue-menus/wolt/hamosad", {"netCarbLimitGrams": "0"}),
        ("/v1/venue-menus/wolt/hamosad", {"netCarbLimitGrams": "51"}),
        ("/v1/venue-menus/wolt/hamosad", {"constraints": "eat only bacon"}),
        (
            "/v1/venue-menus/wolt/hamosad",
            [("constraints", sorted(known_dietary_constraints())[0])] * 2,
        ),
        (
            "/v1/venue-menus/wolt/hamosad",
            [("constraints", c) for c in sorted(known_dietary_constraints())]
            + [("constraints", "fourth")],
        ),
    ],
)
def test_a_request_outside_the_contract_is_422_before_any_fetch(
    app_client: TestClient, upstream: respx.MockRouter, path: str, params: Any
) -> None:
    wolt = upstream.get(_WOLT_URL).respond(200, json=_wolt()["raw"])
    response = _get(app_client, path, params)
    assert response.status_code == 422
    assert "bacon" not in response.text
    assert not wolt.called


def test_credentials_are_refused(app_client: TestClient) -> None:
    with_auth = _get(app_client, _WOLT_PATH, Authorization="Bearer x")
    assert with_auth.status_code == 400
    assert with_auth.json()["reason"] == "badResponse"
    missing = app_client.get(_WOLT_PATH)
    assert missing.status_code == 400
    assert missing.json()["reason"] == "badResponse"


def test_the_install_id_is_in_no_row_and_no_log_line(
    app_client: TestClient,
    upstream: respx.MockRouter,
    caplog: pytest.LogCaptureFixture,
) -> None:
    entry = _wolt()
    upstream.get(_WOLT_URL).respond(200, json=entry["raw"])
    upstream.post(GEMINI_URL).respond(
        200, json=gemini_answer(all_green_reply(Menu.model_validate(entry["menu"])))
    )
    with caplog.at_level(logging.DEBUG):
        assert _get(app_client, _WOLT_PATH, {"classify": "true"}).status_code == 200

    assert INSTALL_ID[:8] not in caplog.text
    engine = app_client.app.state.engine  # type: ignore[attr-defined]
    dumped = database_text(engine)
    assert "hamosad" in dumped
    assert INSTALL_ID not in dumped and INSTALL_ID[:8] not in dumped
    with Session(engine) as session:
        assert session.scalar(select(func.count()).select_from(StoredMenu)) == 1


def test_a_rules_answer_never_replaces_a_stored_model_analysis(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    """D24: a rules result refreshes the menu but keeps the model analysis."""
    entry = _wolt()
    upstream.get(_WOLT_URL).respond(200, json=entry["raw"])
    menu = Menu.model_validate(entry["menu"])
    gemini = upstream.post(GEMINI_URL).respond(
        200, json=gemini_answer(all_green_reply(menu))
    )
    first = _get(app_client, _WOLT_PATH, {"classify": "true"})
    assert first.json()["analysis"]["engine"]["kind"] == "llm"
    (row,) = _stored(app_client)
    model_analysis = row.analysis_json

    # Other options miss the analysis cache; Gemini now times out.
    gemini.mock(side_effect=httpx.ReadTimeout("slow"))
    second = _get(
        app_client, _WOLT_PATH, {"classify": "true", "netCarbLimitGrams": "9"}
    )

    assert second.json()["analysis"]["engine"] == {
        "kind": "rules",
        "reason": "timeout",
    }
    (row,) = _stored(app_client)
    assert row.analysis_json == model_analysis
    assert row.submission_count == 2
