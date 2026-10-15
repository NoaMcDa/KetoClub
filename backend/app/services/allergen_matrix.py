"""Restaurant allergen matrices: format, storage and the current one (ALG-16).

A matrix is what a restaurant says about its dishes' allergens, one table per
venue and date (issue #358, ``allergen app documentation/10_epic_allergens.md``
§ALG-16): rows are dishes by printed name, columns are the EU 14 allergens by
taxonomy id (``ALLERGEN_COLUMNS``; sesame is one of the 14), and each cell is
``contains``, ``may_contain``, ``free`` or blank. The format is documented in
``backend/README.md``.

This module holds the three pure-ish parts the maintainer CLI
(``tools/allergen_matrix.py``) and ``GET /v1/venue-menus`` share:

* **Parsing**: ``parse_document`` reads the JSON intake document,
  ``parse_csv`` a CSV table plus the metadata the CLI takes as flags. Both
  answer a validated ``MatrixDocument`` or raise ``MatrixFormatError`` with a
  message that names the row or field, never a partial matrix.
* **Storage**: ``save``, ``remove`` and ``entries`` over the
  ``allergen_matrices`` table, keyed by venue like ``stored_menus`` (D24) plus
  the matrix's first valid day. There is no write route and no account
  system: the CLI is the only writer.
* **The current matrix**: ``current`` answers the wire form
  (``AllergenMatrixWire``) of the matrix that holds on a given day, or None.

Matching a row to a dish happens on the device only
(``lib/utils/allergens/allergen_matrix.dart``), beside the evaluator that
uses it: the server stores and returns the restaurant's words as written.
The one normalisation done here is ``app.keto.normaliser.normalise`` (the
port the normaliser golden pins), used to refuse two rows whose names the
device would read as one dish.

No function here takes, stores or logs an install id (D12, D24).
"""

import csv
import io
import json
import re
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Annotated, Any, Final, Literal, get_args

from pydantic import Field, StringConstraints, ValidationError, field_validator
from sqlalchemy import Engine, select
from sqlalchemy.orm import Session

from app.db import get_session
from app.keto.dart_text import dart_trim
from app.keto.models import WireModel
from app.keto.normaliser import normalise
from app.models import AllergenMatrix
from app.services.platform_menu import RESTAURANT_ID_PATTERN, SLUG_PATTERN

AllergenColumn = Literal[
    "gluten",
    "crustaceans",
    "eggs",
    "fish",
    "peanuts",
    "soy",
    "milk",
    "treeNuts",
    "celery",
    "mustard",
    "sesame",
    "sulphites",
    "lupin",
    "molluscs",
]
"""The EU 14 allergens (Regulation 1169/2011 Annex II), by taxonomy id.

"Cereals containing gluten" is ``gluten`` (the celiac entry), never
``wheat``: a gluten-free dish may still hold wheat starch, as ALG-09's
gluten-free rule reads it. Sesame is one of the 14."""

ALLERGEN_COLUMNS: Final[tuple[str, ...]] = get_args(AllergenColumn)
"""``AllergenColumn``'s ids in the order a CSV template lists them."""

CellValue = Literal["contains", "may_contain", "free"]
"""A cell's value; a blank cell is left out of the row."""

MatrixSource = Literal["restaurant", "printed", "website"]
"""Where the restaurant's own information was read: sent by the restaurant,
printed or posted at the venue, or published on its website. Every value is
the restaurant's own word, which is what the app's notice says."""

VenueSource = Literal["wolt", "tenbis"]
"""The platforms whose menus ``GET /v1/venue-menus`` serves."""

MAX_ROWS: Final = 500
"""The most dishes one matrix may list."""

MAX_ALIASES: Final = 5
"""The most other printed names one row may carry."""

MAX_NAME_LENGTH: Final = 200
"""The longest dish name or alias, in characters."""

_PLATFORM_ID_PATTERNS: Final[dict[str, str]] = {
    "wolt": SLUG_PATTERN,
    "tenbis": RESTAURANT_ID_PATTERN,
}

_CSV_VALUES: Final[dict[str, CellValue]] = {
    "contains": "contains",
    "may_contain": "may_contain",
    "may contain": "may_contain",
    "free": "free",
}

DishName = Annotated[str, StringConstraints(min_length=1, max_length=MAX_NAME_LENGTH)]


class MatrixFormatError(ValueError):
    """A matrix the format refuses; the message says where and why."""


class MatrixRowWire(WireModel):
    """One dish of a matrix: ``{name, aliases, allergens}``.

    ``aliases`` are the dish's other printed names (its English name on a
    Hebrew menu, say), matched exactly like ``name``. ``allergens`` maps an
    EU 14 id to its cell; a blank cell is absent.
    """

    name: DishName
    aliases: Annotated[list[DishName], Field(max_length=MAX_ALIASES)] = []
    allergens: dict[AllergenColumn, CellValue]

    @field_validator("name")
    @classmethod
    def _name_is_not_blank(cls, value: str) -> str:
        if not dart_trim(value):
            raise ValueError("name is blank")
        return value


