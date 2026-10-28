"""Score the Israeli keto corpus: rules alone, model alone, and merged.

The labelled keto corpus under ``test/fixtures/keto/menus/`` (its contract is
``test/fixtures/keto/SCHEMA.md``) is the measuring stick for the verdicts;
this module holds the **pure scoring** the CI gate
(``tests/test_keto_corpus_gate.py``) and the person-run evaluation share,
modelled on ``tools/allergen_eval.py``. The Dart gate
(``test/utils/keto/keto_scoring.dart``) uses the same metric definitions and
reads the same shrink-only list of known misses,
``test/fixtures/keto/known_keto_misses.json``.

Two things live here:

* The pure part: loading the corpus, the rules' verdicts per dish
  (:func:`rules_verdicts`, the ported heuristic), the verdicts a model reply
  gives (:func:`model_verdicts`, the ported parser, exactly as the app reads
  a reply), the merge of the two (:func:`merge`), the metrics
  (:func:`score`), the gate's misses and the markdown report
  (:func:`report_markdown`). It does no I/O but reading the corpus files,
  and ``tests/test_keto_eval.py`` exercises it offline.
* ``main``: the person-run evaluation. It makes real network calls, so no
  test lets it leave the sandbox and ``check.sh``'s coverage (``--cov=app``)
  never counts it::

      cd backend
      GEMINI_API_KEY=... uv run python tools/keto_eval.py

  Each corpus menu goes out through the backend's own model client
  (``app.services.gemini.complete``) with the real text-path prompt and
  schema (``app.keto.prompt``, keto only, the 6 g default), split into
  batches exactly as ``app.services.classify`` splits a large menu (#188),
  one request at a time with a pause between them. Failures (``timeout``,
  ``rateLimited``, ``badResponse`` and the rest) are recorded per batch and
  never stop the run. The key is read from the environment only (never a
  ``.env`` file); with none the tool says so and exits 1. The result is
  spliced into ``docs/KETO_EVAL.md``; ``--no-write`` only prints it,
  ``--record`` also saves each raw reply (no key, no headers) under
  ``test/fixtures/llm/keto_eval/``, and ``--rules-only`` needs no key.

**Metrics** (one :class:`Score` per source and slice):

* *accuracy*: dishes whose verdict is the expected one or one of its
  ``acceptable`` alternatives, over all dishes; an unclassified dish is
  never correct.
* *false-green rate* (the headline): dishes expected ``modifiable`` or
  ``nonKeto`` that came back ``orderAsIs`` (and ``orderAsIs`` is not
  acceptable for them), over all dishes expected ``modifiable`` or
  ``nonKeto``.
* *false-red rate*: dishes expected ``orderAsIs`` or ``modifiable`` that came
  back ``nonKeto`` (not acceptable for them), over all dishes expected
  ``orderAsIs`` or ``modifiable``.
* *unclassified*: dishes with no verdict at all.
* *hidden-carb recall / precision*: a labelled hidden carb is found when a
  produced flag matches it, and a produced flag is matched when it matches
  a labelled one. A label with a ``term`` (the text in the dish that points
  at it) is matched by the term: the flag's source contains the term, the
  term contains the flag's source, or the flag's waiter question contains
  the term. A label without one falls back to its ``source``: one of the
  two texts contains the other. Every text is normalised first
  (``app.keto.normaliser.normalise``: case, punctuation and brackets gone).

The labels are unreviewed desk research: a number from this module is a
question for the labels as much as for the engine.
"""

import argparse
import asyncio
import json
import os
import re
import subprocess
import sys
import time
from collections.abc import Awaitable, Callable, Iterable, Mapping, Sequence
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Final

import httpx

from app.config import Settings
from app.errors import BackendError
from app.keto import parser, prompt
from app.keto.batching import batch_max_dishes, split_batches
from app.keto.heuristic import classify_heuristic
from app.keto.models import AnalysedDish, AnalysisOptionsSnapshot, LlmEngine, Menu
from app.keto.normaliser import normalise
from app.schemas import USER_PROMPT_MAX_CHARS, ChatRequest
from app.services import gemini

REPO_ROOT: Final = Path(__file__).resolve().parents[2]
"""The repository root (this file is ``backend/tools/keto_eval.py``)."""

CORPUS_DIR: Final = REPO_ROOT / "test" / "fixtures" / "keto" / "menus"
"""The labelled menus, one JSON file each."""

KNOWN_MISSES_PATH: Final = (
    REPO_ROOT / "test" / "fixtures" / "keto" / ("known_keto_misses.json")
)
"""The shrink-only list of misses the rules do not close yet, shared with
the Dart gate."""

REPORT_PATH: Final = REPO_ROOT / "docs" / "KETO_EVAL.md"
"""Where ``main`` writes the last result."""

RECORD_DIR: Final = REPO_ROOT / "test" / "fixtures" / "llm" / "keto_eval"
"""Where ``--record`` saves each menu's raw replies."""

