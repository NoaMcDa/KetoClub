"""Tests for ``POST /v1/website/fetch`` (D19, #181). respx only; no network."""

import base64
import logging
from collections.abc import AsyncIterator, Iterator

import httpx
import pytest
import respx
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app

_INSTALL_ID = "0123456789abcdef0123456789abcdef"
_PATH = "/v1/website/fetch"
_SITE = "https://cafe.example"
_HOME = f"{_SITE}/"
_ROBOTS = f"{_SITE}/robots.txt"
_PUBLIC = "93.184.216.34"

_MENU_PAGE = (
    "<html><head><title>Cafe</title></head><body><h1>Menu</h1>"
    + "".join(f"<p>Dish {i} with a long description 52</p>" for i in range(20))
    + "</body></html>"
)
_PDF = b"%PDF-1.7\n" + b"x" * 64


class FakeClock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


def _build(
    settings: Settings, addresses: dict[str, list[str]] | None = None
) -> FastAPI:
    app = create_app(settings=settings)
    table = addresses or {}

    async def resolve(host: str) -> list[str]:
        if host in table:
            return table[host]
        return [_PUBLIC]

    app.state.resolve_host = resolve
    app.state.website_clock = FakeClock()
    return app


@pytest.fixture
def web() -> Iterator[respx.MockRouter]:
    with respx.mock(assert_all_called=False) as router:
        yield router


@pytest.fixture
def site_client(settings: Settings) -> Iterator[TestClient]:
    with TestClient(_build(settings)) as test_client:
        yield test_client


def _post(
    client: TestClient, url: str = _HOME, install_id: str | None = _INSTALL_ID
) -> httpx.Response:
    headers = {} if install_id is None else {"X-KetoClub-Install-Id": install_id}
    return client.post(_PATH, json={"url": url}, headers=headers)


def _no_robots(web: respx.MockRouter, site: str = _SITE) -> None:
    web.get(f"{site}/robots.txt").mock(return_value=httpx.Response(404))


def _html(body: str = _MENU_PAGE, **headers: str) -> httpx.Response:
    return httpx.Response(
        200,
        content=body.encode(),
        headers={"content-type": "text/html; charset=utf-8", **headers},
    )


def _reason(response: httpx.Response) -> str:
    return str(response.json()["reason"])


# --- success ----------------------------------------------------------------


def test_html_page_is_returned_with_its_final_url(
    site_client: TestClient, web: respx.MockRouter
) -> None:
    _no_robots(web)
    route = web.get(_HOME).mock(return_value=_html())

    response = _post(site_client)

    assert response.status_code == 200
    body = response.json()
    assert body["kind"] == "html"
    assert body["final_url"] == _HOME
    assert "Dish 3" in body["body"]
    assert body["content_type"].startswith("text/html")
    sent = route.calls.last.request
    assert sent.headers["user-agent"].startswith("KetoClubBot/1.0 (+https://")
    assert "cookie" not in sent.headers
    assert "x-ketoclub-install-id" not in sent.headers


def test_an_unknown_charset_still_answers_200_with_the_decoded_page(
    site_client: TestClient, web: respx.MockRouter
) -> None:
    _no_robots(web)
    web.get(_HOME).mock(
        return_value=httpx.Response(
            200,
            content=_MENU_PAGE.encode(),
            headers={"content-type": "text/html; charset=x-bogus-charset"},
        )
    )

    response = _post(site_client)

    assert response.status_code == 200
    body = response.json()
    assert body["kind"] == "html"
    assert "Dish 3" in body["body"]


def test_bytes_that_do_not_match_the_declared_charset_never_500(
    site_client: TestClient, web: respx.MockRouter
) -> None:
    _no_robots(web)
    page = _MENU_PAGE.replace("Menu", "תפריט", 1).encode("windows-1255")
    web.get(_HOME).mock(
        return_value=httpx.Response(
            200,
            content=page,
            headers={"content-type": "text/html; charset=utf-8"},
        )
    )

    response = _post(site_client)

    assert response.status_code == 200
    assert response.json()["kind"] == "html"
    assert "Dish 3" in response.json()["body"]


def test_pdf_is_returned_as_base64(
    site_client: TestClient, web: respx.MockRouter
) -> None:
    _no_robots(web)
    web.get(f"{_SITE}/menu.pdf").mock(
        return_value=httpx.Response(
            200, content=_PDF, headers={"content-type": "application/pdf"}
        )
    )

    response = _post(site_client, f"{_SITE}/menu.pdf")

    assert response.status_code == 200
    body = response.json()
    assert body["kind"] == "pdf"
    assert body["content_type"] == "application/pdf"
    assert base64.b64decode(body["body"]) == _PDF


