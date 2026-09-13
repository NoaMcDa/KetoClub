/// Wall-clock time, injected everywhere a service needs "now" so tests
/// can control it (architecture.md §18.1, §18.4).
abstract interface class Clock {
  /// The current time.
  ///
  /// Never throws.
  DateTime now();
}

/// A [Clock] backed by the real system clock.
final class SystemClock implements Clock {
  /// Creates a clock backed by [DateTime.now].
  const new();

  @override
  DateTime now() => DateTime.now();
}
