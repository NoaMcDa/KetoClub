"""Score the allergen safety corpus: rules alone, model alone, and merged.

ALG-10 (issue #352). The labelled corpus under ``test/fixtures/allergens/``
is the measuring stick; this module holds the **pure scoring** the CI recall
gate (``tests/test_allergen_corpus_recall.py``) and the evaluation run share,
and a person-run ``main`` that sends the corpus to a real model.

Two things live here:

* The pure part: loading the corpus, the rules' findings per dish, the
  findings read from a model reply's ingredients, the merge of the two, the
  gate's rule (a ``contains`` label needs a concern of at least ``likely``,
  a ``may_contain`` one at least ``suspected``) and the markdown report. It
  does no I/O but reading the corpus files, and the unit tests
  (``tests/test_allergen_eval.py``) exercise it offline.
* ``main``: the person-run evaluation. It makes real network calls, so no
  test imports it and ``check.sh``'s coverage (``--cov=app``) never counts
  it::

      cd backend
      GEMINI_API_KEY=... uv run python tools/allergen_eval.py

  Each corpus menu goes out as ONE request through the backend's own model
  client (``app.services.gemini.complete``) with the extraction prompt
  (``restrictions_requested`` on), exactly as ``/v1/classify`` would send it,
  and nothing is stored. With no key it says so and exits 1. The result is
  spliced into ``docs/ALLERGEN_EVAL.md``; pass ``--no-write`` to only print it.

The labels are unreviewed desk research (``test/fixtures/allergens/README.md``):
a number from this module is a question for the labels as much as for the
engine until a person with a clinical background has read them.
"""

import argparse
import asyncio
import inspect
import json
import re
import sys
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Final

import httpx

from app.config import Settings
from app.errors import BackendError
from app.keto import prompt
from app.keto.allergens import allergens, find
from app.keto.models import AnalysisOptionsSnapshot, Dish, DishOption, Menu
from app.keto.rules import allergen_concerns
from app.schemas import ChatRequest
from app.services import gemini

REPO_ROOT: Final = Path(__file__).resolve().parents[2]
"""The repository root (this file is ``backend/tools/allergen_eval.py``)."""

CORPUS_DIR: Final = REPO_ROOT / "test" / "fixtures" / "allergens" / "menus"
"""The labelled menus, one JSON file each."""

KNOWN_MISSES_PATH: Final = (
    REPO_ROOT / "test" / "fixtures" / "allergens" / ("known_misses.json")
)
"""The reviewed allowlist of misses the vocabulary does not close yet."""

REPORT_PATH: Final = REPO_ROOT / "docs" / "ALLERGEN_EVAL.md"
"""Where ``main`` writes the last result."""

CERTAINTY_RANK: Final[Mapping[str, int]] = {"stated": 0, "likely": 1, "suspected": 2}
"""Dart ``Certainty.index``: a lower rank is a surer finding."""

REQUIRED_CERTAINTY: Final[Mapping[str, str]] = {
    "contains": "likely",
    "may_contain": "suspected",
}
"""The weakest certainty the gate accepts for each non-free label."""

Findings = dict[str, str]
"""A dish's findings: restriction id to the surest certainty found."""


@dataclass(frozen=True, slots=True)
class CorpusDish:
    """One labelled dish of one corpus menu."""

    menu: str
    index: int
    name: str
    description: str
    options: tuple[tuple[str, tuple[str, ...]], ...]
    labels: Mapping[str, Mapping[str, Any]]

    def label_of(self, restriction_id: str) -> str | None:
        """``contains``, ``may_contain`` or ``free``; None when unlabelled."""
        label = self.labels.get(restriction_id)
        return None if label is None else str(label["label"])

    def to_dish(self) -> Dish:
        """The dish as the engine sees it, as the Dart test builds it."""
        return Dish.model_construct(
            id=f"{self.menu}#{self.index}",
            name=self.name,
            description=self.description,
            price=0.0,
            options=[
                DishOption.model_construct(name=name, values=list(values))
                for name, values in self.options
            ],
            image_url=None,
            page=None,
        )