class AllergenMatrixWire(WireModel):
    """``allergenMatrix`` on ``GET /v1/venue-menus``: the current matrix.

    ``validFrom`` and ``validUntil`` are ISO dates (``YYYY-MM-DD``),
    ``validUntil`` null for "until replaced". The person who entered it is
    not sent: it is the maintainer's audit trail, not the restaurant's word.
    """

    source: MatrixSource
    valid_from: str
    valid_until: str | None
    rows: list[MatrixRowWire]


@dataclass(frozen=True)
class MatrixDocument:
    """A validated intake: the venue, the metadata and the rows."""

    venue_source: VenueSource
    platform_id: str
    source: MatrixSource
    entered_by: str
    valid_from: date
    valid_until: date | None
    rows: tuple[MatrixRowWire, ...]

    def wire(self) -> AllergenMatrixWire:
        """The form ``GET /v1/venue-menus`` answers."""
        return AllergenMatrixWire(
            source=self.source,
            valid_from=self.valid_from.isoformat(),
            valid_until=None
            if self.valid_until is None
            else self.valid_until.isoformat(),
            rows=list(self.rows),
        )


def _date(value: object, field: str) -> date:
    if not isinstance(value, str):
        raise MatrixFormatError(f"{field} must be a date written YYYY-MM-DD")
    try:
        parsed = date.fromisoformat(value)
    except ValueError:
        raise MatrixFormatError(f"{field} must be a date written YYYY-MM-DD") from None
    if parsed.isoformat() != value:
        raise MatrixFormatError(f"{field} must be a date written YYYY-MM-DD")
    return parsed


def _choice[T: str](value: object, field: str, allowed: Sequence[T]) -> T:
    for choice in allowed:
        if value == choice:
            return choice
    raise MatrixFormatError(f"{field} must be one of {', '.join(allowed)}")


def _row(raw: object, number: int) -> MatrixRowWire:
    """Row ``number`` (1-based) as a ``MatrixRowWire``; blank cells dropped."""
    if not isinstance(raw, Mapping):
        raise MatrixFormatError(f"row {number}: not an object")
    allergens = raw.get("allergens", {})
    if not isinstance(allergens, Mapping):
        raise MatrixFormatError(f"row {number}: allergens must be an object")
    cells: dict[str, object] = {}
    for column, cell in allergens.items():
        if column not in ALLERGEN_COLUMNS:
            raise MatrixFormatError(
                f"row {number}: {column!r} is not one of the EU 14 allergen ids"
            )
        if cell is None or cell == "":
            continue
        cells[column] = cell
    try:
        return MatrixRowWire.model_validate({**raw, "allergens": cells})
    except ValidationError as error:
        first = error.errors(include_url=False)[0]
        where = ".".join(str(part) for part in first.get("loc", ()))
        raise MatrixFormatError(
            f"row {number}: {where or 'row'}: {first.get('msg', 'invalid')}"
        ) from None


def _validated(
    *,
    venue_source: object,
    platform_id: object,
    source: object,
    entered_by: object,
    valid_from: object,
    valid_until: object,
    rows: Sequence[MatrixRowWire],
) -> MatrixDocument:
    venue = _choice(venue_source, "venue source", get_args(VenueSource))
    if not isinstance(platform_id, str) or not _matches(
        _PLATFORM_ID_PATTERNS[venue], platform_id
    ):
        raise MatrixFormatError(f"platformId is not a {venue} venue id")
    origin = _choice(source, "source", get_args(MatrixSource))
    if not isinstance(entered_by, str) or not dart_trim(entered_by):
        raise MatrixFormatError("enteredBy must name who entered the matrix")
    if len(entered_by) > MAX_NAME_LENGTH:
        raise MatrixFormatError(f"enteredBy is over {MAX_NAME_LENGTH} characters")
    start = _date(valid_from, "validFrom")
    end = None if valid_until is None else _date(valid_until, "validUntil")
    if end is not None and end < start:
        raise MatrixFormatError("validUntil is before validFrom")
    if not rows:
        raise MatrixFormatError("the matrix has no rows")
    if len(rows) > MAX_ROWS:
        raise MatrixFormatError(f"the matrix has more than {MAX_ROWS} rows")
    seen: dict[str, int] = {}
    for number, row in enumerate(rows, start=1):
        for name in (row.name, *row.aliases):
            key = normalise(name)
            if not key:
                raise MatrixFormatError(
                    f"row {number}: {name!r} has no letter or digit to match"
                )
            if key in seen and seen[key] != number:
                raise MatrixFormatError(
                    f"row {number}: {name!r} names the same dish as row {seen[key]}"
                )
            seen[key] = number
    return MatrixDocument(
        venue_source=venue,
        platform_id=platform_id,
        source=origin,
        entered_by=dart_trim(entered_by),
        valid_from=start,
        valid_until=end,
        rows=tuple(rows),
    )


