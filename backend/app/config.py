"""Application configuration via pydantic-settings.

All settings are read from environment variables (and from a .env file when
present).  The .env.example file lists every variable with its default and a
short description.  No setting is imported at module level outside this file;
callers use the ``get_settings`` dependency or import ``settings`` directly.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Typed, validated configuration for the KetoClub backend.

    Defaults are chosen so the server starts without any .env file and serves
    the health endpoint immediately.  Production deployments set at least
    OPENROUTER_API_KEY and ADMIN_TOKEN.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
    )

    # --- LLM ------------------------------------------------------------------
    # The server's OpenRouter key.  Absent → /v1/chat returns notConfigured.
    OPENROUTER_API_KEY: str = ""
    # Model id forwarded to OpenRouter (#100).  Kept in sync with the Dart
    # client's pinned model when that model is bumped.
    OPENROUTER_MODEL: str = "nex-agi/nex-n2.5-pro:free"

    # --- Proxy ----------------------------------------------------------------
    # Upstream Wolt host for the proxy route (#95).
    # Never taken from a request — hard-coded here so a misconfigured client
    # cannot redirect the proxy to an arbitrary host.
    WOLT_BASE_URL: str = "https://restaurant-api.wolt.com"

    # --- Database -------------------------------------------------------------
    DATABASE_URL: str = "sqlite:///./ketoclub.db"

    # --- CORS -----------------------------------------------------------------
    # Flutter's dev server picks a random port, so we allow any
    # localhost / 127.0.0.1 port.  Tighten for a public host.
    CORS_ORIGIN_REGEX: str = r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"

    # --- Auth -----------------------------------------------------------------
    # Bearer token for /v1/admin/* routes.  Absent → those routes return 503.
    ADMIN_TOKEN: str = ""

    # --- Cache TTLs -----------------------------------------------------------
    # Raw Wolt body cache TTL seconds (proxy route, #95).
    MENU_CACHE_TTL_SECONDS: int = 3600
    # Shared LLM completion cache TTL seconds (#103).
    CHAT_CACHE_TTL_SECONDS: int = 86400

    # --- Rate limits ----------------------------------------------------------
    # Per-install-ID limits on /v1/chat and write endpoints (#101).
    RATE_LIMIT_PER_MINUTE: int = 5
    RATE_LIMIT_PER_DAY: int = 40

    @property
    def llm_configured(self) -> bool:
        """True when the server holds an OpenRouter key."""
        return bool(self.OPENROUTER_API_KEY)


@lru_cache
def get_settings() -> Settings:
    """Return the cached Settings singleton.

    Using lru_cache means environment variables are read once at startup.
    Tests override this via ``app.dependency_overrides``.
    """
    return Settings()
