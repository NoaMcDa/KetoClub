import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/theme/verdict_colors.dart';
import 'package:ketoclub/utils/allergens/declarations.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/banto_mode.dart';
import 'package:ketoclub/utils/price_format.dart';
import 'package:ketoclub/utils/profile_wording.dart';
import 'package:ketoclub/widgets/content_direction.dart';
import 'package:ketoclub/widgets/focus_ring.dart';
import 'package:ketoclub/widgets/net_carbs_chip.dart';
import 'package:ketoclub/widgets/photo_tile.dart';
import 'package:ketoclub/widgets/status_badge.dart';
import 'package:ketoclub/widgets/verdict_copy.dart';
import 'package:ketoclub/widgets/waiter_script_widget.dart';
import 'package:ketoclub/widgets/why_sheet.dart';
import 'package:provider/provider.dart';

/// One menu row: the dish, its price, and its verdict once analysed
/// (architecture.md §6.6), styled per verdict from the artboard's
/// `verdictStyles` table (`.design/Main.dc.html` around line 178) — a
/// coloured left rail, a tinted card, and a net-carb chip that is always
/// framed as an estimate.
///
/// A [DishVerdict.modifiable] row shows one tappable amber summary that
/// expands into its waiter script; the button to open the full-screen
/// waiter card lives inside that expanded panel, beside Copy, not as a
/// standing second action (issue #239). A [DishVerdict.nonKeto] row shows
/// neither; a row whose
/// [DishRow.analysis] is null shows no verdict claim and no script,
/// because none has been made yet.
///
/// **Banto (ALG-05, issue #347).** With [bantoMode] on, an [evaluated]
/// dish and a [wording] that [ProfileWording.usesStates], the card speaks
/// the dish's [DishState] instead of its keto verdict: a [StateBadge], the
/// state's colours, one line per concern under the dish (the restriction
/// named in the dish's own language, where it was found and how sure, in
/// words), a "Why?" button that opens [showWhySheet], and the one waiter
/// row carrying [VerdictCopy.waiterLine]. The net-carb chip and the
/// hidden-carb flags stay only while [holdsKeto]. A dish the platform
/// flags kosher shows "declared kosher by the platform" beside the price
/// (ALG-09). Otherwise the card is exactly as before.
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
    this.showPrice = true,
    this.unclassified = false,
    this.evaluated,
    this.wording = ProfileWording.ketoOnly,
    this.holdsKeto = true,
    this.bantoMode = BantoMode.enabled,
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

  /// Whether the dish's price is drawn. False for a pasted menu, whose
  /// prices were stripped before classification and are not real (issue
  /// #83, architecture.md D18); true everywhere else.
  final bool showPrice;

  /// Whether this is a dish the classifier could not place (issue #244):
  /// a null-analysis row then carries the neutral [UnclassifiedBadge]
  /// instead of no badge at all. False everywhere else, where a null
  /// analysis means the menu has not been analysed yet.
  final bool unclassified;

  /// The dish's on-device evaluation for the profile (Banto, ALG-05), or
  /// null for a keto-only screen.
  final EvaluatedDish? evaluated;

  /// How the profile asks for the state to be worded; keto-only renders
  /// the card exactly as before.
  final ProfileWording wording;

  /// Whether keto is in the profile, so the net-carb chip and the
  /// hidden-carb flags still apply. Read only in state mode.
  final bool holdsKeto;

  /// Whether this build shows Banto surfaces (D26's convention).
  final bool bantoMode;

  /// Whether this card renders [evaluated]'s state rather than the keto
  /// verdict.
  bool get _stateMode => bantoMode && wording.usesStates && evaluated != null;

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
    final evaluated = widget._stateMode ? widget.evaluated : null;
    final state = evaluated?.state;
    final tone = state != null
        ? VerdictColors.of(context).forState(state)
        : verdict == null
        ? null
        : VerdictColors.of(context).forVerdict(verdict);
    final isModifiable = verdict == DishVerdict.modifiable;
    // In state mode the one waiter row carries the evaluator's change or
    // the question to ask; the keto script row is not shown.
    final stateLine = evaluated == null
        ? null
        : VerdictCopy.waiterLine(evaluated, dish);
    final showKeto = evaluated == null || widget.holdsKeto;
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
    final budget = context.watch<CarbBudgetController>().budgetGrams;
    final leavesGrams = (budget != null && netCarbs != null)
        ? budget - netCarbs.round()
        : null;
    final neutralSurfaces = NeutralSurfaces.of(context);
    final ambient = Directionality.of(context);

    final cardEdge = state != null
        ? _stateCardEdge(theme, neutralSurfaces, state, tone!)
        : _cardEdge(theme, neutralSurfaces, verdict, tone);
    final hasNote =
        widget.onEditNote != null &&
        widget.note != null &&
        widget.note!.isNotEmpty;
    final showAddNote = widget.onEditNote != null && !hasNote;
    // The badge/name/description/price block and the photo tile sit in one
    // row, per the artboard's dish row (`.design/Main.dc.html`); the note
    // and script-disclosure rows below stay full width, outside it.
    final textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sizes and the 6px rhythm are the artboard's dish row
        // (`.design/Main.dc.html`): a 15px bold name, a 12.5px `--ink2`
        // description at 1.45 line height, and a 13.5px bold price.
        // The "add a note" icon sits at the corner of this header, opposite
        // the badge, only while there is no note (issue #240); once a note
        // exists the full-width note row below replaces it.
        if (state != null) ...[
          // Banto's state pill can be a sentence ("No trigger found — ask
          // the restaurant") that fills the line, which in the keto Wrap
          // below pushed the note icon onto a line of its own (ALG-05's
          // visual pass, finding B1). A Row keeps the icon at the corner
          // and lets the pill wrap its own text instead.
          Row(
            key: dishStateHeaderKey,
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: StateBadge(state: state, wording: widget.wording),
                ),
              ),
              if (showAddNote) ...[
                const SizedBox(width: 4),
                _AddNoteButton(onPressed: () => widget.onEditNote!(row)),
              ],
            ],
          ),
          const SizedBox(height: 6),
        ] else if (analysis != null || showAddNote) ...[
          // A Wrap, not a Row: at a large text scale the badge and the
          // 36px icon can outgrow one line together.
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: analysis != null
                  ? WrapAlignment.spaceBetween
                  : WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (analysis != null) StatusBadge(verdict: analysis.verdict),
                if (showAddNote)
                  _AddNoteButton(onPressed: () => widget.onEditNote!(row)),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ] else if (widget.unclassified) ...[
          const UnclassifiedBadge(),
          const SizedBox(height: 6),
        ],
        // The name and description are menu content, laid out in the
        // menu's own direction rather than the UI's (contentDirection).
        SizedBox(
          width: double.infinity,
          child: Text(
            dish.name,
            textDirection: contentDirection(dish.name, ambient),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ),
        if (dish.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: Text(
              dish.description,
              textDirection: contentDirection(dish.description, ambient),
              style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
            ),
          ),
        ],
        const SizedBox(height: 7),
        // A Wrap, not a Row: at a large text scale the price and the
        // net-carb chip can outgrow one line together (architecture.md
        // §8.3's large-text pass) — wrapping the chip to its own line
        // reads better than a RenderFlex overflow.
        Wrap(
          spacing: 9,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (widget.showPrice)
              Text(
                formatPrice(dish.price, localeTag: widget.localeTag),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (netCarbs != null && tone != null && verdict != null && showKeto)
              NetCarbsChip(
                label: _netCarbsLabel(l10n, netCarbs, leavesGrams),
                semanticLabel: l10n.netCarbsChipSemanticLabel(
                  netCarbs.round().toString(),
                ),
                tone: tone,
                background: netCarbsChipBackground(theme, verdict, tone),
              ),
            // Banto only, and only where the card speaks for a profile, so
            // a keto-only screen is unchanged (ALG-09).
            if (widget.bantoMode &&
                widget.wording.usesStates &&
                Declarations.declaresKosher(dish))
              const _DeclaredKosherChip(),
          ],
        ),
      ],
    );
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
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
          if (hasNote) ...[
            const SizedBox(height: 8),
            _NoteRow(note: widget.note!, onTap: () => widget.onEditNote!(row)),
          ],
          if (evaluated != null) ...[
            const SizedBox(height: 8),
            _ConcernsBlock(
              evaluated: evaluated,
              hebrew: VerdictCopy.dishIsHebrew(dish),
              dishName: dish.name,
              strictProfile: widget.wording == ProfileWording.strict,
              bantoMode: widget.bantoMode,
            ),
          ],
          if (evaluated != null && stateLine != null && tone != null) ...[
            const SizedBox(height: 8),
            _ScriptDisclosure(
              expanded: _scriptExpanded,
              tone: tone,
              ownNode: true,
              label: state == DishState.ask
                  ? l10n.dishCardAskQuestion
                  : l10n.dishCardAskWaiter,
              onTap: () => setState(() => _scriptExpanded = !_scriptExpanded),
            ),
            if (_scriptExpanded) ...[
              const SizedBox(height: 8),
              WaiterScriptWidget(
                script: stateLine,
                trailingAction: _FullScreenAction(
                  dishName: dish.name,
                  onPressed: () => widget.onShowScript(row),
                ),
              ),
              if (showKeto && analysis!.hiddenCarbs.isNotEmpty) ...[
                const SizedBox(height: 8),
                _HiddenCarbsRow(hiddenCarbs: analysis.hiddenCarbs, tone: tone),
              ],
            ],
          ],
          if (evaluated == null && isModifiable && tone != null) ...[
            const SizedBox(height: 8),
            _ScriptDisclosure(
              expanded: _scriptExpanded,
              tone: tone,
              onTap: () => setState(() => _scriptExpanded = !_scriptExpanded),
            ),
            if (_scriptExpanded) ...[
              const SizedBox(height: 8),
              WaiterScriptWidget(
                script: scriptText!,
                trailingAction: _FullScreenAction(
                  dishName: dish.name,
                  onPressed: () => widget.onShowScript(row),
                ),
              ),
              if (analysis!.hiddenCarbs.isNotEmpty) ...[
                const SizedBox(height: 8),
                _HiddenCarbsRow(hiddenCarbs: analysis.hiddenCarbs, tone: tone),
              ],
            ],
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
          color: state != null
              ? _stateCardBackground(theme, neutralSurfaces, state, tone!)
              : _cardBackground(theme, neutralSurfaces, verdict, tone),
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

/// The card background for a Banto [state] (ALG-05): fits takes green's
/// tint, as an order-as-is dish does; fits with a change and ask the plain
/// card colour; avoid red's quieter second surface.
Color _stateCardBackground(
  ThemeData theme,
  NeutralSurfaces neutralSurfaces,
  DishState state,
  VerdictTone tone,
) => switch (state) {
  DishState.fits => tone.tint,
  DishState.fitsWithChange || DishState.ask => theme.cardColor,
  DishState.avoid => neutralSurfaces.surface2,
};

/// The card edge for a Banto [state]: ask is outlined in its own orange,
/// the shape signal its pill carries too; the rest follow [_cardEdge].
Color _stateCardEdge(
  ThemeData theme,
  NeutralSurfaces neutralSurfaces,
  DishState state,
  VerdictTone tone,
) => switch (state) {
  DishState.fits => tone.tint,
  DishState.fitsWithChange => theme.dividerColor,
  DishState.ask => tone.rail,
  DishState.avoid => neutralSurfaces.line2,
};

/// The key of the concern line at [index] on a dish card (ALG-05).
Key dishConcernKey(int index) => ValueKey<String>('dishConcern_$index');

/// The key of a dish card's "Why?" button (ALG-05).
const Key dishWhyKey = ValueKey<String>('dishWhy');

/// The key of the row holding a Banto dish card's state pill and its
/// "add a note" icon (ALG-05).
const Key dishStateHeaderKey = ValueKey<String>('dishStateHeader');

/// The key of the "declared kosher by the platform" chip (ALG-09).
const Key dishDeclaredKosherKey = ValueKey<String>('dishDeclaredKosher');

/// The one kosher statement the app makes (Banto, ALG-09): the platform's
/// own flag, attributed to it in words, never a claim by the app.
class _DeclaredKosherChip extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return DecoratedBox(
      key: dishDeclaredKosherKey,
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Text(
          l10n.dishCardDeclaredKosher,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Where [concern] was found, in words of the UI language, with the menu
/// text it matched when that text is not already the dish's own name or
/// description: "option: bread", "hidden: soy sauce".
String concernSourceLabel(AppLocalizations l10n, Concern concern) {
  final source = switch (concern.source) {
    ConcernSource.name => l10n.concernSourceName,
    ConcernSource.description => l10n.concernSourceDescription,
    ConcernSource.option => l10n.concernSourceOption,
    ConcernSource.hidden => l10n.concernSourceHidden,
    ConcernSource.model => l10n.concernSourceModel,
  };
  final text = concern.matchedText;
  final quoted = switch (concern.source) {
    ConcernSource.name || ConcernSource.description => false,
    ConcernSource.option ||
    ConcernSource.hidden ||
    ConcernSource.model => text != null && text.trim().isNotEmpty,
  };
  return quoted ? l10n.concernSourceWithText(source, text!) : source;
}

/// How sure [certainty] is, in words, never a number (ALG-06).
String concernCertaintyLabel(AppLocalizations l10n, Certainty certainty) =>
    switch (certainty) {
      Certainty.stated => l10n.concernCertaintyStated,
      Certainty.likely => l10n.concernCertaintyLikely,
      Certainty.suspected => l10n.concernCertaintySuspected,
    };

/// The concern lines under a Banto dish (ALG-05) and the "Why?" button
/// that opens the Why sheet (ALG-06).
///
/// A plain [Column], not a lazy list: a dish has a handful of concerns.
class _ConcernsBlock extends StatelessWidget {
  const new({
    required this.evaluated,
    required this.hebrew,
    required this.dishName,
    required this.strictProfile,
    required this.bantoMode,
  });

  /// The dish's evaluation, whose [EvaluatedDish.concerns] are listed.
  final EvaluatedDish evaluated;

  /// Whether the dish's own text is Hebrew, the language the restriction
  /// names are shown in.
  final bool hebrew;

  /// The dish's name, for the Why sheet and the button's label.
  final String dishName;

  /// Whether the profile holds a strict entry, for the Why sheet.
  final bool strictProfile;

  /// Passed through to [showWhySheet].
  final bool bantoMode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final concerns = evaluated.concerns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < concerns.length; i++)
          Padding(
            key: dishConcernKey(i),
            padding: const EdgeInsets.only(bottom: 6),
            child: _ConcernLine(concern: concerns[i], hebrew: hebrew),
          ),
        // A node of its own (container): without it the button's flag and
        // tap merged into the card's node, so the web build announced the
        // whole card as one "Why?" button (ALG-05's visual pass, B2).
        Semantics(
          container: true,
          button: true,
          label: l10n.dishCardWhySemanticLabel(dishName),
          excludeSemantics: true,
          onTap: () => _openWhy(context),
          // The keyboard ring the tiles and the waiter row draw (#264):
          // a TextButton's own focus tint is faint on a tinted card
          // (ALG-05's visual pass, B5).
          child: FocusRing(
            borderRadius: BorderRadius.circular(18),
            child: TextButton.icon(
              key: dishWhyKey,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(48, 36),
              ),
              onPressed: () => _openWhy(context),
              icon: const Icon(Icons.info_outline, size: 16),
              label: Text(l10n.dishCardWhy),
            ),
          ),
        ),
      ],
    );
  }

  void _openWhy(BuildContext context) => unawaited(
    showWhySheet(
      context,
      dishName: dishName,
      concerns: evaluated.concerns,
      strictProfile: strictProfile,
      declarations: evaluated.declarations,
      bantoMode: bantoMode,
    ),
  );
}

