"""Tests for ``POST /v1/confirmations`` and the ``confirmations`` list of
``GET /v1/venue-menus`` (ALG-14, #356): anonymous post-meal facts about a dish.

The table is keyed by venue, dish fingerprint, restriction id and polarity and
holds a count and two dates; the install id spends the rate limit and is turned
into a one-way token for distinct counting, and reaches no column and no log
line (the D24 rule).
"""

import json
import logging
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from datetime import date
from typing import Any

import httpx
import pytest
import respx
from fastapi.testclient import TestClient
from sqlalchemy import Engine, inspect, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import Settings
from app.main import create_app
from app.models import ConfirmationVoter, DishConfirmation
from app.services import confirmations
from tests.analysis_support import golden_entry

_INSTALL_ID = "fedcba9876543210fedcba9876543210"
_WOLT_URL = (
    "https://consumer-api.wolt.com/consumer-api/consumer-assortment/v1/venues/slug/"
    "hamosad/assortment"
)
_FINGERPRINT = "a1b2c3d4"


def _settings(**overrides: object) -> Settings:
    fields: dict[str, object] = {
        "DATABASE_URL": "sqlite:///:memory:",
        "CONFIRMATION_RATE_LIMIT_PER_MINUTE": 100,
        "CONFIRMATION_RATE_LIMIT_PER_DAY": 1000,
    }
    fields.update(overrides)
    return Settings(**fields)  # type: ignore[arg-type]


@contextmanager
def _client(settings: Settings) -> Iterator[TestClient]:
    with TestClient(create_app(settings=settings)) as client:
        yield client


@pytest.fixture
def app_client() -> Iterator[TestClient]:
    with _client(_settings()) as client:
        yield client


@pytest.fixture
def upstream() -> Iterator[respx.MockRouter]:
    with respx.mock(assert_all_called=False) as router:
        router.get(_WOLT_URL).respond(
            200,
            json=golden_entry("wolt_menu.json", "synthetic_options_and_labels")["raw"],
        )
        yield router


def _install(n: int) -> str:
    return f"{n:032x}"


def _body(**overrides: Any) -> dict[str, Any]:
    body: dict[str, Any] = {
        "venue": {"source": "wolt", "platform_id": "hamosad"},
        "dishFingerprint": _FINGERPRINT,
        "restrictionId": "sesame",
        "polarity": "present",
    }
    body.update(overrides)
    return body


def _post(
    client: TestClient,
    body: dict[str, Any] | None = None,
    install_id: str | None = _INSTALL_ID,
) -> httpx.Response:
    headers = {} if install_id is None else {"X-KetoClub-Install-Id": install_id}
    response: httpx.Response = client.post(
        "/v1/confirmations",
        json=_body() if body is None else body,
        headers=headers,
    )
    return response


def _engine(client: TestClient) -> Engine:
    engine: Engine = client.app.state.engine  # type: ignore[attr-defined]
    return engine


def _rows(client: TestClient) -> list[DishConfirmation]:
    with Session(_engine(client)) as session:
        rows = list(session.scalars(select(DishConfirmation)))
        for row in rows:
            session.expunge(row)
        return rows


def _confirm_n(client: TestClient, n: int, *, start: int = 1, **overrides: Any) -> None:
    for index in range(start, start + n):
        assert _post(client, _body(**overrides), _install(index)).status_code == 201


def _venue_menu(client: TestClient, query: str = "") -> dict[str, Any]:
    response = client.get(
        f"/v1/venue-menus/wolt/hamosad{query}",
        headers={"X-KetoClub-Install-Id": _INSTALL_ID},
    )
    assert response.status_code == 200, response.text
    body: dict[str, Any] = response.json()
    return body


# --- the table -------------------------------------------------------------------


def test_the_table_has_no_install_id_and_no_note_column(
    app_client: TestClient,
) -> None:
    names = set(inspect(_engine(app_client)).get_table_names())
    assert {"dish_confirmations", "confirmation_voters", "stored_menus"} <= names
    columns = {
        column["name"]
        for column in inspect(_engine(app_client)).get_columns("dish_confirmations")
    }
    assert columns == {
        "source",
        "platform_id",
        "dish_fingerprint",
        "restriction_id",
        "polarity",
        "distinct_count",
        "submission_count",
        "first_on",
        "last_on",
    }
    voter_columns = [
        column["name"]
        for column in inspect(_engine(app_client)).get_columns("confirmation_voters")
    ]
    assert voter_columns == ["token"]


# --- the route -------------------------------------------------------------------


