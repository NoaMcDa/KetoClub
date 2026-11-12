"""Tests for ``POST /v1/places/search`` (#449): a typed street geocoded by
Photon through the backend."""

import json
import logging
from collections.abc import Iterator
from typing import Any
from urllib.parse import quote

import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.services.places import map_photon_places

_INSTALL_ID = "0123456789abcdef0123456789abcdef"
_PATH = "/v1/places/search"
_UPSTREAM = "https://photon.komoot.io/api/"
_QUERY = "הרצל 10 תל אביב"


def _headers(install_id: str | None = _INSTALL_ID) -> dict[str, str]:
    return {} if install_id is None else {"X-KetoClub-Install-Id": install_id}


def _search(
    client: TestClient,
    body: dict[str, object] | None = None,
    headers: dict[str, str] | None = None,
) -> httpx.Response:
    payload = {"query": _QUERY} if body is None else body
    return client.post(
        _PATH, json=payload, headers=_headers() if headers is None else headers
    )


def _house(
    street: str | None,
    number: str | None = None,
    city: str | None = "תל אביב-יפו",
    *,
    lon: Any = 34.7745,
    lat: Any = 32.0636,
    country: str = "IL",
    district: str | None = None,
) -> dict[str, Any]:
    properties: dict[str, Any] = {"countrycode": country, "type": "house"}
    if street is not None:
        properties["street"] = street
    if number is not None:
        properties["housenumber"] = number
    if city is not None:
        properties["city"] = city
    if district is not None:
        properties["district"] = district
    return {
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": [lon, lat]},
        "properties": properties,
    }


def _street(
    name: str | None,
    city: str | None = "תל אביב-יפו",
    *,
    lon: float = 34.77,
    lat: float = 32.07,
    country: str = "IL",
    district: str | None = None,
) -> dict[str, Any]:
    properties: dict[str, Any] = {"countrycode": country, "type": "street"}
    if name is not None:
        properties["name"] = name
    if city is not None:
        properties["city"] = city
    if district is not None:
        properties["district"] = district
    return {
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": [lon, lat]},
        "properties": properties,
    }


def _collection(*features: dict[str, Any]) -> dict[str, Any]:
    return {"type": "FeatureCollection", "features": list(features)}


@pytest.fixture
def photon() -> Iterator[respx.MockRouter]:
    with respx.mock(assert_all_called=False) as router:
        yield router


def _client(**overrides: Any) -> TestClient:
    settings = Settings(
        DATABASE_URL="sqlite:///:memory:",
        GEMINI_API_KEY="",
        ADMIN_TOKEN="",
        **overrides,
    )
    return TestClient(create_app(settings=settings))


# --- a good reply -----------------------------------------------------------


def test_house_and_street_features_become_places(
    client: TestClient, photon: respx.MockRouter
) -> None:
    photon.get(_UPSTREAM).mock(
        return_value=httpx.Response(
            200,
            json=_collection(
                _house("הרצל", "10", lon=34.7712, lat=32.0621),
                _street("הרצל", city=None, district="נווה צדק"),
                _street("רוטשילד", city=None),
            ),
        )
    )

    response = _search(client)

    assert response.status_code == 200
    assert response.json() == {
        "places": [
            {
                "label": "הרצל 10, תל אביב-יפו",
                "city": "תל אביב-יפו",
                "latitude": 32.0621,
                "longitude": 34.7712,
            },
            {
                "label": "הרצל, נווה צדק",
                "city": "נווה צדק",
                "latitude": 32.07,
                "longitude": 34.77,
            },
            {
                "label": "רוטשילד",
                "city": None,
                "latitude": 32.07,
                "longitude": 34.77,
            },
        ]
    }


def test_the_upstream_request_is_built_from_scratch(
    client: TestClient, photon: respx.MockRouter
) -> None:
    route = photon.get(_UPSTREAM).mock(
        return_value=httpx.Response(200, json=_collection())
    )

    client.post(
        _PATH,
        json={"query": f"  {_QUERY}  "},
        headers={**_headers(), "Cookie": "a=b", "Origin": "http://localhost:1"},
    )

    request = route.calls.last.request
    assert request.url.params.get("q") == _QUERY
    assert request.url.params.get("limit") == "15"
    assert request.url.params.get("lang") == "default"
    assert request.url.params.get("bbox") == "34.2,29.4,35.9,33.4"
    assert request.url.params.get_list("layer") == ["house", "street"]
    assert request.headers["User-Agent"].startswith("KetoClub/")
    assert "cookie" not in request.headers
    assert "origin" not in request.headers
    assert "x-ketoclub-install-id" not in request.headers
    assert "authorization" not in request.headers