/// One concern: a restriction chip named in the dish's language and
/// coloured by its kind (strict red, flexible amber), then where it was
/// found and how sure, in words.
class _ConcernLine extends StatelessWidget {
  const new({required this.concern, required this.hebrew});

  /// The concern this line shows.
  final Concern concern;

  /// Whether the dish's text is Hebrew, the restriction name's language.
  final bool hebrew;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = VerdictColors.of(context);
    final strict = restrictionFor(concern.restrictionId).isStrict;
    final chipTone = strict ? colors.red : colors.amber;
    final name = VerdictCopy.restrictionName(
      concern.restrictionId,
      hebrew: hebrew,
    );
    final source = concernSourceLabel(l10n, concern);
    final certainty = concernCertaintyLabel(l10n, concern.certainty);
    return Semantics(
      container: true,
      label: l10n.concernLineSemanticLabel(name, source, certainty),
      excludeSemantics: true,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: chipTone.tint,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(
                name,
                // Read beside the dish's own name, in its language.
                textDirection: hebrew ? TextDirection.rtl : TextDirection.ltr,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: chipTone.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Text(
            l10n.concernLineText(source, certainty),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The net-carb chip's visible text: "~3g net carbs (estimate)", with a
/// " · leaves 5g" suffix when a budget is active ([leavesGrams] non-null).
String _netCarbsLabel(
  AppLocalizations l10n,
  double estimate,
  int? leavesGrams,
) {
  final grams = estimate.round().toString();
  final label = l10n.netCarbsChipLabel(grams);
  return leavesGrams == null
      ? label
      : '$label${l10n.netCarbsChipLeavesSuffix(leavesGrams)}';
}

/// The tappable amber summary row that expands into the waiter script.
///
/// A [Semantics] wrapper marks it as a button and carries Flutter's own
/// `expanded` flag, so a screen reader announces the disclosure state
/// without a second, hand-written phrase for it.
class _ScriptDisclosure extends StatelessWidget {
  const new({
    required this.expanded,
    required this.tone,
    required this.onTap,
    this.label,
    this.ownNode = false,
  });

  /// Whether the script panel below this row is currently shown.
  final bool expanded;

  /// The collapsed row's text; null for the keto row's "Ask your waiter".
  /// Banto's ask state passes "What to ask the waiter" (ALG-05).
  final String? label;

  /// This dish's tone: amber for a [DishVerdict.modifiable] dish, and in
  /// Banto's state mode amber or the "ask" orange.
  final VerdictTone tone;

  /// Called when the row is tapped, to toggle [expanded].
  final VoidCallback onTap;

  /// Whether the row is a semantics node of its own. Banto's state row
  /// passes true (ALG-05's visual pass, B2), so the card is not announced
  /// as one button; the keto row keeps today's tree.
  final bool ownNode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final label = expanded
        ? l10n.dishCardHideScript
        : (this.label ?? l10n.dishCardAskWaiter);
    return Semantics(
      container: ownNode,
      button: true,
      expanded: expanded,
      label: label,
      // excludeSemantics drops the InkWell's own tap action, so the
      // action is declared here too; without it a screen reader could
      // focus the row but never activate it.
      onTap: onTap,
      excludeSemantics: true,
      child: FocusRing(
        borderRadius: BorderRadius.circular(11),
        color: tone.rail,
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
      ),
    );
  }
}

/// The "Full screen" action shown beside Copy inside the expanded waiter
/// script (issue #239): opens the full-screen waiter card for the dish.
///
/// Announced with the dish name, so a screen reader user hears which
/// dish's card it opens rather than a bare "Full screen".
class _FullScreenAction extends StatelessWidget {
  const new({required this.dishName, required this.onPressed});

  /// The dish's name, spoken as part of the semantic label.
  final String dishName;

  /// Called when the action is activated.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      button: true,
      label: l10n.dishCardFullScreenSemanticLabel(dishName),
      onTap: onPressed,
      excludeSemantics: true,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.fullscreen),
        label: Text(l10n.dishCardFullScreen),
      ),
    );
  }
}

