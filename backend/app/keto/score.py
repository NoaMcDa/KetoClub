"""The keto score and the food-only verdict counts it is computed from.

The Python twins of ``lib/utils/keto_score.dart`` and
``lib/utils/verdict_counts.dart`` (architecture.md D13, D21, D25).

``score = 10 * (green + 0.5 * otherYellow + 0.25 * hiddenYellow) / total``,
rounded to one decimal the way Dart's ``toStringAsFixed(1)`` rounds: on the
**exact binary value** of the double, ties away from zero (``1.25`` becomes
``1.3``, where Python's ``round`` gives ``1.2``). Unclassified dishes play no
part; a total of zero is ``None``, never ``0.0``. A UI ranking heuristic
with no nutrition basis (D13).

Only food counts (D21): :meth:`VerdictCounts.of` reads each analysed dish's
kind from :func:`app.keto.dish_kind.dish_kinds_of`, and a dish id the menu
does not hold counts as food.
"""

from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal
from typing import ClassVar

from app.keto.dish_kind import DishKind, dish_kinds_of
from app.keto.models import Menu, MenuAnalysed
from app.keto.vocabulary import vocabulary

_ONE_DECIMAL = Decimal("0.1")


def dart_to_fixed_1(value: float) -> float:
    """``double.parse(value.toStringAsFixed(1))`` for a finite ``value``.

    ``Decimal(value)`` is the double's exact binary value, so a tie is a
    real tie (``1.25``) and ``0.15`` (really ``0.1499...``) rounds down, as
    in Dart.
    """
    return float(Decimal(value).quantize(_ONE_DECIMAL, rounding=ROUND_HALF_UP))


def keto_score(
    *,
    green_count: int,
    hidden_carb_yellow_count: int,
    other_yellow_count: int,
    red_count: int,
) -> float | None:
    """Dart ``ketoScore``: the menu's keto score out of 10, or ``None`` when
    no dish was placed."""
    total = green_count + hidden_carb_yellow_count + other_yellow_count + red_count
    if total == 0:
        return None
    weights = vocabulary().keto_score_weights
    weighted = (
        green_count
        + weights.yellow * other_yellow_count
        + weights.hidden_carb_yellow * hidden_carb_yellow_count
    )
    return dart_to_fixed_1(10 * weighted / total)


@dataclass(frozen=True, slots=True)
class VerdictCounts:
    """Dart ``VerdictCounts``: how many *food* dishes an analysis placed in
    each verdict. ``hidden_carb_yellow`` is the part of ``yellow`` demoted
    from green by a hidden-carb flag (issue #213)."""

    green: int
    yellow: int
    hidden_carb_yellow: int
    red: int

    ZERO: ClassVar["VerdictCounts"]

    def __post_init__(self) -> None:
        if self.hidden_carb_yellow > self.yellow:
            raise ValueError("hidden-carb yellows are yellows")

    @classmethod
    def of(cls, menu: Menu, analysis: MenuAnalysed) -> "VerdictCounts":
        """Dart ``VerdictCounts.of``: the food-only counts of ``analysis``
        over ``menu``."""
        kinds = dish_kinds_of(menu)
        green = yellow = hidden = red = 0
        for dish in analysis.dishes:
            if not kinds.get(dish.dish_id, DishKind.FOOD).counts_toward_score:
                continue
            if dish.verdict == "orderAsIs":
                green += 1
            elif dish.verdict == "modifiable":
                yellow += 1
                if dish.hidden_carbs:
                    hidden += 1
            else:
                red += 1
        return cls(green=green, yellow=yellow, hidden_carb_yellow=hidden, red=red)

    @property
    def other_yellow(self) -> int:
        """The yellows that are not hidden-carb demotions."""
        return self.yellow - self.hidden_carb_yellow

    @property
    def total(self) -> int:
        """Every placed food dish."""
        return self.green + self.yellow + self.red

    @property
    def score(self) -> float | None:
        """:func:`keto_score` over these counts: ``None`` when no food dish
        was placed."""
        return keto_score(
            green_count=self.green,
            hidden_carb_yellow_count=self.hidden_carb_yellow,
            other_yellow_count=self.other_yellow,
            red_count=self.red,
        )


VerdictCounts.ZERO = VerdictCounts(green=0, yellow=0, hidden_carb_yellow=0, red=0)
