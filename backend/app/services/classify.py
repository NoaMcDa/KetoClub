"""Server-side menu classification for the D25 routes (#333).

:func:`classify` is the one path every D25 route that analyses a text menu
takes — ``POST /v1/classify``, ``GET /v1/venue-menus/...``,
``POST /v1/text-menu`` and, from #334, ``POST /v1/website-menu`` — and it
mirrors the client's ``RoutingMenuClassifier`` (``lib/services/classifier/
classifier_router.dart``) behind the shared analysis cache:

1. A menu with no dish has nothing to classify: ``None``, and nothing else
   happens (no cache read, no bucket, no Gemini call).
2. An analysis-cache hit (``app.services.analysis_cache``) answers for free:
   it spends no bucket, makes no Gemini call.
3. No server key is a rules result stamped ``notConfigured``, with no
   bucket spent: no Gemini call was about to be made.
4. The analysis bucket is spent only now, just before the Gemini call. An
   empty bucket either refuses the request (429 ``rateLimited``, for a route
   whose only product is the analysis) or answers with the rules stamped
   ``rateLimited`` (for a route that also fetched a menu), as the caller
   chooses.
5. ``app.services.gemini.complete`` with the text path's prompt and schema
   (``app.keto.prompt``), then ``app.keto.parser.parse``. Any Gemini failure
   (``notConfigured``, ``offline``, ``timeout``, ``rateLimited`` from
   upstream, ``badResponse``) and an unusable reply fall back to the ported
   heuristic stamped ``{"kind": "rules", "reason": <that reason>}``, exactly
   as ``RoutingMenuClassifier`` falls back. Only an ``llm`` analysis is
   written to the analysis cache.

A menu too large for one request (#188; architecture.md D6 as D25 amends
it) is split by ``app.keto.batching.split_batches``, the Dart split's twin,
under ``app.schemas.USER_PROMPT_MAX_CHARS`` and the dish ceiling, and steps
4 and 5 run once per batch, in order: one bucket unit and one Gemini call
each. The batches are merged as ``LlmMenuClassifier`` merges them on the
device. A batch whose own reply or wait failed (``badResponse``,
``timeout``) puts its dishes under ``unclassified`` and the next batch is
still sent; only when no batch answered is the menu the rules with the
first reason. Any other failure, an empty bucket mid-menu included, stops
the menu and answers as it would have for the first batch (the rules with
that reason, or the 429), so a mid-menu ``rateLimited`` is named rather
than hidden among the unclassified. A merged analysis with a failed batch
is not cached. A menu that fits one request is exactly the one request it
always was.

Every analysis returned carries the request's options snapshot and
``schemaVersion`` 1 (``app.keto.parser.SCHEMA_VERSION``), so the client's
``tryFrom`` and options check accept it as one it made itself.

The install id is used for the analysis bucket only: it is never stored,
never logged, and never leaves this module except as the limiter's key.
"""

import logging
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any, Final, Literal

import httpx
from fastapi import Request
from pydantic import ValidationError
from sqlalchemy import Engine
from starlette.concurrency import run_in_threadpool

from app.config import Settings
from app.errors import BackendError
from app.keto import parser, prompt
from app.keto.batching import batch_max_dishes, split_batches
from app.keto.heuristic import classify_heuristic
from app.keto.models import (
    AnalysedDish,
    AnalysisOptionsSnapshot,
    LlmEngine,
    Menu,
    MenuAnalysed,
    RulesEngine,
    to_json,
)
from app.keto.text_menu import dart_iso8601, scrub_lone_surrogates
from app.schemas import USER_PROMPT_MAX_CHARS, ChatRequest
from app.services import analysis_cache, gemini
from app.services.rate_limit import RateLimiter

logger = logging.getLogger("ketoclub.classify")

RulesReason = Literal[
    "notConfigured", "offline", "timeout", "rateLimited", "badResponse"
]
"""The reasons a server-side rules fallback is stamped with: the Gemini
client's failure names (``app.services.gemini.CHAT_FAILURE_REASONS``)."""

