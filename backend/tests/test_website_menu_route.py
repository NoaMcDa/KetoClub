"""Tests for ``POST /v1/website-menu`` (D19, D25, #334).

The pages are the golden website corpus (``website.json``, exported from the
Dart reader over ``test/fixtures/website/``); every site, robots.txt and
Gemini is a respx route nested inside the autouse network block from
``conftest``, and DNS is a stub table. Nothing leaves the sandbox.
"""

import base64
import json
import logging
from collections.abc import Iterator
from contextlib import contextmanager
from typing import Any

import httpx
import pytest
import respx
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import Settings
from app.keto.models import Menu, to_json
from app.keto.vocabulary import vocabulary
from app.main import create_app
from app.models import StoredMenu
from app.schemas import WebsiteMenuResponse
from app.services import menu_store
from app.website.ref import normalise_website_url, website_ref
from tests.analysis_support import (
    GEMINI_URL,
    HEADERS,
    INSTALL_ID,
    KEY,
    MODEL_VERSION,
    all_green_reply,
    database_text,
    gemini_answer,
    golden_entry,
    settings,
)

_PATH = "/v1/website-menu"
_SITE = "https://cafe-noir.example"
_HOME = f"{_SITE}/"
_PUBLIC = "93.184.216.34"
_OPTIONS = {"netCarbLimitGrams": 6, "dietaryConstraints": []}
_PDF_URL = "https://files.example-cdn.com/cafe-noir/Menu-2026.pdf?v=3"
_PDF = b"%PDF-1.7\n" + b"a menu " * 16
_PDF_B64 = base64.b64encode(_PDF).decode()
_VISION_REPLY = json.dumps(
    {
        "dishes": [
            {
                "id": "",
                "name": "Grilled salmon",
                "verdict": "orderAsIs",
                "why": "Plain protein.",
                "modification": None,
                "net_carbs_estimate": 1,
                "hidden_carbs": [],
                "page": 1,
            }
        ]
    }
)


class _FakeClock:
    def __call__(self) -> float:
        return 1000.0


@contextmanager
def _client(
    app_settings: Settings, addresses: dict[str, list[str]] | None = None
) -> Iterator[TestClient]:
    app = create_app(settings=app_settings)
    table = addresses or {}

    async def resolve(host: str) -> list[str]:
        return table.get(host, [_PUBLIC])

    app.state.resolve_host = resolve
    app.state.website_clock = _FakeClock()
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def web() -> Iterator[respx.MockRouter]:
    with respx.mock(assert_all_called=False) as router:
        router.get(f"{_SITE}/robots.txt").respond(404)
        router.get("https://files.example-cdn.com/robots.txt").respond(404)
        yield router


@pytest.fixture
def app_client() -> Iterator[TestClient]:
    with _client(settings()) as test_client:
        yield test_client


def _page(name: str) -> str:
    return str(golden_entry("website.json", name)["html"])


def _html(body: str, **headers: str) -> httpx.Response:
    return httpx.Response(
        200,
        content=body.encode(),
        headers={"content-type": "text/html; charset=utf-8", **headers},
    )


def _pdf() -> httpx.Response:
    return httpx.Response(
        200, content=_PDF, headers={"content-type": "application/pdf"}
    )


def _post(
    test_client: TestClient,
    url: str = _SITE,
    options: Any = None,
    headers: dict[str, str] | None = None,
) -> httpx.Response:
    return test_client.post(
        _PATH,
        json={"url": url, "options": options or _OPTIONS},
        headers=HEADERS if headers is None else headers,
    )


def _stored(test_client: TestClient) -> list[StoredMenu]:
    app: Any = test_client.app
    with Session(app.state.engine) as session:
        rows = list(session.scalars(select(StoredMenu)))
        session.expunge_all()
    return rows


def _assert_round_trips(body: dict[str, Any]) -> None:
    assert to_json(WebsiteMenuResponse.model_validate(body)) == body


# --- the ref ------------------------------------------------------------------