def test_english_maps_to_lang_en(client: TestClient, photon: respx.MockRouter) -> None:
    route = photon.get(_UPSTREAM).mock(
        return_value=httpx.Response(
            200, json=_collection(_house("Dizengoff Street", "50", "Tel Aviv-Yafo"))
        )
    )

    response = _search(client, {"query": "Dizengoff 50", "language": "en"})

    assert route.calls.last.request.url.params.get("lang") == "en"
    assert response.json()["places"][0]["label"] == "Dizengoff Street 50, Tel Aviv-Yafo"


def test_duplicates_are_dropped_keeping_the_first(
    client: TestClient, photon: respx.MockRouter
) -> None:
    photon.get(_UPSTREAM).mock(
        return_value=httpx.Response(
            200,
            json=_collection(
                _house("הרצל", "10", lon=34.1, lat=32.1),
                _house("הרצל", "10", lon=34.2, lat=32.2),
                _street("הרצל"),
            ),
        )
    )

    places = _search(client).json()["places"]

    assert [p["label"] for p in places] == ["הרצל 10, תל אביב-יפו", "הרצל, תל אביב-יפו"]
    assert places[0]["longitude"] == 34.1


def _labels(*features: dict[str, Any]) -> list[str]:
    places = map_photon_places(_collection(*features))
    assert places is not None
    return [place.label for place in places]


def test_one_address_under_three_city_spellings_is_one_place() -> None:
    # The live reply for "הרצל 10 תל אביב" on 2026-11-12.
    labels = _labels(
        _house("הרצל", "10", "תל אביב", lon=34.7698648, lat=32.0625697),
        _house("הרצל", "10", "תל אביב-יפו", lon=34.7699465, lat=32.0625439),
        _house("הרצל", "10", "תל אביב–יפו", lon=34.769931, lat=32.062416),
        _house("הרצל", "10", "רמת גן", lon=34.8188628, lat=32.08107),
    )

    assert labels == ["הרצל 10, תל אביב", "הרצל 10, רמת גן"]


def test_street_and_number_compare_trimmed_and_lowercased() -> None:
    labels = _labels(
        _house("Herzl", "10a", "Tel Aviv", lon=34.7700, lat=32.0600),
        _house(" herzl ", " 10A ", "Tel Aviv-Yafo", lon=34.7720, lat=32.0620),
    )

    assert labels == ["Herzl 10a, Tel Aviv"]


def test_the_same_street_in_two_cities_far_apart_stays_two() -> None:
    labels = _labels(
        _street("רוטשילד", "תל אביב-יפו", lon=34.7740, lat=32.0640),
        _street("רוטשילד", "ראשון לציון", lon=34.8028, lat=31.9640),
    )

    assert labels == ["רוטשילד, תל אביב-יפו", "רוטשילד, ראשון לציון"]


def test_a_numberless_street_does_not_merge_with_a_house_on_it() -> None:
    labels = _labels(
        _street("הרצל", "תל אביב", lon=34.7700, lat=32.0620),
        _house("הרצל", "10", "תל אביב-יפו", lon=34.7701, lat=32.0621),
        _house("הרצל", None, "תל אביב–יפו", lon=34.7702, lat=32.0622),
    )

    assert labels == ["הרצל, תל אביב", "הרצל 10, תל אביב-יפו"]


def test_close_same_named_street_segments_merge() -> None:
    labels = _labels(
        _street("אבן גבירול", "תל אביב", lon=34.7810, lat=32.0800),
        _street("אבן גבירול", "תל אביב-יפו", lon=34.7835, lat=32.0825),
        _street("אבן גבירול", "תל אביב–יפו", lon=34.7810, lat=32.0840),
        _street("אבן גבירול", "רמת השרון", lon=34.7850, lat=32.0800),
    )

    # Within 0.003 of the first in both axes merges; 0.004 in either does not.
    assert labels == [
        "אבן גבירול, תל אביב",
        "אבן גבירול, תל אביב–יפו",
        "אבן גבירול, רמת השרון",
    ]


