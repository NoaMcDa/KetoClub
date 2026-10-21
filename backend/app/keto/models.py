"""Pydantic mirrors of the Dart wire models (architecture.md D25, #321).

Each class here is the Python twin of one Dart model in ``lib/models/``:
``menu.dart`` (``Menu``, ``MenuCategory``, ``Dish``, ``DishOption``),
``analysis.dart`` (``MenuAnalysed``, ``AnalysedDish``, ``HiddenCarb``,
``LlmEngine``/``RulesEngine``, ``AnalysisOptionsSnapshot``), ``concern.dart``
(``Concern``, ``ExtractedIngredient``; Banto, D26 W2-0) and
``venue.dart`` (``VenueRef``, ``Venue``). The contract is that
``to_json(Model.model_validate(x)) == x`` for every ``x`` a Dart ``toJson``
wrote, down to key order and ``json.dumps`` bytes:

* **Field order is key order.** Fields are declared in the order the Dart
  ``toJson`` map literal writes them, and pydantic dumps in declaration
  order. Reordering a field here is a wire change.
* **No key is omitted, with four exceptions.** Every Dart ``toJson`` in
  these files writes every key, null or not (``Dish.imageUrl``/``page``,
  ``Menu.venueName``, ``AnalysedDish.modification``/``netCarbsEstimate``,
  ``MenuAnalysed.options``, every optional ``Venue`` field), so ``to_json``
  never passes ``exclude_none``. The exceptions are Banto's (D26 C2, C3):
  ``AnalysedDish.ingredients`` and ``concerns`` are written only when
  non-empty and ``AnalysisOptionsSnapshot.restrictionsRequested`` only when
  true, by a ``model_serializer`` on each model, so a keto analysis is the
  same bytes it was before they existed; ``Dish.declaredTags`` (ALG-09) is
  written only when non-empty, the same way.
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
``hiddenCarbs``, ``ingredients`` or ``concerns`` as empty with malformed
entries dropped, a missing or non-true ``restrictionsRequested`` as false, a
missing or non-int ``schemaVersion`` as 0). Types are strict, as Dart's
``is`` checks are: ``"5"`` is not a number and ``true`` is not an int. The one
deliberate difference is ``extra="forbid"``: a Dart ``tryFrom`` ignores
unknown keys, but on this wire an unknown key means the two sides have
drifted, and that should fail loudly here rather than be dropped. Inside the
tolerant lists that difference drops the entry, as any other malformed entry
is dropped.

Python names are snake_case; the camelCase JSON names come from the
``to_camel`` alias generator rather than a per-field ``alias=``, because a
type checker reads an explicit ``alias`` as the ``__init__`` keyword (PEP
681) and would make ``Dish(imageUrl=...)`` the only spelling mypy accepts.
Both ``Dish(image_url=...)`` and ``Dish.model_validate({"imageUrl": ...})``
work at runtime.
"""

from datetime import datetime
from typing import Annotated, Any, Final, Literal, get_args

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    SerializerFunctionWrapHandler,
    StrictInt,
    ValidationError,
    field_validator,
    model_serializer,
    model_validator,
)
from pydantic.alias_generators import to_camel

from app.keto.dart_text import dart_trim

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

HiddenCarbCertainty = Literal["suspected", "likely"]
"""The Dart ``HiddenCarbCertainty`` names."""

RestrictionIdName = Literal[
    "peanuts",
    "treeNuts",
    "milk",
    "lactose",
    "eggs",
    "soy",
    "wheat",
    "gluten",
    "fish",
    "crustaceans",
    "molluscs",
    "sesame",
    "celery",
    "mustard",
    "lupin",
    "sulphites",
    "legumes",
    "alphaGal",
    "fodmap",
    "histamine",
    "vegan",
    "vegetarian",
    "glp1",
    "buckwheat",
    "kiwi",
    "peach",
    "apple",
    "banana",
    "orange",
    "beef",
    "pork",
    "chicken",
    "gelatin",
    "yam",
    "corn",
    "sunflower",
    "flax",
    "chickpea",
    "lentil",
    "pea",
    "fenugreek",
    "fava",
    "nightshades",
    "msg",
    "caffeine",
    "salicylates",
    "oralAllergy",
    "pescatarian",
    "paleo",
    "whole30",
    "aip",
    "jain",
    "keto",
    "custom",
]
"""The Dart ``RestrictionId`` names; a test pins them to the taxonomy in
``allergens.json`` (this module may not import ``app.keto.allergens``, which
imports it)."""