_RULES_REASONS: Final[dict[str, RulesReason]] = {
    "notConfigured": "notConfigured",
    "offline": "offline",
    "timeout": "timeout",
    "rateLimited": "rateLimited",
    "badResponse": "badResponse",
}
"""``gemini.CHAT_FAILURE_REASONS``, typed: a test pins the two equal."""


def _rules_reason(reason: str) -> RulesReason:
    """A Gemini failure's reason, or ``badResponse`` for one it never sends."""
    return _RULES_REASONS.get(reason, "badResponse")


WhenRateLimited = Literal["refuse", "rules"]
"""What an empty analysis bucket means to the caller: ``"refuse"`` raises
429 ``rateLimited``; ``"rules"`` answers with the heuristic stamped
``rateLimited``."""


@dataclass(frozen=True, slots=True)
class ClassifyContext:
    """Everything :func:`classify` reads from the app, bundled once per
    request. ``install_id`` keys ``limiter`` and nothing else."""

    settings: Settings
    engine: Engine
    http_client: httpx.AsyncClient
    limiter: RateLimiter
    install_id: str

    @classmethod
    def of(cls, request: Request, install_id: str) -> "ClassifyContext":
        """The context for one request: the app's settings, database,
        shared HTTP client and analysis bucket (``analysis_rate_limiter``)."""
        state = request.app.state
        return cls(
            settings=state.settings,
            engine=state.engine,
            http_client=state.http_client,
            limiter=state.analysis_rate_limiter,
            install_id=install_id,
        )


@dataclass(frozen=True, slots=True)
class Classified:
    """One analysis :func:`classify` returns, and where it came from.

    ``cache`` is ``"hit"`` for an analysis-cache hit, ``"miss"`` for a
    fresh ``llm`` analysis (now cached) and ``"bypass"`` for one that is
    never cached: a rules fallback, or an ``llm`` analysis of a split menu
    one of whose batches failed (#188). The route's ``X-KetoClub-Cache``.
    """

    analysis: MenuAnalysed
    cache: Literal["hit", "miss", "bypass"]