def test_pdf_is_recognised_by_its_signature(
    site_client: TestClient, web: respx.MockRouter
) -> None:
    _no_robots(web)
    web.get(f"{_SITE}/download").mock(
        return_value=httpx.Response(
            200, content=_PDF, headers={"content-type": "application/octet-stream"}
        )
    )

    assert _post(site_client, f"{_SITE}/download").json()["kind"] == "pdf"


def test_a_redirect_is_followed_and_reported(
    site_client: TestClient, web: respx.MockRouter
) -> None:
    _no_robots(web)
    web.get(_HOME).mock(
        return_value=httpx.Response(301, headers={"location": "/he/menu"})
    )
    web.get(f"{_SITE}/he/menu").mock(return_value=_html())

    response = _post(site_client)

    assert response.status_code == 200
    assert response.json()["final_url"] == f"{_SITE}/he/menu"


def test_a_legacy_charset_is_decoded(
    site_client: TestClient, web: respx.MockRouter
) -> None:
    _no_robots(web)
    page = "<p>" + "סלט יווני 48 " * 30 + "</p>"
    web.get(_HOME).mock(
        return_value=httpx.Response(
            200,
            content=page.encode("windows-1255"),
            headers={"content-type": "text/html; charset=windows-1255"},
        )
    )

    assert "סלט יווני" in _post(site_client).json()["body"]


# --- robots.txt -------------------------------------------------------------


def test_robots_disallow_refuses_without_fetching_the_page(
    site_client: TestClient, web: respx.MockRouter
) -> None:
    web.get(_ROBOTS).mock(
        return_value=httpx.Response(200, text="User-agent: *\nDisallow: /\n")
    )
    page = web.get(_HOME).mock(return_value=_html())

    response = _post(site_client)

    assert response.status_code == 403
    assert _reason(response) == "disallowedByRobots"
    assert not page.called


def test_robots_allow_lets_the_page_through(
    site_client: TestClient, web: respx.MockRouter
) -> None:
    web.get(_ROBOTS).mock(
        return_value=httpx.Response(
            200, text="User-agent: *\nDisallow: /admin\nAllow: /\n"
        )
    )
    web.get(_HOME).mock(return_value=_html())

    assert _post(site_client).status_code == 200


def test_a_failing_robots_txt_refuses_to_fetch(
    site_client: TestClient, web: respx.MockRouter
) -> None:
    web.get(_ROBOTS).mock(return_value=httpx.Response(503))
    page = web.get(_HOME).mock(return_value=_html())

    response = _post(site_client)

    assert response.status_code == 502
    assert _reason(response) == "offline"
    assert not page.called


def test_an_unreachable_robots_txt_is_offline_or_timeout(
    site_client: TestClient, web: respx.MockRouter
) -> None:
    web.get(_ROBOTS).mock(side_effect=httpx.ConnectError("down"))
    assert _reason(_post(site_client)) == "offline"


def test_a_slow_robots_txt_is_a_timeout(settings: Settings) -> None:
    with (
        TestClient(_build(settings)) as client,
        respx.mock(assert_all_called=False) as web,
    ):
        web.get(_ROBOTS).mock(side_effect=httpx.ReadTimeout("slow"))
        response = _post(client)
    assert response.status_code == 504
    assert _reason(response) == "timeout"


def test_robots_txt_is_cached_per_host(
    site_client: TestClient, web: respx.MockRouter
) -> None:
    robots = web.get(_ROBOTS).mock(return_value=httpx.Response(200, text=""))
    web.get(_HOME).mock(return_value=_html())
    web.get(f"{_SITE}/menu").mock(return_value=_html())

    assert _post(site_client).status_code == 200
    assert _post(site_client, f"{_SITE}/menu").status_code == 200
    assert robots.call_count == 1


def test_robots_cache_expires(settings: Settings) -> None:
    app = _build(settings)
    with TestClient(app) as client, respx.mock(assert_all_called=False) as web:
        robots = web.get(_ROBOTS).mock(return_value=httpx.Response(404))
        web.get(_HOME).mock(return_value=_html())
        _post(client)
        app.state.website_clock.now += settings.WEBSITE_ROBOTS_TTL_SECONDS + 1
        _post(client)
    assert robots.call_count == 2


# --- AI opt-outs and JavaScript-only pages -----------------------------------


