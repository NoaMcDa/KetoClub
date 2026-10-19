import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/services/platform/entitlement.dart';
import 'package:ketoclub/state/premium_controller.dart';
import 'package:ketoclub/utils/premium_gates.dart';
import 'package:ketoclub/widgets/app_notice.dart';
import 'package:ketoclub/widgets/content_width.dart';
import 'package:provider/provider.dart';

/// The paywall's price line.
const Key paywallPriceKey = Key('paywallPrice');

/// The paywall's buy button.
const Key paywallBuyKey = Key('paywallBuy');

/// The paywall's restore button.
const Key paywallRestoreKey = Key('paywallRestore');

/// The paywall's line about what is never locked.
const Key paywallNeverLockedKey = Key('paywallNeverLocked');

/// The paywall's message about the last purchase or restore.
const Key paywallMessageKey = Key('paywallMessage');

/// The paywall's line naming why it opened.
const Key paywallReasonKey = Key('paywallReason');

/// The copy for [result] on the paywall, one distinct line per case.
String paywallResultText(AppLocalizations l10n, EntitlementResult result) =>
    switch (result) {
      PremiumActive() => l10n.paywallActive,
      PremiumInactive() => l10n.paywallRestoredNone,
      PurchaseCancelled() => l10n.paywallCancelled,
      PurchasePending() => l10n.paywallPending,
      EntitlementFailed(:final reason) => switch (reason) {
        EntitlementFailureReason.notSold => l10n.paywallFailedNotSold,
        EntitlementFailureReason.storeUnavailable =>
          l10n.paywallFailedStoreUnavailable,
        EntitlementFailureReason.productNotFound =>
          l10n.paywallFailedProductNotFound,
        EntitlementFailureReason.storeError => l10n.paywallFailedStoreError,
        EntitlementFailureReason.timedOut => l10n.paywallFailedTimedOut,
      },
    };

/// The line naming why a gate opened the paywall for [reason].
String paywallReasonText(
  AppLocalizations l10n,
  PremiumFeature reason, {
  int scansThisMonth = freeScansPerMonth,
}) => switch (reason) {
  PremiumFeature.restrictions => l10n.paywallReasonRestrictions,
  PremiumFeature.groupProfiles => l10n.paywallReasonGroup,
  PremiumFeature.tripMode => l10n.paywallReasonTrip,
  PremiumFeature.scans => l10n.paywallReasonScans(scansThisMonth),
};

/// The Banto Premium paywall (ALG-18, issue #360): why it opened (when a
/// gate opened it), what Premium adds, the line saying what is never
/// locked, the store's own price, Subscribe, Restore purchase and the
/// billing line.
///
/// The price shown is always the store's localized string
/// ([PremiumController.price]); while the store has not answered the line
/// says so, and no figure is ever written here. Reads the app-lifetime
/// [PremiumController] from the nearest provider.
///
/// Opened by a gate ([reason] set), it closes itself with `true` once
/// Premium is active, so the action that opened it goes ahead; opened from
/// Settings it stays and says so. It never names a dish or an allergen
/// "safe": nothing it describes is a verdict.
class PaywallScreen extends StatefulWidget {
  /// Creates the paywall, opened for [reason] or from Settings (null).
  /// [scansThisMonth] fills the scan reason's count.
  const new({this.reason, this.scansThisMonth = freeScansPerMonth, super.key});

  /// The gate that opened the paywall, or null from Settings.
  final PremiumFeature? reason;

  /// The scans read this month, for the scan reason's wording.
  final int scansThisMonth;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame, so building the screen starts no store call.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final premium = context.read<PremiumController>()..clearResult();
      unawaited(premium.loadPrice());
      unawaited(premium.ensureChecked());
    });
  }

  Future<void> _run(Future<EntitlementResult> Function() call) async {
    final result = await call();
    if (!mounted) return;
    if (result is PremiumActive && widget.reason != null) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final premium = context.watch<PremiumController>();
    final price = premium.price;
    final result = premium.lastResult;
    final reason = widget.reason;
    final busy = premium.busy;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.premiumTitle)),
      body: ContentWidth(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (reason != null) ...[
                Text(
                  paywallReasonText(
                    l10n,
                    reason,
                    scansThisMonth: widget.scansThisMonth,
                  ),
                  key: paywallReasonKey,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
              ],
              Text(l10n.paywallIntro, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 20),
              Semantics(
                header: true,
                child: Text(
                  l10n.paywallFeaturesHeading,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 4),
              for (final feature in <String>[
                l10n.paywallFeatureRestrictions,
                l10n.paywallFeatureGroup,
                l10n.paywallFeatureTrip,
                l10n.paywallFeatureScans,
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check),
                  title: Text(feature),
                ),
              const SizedBox(height: 8),
              AppNotice.info(
                key: paywallNeverLockedKey,
                icon: Icons.lock_open_outlined,
                message: l10n.paywallNeverLocked,
              ),
              const SizedBox(height: 24),
              Text(
                price == null
                    ? l10n.paywallPriceUnknown
                    : l10n.paywallPrice(price),
                key: paywallPriceKey,
                style: price == null
                    ? theme.textTheme.bodyMedium
                    : theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: paywallBuyKey,
                onPressed: busy || premium.isPremium
                    ? null
                    : () => unawaited(_run(premium.purchase)),
                child: Text(l10n.paywallBuy),
              ),
              const SizedBox(height: 4),
              TextButton(
                key: paywallRestoreKey,
                onPressed: busy ? null : () => unawaited(_run(premium.restore)),
                child: Text(l10n.paywallRestore),
              ),
              const SizedBox(height: 8),
              Text(l10n.paywallTerms, style: theme.textTheme.bodySmall),
              if (busy) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ] else if (result != null) ...[
                const SizedBox(height: 16),
                Text(
                  paywallResultText(l10n, result),
                  key: paywallMessageKey,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
