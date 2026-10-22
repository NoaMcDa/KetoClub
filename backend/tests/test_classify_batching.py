"""A menu too large for one request is classified in batches (#188).

``app.services.classify`` splits the menu with ``app.keto.batching`` (the
Dart split's twin, pinned by ``batches.json``), sends one Gemini request per
batch in order, and merges the replies as ``LlmMenuClassifier`` does on the
device. Gemini is a respx route that answers each request from the dish
lines of its own user prompt, so every batch is placed by what it was sent.
"""

import json
from collections.abc import Callable, Iterator
from typing import Any

import httpx
import pytest
import respx
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.keto.batching import ANALYSIS_BATCH_MAX_DISHES, split_batches
from app.keto.models import AnalysisOptionsSnapshot, Menu, MenuAnalysed
from app.keto.prompt import user_prompt
from app.models import AnalysisCache
from app.schemas import USER_PROMPT_MAX_CHARS
from app.services.classify import ClassifyContext, classify
from tests.analysis_support import (
    GEMINI_URL,
    HEADERS,
    INSTALL_ID,
    MODEL_VERSION,
    client,
    gemini_answer,
    golden,
    settings,
)

_LARGE: dict[str, Any] = golden("batches.json")["menus"]["large"]
_MENU = Menu.model_validate(_LARGE)
_OPTIONS = {"netCarbLimitGrams": 6, "dietaryConstraints": []}
_EXTRACT = {**_OPTIONS, "restrictionsRequested": True}
_BATCHES = split_batches(
    _MENU, max_dishes=ANALYSIS_BATCH_MAX_DISHES, max_chars=USER_PROMPT_MAX_CHARS
)


def _sent_prompt(request: httpx.Request) -> str:
    body = json.loads(request.content)
    text: str = body["contents"][0]["parts"][0]["text"]
    return text


def _green_reply_for(prompt_text: str) -> str:
    """Every dish line of ``prompt_text`` placed as ``orderAsIs``."""
    dishes = []
    for line in prompt_text.split("\n"):
        dish_id, _category, name, *_rest = line.split(" | ")
        dishes.append(
            {
                "id": dish_id,
                "name": name,
                "verdict": "orderAsIs",
                "why": "Plain protein.",
                "modification": None,
                "net_carbs_estimate": 1,
                "hidden_carbs": [],
            }
        )
    return json.dumps({"dishes": dishes}, ensure_ascii=False)


