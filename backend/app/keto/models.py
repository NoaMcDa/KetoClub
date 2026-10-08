"""Pydantic mirrors of the Dart wire models (architecture.md D25, #321).

Each class here is the Python twin of one Dart model in ``lib/models/``:
``menu.dart`` (``Menu``, ``MenuCategory``, ``Dish``, ``DishOption``),
``analysis.dart`` (``MenuAnalysed``, ``AnalysedDish``, ``HiddenCarb``,
``LlmEngine``/``RulesEngine``, ``AnalysisOptionsSnapshot``) and
``venue.dart`` (``VenueRef``, ``Venue``). The contract is that
``to_json(Model.model_validate(x)) == x`` for every ``x`` a Dart ``toJson``
wrote, down to key order and ``json.dumps`` bytes:

* **Field order is key order.** Fields are declared in the order the Dart
  ``toJson`` map literal writes them, and pydantic dumps in declaration
  order. Reordering a field here is a wire change.
* **No key is ever omitted.** Every Dart ``toJson`` in these files writes
  every key, null or not (``Dish.imageUrl``/``page``, ``Menu.venueName``,
  ``AnalysedDish.modification``/``netCarbsEstimate``,
  ``MenuAnalysed.options``, every optional ``Venue`` field), so ``to_json``
  never passes ``exclude_none``.
* **Doubles stay doubles.** Dart fields typed ``double`` (``Dish.price``,
  ``AnalysedDish.netCarbsEstimate``, ``Venue.latitude``/``longitude``/
  ``platformRating``) are ``float`` here: an incoming ``5`` is read as
  ``5.0`` and written back as ``5.0``. That is what the Dart VM writes too
  (``jsonEncode(5.0)`` is ``"5.0"``); only a Dart web build writes ``5``,
  and both Dart readers accept either, since they read ``num``. A JSON
  integer in a ``double`` position therefore does not round-trip byte for
  byte; its value does. Nor does a non-zero double under ``1e-4`` in
  magnitude, or one of at least ``1e16``: Python's ``repr`` switches to an
  exponent there (``1e-05``) where Dart's ``toString`` does not
  (``0.00001``), so the same value is spelled differently. No price,
  coordinate, rating or carb estimate falls in that range.
* **Timestamps stay strings.** ``Menu.fetchedAt`` and
  ``MenuAnalysed.analysedAt`` are kept exactly as the Dart
  ``DateTime.toIso8601String()`` wrote them (checked to parse, never
  re-rendered), so a round trip cannot change their precision or zone.

Reading mirrors each Dart ``tryFrom``: the same fields are required, the
same are non-empty, and the same few are read tolerantly (a missing or
malformed ``Dish.imageUrl``/``page`` reads as null, a missing
``hiddenCarbs`` as empty with malformed entries dropped, a missing or
non-int ``schemaVersion`` as 0). Types are strict, as Dart's ``is`` checks
are: ``"5"`` is not a number and ``true`` is not an int. The one deliberate
difference is ``extra="forbid"``: a Dart ``tryFrom`` ignores unknown keys,
but on this wire an unknown key means the two sides have drifted, and that
should fail loudly here rather than be dropped.

Python names are snake_case; the camelCase JSON names come from the
``to_camel`` alias generator rather than a per-field ``alias=``, because a
type checker reads an explicit ``alias`` as the ``__init__`` keyword (PEP
681) and would make ``Dish(imageUrl=...)`` the only spelling mypy accepts.
Both ``Dish(image_url=...)`` and ``Dish.model_validate({"imageUrl": ...})``
work at runtime.
"""

from datetime import datetime
from typing import Annotated, Any, Final, Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StrictInt,
    ValidationError,
    field_validator,
    model_validator,
)
from pydantic.alias_generators import to_camel

WIRE_CONFIG: Final = ConfigDict(
    alias_generator=to_camel,
    validate_by_name=True,
    validate_by_alias=True,
    serialize_by_alias=True,
    extra="forbid",
    strict=True,
    allow_inf_nan=False,
    frozen=True,
)
"""The configuration every wire model shares, request and response bodies in
``app.schemas`` included: camelCase on the wire, snake_case in Python,
unknown keys refused, Dart-strict types, no NaN or Infinity (which
``jsonEncode`` cannot write either), and immutable like the Dart models."""


class WireModel(BaseModel):
    """Base class of every camelCase wire model (``WIRE_CONFIG``)."""

    model_config = WIRE_CONFIG


def to_json(model: BaseModel) -> dict[str, Any]:
    """``model`` as the JSON object the matching Dart ``toJson`` writes.

    Camel-case keys in declaration order, every null kept, ``float`` fields
    as floats. ``json.dumps(to_json(m))`` is the byte form.
    """
    return model.model_dump(by_alias=True, mode="json")


