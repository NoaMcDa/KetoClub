"""Tests for ``app.services.rate_limit.RateLimiter``, with an injected clock."""

from app.services.rate_limit import RateLimiter

_ID_A = "a" * 32
_ID_B = "b" * 32


class FakeClock:
    """A monotonic clock the test moves by hand."""

    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += seconds


def test_allows_up_to_the_per_minute_limit_then_refuses() -> None:
    limiter = RateLimiter(per_minute=2, per_day=100, clock=FakeClock())

    assert limiter.allow(_ID_A) is True
    assert limiter.allow(_ID_A) is True
    assert limiter.allow(_ID_A) is False


def test_minute_window_rolls_over_after_sixty_seconds() -> None:
    clock = FakeClock()
    limiter = RateLimiter(per_minute=1, per_day=100, clock=clock)

    assert limiter.allow(_ID_A) is True
    clock.advance(59.9)
    assert limiter.allow(_ID_A) is False
    clock.advance(0.1)
    assert limiter.allow(_ID_A) is True


def test_minute_window_slides_rather_than_resetting() -> None:
    clock = FakeClock()
    limiter = RateLimiter(per_minute=2, per_day=100, clock=clock)

    assert limiter.allow(_ID_A) is True
    clock.advance(30)
    assert limiter.allow(_ID_A) is True
    clock.advance(30)
    # The first hit has left the window; the second has not.
    assert limiter.allow(_ID_A) is True
    assert limiter.allow(_ID_A) is False


def test_day_limit_refuses_even_when_the_minute_window_is_clear() -> None:
    clock = FakeClock()
    limiter = RateLimiter(per_minute=5, per_day=3, clock=clock)

    for _ in range(3):
        assert limiter.allow(_ID_A) is True
        clock.advance(61)

    assert limiter.allow(_ID_A) is False


def test_day_window_rolls_over_after_twenty_four_hours() -> None:
    clock = FakeClock()
    limiter = RateLimiter(per_minute=5, per_day=1, clock=clock)

    assert limiter.allow(_ID_A) is True
    clock.advance(86399)
    assert limiter.allow(_ID_A) is False
    clock.advance(1)
    assert limiter.allow(_ID_A) is True


def test_refused_hits_are_not_recorded() -> None:
    clock = FakeClock()
    limiter = RateLimiter(per_minute=1, per_day=100, clock=clock)

    assert limiter.allow(_ID_A) is True
    clock.advance(30)
    assert limiter.allow(_ID_A) is False
    clock.advance(30)
    # Had the refused hit counted, the window would still be full.
    assert limiter.allow(_ID_A) is True


def test_install_ids_are_limited_independently() -> None:
    limiter = RateLimiter(per_minute=1, per_day=1, clock=FakeClock())

    assert limiter.allow(_ID_A) is True
    assert limiter.allow(_ID_A) is False
    assert limiter.allow(_ID_B) is True
    assert limiter.allow(_ID_B) is False


def test_default_clock_is_usable() -> None:
    limiter = RateLimiter(per_minute=1, per_day=1)

    assert limiter.allow(_ID_A) is True
    assert limiter.allow(_ID_A) is False
