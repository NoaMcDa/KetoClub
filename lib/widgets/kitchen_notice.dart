import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/utils/allergens/kitchen_reach.dart';
import 'package:ketoclub/utils/allergens/kitchen_signals.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/banto_mode.dart';
import 'package:ketoclub/widgets/app_notice.dart';
import 'package:ketoclub/widgets/content_direction.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';

/// The key of the kitchen notice, when it shows.
const Key kitchenNoticeKey = ValueKey<String>('kitchenNotice');

/// The key of the expanded notice's row for [kind].
Key kitchenNoticeRowKey(KitchenSignalKind kind) =>
    ValueKey<String>('kitchenNoticeRow_${kind.name}');

/// The key of the copy button of [kind]'s question.
Key kitchenNoticeCopyKey(KitchenSignalKind kind) =>
    ValueKey<String>('kitchenNoticeCopy_${kind.name}');

/// [kind] as a noun inside a sentence of the UI language: "a fryer".
String kitchenKindNoun(AppLocalizations l10n, KitchenSignalKind kind) =>
    switch (kind) {
      KitchenSignalKind.fryer => l10n.kitchenKindFryer,
      KitchenSignalKind.wok => l10n.kitchenKindWok,
      KitchenSignalKind.sharedGrill => l10n.kitchenKindSharedGrill,
      KitchenSignalKind.bakery => l10n.kitchenKindBakery,
      KitchenSignalKind.nuts => l10n.kitchenKindNuts,
      KitchenSignalKind.sesame => l10n.kitchenKindSesame,
    };

/// [kind] as a heading of the UI language: "Fryer".
String kitchenKindTitle(AppLocalizations l10n, KitchenSignalKind kind) =>
    switch (kind) {
      KitchenSignalKind.fryer => l10n.kitchenTitleFryer,
      KitchenSignalKind.wok => l10n.kitchenTitleWok,
      KitchenSignalKind.sharedGrill => l10n.kitchenTitleSharedGrill,
      KitchenSignalKind.bakery => l10n.kitchenTitleBakery,
      KitchenSignalKind.nuts => l10n.kitchenTitleNuts,
      KitchenSignalKind.sesame => l10n.kitchenTitleSesame,
    };

/// The kitchen signal kind a [ConcernSource.kitchen] concern names
/// (`applyKitchenSignals` writes the kind's name as its matched text), or
/// null for any other concern or a name no kind has.
KitchenSignalKind? kitchenKindOf(Concern concern) {
  if (concern.source != ConcernSource.kitchen) return null;
  final text = concern.matchedText;
  return text == null ? null : KitchenSignalKind.values.asNameMap()[text];
}

/// [items] as one phrase of the UI language: "a, b and c" ("א, ב וג").
String kitchenJoin(AppLocalizations l10n, List<String> items) {
  if (items.length <= 1) return items.join();
  final rest = items
      .sublist(0, items.length - 1)
      .join(l10n.kitchenListSeparator);
  return l10n.kitchenListAnd(rest, items.last);
}

/// The menu screen's kitchen notice (Banto; ALG-07, issue #349;
/// architecture.md D26): what the menu reveals about its kitchen, shown
/// only when a signal threatens a strict entry of [profile]
/// ([KitchenReach.strictThreats]).
///
/// Collapsed, it is one [AppNotice.info] line, "This kitchen has a fryer
/// and a bakery — ask about cross-contact", with a "Show questions"
/// action. Expanded, one row per such signal follows: its name, the
/// profile's strict restrictions it matters for (in the UI language),
/// the dishes that show it (as printed), and its staff question in the
/// menu's language (§12; the question is `KitchenSignals` Dart text) with
/// a copy button.
///
/// A signal that threatens only flexible entries is not shown, not even
/// collapsed: cross-contact is a trace, which an intolerance or a diet
/// does not turn on, and every threat today is an allergen or celiac
/// disease anyway. Nothing here says a dish or a menu is safe.
///
/// Builds nothing with [bantoMode] off, for a keto-only profile, or when
/// no signal threatens a strict entry. Adds 12 px under itself when it
/// shows, as the menu's other notices do.
class KitchenNotice extends StatefulWidget {
  /// Creates the notice for [kitchen] and [profile].
  const new({
    required this.kitchen,
    required this.profile,
    this.bantoMode = BantoMode.enabled,
    super.key,
  });

