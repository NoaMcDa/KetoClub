import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/scanned_menu.dart';

/// The width of one page thumbnail in [ScannedPagesSheet].
const double _thumbnailWidth = 96;

/// The height of one page thumbnail: a portrait page's proportions.
const double _thumbnailHeight = 128;

/// The pages a scanned menu was read from, as thumbnails (architecture.md
/// D15; issue #89).
///
/// The transcription's honest source: the model read these pages, and
/// the user can check the dish names against them. An image page opens
/// full screen, zoomable, on a tap; a PDF page is a labelled tile, since
/// rendering a PDF would need a plugin this app does not carry. Shown by
/// the menu screen's "View pages" action as a dismissible bottom sheet.
///
/// With [initialPage] the sheet opens at that page (issue #250): the page's
/// tile is outlined and an image page is already open full screen, which
/// is what tapping a thumbnail in the Scan tab's page list asks for.
class ScannedPagesSheet extends StatelessWidget {
  /// Creates a sheet showing [scan]'s pages in order, opened at
  /// [initialPage] when given.
  const new({required this.scan, this.initialPage, super.key});

  /// The pages to show, in reading order.
  final ScannedMenu scan;

  /// The 0-based index of the page to open at, or null for none. An index
  /// outside [scan]'s pages is ignored.
  final int? initialPage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.scannedMenuPagesTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.scannedMenuPagesClose,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Text(
                l10n.scannedMenuPagesNote,
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < scan.pages.length; i++)
                  _PageTile(
                    page: scan.pages[i],
                    number: i + 1,
                    selected: i == initialPage,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One page of [ScannedPagesSheet]: an image thumbnail that opens full
/// screen, or a PDF tile.
class _PageTile extends StatefulWidget {
  const new({required this.page, required this.number, required this.selected});

  final ScannedPage page;

  /// The page's 1-based position, for its semantic label.
  final int number;

  /// Whether the sheet was opened at this page: it is outlined, and an
  /// image page opens full screen once the sheet is on screen.
  final bool selected;

  @override
  State<_PageTile> createState() => _PageTileState();
}

class _PageTileState extends State<_PageTile> {
  ScannedPage get page => widget.page;

  @override
  void initState() {
    super.initState();
    if (widget.selected && !page.isPdf) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openFullScreen(
            context,
            AppLocalizations.of(context)!.scannedMenuPageLabel(widget.number),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final number = widget.number;
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final label = l10n.scannedMenuPageLabel(number);
    final border = BorderRadius.circular(8);
    final outline = widget.selected
        ? Border.all(color: theme.colorScheme.primary, width: 2)
        : null;
    if (page.isPdf) {
      return Semantics(
        label: label,
        selected: widget.selected,
        child: Container(
          width: _thumbnailWidth,
          height: _thumbnailHeight,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: border,
            border: outline,
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.picture_as_pdf_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.scannedMenuPdfPage,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      );
    }
    return Semantics(
      label: label,
      button: true,
      selected: widget.selected,
      child: InkWell(
        borderRadius: border,
        onTap: () => _openFullScreen(context, label),
        child: Container(
          decoration: BoxDecoration(borderRadius: border, border: outline),
          child: ClipRRect(
            borderRadius: border,
            child: SizedBox(
              width: _thumbnailWidth,
              height: _thumbnailHeight,
              child: _image(fit: BoxFit.cover),
            ),
          ),
        ),
      ),
    );
  }

  /// The page's image, or a broken-image icon when its bytes do not
  /// decode — a thumbnail must never throw the sheet away.
  Widget _image({required BoxFit fit}) => Image.memory(
    page.bytes,
    fit: fit,
    gaplessPlayback: true,
    errorBuilder: (context, _, _) => Center(
      child: Icon(
        Icons.broken_image_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  /// Shows the page at full size, pinch-zoomable, until dismissed.
  void _openFullScreen(BuildContext context, String label) {
    final closeLabel = AppLocalizations.of(context)!.scannedMenuPagesClose;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog.fullscreen(
          child: Stack(
            children: [
              Positioned.fill(
                child: Semantics(
                  label: label,
                  image: true,
                  child: InteractiveViewer(
                    maxScale: 5,
                    child: Center(child: _image(fit: BoxFit.contain)),
                  ),
                ),
              ),
              PositionedDirectional(
                top: 8,
                end: 8,
                child: SafeArea(
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.close),
                    tooltip: closeLabel,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
