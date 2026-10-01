import 'package:flutter/material.dart';

/// Draws a visible ring around [child] while a keyboard user has focus
/// anywhere inside it (issue #264).
///
/// `InkWell`'s own focus highlight is a faint tint, easy to lose on a
/// tinted verdict tile or over a photo; this adds a solid outline in the
/// theme's primary colour. The ring shows only in the *traditional* focus
/// highlight mode, that is, once a key has been pressed: a mouse or touch
/// tap that happens to focus the same widget never leaves a ring behind.
///
/// It owns no focus node and takes no focus itself, so it changes neither
/// the tab order nor what activates the widget inside it.
class FocusRing extends StatefulWidget {
  /// Wraps [child], outlining it with [borderRadius] corners.
  const new({
    required this.child,
    required this.borderRadius,
    this.color,
    super.key,
  });

  /// The focusable widget the ring surrounds.
  final Widget child;

  /// The corner radius of the ring; match the child's own shape.
  final BorderRadius borderRadius;

  /// The ring's colour; the theme's primary colour when null.
  final Color? color;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _hasFocus = false;

  bool get _visible =>
      _hasFocus &&
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _hasFocus = focused),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: _visible ? Border.all(color: color, width: 2) : null,
        ),
        child: widget.child,
      ),
    );
  }
}