  /// The menu's kitchen signals and their reach.
  final KitchenReach kitchen;

  /// The user's profile; only its strict entries count.
  final DietaryProfile profile;

  /// Whether this build shows Banto surfaces.
  final bool bantoMode;

  @override
  State<KitchenNotice> createState() => _KitchenNoticeState();
}

class _KitchenNoticeState extends State<KitchenNotice> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.bantoMode) return const SizedBox.shrink();
    final threats = widget.kitchen.strictThreats(widget.profile);
    if (threats.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final summary = l10n.kitchenNoticeSummary(
      kitchenJoin(l10n, <String>[
        for (final threat in threats) kitchenKindNoun(l10n, threat.signal.kind),
      ]),
    );
    return Padding(
      key: kitchenNoticeKey,
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppNotice.info(
            message: summary,
            icon: Icons.soup_kitchen_outlined,
            actions: <AppNoticeAction>[
              AppNoticeAction(
                label: _expanded
                    ? l10n.kitchenNoticeHide
                    : l10n.kitchenNoticeShow,
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
            ],
          ),
          // A plain Column, not a lazy list: at most six rows, and every
          // one must exist in the tree once expanded.
          if (_expanded)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 26, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < threats.length; i++) ...[
                    if (i > 0) const Divider(height: 20),
                    _SignalRow(
                      key: kitchenNoticeRowKey(threats[i].signal.kind),
                      threat: threats[i],
                      hebrew: widget.kitchen.hebrew,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// How long a copy button reads "Copied" before it flips back.
const Duration _copiedDuration = Duration(seconds: 2);

/// One signal of the expanded notice.
class _SignalRow extends StatefulWidget {
  const new({required this.threat, required this.hebrew, super.key});

  final KitchenThreat threat;

  /// Whether the menu reads as Hebrew, the question's language.
  final bool hebrew;

  @override
  State<_SignalRow> createState() => _SignalRowState();
}

class _SignalRowState extends State<_SignalRow> {
  Timer? _resetTimer;
  bool _copied = false;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  String get _question => widget.hebrew
      ? widget.threat.signal.questionHe
      : widget.threat.signal.questionEn;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _question));
    if (!mounted) return;
    _resetTimer?.cancel();
    setState(() => _copied = true);
    _resetTimer = Timer(_copiedDuration, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final ambient = Directionality.of(context);
    final signal = widget.threat.signal;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final restrictions = kitchenJoin(l10n, <String>[
      for (final id in widget.threat.strict)
        restrictionDisplayName(restrictionFor(id), locale),
    ]);
    final question = _question;
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kitchenKindTitle(l10n, signal.kind),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(l10n.kitchenNoticeMattersFor(restrictions), style: muted),
          if (signal.evidence.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              l10n.kitchenNoticeSeenIn(
                signal.evidence.join(l10n.kitchenListSeparator),
              ),
              style: muted,
            ),
          ],
          const SizedBox(height: 8),
          Text(l10n.kitchenNoticeQuestionLabel, style: muted),
          SizedBox(
            width: double.infinity,
            child: Text(
              question,
              // Read to the staff in the menu's language, laid out in its
              // own direction (audit M8).
              textDirection: contentDirection(question, ambient),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Semantics(
              button: true,
              label: l10n.kitchenNoticeCopyLabel(
                kitchenKindNoun(l10n, signal.kind),
              ),
              excludeSemantics: true,
              onTap: _copy,
              child: TextButton.icon(
                key: kitchenNoticeCopyKey(signal.kind),
                onPressed: _copy,
                icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
                label: Text(_copied ? l10n.actionCopied : l10n.actionCopy),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
