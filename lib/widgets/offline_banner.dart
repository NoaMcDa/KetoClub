import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/services/platform/connectivity.dart';

/// A persistent banner shown while the device appears to have no route to
/// the network (issue #68), on the venue search screen and the menu
/// screen alike.
///
/// [Connectivity.isOnline] is a one-shot check, not a stream (its own doc
/// comment) — this widget never subscribes to anything. It asks
/// [connectivity] itself once, when it is first built, and again whenever
/// [recheckToken] differs from what it was on the previous build. A screen
/// with a retry action bumps that token on every retry, so this banner's
/// answer is never staler than the screen's own last attempt; a screen
/// with nothing to retry (`VenueSearchScreen`) passes the same constant
/// every time, which is exactly a check on screen open and never again.
///
/// [Connectivity] is a hint, never a verdict (its own doc comment): this
/// banner shows or hides itself purely on the last answer it was given,
/// and never claims more than that answer means.
class OfflineBanner extends StatefulWidget {
  /// Creates a banner over [connectivity], re-checked whenever
  /// [recheckToken] changes from its previous value.
  const new({required this.connectivity, this.recheckToken = 0, super.key});

  /// The connectivity check this banner asks.
  final Connectivity connectivity;

  /// Bump this to any different value to make the banner ask
  /// [connectivity] again — e.g. once per retry action on the screen
  /// above it.
  final Object recheckToken;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  @override
  void didUpdateWidget(OfflineBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recheckToken != widget.recheckToken) {
      unawaited(_check());
    }
  }

  /// Re-asks [OfflineBanner.connectivity] and updates [_isOffline] with
  /// its answer. Never throws — [Connectivity.isOnline] itself never does
  /// — and does nothing if this widget was disposed while the check was
  /// in flight.
  Future<void> _check() async {
    final online = await widget.connectivity.isOnline();
    if (!mounted) return;
    setState(() => _isOffline = !online);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isOffline) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.wifi_off,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.offlineBannerMessage,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
