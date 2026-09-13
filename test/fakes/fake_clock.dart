import 'package:ketoclub/services/platform/clock.dart';

/// A [Clock] fixed to a settable time. No real clock, ever.
final class FakeClock implements Clock {
  /// Creates a clock starting at [initial].
  new(this.initial) : _current = initial;

  /// The time this clock started at, before any [advance] call.
  final DateTime initial;

  DateTime _current;

  @override
  DateTime now() => _current;

  /// Moves this clock forward by [duration].
  void advance(Duration duration) {
    _current = _current.add(duration);
  }
}