def load_corpus(directory: Path = CORPUS_DIR) -> list[CorpusDish]:
    """Every dish of every ``*.json`` menu in ``directory``, files sorted by
    name and dishes in file order."""
    dishes: list[CorpusDish] = []
    for path in sorted(directory.glob("*.json")):
        document = json.loads(path.read_text(encoding="utf-8"))
        for index, raw in enumerate(document["dishes"]):
            dishes.append(
                CorpusDish(
                    menu=path.name,
                    index=index,
                    name=raw["name"],
                    description=raw["description"],
                    options=tuple(
                        (option["name"], tuple(option["values"]))
                        for option in raw["options"]
                    ),
                    labels=raw["labels"],
                )
            )
    return dishes


def strict_ids() -> list[str]:
    """The strict restriction ids, in taxonomy order, from the packaged
    taxonomy (allergens, celiac disease and fava for G6PD), without ``custom``: the user's
    own restriction (ALG-17) is strict but has no vocabulary to measure,
    since its words live in the profile on the device."""
    return [r.id for r in allergens().taxonomy if r.is_strict and r.id != "custom"]


def surer(first: str | None, second: str | None) -> str | None:
    """The surer of two certainties; None is the weakest of all."""
    if first is None:
        return second
    if second is None:
        return first
    return first if CERTAINTY_RANK[first] <= CERTAINTY_RANK[second] else second


def weaker(first: str, second: str) -> str:
    """The weaker of two certainties (Dart ``ProfileEvaluator._weaker``)."""
    return first if CERTAINTY_RANK[first] >= CERTAINTY_RANK[second] else second


def rules_findings(dish: Dish) -> Findings:
    """What the rules pass finds on ``dish``: one entry per restriction,
    its surest certainty (``allergen_concerns``)."""
    return {
        concern.restriction_id: concern.certainty for concern in allergen_concerns(dish)
    }


def model_findings(ingredients: object) -> Findings:
    """What a model reply's ``ingredients`` for one dish amount to: the
    allergen matcher run on each ingredient's name, a hit's certainty cut to
    the weaker of the ingredient's and the trigger's (Dart
    ``ProfileEvaluator._evidence``). Anything malformed is skipped."""
    found: Findings = {}
    if not isinstance(ingredients, list):
        return found
    for entry in ingredients:
        if not isinstance(entry, dict):
            continue
        name = entry.get("name")
        certainty = entry.get("certainty")
        if not isinstance(name, str) or not isinstance(certainty, str):
            continue
        if certainty not in CERTAINTY_RANK:
            continue
        for hit in find(name):
            cut = weaker(certainty, hit.certainty)
            found[hit.id] = surer(found.get(hit.id), cut) or cut
    return found


def merge(*sources: Mapping[str, str]) -> Findings:
    """The surest certainty per restriction across ``sources``."""
    merged: Findings = {}
    for source in sources:
        for restriction_id, certainty in source.items():
            merged[restriction_id] = surer(merged.get(restriction_id), certainty) or (
                certainty
            )
    return merged


def meets(found: str | None, label: str) -> bool:
    """Whether ``found`` satisfies the gate for a ``contains`` or
    ``may_contain`` ``label``."""
    return found is not None and (
        CERTAINTY_RANK[found] <= CERTAINTY_RANK[REQUIRED_CERTAINTY[label]]
    )


@dataclass(frozen=True, slots=True)
class Miss:
    """A strict label the findings did not meet."""

    restriction_id: str
    menu: str
    dish: str
    label: str
    found: str | None

    @property
    def key(self) -> str:
        """What an allowlist entry matches: ``id|menu|dish``."""
        return f"{self.restriction_id}|{self.menu}|{self.dish}"

    def __str__(self) -> str:
        return (
            f"{self.restriction_id}  {self.menu}  {self.dish!r}  {self.label}  "
            f"found: {self.found or 'nothing'}"
        )


def find_misses(
    dishes: Sequence[CorpusDish],
    findings: Sequence[Mapping[str, str]],
    ids: Sequence[str] | None = None,
) -> list[Miss]:
    """Every ``contains`` or ``may_contain`` label of a strict restriction
    that ``findings`` (one mapping per dish, same order) does not meet."""
    chosen = list(ids) if ids is not None else strict_ids()
    misses: list[Miss] = []
    for dish, found in zip(dishes, findings, strict=True):
        for restriction_id in chosen:
            label = dish.label_of(restriction_id)
            if label not in REQUIRED_CERTAINTY:
                continue
            assert label is not None
            if not meets(found.get(restriction_id), label):
                misses.append(
                    Miss(
                        restriction_id,
                        dish.menu,
                        dish.name,
                        label,
                        found.get(restriction_id),
                    )
                )
    return misses


