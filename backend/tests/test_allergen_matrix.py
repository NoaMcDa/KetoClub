"""The allergen-matrix format, its storage and the maintainer CLI (ALG-16).

No network: the storage tests run over an in-memory SQLite engine, and the
CLI is driven through ``main`` with that engine passed in.
"""

import io
import json
from datetime import UTC, date, datetime
from pathlib import Path
from typing import Any

import pytest
from sqlalchemy import Engine, inspect, text

from app.config import Settings
from app.db import Base, build_engine
from app.services import allergen_matrix as am
from tools import allergen_matrix as cli

_NOW = datetime(2026, 10, 15, 9, 30, tzinfo=UTC)


def _document(**overrides: Any) -> dict[str, Any]:
    document: dict[str, Any] = {
        "venue": {"source": "wolt", "platformId": "hamosad"},
        "source": "restaurant",
        "enteredBy": "Maintainer",
        "validFrom": "2026-10-01",
        "validUntil": "2027-03-31",
        "rows": [
            {
                "name": "שקשוקה",
                "aliases": ["Shakshuka"],
                "allergens": {"eggs": "contains", "gluten": "may_contain"},
            },
            {
                "name": "Tahini salad",
                "allergens": {"sesame": "contains", "milk": "free", "fish": ""},
            },
        ],
    }
    document.update(overrides)
    return document


@pytest.fixture
def engine() -> Engine:
    built = build_engine(Settings(DATABASE_URL="sqlite:///:memory:"))
    Base.metadata.create_all(built)
    return built


# --- the JSON format ---------------------------------------------------------


def test_a_json_document_reads_into_its_venue_metadata_and_rows() -> None:
    document = am.parse_document(_document())

    assert document.venue_source == "wolt"
    assert document.platform_id == "hamosad"
    assert document.source == "restaurant"
    assert document.entered_by == "Maintainer"
    assert document.valid_from == date(2026, 10, 1)
    assert document.valid_until == date(2027, 3, 31)
    assert [row.name for row in document.rows] == ["שקשוקה", "Tahini salad"]
    assert document.rows[0].aliases == ["Shakshuka"]
    # A blank cell ("" or null) is left out of the row.
    assert document.rows[1].allergens == {"sesame": "contains", "milk": "free"}


def test_the_wire_form_carries_no_person_and_writes_dates_iso() -> None:
    wire = am.parse_document(_document(validUntil=None)).wire()

    body = wire.model_dump(by_alias=True, mode="json")
    assert body["source"] == "restaurant"
    assert body["validFrom"] == "2026-10-01"
    assert body["validUntil"] is None
    assert "enteredBy" not in body
    assert body["rows"][0] == {
        "name": "שקשוקה",
        "aliases": ["Shakshuka"],
        "allergens": {"eggs": "contains", "gluten": "may_contain"},
    }


def test_the_columns_are_the_eu_14_by_taxonomy_id() -> None:
    assert am.ALLERGEN_COLUMNS == (
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
    )


@pytest.mark.parametrize(
    ("change", "message"),
    [
        ({"venue": {"source": "tabit", "platformId": "x"}}, "venue source"),
        ({"venue": {"source": "wolt", "platformId": "Bad Slug"}}, "platformId"),
        ({"venue": {"source": "tenbis", "platformId": "abc"}}, "platformId"),
        ({"venue": "wolt/hamosad"}, "venue must be"),
        ({"source": "a friend"}, "source must be one of"),
        ({"enteredBy": "  "}, "enteredBy"),
        ({"enteredBy": 7}, "enteredBy"),
        ({"enteredBy": "x" * 201}, "over 200"),
        ({"validFrom": "1.10.2026"}, "validFrom"),
        ({"validFrom": "2026-1-01"}, "validFrom"),
        ({"validFrom": 20261001}, "validFrom"),
        ({"validUntil": "2026-09-30"}, "before validFrom"),
        ({"rows": []}, "no rows"),
        ({"rows": "none"}, "rows must be a list"),
        ({"rows": ["dish"]}, "row 1: not an object"),
        ({"rows": [{"name": "x", "allergens": []}]}, "allergens must be"),
        ({"rows": [{"name": "x", "allergens": {"wheat": "free"}}]}, "EU 14"),
        ({"rows": [{"name": "x", "allergens": {"eggs": "yes"}}]}, "row 1"),
        ({"rows": [{"name": " ", "allergens": {}}]}, "blank"),
        ({"rows": [{"name": "x", "colour": "red", "allergens": {}}]}, "row 1"),
        ({"rows": [{"name": "!!", "allergens": {}}]}, "no letter or digit"),
        ({"extra": True}, "unknown field 'extra'"),
    ],
)
def test_a_malformed_document_is_refused_naming_the_problem(
    change: dict[str, Any], message: str
) -> None:
    with pytest.raises(am.MatrixFormatError, match=message):
        am.parse_document(_document(**change))


