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
    GEMINI_API_KEY and ADMIN_TOKEN.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
    )

    # --- LLM ------------------------------------------------------------------
    # The server's Gemini API key.  Absent → /v1/chat returns notConfigured.
    # Sent upstream only as the ``x-goog-api-key`` header, never in a URL.
    GEMINI_API_KEY: str = ""
    # Model id in the generateContent path (#100).
    GEMINI_MODEL: str = "gemini-2.5-flash"
    # Upstream Gemini host.  Never taken from a request, for the same reason
    # as WOLT_BASE_URL; tests point respx at the default.
    GEMINI_BASE_URL: str = "https://generativelanguage.googleapis.com"
    # generationConfig.maxOutputTokens.  A full menu's verdicts fit well
    # inside it; a reply that hits it ends MAX_TOKENS and is badResponse.
    GEMINI_MAX_OUTPUT_TOKENS: int = 8192
    # generationConfig.thinkingConfig.thinkingBudget.  Thinking tokens count
    # against the output budget above, and this is a classification task
    # with a strict schema, so the default spends none on thinking.
    GEMINI_THINKING_BUDGET: int = 0

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
        """True when the server holds a Gemini key."""
        return bool(self.GEMINI_API_KEY)


@lru_cache
def get_settings() -> Settings:
    """Return the cached Settings singleton.

    Using lru_cache means environment variables are read once at startup.
    Tests override this via ``app.dependency_overrides``.
    """
    return Settings()