@dataclass(slots=True)
class Tally:
    """One restriction's counts. ``fp_free`` counts dishes explicitly
    labelled ``free`` that drew a concern; ``fp_unlabelled`` counts dishes
    with no label that did (absence means free, but a label gap is likelier
    there than a false alarm)."""

    contains: int = 0
    contains_hit: int = 0
    may_contain: int = 0
    may_contain_hit: int = 0
    fp_free: int = 0
    fp_unlabelled: int = 0


def tally(
    dishes: Sequence[CorpusDish],
    findings: Sequence[Mapping[str, str]],
    ids: Sequence[str] | None = None,
) -> dict[str, Tally]:
    """Recall and false positives per restriction in ``ids`` (default: the
    strict ones)."""
    chosen = list(ids) if ids is not None else strict_ids()
    counts = {restriction_id: Tally() for restriction_id in chosen}
    for dish, found in zip(dishes, findings, strict=True):
        for restriction_id, count in counts.items():
            label = dish.label_of(restriction_id)
            got = found.get(restriction_id)
            if label == "contains":
                count.contains += 1
                count.contains_hit += meets(got, "contains")
            elif label == "may_contain":
                count.may_contain += 1
                count.may_contain_hit += meets(got, "may_contain")
            elif got is not None and label == "free":
                count.fp_free += 1
            elif got is not None and label is None:
                count.fp_unlabelled += 1
    return counts


def percent(hit: int, total: int) -> str:
    """``hit`` of ``total`` as ``93.6%``, or ``-`` when ``total`` is zero."""
    return "-" if total == 0 else f"{100 * hit / total:.1f}%"


def recall_table(counts: Mapping[str, Tally]) -> str:
    """The plain-text table the CI gate prints."""
    rows = [
        f"  {'restriction':<12} {'contains':>9}  recall  {'may_contain':>11}  "
        f"recall  FP(free)  FP(unlabelled)"
    ]
    total = Tally()
    for restriction_id, count in counts.items():
        rows.append(
            f"  {restriction_id:<12} "
            f"{f'{count.contains_hit}/{count.contains}':>9}  "
            f"{percent(count.contains_hit, count.contains):>6}  "
            f"{f'{count.may_contain_hit}/{count.may_contain}':>11}  "
            f"{percent(count.may_contain_hit, count.may_contain):>6}  "
            f"{count.fp_free:>8}  {count.fp_unlabelled:>14}"
        )
        total.contains += count.contains
        total.contains_hit += count.contains_hit
        total.may_contain += count.may_contain
        total.may_contain_hit += count.may_contain_hit
    rows.append(
        f"  {'all strict':<12} "
        f"{f'{total.contains_hit}/{total.contains}':>9}  "
        f"{percent(total.contains_hit, total.contains):>6}  "
        f"{f'{total.may_contain_hit}/{total.may_contain}':>11}  "
        f"{percent(total.may_contain_hit, total.may_contain):>6}"
    )
    return "\n".join(rows)


def load_known_misses(path: Path = KNOWN_MISSES_PATH) -> list[dict[str, str]]:
    """The allowlist entries, as written."""
    document = json.loads(path.read_text(encoding="utf-8"))
    return [dict(entry) for entry in document["misses"]]


def entry_key(entry: Mapping[str, str]) -> str:
    """The ``id|menu|dish`` key of an allowlist entry."""
    return f"{entry['id']}|{entry['menu']}|{entry['dish']}"


# --- the person-run evaluation ---------------------------------------------------


@dataclass(slots=True)
class MenuRun:
    """One corpus menu's model result: per-dish ingredient lists keyed by
    dish index, or why there are none."""

    menu: str
    ingredients: dict[int, list[Any]] = field(default_factory=dict)
    error: str | None = None