@pytest.mark.parametrize(
    ("raw", "normalised"),
    [
        ("https://Cafe-Noir.Example/", "https://cafe-noir.example"),
        ("  https://cafe-noir.example  ", "https://cafe-noir.example"),
        (
            "HTTP://cafe-noir.example:80/menu/?a=1#top",
            "http://cafe-noir.example/menu?a=1",
        ),
        ("https://cafe-noir.example:8443/x/", "https://cafe-noir.example:8443/x"),
        (
            "https://cafe-noir.example/תפריט/",
            "https://cafe-noir.example/%D7%AA%D7%A4%D7%A8%D7%99%D7%98",
        ),
        ("https://8.8.8.8/", "https://8.8.8.8"),
        ("ftp://cafe-noir.example/", None),
        ("https://localhost/", None),
        ("https://cafe.local/", None),
        ("https://10.0.0.1/", None),
        ("https://1.2.3/", None),
        ("https://999.1.1.1/", None),
        ("https://user@cafe-noir.example/", None),
        ("https://.cafe-noir.example/", None),
        ("https:// bad", None),
        ("http://[bad", None),
    ],
)
def test_a_website_url_is_normalised_as_the_app_does(
    raw: str, normalised: str | None
) -> None:
    assert normalise_website_url(raw) == normalised
    ref = website_ref(raw)
    if normalised is None:
        assert ref is None
    else:
        assert ref is not None
        assert (ref.source, ref.platform_id) == ("website", normalised)


# --- a menu in the page itself ------------------------------------------------


def test_a_json_ld_menu_is_read_and_classified_by_the_rules_without_a_key(
    web: respx.MockRouter,
) -> None:
    web.get(_HOME).mock(return_value=_html(_page("jsonld_menu.html")))
    gemini = web.post(GEMINI_URL).respond(500)
    with _client(settings(GEMINI_API_KEY="")) as test_client:
        response = _post(test_client)
        rows = _stored(test_client)

    assert response.status_code == 200
    body = response.json()
    _assert_round_trips(body)
    entry = golden_entry("website.json", "jsonld_menu.html")
    assert body["menu"]["categories"] == entry["located"]["categories"]
    assert body["menu"]["venueRef"] == {"source": "website", "platformId": _SITE}
    assert body["menu"]["currency"] == "ILS"
    assert body["menu"]["venueName"] is None
    assert body["analysis"]["engine"] == {"kind": "rules", "reason": "notConfigured"}
    assert body["analysis"]["schemaVersion"] == 1
    assert body["analysis"]["options"] == _OPTIONS
    assert not gemini.called
    assert [(row.source, row.platform_id) for row in rows] == [("website", _SITE)]


def test_an_llm_analysis_is_cached_and_stored_without_options_or_install_id(
    app_client: TestClient,
    web: respx.MockRouter,
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.DEBUG)
    web.get(_HOME).mock(return_value=_html(_page("jsonld_menu.html")))
    entry = golden_entry("website.json", "jsonld_menu.html")
    menu = Menu.model_validate(
        {
            "venueRef": {"source": "website", "platformId": _SITE},
            "currency": "ILS",
            "fetchedAt": "2026-01-01T00:00:00.000Z",
            "categories": entry["located"]["categories"],
        }
    )
    gemini = web.post(GEMINI_URL).respond(
        200, json=gemini_answer(all_green_reply(menu))
    )

    first = _post(app_client)
    second = _post(app_client)

    assert first.status_code == 200
    assert first.headers["X-KetoClub-Cache"] == "miss"
    assert second.headers["X-KetoClub-Cache"] == "hit"
    assert gemini.call_count == 1
    body = first.json()
    _assert_round_trips(body)
    assert body["analysis"]["engine"] == {"kind": "llm", "model": MODEL_VERSION}
    assert body["analysis"]["options"] == _OPTIONS
    assert body["analysis"]["schemaVersion"] == 1

    rows = _stored(app_client)
    assert len(rows) == 1
    assert rows[0].submission_count == 2
    assert rows[0].venue_name is None
    stored_analysis = json.loads(rows[0].analysis_json or "{}")
    assert "options" not in stored_analysis
    assert stored_analysis["engine"] == {"kind": "llm", "model": MODEL_VERSION}
    assert json.loads(rows[0].menu_json)["venueRef"]["platformId"] == _SITE

    app: Any = app_client.app
    assert INSTALL_ID not in database_text(app.state.engine)
    assert INSTALL_ID[:8] not in caplog.text
    assert KEY not in caplog.text
    ours = "\n".join(
        record.getMessage()
        for record in caplog.records
        if record.name.startswith("ketoclub")
    )
    assert "https://cafe-noir.example" not in ours


