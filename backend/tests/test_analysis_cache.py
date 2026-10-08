"""Tests for the D25 analysis cache (``app.services.analysis_cache``, #333)
and the pieces of ``app.services.classify`` no route test reaches."""

from collections.abc import Iterator
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import Engine, inspect

from app.config import Settings
from app.db import build_engine
from app.keto.models import (
    AnalysisOptionsSnapshot,
    LlmEngine,
    Menu,
    MenuAnalysed,
    RulesEngine,
)
from app.keto.parser import SCHEMA_VERSION
from app.models import AnalysisCache, Base
from app.schemas import known_dietary_constraints
from app.services import analysis_cache, classify, gemini
from tests.analysis_support import golden

_NOW = datetime(2026, 10, 8, 12, 0, 0, tzinfo=UTC)
_OPTIONS = AnalysisOptionsSnapshot(net_carb_limit_grams=6, dietary_constraints=[])
_MODEL = "gemini-3.5-flash"


@pytest.fixture
def engine() -> Iterator[Engine]:
    built = build_engine(Settings(DATABASE_URL="sqlite:///:memory:"))
    Base.metadata.create_all(built)
    yield built
    built.dispose()


def _menu() -> Menu:
    entry = next(
        e
        for e in golden("parser.json")["text"]
        if e["name"] == ("llm_skipped_dish.json")
    )
    return Menu.model_validate(entry["sourceMenu"])


def _analysis(menu: Menu) -> MenuAnalysed:
    return classify.rules_analysis(menu, _OPTIONS, "offline", now=_NOW).model_copy(
        update={"engine": LlmEngine(model=_MODEL)}
    )


def _key(menu: Menu, **overrides: object) -> str:
    fields: dict[str, object] = {
        "model": _MODEL,
        "schema_version": SCHEMA_VERSION,
        "options": _OPTIONS,
    }
    fields.update(overrides)
    return analysis_cache.cache_key(menu, **fields)  # type: ignore[arg-type]


def test_the_table_exists_with_no_install_id_column(engine: Engine) -> None:
    columns = {c["name"] for c in inspect(engine).get_columns("analysis_cache")}
    assert columns == {"key", "analysis_json", "created_at"}


def test_the_key_is_a_stable_sha256_of_its_five_parts() -> None:
    menu = _menu()
    key = _key(menu)
    assert key == _key(menu)
    assert len(key) == 64 and all(c in "0123456789abcdef" for c in key)
    fragments = sorted(known_dietary_constraints())
    variants = {
        _key(menu, model="other-model"),
        _key(menu, schema_version=SCHEMA_VERSION + 1),
        _key(
            menu,
            options=AnalysisOptionsSnapshot(
                net_carb_limit_grams=7, dietary_constraints=[]
            ),
        ),
        _key(
            menu,
            options=AnalysisOptionsSnapshot(
                net_carb_limit_grams=6, dietary_constraints=fragments[:2]
            ),
        ),
        _key(
            menu,
            options=AnalysisOptionsSnapshot(
                net_carb_limit_grams=6, dietary_constraints=fragments[1::-1]
            ),
        ),
    }
    assert key not in variants
    assert len(variants) == 5


def test_the_key_follows_dish_text_not_the_venue() -> None:
    menu = _menu()
    elsewhere = menu.model_copy(
        update={
            "venue_ref": menu.venue_ref.model_copy(update={"platform_id": "other"}),
            "fetched_at": "2030-01-01T00:00:00.000Z",
        }
    )
    assert _key(elsewhere) == _key(menu)
    first = menu.categories[0]
    renamed_dish = first.dishes[0].model_copy(update={"name": "Grilled Tuna"})
    changed = menu.model_copy(
        update={
            "categories": [
                first.model_copy(update={"dishes": [renamed_dish, *first.dishes[1:]]})
            ]
        }
    )
    assert _key(changed) != _key(menu)


