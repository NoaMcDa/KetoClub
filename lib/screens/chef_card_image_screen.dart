import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/utils/allergens/chef_card_locales.dart';
import 'package:ketoclub/utils/allergens/group_chef_card.dart';
import 'package:ketoclub/widgets/chef_card_image.dart';

/// The boundary the image is rendered from, public so a test can find it.
const Key chefCardImageBoundaryKey = Key('chefCardImageBoundary');

/// The page's Share button.
const Key chefCardImageShareKey = Key('chefCardImageShare');

/// The longest side, in pixels, the shared image may have: a long card is
/// rendered at a lower pixel ratio rather than as a huge file.
const double _maxImageSide = 6000;

/// The chef card as an image, before it is shared (Banto, issue #420).
///
/// Shows exactly what will be sent — [ChefCardImage], the card in its own
/// language and the light theme, with the helper-not-a-guarantee footer —
/// inside a [RepaintBoundary]; Share renders that boundary to a PNG and
/// hands it to [menuSharer] as a file. Where the platform cannot share
/// files, the sharer shares [text] instead and a snackbar says so. The
/// image lives in memory only: nothing is written to the device and
/// nothing is uploaded.
class ChefCardImageScreen extends StatefulWidget {
  /// Creates the page for a one-person card of [lines], or for [group].
  const new({
    required this.lines,
    required this.language,
    required this.text,
    required this.menuSharer,
    this.group,
    super.key,
  });

  /// The one-person card's lines; unused with a [group].
  final List<String> lines;

  /// The group card, or null.
  final GroupChefCard? group;

  /// The card's language.
  final ChefCardLanguage language;

  /// The card as text, shared when the platform cannot share the image.
  final String text;

  /// Shares the image.
  final MenuSharer menuSharer;

  @override
  State<ChefCardImageScreen> createState() => _ChefCardImageScreenState();
}

class _ChefCardImageScreenState extends State<ChefCardImageScreen> {
  final GlobalKey _boundary = GlobalKey();
  bool _busy = false;

  /// The boundary rendered to PNG bytes, or null when it cannot be.
  Future<Uint8List?> _capture() async {
    final boundary = _boundary.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    final size = boundary.size;
    final longest = math.max(size.width, size.height);
    if (longest <= 0) return null;
    final ratio = math.min(
      MediaQuery.devicePixelRatioOf(context).clamp(2.0, 3.0),
      _maxImageSide / longest,
    );
    try {
      final image = await boundary.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data?.buffer.asUint8List();
    } on Exception {
      return null;
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), showCloseIcon: true));
  }

  Future<void> _share() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    final png = await _capture();
    if (!mounted) return;
    if (png == null) {
      _say(l10n.chefCardImageFailed);
    } else {
      await widget.menuSharer.shareImage(
        png,
        subject: l10n.chefCardTitle,
        fallbackText: widget.text,
        onTextFallback: () => _say(l10n.chefCardImageTextFallback),
      );
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.chefCardImageTitle)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.chefCardImageExplain,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: RepaintBoundary(
                          key: _boundary,
                          child: ChefCardImage(
                            key: chefCardImageBoundaryKey,
                            lines: widget.lines,
                            group: widget.group,
                            language: widget.language,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 16),
              child: FilledButton.icon(
                key: chefCardImageShareKey,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: _busy ? null : () => unawaited(_share()),
                icon: const Icon(Icons.ios_share),
                label: Text(l10n.chefCardImageShareButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
