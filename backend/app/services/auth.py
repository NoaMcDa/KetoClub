"""Route-level guards on inbound credentials.

``reject_authorization`` lived in ``app.routers.chat`` until the menu store
(#310) needed the same guard; it moved here unchanged so both routers share
one definition rather than one importing the other.
"""

from typing import Annotated

from fastapi import Header

from app.errors import BackendError


def reject_authorization(
    authorization: Annotated[str | None, Header()] = None,
) -> None:
    """400 ``badResponse`` for any inbound ``Authorization`` header.

    The backend holds the key; a client sending one is either confused or
    trying to have its own credential forwarded, and neither is served.
    Declared as a route-level dependency so it runs before anything else,
    body validation included.
    """
    if authorization is not None:
        raise BackendError(400, "badResponse")