def ingredients_by_dish(body: str, menu: Menu) -> dict[int, list[Any]]:
    """The ``ingredients`` the model's reply ``body`` gives each dish of
    ``menu``, keyed by the dish's position in the menu. The reply is
    untrusted: a dish id the menu does not hold, or an entry that is not an
    object, is dropped. Returns an empty dict for a reply that is not
    JSON."""
    try:
        document = json.loads(body)
    except ValueError:
        return {}
    raw_dishes = document.get("dishes") if isinstance(document, dict) else None
    if not isinstance(raw_dishes, list):
        return {}
    positions = {dish.id: i for i, dish in enumerate(menu.all_dishes())}
    out: dict[int, list[Any]] = {}
    for raw in raw_dishes:
        if not isinstance(raw, dict):
            continue
        position = positions.get(str(raw.get("id")))
        ingredients = raw.get("ingredients")
        if position is not None and isinstance(ingredients, list):
            out[position] = ingredients
    return out


def _corpus_menu(menu_name: str, dishes: Sequence[CorpusDish]) -> Menu:
    """The corpus menu ``menu_name`` as one category of its dishes."""
    return Menu.model_validate(
        {
            "venueRef": {"source": "scan", "platformId": f"corpus-{menu_name}"},
            "currency": "ILS",
            "fetchedAt": "2026-01-01T00:00:00.000Z",
            "categories": [
                {
                    "id": "corpus",
                    "name": menu_name,
                    "dishes": [
                        {
                            "id": f"{dish.menu}#{dish.index}",
                            "name": dish.name,
                            "description": dish.description,
                            "price": 0,
                            "options": [
                                {"name": name, "values": list(values)}
                                for name, values in dish.options
                            ],
                        }
                        for dish in dishes
                    ],
                }
            ],
        }
    )


def extraction_supported() -> bool:
    """Whether this checkout's prompt module knows the extraction request
    (``restrictions_requested`` and the ``extract`` schema flag)."""
    return "extract" in inspect.signature(prompt.response_schema).parameters


def _extraction_schema() -> dict[str, Any]:
    """The reply schema with ``ingredients`` required, when this checkout's
    prompt module can build it (see :func:`extraction_supported`)."""
    build: Callable[..., dict[str, Any]] = prompt.response_schema
    return build(extract=True)


def render_report(
    *,
    dishes: Sequence[CorpusDish],
    rules: Sequence[Mapping[str, str]],
    model: Sequence[Mapping[str, str]],
    model_id: str,
    failed_menus: Sequence[str],
    when: datetime,
) -> str:
    """The markdown of a run's results: the run's facts, then one table per
    source (rules alone, model alone, merged). :func:`update_page` splices it
    into ``docs/ALLERGEN_EVAL.md``."""
    merged = [merge(r, m) for r, m in zip(rules, model, strict=True)]
    sections = {
        "Rules alone": tally(dishes, rules),
        "Model alone": tally(dishes, model),
        "Merged (rules and model)": tally(dishes, merged),
    }
    lines = [
        f"Run: {when.strftime('%Y-%m-%d %H:%M UTC')}. Model id: `{model_id}`. "
        f"Dishes: {len(dishes)}. Menus the model did not answer for: "
        f"{', '.join(failed_menus) if failed_menus else 'none'}.",
        "",
    ]
    for title, counts in sections.items():
        lines += [
            f"## {title}",
            "",
            "| Restriction | contains | recall | may_contain | recall | FP (free) |",
            "|---|---:|---:|---:|---:|---:|",
        ]
        for restriction_id, count in counts.items():
            lines.append(
                f"| {restriction_id} | {count.contains_hit}/{count.contains} | "
                f"{percent(count.contains_hit, count.contains)} | "
                f"{count.may_contain_hit}/{count.may_contain} | "
                f"{percent(count.may_contain_hit, count.may_contain)} | "
                f"{count.fp_free} |"
            )
        lines.append("")
    return "\n".join(lines)


_STATUS: Final = re.compile(r"\*\*Status:.*?\n\n", re.DOTALL)
_RESULT_HEADING: Final = "## Last result\n"


