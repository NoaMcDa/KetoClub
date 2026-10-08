"""The website menu source's pure core, ported from Dart (D19, D25, #326).

The Python twins of ``lib/services/menu/website/``: the HTML readings
(:mod:`app.website.html`), the schema.org reader (:mod:`app.website.json_ld`),
the menu locator (:mod:`app.website.locator`) and the pure decision steps of
``WebsiteMenuAdapter`` (:mod:`app.website.adapter`).

This package is **pure**, like :mod:`app.keto`: it reads values and returns
values. Nothing in it may import ``fastapi``, ``starlette``, ``httpx`` or
``sqlalchemy``, open a socket, read the clock or touch the database; the
route that fetches pages hands each fetched page in and acts on the answer.
"""
