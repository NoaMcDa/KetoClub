"""Tests for ``GET /v1/health``."""

import logging

import pytest
from fastapi.testclient import TestClient

from app import __version__
from app.config import Settings
from app.main import create_app


def test_health_reports_ok_with_no_key_configured(client: TestClient) -> None:
    response = client.get("/v1/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "version": __version__,
        "llm_configured": False,
    }


def test_health_reports_llm_configured_when_key_set() -> None:
    app = create_app(
        settings=Settings(
            DATABASE_URL="sqlite:///:memory:", OPENROUTER_API_KEY="sk-test"
        )
    )
    with TestClient(app) as client:
        response = client.get("/v1/health")

    assert response.json()["llm_configured"] is True


def test_health_request_is_logged_without_leaking_secrets(
    client: TestClient, caplog: pytest.LogCaptureFixture
) -> None:
    with caplog.at_level(logging.INFO, logger="ketoclub.request"):
        response = client.get(
            "/v1/health", headers={"Authorization": "Bearer super-secret-value"}
        )

    assert response.status_code == 200
    records = [r for r in caplog.records if r.name == "ketoclub.request"]
    assert len(records) == 1

    record = records[0]
    assert record.route == "/v1/health"  # type: ignore[attr-defined]
    assert record.method == "GET"  # type: ignore[attr-defined]
    assert record.status == 200  # type: ignore[attr-defined]
    assert record.latency_ms >= 0  # type: ignore[attr-defined]
    assert isinstance(record.request_id, str) and record.request_id  # type: ignore[attr-defined]

    formatted = caplog.text
    assert "super-secret-value" not in formatted


def test_health_response_carries_request_id_header(client: TestClient) -> None:
    response = client.get("/v1/health")

    assert response.headers["X-Request-Id"]
