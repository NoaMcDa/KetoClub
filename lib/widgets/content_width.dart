import 'package:flutter/widgets.dart';

/// The widest a screen's content column grows, in logical pixels (issue
/// #221).
///
/// Every screen was drawn on a 390px artboard. Past this width a venue
/// photo turns into a letterbox strip and a button spans the monitor, so
/// the content stops here and the window's extra width is left as the
/// screen's own background on both sides.
const double contentMaxWidth = 680;

/// Centres [child] horizontally and caps its width at [maxWidth]
/// (architecture.md §6.6, issue #221).
///
/// Every screen body sits inside one of these, just inside its
/// `Scaffold`, so the `Scaffold`'s background and app bar stay full-bleed
/// on a wide web window and only the content column is capped. At phone
/// width, or any width up to [maxWidth], [child] fills the whole width and
/// is given the same height constraints it would be given without this
/// widget, so nothing on a phone moves.
///
/// The child is pinned to the top, not centred vertically as a plain
/// `Center` would: a `Scaffold` body is given loose height constraints,
/// so a short scroll view sizes itself to its content, and a `Center`
/// would float it halfway down the screen.
class ContentWidth extends StatelessWidget {
  /// Caps [child] at [maxWidth], which defaults to [contentMaxWidth].
  const new({required this.child, this.maxWidth = contentMaxWidth, super.key});

  /// The screen body being capped.
  final Widget child;

  /// The widest [child] is laid out, in logical pixels.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        // A tight width: without it a child that sizes to its content
        // would shrink and drift to the centre instead of filling the
        // column.
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
