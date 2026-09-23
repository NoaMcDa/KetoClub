"""Tests for ``app.services.install_id``."""

import pytest

from app.errors import BackendError
from app.services.install_id import is_valid_install_id, log_safe, require_install_id

_VALID = "0123456789abcdef0123456789abcdef"


def test_thirty_two_lowercase_hex_characters_are_valid() -> None:
    assert is_valid_install_id(_VALID) is True


@pytest.mark.parametrize(
    "value",
    [
        "",
        _VALID[:-1],
        _VALID + "0",
        _VALID.upper(),
        "g" + _VALID[1:],
        _VALID + "\n",
        " " + _VALID[1:],
        "0123456789abcdef-0123456789abcde",
    ],
)
def test_anything_else_is_invalid(value: str) -> None:
    assert is_valid_install_id(value) is False


def test_log_safe_keeps_only_eight_characters() -> None:
    assert log_safe(_VALID) == "01234567"


def test_dependency_returns_a_valid_id() -> None:
    assert require_install_id(_VALID) == _VALID


def test_dependency_rejects_a_missing_id_as_bad_response() -> None:
    with pytest.raises(BackendError) as raised:
        require_install_id(None)

    assert raised.value.status_code == 400
    assert raised.value.reason == "badResponse"


def test_dependency_rejects_a_malformed_id_as_bad_response() -> None:
    with pytest.raises(BackendError) as raised:
        require_install_id("not-an-install-id")

    assert raised.value.status_code == 400
    assert raised.value.reason == "badResponse"
