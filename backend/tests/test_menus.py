"""Tests for ``POST /v1/menus`` and ``GET /v1/menus/{source}/{platform_id}``
(#310): the anonymous shared menu store.

The install id is for rate limiting only (D12, #164): the privacy tests
below assert it reaches neither a log record nor any column of any table.
"""

import json
import logging
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import UTC, datetime, timedelta
from typing import Any

import httpx
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Engine, inspect, text

from app.config import Settings
from app.main import create_app
from app.routers import menus

_INSTALL_ID = "fedcba9876543210fedcba9876543210"
_HEADERS = {"X-KetoClub-Install-Id": _INSTALL_ID}
_MENU: dict[str, Any] = {
    "categories": [
        {"name": "Mains", "dishes": [{"name": "Steak"}, {"name": "Salmon"}]},
    ]
}


def _settings(**overrides: object) -> Settings:
    fields: dict[str, object] = {
        "DATABASE_URL": "sqlite:///:memory:",
        "RATE_LIMIT_PER_MINUTE": 100,
        "RATE_LIMIT_PER_DAY": 1000,
    }
    fields.update(overrides)
    return Settings(**fields)  # type: ignore[arg-type]


@contextmanager
def _client(settings: Settings) -> Iterator[TestClient]:
    with TestClient(create_app(settings=settings)) as client:
        yield client


@pytest.fixture
def menus_client() -> Iterator[TestClient]:
    with _client(_settings()) as client:
        yield client


def _body(**overrides: Any) -> dict[str, Any]:
    body: dict[str, Any] = {
        "source": "wolt",
        "platform_id": "hamosad",
        "venue_name": "Hamosad",
        "city": "Tel Aviv",
        "menu": _MENU,
        "analysis": {"score": 80, "dishes": []},
    }
    body.update(overrides)
    return body


def _post(
    client: TestClient,
    body: dict[str, Any] | None = None,
    headers: dict[str, str] | None = None,
) -> httpx.Response:
    response: httpx.Response = client.post(
        "/v1/menus",
        json=_body() if body is None else body,
        headers=_HEADERS if headers is None else headers,
    )
    return response


def _engine(client: TestClient) -> Engine:
    engine: Engine = client.app.state.engine  # type: ignore[attr-defined]
    return engine


def _rows(client: TestClient) -> list[dict[str, Any]]:
    with _engine(client).connect() as connection:
        result = connection.execute(text("SELECT * FROM stored_menus"))
        return [dict(row._mapping) for row in result]


class _Clock:
    """Stands in for ``datetime`` in the router: ``now`` steps forward."""

    def __init__(self) -> None:
        self.current = datetime(2026, 10, 8, 9, 0, tzinfo=UTC)

    def now(self, tz: object = None) -> datetime:
        return self.current


@pytest.fixture
def clock(monkeypatch: pytest.MonkeyPatch) -> _Clock:
    fake = _Clock()
    monkeypatch.setattr(menus, "datetime", fake)
    return fake


# --- POST: create and refresh --------------------------------------------------


def test_first_post_creates_a_row(menus_client: TestClient) -> None:
    response = _post(menus_client)

    assert response.status_code == 201
    assert response.json() == {"created": True, "submission_count": 1}
    rows = _rows(menus_client)
    assert len(rows) == 1
    assert rows[0]["source"] == "wolt"
    assert rows[0]["platform_id"] == "hamosad"
    assert rows[0]["dish_count"] == 2
    assert rows[0]["score"] == 80.0
    assert json.loads(rows[0]["menu_json"]) == _MENU


def test_second_post_refreshes_the_row(menus_client: TestClient, clock: _Clock) -> None:
    _post(menus_client)
    first = _rows(menus_client)[0]
    clock.current += timedelta(minutes=30)

    response = _post(menus_client)

    assert response.status_code == 200
    assert response.json() == {"created": False, "submission_count": 2}
    second = _rows(menus_client)[0]
    assert second["first_seen_at"] == first["first_seen_at"]
    assert second["last_seen_at"] > first["last_seen_at"]
    assert second["submission_count"] == 2


def test_platform_id_is_stripped(menus_client: TestClient) -> None:
    _post(menus_client, _body(platform_id="  hamosad  "))
    assert _post(menus_client).json()["submission_count"] == 2


def test_null_name_city_and_analysis_never_overwrite(
    menus_client: TestClient,
) -> None:
    _post(menus_client)
    _post(menus_client, _body(venue_name=None, city=None, analysis=None))

    row = _rows(menus_client)[0]
    assert row["venue_name"] == "Hamosad"
    assert row["city"] == "Tel Aviv"
    assert json.loads(row["analysis_json"]) == {"score": 80, "dishes": []}
    assert row["score"] == 80.0


