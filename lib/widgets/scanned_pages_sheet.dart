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
class ScannedPagesSheet extends StatelessWidget {
  /// Creates a sheet showing [scan]'s pages in order.
  const new({required this.scan, super.key});

  /// The pages to show, in reading order.
  final ScannedMenu scan;

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
                  _PageTile(page: scan.pages[i], number: i + 1),
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
class _PageTile extends StatelessWidget {
  const new({required this.page, required this.number});

  final ScannedPage page;

  /// The page's 1-based position, for its semantic label.
  final int number;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final label = l10n.scannedMenuPageLabel(number);
    final border = BorderRadius.circular(8);
    if (page.isPdf) {
      return Semantics(
        label: label,
        child: Container(
          width: _thumbnailWidth,
          height: _thumbnailHeight,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: border,
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
      child: InkWell(
        borderRadius: border,
        onTap: () => _openFullScreen(context, label),
        child: ClipRRect(
          borderRadius: border,
          child: SizedBox(
            width: _thumbnailWidth,
            height: _thumbnailHeight,
            child: _image(fit: BoxFit.cover),
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