def test_a_document_that_is_not_an_object_is_refused() -> None:
    with pytest.raises(am.MatrixFormatError, match="not a JSON object"):
        am.parse_document(["rows"])


def test_more_rows_than_the_cap_are_refused() -> None:
    rows = [{"name": f"dish {i}", "allergens": {}} for i in range(am.MAX_ROWS + 1)]
    with pytest.raises(am.MatrixFormatError, match="more than 500"):
        am.parse_document(_document(rows=rows))


@pytest.mark.parametrize(
    ("first", "second"),
    [
        # The device's normaliser reads these as one name, so they are one dish.
        ("Shakshuka", "SHAKSHUKA!"),
        ("צ'יפס", "ציפס"),
        ("סלט חלומי", "סלט-חלומי"),
        ("Purée of the day", "Puree of the day"),
    ],
)
def test_two_rows_naming_one_dish_are_refused(first: str, second: str) -> None:
    rows = [
        {"name": first, "allergens": {"eggs": "free"}},
        {"name": "Other", "aliases": [second], "allergens": {"eggs": "contains"}},
    ]
    with pytest.raises(am.MatrixFormatError, match="same dish as row 1"):
        am.parse_document(_document(rows=rows))


def test_a_row_may_repeat_its_own_name_as_an_alias() -> None:
    rows = [{"name": "Shakshuka", "aliases": ["shakshuka"], "allergens": {}}]

    assert am.parse_document(_document(rows=rows)).rows[0].name == "Shakshuka"


# --- the CSV format ----------------------------------------------------------


def _csv(text: str, **overrides: Any) -> am.MatrixDocument:
    metadata: dict[str, Any] = {
        "venue_source": "tenbis",
        "platform_id": "9001",
        "source": "printed",
        "entered_by": "Maintainer",
        "valid_from": "2026-10-01",
        "valid_until": None,
    }
    metadata.update(overrides)
    return am.parse_csv(text, **metadata)


def test_a_csv_table_reads_like_the_json_document() -> None:
    document = _csv(
        "﻿name,aliases,eggs,sesame,gluten\n"
        "שקשוקה,Shakshuka|Shakshouka,Contains,,MAY CONTAIN\n"
        '"Salad, tahini",,free,contains,may_contain\n'
        ",,,,\n"
    )

    assert document.venue_source == "tenbis"
    assert document.source == "printed"
    assert document.valid_until is None
    assert [row.name for row in document.rows] == ["שקשוקה", "Salad, tahini"]
    assert document.rows[0].aliases == ["Shakshuka", "Shakshouka"]
    assert document.rows[0].allergens == {"eggs": "contains", "gluten": "may_contain"}
    assert document.rows[1].allergens == {
        "eggs": "free",
        "sesame": "contains",
        "gluten": "may_contain",
    }


@pytest.mark.parametrize(
    ("table", "message"),
    [
        ("", "empty"),
        ("dish,eggs\nx,free\n", "no name column"),
        ("name,wheat\nx,free\n", "'wheat' is not name"),
        ("name,eggs,eggs\nx,free,free\n", "named twice"),
        ("name,eggs\nx,yes\n", "line 2: eggs is 'yes'"),
        ("name,eggs\nx,free,extra\n", "line 2: more cells"),
        ("name,eggs\nx,free\nX,contains\n", "same dish as row 1"),
        ("name\n", "no rows"),
    ],
)
def test_a_malformed_csv_is_refused_naming_the_line(table: str, message: str) -> None:
    with pytest.raises(am.MatrixFormatError, match=message):
        _csv(table)


def test_the_csv_metadata_is_validated_too() -> None:
    with pytest.raises(am.MatrixFormatError, match="validFrom"):
        _csv("name,eggs\nx,free\n", valid_from="tomorrow")


def test_the_csv_template_has_every_column() -> None:
    header = am.csv_template().strip().split(",")

    assert header == ["name", "aliases", *am.ALLERGEN_COLUMNS]


# --- storage -----------------------------------------------------------------