VERDICTS: Final = ("orderAsIs", "modifiable", "nonKeto")
"""Dart ``DishVerdict.values`` names: green, yellow, red."""

HIDDEN_CARB_CERTAINTIES: Final = ("likely", "suspected")
"""The certainties a labelled hidden carb carries."""

NET_CARB_LIMIT_GRAMS: Final = 6
"""The app's default limit, which the evaluation asks under."""

OPTIONS: Final = AnalysisOptionsSnapshot(
    net_carb_limit_grams=NET_CARB_LIMIT_GRAMS, dietary_constraints=[]
)
"""Keto only: no dietary constraint, no restriction extraction."""

UNCLASSIFIED: Final = "unclassified"
"""How a dish with no verdict is named in a miss and in the report."""

_ANALYSED_AT: Final = "2026-01-01T00:00:00.000Z"
"""The timestamp stamped on every analysis here; nothing reads it."""


# --- the corpus ------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class ExpectedCarb:
    """One labelled hidden carb of a dish: a short English ``source`` (with
    the Hebrew word in brackets when there is one) and, when the dish names
    it, the ``term`` in the dish's own text that points at it."""

    source: str
    certainty: str
    term: str | None = None

    def matched_by(self, flag: "Flag") -> bool:
        """Whether a produced ``flag`` (the model's or the rules') names this
        hidden carb. With a ``term``, by the term alone: the flag's source
        contains the term, the term contains the flag's source, or the flag's
        waiter question contains the term. Without one, by the source
        (:func:`texts_match`). Every text is normalised first."""
        if not self.term:
            return texts_match(self.source, flag.source)
        term = _norm(self.term)
        if not term:
            return False
        source = _norm(flag.source)
        question = _norm(flag.question)
        return (
            bool(source)
            and (term in source or source in term)
            or (bool(question) and term in question)
        )


@dataclass(frozen=True, slots=True)
class CorpusDish:
    """One labelled dish of one corpus menu."""

    menu: str
    id: str
    name: str
    description: str
    options: tuple[tuple[str, tuple[str, ...]], ...]
    expected: str
    acceptable: frozenset[str]
    hidden_carbs: tuple[ExpectedCarb, ...]
    language: str

    @property
    def key(self) -> str:
        """The dish id the engine sees: ``<menu id>/<dish id>``, unique
        across the corpus. Every verdict mapping is keyed by it."""
        return f"{self.menu}/{self.id}"

    def accepts(self, verdict: str | None) -> bool:
        """Whether ``verdict`` is the expected one or an acceptable one."""
        return verdict is not None and (
            verdict == self.expected or verdict in self.acceptable
        )


@dataclass(frozen=True, slots=True)
class CorpusMenu:
    """One labelled corpus menu: its categories of dishes, in file order."""

    id: str
    name: str
    source: str
    language: str
    categories: tuple[tuple[str, tuple[CorpusDish, ...]], ...]

    @property
    def dishes(self) -> list[CorpusDish]:
        """Every dish, flattened, in file order."""
        return [dish for _, dishes in self.categories for dish in dishes]

    def to_menu(self) -> Menu:
        """The menu as the engine and the prompt see it: one dish per corpus
        dish under its :attr:`CorpusDish.key`, no prices."""
        return Menu.model_validate(
            {
                "venueRef": {"source": "scan", "platformId": f"corpus-{self.id}"},
                "currency": "ILS",
                "fetchedAt": _ANALYSED_AT,
                "venueName": self.name,
                "categories": [
                    {
                        "id": f"c{index}",
                        "name": name,
                        "dishes": [
                            {
                                "id": dish.key,
                                "name": dish.name,
                                "description": dish.description,
                                "price": 0,
                                "options": [
                                    {"name": option, "values": list(values)}
                                    for option, values in dish.options
                                ],
                            }
                            for dish in dishes
                        ],
                    }
                    for index, (name, dishes) in enumerate(self.categories)
                ],
            }
        )


def _verdict_name(value: object, where: str) -> str:
    if not isinstance(value, str) or value not in VERDICTS:
        raise ValueError(f"{where}: {value!r} is not one of {', '.join(VERDICTS)}")
    return value


def _dish(raw: Mapping[str, Any], menu: str, language: str) -> CorpusDish:
    where = f"{menu}/{raw.get('id')}"
    acceptable = raw.get("acceptable") or []
    return CorpusDish(
        menu=menu,
        id=str(raw["id"]),
        name=str(raw["name"]),
        description=str(raw.get("description") or ""),
        options=tuple(
            (str(option["name"]), tuple(str(v) for v in option["values"]))
            for option in raw.get("options") or []
        ),
        expected=_verdict_name(raw.get("expected"), where),
        acceptable=frozenset(_verdict_name(v, where) for v in acceptable),
        hidden_carbs=tuple(
            ExpectedCarb(
                str(carb["source"]),
                str(carb.get("certainty", "likely")),
                str(carb["term"]) if carb.get("term") else None,
            )
            for carb in raw.get("hiddenCarbs") or []
        ),
        language=language,
    )