def test_omitted_optional_fields_are_null(menus_client: TestClient) -> None:
    response = _post(menus_client, {"source": "scan", "platform_id": "abc", "menu": {}})

    assert response.status_code == 201
    row = _rows(menus_client)[0]
    assert row["venue_name"] is None
    assert row["city"] is None
    assert row["analysis_json"] is None
    assert row["score"] is None
    assert row["dish_count"] == 0


# --- POST: validation ------------------------------------------------------------


@pytest.mark.parametrize(
    "body",
    [
        _body(source="deliveroo"),
        _body(platform_id=""),
        _body(platform_id="   "),
        _body(platform_id="x" * 513),
        _body(venue_name="n" * 201),
        _body(city="c" * 201),
        _body(menu="not an object"),
        _body(analysis=[1, 2]),
        {"source": "wolt", "platform_id": "hamosad"},
    ],
)
def test_a_bad_body_is_422_and_stores_nothing(
    menus_client: TestClient, body: dict[str, Any]
) -> None:
    response = _post(menus_client, body)

    assert response.status_code == 422
    assert response.json()["detail"][0]["loc"][0] == "body"
    assert _rows(menus_client) == []


def test_malformed_json_is_422(menus_client: TestClient) -> None:
    response = menus_client.post(
        "/v1/menus",
        content=b"{not json",
        headers={**_HEADERS, "Content-Type": "application/json"},
    )
    assert response.status_code == 422


def test_nan_in_the_menu_is_422(menus_client: TestClient) -> None:
    response = menus_client.post(
        "/v1/menus",
        content=(
            b'{"source":"wolt","platform_id":"x","menu":{"categories":[],"v":NaN}}'
        ),
        headers={**_HEADERS, "Content-Type": "application/json"},
    )
    assert response.status_code == 422
    assert _rows(menus_client) == []


def test_a_422_spends_no_quota() -> None:
    with _client(_settings(RATE_LIMIT_PER_MINUTE=1)) as client:
        assert _post(client, _body(source="nope")).status_code == 422
        assert _post(client).status_code == 201


# --- POST: install id, Authorization, rate limit, size ---------------------------


@pytest.mark.parametrize(
    "headers",
    [
        {},
        {"X-KetoClub-Install-Id": "not-hex"},
        {"X-KetoClub-Install-Id": _INSTALL_ID.upper()},
    ],
)
def test_missing_or_malformed_install_id_is_400(
    menus_client: TestClient, headers: dict[str, str]
) -> None:
    response = _post(menus_client, headers=headers)

    assert response.status_code == 400
    assert response.json() == {"reason": "badResponse", "status_code": 400}
    assert _rows(menus_client) == []


def test_an_authorization_header_is_400(menus_client: TestClient) -> None:
    response = _post(menus_client, headers={**_HEADERS, "Authorization": "Bearer x"})

    assert response.status_code == 400
    assert response.json() == {"reason": "badResponse", "status_code": 400}
    assert _rows(menus_client) == []


def test_the_sixth_post_in_a_minute_is_429() -> None:
    with _client(_settings(RATE_LIMIT_PER_MINUTE=5)) as client:
        statuses = [_post(client).status_code for _ in range(5)]
        sixth = _post(client)

        assert statuses == [201, 200, 200, 200, 200]
        assert sixth.status_code == 429
        assert sixth.json() == {"reason": "rateLimited", "status_code": 429}
        assert _rows(client)[0]["submission_count"] == 5


def test_an_oversized_content_length_is_413() -> None:
    with _client(_settings(MENU_STORE_MAX_BODY_BYTES=200)) as client:
        big = _body(menu={"categories": [], "pad": "x" * 500})
        response = _post(client, big)

        assert response.status_code == 413
        assert response.json() == {"reason": "payloadTooLarge", "status_code": 413}
        assert _rows(client) == []


def test_an_oversized_chunked_body_is_413() -> None:
    def chunks() -> Iterator[bytes]:
        yield b'{"source":"wolt","platform_id":"x","menu":{"pad":"'
        for _ in range(10):
            yield b"x" * 100
        yield b'"}}'

    with _client(_settings(MENU_STORE_MAX_BODY_BYTES=200)) as client:
        response = client.post(
            "/v1/menus",
            content=chunks(),
            headers={**_HEADERS, "Content-Type": "application/json"},
        )

        assert "content-length" not in response.request.headers
        assert response.status_code == 413
        assert _rows(client) == []


