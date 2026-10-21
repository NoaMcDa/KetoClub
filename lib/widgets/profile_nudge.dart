import 'dart:async';

import 'package:flutter/material.dart' hide MenuController;
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/state/profile_nudge_actions.dart' as actions;
import 'package:ketoclub/widgets/app_notice.dart';
import 'package:ketoclub/widgets/helper_tool_sheet.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';

/// The key of the notice on [surface], so a test can find it by identity.
Key profileNudgeKey(ProfileNudgeSurface surface) =>
    ValueKey<String>('profileNudge_${surface.name}');

/// The empty-profile notice (Banto, issue #421): one dismissible
/// [AppNotice.info] saying "Tell Banto what you avoid to see which dishes
/// fit you", with an action that opens the restriction picker and one that
/// dismisses it.
///
/// Only the look: whether it shows, and what the two actions do, belong to
/// [MenuProfileNudge] and [DiscoveryProfileNudge]. It names no verdict and
/// never calls a dish safe.
class ProfileNudge extends StatelessWidget {
  /// Creates the notice of [surface].
  const new({
    required this.surface,
    required this.onChoose,
    required this.onDismiss,
    super.key,
  });

  /// The screen the notice sits on; keys the notice for tests.
  final ProfileNudgeSurface surface;

  /// Called by the "Add what you avoid" action.
  final VoidCallback onChoose;

  /// Called by the "Not now" action.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      key: profileNudgeKey(surface),
      padding: const EdgeInsets.only(bottom: 12),
      child: AppNotice.info(
        icon: Icons.tune,
        message: l10n.profileNudgeMessage,
        actions: [
          AppNoticeAction(label: l10n.profileNudgeChoose, onPressed: onChoose),
          AppNoticeAction(
            label: l10n.profileNudgeDismiss,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// Opens the restriction picker over [profile], hands what the user picks
/// to [add] and, when [add] says the helper-tool sheet is due, shows it.
///
/// There is no paywall step: the notice shows only while the profile holds
/// nothing but keto, and the free plan's first restriction is never gated.
/// Dismissing the picker changes nothing.
///
/// The sheet is shown from the navigator's context, not [context]: adding
/// the first restriction removes the notice that [context] belongs to.
Future<void> _chooseFor(
  BuildContext context, {
  required DietaryProfile profile,
  required Future<bool> Function({RestrictionId? id, String? term}) add,
  required bool bantoMode,
}) async {
  final navigator = Navigator.of(context);
  final picked = await showRestrictionPickerSheet(
    context: context,
    added: <RestrictionId>{
      for (final entry in profile.entries) entry.restrictionId,
    },
  );
  if (picked == null) return;
  final showHelper = await add(id: picked.id, term: picked.term);
  if (!showHelper || !navigator.mounted) return;
  await showHelperToolSheet(navigator.context, bantoMode: bantoMode);
}

/// The notice on the menu screen, above the dishes (issue #421). Draws
/// nothing unless [MenuController.showsProfileNudge]; choosing a
/// restriction adds it through the controller, which re-reads the profiles,
/// so the menu is evaluated against it and the notice goes.
class MenuProfileNudge extends StatelessWidget {
  /// Creates the notice over [controller].
  const new({required this.controller, required this.bantoMode, super.key});

  /// The open menu's controller, which holds the profile and the
  /// dismissal.
  final MenuController controller;

  /// Whether this build shows Banto surfaces; see `BantoMode`.
  final bool bantoMode;

  @override
  Widget build(BuildContext context) {
    if (!bantoMode || !controller.showsProfileNudge) {
      return const SizedBox.shrink();
    }
    return ProfileNudge(
      surface: ProfileNudgeSurface.menu,
      onChoose: () => unawaited(
        _chooseFor(
          context,
          profile: controller.profile,
          add: controller.addToProfile,
          bantoMode: bantoMode,
        ),
      ),
      onDismiss: () => unawaited(controller.dismissProfileNudge()),
    );
  }
}

/// The notice on Discovery, once above the list (issue #421). Reads
/// [store] itself, like the disclosure banner beside it, because the
/// Explore route provides no settings controller; draws nothing until that
/// read says the profiles hold nothing but keto and the notice was not
/// dismissed. [onProfileChanged] runs after a restriction is added, so the
/// cards re-read the profile.
class DiscoveryProfileNudge extends StatefulWidget {
  /// Creates the notice over [store].
  const new({
    required this.store,
    required this.bantoMode,
    required this.onProfileChanged,
    super.key,
  });

  /// Where the profile and the dismissal live.
  final SettingsStore store;

  /// Whether this build shows Banto surfaces; see `BantoMode`.
  final bool bantoMode;

  /// Called after a restriction was added from the notice.
  final VoidCallback onProfileChanged;

  @override
  State<DiscoveryProfileNudge> createState() => _DiscoveryProfileNudgeState();
}

class _DiscoveryProfileNudgeState extends State<DiscoveryProfileNudge> {
  AppSettings? _settings;

  @override
  void initState() {
    super.initState();
    if (widget.bantoMode) unawaited(_read());
  }

  Future<void> _read() async {
    final settings = await widget.store.read();
    if (mounted) setState(() => _settings = settings);
  }

  Future<void> _dismiss() async {
    await actions.dismissProfileNudge(
      widget.store,
      ProfileNudgeSurface.discovery,
    );
    await _read();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (!widget.bantoMode ||
        settings == null ||
        settings.activeHasNonKetoEntry ||
        settings.discoveryNudgeDismissed) {
      return const SizedBox.shrink();
    }
    return ProfileNudge(
      surface: ProfileNudgeSurface.discovery,
      onChoose: () => unawaited(
        _chooseFor(
          context,
          profile: settings.profile,
          add: ({id, term}) async {
            final showHelper = await actions.addToProfile(
              widget.store,
              id: id,
              term: term,
            );
            widget.onProfileChanged();
            if (mounted) await _read();
            return showHelper;
          },
          bantoMode: widget.bantoMode,
        ),
      ),
      onDismiss: () => unawaited(_dismiss()),
    );
  }
}