def test_a_new_confirmation_is_201_and_a_repeat_is_200_and_not_recounted(
    app_client: TestClient,
) -> None:
    first = _post(app_client)
    assert (first.status_code, first.json()) == (201, {"counted": True})
    repeat = _post(app_client)
    assert (repeat.status_code, repeat.json()) == (200, {"counted": False})

    (row,) = _rows(app_client)
    assert (row.source, row.platform_id) == ("wolt", "hamosad")
    assert (row.dish_fingerprint, row.restriction_id, row.polarity) == (
        _FINGERPRINT,
        "sesame",
        "present",
    )
    assert (row.distinct_count, row.submission_count) == (1, 2)
    assert row.first_on == row.last_on


def test_distinct_installs_are_counted_each_once(app_client: TestClient) -> None:
    _confirm_n(app_client, 3)
    assert _post(app_client, install_id=_install(2)).status_code == 200

    (row,) = _rows(app_client)
    assert (row.distinct_count, row.submission_count) == (3, 4)


def test_each_polarity_dish_restriction_and_venue_is_its_own_row(
    app_client: TestClient,
) -> None:
    for body in (
        _body(),
        _body(polarity="absent"),
        _body(restrictionId="milk"),
        _body(dishFingerprint="ffff0000"),
        _body(venue={"source": "wolt", "platform_id": "other"}),
        _body(venue={"source": "tenbis", "platform_id": "hamosad"}),
    ):
        assert _post(app_client, body).status_code == 201
    assert len(_rows(app_client)) == 6


def test_the_venue_may_use_the_camel_case_spelling(app_client: TestClient) -> None:
    body = _body(venue={"source": "scan", "platformId": "scan/1a2b3c4d"})
    assert _post(app_client, body).status_code == 201
    (row,) = _rows(app_client)
    assert (row.source, row.platform_id) == ("scan", "scan/1a2b3c4d")


@pytest.mark.parametrize(
    "restriction", ["peanuts", "sesame", "gluten", "alphaGal", "buckwheat", "fava"]
)
def test_every_taxonomy_id_is_accepted(
    app_client: TestClient, restriction: str
) -> None:
    assert _post(app_client, _body(restrictionId=restriction)).status_code == 201


# --- 422 -------------------------------------------------------------------------


def _with(extra: dict[str, Any]) -> dict[str, Any]:
    return _body(**extra)


_REFUSED: list[tuple[str, dict[str, Any]]] = [
    ("installId", _with({"installId": _INSTALL_ID})),
    ("install_id", _with({"install_id": _INSTALL_ID})),
    ("InstallId", _with({"InstallId": _INSTALL_ID})),
    ("note", _with({"note": "the waiter said no sesame"})),
    ("notes", _with({"notes": "x"})),
    ("Note", _with({"Note": "x"})),
    (
        "nested install id",
        _with({"venue": {"source": "wolt", "platform_id": "x", "installId": "y"}}),
    ),
    (
        "nested note",
        _with({"venue": {"source": "wolt", "platform_id": "x", "note": "y"}}),
    ),
    ("restrictions", _with({"restrictions": ["sesame"]})),
    ("restrictionIds", _with({"restrictionIds": ["sesame"]})),
    ("dietaryProfile", _with({"dietaryProfile": {}})),
    ("severity", _with({"severity": "strict"})),
    ("unknown field", _with({"count": 99})),
    ("unknown restriction", _with({"restrictionId": "pineapple"})),
    ("custom restriction", _with({"restrictionId": "custom"})),
    ("empty restriction", _with({"restrictionId": ""})),
    ("bad polarity", _with({"polarity": "maybe"})),
    ("prose fingerprint", _with({"dishFingerprint": "Eggplant salad, no sesame"})),
    ("empty fingerprint", _with({"dishFingerprint": ""})),
    ("long fingerprint", _with({"dishFingerprint": "a" * 65})),
    ("bad source", _with({"venue": {"source": "nope", "platform_id": "x"}})),
    ("empty platform id", _with({"venue": {"source": "wolt", "platform_id": ""}})),
    ("no venue", {k: v for k, v in _body().items() if k != "venue"}),
    ("venue as string", _with({"venue": "wolt/hamosad"})),
]


@pytest.mark.parametrize(("label", "body"), _REFUSED, ids=[r[0] for r in _REFUSED])
def test_a_malformed_or_forbidden_body_is_422_and_stores_nothing(
    app_client: TestClient, label: str, body: dict[str, Any]
) -> None:
    response = _post(app_client, body)
    assert response.status_code == 422, label
    assert "detail" in response.json()
    assert _INSTALL_ID not in response.text
    assert _rows(app_client) == []


