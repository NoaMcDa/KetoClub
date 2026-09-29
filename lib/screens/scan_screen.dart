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
import 'package:ketoclub/widgets/scan_failure_copy.dart';
import 'package:provider/provider.dart';

/// The Scan tab (architecture.md §6.6, D15, D18; issues #11, #82, #83):
/// take a photo, choose photos or choose a PDF, list and remove the pages
/// collected, and analyse them in one go, or paste a menu's text instead.
/// Where the build has a camera scanner (not web), "Scan QR code" reads a
/// table's QR code (issue #182): a menu link opens the menu exactly as a
/// pasted one does, and a code that leads nowhere KetoClub can read says
/// why and suggests photographing the menu.
///
/// Pages are read by a vision model, so one line above Analyse says where
/// they go (D17): through KetoClub's server on web, straight to Google on
/// phones, with a link to Settings where that is controlled. A failed
/// analysis keeps every page and offers Retry. Both Analyse paths store
/// the menu through [ScanController] and then push `/venue/scan/{id}`, so
/// the menu screen loads, classifies and caches it exactly like a venue
/// from a delivery platform.
///
/// A `StatefulWidget` only to own the [TextEditingController], the
/// in-flight picker flag and the last page rejection; the pages and the
/// pasted text themselves live in [ScanController].
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
    final picked = await source();
    if (!mounted) return;
    final rejection = controller.addPages(picked);
    setState(() {
      _picking = false;
      _rejection = rejection;
    });
  }

  void _remove(int index) {
    context.read<ScanController>().removePageAt(index);
    if (_rejection != null) setState(() => _rejection = null);
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
    final theme = Theme.of(context);
    final pages = controller.pages;
    final canAdd = !controller.atPageCap && !controller.analysing && !_picking;
    final canScanQr = !controller.qrScanning && !controller.analysing;
    final qrNotice = controller.qrNotice;
    final failure = controller.lastFailure;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(l10n.scanScreenIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
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
              if (controller.qrAvailable)
                OutlinedButton.icon(
                  onPressed: canScanQr ? () => unawaited(_scanQr()) : null,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(l10n.scanQrAction),
                ),
            ],
          ),
          if (qrNotice != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(switch (qrNotice) {
                QrUnsupportedSource(:final name) =>
                  l10n.scanQrUnsupportedSource(name),
                QrVenue() ||
                QrPhotographInstead() => l10n.scanQrPhotographInstead,
              }, style: theme.textTheme.bodyMedium),
            ),
          ],
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
            Text(
              l10n.scanScreenPagesHeading,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.scanScreenPageCount(pages.length, maxScanPages),
              style: theme.textTheme.bodySmall,
            ),
            if (controller.atPageCap)
              Text(l10n.scanScreenCapReached, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            for (var i = 0; i < pages.length; i++)
              _PageRow(
                page: pages[i],
                number: i + 1,
                onRemove: controller.analysing ? null : () => _remove(i),
              ),
          ],
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
              onPressed: () => Navigator.pushNamed(context, '/settings'),
              child: Text(l10n.scanScreenSettingsLink),
            ),
          ),
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
            child: ElevatedButton(
              onPressed: controller.canAnalysePages
                  ? () => unawaited(_analysePages())
                  : null,
              child: Text(l10n.scanScreenAnalysePages),
            ),
          ),
          const SizedBox(height: 28),
          Text(l10n.scanScreenPasteHeading, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
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
              border: const OutlineInputBorder(),
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
            child: ElevatedButton(
              onPressed: controller.canAnalyse
                  ? () => unawaited(_analysePaste())
                  : null,
              child: Text(l10n.scanAnalyse),
            ),
          ),
        ],
      ),
    );
  }
}

/// One collected page: a thumbnail (a PDF icon for a document), its label
/// and size, and a button that removes it. [onRemove] is null while an
/// analysis is reading the pages.
class _PageRow extends StatelessWidget {
  const new({required this.page, required this.number, required this.onRemove});

  final ScannedPage page;
  final int number;
  final VoidCallback? onRemove;

  static const double _thumb = 56;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final kb = (page.bytes.length / 1024).ceil();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox.square(
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
