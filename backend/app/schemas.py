"""Pydantic request and response schemas."""

import base64
import binascii
from datetime import datetime
from typing import Annotated, Any, Final, Literal, get_args

from pydantic import (
    BaseModel,
    Field,
    PrivateAttr,
    StrictInt,
    StringConstraints,
    field_validator,
    model_validator,
)

from app.keto.models import (
    AnalysisOptionsSnapshot,
    Menu,
    MenuAnalysed,
    Venue,
    WireModel,
)
from app.keto.vocabulary import vocabulary
from app.services.wolt import WoltLang


class HealthResponse(BaseModel):
    """Response body for ``GET /v1/health``."""

    status: str
    version: str
    llm_configured: bool


class ErrorResponse(BaseModel):
    """Body of every error the backend itself originates."""

    reason: str
    status_code: int


ImageMimeType = Literal["image/jpeg", "image/png", "image/webp", "application/pdf"]


def _strict_base64(value: str) -> str:
    """``value`` unchanged when it is strict, padded standard base64.

    Shared by ``ImagePart`` and ``ScanPage``. The message is fixed: the
    default one would not quote the value, but nothing about a page's bytes
    belongs in an error either.
    """
    try:
        base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError):
        raise ValueError("data must be standard base64") from None
    return value


def _base64_decoded_size(data: str) -> int:
    """The decoded length of base64 ``_strict_base64`` accepted.

    Exact for such input: every 4 characters are 3 bytes, less one per
    ``=`` of padding.
    """
    padding = len(data) - len(data.rstrip("="))
    return len(data) * 3 // 4 - padding


class ImagePart(BaseModel):
    """One menu page on ``POST /v1/chat`` (D15, #170), base64 in ``data``.

    ``mime_type`` is one of the four types Gemini reads natively; anything
    else (``image/gif``, ``image/heic``) is a 422 before any upstream call.
    ``data`` must be strict, padded standard base64: it is decoded here once,
    so a malformed part is a 422 too, and the decoded length is kept for the
    route's ``VISION_MAX_IMAGE_BYTES`` check. The bytes themselves are not
    kept; ``data`` is forwarded to Gemini as-is.

    The size and count bounds are configuration (``app.config``), which a
    Pydantic validator cannot reach, so ``ChatRequest.image_bound_violation``
    applies them from the route instead.
    """

    mime_type: ImageMimeType
    data: str = Field(..., min_length=1)
    _decoded_size: int = PrivateAttr(default=0)

    @field_validator("data")
    @classmethod
    def _data_is_base64(cls, value: str) -> str:
        return _strict_base64(value)

    @model_validator(mode="after")
    def _record_decoded_size(self) -> "ImagePart":
        self._decoded_size = _base64_decoded_size(self.data)
        return self

    @property
    def decoded_size(self) -> int:
        """The part's size in bytes once decoded."""
        return self._decoded_size


class ChatRequest(BaseModel):
    """Request body for ``POST /v1/chat``.

    Mirrors the Dart ``LlmChatClient.complete`` parameters one to one. The
    ``max_length`` bounds turn an oversized prompt into a 422 before any
    upstream call. ``schema_name`` is accepted for parity with the Dart
    contract (and as part of the #103 cache key); Gemini's
    ``responseSchema`` has no name, so it is not forwarded.

    ``user_prompt``'s bound is an abuse guard, not a model limit: the Dart
    prompt runs about 430 characters per dish on a real Wolt menu, so the
    old 60,000 rejected every venue over ~139 dishes with a 422 the app could
    only render as "AI error" (#188). Gemini's input window is over a
    million tokens; 400,000 characters is roughly 900 dishes, past any
    restaurant and most supermarkets, while still refusing a runaway body.

    ``images`` (D15, #170) are menu pages forwarded to Gemini as
    ``inline_data`` parts after the user prompt. Empty by default, so a
    text-only body is exactly what it was before images existed. They never
    enter the #103 cache key, and a request carrying any skips the cache.
    """

    system_prompt: str = Field(..., min_length=1, max_length=20000)
    user_prompt: str = Field(..., min_length=1, max_length=400000)
    response_schema: dict[str, object] | None = None
    schema_name: str | None = Field(default=None, max_length=64)
    images: list[ImagePart] = Field(default_factory=list)

    def image_bound_violation(self, max_images: int, max_bytes: int) -> str | None:
        """Why ``images`` breaks the configured bounds, or None when it does not.

        More than ``max_images`` parts, or any part over ``max_bytes`` once
        decoded. The message names the bound, never a part's content.
        """
        if len(self.images) > max_images:
            return f"at most {max_images} images per request"
        for index, image in enumerate(self.images):
            if image.decoded_size > max_bytes:
                return f"image {index} is over {max_bytes} bytes once decoded"
        return None


