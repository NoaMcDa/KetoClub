"""Runtime configuration, read from the environment and an optional `.env`.

Every value has a default that is safe for local development, so the service
starts with no `.env` at all. `backend/.env.example` documents the full set.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """The service's configuration.

    Attributes:
        openrouter_api_key: The server's model key. Empty means `/v1/chat`
            answers `notConfigured` rather than forwarding.
        openrouter_model: The model id requested upstream.
        wolt_base_url: Upstream host for the menu proxy. Never taken from a
            request: the proxy forwards to this host and no other.
        database_url: SQLAlchemy URL. SQLite by default; Postgres is an
            environment-variable swap.
        cors_origin_regex: Origins allowed to call this service. The default
            admits any localhost port, because Flutter's development server
            picks one at random.
        admin_token: Required by `/v1/admin/*`. Empty means those routes are
            unavailable.
        menu_cache_ttl_seconds: How long a proxied menu body stays fresh.
        chat_cache_ttl_seconds: How long a completion stays fresh. Equal to the
            app's own `menuCacheTtl` of 24 hours.
        rate_limit_per_minute: Per-install request ceiling, short window.
        rate_limit_per_day: Per-install request ceiling, long window.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    openrouter_api_key: str = ""
    openrouter_model: str = "nex-agi/nex-n2.5-pro:free"
    wolt_base_url: str = "https://restaurant-api.wolt.com"
    database_url: str = "sqlite:///./ketoclub.db"
    cors_origin_regex: str = r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"
    admin_token: str = ""
    menu_cache_ttl_seconds: int = 3600
    chat_cache_ttl_seconds: int = 86400
    rate_limit_per_minute: int = 5
    rate_limit_per_day: int = 40


@lru_cache
def get_settings() -> Settings:
    """Returns the process-wide settings, read once.

    Exposed as a FastAPI dependency so a test can override it without touching
    the environment.
    """
    return Settings()