/// One or more hidden-carb flags shown inside [_ScriptDisclosure] when a
/// dish was demoted to yellow by the parser (issue #213).
///
/// Each flag shows a small warning icon, the [HiddenCarb.source] (the
/// suspected ingredient), and the [HiddenCarb.waiterQuestion] in the
/// menu's own language. The label ("Possible hidden carbs") comes from
/// ARB; the question text is rendered as-is, in the menu's own language
/// per architecture.md §12, with a [Directionality] wrapper.
class _HiddenCarbsRow extends StatelessWidget {
  /// Creates a row for one or more [hiddenCarbs] on a [DishVerdict.modifiable]
  /// dish, styled with [tone].
  const new({required this.hiddenCarbs, required this.tone});

  /// The non-empty list of hidden-carb flags from [AnalysedDish.hiddenCarbs].
  final List<HiddenCarb> hiddenCarbs;

  /// The amber tone of the enclosing [DishCard].
  final VerdictTone tone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final ambient = Directionality.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            l10n.hiddenCarbsSectionLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: tone.ink,
              letterSpacing: 0.4,
            ),
          ),
        ),
        ...hiddenCarbs.map(
          (flag) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: tone.ink),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        flag.source,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: tone.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        flag.waiterQuestion,
                        textDirection: contentDirection(
                          flag.waiterQuestion,
                          ambient,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tone.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The "add a note" affordance (issue #240): one small icon button, shown
/// only while a dish has no note, so forty dishes do not each carry a muted
/// text row. Its tooltip is visual; its icon carries the semantics label.
class _AddNoteButton extends StatelessWidget {
  const new({required this.onPressed});

  /// Called when the icon is tapped, to open the note editor.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // The tooltip is visual only; the icon's own label is the one semantics
    // announcement, so the two never read twice.
    return Tooltip(
      message: l10n.dishCardAddNote,
      excludeFromSemantics: true,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(
          Icons.note_add_outlined,
          semanticLabel: l10n.dishCardAddNote,
        ),
        iconSize: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
  }
}

/// The personal-note row (issue #52): a small tappable icon-and-text row
/// showing the note itself. Rendered only once a note exists (issue #240);
/// before that, [_AddNoteButton] is the affordance. Neutral for every
/// verdict — a note is the user's own annotation, not a verdict colour — so
/// it reads from the theme's own on-surface-variant colour rather than a
/// [VerdictTone].
class _NoteRow extends StatelessWidget {
  const new({required this.note, required this.onTap});

  /// The (non-empty) note to show.
  final String note;

  /// Called when the row is tapped, to open the note editor.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      label: l10n.dishCardEditNoteSemanticLabel(note),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(Icons.sticky_note_2_outlined, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  note,
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
