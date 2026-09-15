import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/theme/verdict_colors.dart';
import 'package:ketoclub/widgets/waiter_script_widget.dart';

/// The full-screen waiter card: a tab per modifiable dish, each one's
/// script shown as numbered lines large enough and with enough contrast
/// to hand the phone across a table (architecture.md §6.3), with the
/// screen brightness raised for as long as the card is open.
///
/// The dish name and script are rendered exactly as printed, in the
/// menu's own language, matching [WaiterScriptWidget.script]'s convention
/// (architecture.md §12) — neither is translated to the UI language. A
/// row with no modification renders the dish name with no script section
/// rather than crashing, since a screen must never fail to show what it
/// already has; the same is true of the optional "safe to order" note,
/// shown only when [AnalysedDish.netCarbsEstimate] is present, per issue
/// #30's decision on estimated net carbs (architecture.md §17.4).
///
/// **Two constructors, one screen.** [WaiterCardSheet.new] takes a single
/// [DishRow], the shape `menu_screen.dart`'s dish-card affordance already
/// calls this with; it keeps compiling unchanged and defaults
/// [screenBrightness] to [NoOpScreenBrightness] since that call site has
/// no [ScreenBrightness] of its own to pass yet (issue #31's follow-up:
/// thread `AppDependencies.screenBrightness` down to it, then pass it
/// through here, for the brightness raise to actually happen from that
/// path). [WaiterCardSheet.forRows] is the shape a sticky bar offering
/// every modifiable dish needs — a list plus which one to open on —
/// and always takes its [ScreenBrightness] explicitly, since every new
/// call site can supply one from the start.
class WaiterCardSheet extends StatefulWidget {
  /// Creates a card for a single dish [row] — see this class's own doc
  /// comment for why [screenBrightness] defaults to a no-op here and not
  /// on [WaiterCardSheet.forRows].
  new({required DishRow row, ScreenBrightness? screenBrightness, Key? key})
    : this.forRows(
        rows: [row],
        screenBrightness: screenBrightness ?? const NoOpScreenBrightness(),
        key: key,
      );

  /// Creates a card over [rows] — every modifiable dish worth offering a
  /// tab for — opening on [initialIndex] (clamped into range, default the
  /// first). A pill tab per row is shown across the top whenever there is
  /// more than one.
  ///
  // This lint wants this constructor's own name written without repeating
  // the class ("WaiterCardSheet.forRows" -> just ".forRows"), but Dart's
  // constructor grammar accepts the type-name-elision shorthand only for
  // the unnamed constructor (as `new`, used above); a named constructor
  // still requires its enclosing class name (see VerdictTone.lerp in
  // verdict_colors.dart for the same finding). Suppressed rather than
  // worked around with an invalid syntax.
  // ignore: unnecessary_type_name_in_constructor
  const WaiterCardSheet.forRows({
    required this.rows,
    required this.screenBrightness,
    this.initialIndex = 0,
    super.key,
  }) : assert(rows.length > 0, 'WaiterCardSheet needs at least one row');

  /// The dishes shown as tabs, in display order. Never empty.
  final List<DishRow> rows;

  /// Which of [rows] is shown when the card first opens.
  final int initialIndex;

  /// Raised for as long as this card is on screen, restored once it
  /// closes (architecture.md §6.3). A no-op on platforms with no
  /// brightness API of their own, such as web.
  final ScreenBrightness screenBrightness;

  @override
  State<WaiterCardSheet> createState() => _WaiterCardSheetState();
}

class _WaiterCardSheetState extends State<WaiterCardSheet> {
  /// The active tab: an index into `widget.rows`, clamped so a caller
  /// passing an out-of-range [WaiterCardSheet.initialIndex] cannot crash
  /// this screen — the same "show what it already has" rule as the
  /// missing-script and missing-estimate cases this screen also handles.
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = math.max(0, math.min(widget.initialIndex, widget.rows.length - 1));
    // Fire-and-forget: raising brightness must never block or fail this
    // screen's build (ScreenBrightness's own contract never throws).
    unawaited(widget.screenBrightness.raise());
  }

  @override
  void dispose() {
    unawaited(widget.screenBrightness.restore());
    super.dispose();
  }

  void _selectTab(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final row = widget.rows[_index];
    final script = row.analysis?.modification;
    final netCarbsEstimate = row.analysis?.netCarbsEstimate;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(24, 24, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.waiterCardTitle, style: theme.textTheme.labelLarge),
            if (widget.rows.length > 1) ...[
              const SizedBox(height: 16),
              _TabRow(
                rows: widget.rows,
                activeIndex: _index,
                onSelect: _selectTab,
              ),
            ],
            const SizedBox(height: 8),
            Text(row.dish.name, style: theme.textTheme.headlineSmall),
            if (script != null) ...[
              const SizedBox(height: 24),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border.all(color: theme.colorScheme.outline),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                      height: 1.35,
                    ),
                    child: WaiterScriptWidget(script: script),
                  ),
                ),
              ),
            ],
            if (netCarbsEstimate != null) ...[
              const SizedBox(height: 16),
              _AfterText(estimate: netCarbsEstimate),
            ],
          ],
        ),
      ),
    );
  }
}

/// A pill row across the modifiable dishes; tapping one switches
/// [_WaiterCardSheetState]'s active tab.
///
/// Scrolls horizontally so a menu with many modifiable dishes never
/// overflows a phone-width screen, per this repo's responsive rule.
class _TabRow extends StatelessWidget {
  const new({
    required this.rows,
    required this.activeIndex,
    required this.onSelect,
  });

  /// The dishes to show one pill per, in display order.
  final List<DishRow> rows;

  /// Which pill is currently selected.
  final int activeIndex;

  /// Called with the tapped pill's index.
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: EdgeInsetsDirectional.only(
                end: i == rows.length - 1 ? 0 : 8,
              ),
              child: ChoiceChip(
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    rows[i].dish.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                selected: i == activeIndex,
                onSelected: (_) => onSelect(i),
              ),
            ),
        ],
      ),
    );
  }
}

/// The optional "safe to order" note below the script, from
/// [AnalysedDish.netCarbsEstimate] — present only for an LLM verdict,
/// never a rules one, and always framed as an estimate (issue #30,
/// architecture.md §17.4), matching `DishCard`'s net-carb chip wording.
class _AfterText extends StatelessWidget {
  const new({required this.estimate});

  /// The raw estimate in grams. Rounded for display.
  final double estimate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tone = VerdictColors.of(context).forVerdict(DishVerdict.orderAsIs);
    final grams = estimate.round().toString();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.tint,
        border: Border.all(color: tone.rail),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle, color: tone.ink, size: 19),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                l10n.waiterCardAfterText(grams),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tone.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
