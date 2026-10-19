import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/screens/paywall_screen.dart';
import 'package:ketoclub/state/premium_controller.dart';
import 'package:ketoclub/utils/premium_gates.dart';
import 'package:provider/provider.dart';

/// The "Banto Premium" row, which opens the paywall.
const Key settingsPremiumRowKey = Key('settingsPremiumRow');

/// The "Restore purchase" button under it.
const Key settingsPremiumRestoreKey = Key('settingsPremiumRestore');

/// The message under the row after a restore.
const Key settingsPremiumMessageKey = Key('settingsPremiumMessage');

/// The rows of Settings' "Banto Premium" group (ALG-18, issue #360): the
/// plan's status — "Premium is active", or the free plan's limits — on a
/// row that opens the [PaywallScreen], then "Restore purchase" and what the
/// last restore came to. Settings draws the group, and only in a Banto
/// build that sells Premium (not on web). Reads the app-lifetime
/// [PremiumController].
class SettingsPremiumRows extends StatefulWidget {
  /// Creates the rows.
  const new({super.key});

  @override
  State<SettingsPremiumRows> createState() => _SettingsPremiumRowsState();
}

class _SettingsPremiumRowsState extends State<SettingsPremiumRows> {
  @override
  void initState() {
    super.initState();
    // After the first frame: building Settings starts no store call.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final premium = context.read<PremiumController>()..clearResult();
      unawaited(premium.ensureChecked());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final premium = context.watch<PremiumController>();
    final result = premium.lastResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: settingsPremiumRowKey,
          leading: Icon(
            premium.isPremium ? Icons.workspace_premium : Icons.star_outline,
          ),
          title: Text(
            premium.isPremium
                ? l10n.settingsPremiumActive
                : l10n.settingsPremiumFree(freeScansPerMonth),
          ),
          subtitle: Text(l10n.settingsPremiumOpen),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(builder: (_) => const PaywallScreen()),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: settingsPremiumRestoreKey,
              icon: const Icon(Icons.restore),
              label: Text(l10n.paywallRestore),
              onPressed: premium.busy
                  ? null
                  : () => unawaited(premium.restore()),
            ),
          ),
        ),
        if (result != null && !premium.busy)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
            child: Text(
              paywallResultText(l10n, result),
              key: settingsPremiumMessageKey,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