def load_menu(path: Path) -> CorpusMenu:
    """One corpus menu file. A menu with a top-level ``dishes`` list instead
    of ``categories`` reads as one category named after the menu. Raises
    ``ValueError`` for an ``expected`` or ``acceptable`` that is not a
    verdict name, so a label typo fails loudly rather than scoring."""
    document = json.loads(path.read_text(encoding="utf-8"))
    menu_id = str(document.get("id") or path.stem)
    name = str(document.get("name") or menu_id)
    language = str(document.get("language") or "unknown")
    raw_categories = document.get("categories")
    if raw_categories is None:
        raw_categories = [{"name": name, "dishes": document.get("dishes") or []}]
    categories = tuple(
        (
            str(category.get("name") or name),
            tuple(_dish(raw, menu_id, language) for raw in category["dishes"]),
        )
        for category in raw_categories
    )
    return CorpusMenu(
        id=menu_id,
        name=name,
        source=str(document.get("source") or ""),
        language=language,
        categories=categories,
    )


def load_corpus(directory: Path = CORPUS_DIR) -> list[CorpusMenu]:
    """Every ``*.json`` menu in ``directory``, sorted by file name; an empty
    list when the directory does not exist."""
    if not directory.is_dir():
        return []
    return [load_menu(path) for path in sorted(directory.glob("*.json"))]


def all_dishes(menus: Iterable[CorpusMenu]) -> list[CorpusDish]:
    """Every dish of every menu, in corpus order."""
    return [dish for menu in menus for dish in menu.dishes]


# --- verdicts --------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class Flag:
    """One hidden carb a source flagged: its ``source`` text and the waiter
    question it came with (empty when it has none)."""

    source: str
    question: str = ""


@dataclass(frozen=True, slots=True)
class Got:
    """What one source said about one dish: its verdict and the hidden
    carbs it flagged."""

    verdict: str
    hidden_carbs: tuple[Flag, ...] = ()


def _flags(dish: AnalysedDish) -> tuple[Flag, ...]:
    return tuple(Flag(c.source, c.waiter_question) for c in dish.hidden_carbs)


Verdicts = dict[str, Got]
"""A source's verdicts, keyed by :attr:`CorpusDish.key`. A dish that is
absent has no verdict (it is unclassified)."""


def rules_verdicts(menu: CorpusMenu) -> Verdicts:
    """What the rules engine (``app.keto.heuristic``, the Dart heuristic's
    twin) says about every dish of ``menu`` under :data:`OPTIONS`."""
    analysis = classify_heuristic(menu.to_menu(), OPTIONS, analysed_at=_ANALYSED_AT)
    return {dish.dish_id: Got(dish.verdict, _flags(dish)) for dish in analysis.dishes}


def model_verdicts(reply: str, menu: Menu, *, model: str = "model") -> Verdicts | None:
    """The verdicts a model ``reply`` (the reply text) gives the dishes of
    ``menu`` (the menu, or the batch, the request was built from), read by
    ``app.keto.parser.parse`` exactly as the app reads it: an invented dish
    is dropped, a yellow with no instruction is unclassified, an
    ``orderAsIs`` over the 6 g limit or with a hidden carb is demoted.
    ``None`` when the reply is unusable (``badResponse``)."""
    parsed = parser.parse(
        reply,
        source=menu,
        engine=LlmEngine.model_construct(model=model),
        net_carb_limit_grams=NET_CARB_LIMIT_GRAMS,
        analysed_at=_ANALYSED_AT,
    )
    if isinstance(parsed, parser.Failed):
        return None
    return {
        dish.dish_id: Got(dish.verdict, _flags(dish)) for dish in parsed.analysis.dishes
    }


def _norm(text: str) -> str:
    return normalise(text)


def merge(rules: Mapping[str, Got], model: Mapping[str, Got]) -> Verdicts:
    """The model's verdict with a rules floor: a dish the rules call
    ``modifiable`` or ``nonKeto`` is never upgraded to ``orderAsIs``, so a
    model green over a rules yellow or red is the rules' verdict, and any
    other model verdict stands. A dish the model did not place keeps the
    rules' verdict. Hidden carbs are the union, rules first, deduplicated
    by normalised text."""
    merged: Verdicts = {}
    for key in [*rules, *(k for k in model if k not in rules)]:
        from_rules = rules.get(key)
        from_model = model.get(key)
        if from_model is None:
            assert from_rules is not None
            merged[key] = from_rules
            continue
        verdict = from_model.verdict
        if (
            from_rules is not None
            and verdict == "orderAsIs"
            and from_rules.verdict != "orderAsIs"
        ):
            verdict = from_rules.verdict
        flags: list[Flag] = []
        seen: set[str] = set()
        for flag in [
            *(from_rules.hidden_carbs if from_rules else ()),
            *from_model.hidden_carbs,
        ]:
            if _norm(flag.source) not in seen:
                seen.add(_norm(flag.source))
                flags.append(flag)
        merged[key] = Got(verdict, tuple(flags))
    return merged


