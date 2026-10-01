import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/platform/page_picker.dart';
import 'package:ketoclub/services/venue/qr_payload_router.dart';
import 'package:ketoclub/state/menu_controller.dart' show LoadPhase;
import 'package:ketoclub/state/scan_controller.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/venue_route.dart';
import 'package:ketoclub/widgets/analysis_progress_row.dart';
import 'package:ketoclub/widgets/app_sheet.dart';
import 'package:ketoclub/widgets/content_width.dart';
import 'package:ketoclub/widgets/scan_failure_copy.dart';
import 'package:ketoclub/widgets/scanned_pages_sheet.dart';
import 'package:provider/provider.dart';

/// The Scan tab (architecture.md §6.6, D15, D18; issues #11, #82, #83):
/// take a photo, choose photos or choose a PDF, list and remove the pages
/// collected, and analyse them in one go, or paste a menu's text instead.
/// Where the build has a camera scanner (not web), "Scan QR code" reads a
/// table's QR code (issue #182): a menu link opens the menu exactly as a
/// pasted one does, and a code that leads nowhere KetoClub can read says
/// why and suggests photographing the menu.
///
/// A `SegmentedButton` splits these into modes (issue #247): "Photos &
/// PDF", "Paste text" and, where the build can scan, "QR code". Each mode
/// shows its own inputs and exactly one `FilledButton`, so one primary
/// action is on screen at a time. Switching modes loses nothing: the pages
/// and the pasted text live in [ScanController].
///
/// Pages are read by a vision model, so one line under Analyse pages says
/// where they go (D17): through KetoClub's server on web, straight to
/// Google on phones, with a link to Settings where that is controlled. A
/// failed analysis keeps every page and offers Retry. Both Analyse paths
/// store the menu through [ScanController] and then push
/// `/venue/scan/{id}`, so the menu screen loads, classifies and caches it
/// exactly like a venue from a delivery platform.
///
/// A `StatefulWidget` only to own the [TextEditingController], the
/// selected mode, the in-flight picker flag and the last page rejection;
/// the pages and the pasted text themselves live in [ScanController].
class ScanScreen extends StatefulWidget {
  /// Creates the Scan tab, collecting pages through [pagePicker].
  ///
  /// [directToGoogle] is true on iOS and Android (D17), where pages go
  /// straight to Google's Gemini API with the user's own key, and false on
  /// web, where they go through KetoClub's server. It only picks the
  /// disclosure line and the wording of a `notConfigured` failure.
  const new({required this.pagePicker, this.directToGoogle = false, super.key});

  /// Where photos, images and PDFs come from.
  final PagePicker pagePicker;

  /// Whether pages go straight from this device to Google (iOS and
  /// Android, D17) rather than through KetoClub's server (web, D12).
  final bool directToGoogle;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final TextEditingController _field = TextEditingController();
  bool _picking = false;
  ScanPageRejection? _rejection;
  _ScanMode _mode = _ScanMode.pages;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _pick(Future<List<ScannedPage>> Function() source) async {
    final controller = context.read<ScanController>();
    setState(() {
      _picking = true;
      _rejection = null;
    });
    ScanPageRejection? rejection;
    try {
      final picked = await source();
      if (!mounted) return;
      rejection = controller.addPages(picked);
    } finally {
      // Reset even if a picker ever throws, so the buttons never stay
      // disabled for good.
      if (mounted) {
        setState(() {
          _picking = false;
          _rejection = rejection;
        });
      }
    }
  }

  void _remove(int index) {
    context.read<ScanController>().removePageAt(index);
    if (_rejection != null) setState(() => _rejection = null);
  }

