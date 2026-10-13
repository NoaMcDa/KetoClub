"""``POST /v1/menus`` refuses a restriction profile (Banto C1).

The profile never leaves the device, not even as ids. The Dart side is pinned
by ``test/architecture/no_profile_on_the_wire_test.dart``; this is the server
half: the shared menu store's body model forbids unknown fields
(``extra="forbid"``, which was not set before this change), and it refuses a
profile key anywhere inside the opaque ``menu`` and ``analysis`` objects, so a
client bug cannot upload one and have the rest of the body stored.
"""

from collections.abc import Iterator
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app

_HEADERS = {"X-KetoClub-Install-Id": "fedcba9876543210fedcba9876543210"}
_PROFILE_KEYS = [
    "profile",
    "dietaryProfile",
    "restrictions",
    "restrictionIds",
    "severity",
]


def _valid_body() -> dict[str, Any]:
    return {
        "source": "wolt",
        "platform_id": "hamosad",
        "venue_name": "Hamosad",
        "city": "Tel Aviv",
        "menu": {"categories": [{"name": "Mains", "dishes": [{"name": "Steak"}]}]},
        "analysis": {"score": 80, "dishes": []},
    }


@pytest.fixture
def client() -> Iterator[TestClient]:
    settings = Settings(
        DATABASE_URL="sqlite:///:memory:",  # type: ignore[arg-type]
        RATE_LIMIT_PER_MINUTE=100,  # type: ignore[arg-type]
        RATE_LIMIT_PER_DAY=1000,  # type: ignore[arg-type]
    )
    with TestClient(create_app(settings=settings)) as test_client:
        yield test_client


def _post(client: TestClient, body: dict[str, Any]) -> int:
    return client.post("/v1/menus", json=body, headers=_HEADERS).status_code


def _stored_count(client: TestClient) -> int:
    response = client.get("/v1/menus/wolt/hamosad")
    return (
        0 if response.status_code == 404 else int(response.json()["submission_count"])
    )


def test_a_valid_body_is_still_accepted(client: TestClient) -> None:
    assert _post(client, _valid_body()) == 201
    assert _post(client, _valid_body()) == 200


@pytest.mark.parametrize("key", _PROFILE_KEYS)
@pytest.mark.parametrize("value", [["gluten"], {"gluten": 1}, "high", 3])
def test_a_top_level_profile_key_is_422(
    client: TestClient, key: str, value: object
) -> None:
    body = {**_valid_body(), key: value}

    assert _post(client, body) == 422
    assert _stored_count(client) == 0


@pytest.mark.parametrize("key", _PROFILE_KEYS)
def test_a_profile_key_inside_the_menu_is_422(client: TestClient, key: str) -> None:
    body = _valid_body()
    body["menu"]["categories"][0]["dishes"][0][key] = ["gluten"]

    assert _post(client, body) == 422
    assert _stored_count(client) == 0


@pytest.mark.parametrize("key", _PROFILE_KEYS)
def test_a_profile_key_inside_the_analysis_is_422(client: TestClient, key: str) -> None:
    body = _valid_body()
    body["analysis"] = {"score": 80, "dishes": [], "meta": {key: ["gluten"]}}

    assert _post(client, body) == 422
    assert _stored_count(client) == 0


def test_a_profile_word_in_a_value_is_not_a_key(client: TestClient) -> None:
    # Only keys are refused: a dish may be called "Severity Burger".
    body = _valid_body()
    body["menu"]["categories"][0]["dishes"][0]["name"] = "profile restrictions"

    assert _post(client, body) == 201
