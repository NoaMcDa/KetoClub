import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/services/storage/settings_store.dart';

/// The first-launch AI-analysis disclosure banner (D16, issue #167),
/// shown on Explore only while the [SettingsStore]'s
/// [AppSettings.disclosureSeen] is false. Two buttons: "OK"
/// acknowledges without changing consent; "Turn off" also sets consent
/// to false. Either button persists `disclosureSeen: true`, so the
/// banner never appears twice on the same install.
///
/// Shape borrowed from `OfflineBanner`: a rounded box in
/// `surfaceContainerHighest` with an outline, taking the width of its
/// parent, so it slots into Explore's [Column] without extra
/// scaffolding.
///
/// Takes a [SettingsStore] rather than reading a `SettingsController`
/// from `provider`: the Explore route builds no `SettingsController`
/// of its own — that provider lives only under `/settings` — so a
/// controller-based banner would blow up the whole route. Reads the
/// store on init and after every write, so the banner reflects the
/// stored value whether it was written from Settings, from this widget,
/// or on a previous launch.
class ConsentDisclosureBanner extends StatefulWidget {
  /// Creates a banner over [settingsStore].
  const new({required this.settingsStore, super.key});

  /// The persistent settings this banner reads and writes.
  final SettingsStore settingsStore;

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

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null || settings.disclosureSeen) {
      return const SizedBox.shrink();
    }
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.settingsConsentTitle,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                l10n.settingsConsentBody,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: _busy ? null : () => unawaited(_acknowledge()),
                    child: Text(l10n.consentDisclosureOk),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => unawaited(_turnOff()),
                    child: Text(l10n.consentDisclosureTurnOff),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
