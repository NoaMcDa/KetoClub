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
/// The meta line also carries the distance from the search position
/// ([distanceKm]) as metres or kilometres (issue #230), and nothing when
/// that is null.
///
/// The minutes figure is the platform's own delivery estimate when it
/// gave one, else the walking time from the search position
/// ([walkingMinutes]), labelled as walking; with neither, the meta line
/// shows the cuisine alone.
///
/// Drawn on a [Card] surface (issue #222), so it takes the theme's
/// `CardThemeData` shape — the rounded `--line` edge — and the photo sits
/// flush in its top, clipped to the card's corners. The ink well is laid
/// over the whole card, photo included, so a hover or keyboard focus on
/// the web lights up the entire tile rather than only the text below an
/// opaque photo.
///
/// A venue the platform reports closed (`isOnline == false`) carries a
/// small "Closed" tag in the photo's top-end corner (issue #227); open and
/// unknown venues are drawn exactly as before.
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
    this.photoAspectRatio,
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

  /// The photo's width-to-height ratio, or null for the phone's fixed
  /// [photoHeight] banner. The Discovery grid passes
  /// [gridPhotoAspectRatio] once it shows two or more cards per row
  /// (issue #222), where a fixed height would draw a strip.
  final double? photoAspectRatio;

  /// The photo tile's fixed height, from the artboard; its width is the
  /// card's full width ([PhotoTile.width] `double.infinity`), reproducing
  /// the artboard's banner (issue #50). The [Stack] the tile sits in hands
  /// it loose constraints, so a square tile would *not* be stretched — the
  /// visual audit (`docs/VISUAL_AUDIT.md`) found it drawn 118px square.
  /// Fixed so an image arriving late never shifts the list.
  static const double photoHeight = 118;

  /// The photo's aspect ratio when the card is one tile of a two- or
  /// three-column grid (issue #222, `docs/UX_REVIEW.md` §1 item 2): 3:2.
  static const double gridPhotoAspectRatio = 3 / 2;

  /// The inset around the text below the photo, inside the card's edge;
  /// `VenueCardSkeleton` reads it so a loading card has the same shape.
  static const EdgeInsetsDirectional textPadding =
      EdgeInsetsDirectional.fromSTEB(14, 10, 14, 14);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final verdictColors = VerdictColors.of(context);
    final cardNumbers = numbers;
    final blurb = venue.shortDescription;
    final meta = _meta(l10n);
    final aspectRatio = photoAspectRatio;
    // The card's own clip rounds the photo's top corners.
    final photo = aspectRatio == null
        ? PhotoTile(
            imageUrl: venue.imageUrl,
            size: photoHeight,
            width: double.infinity,
            borderRadius: BorderRadius.zero,
          )
        : AspectRatio(
            aspectRatio: aspectRatio,
            child: PhotoTile(
              imageUrl: venue.imageUrl,
              size: double.infinity,
              width: double.infinity,
              borderRadius: BorderRadius.zero,
            ),
          );

    // One node for the whole card: its children are excluded, so the tap
    // is re-exposed here or a screen reader could not open the venue.
    return Semantics(
      container: true,
      button: true,
      label: _semanticLabel(l10n),
      onTap: onTap,
      excludeSemantics: true,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  children: [
                    photo,
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
                    if (venue.isOnline == false)
                      PositionedDirectional(
                        top: 11,
                        end: 11,
                        child: _ClosedPill(text: l10n.venueCardClosed),
                      ),
                  ],
                ),
                Padding(
                  padding: textPadding,
                  child: _details(context, l10n, meta, blurb),
                ),
              ],
            ),
            // Above the content, so the hover and focus highlight covers
            // the photo too; an ink well under it would paint below the
            // opaque photo and light up only the text.
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(onTap: onTap),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The name with its score, the blurb, and the meta line with the
  /// counts: everything below the photo.
  Widget _details(
    BuildContext context,
    AppLocalizations l10n,
    String meta,
    String? blurb,
  ) {
    final theme = Theme.of(context);
    final verdictColors = VerdictColors.of(context);
    final cardNumbers = numbers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
              if (meta.isNotEmpty) Text(meta, style: theme.textTheme.bodySmall),
              if (cardNumbers != null)
                _YellowCount(
                  text: l10n.venueCardYellowCount(cardNumbers.yellow),
                  color: verdictColors.amber.rail,
                ),
              if (cardNumbers?.engine case final RulesEngine engine)
                EngineChip(engine: engine),
            ],
          ),
        ],
      ],
    );
  }

  /// "{cuisine} · {distance} · {N} min", leaving out whichever part is
  /// unknown (issue #230).
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
    final String? distance;
    if (km == null) {
      distance = null;
    } else {
      final label = formatDistance(km, locale: l10n.localeName);
      distance = switch (label.unit) {
        DistanceUnit.metres => l10n.venueCardDistanceMetres(label.value),
        DistanceUnit.kilometres => l10n.venueCardDistanceKm(label.value),
      };
    }
    return [?cuisine, ?distance, ?minutes].join(' · ');
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

/// The "Closed" tag over the photo of a venue whose platform reports it
/// offline (issue #227). Drawn in the theme's own ink on its surface, so
/// it reads on any photo in both themes; `contrast_test.dart` pins the
/// pair. Never shown for an unknown (`null`) state.
class _ClosedPill extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(10, 5, 10, 5),
        child: Text(
          text,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// The artboard's amber "{N} with changes" count, an icon (matching the
/// [DishVerdict.modifiable] pill's own icon) beside its own colour rather
/// than the colour standing alone (architecture.md §6.6).
class _YellowCount extends StatelessWidget {
  const new({required this.text, required this.color});

  final String text;

  /// This count's colour, shared by its icon and its text.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The parent `Wrap` hands this row the card's full width as its
    // bound; at a large text scale (architecture.md §8.3) the label alone
    // can be wider than that, so it is `Flexible` and wraps onto a second
    // line rather than overflowing the row's trailing edge.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.edit_note, size: 13, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