ConcernSource = Literal[
    "name", "description", "option", "hidden", "model", "kitchen", "matrix"
]
"""The Dart ``ConcernSource`` names. ``kitchen`` (ALG-07) and ``matrix``
(ALG-16) are made on the device only; the server never emits them, and reads
them like any other name."""

Certainty = Literal["stated", "likely", "suspected"]
"""The Dart ``Certainty`` names, the vocabulary's ``TriggerCertainty``
names too."""

EvidenceTier = Literal[
    "declared", "stated", "inferred", "suspected", "confirmed", "denied"
]
"""The Dart ``EvidenceTier`` names."""

ComponentRole = Literal[
    "base", "protein", "side", "sauce", "garnish", "option", "unknown"
]
"""The Dart ``ComponentRole`` names."""

_COMPONENT_ROLES: Final = frozenset(get_args(ComponentRole))

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
    """Dart ``Dish``: ``{id, name, description, price, options, imageUrl, page,
    declaredTags?}``.

    ``description`` is ``""`` (never null) when absent or null. ``image_url``
    and ``page`` are read tolerantly, as Dart does: anything but a non-empty
    string, or an int of at least 1, reads as null. Both are always written,
    null included. ``declared_tags`` (Banto, ALG-09) is the platform's own
    dietary labels, kept raw: absent or not a list reads as empty, an entry
    that is not a non-blank string (Dart ``trim``) is dropped, and the key is
    written only when non-empty, so a dish with none is the bytes it was.
    """

    id: NonEmptyStr
    name: NonEmptyStr
    description: str = ""
    price: Annotated[float, Field(ge=0)]
    options: list[DishOption]
    image_url: str | None = None
    page: Annotated[int, Field(ge=1)] | None = None
    declared_tags: list[str] = Field(default_factory=list)

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

    @field_validator("declared_tags", mode="before")
    @classmethod
    def _tolerant_declared_tags(cls, value: object) -> list[str]:
        if not isinstance(value, list):
            return []
        return [tag for tag in value if isinstance(tag, str) and dart_trim(tag)]

    @model_serializer(mode="wrap")
    def _omit_empty_declared_tags(
        self, handler: SerializerFunctionWrapHandler
    ) -> dict[str, Any]:
        data: dict[str, Any] = handler(self)
        if not self.declared_tags:
            data.pop("declaredTags", None)
        return data


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
    certainty: HiddenCarbCertainty
    waiter_question: str

    @field_validator("source", "waiter_question")
    @classmethod
    def _not_blank(cls, value: str) -> str:
        # Dart's trim, not Python's strip: U+001C-U+001F are not blank in
        # Dart, so a flag Dart wrote must read back here.
        if not dart_trim(value):
            raise ValueError("must not be blank")
        return value


def _optional_text(value: object) -> object:
    """``value`` when it is a non-empty string, else None: Dart's
    ``_optionalText``."""
    return value if isinstance(value, str) and value else None


class Concern(WireModel):
    """Dart ``Concern``: ``{restrictionId, source, certainty, tier,
    matchedText, waiterQuestion}`` (Banto; D26 W2-0).

    The four enum names are required and must be known (an unknown one fails
    the entry, which the list holding it drops). ``matched_text`` and
    ``waiter_question`` read anything but a non-empty string as null and are
    always written, null included.
    """

    restriction_id: RestrictionIdName
    source: ConcernSource
    certainty: Certainty
    tier: EvidenceTier
    matched_text: str | None = None
    waiter_question: str | None = None

    @field_validator("matched_text", "waiter_question", mode="before")
    @classmethod
    def _tolerant_text(cls, value: object) -> object:
        return _optional_text(value)