class WebsiteFetchRequest(BaseModel):
    """Request body for ``POST /v1/website/fetch`` (D19, #181).

    The URL travels in the body, not the query string, so the per-request
    log line (which records the route path) never carries it.
    """

    url: str = Field(..., min_length=1, max_length=2048)


class WebsiteFetchResponse(BaseModel):
    """A successful ``POST /v1/website/fetch``: one HTML page or PDF.

    ``body`` is the decoded page text for ``html`` and standard base64 for
    ``pdf``. ``final_url`` is the URL after redirects, so the app resolves
    the page's relative links against the right base.
    """

    kind: Literal["html", "pdf"]
    content_type: str
    body: str
    final_url: str


class ChatResponse(BaseModel):
    """Response body for a successful ``POST /v1/chat``."""

    content: str
    model: str


class DiscoverySearchRequest(BaseModel):
    """Request body for ``POST /v1/proxy/wolt/pages/search`` (#123).

    ``q`` is trimmed and bounded before it ever reaches Wolt. ``lat``/``lon``
    share the ``GET /v1/proxy/wolt/pages/restaurants`` route's range and are
    optional together: the app searches by name without a position when
    location was denied (#37), and Wolt ranks by proximity only when both
    are given, so one without the other is rejected rather than half-sent.
    There is no ``target`` field: the route itself fixes it to ``"venues"``,
    so a client cannot ask this backend to proxy a dish search instead.
    """

    q: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)
    ]
    lat: float | None = Field(default=None, ge=-90, le=90)
    lon: float | None = Field(default=None, ge=-180, le=180)
    lang: WoltLang = "en"

    @model_validator(mode="after")
    def _position_is_all_or_nothing(self) -> "DiscoverySearchRequest":
        if (self.lat is None) != (self.lon is None):
            raise ValueError("lat and lon must be given together or not at all")
        return self


MenuStoreSource = Literal["wolt", "tenbis", "tabit", "ontopo", "scan", "website"]
"""Where a stored menu came from: the Dart ``MenuSource`` names (#310)."""

MENU_STORE_SOURCES: Final[frozenset[str]] = frozenset(get_args(MenuStoreSource))

MENU_STORE_MAX_PLATFORM_ID: Final = 512

PlatformId = Annotated[
    str,
    StringConstraints(
        strip_whitespace=True, min_length=1, max_length=MENU_STORE_MAX_PLATFORM_ID
    ),
]


class MenuUploadRequest(BaseModel):
    """Request body for ``POST /v1/menus`` (#310): one menu a user opened.

    ``(source, platform_id)`` names the venue's menu on its platform (a Wolt
    slug, a 10bis restaurant id, a scan's or website's own key) and is the
    stored row's whole identity. Nothing in the body names the sender, and
    the install id the route requires never reaches the store.

    ``menu`` is the client's normalised menu, stored as-is; its dishes are
    counted from ``categories[*].dishes``. ``analysis`` is optional, and a
    top-level numeric ``score`` in it is the only value the backend reads
    out of it. A null ``venue_name``, ``city`` or ``analysis`` never erases
    what an earlier upload stored.
    """

    source: MenuStoreSource
    platform_id: PlatformId
    venue_name: str | None = Field(default=None, max_length=200)
    city: str | None = Field(default=None, max_length=200)
    menu: dict[str, Any]
    analysis: dict[str, Any] | None = None


class MenuStoredResponse(BaseModel):
    """A successful ``POST /v1/menus``: 201 when the row is new, else 200."""

    created: bool
    submission_count: int


