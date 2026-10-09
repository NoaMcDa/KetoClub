"""``app.keto`` stays pure (#318, #322, D25): no module under it imports a
web framework, an HTTP client or the database layer."""

import ast
from pathlib import Path

_KETO = Path(__file__).resolve().parents[1] / "app" / "keto"
_FORBIDDEN_ROOTS = {"fastapi", "starlette", "httpx", "sqlalchemy"}


def _imported_modules(path: Path) -> list[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"))
    names: list[str] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names.extend(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            names.append(node.module)
    return names


def test_the_keto_package_has_modules_to_check() -> None:
    names = {path.name for path in _KETO.rglob("*.py")}
    assert {"normaliser.py", "fingerprint.py", "dish_kind.py", "score.py"} <= names


def test_nothing_under_app_keto_imports_a_framework_or_the_database() -> None:
    offenders = [
        f"{path.relative_to(_KETO)}: {name}"
        for path in sorted(_KETO.rglob("*.py"))
        for name in _imported_modules(path)
        if name.split(".")[0] in _FORBIDDEN_ROOTS
    ]
    assert offenders == []


def test_the_scan_catches_every_import_form(tmp_path: Path) -> None:
    module = tmp_path / "bad.py"
    module.write_text(
        "import httpx\nfrom fastapi import APIRouter\n"
        "import sqlalchemy.orm as orm\nfrom . import sibling\n",
        encoding="utf-8",
    )
    assert _imported_modules(module) == ["httpx", "fastapi", "sqlalchemy.orm"]