def test_at_most_six_places(client: TestClient, photon: respx.MockRouter) -> None:
    photon.get(_UPSTREAM).mock(
        return_value=httpx.Response(
            200, json=_collection(*[_house("הרצל", str(n)) for n in range(1, 16)])
        )
    )

    places = _search(client).json()["places"]

    assert [p["label"] for p in places] == [
        f"הרצל {n}, תל אביב-יפו" for n in range(1, 7)
    ]


def test_unusable_features_are_dropped(
    client: TestClient, photon: respx.MockRouter
) -> None:
    city_feature = _street("תל אביב")
    city_feature["properties"]["type"] = "city"
    # Photon's reply is read with json.loads, which accepts NaN; a JSON
    # encoder that refuses it cannot build this body, so it is dumped here.
    photon.get(_UPSTREAM).mock(
        return_value=httpx.Response(
            200,
            headers={"Content-Type": "application/json"},
            content=json.dumps(
                _collection(
                    _house("Herzl", "10", country="PS"),
                    _house(None, "10"),
                    _house("   ", "10"),
                    _street("  "),
                    city_feature,
                    _house("הרצל", "1", lon="34.7"),
                    _house("הרצל", "2", lon=True),
                    _house("הרצל", "3", lat=float("nan")),
                    "not a feature",
                    {"type": "Feature", "properties": {"countrycode": "IL"}},
                    _house("בן יהודה", "  ", country="il"),
                )
            ).encode("utf-8"),
        )
    )

    places = _search(client).json()["places"]

    assert [p["label"] for p in places] == ["בן יהודה, תל אביב-יפו"]


def test_mapping_rules() -> None:
    no_city = _house("הרצל", "4", city=None)
    district = _house("הרצל", "5", city="  ", district="פלורנטין")
    three = {"geometry": {"coordinates": [1.0, 2.0, 3.0]}, "properties": {}}
    three["properties"] = {"countrycode": "IL", "type": "street", "name": "x"}

    places = map_photon_places(_collection(no_city, district, three))

    assert places is not None
    assert [(p.label, p.city) for p in places] == [
        ("הרצל 4", None),
        ("הרצל 5, פלורנטין", "פלורנטין"),
    ]
    assert map_photon_places([]) is None
    assert map_photon_places({"features": {}}) is None


def test_an_empty_result_is_an_empty_list(
    client: TestClient, photon: respx.MockRouter
) -> None:
    photon.get(_UPSTREAM).mock(return_value=httpx.Response(200, json=_collection()))

    response = _search(client)

    assert response.status_code == 200
    assert response.json() == {"places": []}


# --- upstream failures ------------------------------------------------------


@pytest.mark.parametrize("status", [400, 404, 429, 500, 503])
def test_a_non_2xx_upstream_is_provider_changed(
    client: TestClient, photon: respx.MockRouter, status: int
) -> None:
    photon.get(_UPSTREAM).mock(return_value=httpx.Response(status, json={}))

    response = _search(client)

    assert response.status_code == 502
    assert response.json() == {"reason": "providerChanged", "status_code": 502}


@pytest.mark.parametrize(
    "reply",
    [
        httpx.Response(200, text="<html>not json</html>"),
        httpx.Response(200, json=[]),
        httpx.Response(200, json={"type": "FeatureCollection"}),
        httpx.Response(200, json={"features": "none"}),
    ],
    ids=["not-json", "a-list", "no-features", "features-not-a-list"],
)
def test_a_malformed_body_is_provider_changed(
    client: TestClient, photon: respx.MockRouter, reply: httpx.Response
) -> None:
    photon.get(_UPSTREAM).mock(return_value=reply)

    response = _search(client)

    assert response.status_code == 502
    assert response.json() == {"reason": "providerChanged", "status_code": 502}


def test_a_connect_error_is_offline(
    client: TestClient, photon: respx.MockRouter
) -> None:
    photon.get(_UPSTREAM).mock(side_effect=httpx.ConnectError("down"))

    response = _search(client)

    assert response.status_code == 502
    assert response.json() == {"reason": "offline", "status_code": 502}


def test_a_timeout_is_504(client: TestClient, photon: respx.MockRouter) -> None:
    photon.get(_UPSTREAM).mock(side_effect=httpx.ReadTimeout("slow"))

    response = _search(client)

    assert response.status_code == 504
    assert response.json() == {"reason": "timeout", "status_code": 504}


