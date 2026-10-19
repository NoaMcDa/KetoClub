import 'package:flutter/material.dart';
import 'package:ketoclub/screens/paywall_screen.dart';
import 'package:ketoclub/state/premium_controller.dart';
import 'package:ketoclub/utils/premium_gates.dart';
import 'package:provider/provider.dart';

/// Answers whether the action behind [feature] may go ahead, opening the
/// paywall first when the free plan locks it (Banto, ALG-18, issue #360).
///
/// [locks] is the gate's decision ([PremiumGates]) for the app's current
/// [PremiumAccess]. With no [PremiumController] above [context] (a screen
/// pumped on its own in a test), with nothing sold (a KetoClub build, the
/// web build) or when [locks] says no, it answers true at once. Otherwise
/// it reads the store once for the session, decides again with the fresh
/// answer, and when still locked pushes the [PaywallScreen]: true once
/// Premium is active, false when the person leaves without it. A gate
/// therefore never fails silently: it either goes ahead or shows why not.
///
/// Called only where something is *added* — a restriction, a person, a
/// checked person, a destination, a scan — never on a surface that reads
/// what is already saved (`premium_gate_usage_test` pins the callers).
Future<bool> passPremiumGate(
  BuildContext context,
  PremiumFeature feature, {
  required bool Function(PremiumAccess access) locks,
  int scansThisMonth = freeScansPerMonth,
}) async {
  final premium = Provider.of<PremiumController?>(context, listen: false);
  if (premium == null || !premium.sellsPremium || !locks(premium.access)) {
    return true;
  }
  await premium.ensureChecked();
  if (!locks(premium.access)) return true;
  if (!context.mounted) return false;
  await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) =>
          PaywallScreen(reason: feature, scansThisMonth: scansThisMonth),
    ),
  );
  return !locks(premium.access);
}
