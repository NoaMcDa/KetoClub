"""The menu logic ported from the Dart client (architecture.md D25, #318).

This package is **pure**: it reads values and returns values. Nothing in it
may import ``fastapi``, ``starlette``, ``httpx`` or ``sqlalchemy``, open a
socket, read the clock or touch the database; the routes and services under
``app.routers`` and ``app.services`` do that and hand the results in. A test
(``tests/test_keto_models.py``) scans every module here for those imports.

``app.keto.models`` holds the wire models: pydantic mirrors of the Dart
``Menu``, ``MenuAnalysed`` and ``Venue`` families whose ``to_json`` output is
byte-identical to the Dart ``toJson`` (key order, null fields and all), so a
result the backend builds reads back through the client's ``tryFrom`` exactly
as one the client built itself. The Dart code stays the source of truth; the
golden corpus (#320) is how drift between the two is caught.
"""
