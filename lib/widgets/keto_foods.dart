import 'package:flutter/widgets.dart';
import 'package:ketoclub/theme/loader_colors.dart';

/// The three foods the loaders circle (issues #450, #451): one each for
/// the protein, the fat and the greens a keto plate is made of.
enum KetoFood {
  /// A steak, with its marbling and bone.
  steak,

  /// A fried egg.
  egg,

  /// A lettuce leaf.
  lettuce,
}

/// [food] drawn flat at [size] logical pixels square, in the theme's
/// [LoaderColors] (the loading-states design canvas; `web/index.html`
/// draws the same shapes for the web splash).
///
/// Decorative only: it adds nothing to the semantics tree. Below 20px the
/// marbling, the egg's highlight and the leaf's side veins are left out,
/// as the small loaders in the design do: at that size they read as
/// noise.
class KetoFoodIcon extends StatelessWidget {
  /// Draws [food] at [size].
  const new(this.food, {this.size = 28, super.key});

  /// Which food to draw.
  final KetoFood food;

  /// The side of the square the food is drawn in.
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: KetoFoodPainter(
          food: food,
          colors: LoaderColors.of(context),
          detailed: size >= 20,
        ),
      ),
    );
  }
}

/// Paints one [KetoFood] into whatever square it is given, from the
/// design's 48 × 48 drawing.
class KetoFoodPainter extends CustomPainter {
  /// Paints [food] in [colors], with its small details when [detailed].
  const new({required this.food, required this.colors, this.detailed = true});

  /// Which food to paint.
  final KetoFood food;

  /// The colours to paint it in.
  final LoaderColors colors;

  /// Whether to paint the details too small to read at a small size.
  final bool detailed;

  /// The side of the square the shapes below are drawn in.
  static const double _unit = 48;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / _unit, size.height / _unit);
    switch (food) {
      case KetoFood.steak:
        _paintSteak(canvas);
      case KetoFood.egg:
        _paintEgg(canvas);
      case KetoFood.lettuce:
        _paintLettuce(canvas);
    }
    canvas.restore();
  }

  void _paintSteak(Canvas canvas) {
    final body = Path()
      ..moveTo(8, 24)
      ..cubicTo(8, 14, 17, 8, 27, 9)
      ..cubicTo(37, 10, 42, 17, 41, 25)
      ..cubicTo(40, 34, 32, 40, 22, 39)
      ..cubicTo(13, 38, 8, 32, 8, 24)
      ..close();
    canvas.drawPath(body, Paint()..color = colors.meat);
    if (detailed) {
      final marbling = Path()
        ..moveTo(14, 22)
        ..cubicTo(17, 20, 20, 21, 22, 19)
        ..moveTo(15, 30)
        ..cubicTo(19, 31, 22, 29, 25, 31);
      canvas.drawPath(marbling, _stroke(colors.meatFat, 1.8));
    }
    canvas.drawCircle(
      const Offset(31, 22),
      detailed ? 4.5 : 5,
      Paint()..color = colors.bone,
    );
  }

  void _paintEgg(Canvas canvas) {
    final white = Path()
      ..moveTo(10, 26)
      ..cubicTo(8, 17, 15, 10, 23, 11)
      ..cubicTo(30, 9, 39, 13, 39, 21)
      ..cubicTo(41, 30, 35, 38, 26, 37)
      ..cubicTo(17, 39, 11, 34, 10, 26)
      ..close();
    canvas
      ..drawPath(white, Paint()..color = colors.eggWhite)
      ..drawPath(white, _stroke(colors.eggEdge, detailed ? 1.5 : 3))
      ..drawCircle(
        const Offset(24, 24),
        detailed ? 7 : 8,
        Paint()..color = colors.yolk,
      );
    if (detailed) {
      canvas.drawCircle(
        const Offset(21.6, 21.6),
        2,
        Paint()..color = colors.eggWhite.withValues(alpha: 0.75),
      );
    }
  }

  void _paintLettuce(Canvas canvas) {
    final leaf = Path()
      ..moveTo(24, 6)
      ..cubicTo(34, 12, 40, 22, 36, 32)
      ..cubicTo(33, 39, 27, 42, 24, 42)
      ..cubicTo(21, 42, 15, 39, 12, 32)
      ..cubicTo(8, 22, 14, 12, 24, 6)
      ..close();
    canvas.drawPath(leaf, Paint()..color = colors.leaf);
    if (!detailed) return;
    final veins = Path()
      ..moveTo(24, 12)
      ..lineTo(24, 40)
      ..moveTo(24, 20)
      ..lineTo(18, 16)
      ..moveTo(24, 20)
      ..lineTo(30, 16)
      ..moveTo(24, 28)
      ..lineTo(17, 24)
      ..moveTo(24, 28)
      ..lineTo(31, 24)
      ..moveTo(24, 35)
      ..lineTo(19, 32)
      ..moveTo(24, 35)
      ..lineTo(29, 32);
    canvas.drawPath(veins, _stroke(colors.vein, 1.6));
  }

  static Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round;

  @override
  bool shouldRepaint(KetoFoodPainter oldDelegate) =>
      oldDelegate.food != food ||
      oldDelegate.colors != colors ||
      oldDelegate.detailed != detailed;
}