def test_a_written_analysis_reads_back_whole(engine: Engine) -> None:
    menu = _menu()
    analysis = _analysis(menu)
    analysis_cache.write_cached(engine, "k", analysis, _NOW)
    assert analysis_cache.read_cached(engine, "k", 60, _NOW) == analysis
    assert analysis_cache.read_cached(engine, "absent", 60, _NOW) is None


def test_a_row_past_its_ttl_is_a_miss_and_is_replaced(engine: Engine) -> None:
    menu = _menu()
    analysis_cache.write_cached(engine, "k", _analysis(menu), _NOW)
    assert analysis_cache.read_cached(engine, "k", 60, _NOW + timedelta(seconds=60))
    assert (
        analysis_cache.read_cached(engine, "k", 60, _NOW + timedelta(seconds=61))
        is None
    )
    later = _NOW + timedelta(days=1)
    replacement = _analysis(menu).model_copy(
        update={"engine": LlmEngine(model="newer")}
    )
    analysis_cache.write_cached(engine, "k", replacement, later)
    assert analysis_cache.read_cached(engine, "k", 60, later) == replacement


def test_a_naive_now_is_taken_as_utc(engine: Engine) -> None:
    analysis_cache.write_cached(
        engine, "k", _analysis(_menu()), _NOW.replace(tzinfo=None)
    )
    assert analysis_cache.read_cached(engine, "k", 1, _NOW) is not None


def test_a_row_that_no_longer_reads_is_a_miss(engine: Engine) -> None:
    from sqlalchemy.orm import Session

    with Session(engine) as session:
        session.add(
            AnalysisCache(
                key="k",
                analysis_json='{"dishes": "not a list"}',
                created_at=_NOW.replace(tzinfo=None),
            )
        )
        session.commit()
    assert analysis_cache.read_cached(engine, "k", 60, _NOW) is None


def test_rules_reasons_are_exactly_the_gemini_failure_names() -> None:
    assert set(classify._RULES_REASONS) == set(gemini.CHAT_FAILURE_REASONS)
    assert classify._rules_reason("somethingNew") == "badResponse"


def test_rules_analysis_is_restamped_like_the_client_router() -> None:
    menu = _menu()
    analysis = classify.rules_analysis(menu, _OPTIONS, "timeout", now=_NOW)
    assert analysis.engine == RulesEngine(reason="timeout")
    assert analysis.options == _OPTIONS
    assert analysis.schema_version == SCHEMA_VERSION == 1
    assert analysis.analysed_at == "2026-10-08T12:00:00.000Z"
    assert [dish.dish_id for dish in analysis.dishes] == [
        dish.id for dish in menu.all_dishes()
    ]


def test_dart_now_writes_milliseconds_in_utc() -> None:
    moment = datetime(2026, 1, 2, 3, 4, 5, 678_901, tzinfo=UTC)
    assert classify.dart_now(moment) == "2026-01-02T03:04:05.678Z"
    assert classify.dart_now().endswith("Z")


def test_a_cached_analysis_fits_only_its_own_menu_and_options() -> None:
    menu = _menu()
    analysis = _analysis(menu)
    assert classify._fits(analysis, menu, _OPTIONS)
    rules = analysis.model_copy(update={"engine": RulesEngine(reason="offline")})
    assert not classify._fits(rules, menu, _OPTIONS)
    older = analysis.model_copy(update={"schema_version": 0})
    assert not classify._fits(older, menu, _OPTIONS)
    other_options = AnalysisOptionsSnapshot(
        net_carb_limit_grams=7, dietary_constraints=[]
    )
    assert not classify._fits(analysis, menu, other_options)


def test_a_parser_result_that_does_not_validate_is_refused() -> None:
    analysis = _analysis(_menu())
    broken_dish = analysis.dishes[0].model_construct(
        **{**dict(analysis.dishes[0]), "verdict": "modifiable", "modification": None}
    )
    broken = analysis.model_copy(update={"dishes": [broken_dish]})
    assert classify._finished(broken, _OPTIONS) is None
    assert classify._finished(analysis, _OPTIONS) == analysis
