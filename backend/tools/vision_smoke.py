"""Send menu pages to a running backend's ``POST /v1/chat`` (issue #88).

A person-run smoke check for D15 (#170): it posts ONE real request carrying
the given images or PDFs to a backend that holds a ``GEMINI_API_KEY``, and
prints the status, the latency, ``X-KetoClub-Cache`` (always ``bypass`` for
a request with images) and the reply. It makes real network calls, so no
test imports it and ``check.sh``'s coverage (``--cov=app``) never counts it.

    cd backend
    uv run python tools/vision_smoke.py \\
        --backend http://localhost:8000 \\
        --install-id 0123456789abcdef0123456789abcdef \\
        page1.jpg page2.jpg

The default prompts are short placeholders. For the app's real ones, save
``MenuAnalysisPrompt.systemPrompt()`` and a user prompt from
``lib/services/classifier/menu_analysis_prompt.dart`` to files and pass
``--system-prompt-file`` / ``--user-prompt-file`` (and ``--schema-file`` for
the strict schema, e.g. ``tests/fixtures/menu_analysis_schema.json``).
"""

import argparse
import base64
import json
import sys
import time
from pathlib import Path
from typing import Final

import httpx

_MIME_BY_SUFFIX: Final[dict[str, str]] = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".pdf": "application/pdf",
}

_DEFAULT_SYSTEM_PROMPT: Final = (
    "You are the keto-diet menu analyst for KetoClub. The user message is "
    "followed by photographs or a PDF of a restaurant menu. Read every dish "
    "on the pages and classify each into exactly one of three verdicts: "
    '"orderAsIs", "modifiable" or "nonKeto". Respond with JSON only.'
)

_DEFAULT_USER_PROMPT: Final = (
    "Classify every dish on the attached menu pages. For each dish give its "
    'name exactly as printed, its verdict, a short "why", and for a '
    '"modifiable" dish the exact "modification" to ask the waiter for.'
)


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Post menu pages to a backend's POST /v1/chat once."
    )
    parser.add_argument(
        "--backend",
        default="http://localhost:8000",
        help="backend base URL (default: %(default)s)",
    )
    parser.add_argument(
        "--install-id",
        required=True,
        help="a 32-character lowercase hex install id",
    )
    parser.add_argument("--system-prompt-file", type=Path)
    parser.add_argument("--user-prompt-file", type=Path)
    parser.add_argument(
        "--schema-file",
        type=Path,
        help="strict JSON schema sent as response_schema",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=120.0,
        help="seconds to wait for the reply (default: %(default)s)",
    )
    parser.add_argument(
        "pages",
        nargs="+",
        type=Path,
        help="image (.jpg/.jpeg/.png/.webp) or .pdf files, in page order",
    )
    return parser.parse_args(argv)


def _image_part(path: Path) -> dict[str, str]:
    mime_type = _MIME_BY_SUFFIX.get(path.suffix.lower())
    if mime_type is None:
        allowed = ", ".join(sorted(_MIME_BY_SUFFIX))
        raise SystemExit(f"{path}: unsupported file type (use {allowed})")
    data = base64.b64encode(path.read_bytes()).decode("ascii")
    return {"mime_type": mime_type, "data": data}


def _body(args: argparse.Namespace) -> dict[str, object]:
    system_prompt = (
        args.system_prompt_file.read_text(encoding="utf-8")
        if args.system_prompt_file
        else _DEFAULT_SYSTEM_PROMPT
    )
    user_prompt = (
        args.user_prompt_file.read_text(encoding="utf-8")
        if args.user_prompt_file
        else _DEFAULT_USER_PROMPT
    )
    body: dict[str, object] = {
        "system_prompt": system_prompt,
        "user_prompt": user_prompt,
        "images": [_image_part(path) for path in args.pages],
    }
    if args.schema_file:
        body["response_schema"] = json.loads(
            args.schema_file.read_text(encoding="utf-8")
        )
        body["schema_name"] = "menu_analysis"
    return body


def main(argv: list[str]) -> int:
    """Post one request and print what came back; 0 on HTTP 200."""
    args = _parse_args(argv)
    body = _body(args)
    url = f"{args.backend.rstrip('/')}/v1/chat"
    print(f"POST {url} with {len(args.pages)} page(s)")

    started = time.perf_counter()
    try:
        response = httpx.post(
            url,
            json=body,
            headers={"X-KetoClub-Install-Id": args.install_id},
            timeout=args.timeout,
        )
    except httpx.HTTPError as error:
        print(f"request failed: {type(error).__name__}", file=sys.stderr)
        return 1
    latency = time.perf_counter() - started

    print(f"status: {response.status_code}")
    print(f"latency: {latency:.1f} s")
    print(f"X-KetoClub-Cache: {response.headers.get('X-KetoClub-Cache', '-')}")
    try:
        print(json.dumps(response.json(), ensure_ascii=False, indent=2))
    except ValueError:
        print(response.text)
    return 0 if response.status_code == 200 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
