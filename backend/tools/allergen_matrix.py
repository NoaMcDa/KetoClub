"""Enter a restaurant's allergen matrix by hand (ALG-16, issue #358).

The maintainer's intake path, and for now the only one: there is no public
write route and no account system (the restaurant-facing upload page is a
later issue). A matrix goes straight into the backend's database, in the
``allergen_matrices`` table beside ``stored_menus``, and ``GET
/v1/venue-menus`` returns the one that holds today as ``allergenMatrix``.
The format is documented in ``backend/README.md``.

Usage, from ``backend/`` (the database is ``DATABASE_URL`` from ``.env``, or
``--database-url``)::

    uv run python tools/allergen_matrix.py template > matrix.csv
    uv run python tools/allergen_matrix.py import matrix.json
    uv run python tools/allergen_matrix.py import matrix.csv \\
        --venue wolt/hamosad --source restaurant --entered-by "Noa" \\
        --valid-from 2026-10-01 [--valid-until 2027-03-31]
    uv run python tools/allergen_matrix.py list wolt/hamosad
    uv run python tools/allergen_matrix.py remove wolt/hamosad 2026-10-01

A ``.json`` file carries its own venue and metadata; a ``.csv`` file takes
them as flags. Either is validated as a whole before anything is written:
an unknown column, a cell that is not ``contains``/``may_contain``/``free``/
empty, two rows naming the same dish, or a bad date is refused with the line
or row it is on, and the database is left as it was. No install id is read
or written here.
"""

import argparse
import json
import sys
from collections.abc import Sequence
from datetime import UTC, date, datetime
from pathlib import Path
from typing import TextIO

from sqlalchemy import Engine

from app.config import Settings
from app.db import Base, build_engine
from app.services import allergen_matrix
from app.services.allergen_matrix import MatrixDocument, MatrixFormatError


def _venue(raw: str) -> tuple[str, str]:
    source, slash, platform_id = raw.partition("/")
    if not slash or not source or not platform_id:
        raise argparse.ArgumentTypeError("a venue is SOURCE/PLATFORM_ID")
    return source, platform_id


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="allergen_matrix",
        description="Enter, list or remove a restaurant's allergen matrix.",
    )
    parser.add_argument(
        "--database-url", help="the database to write (default: DATABASE_URL)"
    )
    commands = parser.add_subparsers(dest="command", required=True)

    commands.add_parser("template", help="print an empty CSV with every column")

    enter = commands.add_parser("import", help="validate and store one matrix")
    enter.add_argument("file", type=Path, help="a .json document or a .csv table")
    enter.add_argument("--venue", type=_venue, help="CSV only: SOURCE/PLATFORM_ID")
    enter.add_argument("--source", help="CSV only: restaurant, printed or website")
    enter.add_argument("--entered-by", help="CSV only: who typed it in")
    enter.add_argument("--valid-from", help="CSV only: first day, YYYY-MM-DD")
    enter.add_argument("--valid-until", help="CSV only: last day, YYYY-MM-DD")

    listing = commands.add_parser("list", help="list a venue's stored matrices")
    listing.add_argument("venue", type=_venue, help="SOURCE/PLATFORM_ID")

    removal = commands.add_parser("remove", help="delete one stored matrix")
    removal.add_argument("venue", type=_venue, help="SOURCE/PLATFORM_ID")
    removal.add_argument("valid_from", help="its first day, YYYY-MM-DD")
    return parser


def _document(arguments: argparse.Namespace) -> MatrixDocument:
    path: Path = arguments.file
    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() == ".json":
        try:
            raw: object = json.loads(text)
        except ValueError as error:
            raise MatrixFormatError(f"not JSON: {error}") from None
        return allergen_matrix.parse_document(raw)
    if path.suffix.lower() != ".csv":
        raise MatrixFormatError("the file must end in .json or .csv")
    missing = [
        flag
        for flag, value in (
            ("--venue", arguments.venue),
            ("--source", arguments.source),
            ("--entered-by", arguments.entered_by),
            ("--valid-from", arguments.valid_from),
        )
        if value is None
    ]
    if missing:
        raise MatrixFormatError(f"a CSV needs {', '.join(missing)}")
    venue_source, platform_id = arguments.venue
    return allergen_matrix.parse_csv(
        text,
        venue_source=venue_source,
        platform_id=platform_id,
        source=arguments.source,
        entered_by=arguments.entered_by,
        valid_from=arguments.valid_from,
        valid_until=arguments.valid_until,
    )


def _engine(arguments: argparse.Namespace) -> Engine:
    url = arguments.database_url or Settings().DATABASE_URL
    engine = build_engine(Settings(DATABASE_URL=url))
    Base.metadata.create_all(engine)
    return engine


def main(
    argv: Sequence[str] | None = None,
    *,
    out: TextIO = sys.stdout,
    err: TextIO = sys.stderr,
    engine: Engine | None = None,
    now: datetime | None = None,
) -> int:
    """Run one command; 0 on success, 1 when refused, 2 on a usage error.

    ``engine`` and ``now`` are seams for the tests; a person passes neither.
    """
    arguments = _parser().parse_args(argv)
    if arguments.command == "template":
        out.write(allergen_matrix.csv_template())
        return 0
    try:
        if arguments.command == "import":
            document = _document(arguments)
            db = engine or _engine(arguments)
            created = allergen_matrix.save(db, document, now=now or datetime.now(UTC))
            verb = "stored" if created else "replaced"
            out.write(
                f"{verb} {document.venue_source}/{document.platform_id} "
                f"from {document.valid_from.isoformat()}: "
                f"{len(document.rows)} rows\n"
            )
            return 0
        source, platform_id = arguments.venue
        db = engine or _engine(arguments)
        if arguments.command == "list":
            stored = allergen_matrix.entries(db, source, platform_id)
            if not stored:
                out.write(f"no matrix for {source}/{platform_id}\n")
            for entry in stored:
                until = entry.valid_until.isoformat() if entry.valid_until else "-"
                out.write(
                    f"{entry.valid_from.isoformat()} to {until}  {entry.source}  "
                    f"{entry.row_count} rows  by {entry.entered_by}\n"
                )
            return 0
        try:
            start = date.fromisoformat(arguments.valid_from)
        except ValueError:
            raise MatrixFormatError("valid_from must be YYYY-MM-DD") from None
        if not allergen_matrix.remove(db, source, platform_id, start):
            err.write(f"no matrix for {source}/{platform_id} from {start}\n")
            return 1
        out.write(f"removed {source}/{platform_id} from {start.isoformat()}\n")
        return 0
    except (MatrixFormatError, OSError) as error:
        err.write(f"refused: {error}\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