def test_an_empty_analysis_bucket_keeps_the_menu_with_the_rules(
    web: respx.MockRouter,
) -> None:
    web.get(_HOME).mock(return_value=_html(_page("jsonld_menu.html")))
    gemini = web.post(GEMINI_URL).respond(500)
    with _client(settings(ANALYSIS_RATE_LIMIT_PER_MINUTE=0)) as test_client:
        response = _post(test_client)

    assert response.status_code == 200
    assert response.json()["analysis"]["engine"] == {
        "kind": "rules",
        "reason": "rateLimited",
    }
    assert not gemini.called


def test_a_gemini_failure_on_a_text_menu_is_the_rules_with_its_reason(
    app_client: TestClient, web: respx.MockRouter
) -> None:
    web.get(_HOME).mock(return_value=_html(_page("jsonld_menu.html")))
    web.post(GEMINI_URL).mock(side_effect=httpx.ReadTimeout("slow"))

    response = _post(app_client)

    assert response.status_code == 200
    assert response.json()["analysis"]["engine"] == {
        "kind": "rules",
        "reason": "timeout",
    }


def test_a_json_ld_menu_with_no_dish_is_menu_not_found(
    app_client: TestClient, web: respx.MockRouter
) -> None:
    page = (
        '<script type="application/ld+json">'
        '{"@type": "Menu", "hasMenuSection": [{"name": "Empty"}]}'
        "</script><p>Welcome</p>"
    )
    web.get(_HOME).mock(return_value=_html(page))

    response = _post(app_client)

    assert response.json() == {"reason": "menuNotFound", "status_code": 404}
    assert _stored(app_client) == []


def test_the_menu_store_is_not_written_when_disabled(web: respx.MockRouter) -> None:
    web.get(_HOME).mock(return_value=_html(_page("jsonld_menu.html")))
    with _client(settings(GEMINI_API_KEY="", MENU_STORE_ENABLED=False)) as test_client:
        response = _post(test_client)
        rows = _stored(test_client)

    assert response.json()["analysis"] is not None
    assert rows == []


