"""``allergenMatrix`` on ``GET /v1/venue-menus`` (ALG-16, #358).

The restaurant's allergen matrix rides along with the menu when the
maintainer entered one that holds today, and the key is absent otherwise, so
every existing answer (and golden) is unchanged. Wolt and 10bis are respx
routes on the default base URLs; nothing leaves the sandbox.
"""

import logging
from collections.abc import Iterator
from datetime import UTC, datetime
from typing import Any

import pytest
import respx
from fastapi.testclient import TestClient
from sqlalchemy import Engine

from app.schemas import VenueMenuResponse
from app.services import allergen_matrix as am
from tests.analysis_support import (
    HEADERS,
    INSTALL_ID,
    client,
    database_text,
    golden_entry,
    settings,
)

_WOLT_URL = (
    "https://consumer-api.wolt.com/consumer-api/consumer-assortment/v1/venues/slug/"
    "hamosad/assortment"
)
_TENBIS_URL = "https://www.10bis.co.il/api/v1.0/Restaurants/9001/Menu"


@pytest.fixture
def upstream() -> Iterator[respx.MockRouter]:
    with respx.mock(assert_all_called=False) as router:
        router.get(_WOLT_URL).respond(
            200,
            json=golden_entry("wolt_menu.json", "synthetic_options_and_labels")["raw"],
        )
        router.get(_TENBIS_URL).respond(
            200,
            json=golden_entry("tenbis_menu.json", "tenbis_synthetic_menu.json")["raw"],
        )
        yield router


@pytest.fixture
def app_client() -> Iterator[TestClient]:
    with client(settings()) as test_client:
        yield test_client


def _engine(test_client: TestClient) -> Engine:
    engine: Engine = test_client.app.state.engine  # type: ignore[attr-defined]
    return engine


def _enter(
    test_client: TestClient,
    *,
    source: str = "wolt",
    platform_id: str = "hamosad",
    valid_from: str = "2020-01-01",
    valid_until: str | None = None,
) -> None:
    document = am.parse_document(
        {
            "venue": {"source": source, "platformId": platform_id},
            "source": "restaurant",
            "enteredBy": "Maintainer",
            "validFrom": valid_from,
            "validUntil": valid_until,
            "rows": [
                {
                    "name": "שקשוקה",
                    "aliases": ["Shakshuka"],
                    "allergens": {"eggs": "contains", "sesame": "free"},
                }
            ],
        }
    )
    am.save(_engine(test_client), document, now=datetime.now(UTC))


def _get(test_client: TestClient, path: str) -> dict[str, Any]:
    response = test_client.get(path, headers=HEADERS)
    assert response.status_code == 200
    body: dict[str, Any] = response.json()
    return body


def test_no_matrix_leaves_the_answer_as_it_was(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    body = _get(app_client, "/v1/venue-menus/wolt/hamosad")

    assert set(body) == {"menu", "analysis", "fromCache", "fetchedAt"}


def test_a_current_matrix_rides_along(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    _enter(app_client)

    body = _get(app_client, "/v1/venue-menus/wolt/hamosad")

    assert body["allergenMatrix"] == {
        "source": "restaurant",
        "validFrom": "2020-01-01",
        "validUntil": None,
        "rows": [
            {
                "name": "שקשוקה",
                "aliases": ["Shakshuka"],
                "allergens": {"eggs": "contains", "sesame": "free"},
            }
        ],
    }
    # The person who entered it stays on the server.
    assert "Maintainer" not in str(body)
    parsed = VenueMenuResponse.model_validate(body)
    assert parsed.model_dump(by_alias=True, mode="json") == body


def test_a_10bis_venue_gets_its_own_matrix(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    _enter(app_client, source="tenbis", platform_id="9001")

    assert "allergenMatrix" in _get(app_client, "/v1/venue-menus/tenbis/9001")
    assert "allergenMatrix" not in _get(app_client, "/v1/venue-menus/wolt/hamosad")


@pytest.mark.parametrize(
    ("valid_from", "valid_until"),
    [("2020-01-01", "2021-01-01"), ("2999-01-01", None)],
)
def test_a_matrix_outside_its_dates_is_not_sent(
    app_client: TestClient,
    upstream: respx.MockRouter,
    valid_from: str,
    valid_until: str | None,
) -> None:
    _enter(app_client, valid_from=valid_from, valid_until=valid_until)

    assert "allergenMatrix" not in _get(app_client, "/v1/venue-menus/wolt/hamosad")


def test_a_failed_matrix_read_still_serves_the_menu(
    app_client: TestClient,
    upstream: respx.MockRouter,
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    def broken(*_: object) -> None:
        raise RuntimeError("database gone")

    monkeypatch.setattr(am, "current", broken)

    with caplog.at_level(logging.WARNING):
        body = _get(app_client, "/v1/venue-menus/wolt/hamosad")

    assert "allergenMatrix" not in body
    assert body["menu"]["venueRef"]["platformId"] == "hamosad"
    assert "matrix read failed" in caplog.text


def test_the_install_id_is_never_beside_the_matrix(
    app_client: TestClient,
    upstream: respx.MockRouter,
    caplog: pytest.LogCaptureFixture,
) -> None:
    _enter(app_client)

    with caplog.at_level(logging.DEBUG):
        _get(app_client, "/v1/venue-menus/wolt/hamosad")

    assert INSTALL_ID not in database_text(_engine(app_client))
    assert INSTALL_ID not in caplog.text
