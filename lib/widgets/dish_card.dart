import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/theme/verdict_colors.dart';
import 'package:ketoclub/utils/price_format.dart';
import 'package:ketoclub/widgets/photo_tile.dart';
import 'package:ketoclub/widgets/status_badge.dart';
import 'package:ketoclub/widgets/waiter_script_widget.dart';

/// One menu row: the dish, its price, and its verdict once analysed
/// (architecture.md §6.6), styled per verdict from the artboard's
/// `verdictStyles` table (`.design/Main.dc.html` around line 178) — a
/// coloured left rail, a tinted card, and a net-carb chip that is always
/// framed as an estimate.
///
/// A [DishVerdict.modifiable] row shows a tappable amber summary that
/// expands into its waiter script, plus a button to open the full-screen
/// waiter card; a [DishVerdict.nonKeto] row shows neither; a row whose
/// [DishRow.analysis] is null shows no verdict claim and no script,
/// because none has been made yet.
class DishCard extends StatefulWidget {
  /// Creates a card for [row], formatting its price for [localeTag] and
  /// calling [onShowScript] with [row] when the user asks to open the
  /// full-screen waiter card.
  const new({
    required this.row,
    required this.localeTag,
    required this.onShowScript,
    this.note,
    this.onEditNote,
    super.key,
  });

  /// The dish, its category, and its verdict if any.
  final DishRow row;

  /// The locale used to format the dish price.
  final String localeTag;

  /// Called with [row] when the user asks to open the full waiter card
  /// for a [DishVerdict.modifiable] dish.
  final ValueChanged<DishRow> onShowScript;

  /// The user's personal note for this dish (issue #52), or null when
  /// none has been written. Shown for every verdict, not only
  /// [DishVerdict.modifiable] — a note is the user's own annotation, not
  /// part of the classifier's verdict. Local only: see `NotesStore`'s own
  /// doc comment for the privacy boundary it never crosses.
  final String? note;

  /// Called with [row] when the user taps to add or edit [note]. Null
  /// hides the note affordance entirely, so every existing call site that
  /// predates this field renders exactly as it did before.
  final ValueChanged<DishRow>? onEditNote;

  @override
  State<DishCard> createState() => _DishCardState();
}

class _DishCardState extends State<DishCard> {
  /// Whether the inline waiter-script disclosure is open.
  ///
  /// Local UI state, not part of [DishRow]: it says nothing about the
  /// dish itself, only about this card, the same way `menu_screen.dart`
  /// keeps its own red-group disclosure outside `MenuController`.
  bool _scriptExpanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final row = widget.row;
    final dish = row.dish;
    final analysis = row.analysis;
    final verdict = analysis?.verdict;
    final tone = verdict == null
        ? null
        : VerdictColors.of(context).forVerdict(verdict);
    final isModifiable = verdict == DishVerdict.modifiable;
    // AnalysedDish's own doc comment guarantees `modification` is set
    // exactly when `verdict` is modifiable, and `tryFrom` enforces that on
    // every value that came from the cache or the LLM parser — but the
    // plain const constructor does not enforce it, so this fallback keeps
    // this card's own promise (a modifiable dish always carries script
    // text) even from a value that reached it some other way.
    final scriptText = isModifiable
        ? (_nonBlank(analysis?.modification) ?? l10n.dishCardScriptFallback)
        : null;
    final netCarbs = analysis?.netCarbsEstimate;
    final neutralSurfaces = NeutralSurfaces.of(context);

    final cardEdge = _cardEdge(theme, neutralSurfaces, verdict, tone);
    // The badge/name/description/price block and the photo tile sit in one
    // row, per the artboard's dish row (`.design/Main.dc.html`); the note
    // and script-disclosure rows below stay full width, outside it.
    final textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (analysis != null) ...[
          StatusBadge(verdict: analysis.verdict),
          const SizedBox(height: 8),
        ],
        Text(dish.name, style: theme.textTheme.titleMedium),
        if (dish.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(dish.description, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              formatPrice(dish.price, localeTag: widget.localeTag),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (netCarbs != null && tone != null && verdict != null) ...[
              const SizedBox(width: 9),
              _NetCarbsChip(
                estimate: netCarbs,
                tone: tone,
                background: _carbChipBackground(theme, verdict, tone),
              ),
            ],
          ],
        ),
      ],
    );
    final content = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: textColumn),
              const SizedBox(width: 12),
              PhotoTile(imageUrl: dish.imageUrl, size: 72),
            ],
          ),
          if (widget.onEditNote != null) ...[
            const SizedBox(height: 8),
            _NoteRow(note: widget.note, onTap: () => widget.onEditNote!(row)),
          ],
          if (isModifiable && tone != null) ...[
            const SizedBox(height: 8),
            _ScriptDisclosure(
              expanded: _scriptExpanded,
              tone: tone,
              onTap: () => setState(() => _scriptExpanded = !_scriptExpanded),
            ),
            if (_scriptExpanded) ...[
              const SizedBox(height: 8),
              WaiterScriptWidget(script: scriptText!),
            ],
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => widget.onShowScript(row),
                child: Text(l10n.waiterCardOpen),
              ),
            ),
          ],
        ],
      ),
    );

    // A single [BorderDirectional] cannot mix per-side colours with a
    // [BorderRadius] (Flutter asserts a uniform border colour whenever a
    // radius is set), so the coloured rail is painted separately, as a
    // leading strip inside the same rounded clip, rather than as a wider
    // border side. `Row` places that strip on the leading edge under both
    // text directions with no directional API of its own to get wrong;
    // [IntrinsicHeight] gives that `Row` a bounded height to stretch the
    // strip into, since this card sits in a `ListView` whose items
    // otherwise offer only unbounded (infinite) height.
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _cardBackground(theme, neutralSurfaces, verdict, tone),
          border: Border.all(color: cardEdge),
        ),
        child: tone == null
            ? content
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ColoredBox(
                      key: const ValueKey('dishCardRail'),
                      color: tone.rail,
                      child: const SizedBox(width: 5),
                    ),
                    Expanded(child: content),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Returns [value] when it is neither null nor empty, else null.