# --- the request ------------------------------------------------------------


def test_the_twenty_first_search_in_a_minute_is_429(photon: respx.MockRouter) -> None:
    route = photon.get(_UPSTREAM).mock(
        return_value=httpx.Response(200, json=_collection())
    )
    with _client() as client:
        statuses = [_search(client).status_code for _ in range(20)]
        refused = _search(client)
        other = _search(client, headers=_headers("f" * 32))

    assert statuses == [200] * 20
    assert refused.status_code == 429
    assert refused.json() == {"reason": "rateLimited", "status_code": 429}
    assert other.status_code == 200
    assert route.call_count == 21


def test_the_limit_is_configurable(photon: respx.MockRouter) -> None:
    photon.get(_UPSTREAM).mock(return_value=httpx.Response(200, json=_collection()))
    with _client(PLACE_SEARCH_RATE_LIMIT_PER_MINUTE=1) as client:
        assert _search(client).status_code == 200
        assert _search(client).status_code == 429


@pytest.mark.parametrize("install_id", [None, "short", "0123456789ABCDEF" * 2])
def test_a_missing_or_malformed_install_id_is_400(
    client: TestClient, photon: respx.MockRouter, install_id: str | None
) -> None:
    route = photon.get(_UPSTREAM)

    response = _search(client, headers=_headers(install_id))

    assert response.status_code == 400
    assert response.json() == {"reason": "badResponse", "status_code": 400}
    assert not route.called


def test_an_authorization_header_is_400(
    client: TestClient, photon: respx.MockRouter
) -> None:
    route = photon.get(_UPSTREAM)

    response = _search(client, headers={**_headers(), "Authorization": "Bearer x"})

    assert response.status_code == 400
    assert response.json() == {"reason": "badResponse", "status_code": 400}
    assert not route.called


@pytest.mark.parametrize(
    "body",
    [
        {"query": "a"},
        {"query": "   a   "},
        {"query": "x" * 121},
        {},
        {"query": _QUERY, "language": "fr"},
        {"query": 12},
    ],
    ids=["one-char", "one-char-padded", "121-chars", "no-query", "fr", "number"],
)
def test_a_bad_body_is_422(
    client: TestClient, photon: respx.MockRouter, body: dict[str, object]
) -> None:
    route = photon.get(_UPSTREAM)

    response = _search(client, body)

    assert response.status_code == 422
    assert not route.called


def test_the_query_bounds_are_inclusive(
    client: TestClient, photon: respx.MockRouter
) -> None:
    photon.get(_UPSTREAM).mock(return_value=httpx.Response(200, json=_collection()))

    assert _search(client, {"query": " ab "}).status_code == 200
    assert _search(client, {"query": "x" * 120}).status_code == 200


def test_disabled_is_404(photon: respx.MockRouter) -> None:
    with _client(PLACE_SEARCH_ENABLED=False) as client:
        assert _search(client).status_code == 404


# --- privacy ----------------------------------------------------------------


def test_no_log_record_carries_the_query_or_a_place(
    photon: respx.MockRouter, caplog: pytest.LogCaptureFixture
) -> None:
    photon.get(_UPSTREAM).mock(
        return_value=httpx.Response(
            200,
            json=_collection(
                _house("Dizengoff Street", "50", "Tel Aviv", lon=34.7741, lat=32.0779)
            ),
        )
    )
    secrets = [
        "Dizengoff",
        quote("Dizengoff"),
        "Tel Aviv",
        "34.7741",
        "32.0779",
        _QUERY,
        quote(_QUERY),
        _INSTALL_ID,
    ]

    with caplog.at_level(logging.DEBUG), _client() as client:
        ok = _search(client, {"query": "Dizengoff 50 Tel Aviv", "language": "en"})
        hebrew = _search(client)

    assert ok.json()["places"][0]["label"] == "Dizengoff Street 50, Tel Aviv"
    assert hebrew.status_code == 200
    rendered = " ".join(
        f"{record.getMessage()} {record.__dict__}" for record in caplog.records
    )
    assert "places outcome=ok" in rendered
    assert "photon.komoot.io" in rendered  # httpx's line is there, redacted
    for secret in secrets:
        assert secret not in rendered, secret