class StoredMenuResponse(BaseModel):
    """Response body for ``GET /v1/menus/{source}/{platform_id}`` (#310).

    Timestamps are UTC (stored naive, the ``MenuCache`` convention).
    """

    source: MenuStoreSource
    platform_id: str
    venue_name: str | None
    city: str | None
    menu: dict[str, Any]
    analysis: dict[str, Any] | None
    dish_count: int
    score: float | None
    first_seen_at: datetime
    last_seen_at: datetime
    submission_count: int


# --- D25: complete results (#321) ---------------------------------------------
#
# Every model below is camelCase on the wire (``WireModel``), unlike the
# snake_case bodies above: they carry the Dart ``Menu``/``MenuAnalysed``/
# ``Venue`` JSON (``app.keto.models``) and are read by the same Dart
# ``tryFrom`` code, so one casing runs through each body. Routes are added by
# #333 (classify, venue-menus, text-menu), #334 (scan, website-menu) and
# #335 (venues); ``backend_plan.md`` §3.3 is the route contract.

MAX_DIETARY_CONSTRAINTS: Final = 3
"""As many constraints as the app has "Your keto rules" toggles (#56)."""

MAX_DIETARY_CONSTRAINT_CHARS: Final = 1000

MAX_SCAN_PAGES: Final = 6
"""The schema's hard bound; ``VISION_MAX_IMAGES`` may only lower it."""

MAX_TEXT_MENU_CHARS: Final = 100_000

DietaryConstraint = Annotated[
    str, Field(min_length=1, max_length=MAX_DIETARY_CONSTRAINT_CHARS)
]


def known_dietary_constraints() -> frozenset[str]:
    """The three Dart prompt fragments a ``dietaryConstraints`` item may be
    (``seedOilFreePromptFragment``, ``dairyFreePromptFragment``,
    ``carnivoreOnlyPromptFragment``), verbatim from the shared vocabulary."""
    prompt = vocabulary().prompt
    return frozenset(
        {
            prompt.seed_oil_free_prompt_fragment,
            prompt.dairy_free_prompt_fragment,
            prompt.carnivore_only_prompt_fragment,
        }
    )


class ClassificationOptionsBody(WireModel):
    """The options one analysis is made under: ``{netCarbLimitGrams,
    dietaryConstraints}``, the Dart ``AnalysisOptionsSnapshot`` with bounds.

    ``dietaryConstraints`` holds the prompt fragments themselves, exactly as
    the Dart ``ClassificationOptions.dietaryConstraints`` holds them
    (``seedOilFreePromptFragment`` and its two siblings), so the server can
    echo them back as the result's ``options`` snapshot byte for byte and the
    client's ``_reusableAnalysis`` accepts it. **Any item that is not one of
    those known fragments is refused** (422, by ``_known_fragments_only``),
    as is one given twice: free text here would reach the system prompt
    under the server's own key.
    """

    net_carb_limit_grams: Annotated[StrictInt, Field(ge=1, le=50)]
    dietary_constraints: list[DietaryConstraint] = Field(
        default_factory=list, max_length=MAX_DIETARY_CONSTRAINTS
    )

    @field_validator("dietary_constraints")
    @classmethod
    def _known_fragments_only(cls, value: list[str]) -> list[str]:
        # The message names the rule, never the value: free text sent here
        # is exactly what must not travel any further, a log line included.
        known = known_dietary_constraints()
        if any(item not in known for item in value):
            raise ValueError("each dietary constraint must be a known fragment")
        if len(set(value)) != len(value):
            raise ValueError("a dietary constraint may be given only once")
        return value

    def snapshot(self) -> AnalysisOptionsSnapshot:
        """These options as the snapshot a returned analysis records."""
        return AnalysisOptionsSnapshot(
            net_carb_limit_grams=self.net_carb_limit_grams,
            dietary_constraints=list(self.dietary_constraints),
        )


class VenueMenuResponse(WireModel):
    """``GET /v1/venue-menus/{source}/{platform_id}``: one platform menu.

    ``analysis`` is null when the request did not ask for one
    (``classify=false``) or the menu has no dish to classify.
    ``fromCache`` says whether the menu came from the server's platform
    cache rather than a fresh upstream fetch, and ``fetchedAt`` (ISO-8601,
    as Dart writes it) is when that upstream fetch happened: the same
    instant as ``menu.fetchedAt``.
    """

    menu: Menu
    analysis: MenuAnalysed | None
    from_cache: bool
    fetched_at: str

    @field_validator("fetched_at")
    @classmethod
    def _fetched_at_is_iso(cls, value: str) -> str:
        datetime.fromisoformat(value)
        return value


