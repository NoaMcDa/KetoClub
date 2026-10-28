"""The rules gate over the Israeli keto corpus, Python twin.

Replays ``test/fixtures/keto/menus/*.json`` through the ported rule engine
(``app.keto.heuristic``, via ``tools.keto_eval.rules_verdicts``) and holds
the same gate as the Dart one (``test/utils/keto/``): a dish whose verdict
is neither the expected one nor ``acceptable`` is a miss. The misses the
rules do not close yet are listed in
``test/fixtures/keto/known_keto_misses.json`` (``[{menu, dish, expected,
got, reason}]``), read by both twins: a miss that is not listed fails, and
so does a listed entry that no longer misses in exactly that way, so the
list can only shrink. The metrics are printed, never failing.

Skips cleanly while the corpus directory is absent or holds no dish. The
labels are unreviewed desk research.
"""

import pytest

from tools import keto_eval as ev

_MENUS = ev.load_corpus()
_DISHES = ev.all_dishes(_MENUS)
_RULES: ev.Verdicts = {}
for _menu in _MENUS:
    _RULES.update(ev.rules_verdicts(_menu))
_MISSES = ev.find_misses(_MENUS, _RULES)
_KNOWN = ev.load_known_misses()

needs_corpus = pytest.mark.skipif(
    not _DISHES, reason=f"no keto corpus under {ev.CORPUS_DIR}"
)


@needs_corpus
def test_prints_the_rules_metrics() -> None:
    result = ev.score(_DISHES, _RULES)
    print(
        f"\nketo corpus (rules only, {len(_MENUS)} menus, {len(_DISHES)} dishes)\n"
        f"  accuracy      {ev.percent(result.accuracy)}\n"
        f"  false green   {result.false_green}/{result.non_green} "
        f"({ev.percent(result.false_green_rate)})\n"
        f"  false red     {result.false_red}/{result.non_red} "
        f"({ev.percent(result.false_red_rate)})\n"
        f"  unclassified  {result.unclassified}\n"
        f"  hidden carbs  recall {ev.percent(result.carb_recall)}, "
        f"precision {ev.percent(result.carb_precision)}\n"
        f"  misses: {len(_MISSES)}, known: {len(_KNOWN)}"
    )
    assert result.dishes == len(_DISHES)
    assert result.unclassified == 0, "the rules place every dish"


@needs_corpus
def test_dish_ids_are_unique_within_each_menu() -> None:
    keys = [dish.key for dish in _DISHES]
    assert len(set(keys)) == len(keys)
    assert len({menu.id for menu in _MENUS}) == len(_MENUS)


def test_the_known_misses_are_well_formed() -> None:
    for entry in _KNOWN:
        assert set(entry) == ev.KNOWN_MISS_FIELDS
        assert all(isinstance(value, str) and value.strip() for value in entry.values())
        assert entry["expected"] in ev.VERDICTS
        assert entry["got"] in (*ev.VERDICTS, ev.UNCLASSIFIED)
    pairs = [(entry["menu"], entry["dish"]) for entry in _KNOWN]
    assert len(set(pairs)) == len(pairs), "duplicate entry"


@needs_corpus
def test_every_rules_miss_is_listed() -> None:
    unlisted = ev.unlisted_misses(_MISSES, _KNOWN)
    assert not unlisted, (
        "a dish the rules get wrong that known_keto_misses.json does not list "
        "(with that expected and got):\n" + "\n".join(str(miss) for miss in unlisted)
    )


@needs_corpus
def test_every_listed_miss_still_misses() -> None:
    stale = ev.stale_entries(_MISSES, _KNOWN)
    assert not stale, (
        "known_keto_misses.json lists a miss that is no longer one, or no "
        "longer that one; delete or correct the entry:\n"
        + "\n".join(
            f"{entry['menu']}  {entry['dish']}  expected {entry['expected']}, "
            f"listed as got {entry['got']}"
            for entry in stale
        )
    )
