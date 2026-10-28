"""A menu split into the batches one analysis request each covers (#188).

The Python twin of ``MenuAnalysisPrompt.batches`` and
``MenuAnalysisPrompt.batchMaxDishes`` in
``lib/services/classifier/menu_analysis_prompt.dart`` (architecture.md D6 as
D25 amends it). The golden ``batches.json`` pins the split and the two dish
ceilings equal across the languages: the client batches its own
``/v1/chat`` requests with the Dart split, and the server batches
``/v1/classify`` and ``/v1/venue-menus`` with this one, so the same menu is
asked about in the same pieces on every path.

The prompt budget is not here: it is ``USER_PROMPT_MAX_CHARS`` in
``app.schemas``, the bound ``ChatRequest.user_prompt`` enforces, which the
caller passes as ``max_chars``. A line is measured in UTF-16 code units, as
Dart's ``String.length`` measures it.

Pure: no framework, no I/O.
"""

from itertools import groupby
from typing import Final, NamedTuple

from app.keto.dart_text import utf16_len
from app.keto.models import Dish, Menu
from app.keto.prompt import dish_line

ANALYSIS_BATCH_MAX_DISHES: Final = 80
"""Dart ``llmBatchMaxDishes`` (``lib/utils/constants.dart``): the most dishes
one keto request asks about, sized so the worst reply (about 750 tokens a
dish in Hebrew) fits ``GEMINI_MAX_OUTPUT_TOKENS`` (65,536)."""

ANALYSIS_BATCH_MAX_DISHES_EXTRACT: Final = 35
"""Dart ``llmBatchMaxDishesWithExtraction``: the ceiling when the request
also extracts ingredients (Banto; ALG-03, D26 C2), about 1,750 tokens a
dish."""


class _Line(NamedTuple):
    """One dish's prompt line: its category's index, the dish, and the
    line's length without its prompt id, which is the dish's position in
    the batch it ends up in (Dart ``_PromptLine``)."""

    category: int
    dish: Dish
    rest: int

    def length(self, position: int) -> int:
        """Dart ``_lineLength``: the line's length as the ``position``th
        line of its request (the prompt id's digits and the rest)."""
        return len(str(position)) + self.rest


def batch_max_dishes(*, extract: bool) -> int:
    """Dart ``MenuAnalysisPrompt.batchMaxDishes``."""
    return ANALYSIS_BATCH_MAX_DISHES_EXTRACT if extract else ANALYSIS_BATCH_MAX_DISHES


def split_batches(menu: Menu, *, max_dishes: int, max_chars: int) -> list[Menu]:
    """Dart ``MenuAnalysisPrompt.batches``: ``menu`` as the fewest menus whose
    ``user_prompt`` is at most ``max_chars`` and which hold at most
    ``max_dishes`` dishes each.

    A menu that fits one request (the empty menu included) is returned as
    ``[menu]`` itself. Otherwise the dish ceiling is balanced to
    ``ceil(n / ceil(n / max_dishes))`` and the dishes are dealt out in menu
    order, a batch closing early when its next line (joined by one ``\\n``)
    would pass ``max_chars``. Each batch keeps ``menu``'s reference,
    currency, fetch time and venue name, and the categories its dishes come
    from under their own ids and names. Each batch's ``user_prompt`` numbers
    its own dishes from 1, and every line is measured with the prompt id it
    carries there.
    """
    lines = [
        _Line(index, dish, utf16_len(dish_line("", dish, category.name)))
        for index, category in enumerate(menu.categories)
        for dish in category.dishes
    ]
    count = len(lines)
    prompt_length = max(count - 1, 0) + sum(
        line.length(position) for position, line in enumerate(lines, start=1)
    )
    if count <= max_dishes and prompt_length <= max_chars:
        return [menu]

    batch_count = -(-count // max_dishes)
    target = -(-count // batch_count)
    groups: list[list[_Line]] = []
    current: list[_Line] = []
    current_length = 0
    for line in lines:
        added = (
            line.length(1)
            if not current
            else current_length + 1 + line.length(len(current) + 1)
        )
        if current and (len(current) >= target or added > max_chars):
            groups.append(current)
            current = []
            added = line.length(1)
        current.append(line)
        current_length = added
    groups.append(current)
    return [_batch_menu(menu, group) for group in groups]


def _batch_menu(menu: Menu, group: list[_Line]) -> Menu:
    """The menu holding ``group``'s dishes under ``menu``'s categories."""
    categories = [
        menu.categories[index].model_copy(
            update={"dishes": [line.dish for line in lines]}
        )
        for index, lines in groupby(group, key=lambda line: line.category)
    ]
    return menu.model_copy(update={"categories": categories})