class ClassifyRequest(WireModel):
    """``POST /v1/classify``: a menu the client already holds, to analyse."""

    menu: Menu
    options: ClassificationOptionsBody


class ClassifyResponse(WireModel):
    """A successful ``POST /v1/classify``."""

    analysis: MenuAnalysed


class ScanPage(WireModel):
    """One page on ``POST /v1/scan``: ``{mimeType, data}``.

    Validated exactly like ``ImagePart`` on ``/v1/chat``: one of the four
    types Gemini reads natively, and strict, padded standard base64.
    """

    mime_type: ImageMimeType
    data: str = Field(..., min_length=1)
    _decoded_size: int = PrivateAttr(default=0)

    @field_validator("data")
    @classmethod
    def _data_is_base64(cls, value: str) -> str:
        return _strict_base64(value)

    @model_validator(mode="after")
    def _record_decoded_size(self) -> "ScanPage":
        self._decoded_size = _base64_decoded_size(self.data)
        return self

    @property
    def decoded_size(self) -> int:
        """The page's size in bytes once decoded."""
        return self._decoded_size


class ScanRequest(WireModel):
    """``POST /v1/scan``: one to ``MAX_SCAN_PAGES`` photographed or PDF
    pages of one menu, read and classified in one Gemini request (D15)."""

    pages: list[ScanPage] = Field(..., min_length=1, max_length=MAX_SCAN_PAGES)
    options: ClassificationOptionsBody

    def page_bound_violation(self, max_pages: int, max_bytes: int) -> str | None:
        """Why ``pages`` breaks the configured bounds, or None when it does not.

        ``ChatRequest.image_bound_violation``'s rule: more than ``max_pages``
        pages, or any page over ``max_bytes`` once decoded.
        """
        if len(self.pages) > max_pages:
            return f"at most {max_pages} pages per request"
        for index, page in enumerate(self.pages):
            if page.decoded_size > max_bytes:
                return f"page {index} is over {max_bytes} bytes once decoded"
        return None


class ScannedMenuResponse(WireModel):
    """A successful ``POST /v1/scan`` or ``POST /v1/text-menu``: the menu
    read from the user's pages or text (``venueRef.source`` is ``scan``) and
    its analysis, which is never null on these routes."""

    menu: Menu
    analysis: MenuAnalysed


class TextMenuRequest(WireModel):
    """``POST /v1/text-menu``: a menu pasted as text (D18)."""

    text: str = Field(..., min_length=1, max_length=MAX_TEXT_MENU_CHARS)
    options: ClassificationOptionsBody


class WebsiteMenuRequest(WireModel):
    """``POST /v1/website-menu``: a restaurant's own site (D19).

    The URL is in the body, as on ``/v1/website/fetch``, so the request log
    (which records the path) never carries it.
    """

    url: str = Field(..., min_length=1, max_length=2048)
    options: ClassificationOptionsBody


class WebsiteMenuResponse(WireModel):
    """A successful ``POST /v1/website-menu``. ``analysis`` is null only when
    the menu found has no dish to classify."""

    menu: Menu
    analysis: MenuAnalysed | None


class VenueSearchRequest(WireModel):
    """``POST /v1/venues/search``: venues by name, ``{query, lang, lat?,
    lon?}``.

    ``DiscoverySearchRequest``'s rules: ``query`` trimmed before its bounds
    apply, and ``lat``/``lon`` given together or not at all.
    """

    query: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)
    ]
    lang: WoltLang = "en"
    lat: float | None = Field(default=None, ge=-90, le=90)
    lon: float | None = Field(default=None, ge=-180, le=180)

    @model_validator(mode="after")
    def _position_is_all_or_nothing(self) -> "VenueSearchRequest":
        if (self.lat is None) != (self.lon is None):
            raise ValueError("lat and lon must be given together or not at all")
        return self


class VenuesResponse(WireModel):
    """A successful ``GET /v1/venues/nearby`` or ``POST /v1/venues/search``:
    the venues in Wolt's order (the client sorts nearest-first)."""

    venues: list[Venue]
