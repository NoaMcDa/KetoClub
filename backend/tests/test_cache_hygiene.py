"""Backend cache hygiene (#272): bounded in-memory maps, expired rows
deleted, no empty discovery body cached, robots rules matched on
normalised escapes. respx only; no network."""

from collections.abc import Iterator
from datetime import UTC, datetime, timedelta

import httpx
import pytest
import respx
from fastapi.testclient import TestClient
from sqlalchemy import Engine, func, select
from sqlalchemy.orm import Session

from app.config import Settings
from app.db import build_engine
from app.models import AnalysisCache, Base, ChatCache, MenuCache
from app.services import rate_limit, website_fetch
from app.services.cache_purge import purge_expired
from app.services.rate_limit import RateLimiter
from app.services.website import RobotsRules, normalise_escapes, parse_robots

_NOW = datetime(2026, 11, 13, 12, 0, 0)


class FakeClock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


# --- the rate limiter's map -------------------------------------------------------


def test_a_refused_id_with_no_hit_is_never_stored() -> None:
    limiter = RateLimiter(per_minute=0, per_day=10, clock=FakeClock())

    assert limiter.allow("a" * 32) is False
    assert len(limiter) == 0


def test_ids_idle_for_a_day_are_swept(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(rate_limit, "SWEEP_EVERY", 4)
    clock = FakeClock()
    limiter = RateLimiter(per_minute=10, per_day=100, clock=clock)
    for name in "abc":
        limiter.allow(name * 32)
    assert len(limiter) == 3

    clock.now += 86400
    limiter.allow("d" * 32)  # the fourth check sweeps

    assert len(limiter) == 1


def test_the_map_never_holds_more_than_max_ids() -> None:
    limiter = RateLimiter(per_minute=10, per_day=100, clock=FakeClock(), max_ids=3)
    for index in range(10):
        assert limiter.allow(f"{index:032x}") is True

    assert len(limiter) == 3


def test_a_limited_id_stays_limited_while_others_come_and_go() -> None:
    limiter = RateLimiter(per_minute=1, per_day=100, clock=FakeClock(), max_ids=3)
    assert limiter.allow("a" * 32) is True
    limiter.allow("b" * 32)
    # "a" asked again: it moves to the most recent end and is not evicted.
    assert limiter.allow("a" * 32) is False
    limiter.allow("c" * 32)

    assert limiter.allow("a" * 32) is False


# --- the robots cache -------------------------------------------------------------


def test_the_robots_cache_is_bounded(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(website_fetch, "ROBOTS_CACHE_MAX_HOSTS", 3)
    cache: dict[str, tuple[float, RobotsRules]] = {}
    for index in range(5):
        website_fetch._remember(
            cache, f"https://h{index}", (float(index), RobotsRules()), 10.0, 3600
        )

    assert list(cache) == ["https://h2", "https://h3", "https://h4"]


def test_expired_robots_entries_go_before_fresh_ones(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(website_fetch, "ROBOTS_CACHE_MAX_HOSTS", 3)
    cache: dict[str, tuple[float, RobotsRules]] = {
        "https://fresh": (5000.0, RobotsRules()),
        "https://old-1": (0.0, RobotsRules()),
        "https://old-2": (0.0, RobotsRules()),
    }

    website_fetch._remember(cache, "https://new", (5000.0, RobotsRules()), 5000.0, 3600)

    assert list(cache) == ["https://fresh", "https://new"]


# --- robots percent-escapes ---------------------------------------------------------


@pytest.mark.parametrize("path", ["/%6denu", "/%6Denu/today", "/men%75"])
def test_an_escaped_path_does_not_slip_past_a_disallow(path: str) -> None:
    rules = parse_robots("User-agent: *\nDisallow: /menu\n")

    assert rules.allows(path) is False


def test_an_escaped_rule_matches_the_plain_path() -> None:
    rules = parse_robots("User-agent: *\nDisallow: /%6Denu\n")

    assert rules.allows("/menu") is False
    assert rules.allows("/about") is True


def test_reserved_escapes_stay_escaped_and_compare_case_insensitively() -> None:
    rules = parse_robots("User-agent: *\nDisallow: /a%2fb\n")

    assert rules.allows("/a%2Fb") is False
    assert rules.allows("/a/b") is True
    assert normalise_escapes("/a%2fb") == "/a%2Fb"


def test_non_ascii_rules_match_their_utf8_escapes() -> None:
    rules = parse_robots("User-agent: *\nDisallow: /תפריט\n")

    assert rules.allows("/%D7%AA%D7%A4%D7%A8%D7%99%D7%98") is False
    assert normalise_escapes("/\ud800") == "/%ED%A0%80"


# --- expired rows -------------------------------------------------------------------


@pytest.fixture
def engine() -> Iterator[Engine]:
    built = build_engine(Settings(DATABASE_URL="sqlite:///:memory:"))
    Base.metadata.create_all(built)
    yield built
    built.dispose()


def _count(engine: Engine, model: type[Base]) -> int:
    with Session(engine) as session:
        return int(session.scalar(select(func.count()).select_from(model)) or 0)


def test_expired_rows_are_deleted_and_fresh_ones_kept(engine: Engine) -> None:
    settings = Settings(DATABASE_URL="sqlite:///:memory:")
    old = _NOW - timedelta(days=30)
    with Session(engine) as session, session.begin():
        for stamp, suffix in ((old, "old"), (_NOW, "new")):
            session.add(
                ChatCache(
                    key=f"chat-{suffix}",
                    content="{}",
                    model="m",
                    created_at=stamp,
                )
            )
            session.add(
                AnalysisCache(
                    key=f"analysis-{suffix}", analysis_json="{}", created_at=stamp
                )
            )
            session.add(
                MenuCache(
                    source="wolt",
                    slug=f"menu-{suffix}",
                    status_code=200,
                    content_type="application/json",
                    body="{}",
                    fetched_at=stamp,
                )
            )

    removed = purge_expired(engine, settings, _NOW.replace(tzinfo=UTC))

    assert removed == 3
    assert _count(engine, ChatCache) == 1
    assert _count(engine, AnalysisCache) == 1
    assert _count(engine, MenuCache) == 1


# --- discovery never caches an empty body --------------------------------------------


@pytest.fixture
def wolt() -> Iterator[respx.MockRouter]:
    with respx.mock(assert_all_called=False) as router:
        yield router


def test_an_empty_discovery_body_is_not_cached(
    client: TestClient, wolt: respx.MockRouter
) -> None:
    route = wolt.get("https://consumer-api.wolt.com/v1/pages/restaurants").mock(
        side_effect=[
            httpx.Response(200, content=b""),
            httpx.Response(200, json={"sections": []}),
        ]
    )
    headers = {"X-KetoClub-Install-Id": "0123456789abcdef0123456789abcdef"}
    params = {"lat": 32.07, "lon": 34.77}

    first = client.get(
        "/v1/proxy/wolt/pages/restaurants", params=params, headers=headers
    )
    second = client.get(
        "/v1/proxy/wolt/pages/restaurants", params=params, headers=headers
    )

    assert first.headers["X-KetoClub-Cache"] == "miss"
    assert second.headers["X-KetoClub-Cache"] == "miss"
    assert second.json() == {"sections": []}
    assert route.call_count == 2