def update_page(page: str, results: str, when: datetime) -> str:
    """``page`` (the text of ``docs/ALLERGEN_EVAL.md``) with its status
    paragraph naming the run at ``when`` and everything after its ``## Last
    result`` heading replaced by ``results``. A page without that heading
    gets it appended."""
    status = (
        f"**Status: last run {when.strftime('%Y-%m-%d')}.** The tables under "
        '"Last result" are that run\'s; they are measured against labels no '
        "clinical reviewer has read.\n\n"
    )
    updated = _STATUS.sub(lambda _: status, page, count=1)
    head, found, _ = updated.partition(_RESULT_HEADING)
    if not found:
        head = updated.rstrip("\n") + "\n\n"
    return f"{head}{_RESULT_HEADING}\n{results.rstrip()}\n"


async def _run_menu(
    client: httpx.AsyncClient,
    settings: Settings,
    menu_name: str,
    dishes: Sequence[CorpusDish],
) -> MenuRun:
    menu = _corpus_menu(menu_name, dishes)
    options = AnalysisOptionsSnapshot(
        net_carb_limit_grams=6,
        dietary_constraints=[],
        restrictions_requested=True,
    )
    request = ChatRequest.model_construct(
        system_prompt=prompt.system_prompt(options),
        user_prompt=prompt.user_prompt(menu),
        response_schema=_extraction_schema(),
        schema_name=prompt.SCHEMA_NAME,
        images=[],
    )
    try:
        reply = await gemini.complete(client, settings, request)
    except BackendError as error:
        return MenuRun(menu_name, error=error.reason)
    return MenuRun(menu_name, ingredients_by_dish(reply.content, menu))


async def _evaluate(
    dishes: list[CorpusDish], timeout: float
) -> tuple[list[Findings], str, list[str]]:
    settings = Settings()
    by_menu: dict[str, list[CorpusDish]] = {}
    for dish in dishes:
        by_menu.setdefault(dish.menu, []).append(dish)
    model: dict[tuple[str, int], Findings] = {}
    failed: list[str] = []
    async with httpx.AsyncClient(timeout=timeout) as client:
        for menu_name, menu_dishes in by_menu.items():
            print(f"{menu_name}: {len(menu_dishes)} dishes ...", flush=True)
            run = await _run_menu(client, settings, menu_name, menu_dishes)
            if run.error is not None:
                print(f"  failed: {run.error}", file=sys.stderr)
                failed.append(menu_name)
                continue
            for position, ingredients in run.ingredients.items():
                model[(menu_name, position)] = model_findings(ingredients)
    per_dish = [model.get((dish.menu, dish.index), {}) for dish in dishes]
    return per_dish, settings.GEMINI_MODEL, failed


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser_ = argparse.ArgumentParser(
        description="Evaluate the allergen corpus: rules, model and merged."
    )
    parser_.add_argument(
        "--timeout",
        type=float,
        default=180.0,
        help="seconds to wait for each menu's reply (default: %(default)s)",
    )
    parser_.add_argument(
        "--no-write",
        action="store_true",
        help="print the report instead of writing docs/ALLERGEN_EVAL.md",
    )
    return parser_.parse_args(argv)


def main(argv: list[str]) -> int:
    """Run the evaluation; 0 when a report was produced."""
    args = _parse_args(argv)
    if not Settings().llm_configured:
        print("GEMINI_API_KEY is not set: nothing to evaluate.", file=sys.stderr)
        return 1
    if not extraction_supported():
        print(
            "this checkout's prompt module has no extraction request "
            "(ALG-03): the model would not be asked for ingredients.",
            file=sys.stderr,
        )
        return 1
    dishes = load_corpus()
    model, model_id, failed = asyncio.run(_evaluate(dishes, args.timeout))
    rules = [rules_findings(dish.to_dish()) for dish in dishes]
    when = datetime.now(UTC)
    report = render_report(
        dishes=dishes,
        rules=rules,
        model=model,
        model_id=model_id,
        failed_menus=failed,
        when=when,
    )
    if args.no_write:
        print(report)
    else:
        page = REPORT_PATH.read_text(encoding="utf-8") if REPORT_PATH.exists() else ""
        REPORT_PATH.write_text(update_page(page, report, when), encoding="utf-8")
        print(f"wrote {REPORT_PATH}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