# --- the metrics -----------------------------------------------------------------


def texts_match(expected: str, flagged: str) -> bool:
    """The source fallback for a label with no ``term``: the two normalised
    texts (punctuation and brackets gone) are non-empty and one contains the
    other, so "brown sugar" matches "sugar" and "sweet marinade" matches
    "sweet marinade (מרינדה מתוקה)"."""
    a, b = _norm(expected), _norm(flagged)
    return bool(a) and bool(b) and (a in b or b in a)


def _rate(hit: int, total: int) -> float | None:
    return None if total == 0 else hit / total


@dataclass(slots=True)
class Score:
    """One source's counts over one slice of the corpus."""

    dishes: int = 0
    correct: int = 0
    unclassified: int = 0
    non_green: int = 0
    false_green: int = 0
    non_red: int = 0
    false_red: int = 0
    carbs_expected: int = 0
    carbs_found: int = 0
    carbs_flagged: int = 0
    carbs_flagged_matched: int = 0
    carbs_by_certainty: dict[str, list[int]] = field(default_factory=dict)
    """Per certainty, ``[found, expected]``."""

    @property
    def accuracy(self) -> float | None:
        """Correct dishes over all dishes."""
        return _rate(self.correct, self.dishes)

    @property
    def false_green_rate(self) -> float | None:
        """False greens over dishes expected ``modifiable`` or ``nonKeto``."""
        return _rate(self.false_green, self.non_green)

    @property
    def false_red_rate(self) -> float | None:
        """False reds over dishes expected ``orderAsIs`` or ``modifiable``."""
        return _rate(self.false_red, self.non_red)

    @property
    def carb_recall(self) -> float | None:
        """Labelled hidden carbs found over labelled hidden carbs."""
        return _rate(self.carbs_found, self.carbs_expected)

    @property
    def carb_precision(self) -> float | None:
        """Flagged sources that match a label over flagged sources."""
        return _rate(self.carbs_flagged_matched, self.carbs_flagged)


def score(expected: Sequence[CorpusDish], got: Mapping[str, Got]) -> Score:
    """The metrics of ``got`` (a source's verdicts) over ``expected`` (the
    labelled dishes to score; a slice of the corpus or all of it). See the
    module docstring for the definitions."""
    result = Score(
        carbs_by_certainty={certainty: [0, 0] for certainty in HIDDEN_CARB_CERTAINTIES}
    )
    for dish in expected:
        found = got.get(dish.key)
        verdict = found.verdict if found is not None else None
        result.dishes += 1
        if verdict is None:
            result.unclassified += 1
        elif dish.accepts(verdict):
            result.correct += 1
        if dish.expected != "orderAsIs":
            result.non_green += 1
            if verdict == "orderAsIs" and not dish.accepts(verdict):
                result.false_green += 1
        if dish.expected != "nonKeto":
            result.non_red += 1
            if verdict == "nonKeto" and not dish.accepts(verdict):
                result.false_red += 1
        flagged = found.hidden_carbs if found is not None else ()
        for carb in dish.hidden_carbs:
            hit = any(carb.matched_by(flag) for flag in flagged)
            result.carbs_expected += 1
            result.carbs_found += hit
            tally = result.carbs_by_certainty.setdefault(carb.certainty, [0, 0])
            tally[0] += hit
            tally[1] += 1
        for flag in flagged:
            result.carbs_flagged += 1
            result.carbs_flagged_matched += any(
                carb.matched_by(flag) for carb in dish.hidden_carbs
            )
    return result


# --- the gate --------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class Miss:
    """A dish whose verdict is neither the expected one nor acceptable."""

    menu: str
    dish: str
    name: str
    expected: str
    got: str

    @property
    def key(self) -> tuple[str, str, str, str]:
        """What a known-misses entry must equal: menu, dish, expected, got."""
        return (self.menu, self.dish, self.expected, self.got)

    def entry(self, reason: str = "") -> dict[str, str]:
        """This miss as a ``known_keto_misses.json`` entry."""
        return {
            "menu": self.menu,
            "dish": self.dish,
            "expected": self.expected,
            "got": self.got,
            "reason": reason,
        }

    def __str__(self) -> str:
        return (
            f"{self.menu}  {self.dish}  {self.name!r}  expected {self.expected}, "
            f"got {self.got}"
        )


def find_misses(menus: Iterable[CorpusMenu], got: Mapping[str, Got]) -> list[Miss]:
    """Every dish of ``menus`` whose verdict in ``got`` the labels do not
    accept; a dish with no verdict is a miss that got ``unclassified``."""
    misses: list[Miss] = []
    for dish in all_dishes(menus):
        found = got.get(dish.key)
        verdict = found.verdict if found is not None else None
        if not dish.accepts(verdict):
            misses.append(
                Miss(
                    dish.menu,
                    dish.id,
                    dish.name,
                    dish.expected,
                    verdict or UNCLASSIFIED,
                )
            )
    return misses