@pytest.mark.parametrize(
    "headers",
    [{"X-Robots-Tag": "noai"}, {"tdm-reservation": "1"}],
)
def test_ai_reservation_headers_refuse(
    site_client: TestClient, web: respx.MockRouter, headers: dict[str, str]
) -> None:
    _no_robots(web)
    web.get(_HOME).mock(return_value=_html(**headers))

    response = _post(site_client)

    assert response.status_code == 403
    assert _reason(response) == "aiReserved"


def test_ai_reservation_meta_refuses(
    site_client: TestClient, web: respx.MockRouter
) -> None:
    _no_robots(web)
    page = _MENU_PAGE.replace("<head>", '<head><meta name="robots" content="noai">')
    web.get(_HOME).mock(return_value=_html(page))

    assert _reason(_post(site_client)) == "aiReserved"


def test_a_javascript_only_page_fails_with_its_own_reason(
    site_client: TestClient, web: respx.MockRouter
) -> None:
    _no_robots(web)
    shell = '<html><body><div id="app"></div><script src="/a.js"></script>'
    web.get(_HOME).mock(return_value=_html(shell))

    response = _post(site_client)

    assert response.status_code == 422
    assert _reason(response) == "jsOnlyPage"


# --- limits -----------------------------------------------------------------


def test_the_per_host_limit_refuses_the_extra_fetch(settings: Settings) -> None:
    settings.WEBSITE_HOST_RATE_LIMIT_PER_MINUTE = 2
    with (
        TestClient(_build(settings)) as client,
        respx.mock(assert_all_called=False) as web,
    ):
        _no_robots(web)
        web.get(_HOME).mock(return_value=_html())
        _no_robots(web, "https://other.example")
        web.get("https://other.example/").mock(return_value=_html())

        assert _post(client).status_code == 200
        assert _post(client).status_code == 200
        third = _post(client)
        other = _post(client, "https://other.example/")

    assert third.status_code == 429
    assert _reason(third) == "rateLimited"
    assert other.status_code == 200


def test_the_per_install_limit_refuses(settings: Settings) -> None:
    settings.WEBSITE_RATE_LIMIT_PER_MINUTE = 1
    with (
        TestClient(_build(settings)) as client,
        respx.mock(assert_all_called=False) as web,
    ):
        _no_robots(web)
        web.get(_HOME).mock(return_value=_html())
        assert _post(client).status_code == 200
        assert _reason(_post(client)) == "rateLimited"


def test_a_declared_oversize_body_is_refused(
    site_client: TestClient, web: respx.MockRouter
) -> None:
    _no_robots(web)
    web.get(_HOME).mock(
        return_value=httpx.Response(
            200,
            content=b"<p>x</p>",
            headers={"content-type": "text/html", "content-length": "999999999"},
        )
    )

    response = _post(site_client)

    assert response.status_code == 413
    assert _reason(response) == "tooLarge"


def test_an_oversize_html_page_is_refused(settings: Settings) -> None:
    settings.WEBSITE_MAX_HTML_BYTES = 100
    settings.WEBSITE_MAX_PDF_BYTES = 10_000
    with (
        TestClient(_build(settings)) as client,
        respx.mock(assert_all_called=False) as web,
    ):
        _no_robots(web)
        web.get(_HOME).mock(return_value=_html())
        response = _post(client)
    assert _reason(response) == "tooLarge"


def test_an_undeclared_oversize_stream_is_cut_off(settings: Settings) -> None:
    settings.WEBSITE_MAX_HTML_BYTES = 100
    settings.WEBSITE_MAX_PDF_BYTES = 100

    async def chunks() -> AsyncIterator[bytes]:
        for _ in range(10):
            yield b"<p>" + b"x" * 40 + b"</p>"

    with (
        TestClient(_build(settings)) as client,
        respx.mock(assert_all_called=False) as web,
    ):
        _no_robots(web)
        web.get(_HOME).mock(
            return_value=httpx.Response(
                200, content=chunks(), headers={"content-type": "text/html"}
            )
        )
        response = _post(client)
    assert response.status_code == 413
    assert _reason(response) == "tooLarge"


# --- request validation -----------------------------------------------------


@pytest.mark.parametrize(
    "url",
    [
        "ftp://cafe.example/menu",
        "https://user:pw@cafe.example/",
        "https://cafe.example:8080/",
        "https://cafe.example:notaport/",
        "not a url",
    ],
)
def test_an_unusable_url_is_invalid(site_client: TestClient, url: str) -> None:
    response = _post(site_client, url)
    assert response.status_code == 400
    assert _reason(response) == "invalidUrl"


