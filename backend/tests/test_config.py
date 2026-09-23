"""Tests for ``app.config``."""

from app.config import Settings, get_settings


def test_defaults_match_documented_values() -> None:
    settings = Settings(_env_file=None)  # type: ignore[call-arg]

    assert settings.GEMINI_API_KEY == ""
    assert settings.GEMINI_MODEL == "gemini-2.5-flash"
    assert settings.GEMINI_BASE_URL == "https://generativelanguage.googleapis.com"
    assert settings.GEMINI_MAX_OUTPUT_TOKENS == 8192
    assert settings.GEMINI_THINKING_BUDGET == 0
    assert settings.WOLT_BASE_URL == "https://restaurant-api.wolt.com"
    assert settings.DATABASE_URL == "sqlite:///./ketoclub.db"
    assert settings.CORS_ORIGIN_REGEX == r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"
    assert settings.ADMIN_TOKEN == ""
    assert settings.MENU_CACHE_TTL_SECONDS == 3600
    assert settings.CHAT_CACHE_TTL_SECONDS == 86400
    assert settings.RATE_LIMIT_PER_MINUTE == 5
    assert settings.RATE_LIMIT_PER_DAY == 40


def test_llm_configured_is_false_with_no_key() -> None:
    settings = Settings(_env_file=None, GEMINI_API_KEY="")  # type: ignore[call-arg]

    assert settings.llm_configured is False


def test_llm_configured_is_true_with_a_key() -> None:
    settings = Settings(_env_file=None, GEMINI_API_KEY="test-key")  # type: ignore[call-arg]

    assert settings.llm_configured is True


def test_get_settings_is_cached() -> None:
    assert get_settings() is get_settings()