String? _nonBlank(String? value) =>
    (value == null || value.isEmpty) ? null : value;

/// The card background for [verdict], per the artboard's `verdictStyles`
/// table: green uses its own tint, amber the plain surface, red a second,
/// quieter surface. [tone] is required exactly when [verdict] is not null.
///
/// `VerdictTone` has no field for amber's and red's card backgrounds, which
/// are neutral tokens shared by every verdict rather than per-verdict
/// ones — amber's is the theme's own card colour ([ThemeData.cardColor]),
/// already exposed; red's is [NeutralSurfaces.surface2], the artboard's
/// `--surface2`. Neither is a colour literal in this file.
Color _cardBackground(
  ThemeData theme,
  NeutralSurfaces neutralSurfaces,
  DishVerdict? verdict,
  VerdictTone? tone,
) => switch (verdict) {
  null => theme.cardColor,
  DishVerdict.orderAsIs => tone!.tint,
  DishVerdict.modifiable => theme.cardColor,
  DishVerdict.nonKeto => neutralSurfaces.surface2,
};

/// The card edge colour for [verdict], the border-colour counterpart of
/// [_cardBackground] — see its doc comment for where each neutral token
/// comes from. Red's is [NeutralSurfaces.line2], the artboard's `--line2`.
Color _cardEdge(
  ThemeData theme,
  NeutralSurfaces neutralSurfaces,
  DishVerdict? verdict,
  VerdictTone? tone,
) => switch (verdict) {
  null => theme.dividerColor,
  DishVerdict.orderAsIs => tone!.tint,
  DishVerdict.modifiable => theme.dividerColor,
  DishVerdict.nonKeto => neutralSurfaces.line2,
};

/// The net-carb chip background for [verdict]: the plain surface for
/// green (the artboard's `--surface`), and [tone]'s own tint for amber and
/// red (`--amber-tint` / `--red-tint`).
Color _carbChipBackground(
  ThemeData theme,
  DishVerdict verdict,
  VerdictTone tone,
) => switch (verdict) {
  DishVerdict.orderAsIs => theme.cardColor,
  DishVerdict.modifiable || DishVerdict.nonKeto => tone.tint,
};

/// The net-carb chip (architecture.md §17.4, reversed by issue #30): a
/// rough estimate, always framed as one — never rendered as a bare number
/// — and never shown at all when there is nothing to show.
class _NetCarbsChip extends StatelessWidget {
  const new({
    required this.estimate,
    required this.tone,
    required this.background,
  });

  /// The raw estimate in grams, from the LLM engine only
  /// ([AnalysedDish.netCarbsEstimate]). Rounded for display; this widget
  /// is never built when the estimate is null.
  final double estimate;

  /// This dish's verdict tone, for the chip's foreground colour.
  final VerdictTone tone;

  /// This chip's background, from [_carbChipBackground].
  final Color background;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final grams = estimate.round().toString();
    return Semantics(
      label: l10n.netCarbsChipSemanticLabel(grams),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          child: Text(
            l10n.netCarbsChipLabel(grams),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: tone.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// The tappable amber summary row that expands into the waiter script.
///
/// A [Semantics] wrapper marks it as a button and carries Flutter's own
/// `expanded` flag, so a screen reader announces the disclosure state
/// without a second, hand-written phrase for it.
class _ScriptDisclosure extends StatelessWidget {
  const new({required this.expanded, required this.tone, required this.onTap});

  /// Whether the script panel below this row is currently shown.
  final bool expanded;

  /// This dish's verdict tone; always amber, since this row only ever
  /// appears for a [DishVerdict.modifiable] dish.
  final VerdictTone tone;

  /// Called when the row is tapped, to toggle [expanded].
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final label = expanded ? l10n.dishCardHideScript : l10n.dishCardAskWaiter;
    return Semantics(
      button: true,
      expanded: expanded,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tone.tint,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: tone.rail),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.restaurant_menu, size: 16, color: tone.ink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: tone.ink,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(Icons.expand_more, size: 15, color: tone.ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The personal-note affordance (issue #52): a small tappable icon-and-text
/// row, showing the note itself once one exists or an "add a note" prompt
/// before that. Neutral for every verdict — a note is the user's own
/// annotation, not a verdict colour — so it reads from the theme's own
/// on-surface-variant colour rather than a [VerdictTone].
class _NoteRow extends StatelessWidget {
  const new({required this.note, required this.onTap});

  /// The note to show, or null/empty to show the "add a note" prompt
  /// instead.
  final String? note;

  /// Called when the row is tapped, to open the note editor.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hasNote = note != null && note!.isNotEmpty;
    final color = theme.colorScheme.onSurfaceVariant;
    final label = hasNote ? note! : l10n.dishCardAddNote;
    return Semantics(
      button: true,
      label: hasNote
          ? l10n.dishCardEditNoteSemanticLabel(note!)
          : l10n.dishCardAddNote,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                hasNote
                    ? Icons.sticky_note_2_outlined
                    : Icons.note_add_outlined,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
