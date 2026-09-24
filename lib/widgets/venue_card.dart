import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/state/venue_search_controller.dart';
import 'package:ketoclub/theme/app_typography.dart';
import 'package:ketoclub/theme/verdict_colors.dart';
import 'package:ketoclub/utils/geo.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/keto_score_badge.dart';
import 'package:ketoclub/widgets/photo_tile.dart';

/// One venue in the Discovery list (issue #40, `.design/Discovery.dc.html`):
/// a photo tile, the name, the keto score, the platform's blurb, a
/// "{cuisine} · {N} min" meta line and the green/yellow counts.
///
/// **D13: the score and counts appear only when [numbers] is given** — an
/// analysis already in the device cache — and never as a placeholder
/// zero. When those numbers came from the rules engine, the existing
/// [EngineChip] label rides along as the "estimate" marker rather than a
/// new one.
///
/// The minutes figure is the platform's own delivery estimate when it
/// gave one, else the walking time from the search position
/// ([walkingMinutes]), labelled as walking; with neither, the meta line
/// shows the cuisine alone.
///
/// Laid out with directional insets and [PositionedDirectional] only, so
/// the whole card mirrors under a right-to-left [Directionality].
class VenueCard extends StatelessWidget {
  /// Creates a card for [venue], reporting a tap through [onTap].
  const new({
    required this.venue,
    required this.onTap,
    this.numbers,
    this.distanceKm,
    super.key,
  });

  /// The venue to show.
  final Venue venue;

  /// The cached analysis's score and counts for [venue] (D13), or null to
  /// show neither.
  final VenueCardNumbers? numbers;

  /// How far [venue] is from the search position, in kilometres, or null
  /// when either is unknown.
  final double? distanceKm;

  /// Called when the card is tapped; the screen opens the venue's menu.
  final VoidCallback onTap;

  /// The photo tile's fixed height, from the artboard; its width is the
  /// card's full width ([PhotoTile.width] `double.infinity`), reproducing
  /// the artboard's banner (issue #50). The [Stack] the tile sits in hands
  /// it loose constraints, so a square tile would *not* be stretched — the
  /// visual audit (`docs/VISUAL_AUDIT.md`) found it drawn 118px square.
  /// Fixed so an image arriving late never shifts the list.
  static const double photoHeight = 118;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final verdictColors = VerdictColors.of(context);
    final cardNumbers = numbers;
    final blurb = venue.shortDescription;
    final meta = _meta(l10n);

    // One node for the whole card: its children are excluded, so the tap
    // is re-exposed here or a screen reader could not open the venue.
    return Semantics(
      container: true,
      button: true,
      label: _semanticLabel(l10n),
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                PhotoTile(
                  imageUrl: venue.imageUrl,
                  size: photoHeight,
                  width: double.infinity,
                  borderRadius: BorderRadius.circular(16),
                ),
                if (cardNumbers != null)
                  PositionedDirectional(
                    top: 11,
                    start: 11,
                    child: _GreenPill(
                      text: l10n.venueCardGreenCount(cardNumbers.green),
                      background: verdictColors.green.pill,
                      foreground: verdictColors.green.on,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    venue.name,
                    style: AppTypography.displayStyle(
                      size: 21,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (cardNumbers != null) ...[
                  const SizedBox(width: 10),
                  KetoScoreBadge(score: cardNumbers.score, inline: true),
                ],
              ],
            ),
            if (blurb != null && blurb.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                blurb,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  height: 1.45,
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
            ],
            if (meta.isNotEmpty || cardNumbers != null) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (meta.isNotEmpty)
                    Text(meta, style: theme.textTheme.bodySmall),
                  if (cardNumbers != null)
                    _YellowCount(
                      text: l10n.venueCardYellowCount(cardNumbers.yellow),
                      dot: verdictColors.amber.rail,
                    ),
                  if (cardNumbers?.engine case final RulesEngine engine)
                    EngineChip(engine: engine),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "{cuisine} · {N} min", leaving out whichever part is unknown.
  String _meta(AppLocalizations l10n) {
    final cuisine = venue.cuisineTags.isEmpty
        ? null
        : cuisineLabel(venue.cuisineTags.first);
    final estimate = venue.estimateMinutes;
    final km = distanceKm;
    final String? minutes;
    if (estimate != null) {
      minutes = l10n.venueCardMinutes(estimate);
    } else if (km != null) {
      minutes = l10n.venueCardWalkMinutes(walkingMinutes(km));
    } else {
      minutes = null;
    }
    return [?cuisine, ?minutes].join(' · ');
  }

  /// Name, open or closed when known, the score when there is one, and
  /// the counts — one announcement for the whole card.
  String _semanticLabel(AppLocalizations l10n) {
    final cardNumbers = numbers;
    return [
      venue.name,
      if (venue.isOnline case final online?)
        if (online) l10n.venueCardOpenNow else l10n.venueCardClosed,
      if (cardNumbers != null) ...[
        l10n.menuKetoScoreSemanticLabel(cardNumbers.score.toStringAsFixed(1)),
        l10n.venueCardGreenCount(cardNumbers.green),
        l10n.venueCardYellowCount(cardNumbers.yellow),
      ],
    ].join(', ');
  }

  /// How a platform cuisine [tag] is shown, on the card and on the
  /// cuisine chip: its first letter upper-cased, since Wolt's tags arrive
  /// in lower case (`sushi`). A no-op for Hebrew, which has no case.
  static String cuisineLabel(String tag) =>
      tag.isEmpty ? tag : tag[0].toUpperCase() + tag.substring(1);
}

/// The artboard's green "{N} dishes as-is" pill over the photo.
class _GreenPill extends StatelessWidget {
  const new({
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 5, 10, 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 14, color: foreground),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                color: foreground,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The artboard's amber dot and "{N} with changes" count.
class _YellowCount extends StatelessWidget {
  const new({required this.text, required this.dot});

  final String text;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          child: const SizedBox.square(dimension: 8),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