KNOWN_MISS_FIELDS: Final = frozenset({"menu", "dish", "expected", "got", "reason"})
"""The fields of one known-misses entry, all non-blank strings."""


def load_known_misses(path: Path = KNOWN_MISSES_PATH) -> list[dict[str, str]]:
    """The known-misses entries, as written: a JSON list. A missing file is
    the empty list the shared file starts as."""
    if not path.is_file():
        return []
    document = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(document, list):
        raise ValueError(f"{path}: expected a JSON list of entries")
    return [dict(entry) for entry in document]


def entry_key(entry: Mapping[str, str]) -> tuple[str, str, str, str]:
    """An entry's ``(menu, dish, expected, got)``."""
    return (entry["menu"], entry["dish"], entry["expected"], entry["got"])


def unlisted_misses(
    misses: Iterable[Miss], known: Iterable[Mapping[str, str]]
) -> list[Miss]:
    """The misses no entry lists with exactly that expected and got."""
    listed = {entry_key(entry) for entry in known}
    return [miss for miss in misses if miss.key not in listed]


def stale_entries(
    misses: Iterable[Miss], known: Iterable[Mapping[str, str]]
) -> list[dict[str, str]]:
    """The entries that no longer name a current miss (fixed, or now wrong
    in another way): the list can only shrink."""
    current = {miss.key for miss in misses}
    return [dict(entry) for entry in known if entry_key(entry) not in current]


# --- the report ------------------------------------------------------------------


@dataclass(slots=True)
class MenuRun:
    """One corpus menu's model run: its verdicts, how long it took, what it
    cost, and which batches failed and why."""

    menu: str
    batches: int = 0
    latency_seconds: float = 0.0
    tokens: dict[str, int] = field(default_factory=dict)
    failures: list[tuple[int, str]] = field(default_factory=list)
    verdicts: Verdicts = field(default_factory=dict)
    replies: list[dict[str, Any]] = field(default_factory=list)
    """Per batch, the raw upstream bodies (for ``--record``)."""


@dataclass(frozen=True, slots=True)
class Results:
    """Everything one run produced. ``model`` is ``None`` for a rules-only
    run, in which case ``runs`` is empty and ``model_id`` is ``None``."""

    menus: Sequence[CorpusMenu]
    rules: Mapping[str, Got]
    model: Mapping[str, Got] | None
    runs: Sequence[MenuRun]
    when: datetime
    model_id: str | None
    commit: str
    corpus: str

    def sources(self) -> dict[str, Mapping[str, Got]]:
        """The verdict sources to report, in table order."""
        if self.model is None:
            return {"Rules": self.rules}
        return {
            "Rules": self.rules,
            "Model": self.model,
            "Merged": merge(self.rules, self.model),
        }


def percent(rate: float | None) -> str:
    """``rate`` as ``93.6%``, or ``-`` when there is nothing to divide."""
    return "-" if rate is None else f"{100 * rate:.1f}%"


def _of(hit: int, total: int) -> str:
    return f"{hit}/{total} ({percent(_rate(hit, total))})"


_METRICS_HEADER: Final = (
    "| Source | Dishes | Accuracy | **False green** | False red | "
    "Unclassified | Hidden-carb recall | Hidden-carb precision |\n"
    "|---|---:|---:|---:|---:|---:|---:|---:|"
)


def _metrics_row(label: str, result: Score) -> str:
    return (
        f"| {label} | {result.dishes} | {_of(result.correct, result.dishes)} | "
        f"**{_of(result.false_green, result.non_green)}** | "
        f"{_of(result.false_red, result.non_red)} | {result.unclassified} | "
        f"{_of(result.carbs_found, result.carbs_expected)} | "
        f"{_of(result.carbs_flagged_matched, result.carbs_flagged)} |"
    )