def test_a_store_failure_never_fails_the_read(
    app_client: TestClient,
    web: respx.MockRouter,
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    def broken(*_args: object, **_kwargs: object) -> None:
        raise RuntimeError("database gone")

    monkeypatch.setattr(menu_store, "upsert", broken)
    web.get(_HOME).mock(return_value=_html(_page("jsonld_menu.html")))
    web.post(GEMINI_URL).respond(500)

    response = _post(app_client)

    assert response.status_code == 200
    assert "website_menu store failed" in caplog.text


# --- one link hop -------------------------------------------------------------


def test_a_menu_link_is_followed_once_and_its_page_read(
    app_client: TestClient, web: respx.MockRouter
) -> None:
    web.get(_HOME).mock(return_value=_html(_page("menu_link.html")))
    linked = web.get(f"{_SITE}/food/menu/").mock(
        return_value=_html(_page("menu_page_inline_prices.html"))
    )
    web.post(GEMINI_URL).respond(500)

    response = _post(app_client)

    assert response.status_code == 200
    assert linked.call_count == 1
    body = response.json()
    _assert_round_trips(body)
    entry = golden_entry("website.json", "menu_page_inline_prices.html")
    assert body["menu"]["categories"] == entry["textMenu"]["categories"]
    assert body["menu"]["venueRef"] == {"source": "website", "platformId": _SITE}
    assert body["analysis"]["engine"] == {"kind": "rules", "reason": "badResponse"}


def test_a_linked_page_is_never_followed_further(
    app_client: TestClient, web: respx.MockRouter
) -> None:
    web.get(_HOME).mock(return_value=_html(_page("menu_link.html")))
    # The linked page links to a menu again, and holds none itself.
    web.get(f"{_SITE}/food/menu/").mock(return_value=_html(_page("menu_link.html")))

    response = _post(app_client)

    assert response.json() == {"reason": "menuNotFound", "status_code": 404}
    assert len(web.calls) == 3  # robots.txt, the page, the linked page


def test_every_fetch_spends_the_install_website_budget(
    web: respx.MockRouter,
) -> None:
    web.get(_HOME).mock(return_value=_html(_page("menu_link.html")))
    web.get(f"{_SITE}/food/menu/").mock(
        return_value=_html(_page("menu_page_inline_prices.html"))
    )
    web.post(GEMINI_URL).respond(500)
    with _client(settings(WEBSITE_RATE_LIMIT_PER_MINUTE=3)) as test_client:
        first = _post(test_client)
        # One fetch left: the page, then the link hop is refused, and the
        # page has no text of its own to fall back on.
        second = _post(test_client)
        third = _post(test_client)

    assert first.status_code == 200
    assert second.json() == {"reason": "rateLimited", "status_code": 429}
    assert third.json() == {"reason": "rateLimited", "status_code": 429}


def test_the_link_hop_spends_the_site_budget_too(web: respx.MockRouter) -> None:
    web.get(_HOME).mock(return_value=_html(_page("menu_link.html")))
    web.get(f"{_SITE}/food/menu/").mock(
        return_value=_html(_page("menu_page_inline_prices.html"))
    )
    with _client(
        settings(GEMINI_API_KEY="", WEBSITE_HOST_RATE_LIMIT_PER_MINUTE=1)
    ) as test_client:
        response = _post(test_client)

    assert response.json() == {"reason": "rateLimited", "status_code": 429}


def test_a_failed_link_falls_back_to_the_pages_own_text(
    app_client: TestClient, web: respx.MockRouter
) -> None:
    web.get(_HOME).mock(return_value=_html(_page("menu_page_separate_prices.html")))
    web.get(f"{_SITE}/menu").respond(404)
    web.post(GEMINI_URL).respond(500)

    response = _post(app_client)

    assert response.status_code == 200
    entry = golden_entry("website.json", "menu_page_separate_prices.html")
    assert response.json()["menu"]["categories"] == entry["textMenu"]["categories"]


@pytest.mark.parametrize(
    ("linked", "status", "reason"),
    [
        (httpx.Response(404), 404, "notFound"),
        (httpx.Response(503), 502, "upstreamStatus"),
        (httpx.ConnectError("down"), 502, "offline"),
        (_html(_page("no_menu.html")), 404, "menuNotFound"),
        (_html(_page("inline_js_only_script")), 422, "jsOnlyPage"),
        (_html(_page("inline_reserves_ai_robots")), 403, "aiReserved"),
        (_html("<p>x</p>", **{"X-Robots-Tag": "noai"}), 403, "aiReserved"),
    ],
    ids=[
        "not_found",
        "upstream_status",
        "offline",
        "no_menu",
        "js_only",
        "meta_noai",
        "header_noai",
    ],
)
def test_with_no_text_to_fall_back_on_the_links_failure_is_the_answer(
    app_client: TestClient,
    web: respx.MockRouter,
    linked: httpx.Response | Exception,
    status: int,
    reason: str,
) -> None:
    web.get(_HOME).mock(return_value=_html(_page("menu_link.html")))
    web.get(f"{_SITE}/food/menu/").mock(
        **(
            {"side_effect": linked}
            if isinstance(linked, Exception)
            else {"return_value": linked}
        )
    )

    response = _post(app_client)

    assert response.json() == {"reason": reason, "status_code": status}


# --- PDF menus ----------------------------------------------------------------


def test_a_linked_pdf_is_read_through_the_scan_path(
    app_client: TestClient, web: respx.MockRouter
) -> None:
    web.get(_HOME).mock(return_value=_html(_page("pdf_link.html")))
    pdf = web.get(_PDF_URL).mock(return_value=_pdf())
    gemini = web.post(GEMINI_URL).respond(200, json=gemini_answer(_VISION_REPLY))

    response = _post(app_client)

    assert response.status_code == 200
    assert response.headers["X-KetoClub-Cache"] == "bypass"
    assert pdf.call_count == 1
    body = response.json()
    _assert_round_trips(body)
    assert body["menu"]["venueRef"] == {"source": "website", "platformId": _SITE}
    assert body["menu"]["currency"] == "ILS"
    dishes = body["menu"]["categories"][0]["dishes"]
    assert [(d["id"], d["name"], d["page"]) for d in dishes] == [
        ("v1", "Grilled salmon", 1)
    ]
    assert body["analysis"]["engine"] == {"kind": "llm", "model": MODEL_VERSION}
    assert body["analysis"]["options"] == _OPTIONS
    assert body["analysis"]["schemaVersion"] == 1
    assert body["menu"]["fetchedAt"] == body["analysis"]["analysedAt"]
    parts = json.loads(gemini.calls.last.request.content)["contents"][0]["parts"]
    assert parts[1:] == [
        {"inline_data": {"mime_type": "application/pdf", "data": _PDF_B64}}
    ]
    rows = _stored(app_client)
    assert [(row.source, row.platform_id) for row in rows] == [("website", _SITE)]


def test_a_pasted_pdf_is_read_through_the_scan_path(
    app_client: TestClient, web: respx.MockRouter
) -> None:
    web.get(f"{_SITE}/menu.pdf").mock(return_value=_pdf())
    web.post(GEMINI_URL).respond(200, json=gemini_answer(_VISION_REPLY))

    response = _post(app_client, url=f"{_SITE}/menu.pdf")

    assert response.status_code == 200
    assert response.json()["menu"]["venueRef"] == {
        "source": "website",
        "platformId": f"{_SITE}/menu.pdf",
    }


def test_a_pdf_scan_spends_the_analysis_bucket(web: respx.MockRouter) -> None:
    web.get(f"{_SITE}/menu.pdf").mock(return_value=_pdf())
    gemini = web.post(GEMINI_URL).respond(200, json=gemini_answer(_VISION_REPLY))
    with _client(settings(ANALYSIS_RATE_LIMIT_PER_MINUTE=1)) as test_client:
        first = _post(test_client, url=f"{_SITE}/menu.pdf")
        second = _post(test_client, url=f"{_SITE}/menu.pdf")

    assert first.status_code == 200
    assert second.json() == {"reason": "rateLimited", "status_code": 502}
    assert gemini.call_count == 1


@pytest.mark.parametrize(
    ("gemini_answer_or_error", "status", "reason"),
    [
        (httpx.Response(500), 502, "badResponse"),
        (httpx.Response(429), 502, "rateLimited"),
        (httpx.Response(403), 502, "notConfigured"),
        (httpx.ConnectError("down"), 502, "offline"),
        (httpx.ReadTimeout("slow"), 502, "timeout"),
        (httpx.Response(200, json=gemini_answer("not json")), 502, "badResponse"),
        (
            httpx.Response(200, json=gemini_answer('{"dishes": []}')),
            422,
            "noDishesFound",
        ),
    ],
    ids=[
        "upstream_500",
        "upstream_429",
        "upstream_403",
        "offline",
        "timeout",
        "not_json",
        "no_dishes",
    ],
)
def test_a_pdf_that_could_not_be_read_is_the_scan_reason(
    app_client: TestClient,
    web: respx.MockRouter,
    gemini_answer_or_error: httpx.Response | Exception,
    status: int,
    reason: str,
) -> None:
    web.get(_HOME).mock(return_value=_html(_page("pdf_link.html")))
    web.get(_PDF_URL).mock(return_value=_pdf())
    route = web.post(GEMINI_URL)
    if isinstance(gemini_answer_or_error, Exception):
        route.mock(side_effect=gemini_answer_or_error)
    else:
        route.mock(return_value=gemini_answer_or_error)

    response = _post(app_client)

    assert response.json() == {"reason": reason, "status_code": status}
    assert _stored(app_client) == []


def test_a_pdf_with_no_server_key_is_502_not_configured(
    web: respx.MockRouter,
) -> None:
    web.get(f"{_SITE}/menu.pdf").mock(return_value=_pdf())
    gemini = web.post(GEMINI_URL).respond(500)
    with _client(settings(GEMINI_API_KEY="")) as test_client:
        response = _post(test_client, url=f"{_SITE}/menu.pdf")

    assert response.json() == {"reason": "notConfigured", "status_code": 502}
    assert not gemini.called


def test_a_pdf_larger_than_a_vision_page_is_too_large(web: respx.MockRouter) -> None:
    web.get(f"{_SITE}/menu.pdf").mock(return_value=_pdf())
    gemini = web.post(GEMINI_URL).respond(500)
    with _client(settings(VISION_MAX_IMAGE_BYTES=16)) as test_client:
        response = _post(test_client, url=f"{_SITE}/menu.pdf")

    assert response.json() == {"reason": "tooLarge", "status_code": 413}
    assert not gemini.called


def test_a_failed_pdf_link_falls_back_to_the_pages_own_text(
    app_client: TestClient, web: respx.MockRouter
) -> None:
    page = _page("menu_page_inline_prices.html").replace(
        "</body>", '<a href="/files/menu.pdf">Menu</a></body>'
    )
    web.get(_HOME).mock(return_value=_html(page))
    web.get(f"{_SITE}/files/menu.pdf").mock(return_value=_pdf())
    web.post(GEMINI_URL).respond(500)

    response = _post(app_client)

    assert response.status_code == 200
    entry = golden_entry("website.json", "menu_page_inline_prices.html")
    assert response.json()["menu"]["categories"] == entry["textMenu"]["categories"]
    assert response.json()["analysis"]["engine"]["kind"] == "rules"


# --- the page's own failures --------------------------------------------------


@pytest.mark.parametrize(
    ("name", "status", "reason"),
    [
        ("no_menu.html", 404, "menuNotFound"),
        ("inline_js_only_script", 422, "jsOnlyPage"),
        ("inline_js_only_noscript", 422, "jsOnlyPage"),
        ("inline_reserves_ai_robots", 403, "aiReserved"),
        ("inline_reserves_ai_tdm", 403, "aiReserved"),
        ("inline_too_few_prices", 404, "menuNotFound"),
    ],
)
def test_a_page_with_nothing_readable_is_its_reason(
    app_client: TestClient,
    web: respx.MockRouter,
    name: str,
    status: int,
    reason: str,
) -> None:
    web.get(_HOME).mock(return_value=_html(_page(name)))

    response = _post(app_client)

    assert response.json() == {"reason": reason, "status_code": status}


def test_json_ld_is_read_before_the_javascript_only_test(
    app_client: TestClient, web: respx.MockRouter
) -> None:
    page = _page("jsonld_menu.html").replace(
        "<body>", '<body><div id="root"></div><script src="app.js"></script>'
    )
    web.get(_HOME).mock(return_value=_html(page))
    web.post(GEMINI_URL).respond(500)

    response = _post(app_client)

    assert response.status_code == 200


@pytest.mark.parametrize(
    ("answer", "status", "reason"),
    [
        (httpx.Response(404), 404, "notFound"),
        (httpx.Response(410), 404, "notFound"),
        (httpx.Response(500), 502, "upstreamStatus"),
        (
            httpx.Response(
                200, content=b"\x89PNG", headers={"content-type": "image/png"}
            ),
            415,
            "unsupportedContent",
        ),
        (_html("<p>menu</p>", **{"X-Robots-Tag": "noai"}), 403, "aiReserved"),
        (_html("<p>menu</p>", **{"tdm-reservation": "1"}), 403, "aiReserved"),
        (httpx.ConnectError("down"), 502, "offline"),
        (httpx.ReadTimeout("slow"), 504, "timeout"),
    ],
    ids=[
        "not_found",
        "gone",
        "upstream_status",
        "unsupported",
        "header_noai",
        "header_tdm",
        "offline",
        "timeout",
    ],
)
def test_a_fetch_failure_is_the_website_fetch_reason(
    app_client: TestClient,
    web: respx.MockRouter,
    answer: httpx.Response | Exception,
    status: int,
    reason: str,
) -> None:
    route = web.get(_HOME)
    if isinstance(answer, Exception):
        route.mock(side_effect=answer)
    else:
        route.mock(return_value=answer)

    response = _post(app_client)

    assert response.json() == {"reason": reason, "status_code": status}


def test_robots_txt_is_honoured() -> None:
    with respx.mock(assert_all_called=False) as site:
        site.get(f"{_SITE}/robots.txt").respond(
            200, text="User-agent: ketoclubbot\nDisallow: /\n"
        )
        page = site.get(_HOME).mock(return_value=_html(_page("jsonld_menu.html")))
        with _client(settings()) as test_client:
            response = _post(test_client)

    assert response.json() == {"reason": "disallowedByRobots", "status_code": 403}
    assert not page.called


def test_a_redirect_is_followed_within_the_hygiene(
    app_client: TestClient, web: respx.MockRouter
) -> None:
    web.get(_HOME).respond(301, headers={"location": "/en/"})
    web.get(f"{_SITE}/en/").mock(return_value=_html(_page("jsonld_menu.html")))
    web.post(GEMINI_URL).respond(500)

    response = _post(app_client)

    assert response.status_code == 200
    # The ref is the pasted URL, not where it redirected to.
    assert response.json()["menu"]["venueRef"]["platformId"] == _SITE


def test_a_private_address_is_never_fetched(web: respx.MockRouter) -> None:
    page = web.get(_HOME).mock(return_value=_html(_page("jsonld_menu.html")))
    with _client(settings(), {"cafe-noir.example": ["10.0.0.7"]}) as test_client:
        response = _post(test_client)

    assert response.json() == {"reason": "invalidUrl", "status_code": 400}
    assert not page.called


@pytest.mark.parametrize(
    "url",
    [
        "ftp://cafe-noir.example/",
        "https://localhost/",
        "https://10.0.0.1/",
        "https://user:pw@cafe-noir.example/",
        "not a url",
        "https://cafe-noir.example:8443/",
    ],
)
def test_a_url_that_is_no_public_website_is_400_before_any_fetch(
    app_client: TestClient, web: respx.MockRouter, url: str
) -> None:
    response = _post(app_client, url=url)

    assert response.json() == {"reason": "invalidUrl", "status_code": 400}
    assert not web.calls


# --- the request --------------------------------------------------------------


@pytest.mark.parametrize(
    "headers",
    [
        {},
        {"X-KetoClub-Install-Id": "NOT-HEX"},
        {**HEADERS, "Authorization": "Bearer x"},
    ],
    ids=["missing_install_id", "malformed_install_id", "authorization_header"],
)
def test_a_refused_header_is_400(
    app_client: TestClient, web: respx.MockRouter, headers: dict[str, str]
) -> None:
    response = _post(app_client, headers=headers)

    assert response.json() == {"reason": "badResponse", "status_code": 400}
    assert not web.calls


@pytest.mark.parametrize(
    "body",
    [
        {"url": "", "options": _OPTIONS},
        {"url": "https://x.example/" + "a" * 2048, "options": _OPTIONS},
        {"url": _SITE, "options": {"netCarbLimitGrams": 0, "dietaryConstraints": []}},
        {
            "url": _SITE,
            "options": {"netCarbLimitGrams": 6, "dietaryConstraints": ["be nice"]},
        },
        {"url": _SITE},
    ],
    ids=["empty_url", "long_url", "limit_zero", "unknown_constraint", "no_options"],
)
def test_a_malformed_body_is_422(
    app_client: TestClient, web: respx.MockRouter, body: dict[str, Any]
) -> None:
    response = app_client.post(_PATH, json=body, headers=HEADERS)

    assert response.status_code == 422
    assert "be nice" not in response.text
    assert not web.calls


def test_the_options_come_back_on_the_analysis(
    app_client: TestClient, web: respx.MockRouter
) -> None:
    web.get(_HOME).mock(return_value=_html(_page("jsonld_menu.html")))
    web.post(GEMINI_URL).respond(500)
    fragment = vocabulary().prompt.seed_oil_free_prompt_fragment
    options = {"netCarbLimitGrams": 12, "dietaryConstraints": [fragment]}

    response = _post(app_client, options=options)

    assert response.status_code == 200
    assert response.json()["analysis"]["options"] == options
