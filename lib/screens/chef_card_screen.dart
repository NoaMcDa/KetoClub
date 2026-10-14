import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/utils/allergens/kitchen_signals.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/widgets/verdict_copy.dart';
import 'package:ketoclub/widgets/waiter_script_widget.dart';

/// The full-screen chef card (Banto, issue #350): built from the dietary
/// profile alone (ALG-08a) — "show this at any restaurant", for the days
/// when no menu can be read — or, given a [ChefCardScreen.dish] and its
/// analysis, for that one dish (ALG-08b): the profile's strict lines, the
/// dish's name as printed, its change and every question, and a
/// cross-contact line when the [ChefCardScreen.menu]'s kitchen signals
/// (ALG-07) threaten a strict entry ([ChefCardText.composeForDish]). A
/// dish card opens in the menu's language; the profile card in the app's.
///
/// Mirrors the Waiter Card's shell (`WaiterCardSheet`): the screen
/// brightness is raised for as long as the card is open, the lines are the
/// same large numbered rows with a Copy button ([WaiterScriptWidget]), and a
/// pinned Done button closes it. A Hebrew/English toggle picks the language
/// of the card text, which starts as the app's language; the sentences come
/// from [ChefCardText] and are in the chosen language, never the UI's
/// (architecture.md §12). Share sends the same text through [menuSharer];
/// with none, the button is left out.
///
/// The card says what the person is and what to ask. It never says a dish
/// is safe (the helper-tool sentence below it says why).
class ChefCardScreen extends StatefulWidget {
  /// Creates the card for [profile]; with [dish] and [analysed], the card
  /// for that dish, whose kitchen [menu] is read for signals.
  const new({
    required this.profile,
    this.screenBrightness = const NoOpScreenBrightness(),
    this.menuSharer,
    this.dish,
    this.analysed,
    this.menu,
    super.key,
  });

  /// The restrictions the card states.
  final DietaryProfile profile;

  /// The dish the card is about, or null for the profile-only card.
  final Dish? dish;

  /// [dish]'s analysis; the card is the profile-only one without it.
  final AnalysedDish? analysed;

  /// The menu [dish] is on, read once for kitchen signals
  /// ([KitchenSignals.of]); null reads as no signal.
  final Menu? menu;

  /// Raised while the card is open, restored when it closes.
  final ScreenBrightness screenBrightness;

  /// Shares the card as text; null leaves the Share button out.
  final MenuSharer? menuSharer;

  @override
  State<ChefCardScreen> createState() => _ChefCardScreenState();
}

/// Scopes a test to the Hebrew/English toggle.
const Key chefCardLanguageToggleKey = Key('chefCardLanguageToggle');

/// The Share button, public so a test can tap it.
const Key chefCardShareKey = Key('chefCardShare');

/// The empty-profile message.
const Key chefCardEmptyKey = Key('chefCardEmpty');

class _ChefCardScreenState extends State<ChefCardScreen> {
  /// The user's pick; null until they toggle, so the card follows the
  /// menu's language (a dish card) or the app's (the profile card) until
  /// then.
  bool? _hebrewChoice;

  /// Whether the menu's kitchen threatens a strict entry of the profile,
  /// computed once: the menu does not change while the card is open.
  bool _crossContact = false;

  @override
  void initState() {
    super.initState();
    final menu = widget.menu;
    if (widget.dish != null && menu != null) {
      _crossContact = ChefCardText.kitchenThreatensStrict(
        KitchenSignals.of(menu),
        widget.profile,
      );
    }
    // Fire-and-forget: ScreenBrightness's contract never throws.
    unawaited(widget.screenBrightness.raise());
  }

  @override
  void dispose() {
    unawaited(widget.screenBrightness.restore());
    super.dispose();
  }

  bool get _hebrew {
    final dish = widget.dish;
    return _hebrewChoice ??
        (dish != null && widget.analysed != null
            ? VerdictCopy.dishIsHebrew(dish)
            : Localizations.localeOf(context).languageCode == 'he');
  }

  /// The card's lines in Hebrew when [hebrew]: the dish card when there is
  /// a dish and its analysis, re-evaluated in that language so its
  /// "without" lines and questions follow the toggle; the profile card
  /// otherwise.
  List<String> _lines({required bool hebrew}) {
    final dish = widget.dish;
    final analysed = widget.analysed;
    if (dish == null || analysed == null) {
      return ChefCardText.compose(widget.profile, hebrew: hebrew);
    }
    final evaluated = ProfileEvaluator.evaluate(
      analysed,
      dish,
      widget.profile,
      hebrew: hebrew,
    );
    return ChefCardText.composeForDish(
      widget.profile,
      dishName: dish.name,
      modification: evaluated.modification,
      questions: VerdictCopy.waiterQuestions(evaluated, hebrew: hebrew),
      crossContact: _crossContact,
      hebrew: hebrew,
    );
  }

  Future<void> _share(AppLocalizations l10n, String text) async {
    await widget.menuSharer?.shareText(text, subject: l10n.chefCardTitle);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hebrew = _hebrew;
    final lines = _lines(hebrew: hebrew);
    final text = ChefCardText.asText(lines);
    final sharer = widget.menuSharer;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.chefCardTitle,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 12,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(context)
                        .closeButtonTooltip,
                    color: theme.textTheme.bodySmall?.color,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      container: true,
                      label: l10n.chefCardLanguageLabel,
                      child: SegmentedButton<bool>(
                        key: chefCardLanguageToggleKey,
                        showSelectedIcon: false,
                        segments: <ButtonSegment<bool>>[
                          ButtonSegment<bool>(
                            value: true,
                            label: Text(l10n.settingsLanguageHebrew),
                          ),
                          ButtonSegment<bool>(
                            value: false,
                            label: Text(l10n.settingsLanguageEnglish),
                          ),
                        ],
                        selected: <bool>{hebrew},
                        onSelectionChanged: (selection) =>
                            setState(() => _hebrewChoice = selection.first),
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (lines.isEmpty)
                      Text(
                        l10n.chefCardEmpty,
                        key: chefCardEmptyKey,
                        style: theme.textTheme.bodyLarge,
                      )
                    else
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          border: Border.all(color: theme.dividerColor),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                          child: WaiterScriptWidget(
                            script: text,
                            prominent: true,
                            trailingAction: sharer == null
                                ? null
                                : OutlinedButton.icon(
                                    key: chefCardShareKey,
                                    onPressed: () =>
                                        unawaited(_share(l10n, text)),
                                    icon: const Icon(Icons.ios_share),
                                    label: Text(l10n.chefCardShare),
                                  ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      l10n.helperToolSentence,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 16),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: () => Navigator.maybePop(context),
                child: Text(l10n.waiterCardDone),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