  /// Opens the pages collected so far in [ScannedPagesSheet], at [index].
  void _preview(List<ScannedPage> pages, int index) {
    unawaited(
      showKetoClubSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => ScannedPagesSheet(
          scan: ScannedMenu(pages: pages),
          initialPage: index,
        ),
      ),
    );
  }

  Future<void> _analysePages() async {
    final ref = await context.read<ScanController>().analysePages();
    _open(ref);
  }

  Future<void> _analysePaste() async {
    final ref = await context.read<ScanController>().submitPaste(
      uncategorisedName: AppLocalizations.of(context)!.sourceScanned,
    );
    _open(ref);
  }

  Future<void> _scanQr() async {
    final venue = await context.read<ScanController>().scanQr();
    if (venue == null || !mounted) return;
    _open(venue.ref);
  }

  void _open(VenueRef? ref) {
    if (ref == null || !mounted) return;
    Navigator.pushNamed(context, venueRoutePath(ref));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.watch<ScanController>();
    // A build without a camera scanner has no QR segment to stay on.
    final mode = _mode == _ScanMode.qr && !controller.qrAvailable
        ? _ScanMode.pages
        : _mode;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanTitle)),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SegmentedButton<_ScanMode>(
              showSelectedIcon: false,
              expandedInsets: EdgeInsets.zero,
              style: SegmentedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              segments: [
                ButtonSegment(
                  value: _ScanMode.pages,
                  label: Text(l10n.scanScreenModePages),
                ),
                ButtonSegment(
                  value: _ScanMode.paste,
                  label: Text(l10n.scanScreenModePaste),
                ),
                if (controller.qrAvailable)
                  ButtonSegment(
                    value: _ScanMode.qr,
                    label: Text(l10n.scanScreenModeQr),
                  ),
              ],
              selected: <_ScanMode>{mode},
              onSelectionChanged: (selection) =>
                  setState(() => _mode = selection.single),
            ),
            const SizedBox(height: 20),
            ...switch (mode) {
              _ScanMode.pages => _pagesMode(l10n, controller),
              _ScanMode.paste => _pasteMode(l10n, controller),
              _ScanMode.qr => _qrMode(l10n, controller),
            },
          ],
        ),
      ),
    );
  }

  /// "Photos & PDF": the three pickers, the pages collected, the analysis'
  /// progress or failure, Analyse pages, and under it the line saying
  /// where the pages go with its Settings link.
  List<Widget> _pagesMode(AppLocalizations l10n, ScanController controller) {
    final theme = Theme.of(context);
    final pages = controller.pages;
    final canAdd = !controller.atPageCap && !controller.analysing && !_picking;
    final failure = controller.lastFailure;
    return [
      Text(l10n.scanScreenIntro, style: theme.textTheme.bodyMedium),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (widget.pagePicker.canTakePhoto)
            OutlinedButton.icon(
              onPressed: canAdd
                  ? () => unawaited(_pick(widget.pagePicker.takePhoto))
                  : null,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(l10n.scanScreenActionTakePhoto),
            ),
          OutlinedButton.icon(
            onPressed: canAdd
                ? () => unawaited(_pick(widget.pagePicker.pickImages))
                : null,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(l10n.scanScreenActionChoosePhotos),
          ),
          OutlinedButton.icon(
            onPressed: canAdd
                ? () => unawaited(_pick(widget.pagePicker.pickPdf))
                : null,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(l10n.scanScreenActionChoosePdf),
          ),
        ],
      ),
      if (_rejection != null) ...[
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(
            switch (_rejection!) {
              ScanPageRejection.tooManyPages => l10n.scanScreenTooManyPages(
                maxScanPages,
              ),
              ScanPageRejection.pageTooLarge => l10n.scanScreenPageTooLarge(
                maxScanPageBytes ~/ (1024 * 1024),
              ),
            },
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ],
      if (pages.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text(l10n.scanScreenPagesHeading, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          l10n.scanScreenPageCount(pages.length, maxScanPages),
          style: theme.textTheme.bodySmall,
        ),
        if (controller.atPageCap)
          Text(l10n.scanScreenCapReached, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: controller.movePage,
          children: [
            for (var i = 0; i < pages.length; i++)
              _PageRow(
                key: ObjectKey(pages[i]),
                page: pages[i],
                index: i,
                reorderable: !controller.analysing && pages.length > 1,
                onPreview: () => _preview(pages, i),
                onRemove: controller.analysing ? null : () => _remove(i),
              ),
          ],
        ),
      ],
      const SizedBox(height: 16),
      if (controller.analysing)
        const AnalysisProgressRow(phase: LoadPhase.classifying),
      if (failure != null && !controller.analysing) ...[
        Semantics(
          liveRegion: true,
          child: Text(
            scanFailureMessage(
              failure,
              l10n,
              directToGoogle: widget.directToGoogle,
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton(
            onPressed: controller.canAnalysePages
                ? () => unawaited(_analysePages())
                : null,
            child: Text(l10n.actionRetry),
          ),
        ),
        const SizedBox(height: 8),
      ],
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: controller.canAnalysePages
              ? () => unawaited(_analysePages())
              : null,
          child: Text(l10n.scanScreenAnalysePages),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        widget.directToGoogle
            ? l10n.scanScreenDisclosureDirect
            : l10n.scanScreenDisclosureWeb,
        style: theme.textTheme.bodySmall,
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton(
          style: TextButton.styleFrom(textStyle: theme.textTheme.bodySmall),
          onPressed: () => Navigator.pushNamed(context, '/settings'),
          child: Text(l10n.scanScreenSettingsLink),
        ),
      ),
    ];
  }

  /// "Paste text": the field, the empty-paste message and Analyse.
  List<Widget> _pasteMode(AppLocalizations l10n, ScanController controller) {
    final theme = Theme.of(context);
    return [
      Text(l10n.scanPasteIntro, style: theme.textTheme.bodyMedium),
      const SizedBox(height: 16),
      TextField(
        controller: _field,
        onChanged: (value) => controller.text = value,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        minLines: 8,
        maxLines: 14,
        decoration: InputDecoration(
          labelText: l10n.scanPasteLabel,
          hintText: l10n.scanPasteHint,
          alignLabelWithHint: true,
        ),
      ),
      if (controller.emptyPaste) ...[
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(
            l10n.scanEmptyPaste,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ],
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: controller.canAnalyse
              ? () => unawaited(_analysePaste())
              : null,
          child: Text(l10n.scanAnalyse),
        ),
      ),
    ];
  }

  /// "QR code" (only where the build has a camera scanner): what it does,
  /// "Scan QR code", and why the last code led nowhere, if it did.
  List<Widget> _qrMode(AppLocalizations l10n, ScanController controller) {
    final theme = Theme.of(context);
    final canScanQr = !controller.qrScanning && !controller.analysing;
    final qrNotice = controller.qrNotice;
    return [
      Text(l10n.scanScreenQrIntro, style: theme.textTheme.bodyMedium),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: canScanQr ? () => unawaited(_scanQr()) : null,
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(l10n.scanQrAction),
        ),
      ),
      if (qrNotice != null) ...[
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(switch (qrNotice) {
            QrUnsupportedSource(:final name) => l10n.scanQrUnsupportedSource(
              name,
            ),
            QrVenue() || QrPhotographInstead() => l10n.scanQrPhotographInstead,
          }, style: theme.textTheme.bodyMedium),
        ),
      ],
    ];
  }
}

