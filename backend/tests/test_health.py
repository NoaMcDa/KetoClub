"""Health endpoint and the CORS policy that is this service's whole point."""

from fastapi.testclient import TestClient

from app import __version__
from app.config import Settings
from app.main import create_app


def test_health_reports_ok_and_no_model_key(client: TestClient) -> None:
    response = client.get("/v1/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "version": __version__,
        "llm_configured": False,
    }


def test_health_reports_a_configured_model_key_without_revealing_it() -> None:
    settings = Settings(
        _env_file=None,
        database_url="sqlite://",
        openrouter_api_key="sk-secret-value",
    )
    with TestClient(create_app(settings)) as client:
        response = client.get("/v1/health")

    assert response.json()["llm_configured"] is True
    assert "sk-secret-value" not in response.text


def test_a_localhost_origin_is_allowed_on_any_port(client: TestClient) -> None:
    response = client.get("/v1/health", headers={"Origin": "http://localhost:53421"})

    assert response.headers["access-control-allow-origin"] == "http://localhost:53421"


def test_a_foreign_origin_is_not_allowed(client: TestClient) -> None:
    response = client.get("/v1/health", headers={"Origin": "https://evil.example"})

    assert "access-control-allow-origin" not in response.headers


def test_the_preflight_admits_the_install_id_header(client: TestClient) -> None:
    response = client.options(
        "/v1/health",
        headers={
            "Origin": "http://localhost:1234",
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "X-KetoClub-Install-Id",
        },
    )

    assert response.status_code == 200
    allowed = response.headers["access-control-allow-headers"].lower()
    assert "x-ketoclub-install-id" in allowed