def test_a_refused_key_is_named_but_its_value_is_never_echoed(
    app_client: TestClient,
) -> None:
    response = _post(app_client, _with({"note": "SECRET-NOTE-TEXT"}))
    assert response.status_code == 422
    assert "SECRET-NOTE-TEXT" not in response.text
    assert "note" in response.text


def test_a_body_that_is_not_json_is_422(app_client: TestClient) -> None:
    response = app_client.post(
        "/v1/confirmations",
        content=b"not json",
        headers={"X-KetoClub-Install-Id": _INSTALL_ID},
    )
    assert response.status_code == 422


def test_a_422_spends_no_quota() -> None:
    with _client(_settings(CONFIRMATION_RATE_LIMIT_PER_MINUTE=1)) as client:
        for _ in range(5):
            assert _post(client, _with({"note": "x"})).status_code == 422
        assert _post(client).status_code == 201
        assert _post(client, _body(polarity="absent")).status_code == 429


def test_an_oversized_body_is_413(app_client: TestClient) -> None:
    response = _post(app_client, _with({"dishFingerprint": "a" * 10_000}))
    assert response.status_code == 413
    assert response.json() == {"reason": "payloadTooLarge", "status_code": 413}


def test_an_oversized_body_without_a_content_length_is_413(
    app_client: TestClient,
) -> None:
    def chunks() -> Iterator[bytes]:
        yield b'{"padding":"'
        yield b"a" * 3000
        yield b"a" * 3000
        yield b'"}'

    response = app_client.post(
        "/v1/confirmations",
        content=chunks(),
        headers={"X-KetoClub-Install-Id": _INSTALL_ID},
    )
    assert response.status_code == 413


# --- headers and limits ----------------------------------------------------------


def test_a_missing_or_malformed_install_id_is_400(app_client: TestClient) -> None:
    assert _post(app_client, install_id=None).status_code == 400
    assert _post(app_client, install_id="not-an-id").status_code == 400
    assert _rows(app_client) == []


def test_an_authorization_header_is_400(app_client: TestClient) -> None:
    response = app_client.post(
        "/v1/confirmations",
        json=_body(),
        headers={
            "X-KetoClub-Install-Id": _INSTALL_ID,
            "Authorization": "Bearer x",
        },
    )
    assert response.status_code == 400


def test_the_per_install_rate_limit_applies_and_is_per_install() -> None:
    with _client(_settings(CONFIRMATION_RATE_LIMIT_PER_MINUTE=2)) as client:
        assert _post(client, _body(restrictionId="milk")).status_code == 201
        assert _post(client, _body(restrictionId="eggs")).status_code == 201
        limited = _post(client, _body(restrictionId="soy"))
        assert limited.status_code == 429
        assert limited.json() == {"reason": "rateLimited", "status_code": 429}
        # A repeat of a counted fact spends the bucket too: it is a request.
        assert _post(client, _body(restrictionId="milk")).status_code == 429
        # Another install has its own bucket.
        assert _post(client, install_id=_install(7)).status_code == 201
        assert len(_rows(client)) == 3


def test_confirmations_have_a_bucket_of_their_own() -> None:
    settings = _settings(RATE_LIMIT_PER_MINUTE=1, CONFIRMATION_RATE_LIMIT_PER_MINUTE=4)
    with _client(settings) as client:
        for restriction in ("milk", "eggs", "soy", "fish"):
            assert _post(client, _body(restrictionId=restriction)).status_code == 201


def test_the_daily_limit_applies() -> None:
    settings = _settings(CONFIRMATION_RATE_LIMIT_PER_DAY=2)
    with _client(settings) as client:
        assert _post(client, _body(restrictionId="milk")).status_code == 201
        assert _post(client, _body(restrictionId="eggs")).status_code == 201
        assert _post(client, _body(restrictionId="soy")).status_code == 429


def test_when_disabled_the_route_is_not_mounted() -> None:
    with _client(_settings(CONFIRMATIONS_ENABLED=False)) as client:
        assert _post(client).status_code == 404


# --- privacy ---------------------------------------------------------------------


def test_the_install_id_is_never_logged(caplog: pytest.LogCaptureFixture) -> None:
    with (
        caplog.at_level(logging.DEBUG),
        _client(_settings(CONFIRMATION_RATE_LIMIT_PER_MINUTE=2)) as client,
    ):
        _post(client)
        _post(client)
        _post(client, _body(restrictionId="milk"))  # rate limited
        _post(client, _with({"note": "x"}))

    assert caplog.records
    for record in caplog.records:
        rendered = record.getMessage() + " " + json.dumps(record.__dict__, default=str)
        assert _INSTALL_ID not in rendered
        assert _INSTALL_ID[:8] not in rendered
        assert _FINGERPRINT not in rendered
    lines = [
        r.getMessage() for r in caplog.records if r.name == "ketoclub.confirmations"
    ]
    assert "confirmations counted=True polarity=present" in lines
    assert "confirmations counted=False polarity=present" in lines
    assert "confirmations rate limited" in lines