/// The Scan tab's three ways in (issue #247), one primary action each.
enum _ScanMode {
  /// Photograph pages, choose photos or choose a PDF, then analyse them.
  pages,

  /// Paste a menu's text.
  paste,

  /// Scan a table's QR code (only where the build has a camera scanner).
  qr,
}

/// One collected page: a thumbnail (a PDF icon for a document), its label
/// and size, a drag handle that reorders it (issue #250), and a button that
/// removes it. Tapping the thumbnail calls [onPreview]. [onRemove] is null
/// while an analysis is reading the pages, and [reorderable] false.
class _PageRow extends StatelessWidget {
  const new({
    required this.page,
    required this.index,
    required this.reorderable,
    required this.onPreview,
    required this.onRemove,
    super.key,
  });

  final ScannedPage page;

  /// The row's 0-based position in the list; its label counts from 1.
  final int index;

  /// Whether the drag handle is shown: more than one page and no analysis.
  final bool reorderable;
  final VoidCallback onPreview;
  final VoidCallback? onRemove;

  static const double _thumb = 56;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final kb = (page.bytes.length / 1024).ceil();
    final number = index + 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: l10n.scanScreenPreviewPage(number),
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onPreview,
              child: SizedBox.square(
                dimension: _thumb,
                child: page.isPdf
                    ? Icon(
                        Icons.picture_as_pdf_outlined,
                        size: 32,
                        color: theme.colorScheme.onSurfaceVariant,
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(
                          page.bytes,
                          fit: BoxFit.cover,
                          cacheWidth: _thumb.toInt() * 2,
                          gaplessPlayback: true,
                          excludeFromSemantics: true,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.image_outlined,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  page.isPdf
                      ? l10n.scanScreenPdfLabel
                      : l10n.scanScreenPageLabel(number),
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  l10n.scanScreenPageSizeKb(kb),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (reorderable)
            ReorderableDragStartListener(
              index: index,
              child: Tooltip(
                message: l10n.scanScreenReorderPage(number),
                child: SizedBox.square(
                  dimension: 48,
                  child: Icon(
                    Icons.drag_handle,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.scanScreenRemovePage(number),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