def test_the_table_is_keyed_by_venue_and_date_with_no_install_id(
    engine: Engine,
) -> None:
    columns = {
        column["name"] for column in inspect(engine).get_columns("allergen_matrices")
    }
    keys = inspect(engine).get_pk_constraint("allergen_matrices")["constrained_columns"]

    assert keys == ["source", "platform_id", "valid_from"]
    assert not any("install" in column for column in columns)


def test_a_saved_matrix_is_current_within_its_dates_only(engine: Engine) -> None:
    created = am.save(engine, am.parse_document(_document()), now=_NOW)

    assert created is True
    assert am.current(engine, "wolt", "hamosad", date(2026, 9, 30)) is None
    found = am.current(engine, "wolt", "hamosad", date(2026, 10, 1))
    assert found is not None
    assert found.valid_from == "2026-10-01"
    assert found.rows[0].name == "שקשוקה"
    assert am.current(engine, "wolt", "hamosad", date(2027, 3, 31)) is not None
    assert am.current(engine, "wolt", "hamosad", date(2027, 4, 1)) is None
    assert am.current(engine, "wolt", "other", date(2026, 10, 15)) is None
    assert am.current(engine, "tenbis", "hamosad", date(2026, 10, 15)) is None


def test_the_latest_matrix_that_holds_wins(engine: Engine) -> None:
    am.save(engine, am.parse_document(_document(validUntil=None)), now=_NOW)
    newer = _document(
        validFrom="2026-11-01",
        validUntil=None,
        rows=[{"name": "Newer", "allergens": {"eggs": "free"}}],
    )
    am.save(engine, am.parse_document(newer), now=_NOW)

    october = am.current(engine, "wolt", "hamosad", date(2026, 10, 20))
    november = am.current(engine, "wolt", "hamosad", date(2026, 11, 2))
    assert october is not None and october.rows[0].name == "שקשוקה"
    assert november is not None and november.rows[0].name == "Newer"


def test_saving_the_same_day_again_replaces_it(engine: Engine) -> None:
    am.save(engine, am.parse_document(_document()), now=_NOW)
    again = _document(rows=[{"name": "Only", "allergens": {"milk": "contains"}}])

    created = am.save(engine, am.parse_document(again), now=_NOW)

    assert created is False
    stored = am.entries(engine, "wolt", "hamosad")
    assert len(stored) == 1
    assert stored[0].row_count == 1
    assert stored[0].entered_by == "Maintainer"
    assert stored[0].entered_at == datetime(2026, 10, 15, 9, 30)


def test_remove_deletes_one_matrix(engine: Engine) -> None:
    am.save(engine, am.parse_document(_document()), now=_NOW)

    assert am.remove(engine, "wolt", "hamosad", date(2026, 10, 1)) is True
    assert am.remove(engine, "wolt", "hamosad", date(2026, 10, 1)) is False
    assert am.entries(engine, "wolt", "hamosad") == []


def test_a_hand_edited_row_reads_as_no_matrix(engine: Engine) -> None:
    am.save(engine, am.parse_document(_document()), now=_NOW)
    with engine.begin() as connection:
        connection.execute(text("UPDATE allergen_matrices SET rows_json = '{oops'"))

    assert am.current(engine, "wolt", "hamosad", date(2026, 10, 15)) is None
    assert am.entries(engine, "wolt", "hamosad")[0].row_count == 0


def test_a_row_that_no_longer_validates_reads_as_no_matrix(engine: Engine) -> None:
    am.save(engine, am.parse_document(_document()), now=_NOW)
    with engine.begin() as connection:
        connection.execute(
            text("UPDATE allergen_matrices SET rows_json = :rows"),
            {"rows": json.dumps([{"name": "x", "allergens": {"eggs": "maybe"}}])},
        )

    assert am.current(engine, "wolt", "hamosad", date(2026, 10, 15)) is None


# --- the maintainer CLI ------------------------------------------------------


def _run(engine: Engine, *argv: str) -> tuple[int, str, str]:
    out, err = io.StringIO(), io.StringIO()
    code = cli.main(list(argv), out=out, err=err, engine=engine, now=_NOW)
    return code, out.getvalue(), err.getvalue()


def test_the_cli_imports_a_json_document(engine: Engine, tmp_path: Path) -> None:
    path = tmp_path / "matrix.json"
    path.write_text(json.dumps(_document(), ensure_ascii=False), encoding="utf-8")

    code, out, err = _run(engine, "import", str(path))

    assert (code, err) == (0, "")
    assert out == "stored wolt/hamosad from 2026-10-01: 2 rows\n"
    assert am.current(engine, "wolt", "hamosad", date(2026, 10, 15)) is not None
    code, out, _ = _run(engine, "import", str(path))
    assert out.startswith("replaced ")