NonEmptyStr = Annotated[str, Field(min_length=1)]
"""A string Dart's ``tryFrom`` rejects when empty (``isEmpty``)."""

MenuSourceName = Literal["wolt", "tenbis", "tabit", "ontopo", "scan", "website"]
"""The Dart ``MenuSource`` names, matched by string as ``tryParse`` does."""

Verdict = Literal["orderAsIs", "modifiable", "nonKeto"]
"""The Dart ``DishVerdict`` names."""

Certainty = Literal["suspected", "likely"]
"""The Dart ``HiddenCarbCertainty`` names."""

FailureReason = Literal[
    "notConfigured",
    "offline",
    "timeout",
    "rateLimited",
    "badResponse",
    "noDishesFound",
    "backendUnreachable",
    "consentWithheld",
    "apiKeyMissing",
    "apiKeyRejected",
]
"""The Dart ``MenuAnalysisFailureReason`` names: a ``RulesEngine.reason``."""


def _iso_timestamp(value: str) -> str:
    """``value`` unchanged when it parses as an ISO-8601 timestamp.

    Mirrors the Dart ``DateTime.tryParse`` check in ``Menu.tryFrom`` and
    ``MenuAnalysed.tryFrom``; the string itself is never re-rendered.
    """
    datetime.fromisoformat(value)
    return value


def _is_int(value: object) -> bool:
    """Whether ``value`` is what Dart's ``is int`` accepts: never a bool."""
    return isinstance(value, int) and not isinstance(value, bool)


# --- menu.dart ----------------------------------------------------------------


class VenueRef(WireModel):
    """Dart ``VenueRef``: ``{source, platformId}``."""

    source: MenuSourceName
    platform_id: NonEmptyStr

    @property
    def cache_key(self) -> str:
        """``source/platformId``, the Dart ``VenueRef.cacheKey``."""
        return f"{self.source}/{self.platform_id}"


class DishOption(WireModel):
    """Dart ``DishOption``: ``{name, values}``."""

    name: NonEmptyStr
    values: list[str]


class Dish(WireModel):
    """Dart ``Dish``: ``{id, name, description, price, options, imageUrl, page}``.

    ``description`` is ``""`` (never null) when absent or null. ``image_url``
    and ``page`` are read tolerantly, as Dart does: anything but a non-empty
    string, or an int of at least 1, reads as null. Both are always written,
    null included.
    """

    id: NonEmptyStr
    name: NonEmptyStr
    description: str = ""
    price: Annotated[float, Field(ge=0)]
    options: list[DishOption]
    image_url: str | None = None
    page: Annotated[int, Field(ge=1)] | None = None

    @field_validator("description", mode="before")
    @classmethod
    def _null_description_is_empty(cls, value: object) -> object:
        return "" if value is None else value

    @field_validator("image_url", mode="before")
    @classmethod
    def _tolerant_image_url(cls, value: object) -> object:
        return value if isinstance(value, str) and value else None

    @field_validator("page", mode="before")
    @classmethod
    def _tolerant_page(cls, value: object) -> object:
        if isinstance(value, int) and not isinstance(value, bool) and value >= 1:
            return value
        return None


class MenuCategory(WireModel):
    """Dart ``MenuCategory``: ``{id, name, dishes}``."""

    id: NonEmptyStr
    name: NonEmptyStr
    dishes: list[Dish]


class Menu(WireModel):
    """Dart ``Menu``: ``{venueRef, currency, fetchedAt, categories, venueName}``.

    ``fetched_at`` is the Dart ``toIso8601String()`` text, kept verbatim.
    ``venue_name`` may be absent or null (both read as null) and is always
    written.
    """

    venue_ref: VenueRef
    currency: NonEmptyStr
    fetched_at: str
    categories: list[MenuCategory]
    venue_name: str | None = None

    @field_validator("fetched_at")
    @classmethod
    def _fetched_at_is_iso(cls, value: str) -> str:
        return _iso_timestamp(value)

    def all_dishes(self) -> list[Dish]:
        """Every dish, flattened, category order kept: Dart ``allDishes``."""
        return [dish for category in self.categories for dish in category.dishes]


# --- analysis.dart -------------------------------------------------------------


class HiddenCarb(WireModel):
    """Dart ``HiddenCarb``: ``{source, certainty, waiterQuestion}``.

    ``source`` and ``waiter_question`` must be non-blank, as Dart's
    ``trim().isEmpty`` check requires.
    """

    source: str
    certainty: Certainty
    waiter_question: str

    @field_validator("source", "waiter_question")
    @classmethod
    def _not_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("must not be blank")
        return value