def dart_now(now: datetime | None = None) -> str:
    """``now`` (default: the current UTC time) as the Dart
    ``toIso8601String()`` of a UTC ``DateTime`` at millisecond precision:
    ``2026-01-01T00:00:00.000Z``."""
    moment = (now or datetime.now(UTC)).astimezone(UTC)
    return dart_iso8601(moment.replace(microsecond=moment.microsecond // 1000 * 1000))


async def classify(
    menu: Menu,
    options: AnalysisOptionsSnapshot,
    context: ClassifyContext,
    *,
    when_rate_limited: WhenRateLimited,
    now: datetime | None = None,
) -> Classified | None:
    """``menu`` classified under ``options``, or ``None`` when it has no dish.

    See the module docstring for the order of the steps. Raises
    ``BackendError(429, "rateLimited")`` only when the analysis bucket is
    empty and ``when_rate_limited`` is ``"refuse"``; never raises for a
    Gemini failure. ``now`` stamps ``analysedAt`` (default: the clock) and
    measures the cache's TTL.
    """
    if not menu.all_dishes():
        return None
    moment = now or datetime.now(UTC)
    analysed_at = dart_now(moment)
    settings = context.settings
    key = analysis_cache.cache_key(
        menu,
        model=settings.GEMINI_MODEL,
        schema_version=parser.SCHEMA_VERSION,
        options=options,
    )

    cached = await run_in_threadpool(
        analysis_cache.read_cached,
        context.engine,
        key,
        settings.ANALYSIS_CACHE_TTL_SECONDS,
        moment,
    )
    if cached is not None and _fits(cached, menu, options):
        logger.info("classify cache=hit dishes=%d", len(cached.dishes))
        return Classified(analysis=cached, cache="hit")

    if not settings.llm_configured:
        return _rules(menu, options, "notConfigured", analysed_at)

    batches = split_batches(
        menu,
        max_dishes=batch_max_dishes(extract=options.restrictions_requested),
        max_chars=USER_PROMPT_MAX_CHARS,
    )
    merged = _Merged()
    for batch in batches:
        # One bucket unit per Gemini call, spent just before it (step 4): a
        # menu split in three spends three, one at a time (#188).
        if not context.limiter.allow(context.install_id):
            if when_rate_limited == "refuse":
                logger.info("classify rate limited")
                raise BackendError(429, "rateLimited")
            return _rules(menu, options, "rateLimited", analysed_at)
        outcome = await _classify_batch(batch, options, context, analysed_at)
        if isinstance(outcome, MenuAnalysed):
            merged.add(outcome)
            continue
        if outcome not in _BATCH_REASONS:
            # No key, no route or Google's own rate limit: every later batch
            # would answer the same, so the whole menu is the rules.
            return _rules(menu, options, outcome, analysed_at)
        merged.fail(batch, outcome)

    if merged.engine is None:
        return _rules(menu, options, merged.first_failure or "badResponse", analysed_at)
    analysis = _finished(merged.analysis(analysed_at), options)
    if analysis is None:  # pragma: no cover - each batch already validated
        return _rules(menu, options, "badResponse", analysed_at)

    if merged.first_failure is None:
        await run_in_threadpool(
            analysis_cache.write_cached, context.engine, key, analysis, moment
        )
    logger.info(
        "classify engine=llm dishes=%d unclassified=%d batches=%d failed=%d",
        len(analysis.dishes),
        len(analysis.unclassified),
        len(batches),
        merged.failed_batches,
    )
    # A partial analysis (a batch failed) is not cached: the next open asks
    # again rather than serving the gap for a week.
    return Classified(
        analysis=analysis, cache="miss" if merged.first_failure is None else "bypass"
    )


_BATCH_REASONS: Final[frozenset[RulesReason]] = frozenset({"timeout", "badResponse"})
"""The failures that are one batch's own (#188): its reply or its wait. The
batch's dishes go under ``unclassified`` and the next batch is still sent,
as ``LlmMenuClassifier`` does on the device. Any other reason stops the
menu."""


async def _classify_batch(
    batch: Menu,
    options: AnalysisOptionsSnapshot,
    context: ClassifyContext,
    analysed_at: str,
) -> MenuAnalysed | RulesReason:
    """One Gemini request for ``batch`` (a whole menu, or one batch of one)
    and its reply parsed against ``batch``, validated; or why it failed."""
    request = ChatRequest.model_construct(
        system_prompt=prompt.system_prompt(options),
        user_prompt=prompt.user_prompt(batch),
        response_schema=prompt.response_schema(extract=options.restrictions_requested),
        schema_name=prompt.SCHEMA_NAME,
        images=[],
    )
    try:
        reply = await gemini.complete(context.http_client, context.settings, request)
    except BackendError as error:
        return _rules_reason(error.reason)

    parsed = parser.parse(
        reply.content,
        source=batch,
        # The short ids this batch's prompt numbered its dishes with.
        prompt_ids=prompt.prompt_ids(batch),
        engine=LlmEngine(model=reply.model),
        net_carb_limit_grams=options.net_carb_limit_grams,
        analysed_at=analysed_at,
        extract=options.restrictions_requested,
    )
    if isinstance(parsed, parser.Failed):
        # ``noDishesFound`` is unreachable with a dish in the batch (rule 7
        # lists every dish the reply skipped); either way nothing was placed.
        return "badResponse"
    finished = _finished(parsed.analysis, options)
    return "badResponse" if finished is None else finished


@dataclass(slots=True)
class _Merged:
    """The batches of one menu merged in order, as ``LlmMenuClassifier``
    merges them: verdicts and ``unclassified`` names in batch order, the
    first answering batch's engine, a failed batch's dishes unclassified."""

    dishes: list[AnalysedDish] = field(default_factory=list)
    unclassified: list[str] = field(default_factory=list)
    engine: LlmEngine | RulesEngine | None = None
    first_failure: RulesReason | None = None
    failed_batches: int = 0

    def add(self, analysis: MenuAnalysed) -> None:
        if self.engine is None:
            self.engine = analysis.engine
        self.dishes.extend(analysis.dishes)
        self.unclassified.extend(analysis.unclassified)

    def fail(self, batch: Menu, reason: RulesReason) -> None:
        if self.first_failure is None:
            self.first_failure = reason
        self.failed_batches += 1
        self.unclassified.extend(dish.name for dish in batch.all_dishes())

    def analysis(self, analysed_at: str) -> MenuAnalysed:
        return MenuAnalysed.model_construct(
            dishes=self.dishes,
            unclassified=self.unclassified,
            engine=self.engine,
            analysed_at=analysed_at,
            options=None,
            schema_version=parser.SCHEMA_VERSION,
        )


def rules_analysis(
    menu: Menu,
    options: AnalysisOptionsSnapshot,
    reason: RulesReason,
    *,
    now: datetime | None = None,
) -> MenuAnalysed:
    """The ported heuristic's analysis of ``menu``, stamped ``{"kind":
    "rules", "reason": reason}`` with ``options`` and ``schemaVersion`` 1:
    ``RoutingMenuClassifier``'s ``_toRulesResult``. For a caller that needs
    the rules without :func:`classify` (#334's website route on a fetch it
    could not classify, say)."""
    return _rules(menu, options, reason, dart_now(now)).analysis


def _rules(
    menu: Menu,
    options: AnalysisOptionsSnapshot,
    reason: RulesReason,
    analysed_at: str,
) -> Classified:
    logger.info("classify engine=rules reason=%s", reason)
    analysis = classify_heuristic(menu, options, analysed_at=analysed_at)
    restamped = analysis.model_copy(
        update={
            "engine": RulesEngine(reason=reason),
            "options": options,
            "schema_version": parser.SCHEMA_VERSION,
        }
    )
    return Classified(analysis=restamped, cache="bypass")


def _finished(
    analysis: MenuAnalysed, options: AnalysisOptionsSnapshot
) -> MenuAnalysed | None:
    """The parser's analysis with ``options`` attached, validated as a wire
    model, or ``None`` when it does not validate.

    The parser builds its result with ``model_construct``, as Dart builds
    it unchecked, so it is validated here before it is cached or sent. A
    lone surrogate the reply carried (``"\\ud83d"``) becomes U+FFFD, which
    is what the client reads once Dart's own ``jsonEncode`` + UTF-8 had
    written it.
    """
    raw = to_json(analysis.model_copy(update={"options": options}))
    try:
        return MenuAnalysed.model_validate(scrubbed(raw))
    except ValidationError:
        return None


def scrubbed(value: Any) -> Any:
    """``value`` with every string's lone surrogates replaced by U+FFFD."""
    if isinstance(value, str):
        return scrub_lone_surrogates(value)
    if isinstance(value, list):
        return [scrubbed(item) for item in value]
    if isinstance(value, dict):
        return {key: scrubbed(item) for key, item in value.items()}
    return value


def _fits(analysis: MenuAnalysed, menu: Menu, options: AnalysisOptionsSnapshot) -> bool:
    """Whether a cached ``analysis`` answers ``menu`` under ``options``.

    The cache key holds a 32-bit dish-text fingerprint, so a hit is checked
    before it is served: an ``llm`` analysis at the current schema version,
    made under exactly these options, whose every verdict names a dish this
    menu holds under that id and name. Two venues with the same dishes under
    different ids (a chain on two platforms) therefore miss rather than get
    verdicts for ids their menu does not have; the client would refuse
    those.
    """
    if not isinstance(analysis.engine, LlmEngine):
        return False
    if analysis.schema_version != parser.SCHEMA_VERSION:
        return False
    if analysis.options != options:
        return False
    names = {dish.id: dish.name for dish in menu.all_dishes()}
    return all(names.get(dish.dish_id) == dish.name for dish in analysis.dishes)