def test_the_install_id_is_in_no_column_of_any_table() -> None:
    with _client(_settings(CONFIRMATION_PEPPER="pepper")) as client:
        _post(client)
        _post(client, _body(polarity="absent"))
        engine = _engine(client)
        seen = 0
        with engine.connect() as connection:
            for table in inspect(engine).get_table_names():
                for row in connection.execute(text(f'SELECT * FROM "{table}"')):
                    seen += 1
                    for value in row:
                        assert _INSTALL_ID not in str(value)
                        assert _INSTALL_ID[:8] not in str(value)
        assert seen >= 4


def test_a_voter_token_cannot_be_joined_to_an_install_or_a_row() -> None:
    with _client(_settings()) as client:
        _post(client)
        _post(client, _body(polarity="absent"))
        _post(client, _body(restrictionId="milk"))
        with Session(_engine(client)) as session:
            tokens = list(session.scalars(select(ConfirmationVoter.token)))
    # One token per fact, all different although one install made them.
    assert len(tokens) == len(set(tokens)) == 3
    assert all(len(token) == 64 for token in tokens)
    assert not any(_INSTALL_ID in token for token in tokens)


def test_voter_token_depends_on_install_pepper_and_every_field() -> None:
    fact: dict[str, str] = {
        "source": "wolt",
        "platform_id": "hamosad",
        "dish_fingerprint": _FINGERPRINT,
        "restriction_id": "sesame",
        "polarity": "present",
    }
    base = confirmations.voter_token("pepper", _INSTALL_ID, **fact)
    assert base == confirmations.voter_token("pepper", _INSTALL_ID, **fact)
    assert base != confirmations.voter_token("other", _INSTALL_ID, **fact)
    assert base != confirmations.voter_token("pepper", _install(2), **fact)
    for key, value in (
        ("source", "tenbis"),
        ("platform_id", "x"),
        ("dish_fingerprint", "f"),
        ("restriction_id", "milk"),
        ("polarity", "absent"),
    ):
        assert base != confirmations.voter_token(
            "pepper", _INSTALL_ID, **{**fact, key: value}
        )
    # Field boundaries cannot be shifted to make two facts collide.
    assert confirmations.voter_token(
        "p", _INSTALL_ID, **{**fact, "source": "a", "platform_id": "bc"}
    ) != confirmations.voter_token(
        "p", _INSTALL_ID, **{**fact, "source": "ab", "platform_id": "c"}
    )


def test_the_pepper_changes_what_counts_as_a_repeat() -> None:
    # The same install under a different pepper is a new confirmer: the pepper
    # is a deployment secret, not something to rotate casually.
    with _client(_settings(CONFIRMATION_PEPPER="one")) as client:
        assert _post(client).status_code == 201
        assert _post(client).status_code == 200


# --- the service ---------------------------------------------------------------


def _record(
    engine: Engine, token: str, today: date, *, polarity: str = "present"
) -> bool:
    return confirmations.record(
        engine,
        source="wolt",
        platform_id="hamosad",
        dish_fingerprint=_FINGERPRINT,
        restriction_id="sesame",
        polarity=polarity,
        token=token,
        today=today,
    )


def test_first_and_last_dates_follow_the_calendar_days_counted(
    app_client: TestClient,
) -> None:
    engine = _engine(app_client)
    assert _record(engine, "t1", date(2026, 5, 12))
    assert _record(engine, "t2", date(2026, 5, 20))
    assert _record(engine, "t3", date(2026, 5, 15))  # out of order
    assert not _record(engine, "t1", date(2026, 6, 1))  # a repeat moves nothing

    (row,) = _rows(app_client)
    assert (row.first_on, row.last_on) == (date(2026, 5, 12), date(2026, 5, 20))
    assert (row.distinct_count, row.submission_count) == (3, 4)


