"""#269 and #268's time budget: every website read is bounded in bytes and in
time. respx only; no network.

The issue's reproductions, each now a test:

- a 400 KB gzip robots.txt that inflates to 400 MB raised peak memory by
  1.6 GB and still answered 200 (here: 64 MiB, and the peak stays a few MiB);
- one 64 KiB gzip chunk could inflate to 64 MiB before the page cap was
  looked at (here: the inflater never runs more than a byte past the cap);
- a server dripping a byte every 3 s held a request for 42 s (here: the
  whole fetch ends at ``WEBSITE_FETCH_DEADLINE_SECONDS``, robots.txt too).
"""

import asyncio
import gzip
import time
import tracemalloc
import zlib
from collections.abc import AsyncIterator, Callable, Iterator

import httpx
import pytest
import respx
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.config import Settings
from app.errors import BackendError
from app.main import create_app
from app.services import website_fetch
from app.services.website_fetch import _BodyDecoder
from tests.website_network import PUBLIC, FakeNetwork, http_response, passing_through

_INSTALL_ID = "0123456789abcdef0123456789abcdef"
_SITE = "https://cafe.example"
_HOME = f"{_SITE}/"
_ROBOTS = f"{_SITE}/robots.txt"
_MIB = 1024 * 1024
_MENU_PAGE = (
    "<html><body><h1>Menu</h1>"
    + "".join(f"<p>Dish {i} with a long description 52</p>" for i in range(20))
    + "</body></html>"
)


def _settings(**overrides: object) -> Settings:
    return Settings(DATABASE_URL="sqlite:///:memory:", **overrides)  # type: ignore[arg-type]


def _build(settings: Settings) -> FastAPI:
    app = create_app(settings=settings)

    async def resolve(host: str) -> list[str]:
        return ["93.184.216.34"]

    app.state.resolve_host = resolve
    return app


@pytest.fixture
def web() -> Iterator[respx.MockRouter]:
    with respx.mock(assert_all_called=False) as router:
        yield router


def _post(client: TestClient, url: str = _HOME) -> httpx.Response:
    return client.post(
        "/v1/website/fetch",
        json={"url": url},
        headers={"X-KetoClub-Install-Id": _INSTALL_ID},
    )