def _answering(
    failures: dict[int, httpx.Response | Exception] | None = None,
) -> Callable[[httpx.Request], httpx.Response]:
    """A respx side effect: the n-th call (from 1) answers ``failures[n]``
    when given, and otherwise places every dish its prompt names."""
    calls = {"n": 0}

    def answer(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        failure = (failures or {}).get(calls["n"])
        if isinstance(failure, Exception):
            raise failure
        if failure is not None:
            return failure
        return httpx.Response(
            200, json=gemini_answer(_green_reply_for(_sent_prompt(request)))
        )

    return answer


@pytest.fixture
def gemini() -> Iterator[respx.MockRouter]:
    with respx.mock(assert_all_called=False) as router:
        yield router


def _post(
    test_client: TestClient, options: dict[str, Any] | None = None
) -> httpx.Response:
    return test_client.post(
        "/v1/classify",
        content=json.dumps({"menu": _LARGE, "options": options or _OPTIONS}),
        headers={"Content-Type": "application/json", **HEADERS},
    )


def _cached_rows(test_client: TestClient) -> int | None:
    with Session(test_client.app.state.engine) as session:  # type: ignore[attr-defined]
        return session.scalar(select(func.count()).select_from(AnalysisCache))


def _names(batch: Menu) -> list[str]:
    return [dish.name for dish in batch.all_dishes()]


def test_the_large_menu_splits_in_three() -> None:
    assert [len(batch.all_dishes()) for batch in _BATCHES] == [67, 67, 66]


def test_a_large_menu_is_one_request_per_batch_merged_in_order(
    gemini: respx.MockRouter,
) -> None:
    route = gemini.post(GEMINI_URL).mock(side_effect=_answering())
    with client(settings()) as test_client:
        response = _post(test_client)
        again = _post(test_client)
        rows = _cached_rows(test_client)

    assert response.status_code == 200
    assert response.headers["X-KetoClub-Cache"] == "miss"
    analysis = response.json()["analysis"]
    assert analysis["engine"] == {"kind": "llm", "model": MODEL_VERSION}
    assert [dish["dishId"] for dish in analysis["dishes"]] == [
        dish.id for dish in _MENU.all_dishes()
    ]
    assert analysis["unclassified"] == []
    assert analysis["options"] == _OPTIONS
    assert analysis["schemaVersion"] == 1
    assert MenuAnalysed.model_validate(analysis)
    # One request per batch, in order, each carrying exactly its batch.
    assert [_sent_prompt(call.request) for call in route.calls[:3]] == [
        user_prompt(batch) for batch in _BATCHES
    ]
    # A complete merge is cached like any analysis: the repeat is free.
    assert route.call_count == 3
    assert again.headers["X-KetoClub-Cache"] == "hit"
    assert rows == 1


@pytest.mark.parametrize(
    "failure",
    [
        httpx.Response(503, json={"error": {"status": "UNAVAILABLE"}}),
        httpx.ReadTimeout("slow"),
        httpx.Response(200, json=gemini_answer("not json at all")),
    ],
    ids=["upstream_error", "timeout", "unusable_reply"],
)
def test_one_failed_batch_of_three_is_its_dishes_unclassified(
    gemini: respx.MockRouter, failure: httpx.Response | Exception
) -> None:
    route = gemini.post(GEMINI_URL).mock(side_effect=_answering({2: failure}))
    with client(settings()) as test_client:
        response = _post(test_client)
        rows = _cached_rows(test_client)

    assert response.status_code == 200
    # Partial: still the model's answer, but never cached.
    assert response.headers["X-KetoClub-Cache"] == "bypass"
    analysis = response.json()["analysis"]
    assert analysis["engine"] == {"kind": "llm", "model": MODEL_VERSION}
    placed = [dish["dishId"] for dish in analysis["dishes"]]
    assert placed == [
        dish.id for batch in (_BATCHES[0], _BATCHES[2]) for dish in batch.all_dishes()
    ]
    assert analysis["unclassified"] == _names(_BATCHES[1])
    assert route.call_count == 3
    assert rows == 0


def test_every_batch_failing_is_the_rules_with_the_first_reason(
    gemini: respx.MockRouter,
) -> None:
    gemini.post(GEMINI_URL).mock(
        side_effect=_answering(
            {
                1: httpx.ReadTimeout("slow"),
                2: httpx.Response(200, json=gemini_answer("nope")),
                3: httpx.Response(200, json=gemini_answer("nope")),
            }
        )
    )
    with client(settings()) as test_client:
        response = _post(test_client)

    assert response.status_code == 200
    analysis = response.json()["analysis"]
    assert analysis["engine"] == {"kind": "rules", "reason": "timeout"}
    assert len(analysis["dishes"]) == len(_MENU.all_dishes())


@pytest.mark.parametrize(
    ("failure", "reason"),
    [
        (httpx.Response(429), "rateLimited"),
        (httpx.ConnectError("no route"), "offline"),
        (httpx.Response(403), "notConfigured"),
    ],
)
def test_a_menu_wide_failure_mid_menu_stops_and_is_the_rules(
    gemini: respx.MockRouter, failure: httpx.Response | Exception, reason: str
) -> None:
    route = gemini.post(GEMINI_URL).mock(side_effect=_answering({2: failure}))
    with client(settings()) as test_client:
        response = _post(test_client)

    assert response.status_code == 200
    analysis = response.json()["analysis"]
    assert analysis["engine"] == {"kind": "rules", "reason": reason}
    assert analysis["unclassified"] == []
    # The third batch is never sent.
    assert route.call_count == 2


def test_an_empty_bucket_mid_menu_is_429_after_the_calls_it_allowed(
    gemini: respx.MockRouter,
) -> None:
    route = gemini.post(GEMINI_URL).mock(side_effect=_answering())
    with client(settings(ANALYSIS_RATE_LIMIT_PER_MINUTE=2)) as test_client:
        response = _post(test_client)

    assert response.status_code == 429
    assert response.json() == {"reason": "rateLimited", "status_code": 429}
    assert route.call_count == 2


def test_an_empty_bucket_mid_menu_is_the_rules_for_a_fetching_route(
    gemini: respx.MockRouter,
) -> None:
    route = gemini.post(GEMINI_URL).mock(side_effect=_answering())
    with client(settings(ANALYSIS_RATE_LIMIT_PER_MINUTE=1)) as test_client:
        state = test_client.app.state  # type: ignore[attr-defined]
        context = ClassifyContext(
            settings=state.settings,
            engine=state.engine,
            http_client=state.http_client,
            limiter=state.analysis_rate_limiter,
            install_id=INSTALL_ID,
        )
        options = AnalysisOptionsSnapshot.model_validate(_OPTIONS)

        async def run() -> Any:
            return await classify(_MENU, options, context, when_rate_limited="rules")

        result = test_client.portal.call(run)  # type: ignore[union-attr]

    assert result is not None
    assert result.cache == "bypass"
    assert result.analysis.engine.model_dump(by_alias=True) == {
        "kind": "rules",
        "reason": "rateLimited",
    }
    assert route.call_count == 1


def test_extraction_batches_are_smaller(gemini: respx.MockRouter) -> None:
    route = gemini.post(GEMINI_URL).mock(side_effect=_answering())
    with client(settings()) as test_client:
        response = _post(test_client, _EXTRACT)

    assert response.status_code == 200
    analysis = response.json()["analysis"]
    assert analysis["engine"]["kind"] == "llm"
    assert len(analysis["dishes"]) == len(_MENU.all_dishes())
    assert route.call_count == 6
    schema = json.loads(route.calls.last.request.content)["generationConfig"][
        "responseSchema"
    ]
    assert "ingredients" in json.dumps(schema)


def test_a_menu_that_fits_is_one_request_with_the_whole_prompt(
    gemini: respx.MockRouter,
) -> None:
    small = golden("batches.json")["menus"]["english"]
    route = gemini.post(GEMINI_URL).mock(side_effect=_answering())
    with client(settings()) as test_client:
        response = test_client.post(
            "/v1/classify",
            content=json.dumps({"menu": small, "options": _OPTIONS}),
            headers={"Content-Type": "application/json", **HEADERS},
        )

    assert response.status_code == 200
    assert route.call_count == 1
    assert _sent_prompt(route.calls.last.request) == user_prompt(
        Menu.model_validate(small)
    )