def test_a_lost_insert_race_is_retried_as_a_repeat(
    app_client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    engine = _engine(app_client)
    real: Callable[..., Any] = confirmations._run_in_session
    calls: list[int] = []

    def flaky(eng: Engine, fn: Callable[[Session], Any]) -> Any:
        calls.append(1)
        if len(calls) == 1:
            # The rival's write lands first, then ours collides with it.
            real(eng, fn)
            raise IntegrityError("insert", {}, Exception("duplicate token"))
        return real(eng, fn)

    monkeypatch.setattr(confirmations, "_run_in_session", flaky)
    assert _record(engine, "racer", date(2026, 5, 12)) is False
    monkeypatch.undo()

    (row,) = _rows(app_client)
    assert (row.distinct_count, row.submission_count) == (1, 2)


# --- GET /v1/venue-menus -----------------------------------------------------------


def test_a_venue_nobody_confirmed_has_no_confirmations_key(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    assert "confirmations" not in _venue_menu(app_client)


def test_below_three_distinct_installs_the_key_is_omitted_entirely(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    _confirm_n(app_client, 2)
    # A third post by an install already counted does not make a third person.
    assert _post(app_client, install_id=_install(1)).status_code == 200
    assert _post(app_client, install_id=_install(2)).status_code == 200
    body = _venue_menu(app_client)
    assert "confirmations" not in body
    assert "confirmations" not in json.dumps(body)


def test_three_distinct_installs_show_the_counts(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    _confirm_n(app_client, 3)
    today = date.today().isoformat()  # noqa: DTZ011 - UTC date within a test run

    body = _venue_menu(app_client)
    assert body["confirmations"] == [
        {
            "dishFingerprint": _FINGERPRINT,
            "restrictionId": "sesame",
            "present": 3,
            "absent": 0,
            "first": body["confirmations"][0]["first"],
            "last": body["confirmations"][0]["last"],
        }
    ]
    assert body["confirmations"][0]["first"] <= today <= "9999"
    assert body["confirmations"][0]["first"] == body["confirmations"][0]["last"]


def test_with_classify_false_and_true_the_counts_are_the_same_field(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    _confirm_n(app_client, 3)
    plain = _venue_menu(app_client, "?classify=false")
    assert plain["analysis"] is None
    assert plain["confirmations"][0]["present"] == 3


def test_a_polarity_under_the_threshold_is_never_shown(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    _confirm_n(app_client, 3)
    _confirm_n(app_client, 2, polarity="absent")

    (entry,) = _venue_menu(app_client)["confirmations"]
    assert (entry["present"], entry["absent"]) == (3, 0)

    _confirm_n(app_client, 1, start=3, polarity="absent")  # a third absent
    (entry,) = _venue_menu(app_client)["confirmations"]
    assert (entry["present"], entry["absent"]) == (3, 3)


def test_each_dish_and_restriction_is_its_own_entry_in_a_stable_order(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    _confirm_n(app_client, 3, dishFingerprint="bbbb")
    _confirm_n(app_client, 3, dishFingerprint="aaaa", restrictionId="milk")
    _confirm_n(app_client, 3, dishFingerprint="aaaa", restrictionId="eggs")
    _confirm_n(app_client, 2, dishFingerprint="cccc")  # under the threshold

    entries = _venue_menu(app_client)["confirmations"]
    assert [(e["dishFingerprint"], e["restrictionId"]) for e in entries] == [
        ("aaaa", "eggs"),
        ("aaaa", "milk"),
        ("bbbb", "sesame"),
    ]


def test_another_venues_confirmations_are_not_shown(
    app_client: TestClient, upstream: respx.MockRouter
) -> None:
    _confirm_n(app_client, 3, venue={"source": "wolt", "platform_id": "elsewhere"})
    assert "confirmations" not in _venue_menu(app_client)


def test_when_disabled_the_list_is_never_served() -> None:
    with _client(_settings(CONFIRMATIONS_ENABLED=False)) as client:
        with respx.mock(assert_all_called=False) as router:
            router.get(_WOLT_URL).respond(
                200,
                json=golden_entry("wolt_menu.json", "synthetic_options_and_labels")[
                    "raw"
                ],
            )
            assert "confirmations" not in _venue_menu(client)


def test_a_failing_lookup_never_fails_the_menu(
    app_client: TestClient,
    upstream: respx.MockRouter,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def boom(*_: object) -> None:
        raise RuntimeError("database is gone")

    monkeypatch.setattr(confirmations, "visible_for", boom)
    body = _venue_menu(app_client)
    assert "confirmations" not in body
    assert body["menu"]


def test_the_openapi_page_declares_the_body_and_the_counts(
    app_client: TestClient,
) -> None:
    spec = app_client.get("/openapi.json").json()
    operation = spec["paths"]["/v1/confirmations"]["post"]
    schema = operation["requestBody"]["content"]["application/json"]["schema"]
    assert set(schema["required"]) == {
        "venue",
        "dishFingerprint",
        "restrictionId",
        "polarity",
    }
    assert (
        "confirmations"
        in spec["components"]["schemas"]["VenueMenuResponse"]["properties"]
    )