def _matches(pattern: str, value: str) -> bool:
    return re.fullmatch(pattern, value) is not None


def parse_document(raw: object) -> MatrixDocument:
    """The JSON intake document ``raw`` (already decoded), validated.

    Shape: ``{venue: {source, platformId}, source, enteredBy, validFrom,
    validUntil?, rows: [{name, aliases?, allergens: {id: value}}]}``. A
    blank cell may be written ``""``, ``null`` or left out. Raises
    ``MatrixFormatError`` naming the first problem.
    """
    if not isinstance(raw, Mapping):
        raise MatrixFormatError("the document is not a JSON object")
    known = {"venue", "source", "enteredBy", "validFrom", "validUntil", "rows"}
    unknown = sorted(str(key) for key in raw if key not in known)
    if unknown:
        raise MatrixFormatError(f"unknown field {unknown[0]!r}")
    venue = raw.get("venue")
    if not isinstance(venue, Mapping):
        raise MatrixFormatError("venue must be {source, platformId}")
    rows = raw.get("rows")
    if not isinstance(rows, list):
        raise MatrixFormatError("rows must be a list")
    return _validated(
        venue_source=venue.get("source"),
        platform_id=venue.get("platformId"),
        source=raw.get("source"),
        entered_by=raw.get("enteredBy"),
        valid_from=raw.get("validFrom"),
        valid_until=raw.get("validUntil"),
        rows=[_row(row, number) for number, row in enumerate(rows, start=1)],
    )


def parse_csv(
    text: str,
    *,
    venue_source: str,
    platform_id: str,
    source: str,
    entered_by: str,
    valid_from: str,
    valid_until: str | None,
) -> MatrixDocument:
    """A CSV table ``text`` plus its metadata, validated.

    The header names ``name``, optionally ``aliases`` (several separated by
    ``|``) and any of the EU 14 ids (``ALLERGEN_COLUMNS``) in any order. A
    cell is ``contains``, ``may_contain`` (or ``may contain``), ``free`` or
    empty, in any case. A leading byte-order mark is ignored. Raises
    ``MatrixFormatError`` naming the line of the first problem.
    """
    reader = csv.reader(io.StringIO(text.removeprefix("﻿")))
    try:
        header = [dart_trim(cell) for cell in next(reader)]
    except StopIteration:
        raise MatrixFormatError("the CSV is empty") from None
    if "name" not in header:
        raise MatrixFormatError("the CSV header has no name column")
    for column in header:
        if column not in ("name", "aliases") and column not in ALLERGEN_COLUMNS:
            raise MatrixFormatError(
                f"header: {column!r} is not name, aliases or an EU 14 allergen id"
            )
    if len(set(header)) != len(header):
        raise MatrixFormatError("header: a column is named twice")
    rows: list[MatrixRowWire] = []
    for line, cells in enumerate(reader, start=2):
        if not any(dart_trim(cell) for cell in cells):
            continue
        if len(cells) > len(header):
            raise MatrixFormatError(f"line {line}: more cells than the header")
        record = dict(zip(header, cells, strict=False))
        allergens: dict[str, str] = {}
        for column in ALLERGEN_COLUMNS:
            cell = dart_trim(record.get(column, "")).lower()
            if not cell:
                continue
            value = _CSV_VALUES.get(cell)
            if value is None:
                raise MatrixFormatError(
                    f"line {line}: {column} is {cell!r}, not contains, "
                    "may_contain, free or empty"
                )
            allergens[column] = value
        aliases = [
            dart_trim(alias)
            for alias in record.get("aliases", "").split("|")
            if dart_trim(alias)
        ]
        row: dict[str, Any] = {
            "name": dart_trim(record.get("name", "")),
            "aliases": aliases,
            "allergens": allergens,
        }
        try:
            rows.append(_row(row, len(rows) + 1))
        except MatrixFormatError as error:
            raise MatrixFormatError(f"line {line}: {error}") from None
    return _validated(
        venue_source=venue_source,
        platform_id=platform_id,
        source=source,
        entered_by=entered_by,
        valid_from=valid_from,
        valid_until=valid_until,
        rows=rows,
    )


def csv_template() -> str:
    """An empty CSV with the full header, for a maintainer to fill in."""
    return ",".join(("name", "aliases", *ALLERGEN_COLUMNS)) + "\n"