class ExtractedIngredient(WireModel):
    """Dart ``ExtractedIngredient``: ``{name, certainty, role}`` (Banto; D26
    W2-0).

    ``name`` must be non-blank by Dart's ``trim`` and ``certainty`` known; an
    absent or unknown ``role`` reads as ``unknown``, so an ingredient is never
    dropped over its role.
    """

    name: str
    certainty: Certainty
    role: ComponentRole = "unknown"

    @field_validator("name")
    @classmethod
    def _not_blank(cls, value: str) -> str:
        if not dart_trim(value):
            raise ValueError("must not be blank")
        return value

    @field_validator("role", mode="before")
    @classmethod
    def _tolerant_role(cls, value: object) -> object:
        return (
            value
            if isinstance(value, str) and value in _COMPONENT_ROLES
            else ("unknown")
        )


def _tolerant_entries[T: BaseModel](model: type[T], value: object) -> list[T]:
    """Each entry of ``value`` that ``model`` accepts, in order; empty when
    ``value`` is not a list. Dart's ``tryFrom`` list reading (§9.4)."""
    if not isinstance(value, list):
        return []
    kept: list[T] = []
    for entry in value:
        if isinstance(entry, model):
            kept.append(entry)
            continue
        if not isinstance(entry, dict):
            continue
        try:
            kept.append(model.model_validate(entry))
        except ValidationError:
            continue
    return kept


class AnalysedDish(WireModel):
    """Dart ``AnalysedDish``: ``{dishId, name, verdict, why, modification,
    netCarbsEstimate, hiddenCarbs, ingredients, concerns}``.

    ``modification`` is a non-empty string exactly when ``verdict`` is
    ``modifiable`` and null otherwise, the invariant Dart's ``tryFrom``
    enforces. ``hidden_carbs``, ``ingredients`` and ``concerns`` read absent,
    null or non-list as empty and drop each malformed entry silently, as Dart
    does (§9.4). ``ingredients`` and ``concerns`` are written only when
    non-empty (D26 C3).
    """

    dish_id: NonEmptyStr
    name: NonEmptyStr
    verdict: Verdict
    why: NonEmptyStr
    modification: str | None = None
    net_carbs_estimate: float | None = None
    hidden_carbs: list[HiddenCarb] = Field(default_factory=list)
    ingredients: list[ExtractedIngredient] = Field(default_factory=list)
    concerns: list[Concern] = Field(default_factory=list)

    @field_validator("hidden_carbs", mode="before")
    @classmethod
    def _tolerant_hidden_carbs(cls, value: object) -> list[HiddenCarb]:
        return _tolerant_entries(HiddenCarb, value)

    @field_validator("ingredients", mode="before")
    @classmethod
    def _tolerant_ingredients(cls, value: object) -> list[ExtractedIngredient]:
        return _tolerant_entries(ExtractedIngredient, value)

    @field_validator("concerns", mode="before")
    @classmethod
    def _tolerant_concerns(cls, value: object) -> list[Concern]:
        return _tolerant_entries(Concern, value)

    @model_serializer(mode="wrap")
    def _omit_empty_banto_lists(
        self, handler: SerializerFunctionWrapHandler
    ) -> dict[str, Any]:
        data: dict[str, Any] = handler(self)
        if not self.ingredients:
            data.pop("ingredients", None)
        if not self.concerns:
            data.pop("concerns", None)
        return data

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
    dietaryConstraints, restrictionsRequested}``. An absent or null
    ``dietaryConstraints`` reads as empty. ``restrictionsRequested`` (Banto;
    D26 C2) reads anything but ``true`` as false and is written only when
    true."""

    net_carb_limit_grams: StrictInt
    dietary_constraints: list[str] = Field(default_factory=list)
    restrictions_requested: bool = False

    @field_validator("dietary_constraints", mode="before")
    @classmethod
    def _null_constraints_are_none(cls, value: object) -> object:
        return [] if value is None else value

    @field_validator("restrictions_requested", mode="before")
    @classmethod
    def _only_true_is_true(cls, value: object) -> object:
        return value is True

    @model_serializer(mode="wrap")
    def _omit_false_restrictions(
        self, handler: SerializerFunctionWrapHandler
    ) -> dict[str, Any]:
        data: dict[str, Any] = handler(self)
        if not self.restrictions_requested:
            data.pop("restrictionsRequested", None)
            data.pop("restrictions_requested", None)
        return data


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