class AnalysedDish(WireModel):
    """Dart ``AnalysedDish``: ``{dishId, name, verdict, why, modification,
    netCarbsEstimate, hiddenCarbs}``.

    ``modification`` is a non-empty string exactly when ``verdict`` is
    ``modifiable`` and null otherwise, the invariant Dart's ``tryFrom``
    enforces. ``hidden_carbs`` reads absent, null or non-list as empty and
    drops each malformed entry silently, as Dart does (§9.4).
    """

    dish_id: NonEmptyStr
    name: NonEmptyStr
    verdict: Verdict
    why: NonEmptyStr
    modification: str | None = None
    net_carbs_estimate: float | None = None
    hidden_carbs: list[HiddenCarb] = Field(default_factory=list)

    @field_validator("hidden_carbs", mode="before")
    @classmethod
    def _tolerant_hidden_carbs(cls, value: object) -> list[HiddenCarb]:
        if not isinstance(value, list):
            return []
        kept: list[HiddenCarb] = []
        for entry in value:
            if isinstance(entry, HiddenCarb):
                kept.append(entry)
                continue
            if not isinstance(entry, dict):
                continue
            try:
                kept.append(HiddenCarb.model_validate(entry))
            except ValidationError:
                continue
        return kept

    @model_validator(mode="after")
    def _modification_matches_verdict(self) -> "AnalysedDish":
        if self.verdict == "modifiable":
            if not self.modification:
                raise ValueError("a modifiable dish needs a modification")
        elif self.modification is not None:
            raise ValueError("only a modifiable dish carries a modification")
        return self


class LlmEngine(WireModel):
    """Dart ``LlmEngine``: ``{kind: "llm", model}``."""

    kind: Literal["llm"] = "llm"
    model: NonEmptyStr


class RulesEngine(WireModel):
    """Dart ``RulesEngine``: ``{kind: "rules", reason}``."""

    kind: Literal["rules"] = "rules"
    reason: FailureReason


AnalysisEngine = Annotated[LlmEngine | RulesEngine, Field(discriminator="kind")]
"""Dart's sealed ``AnalysisEngine``, told apart by ``kind``."""


class AnalysisOptionsSnapshot(WireModel):
    """Dart ``AnalysisOptionsSnapshot``: ``{netCarbLimitGrams,
    dietaryConstraints}``. An absent or null ``dietaryConstraints`` reads as
    empty."""

    net_carb_limit_grams: StrictInt
    dietary_constraints: list[str] = Field(default_factory=list)

    @field_validator("dietary_constraints", mode="before")
    @classmethod
    def _null_constraints_are_none(cls, value: object) -> object:
        return [] if value is None else value


class MenuAnalysed(WireModel):
    """Dart ``MenuAnalysed``: ``{dishes, unclassified, engine, analysedAt,
    options, schemaVersion}``.

    ``analysed_at`` is kept verbatim like ``Menu.fetched_at``. ``options``
    may be absent or null (an analysis cached before #57). ``schema_version``
    reads absent, null or non-int as 0 and is always written.
    """

    dishes: list[AnalysedDish]
    unclassified: list[str]
    engine: AnalysisEngine
    analysed_at: str
    options: AnalysisOptionsSnapshot | None = None
    schema_version: int = 0

    @field_validator("analysed_at")
    @classmethod
    def _analysed_at_is_iso(cls, value: str) -> str:
        return _iso_timestamp(value)

    @field_validator("schema_version", mode="before")
    @classmethod
    def _tolerant_schema_version(cls, value: object) -> object:
        return value if _is_int(value) else 0


# --- venue.dart ----------------------------------------------------------------


class Venue(WireModel):
    """Dart ``Venue``: ``{ref, name, address, latitude, longitude, sourceUrl,
    cuisineTags, isOnline, imageUrl, shortDescription, platformRating,
    estimateMinutes, city}``.

    Only ``ref`` and a non-empty ``name`` are required. Every other field
    may be absent or null (``cuisine_tags`` then reads as empty) and is
    always written; a present value of the wrong type fails the whole venue,
    as ``Venue.tryFrom`` does.
    """

    ref: VenueRef
    name: NonEmptyStr
    address: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    source_url: str | None = None
    cuisine_tags: list[str] = Field(default_factory=list)
    is_online: bool | None = None
    image_url: str | None = None
    short_description: str | None = None
    platform_rating: float | None = None
    estimate_minutes: StrictInt | None = None
    city: str | None = None

    @field_validator("cuisine_tags", mode="before")
    @classmethod
    def _null_tags_are_none(cls, value: object) -> object:
        return [] if value is None else value
