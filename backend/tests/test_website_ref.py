"""``app.website.ref``: the website ref keeps step with the Dart resolver."""

import pytest

from app.website.ref import normalise_website_url


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("https://Cafe.example/menu/", "https://cafe.example/menu"),
        ("http://cafe.example:80/menu", "http://cafe.example/menu"),
        ("https://cafe.example:443/menu", "https://cafe.example/menu"),
        # #283: the fetcher refuses every other port, so no ref names one.
        ("http://cafe.example:8080/menu", None),
        ("https://cafe.example:8443/", None),
    ],
)
def test_normalise_website_url_ports(raw: str, expected: str | None) -> None:
    assert normalise_website_url(raw) == expected
