import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/utils/banto_mode.dart';
import 'package:ketoclub/widgets/app_notice.dart';

/// The version of the Banto build's disclosure copy (ALG-11, issue #353):
/// the keto text plus what of the restriction profile leaves the device.
/// A Banto build shows the banner once more to anyone whose
/// [AppSettings.disclosureCopyVersion] is below it, so a user who
/// acknowledged the keto text reads the new one once. Raise it whenever
/// the Banto disclosure copy changes in substance.
const int bantoDisclosureCopyVersion = 1;

/// The first-launch AI-analysis disclosure banner (D16, issue #167),
/// shown on Explore only while the [SettingsStore]'s
/// [AppSettings.disclosureSeen] is false. Two buttons: "OK"
/// acknowledges without changing consent; "Turn off" also sets consent
/// to false. Either button persists `disclosureSeen: true`, so the
/// banner never appears twice on the same install.
///
/// Drawn as an [AppNotice.decision] (issue #260): the one banner in the
/// app that asks for an answer, so it alone is a surface card with a
/// primary button. It takes the width of its parent, so it slots into
/// Explore's [Column] without extra scaffolding.
///
/// Takes a [SettingsStore] rather than reading a `SettingsController`
/// from `provider`: the Explore route builds no `SettingsController`
/// of its own — that provider lives only under `/settings` — so a
/// controller-based banner would blow up the whole route. Reads the
/// store on init and after every write, so the banner reflects the
/// stored value whether it was written from Settings, from this widget,
/// or on a previous launch.
///
/// [directToGoogle] picks the disclosure text: on iOS and Android dish
/// text goes straight to Google with the user's own key (D17), on web
/// through KetoClub's server (D12) — the same choice the Settings
/// consent section makes from `SettingsController.supportsApiKey`.
///
/// With [bantoMode] on (ALG-11) the text adds what of the restriction
/// profile leaves the device (nothing but the request for ingredients,
/// D26 C1), and the banner shows while
/// [AppSettings.disclosureCopyVersion] is below
/// [bantoDisclosureCopyVersion] even when the keto text was seen; either
/// button records that version. With it off the banner is exactly the keto
/// one and never writes the version. While the user shares what the staff
/// told them ([AppSettings.shareConfirmations], issue #409) the Banto text
/// names that too.
class ConsentDisclosureBanner extends StatefulWidget {
  /// Creates a banner over [settingsStore].
  const new({
    required this.settingsStore,
    this.directToGoogle = false,
    this.backendConfigured = false,
    this.bantoMode = BantoMode.enabled,
    super.key,
  });

  /// The persistent settings this banner reads and writes.
  final SettingsStore settingsStore;

  /// Whether dish text goes straight from this device to Google (iOS and
  /// Android, D17) rather than through KetoClub's server (web, D12).
  final bool directToGoogle;

  /// Whether this build has a KetoClub backend (issue #330). On a phone it
  /// makes the text say dish text goes to the server first and the user's
  /// own key is only the fallback.
  final bool backendConfigured;

  /// Whether this build shows Banto surfaces (D26's convention).
  final bool bantoMode;

  @override
  State<ConsentDisclosureBanner> createState() =>
      _ConsentDisclosureBannerState();
}

class _ConsentDisclosureBannerState extends State<ConsentDisclosureBanner> {
  /// The most recently read snapshot. Null until [_load] settles: while
  /// it is null the banner renders nothing, matching a store whose
  /// disclosure was already seen — never a flash of "not yet seen" on
  /// screens that already saw it.
  AppSettings? _settings;

  /// Whether a write is in flight, so both buttons disable until it
  /// settles and one tap can never race another.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final settings = await widget.settingsStore.read();
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  Future<void> _acknowledge() =>
      _persist((current) => _seen(current.copyWith(disclosureSeen: true)));

  Future<void> _turnOff() => _persist(
    (current) => _seen(
      current.copyWith(estimationConsentGiven: false, disclosureSeen: true),
    ),
  );

  /// [settings] with the Banto copy version recorded, in a Banto build.
  AppSettings _seen(AppSettings settings) => widget.bantoMode
      ? settings.copyWith(disclosureCopyVersion: bantoDisclosureCopyVersion)
      : settings;

  /// Whether [settings] still owes the user a read of this build's text.
  bool _unseen(AppSettings settings) =>
      !settings.disclosureSeen ||
      (widget.bantoMode &&
          settings.disclosureCopyVersion < bantoDisclosureCopyVersion);

  Future<void> _persist(AppSettings Function(AppSettings) mutation) async {
    final current = _settings;
    if (current == null || _busy) return;
    setState(() => _busy = true);
    final next = mutation(current);
    await widget.settingsStore.write(next);
    if (!mounted) return;
    setState(() {
      _settings = next;
      _busy = false;
    });
  }

  String _message(AppLocalizations l10n) {
    final keto = !widget.directToGoogle
        ? l10n.settingsConsentBody
        : widget.backendConfigured
        ? l10n.settingsConsentBodyDirectViaBackend
        : l10n.settingsConsentBodyDirect;
    if (!widget.bantoMode) return keto;
    final banto = '$keto\n\n${l10n.whatLeavesDeviceBanto}';
    // Named while the user shares post-meal answers (issue #409).
    return _settings?.shareConfirmations ?? false
        ? '$banto\n\n${l10n.whatLeavesDeviceSharedConfirmations}'
        : banto;
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null || !_unseen(settings)) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppNotice.decision(
        title: l10n.settingsConsentTitle,
        message: _message(l10n),
        primary: AppNoticeAction(
          label: l10n.consentDisclosureOk,
          onPressed: _busy ? null : () => unawaited(_acknowledge()),
        ),
        secondary: AppNoticeAction(
          label: l10n.consentDisclosureTurnOff,
          onPressed: _busy ? null : () => unawaited(_turnOff()),
        ),
      ),
    );
  }
}
