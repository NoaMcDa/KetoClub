import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/utils/banto_mode.dart';
import 'package:ketoclub/widgets/content_width.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';
import 'package:provider/provider.dart';

/// The key of the "Continue" button, so a test can tap it by identity.
const Key restrictionOnboardingContinueKey = ValueKey<String>(
  'restrictionOnboardingContinue',
);

/// The key of the "Skip" button.
const Key restrictionOnboardingSkipKey = ValueKey<String>(
  'restrictionOnboardingSkip',
);

/// The key of the chip for [id].
Key restrictionOnboardingChipKey(RestrictionId id) =>
    ValueKey<String>('restrictionOnboardingChip_${id.name}');

/// Wraps [child] (the Explore tab) with the first-run restriction
/// onboarding (Banto, ALG-02b, issue #344).
///
/// With [bantoMode] off it returns [child] untouched, at once and with no
/// storage read, so the KetoClub build has no routing change and no extra
/// frame. With it on, it reads the settings once: a user who has not seen
/// the onboarding and has an empty profile gets
/// [RestrictionOnboardingScreen]; everyone else gets [child]. A profile that
/// is already non-empty counts as seen, so a user who added restrictions in
/// Settings first is never asked again.
class RestrictionOnboardingGate extends StatefulWidget {
  /// Creates the gate over [child].
  ///
  /// [createController] is invoked at most once, and only when [bantoMode]
  /// is on; the gate owns and disposes what it returns.
  const new({
    required this.createController,
    required this.child,
    this.bantoMode = BantoMode.enabled,
    super.key,
  });

  /// Builds the controller the onboarding reads and writes the profile
  /// through.
  final SettingsController Function() createController;

  /// What the user sees when there is nothing to ask.
  final Widget child;

  /// Whether Banto surfaces are on; see [BantoMode].
  final bool bantoMode;

  @override
  State<RestrictionOnboardingGate> createState() =>
      _RestrictionOnboardingGateState();
}

/// Where the gate is in reading the settings.
enum _GatePhase { loading, onboarding, done }

class _RestrictionOnboardingGateState extends State<RestrictionOnboardingGate> {
  SettingsController? _controller;
  _GatePhase _phase = _GatePhase.loading;

  @override
  void initState() {
    super.initState();
    if (!widget.bantoMode) {
      _phase = _GatePhase.done;
      return;
    }
    unawaited(_decide(_controller = widget.createController()));
  }

  Future<void> _decide(SettingsController controller) async {
    await controller.load();
    if (!mounted) return;
    setState(() {
      _phase = !controller.onboardingSeen && controller.profile.isEmpty
          ? _GatePhase.onboarding
          : _GatePhase.done;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!widget.bantoMode || controller == null) return widget.child;
    return switch (_phase) {
      _GatePhase.loading => const Scaffold(body: SizedBox.shrink()),
      _GatePhase.done => widget.child,
      _GatePhase.onboarding => ChangeNotifierProvider<SettingsController>.value(
        value: controller,
        child: RestrictionOnboardingScreen(
          onFinished: () {
            if (mounted) setState(() => _phase = _GatePhase.done);
          },
        ),
      ),
    };
  }
}

/// The first-run "What do you avoid?" screen (Banto, ALG-02b, issue #344):
/// the taxonomy as chips grouped by kind, the helper-tool sentence, and
/// "Continue" and "Skip".
///
/// There is no severity question: whether a restriction is strict comes
/// from its kind. Both buttons mark the onboarding seen; "Continue" first
/// adds what was chosen, in the order it was chosen, and "Skip" adds
/// nothing, which is a keto-only profile. Reads a [SettingsController] from
/// the nearest [Provider].
class RestrictionOnboardingScreen extends StatefulWidget {
  /// Creates the screen; [onFinished] is called once either button has
  /// been saved.
  const new({required this.onFinished, super.key});

  /// Called after the choice (or the skip) is saved.
  final VoidCallback onFinished;

  @override
  State<RestrictionOnboardingScreen> createState() =>
      _RestrictionOnboardingScreenState();
}

class _RestrictionOnboardingScreenState
    extends State<RestrictionOnboardingScreen> {
  /// The chosen restrictions, in the order they were tapped.
  final List<RestrictionId> _chosen = <RestrictionId>[];
  bool _saving = false;

  void _toggle(RestrictionId id, bool selected) {
    setState(() {
      if (selected) {
        if (!_chosen.contains(id)) _chosen.add(id);
      } else {
        _chosen.remove(id);
      }
    });
  }

  Future<void> _finish({required bool keepChoices}) async {
    if (_saving) return;
    setState(() => _saving = true);
    final controller = context.read<SettingsController>();
    if (keepChoices) {
      for (final id in _chosen) {
        await controller.addRestriction(id);
      }
    }
    await controller.markOnboardingSeen();
    if (mounted) widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final all = availableRestrictions(const <RestrictionId>{});
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          // A plain Column in a scroll view, not a lazy ListView: about
          // twenty chips, and every one must exist in the tree. The two
          // buttons are pinned below it so they are never scrolled away.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          l10n.restrictionOnboardingTitle,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.restrictionOnboardingBody,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.helperToolSentence,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      for (final kind in restrictionKindOrder)
                        ..._group(l10n, theme, locale, kind, all),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      key: restrictionOnboardingContinueKey,
                      onPressed: _saving
                          ? null
                          : () => unawaited(_finish(keepChoices: true)),
                      child: Text(l10n.restrictionOnboardingContinue),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      key: restrictionOnboardingSkipKey,
                      onPressed: _saving
                          ? null
                          : () => unawaited(_finish(keepChoices: false)),
                      child: Text(l10n.restrictionOnboardingSkip),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The heading and chips of [kind]; nothing when the taxonomy has none.
  List<Widget> _group(
    AppLocalizations l10n,
    ThemeData theme,
    Locale locale,
    RestrictionKind kind,
    List<Restriction> all,
  ) {
    final members = [
      for (final restriction in all)
        if (restriction.kind == kind) restriction,
    ];
    if (members.isEmpty) return const <Widget>[];
    return [
      Padding(
        padding: const EdgeInsetsDirectional.only(top: 20, bottom: 8),
        child: Semantics(
          header: true,
          child: Text(
            restrictionKindLabel(l10n, kind),
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 12,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final restriction in members)
            FilterChip(
              key: restrictionOnboardingChipKey(restriction.id),
              label: Text(restrictionDisplayName(restriction, locale)),
              selected: _chosen.contains(restriction.id),
              onSelected: _saving
                  ? null
                  : (selected) => _toggle(restriction.id, selected),
            ),
        ],
      ),
    ];
  }
}
