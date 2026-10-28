"""The rules gate over the Israeli keto corpus, Python twin.

Replays ``test/fixtures/keto/menus/*.json`` through the ported rule engine
(``app.keto.heuristic``, via ``tools.keto_eval.rules_verdicts``) and holds
the same gate as ``test/utils/keto/keto_corpus_gate_test.dart``: **only
false greens fail** (a dish expected ``modifiable`` or ``nonKeto`` that the
rules call ``orderAsIs``, when ``acceptable`` does not list it). The false
greens the rules do not close yet are listed in
``test/fixtures/keto/known_keto_misses.json`` (``[{menu, dish, expected,
got, reason}]``, false greens only), read by both twins: an unlisted false
green fails, and so does a listed entry that is no longer a false green or
whose ``expected`` or ``got`` changed, so the list can only shrink. Every
other disagreement, and the metrics, are printed and never fail.

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
def test_prints_the_rules_metrics_and_every_other_disagreement() -> None:
    result = ev.score(_DISHES, _RULES)
    others = [miss for miss in _MISSES if not miss.is_false_green]
    todo = sum(entry.get("reason") == "TODO" for entry in _KNOWN)
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
        f"  known misses: {len(_KNOWN)} listed, {todo} still read TODO\n"
        f"  other disagreements (printed, never failing): {len(others)}\n"
        + "".join(f"    {miss}\n" for miss in others)
    )
    assert result.dishes == len(_DISHES)
    assert result.unclassified == 0, "the rules place every dish"


@needs_corpus
def test_dish_ids_are_unique_within_each_menu() -> None:
    keys = [dish.key for dish in _DISHES]
    assert len(set(keys)) == len(keys), "duplicate dish id"
    assert len({menu.id for menu in _MENUS}) == len(_MENUS), "duplicate menu id"


def test_the_known_misses_are_well_formed() -> None:
    for entry in _KNOWN:
        assert set(entry) == set(ev.KNOWN_MISS_FIELDS)
        assert all(isinstance(value, str) and value.strip() for value in entry.values())
    keys = [ev.entry_key(entry) for entry in _KNOWN]
    assert len(set(keys)) == len(keys), "duplicate entry"


@needs_corpus
def test_every_false_green_is_a_known_miss() -> None:
    unlisted = ev.unlisted_false_greens(_MISSES, _KNOWN)
    assert not unlisted, (
        "a dish expected modifiable or nonKeto that the rules call orderAsIs, "
        "and known_keto_misses.json does not list:\n"
        + "\n".join(str(miss) for miss in unlisted)
    )


@needs_corpus
def test_every_known_miss_is_still_a_false_green() -> None:
    stale = ev.stale_known_misses(_MISSES, _KNOWN)
    assert not stale, (
        "known_keto_misses.json lists a dish that is no longer a false green, "
        "or whose expected or got changed; delete or correct the entry:\n"
        + "\n".join(
            f"{entry['menu']}  {entry['dish']}  expected {entry['expected']}, "
            f"listed as got {entry['got']}"
            for entry in stale
        )
    )