def test_a_body_at_the_cap_is_accepted() -> None:
    raw = json.dumps(_body()).encode()
    with _client(_settings(MENU_STORE_MAX_BODY_BYTES=len(raw))) as client:
        response = client.post(
            "/v1/menus",
            content=raw,
            headers={**_HEADERS, "Content-Type": "application/json"},
        )
        assert response.status_code == 201


# --- disabled ------------------------------------------------------------------


def test_disabled_store_is_404() -> None:
    with _client(_settings(MENU_STORE_ENABLED=False)) as client:
        assert _post(client).status_code == 404
        assert client.get("/v1/menus/wolt/hamosad").status_code == 404


# --- GET ------------------------------------------------------------------------


def test_get_returns_the_stored_menu(menus_client: TestClient, clock: _Clock) -> None:
    _post(menus_client)
    clock.current += timedelta(hours=1)
    _post(menus_client, _body(venue_name=None))

    response = menus_client.get("/v1/menus/wolt/hamosad")

    assert response.status_code == 200
    assert response.json() == {
        "source": "wolt",
        "platform_id": "hamosad",
        "venue_name": "Hamosad",
        "city": "Tel Aviv",
        "menu": _MENU,
        "analysis": {"score": 80, "dishes": []},
        "dish_count": 2,
        "score": 80.0,
        "first_seen_at": "2026-10-08T09:00:00Z",
        "last_seen_at": "2026-10-08T10:00:00Z",
        "submission_count": 2,
    }


def test_get_a_menu_without_analysis(menus_client: TestClient) -> None:
    _post(menus_client, _body(source="website", analysis=None))

    body = menus_client.get("/v1/menus/website/hamosad").json()

    assert body["analysis"] is None
    assert body["score"] is None


def test_get_a_platform_id_with_slashes(menus_client: TestClient) -> None:
    _post(menus_client, _body(source="website", platform_id="example.com/menu"))

    response = menus_client.get("/v1/menus/website/example.com/menu")

    assert response.status_code == 200
    assert response.json()["platform_id"] == "example.com/menu"


def test_get_an_unknown_menu_is_404(menus_client: TestClient) -> None:
    response = menus_client.get("/v1/menus/wolt/nowhere")

    assert response.status_code == 404
    assert response.json() == {"reason": "menuNotFound", "status_code": 404}


def test_get_an_unknown_source_is_422(menus_client: TestClient) -> None:
    assert menus_client.get("/v1/menus/deliveroo/hamosad").status_code == 422


def test_get_an_overlong_platform_id_is_422(menus_client: TestClient) -> None:
    assert menus_client.get("/v1/menus/wolt/" + "x" * 513).status_code == 422


def test_get_with_authorization_is_400(menus_client: TestClient) -> None:
    response = menus_client.get(
        "/v1/menus/wolt/hamosad", headers={"Authorization": "Bearer x"}
    )
    assert response.status_code == 400


# --- privacy: the install id is never logged or stored --------------------------


def test_the_install_id_is_never_logged(caplog: pytest.LogCaptureFixture) -> None:
    with (
        caplog.at_level(logging.DEBUG),
        _client(_settings(RATE_LIMIT_PER_MINUTE=2)) as client,
    ):
        _post(client)
        _post(client)
        _post(client)  # rate limited
        _post(client, _body(source="nope"))
        client.get("/v1/menus/wolt/hamosad")

    assert caplog.records
    for record in caplog.records:
        rendered = record.getMessage() + " " + json.dumps(record.__dict__, default=str)
        assert _INSTALL_ID not in rendered
        assert _INSTALL_ID[:8] not in rendered
    menu_lines = [r.getMessage() for r in caplog.records if r.name == "ketoclub.menus"]
    assert "menus store source=wolt created=True" in menu_lines
    assert "menus store rate limited" in menu_lines


def test_the_install_id_is_in_no_column_of_any_table(
    menus_client: TestClient,
) -> None:
    _post(menus_client)
    _post(menus_client, _body(source="tenbis", platform_id="42"))

    engine = _engine(menus_client)
    seen = 0
    with engine.connect() as connection:
        for table in inspect(engine).get_table_names():
            for row in connection.execute(text(f'SELECT * FROM "{table}"')):
                seen += 1
                for value in row:
                    assert _INSTALL_ID not in str(value)
                    assert _INSTALL_ID[:8] not in str(value)
    assert seen >= 2


def test_the_openapi_page_declares_the_body(menus_client: TestClient) -> None:
    spec = menus_client.get("/openapi.json").json()
    operation = spec["paths"]["/v1/menus"]["post"]
    schema = operation["requestBody"]["content"]["application/json"]["schema"]
    assert set(schema["required"]) == {"source", "platform_id", "menu"}
