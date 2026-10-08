"""Tests for ``POST /v1/text-menu`` (D18, D25, #333).

The menu side is pinned by the golden paste corpus (``text_menu.json``,
exported from the Dart ``TextMenuSource``); Gemini is a respx route nested
inside the autouse network block from ``conftest``.
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

from app.keto.fingerprint import fingerprint_hex
from app.keto.models import Menu, to_json
from app.models import StoredMenu
from app.schemas import ScannedMenuResponse
from tests.analysis_support import (
    GEMINI_URL,
    HEADERS,
    INSTALL_ID,
    MODEL_VERSION,
    all_green_reply,
    client,
    database_text,
    gemini_answer,
    golden,
    settings,
)

_OPTIONS = {"netCarbLimitGrams": 6, "dietaryConstraints": []}


def _pastes() -> list[dict[str, Any]]:
    return [
        e for e in golden("text_menu.json") if e["uncategorisedName"] == "Pasted menu"
    ]


def _paste(text_prefix: str) -> dict[str, Any]:
    entry: dict[str, Any] = next(
        e for e in _pastes() if e["text"].startswith(text_prefix)
    )
    return entry


@pytest.fixture
def gemini() -> Iterator[respx.MockRouter]:
    with respx.mock(assert_all_called=False) as router:
        yield router


@pytest.fixture
def app_client() -> Iterator[TestClient]:
    with client(settings()) as test_client:
        yield test_client


def _post(
    test_client: TestClient, text: str, options: Any = None, **headers: str
) -> httpx.Response:
    return test_client.post(
        "/v1/text-menu",
        json={"text": text, "options": options or _OPTIONS},
        headers={**HEADERS, **headers},
    )


def _without_fetched_at(menu: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in menu.items() if key != "fetchedAt"}


@pytest.mark.parametrize(
    "entry",
    [e for e in _pastes() if e["menu"] is not None],
    ids=lambda e: e["text"][:24],
)
def test_the_menu_is_the_dart_paste_readers(
    gemini: respx.MockRouter, entry: dict[str, Any]
) -> None:
    route = gemini.post(GEMINI_URL).respond(500)
    with client(settings(GEMINI_API_KEY="")) as test_client:
        response = _post(test_client, entry["text"])

    assert response.status_code == 200
    body = response.json()
    assert to_json(ScannedMenuResponse.model_validate(body)) == body
    assert _without_fetched_at(body["menu"]) == _without_fetched_at(entry["menu"])
    menu = Menu.model_validate(body["menu"])
    assert body["menu"]["venueRef"] == {
        "source": "scan",
        "platformId": fingerprint_hex(menu),
    }
    assert body["menu"]["fetchedAt"] == body["analysis"]["analysedAt"]
    assert body["analysis"]["engine"] == {"kind": "rules", "reason": "notConfigured"}
    assert body["analysis"]["schemaVersion"] == 1
    assert body["analysis"]["options"] == _OPTIONS
    assert not route.called


def test_an_llm_analysis_is_cached_by_dish_text(
    app_client: TestClient, gemini: respx.MockRouter
) -> None:
    entry = _paste("Grilled salmon\nCaesar salad")
    menu = Menu.model_validate(entry["menu"])
    route = gemini.post(GEMINI_URL).respond(
        200, json=gemini_answer(all_green_reply(menu))
    )

    first = _post(app_client, entry["text"])
    # The same dishes pasted with other spacing: one menu, one analysis.
    second = _post(app_client, entry["text"].replace("\n", "\r\n") + "\n\n")

    assert first.status_code == 200
    assert first.headers["X-KetoClub-Cache"] == "miss"
    analysis = first.json()["analysis"]
    assert analysis["engine"] == {"kind": "llm", "model": MODEL_VERSION}
    assert analysis["options"] == _OPTIONS
    assert [d["dishId"] for d in analysis["dishes"]] == ["p1", "p2", "p3"]
    assert second.headers["X-KetoClub-Cache"] == "hit"
    assert second.json()["menu"]["venueRef"] == first.json()["menu"]["venueRef"]
    assert route.call_count == 1


@pytest.mark.parametrize(
    "text", [e["text"] for e in _pastes() if e["menu"] is None and e["text"]]
)
def test_text_with_no_dish_is_422_and_spends_nothing(
    gemini: respx.MockRouter, text: str
) -> None:
    route = gemini.post(GEMINI_URL).respond(500)
    with client(settings(ANALYSIS_RATE_LIMIT_PER_MINUTE=0)) as test_client:
        response = _post(test_client, text)
    assert response.status_code == 422
    assert response.json() == {"reason": "noDishesFound", "status_code": 422}
    assert not route.called


def test_an_empty_bucket_is_429(gemini: respx.MockRouter) -> None:
    route = gemini.post(GEMINI_URL).respond(500)
    with client(settings(ANALYSIS_RATE_LIMIT_PER_MINUTE=0)) as test_client:
        response = _post(test_client, "Steak\nSalmon")
    assert response.status_code == 429
    assert response.json() == {"reason": "rateLimited", "status_code": 429}
    assert not route.called


def test_a_gemini_failure_is_the_rules_with_its_reason(
    app_client: TestClient, gemini: respx.MockRouter
) -> None:
    gemini.post(GEMINI_URL).mock(side_effect=httpx.ConnectError("no route"))
    response = _post(app_client, "Steak\nPasta carbonara")
    assert response.status_code == 200
    analysis = response.json()["analysis"]
    assert analysis["engine"] == {"kind": "rules", "reason": "offline"}
    assert [d["verdict"] for d in analysis["dishes"]] == ["orderAsIs", "nonKeto"]


@pytest.mark.parametrize(
    "body",
    [
        {"text": "", "options": _OPTIONS},
        {"text": "x" * 100_001, "options": _OPTIONS},
        {
            "text": "Steak",
            "options": {"netCarbLimitGrams": 6, "dietaryConstraints": ["?"]},
        },
        {"text": "Steak"},
    ],
)
def test_a_body_outside_the_contract_is_422(
    app_client: TestClient, body: dict[str, Any]
) -> None:
    response = app_client.post("/v1/text-menu", json=body, headers=HEADERS)
    assert response.status_code == 422
    assert "detail" in response.json()


def test_credentials_are_refused(app_client: TestClient) -> None:
    with_auth = _post(app_client, "Steak", Authorization="Bearer x")
    assert with_auth.status_code == 400
    missing = app_client.post(
        "/v1/text-menu", json={"text": "Steak", "options": _OPTIONS}
    )
    assert missing.status_code == 400
    assert missing.json()["reason"] == "badResponse"


def test_the_install_id_is_in_no_row_and_no_log_line(
    app_client: TestClient,
    gemini: respx.MockRouter,
    caplog: pytest.LogCaptureFixture,
) -> None:
    entry = _paste("Grilled salmon\nCaesar salad")
    gemini.post(GEMINI_URL).respond(
        200, json=gemini_answer(all_green_reply(Menu.model_validate(entry["menu"])))
    )
    with caplog.at_level(logging.DEBUG):
        assert _post(app_client, entry["text"]).status_code == 200

    assert INSTALL_ID[:8] not in caplog.text
    engine = app_client.app.state.engine  # type: ignore[attr-defined]
    dumped = database_text(engine)
    assert dumped
    assert INSTALL_ID not in dumped and INSTALL_ID[:8] not in dumped
    with Session(engine) as session:
        # /v1/text-menu never writes the shared menu store.
        assert session.scalar(select(func.count()).select_from(StoredMenu)) == 0
    assert json.dumps(dict(gemini.calls.last.request.headers)).count(INSTALL_ID) == 0
