import 'package:flutter/material.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/widgets/venue_card.dart';

/// One solid, rounded rectangle of [color] — the shared building block
/// every skeleton in this file is made of.
///
/// Never animated: a static two-tone placeholder was judged good enough
/// for issue #63 (`phase2_discovery_research.md` §8.2), so no shimmer
/// package is pulled in just to draw a loading card.
class _SkeletonBlock extends StatelessWidget {
  const new({
    required this.color,
    required this.height,
    this.width,
    this.radius = 6,
  });

  /// This block's fill colour — always a theme or `AppTokens` surface
  /// read by the widget that builds it, never a literal hex, so both
  /// themes stay correct with no colour wiring of this file's own.
  final Color color;

  /// This block's fixed height.
  final double height;

  /// This block's fixed width, or null to fill whatever the parent (an
  /// [Expanded], or a bounded [Column]) gives it.
  final double? width;

  /// This block's corner radius.
  final double radius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// A static placeholder shaped like [VenueCard] (issue #63): the same
/// fixed-height photo tile, a title bar with a score-badge-sized block
/// beside it, and two shorter bars where the blurb and the meta line sit.
///
/// The Discovery screen shows three of these in place of its old
/// spinner while `DiscoveryPhase.locating` or `.searching` is in flight
/// (`phase2_discovery_research.md` §8.2). Purely decorative — this
/// widget's own [ExcludeSemantics] keeps every block out of the
/// semantics tree, because the screen that lists a run of three wraps
/// the whole group in one `Semantics` label naming what is loading,
/// rather than each card announcing itself.
class VenueCardSkeleton extends StatelessWidget {
  /// Creates one venue-card-shaped placeholder.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final base = NeutralSurfaces.of(context).surface2;
    final bar = Theme.of(context).dividerColor;
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SkeletonBlock(
            color: base,
            height: VenueCard.photoHeight,
            radius: 16,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _SkeletonBlock(color: bar, height: 21)),
              const SizedBox(width: 10),
              _SkeletonBlock(color: bar, height: 21, width: 40, radius: 10),
            ],
          ),
          const SizedBox(height: 8),
          _SkeletonBlock(color: bar, height: 14, width: 200),
          const SizedBox(height: 6),
          _SkeletonBlock(color: bar, height: 14, width: 120),
        ],
      ),
    );
  }
}

/// A static placeholder shaped like `DishCard` (issue #63): a status-badge-
/// sized bar, two text bars for the name and description, a price-sized
/// bar, and the trailing 72×72 photo tile `DishCard` itself uses (it
/// exports no constant for that size, so this file states it again).
///
/// The Menu screen shows a run of these in place of its old "Reading the
/// menu…" text while `LoadPhase.fetching` has no menu yet
/// (`phase2_discovery_research.md` §8.2); `LoadPhase.classifying` and its
/// two engine phases keep `AnalysisProgressRow` instead (issue #65),
/// since by then the menu itself is already on screen. See
/// [VenueCardSkeleton] for why this widget excludes its own semantics
/// rather than each one announcing itself.
class DishCardSkeleton extends StatelessWidget {
  /// Creates one dish-card-shaped placeholder.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = NeutralSurfaces.of(context).surface2;
    final bar = theme.dividerColor;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border.all(color: theme.dividerColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SkeletonBlock(
                        color: bar,
                        height: 16,
                        width: 64,
                        radius: 8,
                      ),
                      const SizedBox(height: 8),
                      _SkeletonBlock(
                        color: bar,
                        height: 16,
                        width: double.infinity,
                      ),
                      const SizedBox(height: 6),
                      _SkeletonBlock(color: bar, height: 12, width: 160),
                      const SizedBox(height: 10),
                      _SkeletonBlock(color: bar, height: 14, width: 60),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _SkeletonBlock(color: base, height: 72, width: 72, radius: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A static placeholder shaped like the Saved tab's own entry tile
/// (issue #63): a title bar, then two shorter bars where the source line
/// and the dish count sit — the same rows `_SavedEntryTile` draws, minus
/// the photo tile it also has none of.
///
/// The Saved tab shows a run of these while `SavedController.isLoading`
/// is true. See [VenueCardSkeleton] for why this widget excludes its own
/// semantics rather than each one announcing itself.
class SavedEntrySkeleton extends StatelessWidget {
  /// Creates one saved-entry-shaped placeholder.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final bar = Theme.of(context).dividerColor;
    return ExcludeSemantics(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SkeletonBlock(color: bar, height: 16, width: 160),
              const SizedBox(height: 10),
              _SkeletonBlock(color: bar, height: 12, width: 130),
              const SizedBox(height: 8),
              _SkeletonBlock(color: bar, height: 12, width: 90),
            ],
          ),
        ),
      ),
    );
  }
}
