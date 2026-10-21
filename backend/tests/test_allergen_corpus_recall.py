"""The rules-recall gate over the allergen safety corpus, Python twin (ALG-10).

Replays ``test/fixtures/allergens/menus/*.json`` through
``app.keto.rules.allergen_concerns`` and holds the same gate as
``test/utils/allergens/corpus_recall_test.dart``: for every strict
restriction a ``contains`` label needs a concern of at least ``likely``
certainty and a ``may_contain`` label one of at least ``suspected``. False
positives are printed, never failing. The misses the vocabulary does not
close yet are listed in ``test/fixtures/allergens/known_misses.json``, read
by both twins: a miss that is not listed fails, and so does a listed entry
that no longer misses, so the list can only shrink.

The labels are unreviewed desk research
(``test/fixtures/allergens/README.md``).
"""

import pytest

from app.keto.allergens import allergens
from tools import allergen_eval as ev

_DISHES = ev.load_corpus()
_FINDINGS = [ev.rules_findings(dish.to_dish()) for dish in _DISHES]
_MISSES = ev.find_misses(_DISHES, _FINDINGS)
_KNOWN = ev.load_known_misses()


def test_the_corpus_is_found() -> None:
    assert ev.CORPUS_DIR.is_dir()
    assert len({dish.menu for dish in _DISHES}) >= 15
    assert len(_DISHES) >= 300


def test_prints_per_restriction_recall_and_false_positives() -> None:
    counts = ev.tally(_DISHES, _FINDINGS)
    table = ev.recall_table(counts)
    print(
        f"\nallergen corpus recall (rules only, {len(_DISHES)} dishes)\n{table}\n"
        f"  misses: {len(_MISSES)}, known: {len(_KNOWN)}"
    )
    assert sum(count.contains for count in counts.values()) > 0


def test_the_allowlist_is_well_formed() -> None:
    for entry in _KNOWN:
        assert set(entry) == {"id", "menu", "dish", "label", "reason"}
        assert all(isinstance(value, str) and value.strip() for value in entry.values())
    keys = [ev.entry_key(entry) for entry in _KNOWN]
    assert len(set(keys)) == len(keys), "duplicate entry"


def test_every_strict_contains_and_may_contain_label_is_found() -> None:
    listed = {ev.entry_key(entry) for entry in _KNOWN}
    unlisted = [str(miss) for miss in _MISSES if miss.key not in listed]
    assert not unlisted, (
        "a label the rules miss and known_misses.json does not list:\n"
        + "\n".join(unlisted)
    )


def test_every_allowlisted_miss_still_misses() -> None:
    current = {miss.key for miss in _MISSES}
    stale = [
        f"{entry['id']}  {entry['menu']}  {entry['dish']!r}"
        for entry in _KNOWN
        if ev.entry_key(entry) not in current
    ]
    assert not stale, (
        "known_misses.json lists a miss that is no longer one (or names a "
        "label that does not exist); delete the entry:\n" + "\n".join(stale)
    )


def test_an_allowlist_entry_names_the_label_the_corpus_carries() -> None:
    by_key = {miss.key: miss for miss in _MISSES}
    wrong = [
        f"{ev.entry_key(entry)}: allowlist says {entry['label']}, "
        f"corpus {by_key[ev.entry_key(entry)].label}"
        for entry in _KNOWN
        if ev.entry_key(entry) in by_key
        and by_key[ev.entry_key(entry)].label != entry["label"]
    ]
    assert not wrong


def _measured_strict_ids() -> list[str]:
    """The strict ids with a vocabulary to measure. The research
    restrictions (issue #342) arrive with empty vocabularies, so the corpus
    carries no labels for them yet; each vocabulary follow-up brings its
    labels, and this gate then holds it to them."""
    vocabulary = allergens().vocabulary
    return [
        rid
        for rid in ev.strict_ids()
        if (entry := vocabulary[rid]).direct_en
        or entry.direct_he
        or entry.hidden_en
        or entry.hidden_he
    ]


@pytest.mark.parametrize("restriction_id", _measured_strict_ids())
def test_every_strict_restriction_has_labels_to_measure(restriction_id: str) -> None:
    counts = ev.tally(_DISHES, _FINDINGS)[restriction_id]
    assert counts.contains + counts.may_contain > 0
