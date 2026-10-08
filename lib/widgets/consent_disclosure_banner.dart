import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/widgets/app_notice.dart';

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
class ConsentDisclosureBanner extends StatefulWidget {
  /// Creates a banner over [settingsStore].
  const new({
    required this.settingsStore,
    this.directToGoogle = false,
    this.backendConfigured = false,
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
      _persist((current) => current.copyWith(disclosureSeen: true));

  Future<void> _turnOff() => _persist(
    (current) =>
        current.copyWith(estimationConsentGiven: false, disclosureSeen: true),
  );

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
    if (!widget.directToGoogle) return l10n.settingsConsentBody;
    return widget.backendConfigured
        ? l10n.settingsConsentBodyDirectViaBackend
        : l10n.settingsConsentBodyDirect;
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null || settings.disclosureSeen) {
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