def _run_in_session[T](engine: Engine, fn: Callable[[Session], T]) -> T:
    """Run ``fn`` over one session obtained from ``get_session``.

    Duplicated from ``app.services.menu_store`` rather than shared, for the
    reason given in ``app.services.chat_cache``: the services stay
    independent of one another.
    """
    generator = get_session(engine)
    session = next(generator)
    try:
        result = fn(session)
    except Exception:
        generator.close()
        raise
    try:
        next(generator)
    except StopIteration:
        pass
    return result


def _rows_json(rows: Sequence[MatrixRowWire]) -> str:
    return json.dumps(
        [row.model_dump(by_alias=True, mode="json") for row in rows],
        ensure_ascii=False,
        separators=(",", ":"),
    )


def save(engine: Engine, document: MatrixDocument, *, now: datetime) -> bool:
    """Store ``document``; True when new, False when it replaced the matrix
    the venue already had for the same ``validFrom``."""
    stamp = now.astimezone(UTC).replace(tzinfo=None) if now.tzinfo else now

    def _write(session: Session) -> bool:
        key = (document.venue_source, document.platform_id, document.valid_from)
        row = session.get(AllergenMatrix, key)
        created = row is None
        if row is None:
            row = AllergenMatrix(
                source=document.venue_source,
                platform_id=document.platform_id,
                valid_from=document.valid_from,
            )
            session.add(row)
        row.valid_until = document.valid_until
        row.matrix_source = document.source
        row.entered_by = document.entered_by
        row.rows_json = _rows_json(document.rows)
        row.entered_at = stamp
        session.flush()
        return created

    return _run_in_session(engine, _write)


def remove(engine: Engine, source: str, platform_id: str, valid_from: date) -> bool:
    """Delete the venue's matrix that starts on ``valid_from``; True when
    there was one."""

    def _delete(session: Session) -> bool:
        row = session.get(AllergenMatrix, (source, platform_id, valid_from))
        if row is None:
            return False
        session.delete(row)
        session.flush()
        return True

    return _run_in_session(engine, _delete)


@dataclass(frozen=True)
class StoredMatrix:
    """One stored matrix, as the CLI lists it."""

    valid_from: date
    valid_until: date | None
    source: str
    entered_by: str
    entered_at: datetime
    row_count: int


def entries(engine: Engine, source: str, platform_id: str) -> list[StoredMatrix]:
    """Every matrix stored for the venue, oldest ``validFrom`` first."""

    def _read(session: Session) -> list[StoredMatrix]:
        found = session.scalars(
            select(AllergenMatrix)
            .where(AllergenMatrix.source == source)
            .where(AllergenMatrix.platform_id == platform_id)
            .order_by(AllergenMatrix.valid_from)
        )
        return [
            StoredMatrix(
                valid_from=row.valid_from,
                valid_until=row.valid_until,
                source=row.matrix_source,
                entered_by=row.entered_by,
                entered_at=row.entered_at,
                row_count=len(_stored_rows(row.rows_json)),
            )
            for row in found
        ]

    return _run_in_session(engine, _read)


def _stored_rows(text: str) -> list[object]:
    try:
        value = json.loads(text)
    except ValueError:
        return []
    return value if isinstance(value, list) else []


def current(
    engine: Engine, source: str, platform_id: str, today: date
) -> AllergenMatrixWire | None:
    """The venue's matrix that holds on ``today``, or None.

    Of the matrices whose ``validFrom`` is on or before ``today`` and whose
    ``validUntil`` is null or on or after it, the latest ``validFrom`` wins.
    A stored row that no longer reads as the wire form (a hand-edited
    database) answers None rather than a 500: the menu is the answer, the
    matrix only rides along.
    """

    def _read(session: Session) -> AllergenMatrix | None:
        row = session.scalars(
            select(AllergenMatrix)
            .where(AllergenMatrix.source == source)
            .where(AllergenMatrix.platform_id == platform_id)
            .where(AllergenMatrix.valid_from <= today)
            .where(
                (AllergenMatrix.valid_until.is_(None))
                | (AllergenMatrix.valid_until >= today)
            )
            .order_by(AllergenMatrix.valid_from.desc())
            .limit(1)
        ).first()
        if row is not None:
            session.expunge(row)
        return row

    row = _run_in_session(engine, _read)
    rows = [] if row is None else _stored_rows(row.rows_json)
    if row is None or not rows:
        return None
    try:
        return AllergenMatrixWire.model_validate(
            {
                "source": row.matrix_source,
                "validFrom": row.valid_from.isoformat(),
                "validUntil": (
                    None if row.valid_until is None else row.valid_until.isoformat()
                ),
                "rows": rows,
            }
        )
    except ValidationError:
        return None