def _bomb(prefix: bytes, inflated: int, wbits: int = zlib.MAX_WBITS | 16) -> bytes:
    """``prefix`` and then newlines up to ``inflated`` bytes, compressed
    without ever holding the inflated body."""
    deflater = zlib.compressobj(9, zlib.DEFLATED, wbits)
    out = [deflater.compress(prefix)]
    block = b"\n" * _MIB
    for _ in range(inflated // _MIB):
        out.append(deflater.compress(block))
    out.append(deflater.flush())
    return b"".join(out)


def _peak_during(work: Callable[[], httpx.Response]) -> tuple[httpx.Response, int]:
    tracemalloc.start()
    try:
        response = work()
        return response, tracemalloc.get_traced_memory()[1]
    finally:
        tracemalloc.stop()


# --- robots.txt is streamed under its cap -----------------------------------


def test_a_robots_txt_gzip_bomb_is_read_only_up_to_its_cap() -> None:
    # Through the real pool and stream (respx would buffer the body itself).
    bomb = _bomb(b"User-agent: *\nDisallow: /\n", 64 * _MIB)
    network = FakeNetwork(
        {PUBLIC: http_response("200 OK", bomb, content_encoding="gzip")}
    )
    app = _build(_settings())
    app.state.website_network_backend = network

    with passing_through("cafe.example"), TestClient(app) as client:
        response, peak = _peak_during(lambda: _post(client))

    # The rules at the top still apply, the page is never asked for, and
    # 64 MiB was never inflated.
    assert response.status_code == 403
    assert response.json()["reason"] == "disallowedByRobots"
    assert network.dialled == [PUBLIC]
    assert peak < 8 * _MIB


def test_robots_txt_past_its_cap_is_cut_there(web: respx.MockRouter) -> None:
    # A Disallow past the cap is never read, so the page is fetched.
    head = b"User-agent: *\n" + b"#" * 600
    web.get(_ROBOTS).mock(
        return_value=httpx.Response(200, content=head + b"\nDisallow: /\n")
    )
    web.get(_HOME).mock(return_value=httpx.Response(200, html=_MENU_PAGE))

    with TestClient(_build(_settings(WEBSITE_MAX_ROBOTS_BYTES=512))) as client:
        response = _post(client)

    assert response.status_code == 200


def test_a_robots_txt_that_breaks_off_mid_body_is_offline(
    web: respx.MockRouter,
) -> None:
    async def broken() -> AsyncIterator[bytes]:
        yield b"User-agent: *\n"
        raise httpx.ReadError("connection reset")

    web.get(_ROBOTS).mock(return_value=httpx.Response(200, content=broken()))

    with TestClient(_build(_settings())) as client:
        response = _post(client)

    assert response.status_code == 502
    assert response.json()["reason"] == "offline"


# --- the page is inflated a capped amount at a time -------------------------


def test_a_page_gzip_bomb_is_refused_without_being_inflated() -> None:
    bomb = _bomb(b"<html><body>", 64 * _MIB)
    network = FakeNetwork(
        {
            PUBLIC: http_response(
                "200 OK", bomb, content_type="text/html", content_encoding="gzip"
            )
        }
    )
    app = _build(_settings(WEBSITE_MAX_HTML_BYTES=64 * 1024))
    app.state.website_network_backend = network
    # robots.txt gets the same bomb: no rules in it, and capped as well.

    with passing_through("cafe.example"), TestClient(app) as client:
        response, peak = _peak_during(lambda: _post(client))

    assert response.status_code == 413
    assert response.json()["reason"] == "tooLarge"
    assert peak < 8 * _MIB


def test_a_gzip_page_under_its_cap_reads_as_before(web: respx.MockRouter) -> None:
    web.get(_ROBOTS).mock(return_value=httpx.Response(404))
    web.get(_HOME).mock(
        return_value=httpx.Response(
            200,
            content=gzip.compress(_MENU_PAGE.encode()),
            headers={"content-type": "text/html", "content-encoding": "gzip"},
        )
    )

    with TestClient(_build(_settings())) as client:
        response = _post(client)

    assert response.status_code == 200
    assert response.json()["body"] == _MENU_PAGE


@pytest.mark.parametrize("wbits", [zlib.MAX_WBITS, -zlib.MAX_WBITS])
def test_deflate_with_or_without_its_zlib_header_reads(
    web: respx.MockRouter, wbits: int
) -> None:
    deflater = zlib.compressobj(9, zlib.DEFLATED, wbits)
    body = deflater.compress(_MENU_PAGE.encode()) + deflater.flush()
    web.get(_ROBOTS).mock(return_value=httpx.Response(404))
    web.get(_HOME).mock(
        return_value=httpx.Response(
            200,
            content=body,
            headers={"content-type": "text/html", "content-encoding": "deflate"},
        )
    )

    with TestClient(_build(_settings())) as client:
        response = _post(client)

    assert response.status_code == 200
    assert response.json()["body"] == _MENU_PAGE


def test_the_fetcher_asks_only_for_codings_it_can_bound(
    web: respx.MockRouter,
) -> None:
    web.get(_ROBOTS).mock(return_value=httpx.Response(404))
    page = web.get(_HOME).mock(return_value=httpx.Response(200, html=_MENU_PAGE))

    with TestClient(_build(_settings())) as client:
        _post(client)

    assert page.calls.last.request.headers["accept-encoding"] == "gzip, deflate"


def test_the_decoder_never_inflates_more_than_a_byte_past_its_room() -> None:
    chunk = _bomb(b"", 64 * _MIB)[: 64 * 1024]
    decoder = _BodyDecoder("gzip")
    assert len(decoder.decode(chunk, 1000)) == 1001


@pytest.mark.parametrize(
    ("coding", "data", "expected"),
    [
        ("", b"plain", b"plain"),
        ("identity", b"plain", b"plain"),
        ("GZIP", gzip.compress(b"page"), b"page"),
        ("x-gzip", gzip.compress(b"page"), b"page"),
        ("gzip, identity", gzip.compress(b"page"), b"page"),
    ],
)
def test_the_decoder_reads_the_codings_it_knows(
    coding: str, data: bytes, expected: bytes
) -> None:
    assert _BodyDecoder(coding).decode(data, 1000) == expected


@pytest.mark.parametrize("coding", ["br", "zstd", "gzip, gzip", "compress"])
def test_any_other_coding_is_unsupported(coding: str) -> None:
    with pytest.raises(BackendError) as raised:
        _BodyDecoder(coding)
    assert (raised.value.status_code, raised.value.reason) == (
        415,
        "unsupportedContent",
    )


@pytest.mark.parametrize("coding", ["gzip", "deflate"])
def test_a_corrupt_body_is_offline(coding: str) -> None:
    decoder = _BodyDecoder(coding)
    with pytest.raises(BackendError) as raised:
        decoder.decode(b"\xff" * 64, 1000)
    assert (raised.value.status_code, raised.value.reason) == (502, "offline")


def test_a_deflate_body_corrupt_after_its_first_chunk_is_offline() -> None:
    deflater = zlib.compressobj(9, zlib.DEFLATED, zlib.MAX_WBITS)
    body = deflater.compress(_MENU_PAGE.encode()) + deflater.flush()
    decoder = _BodyDecoder("deflate")
    decoder.decode(body[:10], 10_000)
    with pytest.raises(BackendError):
        decoder.decode(b"\xff" * 64, 10_000)


# --- one deadline per fetch -------------------------------------------------


async def _drip() -> AsyncIterator[bytes]:
    """A byte every 50 ms, well inside any read timeout, for six seconds:
    without the deadline the request lasts all six (for ever, from a real
    server); with it, half a second."""
    yield b"<html><body>"
    for _ in range(120):
        await asyncio.sleep(0.05)
        yield b" "


def test_a_page_dripping_a_byte_at_a_time_hits_the_deadline(
    web: respx.MockRouter,
) -> None:
    web.get(_ROBOTS).mock(return_value=httpx.Response(404))
    web.get(_HOME).mock(
        return_value=httpx.Response(
            200, content=_drip(), headers={"content-type": "text/html"}
        )
    )

    with TestClient(_build(_settings(WEBSITE_FETCH_DEADLINE_SECONDS=0.5))) as client:
        started = time.monotonic()
        response = _post(client)
        elapsed = time.monotonic() - started

    assert response.status_code == 504
    assert response.json()["reason"] == "timeout"
    assert elapsed < 4


def test_a_dripping_robots_txt_hits_the_same_deadline(web: respx.MockRouter) -> None:
    web.get(_ROBOTS).mock(return_value=httpx.Response(200, content=_drip()))
    page = web.get(_HOME).mock(return_value=httpx.Response(200, html=_MENU_PAGE))

    with TestClient(_build(_settings(WEBSITE_FETCH_DEADLINE_SECONDS=0.5))) as client:
        started = time.monotonic()
        response = _post(client)
        elapsed = time.monotonic() - started

    assert response.status_code == 504
    assert response.json()["reason"] == "timeout"
    assert not page.called
    assert elapsed < 4


# --- parsing runs off the loop, under a budget (#268) -----------------------


def test_a_page_judge_over_its_budget_is_a_timeout(
    web: respx.MockRouter, monkeypatch: pytest.MonkeyPatch
) -> None:
    def stuck(page: str) -> bool:
        time.sleep(5)
        return False

    monkeypatch.setattr(website_fetch, "looks_javascript_only", stuck)
    web.get(_ROBOTS).mock(return_value=httpx.Response(404))
    web.get(_HOME).mock(return_value=httpx.Response(200, html=_MENU_PAGE))

    with TestClient(_build(_settings(WEBSITE_PARSE_BUDGET_SECONDS=0.2))) as client:
        started = time.monotonic()
        response = _post(client)
        elapsed = time.monotonic() - started

    assert response.status_code == 504
    assert response.json()["reason"] == "timeout"
    assert elapsed < 4


def test_the_page_judge_runs_in_a_worker_thread(
    web: respx.MockRouter, monkeypatch: pytest.MonkeyPatch
) -> None:
    import threading

    threads: list[str] = []

    def spy(page: str) -> bool:
        threads.append(threading.current_thread().name)
        return False

    monkeypatch.setattr(website_fetch, "looks_javascript_only", spy)
    web.get(_ROBOTS).mock(return_value=httpx.Response(404))
    web.get(_HOME).mock(return_value=httpx.Response(200, html=_MENU_PAGE))

    with TestClient(_build(_settings())) as client:
        loop_thread = client.portal.call(lambda: threading.current_thread().name)  # type: ignore[union-attr]
        response = _post(client)

    assert response.status_code == 200
    assert threads and threads[0] != loop_thread


def test_a_website_menu_reading_over_its_budget_is_a_timeout(
    web: respx.MockRouter, monkeypatch: pytest.MonkeyPatch
) -> None:
    from app.routers import website_menu

    def stuck(*args: object, **kwargs: object) -> object:
        time.sleep(5)
        raise AssertionError("never answered")

    monkeypatch.setattr(website_menu, "read_page", stuck)
    web.get(_ROBOTS).mock(return_value=httpx.Response(404))
    web.get(_HOME).mock(return_value=httpx.Response(200, html=_MENU_PAGE))

    with TestClient(_build(_settings(WEBSITE_PARSE_BUDGET_SECONDS=0.2))) as client:
        started = time.monotonic()
        response = client.post(
            "/v1/website-menu",
            json={"url": _HOME, "options": {"netCarbLimitGrams": 20}},
            headers={"X-KetoClub-Install-Id": _INSTALL_ID},
        )
        elapsed = time.monotonic() - started

    assert response.status_code == 504
    assert response.json()["reason"] == "timeout"
    assert elapsed < 4
