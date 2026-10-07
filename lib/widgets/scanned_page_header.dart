import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/widgets/focus_ring.dart';

/// The width of the page thumbnail in [ScannedPageHeader].
const double _thumbWidth = 48;

/// The height of the page thumbnail in [ScannedPageHeader].
const double _thumbHeight = 64;

/// The corner radius of the header card.
const double _cardRadius = 15;

/// The header above one scanned page's dishes on the menu screen: the
/// page's thumbnail, "Page n of N", and how many dishes the page held.
///
/// Tapping it (when [onTap] is given) opens that page, which is how the
/// user checks a dish against the photograph it was read from. The
/// [ScannedPageHeader.unknown] variant heads the dishes the model could not
/// place on any page; it is information only and never tappable.
class ScannedPageHeader extends StatelessWidget {
  /// Creates the header of page [number] (1-based) of [total] pages, or of
  /// "Page n" alone when [total] is null, with [dishCount] dishes.
  ///
  /// [thumbnail] is the page itself (null draws no tile); [onTap] makes the
  /// header a button that opens the page.
  new({
    required int this.number,
    required this.dishCount,
    this.total,
    this.thumbnail,
    this.onTap,
  }) : super(key: ValueKey('scannedPageHeader-$number'));

  /// Creates the header of the dishes no page could be matched to, with
  /// [dishCount] dishes. Not tappable.
  // A named constructor still needs its class name.
  // ignore: unnecessary_type_name_in_constructor
  const ScannedPageHeader.unknown({required this.dishCount})
    : number = null,
      total = null,
      thumbnail = null,
      onTap = null,
      super(key: const ValueKey('scannedPageHeader-unknown'));

  /// The page's 1-based number, or null for the unknown variant.
  final int? number;

  /// How many pages the scan has, or null to show "Page n" alone.
  final int? total;

  /// The page shown as a thumbnail, or null for no tile.
  final ScannedPage? thumbnail;

  /// How many dishes sit under this header.
  final int dishCount;

  /// Called when the header is tapped; null makes it plain information.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final n = number;
    final unknown = n == null;
    final title = unknown
        ? l10n.scannedPageUnknown
        : (total == null
              ? l10n.scannedMenuPageLabel(n)
              : l10n.scannedPageHeader(n, total!));
    final subtitle = unknown
        ? l10n.scannedPageUnknownExplain
        : l10n.scannedPageDishCount(dishCount);
    final page = thumbnail;
    final radius = BorderRadius.circular(_cardRadius);
    final muted = theme.colorScheme.onSurfaceVariant;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (unknown)
            Icon(Icons.info_outline, size: 24, color: muted)
          else if (page != null)
            _Thumb(page: page),
          if (unknown || page != null) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (onTap != null) Icon(Icons.chevron_right, color: muted),
        ],
      ),
    );
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: radius,
        border: Border.all(color: theme.dividerColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: onTap == null
            ? row
            : FocusRing(
                borderRadius: radius,
                child: InkWell(onTap: onTap, borderRadius: radius, child: row),
              ),
      ),
    );
    if (onTap == null) return card;
    return Semantics(
      button: true,
      label: l10n.scannedPageHeaderOpen,
      onTap: onTap,
      child: card,
    );
  }
}

/// The 48x64 page tile: the image, a broken-image icon when its bytes do
/// not decode, or a PDF tile.
class _Thumb extends StatelessWidget {
  const new({required this.page});

  final ScannedPage page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = BorderRadius.circular(6);
    final muted = theme.colorScheme.onSurfaceVariant;
    final content = page.isPdf
        ? Center(child: Icon(Icons.picture_as_pdf_outlined, color: muted))
        : Image.memory(
            page.bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, _, _) =>
                Center(child: Icon(Icons.broken_image_outlined, color: muted)),
          );
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: border,
        child: ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest,
          child: SizedBox(
            width: _thumbWidth,
            height: _thumbHeight,
            child: content,
          ),
        ),
      ),
    );
  }
}
