import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/theme/loader_colors.dart';
import 'package:ketoclub/widgets/keto_foods.dart';

/// How long the foods take to go once round the orbit (the loading-states
/// design canvas's motion spec, issue #450).
const Duration ketoOrbitPeriod = Duration(milliseconds: 3600);

/// How long each line of kitchen talk stays before the next one (#451).
const Duration kitchenTalkPeriod = Duration(milliseconds: 2400);

/// Whether the platform asks for reduced motion
/// ([MediaQueryData.disableAnimations]): the loaders then hold still.
bool loaderMotionReduced(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// The orbit (issues #450, #451): a steak, a fried egg and a lettuce leaf
/// going round a dashed ring, upright all the way, each with a small bob of
/// its own.
///
/// [size] is the side of the square it fills. From 30px up it draws the
/// three foods; below that, three dots in the foods' colours, which is
/// all that reads at that size (the quick-score button).
///
/// With reduced motion ([loaderMotionReduced]) it holds still, the foods
/// at twelve, four and eight o'clock, and schedules no frames. Decorative:
/// the widget that shows it names the wait for a screen reader.
class KetoOrbit extends StatefulWidget {
  /// An orbit [size] logical pixels square.
  const new({this.size = 112, super.key});

  /// The side of the square the orbit fills.
  final double size;

  @override
  State<KetoOrbit> createState() => _KetoOrbitState();
}

class _KetoOrbitState extends State<KetoOrbit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: ketoOrbitPeriod,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loaderMotionReduced(context)) {
      _turn
        ..stop()
        ..value = 0;
    } else if (!_turn.isAnimating) {
      _turn.repeat();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final colors = LoaderColors.of(context);
    final dots = size < 30;
    final food = dots ? size * 0.36 : size * 0.25;
    final radius = dots ? (size - food) / 2 : size * 0.34;
    // No bob under reduced motion: the foods sit exactly on the ring.
    final bobHeight = dots || loaderMotionReduced(context)
        ? 0.0
        : math.max(1, size / 56);
    const foods = KetoFood.values;
    final dotColors = [colors.meat, colors.yolk, colors.leaf];
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: AnimatedBuilder(
          animation: _turn,
          builder: (context, _) {
            final turn = _turn.value * 2 * math.pi;
            return Stack(
              children: [
                if (!dots)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _DashedRingPainter(
                        color: colors.ring,
                        radius: radius,
                      ),
                    ),
                  ),
                for (var i = 0; i < foods.length; i++)
                  _placed(
                    angle: -math.pi / 2 + turn + i * 2 * math.pi / 3,
                    bob: -bobHeight * math.sin(3 * turn + i * 2 * math.pi / 3),
                    radius: radius,
                    size: size,
                    food: food,
                    child: dots
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              color: dotColors[i],
                              shape: BoxShape.circle,
                            ),
                          )
                        : KetoFoodIcon(foods[i], size: food),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// [child], [food] square, centred on the ring at [angle] and lifted by
  /// [bob].
  Widget _placed({
    required double angle,
    required double bob,
    required double radius,
    required double size,
    required double food,
    required Widget child,
  }) {
    final centre = size / 2;
    return Positioned(
      left: centre + radius * math.cos(angle) - food / 2,
      top: centre + radius * math.sin(angle) - food / 2 + bob,
      width: food,
      height: food,
      child: child,
    );
  }
}

/// The dashed ring the foods circle, [radius] from the centre.
class _DashedRingPainter extends CustomPainter {
  const new({required this.color, required this.radius});

  final Color color;

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: radius,
    );
    // About a 4px dash and a 4px gap, whatever the ring's size.
    final dashes = math.max(8, (2 * math.pi * radius / 8).round());
    final step = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * step, step / 2, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

/// A screen's first wait, centred (issues #450, #451): the orbit, the
/// [status] in bold under it and, when [talk] is on, a line of
/// [KitchenTalk] under that.
///
/// A screen reader hears [status] once, as a live region, and nothing
/// else: the orbit and the kitchen talk are decoration.
class KetoLoader extends StatelessWidget {
  /// A loader saying [status], with an orbit [orbitSize] square.
  const new({
    required this.status,
    this.orbitSize = 112,
    this.talk = true,
    super.key,
  });

  /// What is being waited for, in a few words: "Finding your location…".
  final String status;

  /// The side of the orbit's square.
  final double orbitSize;

  /// Whether a line of kitchen talk runs under [status].
  final bool talk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      label: status,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            KetoOrbit(size: orbitSize),
            const SizedBox(height: 12),
            Text(
              status,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (talk) ...[
              const SizedBox(height: 6),
              const KitchenTalk(textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

/// A wait that sits beside content, as one row on a card (#451): a small
/// orbit, the [status] in bold and, when [talk] is on, a line of
/// [KitchenTalk] under it. The menu's fetch and its analysis use it.
///
/// Announced as [KetoLoader] is: [status] once, nothing else.
class KetoLoaderStrip extends StatelessWidget {
  /// A strip saying [status].
  const new({required this.status, this.talk = true, super.key});

  /// What is being waited for, in a few words: "Asking the AI…".
  final String status;

  /// Whether a line of kitchen talk runs under [status].
  final bool talk;

  /// The side of the strip's orbit.
  static const double orbitSize = 44;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      label: status,
      child: ExcludeSemantics(
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const KetoOrbit(size: orbitSize),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        status,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (talk) ...[
                        const SizedBox(height: 3),
                        const KitchenTalk(),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A line of kitchen talk under a loader's status (#451): "Checking the
/// sauces…", "Swapping fries for salad…", one after another every
/// [kitchenTalkPeriod], each fading in.
///
/// Decoration: it adds nothing to the semantics tree, so a screen reader
/// is never interrupted by it. With reduced motion it shows the first line
/// and never changes.
class KitchenTalk extends StatefulWidget {
  /// A line of kitchen talk, aligned by [textAlign].
  const new({this.textAlign = TextAlign.start, super.key});

  /// How the line is aligned.
  final TextAlign textAlign;

  /// Every line, in the order shown, in the UI language.
  static List<String> linesOf(AppLocalizations l10n) => [
    l10n.loadingTalkCarbs,
    l10n.loadingTalkSauces,
    l10n.loadingTalkFries,
    l10n.loadingTalkSugar,
    l10n.loadingTalkBun,
  ];

  @override
  State<KitchenTalk> createState() => _KitchenTalkState();
}

class _KitchenTalkState extends State<KitchenTalk> {
  Timer? _timer;
  int _line = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loaderMotionReduced(context)) {
      _timer?.cancel();
      _timer = null;
      _line = 0;
    } else {
      _timer ??= Timer.periodic(
        kitchenTalkPeriod,
        (_) => setState(() => _line++),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = KitchenTalk.linesOf(AppLocalizations.of(context)!);
    final line = lines[_line % lines.length];
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return ExcludeSemantics(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Text(
          line,
          key: ValueKey<int>(_line % lines.length),
          textAlign: widget.textAlign,
          style: style,
        ),
      ),
    );
  }
}

/// How far a run of the quick score has got (issue #451): [done] of
/// [total] restaurants scored, as a row of segments that fill in the
/// accent colour, one per restaurant, so the progress is seen as well as
/// read.
///
/// Past [maxSegments] restaurants the segments would be slivers, so it is
/// one continuous bar instead. Decoration: the button above it already
/// reads "Estimating {done} of {total}…". Nothing in it moves on its own;
/// it changes only when [done] does.
class EstimateProgress extends StatelessWidget {
  /// Progress of [done] out of [total].
  const new({required this.done, required this.total, super.key});

  /// How many restaurants are scored so far.
  final int done;

  /// How many the run set out to score.
  final int total;

  /// The most restaurants shown one segment each.
  static const int maxSegments = 24;

  /// The bar's height.
  static const double height = 6;

  @override
  Widget build(BuildContext context) {
    final filled = Theme.of(context).colorScheme.primary;
    final empty = NeutralSurfaces.of(context).surface2;
    final radius = BorderRadius.circular(height / 2);
    final Widget bar;
    if (total <= 0) {
      bar = const SizedBox(height: height);
    } else if (total > maxSegments) {
      bar = ClipRRect(
        borderRadius: radius,
        child: LinearProgressIndicator(
          value: (done / total).clamp(0.0, 1.0),
          minHeight: height,
          color: filled,
          backgroundColor: empty,
        ),
      );
    } else {
      bar = Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: height,
                decoration: BoxDecoration(
                  color: i < done ? filled : empty,
                  borderRadius: radius,
                ),
              ),
            ),
          ],
        ],
      );
    }
    return ExcludeSemantics(child: bar);
  }
}