def test_the_cli_imports_a_csv_with_its_metadata_flags(
    engine: Engine, tmp_path: Path
) -> None:
    path = tmp_path / "matrix.csv"
    path.write_text("name,sesame\nחומוס,contains\n", encoding="utf-8")

    code, out, _ = _run(
        engine,
        "import",
        str(path),
        "--venue",
        "tenbis/9001",
        "--source",
        "website",
        "--entered-by",
        "Maintainer",
        "--valid-from",
        "2026-10-01",
        "--valid-until",
        "2026-12-31",
    )

    assert code == 0
    assert out == "stored tenbis/9001 from 2026-10-01: 1 rows\n"
    found = am.current(engine, "tenbis", "9001", date(2026, 10, 15))
    assert found is not None
    assert found.source == "website"
    assert found.valid_until == "2026-12-31"


def test_the_cli_refuses_a_csv_without_its_flags(
    engine: Engine, tmp_path: Path
) -> None:
    path = tmp_path / "matrix.csv"
    path.write_text("name,sesame\nx,contains\n", encoding="utf-8")

    code, out, err = _run(engine, "import", str(path), "--venue", "wolt/x")

    assert code == 1
    assert out == ""
    assert err == "refused: a CSV needs --source, --entered-by, --valid-from\n"


@pytest.mark.parametrize(
    ("name", "content", "message"),
    [
        ("matrix.json", "{not json", "refused: not JSON"),
        ("matrix.txt", "name\n", "refused: the file must end in .json or .csv"),
        ("matrix.json", json.dumps(_document(rows=[])), "refused: the matrix has"),
    ],
)
def test_the_cli_refuses_a_bad_file_and_writes_nothing(
    engine: Engine, tmp_path: Path, name: str, content: str, message: str
) -> None:
    path = tmp_path / name
    path.write_text(content, encoding="utf-8")

    code, _, err = _run(engine, "import", str(path))

    assert code == 1
    assert err.startswith(message)
    assert am.entries(engine, "wolt", "hamosad") == []


def test_the_cli_refuses_a_missing_file(engine: Engine, tmp_path: Path) -> None:
    code, _, err = _run(engine, "import", str(tmp_path / "absent.json"))

    assert code == 1
    assert err.startswith("refused: ")


def test_the_cli_lists_and_removes(engine: Engine) -> None:
    code, out, _ = _run(engine, "list", "wolt/hamosad")
    assert (code, out) == (0, "no matrix for wolt/hamosad\n")

    am.save(engine, am.parse_document(_document()), now=_NOW)
    am.save(
        engine,
        am.parse_document(_document(validFrom="2027-04-01", validUntil=None)),
        now=_NOW,
    )
    code, out, _ = _run(engine, "list", "wolt/hamosad")
    assert code == 0
    assert out == (
        "2026-10-01 to 2027-03-31  restaurant  2 rows  by Maintainer\n"
        "2027-04-01 to -  restaurant  2 rows  by Maintainer\n"
    )

    code, out, _ = _run(engine, "remove", "wolt/hamosad", "2026-10-01")
    assert (code, out) == (0, "removed wolt/hamosad from 2026-10-01\n")
    code, _, err = _run(engine, "remove", "wolt/hamosad", "2026-10-01")
    assert code == 1
    assert err == "no matrix for wolt/hamosad from 2026-10-01\n"
    code, _, err = _run(engine, "remove", "wolt/hamosad", "October")
    assert code == 1
    assert err == "refused: valid_from must be YYYY-MM-DD\n"


def test_the_cli_prints_the_template(engine: Engine) -> None:
    code, out, _ = _run(engine, "template")

    assert code == 0
    assert out == am.csv_template()


def test_the_cli_rejects_a_venue_without_a_slash(engine: Engine) -> None:
    with pytest.raises(SystemExit) as exit_info:
        _run(engine, "list", "hamosad")

    assert exit_info.value.code == 2


def test_the_cli_opens_the_database_it_is_given(tmp_path: Path) -> None:
    url = f"sqlite:///{tmp_path / 'matrices.db'}"
    path = tmp_path / "matrix.json"
    path.write_text(json.dumps(_document()), encoding="utf-8")
    out, err = io.StringIO(), io.StringIO()

    code = cli.main(["--database-url", url, "import", str(path)], out=out, err=err)
    listed = io.StringIO()
    cli.main(["--database-url", url, "list", "wolt/hamosad"], out=listed, err=err)

    assert code == 0
    assert "2026-10-01" in listed.getvalue()