def test_a_missing_install_id_is_refused(site_client: TestClient) -> None:
    assert _post(site_client, install_id=None).status_code == 400


@pytest.mark.parametrize("address", ["127.0.0.1", "10.1.2.3", "169.254.169.254"])
def test_a_private_address_is_never_fetched(settings: Settings, address: str) -> None:
    app = _build(settings, {"intranet.example": [address]})
    with TestClient(app) as client, respx.mock(assert_all_called=False) as web:
        page = web.get("https://intranet.example/").mock(return_value=_html())
        response = _post(client, "https://intranet.example/")
    assert _reason(response) == "invalidUrl"
    assert not page.called


def test_a_redirect_to_a_private_address_is_refused(settings: Settings) -> None:
    app = _build(settings, {"intranet.example": ["192.168.0.1"]})
    with TestClient(app) as client, respx.mock(assert_all_called=False) as web:
        _no_robots(web)
        web.get(_HOME).mock(
            return_value=httpx.Response(
                302, headers={"location": "http://intranet.example/admin"}
            )
        )
        response = _post(client)
    assert _reason(response) == "invalidUrl"


def test_an_unresolvable_host_is_offline(settings: Settings) -> None:
    app = _build(settings, {"gone.example": []})
    with TestClient(app) as client:
        assert _reason(_post(client, "https://gone.example/")) == "offline"


def test_a_resolver_error_is_offline(settings: Settings) -> None:
    app = _build(settings)

    async def broken(host: str) -> list[str]:
        raise OSError("dns down")

    app.state.resolve_host = broken
    with TestClient(app) as client:
        assert _reason(_post(client)) == "offline"


# --- upstream failures ------------------------------------------------------


@pytest.mark.parametrize(
    ("upstream", "status", "reason"),
    [
        (httpx.Response(404), 404, "notFound"),
        (httpx.Response(410), 404, "notFound"),
        (httpx.Response(500), 502, "upstreamStatus"),
        (httpx.Response(403), 502, "upstreamStatus"),
        (
            httpx.Response(
                200, content=b"\x89PNG", headers={"content-type": "image/png"}
            ),
            415,
            "unsupportedContent",
        ),
    ],
)
def test_upstream_answers_map_to_reasons(
    site_client: TestClient,
    web: respx.MockRouter,
    upstream: httpx.Response,
    status: int,
    reason: str,
) -> None:
    _no_robots(web)
    web.get(_HOME).mock(return_value=upstream)

    response = _post(site_client)

    assert response.status_code == status
    assert _reason(response) == reason


def test_a_connect_error_is_offline(
    site_client: TestClient, web: respx.MockRouter
) -> None:
    _no_robots(web)
    web.get(_HOME).mock(side_effect=httpx.ConnectError("refused"))
    response = _post(site_client)
    assert response.status_code == 502
    assert _reason(response) == "offline"


def test_a_timeout_is_timeout(site_client: TestClient, web: respx.MockRouter) -> None:
    _no_robots(web)
    web.get(_HOME).mock(side_effect=httpx.ReadTimeout("slow"))
    response = _post(site_client)
    assert response.status_code == 504
    assert _reason(response) == "timeout"


def test_endless_redirects_give_up(
    site_client: TestClient, web: respx.MockRouter
) -> None:
    _no_robots(web)
    web.get(_HOME).mock(return_value=httpx.Response(302, headers={"location": "/"}))
    response = _post(site_client)
    assert response.status_code == 502
    assert _reason(response) == "upstreamStatus"


# --- logging ----------------------------------------------------------------


def test_logs_carry_the_host_and_never_the_path(
    site_client: TestClient,
    web: respx.MockRouter,
    caplog: pytest.LogCaptureFixture,
) -> None:
    _no_robots(web)
    web.get(f"{_SITE}/secret-menu-path").mock(return_value=_html())
    web.get(f"{_SITE}/blocked-path").mock(return_value=httpx.Response(404))

    with caplog.at_level(logging.INFO, logger="ketoclub.website"):
        _post(site_client, f"{_SITE}/secret-menu-path?token=abc")
        _post(site_client, f"{_SITE}/blocked-path")

    lines = [r.getMessage() for r in caplog.records if r.name == "ketoclub.website"]
    assert lines == [
        "website fetch host=cafe.example outcome=html",
        "website fetch host=cafe.example outcome=notFound",
    ]
    assert not any("secret" in line or "token" in line for line in lines)
