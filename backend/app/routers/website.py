"""``POST /website/fetch``: one restaurant page, fetched politely (D19, #181).

The web build cannot read a restaurant's own site: browsers refuse the
cross-origin request, exactly as they do for Wolt (D11). So it asks this
route, which fetches the one URL server-side and hands back the document.
Phones fetch sites themselves with the same rules (D17). Unlike the Wolt and
10bis proxies the upstream host comes from the request, so this route is
fenced harder than they are:

- **Logged out, named.** No cookie, no credential, nothing of the inbound
  request is forwarded; every fetch sends ``WEBSITE_USER_AGENT``, which names
  KetoClub and a contact URL.
- **Public hosts only.** ``http``/``https`` on the default port; the host
  must resolve to globally routable addresses only (checked again on every
  redirect hop), so the route cannot reach this server's own network.
- **robots.txt is honoured** for ``ketoclubbot``, else ``*``; cached per host
  for ``WEBSITE_ROBOTS_TTL_SECONDS``. A 4xx robots.txt means no rules; a 5xx
  or an unreachable one means the site is not fetched (RFC 9309 §2.3.1.4).
- **AI opt-outs are honoured**: ``X-Robots-Tag: noai``, ``tdm-reservation:
  1`` and their ``<meta>`` forms.
- **Per-host and per-install rate limits**, and a size cap per kind.
- **Nothing is kept.** No response is cached or logged; a log line carries
  the host and the outcome only, never the path, the query or the body.

Every failure is a ``{reason, status_code}`` body with its own reason, which
the Dart client maps to a ``MenuFetchFailureReason`` one to one.
"""

import base64
from typing import Annotated

from fastapi import APIRouter, Depends, Request

from app.schemas import WebsiteFetchRequest, WebsiteFetchResponse
from app.services.install_id import require_install_id
from app.services.website_fetch import fetch_document

router = APIRouter()


@router.post("/website/fetch")
async def fetch_website(
    request: Request,
    install_id: Annotated[str, Depends(require_install_id)],
    body: WebsiteFetchRequest,
) -> WebsiteFetchResponse:
    """Fetch ``body.url`` (following up to five redirects) as HTML or PDF.

    The URL travels in the body rather than the query so the request log,
    which records the route path, never holds it. Every rule above is
    ``app.services.website_fetch.fetch_document``'s, shared with
    ``POST /v1/website-menu`` (#334).
    """
    document = await fetch_document(request, body.url.strip(), install_id)
    if document.kind == "pdf":
        return WebsiteFetchResponse(
            kind="pdf",
            content_type=document.content_type,
            body=base64.b64encode(document.content).decode("ascii"),
            final_url=document.final_url,
        )
    return WebsiteFetchResponse(
        kind="html",
        content_type=document.content_type,
        body=document.page or "",
        final_url=document.final_url,
    )