def _cell(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", " ")


def _count(n: int, one: str, many: str | None = None) -> str:
    return f"{n} {one if n == 1 else (many or one + 's')}"


def _run_facts(results: Results) -> list[str]:
    dishes = all_dishes(results.menus)
    sizes = (
        f"{_count(len(results.menus), 'menu')}, {_count(len(dishes), 'dish', 'dishes')}"
    )
    model = (
        f"Model: `{results.model_id}` (the configured `GEMINI_MODEL`)."
        if results.model_id is not None
        else "Model: **not yet run** (rules only)."
    )
    failed = [run.menu for run in results.runs if run.failures]
    lines = [
        f"Run: {results.when.strftime('%Y-%m-%d %H:%M UTC')}. "
        f"Commit: `{results.commit}`. Corpus: `{results.corpus}` "
        f"({sizes}). {model} "
        f"Net-carb limit: {NET_CARB_LIMIT_GRAMS} g, keto only.",
    ]
    if results.model is not None:
        lines.append(
            "Menus with a failed batch: "
            f"{', '.join(failed) if failed else 'none'}. "
            "A dish of a failed batch counts as unclassified for the model "
            "and keeps the rules' verdict in the merge."
        )
    lines += [
        "",
        "The labels are **unreviewed**: no dietitian has read them, so every "
        "figure here is a question for the labels as much as for the engine.",
    ]
    return lines


def report_markdown(results: Results) -> str:
    """The markdown of a run's results: the run's facts, the overall table
    (rules, model and merged), the same per language, the hidden-carb table,
    the per-menu model run and every false green by dish. :func:`update_page`
    splices it into ``docs/KETO_EVAL.md``."""
    dishes = all_dishes(results.menus)
    sources = results.sources()
    lines = [*_run_facts(results), "", "### Overall", "", _METRICS_HEADER]
    for label, got in sources.items():
        lines.append(_metrics_row(label, score(dishes, got)))

    lines += ["", "### Per language", "", _METRICS_HEADER.replace("Source", "Slice")]
    for language in sorted({dish.language for dish in dishes}):
        subset = [dish for dish in dishes if dish.language == language]
        for label, got in sources.items():
            lines.append(_metrics_row(f"{language}: {label}", score(subset, got)))

    lines += [
        "",
        "### Hidden carbs",
        "",
        "| Source | Labelled | Found | Recall (likely) | Recall (suspected) | "
        "Flagged | Matched a label | Precision |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for label, got in sources.items():
        result = score(dishes, got)
        likely = result.carbs_by_certainty.get("likely", [0, 0])
        suspected = result.carbs_by_certainty.get("suspected", [0, 0])
        lines.append(
            f"| {label} | {result.carbs_expected} | {result.carbs_found} | "
            f"{_of(likely[0], likely[1])} | {_of(suspected[0], suspected[1])} | "
            f"{result.carbs_flagged} | {result.carbs_flagged_matched} | "
            f"{percent(result.carb_precision)} |"
        )

    if results.runs:
        lines += [
            "",
            "### Model run per menu",
            "",
            "| Menu | Dishes | Requests | Latency (s) | Prompt tokens | "
            "Output tokens | Failures |",
            "|---|---:|---:|---:|---:|---:|---|",
        ]
        by_menu = {menu.id: menu for menu in results.menus}
        for run in results.runs:
            failures = (
                ", ".join(f"batch {batch}: {reason}" for batch, reason in run.failures)
                or "none"
            )
            menu = by_menu.get(run.menu)
            lines.append(
                f"| {run.menu} | {len(menu.dishes) if menu else '-'} | "
                f"{run.batches} | {run.latency_seconds:.1f} | "
                f"{run.tokens.get('prompt', '-')} | {run.tokens.get('output', '-')} | "
                f"{failures} |"
            )

    lines += ["", "### False greens", ""]
    rows: list[str] = []
    for dish in dishes:
        if dish.expected == "orderAsIs":
            continue
        cells = []
        wrong = False
        for got in sources.values():
            found = got.get(dish.key)
            verdict = found.verdict if found is not None else UNCLASSIFIED
            wrong = wrong or (verdict == "orderAsIs" and not dish.accepts(verdict))
            cells.append(verdict)
        if wrong:
            rows.append(
                f"| {dish.menu} | {_cell(dish.name)} | {dish.expected} | "
                + " | ".join(cells)
                + " |"
            )
    if rows:
        labels = list(sources)
        lines += [
            "| Menu | Dish | Expected | " + " | ".join(labels) + " |",
            "|---|---|---|" + "---|" * len(labels),
            *rows,
        ]
    else:
        lines.append("None.")
    return "\n".join(lines) + "\n"


_STATUS: Final = re.compile(r"\*\*Status:.*?\n\n", re.DOTALL)
_RESULT_HEADING: Final = "## Last result\n"


def update_page(page: str, report: str, results: Results) -> str:
    """``page`` (the text of ``docs/KETO_EVAL.md``) with its status paragraph
    naming the run and everything after its ``## Last result`` heading
    replaced by ``report``. A page without that heading gets it appended."""
    if results.model is None:
        status = (
            "**Status: not yet run.** No person has run the model evaluation, "
            "so this page holds no model figure. The rules-only tables under "
            f'"Last result" were made {results.when.strftime("%Y-%m-%d")} '
            f"from `{results.corpus}` with `--rules-only`"
            + (
                "."
                if results.corpus == _label(CORPUS_DIR)
                else ", which is not the keto corpus: they show the page's "
                "shape, not a measurement."
            )
            + "\n\n"
        )
    else:
        status = (
            f"**Status: last run {results.when.strftime('%Y-%m-%d')}.** The "
            'tables under "Last result" are that run\'s; they are measured '
            "against labels no dietitian has reviewed.\n\n"
        )
    updated = _STATUS.sub(lambda _: status, page, count=1)
    head, found, _ = updated.partition(_RESULT_HEADING)
    if not found:
        head = updated.rstrip("\n") + "\n\n"
    return f"{head}{_RESULT_HEADING}\n{report.rstrip()}\n"


# --- recording -------------------------------------------------------------------


REDACTED: Final = "[redacted]"


def redact(value: Any, secrets: Sequence[str]) -> Any:
    """``value`` with every non-empty string in ``secrets`` replaced by
    :data:`REDACTED` in every string (keys included), recursively."""
    if isinstance(value, str):
        for secret in secrets:
            if secret:
                value = value.replace(secret, REDACTED)
        return value
    if isinstance(value, list):
        return [redact(item, secrets) for item in value]
    if isinstance(value, dict):
        return {redact(k, secrets): redact(v, secrets) for k, v in value.items()}
    return value


def recording(run: MenuRun, model_id: str, secrets: Sequence[str]) -> dict[str, Any]:
    """What ``--record`` saves for one menu: the menu id, the configured
    model, and per batch the upstream status and body of every attempt,
    redacted. No request, no header and no key is ever part of it."""
    document: dict[str, Any] = redact(
        {"menu": run.menu, "model": model_id, "batches": run.replies}, secrets
    )
    return document


def write_recordings(
    runs: Iterable[MenuRun],
    model_id: str,
    secrets: Sequence[str],
    directory: Path | None = None,
) -> list[Path]:
    """Every run's :func:`recording`, one ``<menu>.json`` each, in
    ``directory`` (default :data:`RECORD_DIR`)."""
    directory = directory if directory is not None else RECORD_DIR
    directory.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for run in runs:
        path = directory / f"{run.menu}.json"
        text = json.dumps(recording(run, model_id, secrets), ensure_ascii=False)
        path.write_text(text + "\n", encoding="utf-8")
        written.append(path)
    return written


# --- the person-run evaluation ---------------------------------------------------


_USAGE_FIELDS: Final = (
    ("promptTokenCount", "prompt"),
    ("candidatesTokenCount", "output"),
    ("thoughtsTokenCount", "thoughts"),
    ("totalTokenCount", "total"),
)


def usage_of(body: object) -> dict[str, int]:
    """The token counters a Gemini body's ``usageMetadata`` exposes."""
    usage = body.get("usageMetadata") if isinstance(body, dict) else None
    if not isinstance(usage, dict):
        return {}
    return {
        name: usage[field_]
        for field_, name in _USAGE_FIELDS
        if isinstance(usage.get(field_), int) and not isinstance(usage[field_], bool)
    }


class Tap:
    """An httpx response hook that keeps every upstream body it sees, so the
    run can read the token counts and ``--record`` the raw reply that
    ``gemini.complete`` itself discards. It sees responses only: never a
    request, its headers or the key."""

    def __init__(self) -> None:
        self.bodies: list[tuple[int, Any]] = []

    async def __call__(self, response: httpx.Response) -> None:
        await response.aread()
        try:
            body: Any = response.json()
        except ValueError:
            body = response.text
        self.bodies.append((response.status_code, body))


async def run_menu(
    client: httpx.AsyncClient,
    settings: Settings,
    menu: CorpusMenu,
    tap: Tap,
    *,
    timeout: float,
    pause: Callable[[], Awaitable[None]],
) -> MenuRun:
    """``menu`` sent to the model, one request per batch (#188), each
    awaited for at most ``timeout`` seconds after ``pause``. A failure is
    recorded against its batch and the next batch is still sent."""
    source = menu.to_menu()
    batches = split_batches(
        source,
        max_dishes=batch_max_dishes(extract=False),
        max_chars=USER_PROMPT_MAX_CHARS,
    )
    run = MenuRun(menu.id, batches=len(batches))
    for number, batch in enumerate(batches, start=1):
        await pause()
        request = ChatRequest.model_construct(
            system_prompt=prompt.system_prompt(OPTIONS),
            user_prompt=prompt.user_prompt(batch),
            response_schema=prompt.response_schema(),
            schema_name=prompt.SCHEMA_NAME,
            images=[],
        )
        tap.bodies.clear()
        started = time.monotonic()
        failure: str | None = None
        content: str | None = None
        model = settings.GEMINI_MODEL
        try:
            reply = await asyncio.wait_for(
                gemini.complete(client, settings, request), timeout
            )
            content, model = reply.content, reply.model
        except TimeoutError:
            failure = "timeout"
        except BackendError as error:
            failure = error.reason
        run.latency_seconds += time.monotonic() - started
        for _, body in tap.bodies:
            for name, count in usage_of(body).items():
                run.tokens[name] = run.tokens.get(name, 0) + count
        if content is not None:
            verdicts = model_verdicts(content, batch, model=model)
            if verdicts is None:
                failure = "badResponse"
            else:
                run.verdicts.update(verdicts)
        if failure is not None:
            run.failures.append((number, failure))
        run.replies.append(
            {
                "batch": number,
                "failure": failure,
                "attempts": [
                    {"status": status, "body": body} for status, body in tap.bodies
                ],
            }
        )
    return run


async def evaluate(
    menus: Sequence[CorpusMenu],
    settings: Settings,
    *,
    timeout: float,
    delay: float,
) -> list[MenuRun]:
    """Every menu of ``menus`` run in order, one request at a time, with
    ``delay`` seconds between requests."""
    tap = Tap()
    sent = 0

    async def pause() -> None:
        nonlocal sent
        if sent and delay > 0:
            await asyncio.sleep(delay)
        sent += 1

    runs: list[MenuRun] = []
    async with httpx.AsyncClient(event_hooks={"response": [tap]}) as client:
        for menu in menus:
            print(f"{menu.id}: {len(menu.dishes)} dishes ...", flush=True)
            run = await run_menu(
                client, settings, menu, tap, timeout=timeout, pause=pause
            )
            for batch, reason in run.failures:
                print(f"  batch {batch} failed: {reason}", file=sys.stderr)
            runs.append(run)
    return runs


def current_commit(root: Path = REPO_ROOT) -> str:
    """The checkout's short commit id, or ``unknown``."""
    try:
        completed = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=root,
            capture_output=True,
            text=True,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return "unknown"
    return completed.stdout.strip() or "unknown"


def _label(path: Path) -> str:
    try:
        return path.resolve().relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser_ = argparse.ArgumentParser(
        description="Evaluate the keto corpus: rules, model and merged."
    )
    parser_.add_argument(
        "--timeout",
        type=float,
        default=180.0,
        help="seconds to wait for each request's reply (default: %(default)s)",
    )
    parser_.add_argument(
        "--delay",
        type=float,
        default=4.0,
        help="seconds to pause between requests (default: %(default)s)",
    )
    parser_.add_argument(
        "--menus",
        default="",
        help="comma-separated menu ids (or file names) to run; default all",
    )
    parser_.add_argument(
        "--corpus",
        type=Path,
        default=CORPUS_DIR,
        help="the directory of labelled menus (default: the keto corpus)",
    )
    parser_.add_argument(
        "--no-write",
        action="store_true",
        help="print the report instead of writing docs/KETO_EVAL.md",
    )
    parser_.add_argument(
        "--record",
        action="store_true",
        help="save each menu's raw replies, redacted, under "
        "test/fixtures/llm/keto_eval/",
    )
    parser_.add_argument(
        "--rules-only",
        action="store_true",
        help="score the rules alone; needs no key and sends nothing",
    )
    return parser_.parse_args(argv)


def select_menus(menus: Sequence[CorpusMenu], wanted: str) -> list[CorpusMenu]:
    """The menus ``wanted`` (comma-separated ids, a ``.json`` suffix
    allowed) names, in corpus order; all of them when it is blank. Raises
    ``ValueError`` naming any id the corpus does not hold."""
    names = [name.strip().removesuffix(".json") for name in wanted.split(",")]
    names = [name for name in names if name]
    if not names:
        return list(menus)
    known = {menu.id for menu in menus}
    unknown = [name for name in names if name not in known]
    if unknown:
        raise ValueError(f"no such corpus menu: {', '.join(unknown)}")
    return [menu for menu in menus if menu.id in names]


def main(argv: list[str]) -> int:
    """Run the evaluation; 0 when a report was produced and no request
    failed, 1 otherwise, 2 for a bad ``--menus``."""
    args = _parse_args(argv)
    key = os.environ.get("GEMINI_API_KEY", "").strip()
    if not args.rules_only and not key:
        print(
            "GEMINI_API_KEY is not set in the environment: nothing to evaluate. "
            "Set it (it is never read from a .env file), or pass --rules-only.",
            file=sys.stderr,
        )
        return 1
    try:
        menus = select_menus(load_corpus(args.corpus), args.menus)
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 2
    if not menus:
        print(f"no corpus menus under {args.corpus}", file=sys.stderr)
        return 1

    rules: Verdicts = {}
    for menu in menus:
        rules.update(rules_verdicts(menu))
    model: Verdicts | None = None
    runs: list[MenuRun] = []
    model_id: str | None = None
    if not args.rules_only:
        # Environment only: a key in backend/.env is never read here.
        settings = Settings(_env_file=None)  # type: ignore[call-arg]
        model_id = settings.GEMINI_MODEL
        runs = asyncio.run(
            evaluate(menus, settings, timeout=args.timeout, delay=args.delay)
        )
        model = {}
        for run in runs:
            model.update(run.verdicts)
        if args.record:
            for path in write_recordings(runs, model_id, [key]):
                print(f"recorded {path}")

    results = Results(
        menus=menus,
        rules=rules,
        model=model,
        runs=runs,
        when=datetime.now(UTC),
        model_id=model_id,
        commit=current_commit(),
        corpus=_label(args.corpus),
    )
    report = report_markdown(results)
    if args.no_write:
        print(report)
    else:
        page = REPORT_PATH.read_text(encoding="utf-8") if REPORT_PATH.exists() else ""
        REPORT_PATH.write_text(update_page(page, report, results), encoding="utf-8")
        print(f"wrote {REPORT_PATH}")
    return 1 if any(run.failures for run in runs) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
