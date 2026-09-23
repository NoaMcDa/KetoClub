"""10bis upstream client: request headers, timeout and the URL builder.

``backend_plan.md`` §3.3, issue #122, shaped like ``app.services.wolt``
(#95). The user-agent string and timeout bounds are identical to Wolt's —
both proxies need a browser-shaped `User-Agent` because a browser cannot set
its own — so they are imported rather than duplicated. The response cache
is fully shared: ``read_cached_menu``/``write_cached_menu`` live in
``app.services.wolt``, generalised with a ``source`` parameter, so this
module has no cache code of its own.
"""

from app.services.wolt import WOLT_TIMEOUT, WOLT_USER_AGENT

# Built from scratch, never copied from the inbound request: nothing of the
# browser's own request (Origin, Cookie, Authorization, the install id)
# reaches 10bis (backend_plan.md §3.3).
TENBIS_HEADERS: dict[str, str] = {
    "User-Agent": WOLT_USER_AGENT,
    "Accept": "application/json",
}

# Same connect/read/write/pool bounds as the Wolt proxy; 10bis's own bounds
# are not documented anywhere, so they are set to match.
TENBIS_TIMEOUT = WOLT_TIMEOUT

# The ``source`` this platform writes into ``MenuCache`` rows (#122).
SOURCE = "tenbis"


def tenbis_menu_url(base_url: str, restaurant_id: str) -> str:
    """Build the upstream 10bis menu URL for ``restaurant_id``."""
    return f"{base_url}/api/v1.0/Restaurants/{restaurant_id}/Menu"
