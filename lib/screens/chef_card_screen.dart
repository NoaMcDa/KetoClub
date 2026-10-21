import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/trip_destination.dart';
import 'package:ketoclub/screens/chef_card_image_screen.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/utils/allergens/allergen_matrix.dart';
import 'package:ketoclub/utils/allergens/chef_card_locales.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/utils/allergens/confirmations.dart';
import 'package:ketoclub/utils/allergens/group_chef_card.dart';
import 'package:ketoclub/utils/allergens/group_evaluator.dart';
import 'package:ketoclub/utils/allergens/kitchen_reach.dart';
import 'package:ketoclub/utils/allergens/kitchen_signals.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/widgets/group_chef_card_view.dart';
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
/// With several [people] the card has one section per person, and a dish
/// card holds each person's own questions and change in their section.
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
/// **In the trip's language (issue #419).** While trip mode is on for
/// France, Italy, Spain, Germany or Japan ([trip]), the toggle offers that
/// language beside Hebrew and English and the card opens in it
/// ([ChefCardLanguage.forTrip]); the sentences and names come from
/// `chef_card_locales.dart`, composed on the device, so the card works
/// offline as trip mode does. Under a translated card one muted line in
/// the UI's language says it was translated by the app and not checked by
/// a native speaker. A dish card's change and questions are the
/// evaluator's English ones in a translated card, and its allergy note is
/// English: only the card's own sentences are translated.
///
/// **As an image (issue #420).** "Share as image" opens
/// [ChefCardImageScreen]: the card in the language shown, in the light
/// theme, with a helper-not-a-guarantee footer in that language, rendered
/// to a PNG and shared as a file; the text share stays.
///
/// A dish card is evaluated as the menu screen evaluates the dish: with
/// the section heading it sits under, the restaurant's allergen matrix
/// ([matrix], ALG-16) and the person's own staff answers
/// ([confirmations], ALG-14), which the menu screen hands over from its
/// `MenuController`. Below it, the dish's allergy note
/// ([ChefCardText.dishAllergyNote], ALG-15), in the card's language, can
/// be copied or shared for a delivery app's note box.
///
/// The card says what the person is and what to ask. It never says a dish
/// is safe (the helper-tool sentence below it says why).
class ChefCardScreen extends StatefulWidget {
  /// Creates the card for [profile]; with [dish] and [analysed], the card
  /// for that dish, whose kitchen [menu] is read for signals.
  const new({
    required this.profile,
    this.people = const <NamedProfile>[],
    this.screenBrightness = const NoOpScreenBrightness(),
    this.menuSharer,
    this.dish,
    this.analysed,
    this.menu,
    this.trip,
    this.matrix = MatrixEvidence.none,
    this.confirmations = const <ConfirmationEvidence>[],
    super.key,
  });

  /// The restrictions the card states.
  final DietaryProfile profile;

  /// With more than one person the card is theirs instead of [profile]'s:
  /// one section per person under their name (ALG-12, issue #354;
  /// [GroupChefCardText]). With a [dish] and its analysis too, the dish's
  /// name comes once before the sections, each person's section also holds
  /// the change and the questions that apply to them for that dish, and
  /// one closing ends it ([GroupChefCardText.composeForDish]). With one
  /// person or none, the card is built from [profile] alone.
  final List<NamedProfile> people;

  /// The dish the card is about, or null for the profile-only card.
  final Dish? dish;

  /// [dish]'s analysis; the card is the profile-only one without it.
  final AnalysedDish? analysed;

  /// The menu [dish] is on, read once for kitchen signals
  /// ([KitchenSignals.of]); null reads as no signal.
  final Menu? menu;

  /// Trip mode's destination (ALG-13), so a dish card asks what the menu
  /// screen asked: the destination's lexicon is evaluated on the device.
  /// Null when no trip is active.
  final TripDestination? trip;

  /// What the restaurant's allergen matrix says about [dish] (ALG-16), as
  /// the menu screen read it; [MatrixEvidence.none] without one.
  final MatrixEvidence matrix;

  /// What the staff said about [dish] after an earlier meal (ALG-14,
  /// `Confirmations.forDish`), as the menu screen read it; empty without.
  final List<ConfirmationEvidence> confirmations;

  /// Raised while the card is open, restored when it closes.
  final ScreenBrightness screenBrightness;

  /// Shares the card as text; null leaves the Share button out.
  final MenuSharer? menuSharer;

  @override
  State<ChefCardScreen> createState() => _ChefCardScreenState();
}

/// Scopes a test to the language toggle.
const Key chefCardLanguageToggleKey = Key('chefCardLanguageToggle');

/// The "translated by the app" line under a translated card (#419).
const Key chefCardTranslatedNoteKey = Key('chefCardTranslatedNote');

/// The "Share as image" button (#420).
const Key chefCardShareImageKey = Key('chefCardShareImage');

/// [language]'s name in the UI language, for the card's language toggle.
String chefCardLanguageName(AppLocalizations l10n, ChefCardLanguage language) =>
    switch (language) {
      ChefCardLanguage.he => l10n.settingsLanguageHebrew,
      ChefCardLanguage.en => l10n.settingsLanguageEnglish,
      ChefCardLanguage.fr => l10n.chefCardLanguageFrench,
      ChefCardLanguage.it => l10n.chefCardLanguageItalian,
      ChefCardLanguage.es => l10n.chefCardLanguageSpanish,
      ChefCardLanguage.de => l10n.chefCardLanguageGerman,
      ChefCardLanguage.ja => l10n.chefCardLanguageJapanese,
    };

/// The Share button, public so a test can tap it.
const Key chefCardShareKey = Key('chefCardShare');

/// The empty-profile message.
const Key chefCardEmptyKey = Key('chefCardEmpty');

/// The dish's allergy note text (ALG-15).
const Key chefCardAllergyNoteKey = Key('chefCardAllergyNote');

/// The button copying the dish's allergy note.
const Key chefCardAllergyNoteCopyKey = Key('chefCardAllergyNoteCopy');

/// The button sharing the dish's allergy note.
const Key chefCardAllergyNoteShareKey = Key('chefCardAllergyNoteShare');

class _ChefCardScreenState extends State<ChefCardScreen> {
  /// The user's pick; null until they toggle, so the card follows the
  /// trip's language (#419), else the menu's language (a dish card) or
  /// the app's (the profile card) until then.
  ChefCardLanguage? _choice;

  /// Whether the menu's kitchen threatens a strict entry of the profile,
  /// computed once: the menu does not change while the card is open.
  bool _crossContact = false;

  /// What the menu's kitchen reaches, read once for a group dish card.
  KitchenReach _reach = KitchenReach.empty;

  /// The heading of the menu section holding the dish, for the
  /// declarations the evaluator reads from it (ALG-09); null when unknown.
  String? _heading;

  bool get _isGroup => widget.people.length > 1;

  @override
  void initState() {
    super.initState();
    final menu = widget.menu;
    if (widget.dish != null && menu != null) {
      final signals = KitchenSignals.of(menu);
      _crossContact = _isGroup
          ? GroupChefCardText.kitchenThreatensStrict(signals, widget.people)
          : ChefCardText.kitchenThreatensStrict(signals, widget.profile);
      if (_isGroup) _reach = KitchenReach.of(menu);
      for (final category in menu.categories) {
        if (category.dishes.any((d) => d.id == widget.dish!.id)) {
          _heading = category.name;
        }
      }
    }
    // Fire-and-forget: ScreenBrightness's contract never throws.
    unawaited(widget.screenBrightness.raise());
  }

  @override
  void dispose() {
    unawaited(widget.screenBrightness.restore());
    super.dispose();
  }

  /// The trip's language when the card has one for it; null otherwise.
  ChefCardLanguage? get _tripLanguage => ChefCardLanguage.forTrip(widget.trip);

  ChefCardLanguage get _language {
    final dish = widget.dish;
    return _choice ??
        _tripLanguage ??
        ChefCardLanguage.of(
          hebrew: dish != null && widget.analysed != null
              ? VerdictCopy.dishIsHebrew(dish)
              : Localizations.localeOf(context).languageCode == 'he',
        );
  }

  /// The dish evaluated for the one profile in Hebrew when [hebrew], as
  /// the menu screen evaluates it: under its section heading, with the
  /// restaurant's matrix and the person's staff answers.
  EvaluatedDish _evaluateDish({required bool hebrew}) =>
      ProfileEvaluator.evaluate(
        widget.analysed!,
        widget.dish!,
        widget.profile,
        hebrew: hebrew,
        heading: _heading,
        trip: widget.trip,
        matrix: widget.matrix,
        confirmations: widget.confirmations,
      );

  /// The card's lines in [language]: the dish card for [evaluated] when
  /// there is a dish and its analysis, re-evaluated in Hebrew or English
  /// (English for a translated card) so its "without" lines and questions
  /// follow the toggle; the profile card otherwise.
  List<String> _lines(ChefCardLanguage language, {EvaluatedDish? evaluated}) {
    final hebrew = language == ChefCardLanguage.he;
    final dish = widget.dish;
    if (dish == null || evaluated == null) {
      return ChefCardText.compose(
        widget.profile,
        hebrew: hebrew,
        language: language,
      );
    }
    return ChefCardText.composeForDish(
      widget.profile,
      dishName: dish.name,
      modification: evaluated.modification,
      questions: VerdictCopy.waiterQuestions(evaluated, hebrew: hebrew),
      crossContact: _crossContact,
      hebrew: hebrew,
      language: language,
    );
  }

  /// The group card for the dish, in Hebrew when [hebrew]: each person is
  /// evaluated on their own through the pipeline the menu screen uses
  /// ([GroupEvaluator.evaluate]: the evaluator, then the kitchen), in the
  /// card's language so the lines follow the toggle.
  GroupEvaluation _evaluateGroup({required bool hebrew}) =>
      GroupEvaluator.evaluate(
        widget.analysed!,
        widget.dish!,
        widget.people,
        hebrew: hebrew,
        heading: _heading,
        kitchen: _reach,
        trip: widget.trip,
        matrix: widget.matrix,
        confirmations: widget.confirmations,
      );

  /// The group card for [group], the dish's evaluation for every person,
  /// in [language].
  GroupChefCard _groupDishCard(
    GroupEvaluation group,
    ChefCardLanguage language,
  ) {
    final hebrew = language == ChefCardLanguage.he;
    final dish = widget.dish!;
    return GroupChefCardText.composeForDish(
      <PersonDishPart>[
        for (final result in group.people)
          (
            person: result.person,
            modification: result.evaluated.modification,
            questions: VerdictCopy.waiterQuestions(
              result.evaluated,
              hebrew: hebrew,
            ),
          ),
      ],
      dishName: dish.name,
      crossContact: _crossContact,
      hebrew: hebrew,
      language: language,
    );
  }

  /// Opens the card as an image, ready to share (#420).
  void _openImage({
    required List<String> lines,
    required GroupChefCard? group,
    required ChefCardLanguage language,
    required String text,
    required MenuSharer sharer,
  }) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ChefCardImageScreen(
          lines: lines,
          group: group,
          language: language,
          text: text,
          menuSharer: sharer,
        ),
      ),
    );
  }

  Future<void> _share(AppLocalizations l10n, String text) async {
    await widget.menuSharer?.shareText(text, subject: l10n.chefCardTitle);
  }

  /// Copies the dish's allergy [note] (ALG-15) to the clipboard and says
  /// so, as the menu's own "Copy allergy note" does.
  Future<void> _copyNote(String note) async {
    await Clipboard.setData(ClipboardData(text: note));
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.menuAllergyNoteCopied),
          showCloseIcon: true,
        ),
      );
  }

  /// The dish's allergy note under the card (ALG-15): a heading, the note
  /// in the card's language and its Copy and Share buttons.
  Widget _noteSection(
    AppLocalizations l10n,
    ThemeData theme,
    String note, {
    required bool hebrew,
  }) {
    final sharer = widget.menuSharer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        Text(l10n.chefCardAllergyNoteTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(l10n.chefCardAllergyNoteExplain, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: Text(
            note,
            key: chefCardAllergyNoteKey,
            textDirection: hebrew ? TextDirection.rtl : TextDirection.ltr,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: chefCardAllergyNoteCopyKey,
              onPressed: () => unawaited(_copyNote(note)),
              icon: const Icon(Icons.copy),
              label: Text(l10n.menuAllergyNoteAction),
            ),
            if (sharer != null)
              OutlinedButton.icon(
                key: chefCardAllergyNoteShareKey,
                onPressed: () => unawaited(
                  sharer.shareText(note, subject: l10n.menuAllergyNoteSubject),
                ),
                icon: const Icon(Icons.ios_share),
                label: Text(l10n.menuAllergyNoteShare),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final language = _language;
    final tripLanguage = _tripLanguage;
    // A translated card's dish lines and allergy note are English.
    final hebrew = language == ChefCardLanguage.he;
    // Precedence: with more than one person the group card, for the dish
    // when there is a dish and its analysis; otherwise the dish card for
    // one profile, then the profile card.
    final isDishCard = widget.dish != null && widget.analysed != null;
    final groupEvaluation = _isGroup && isDishCard
        ? _evaluateGroup(hebrew: hebrew)
        : null;
    final evaluated = !_isGroup && isDishCard
        ? _evaluateDish(hebrew: hebrew)
        : null;
    final group = !_isGroup
        ? null
        : groupEvaluation != null
        ? _groupDishCard(groupEvaluation, language)
        : GroupChefCardText.compose(
            widget.people,
            hebrew: hebrew,
            language: language,
          );
    final lines = group == null
        ? _lines(language, evaluated: evaluated)
        : const <String>[];
    // ALG-15: the dish's own allergy note, from the profile and the
    // concerns the card itself found; none on the profile card.
    final noteConcerns =
        groupEvaluation?.combined.concerns ?? evaluated?.concerns;
    final note = noteConcerns == null
        ? null
        : ChefCardText.dishAllergyNote(
            widget.profile,
            dishName: widget.dish!.name,
            concerns: noteConcerns,
            hebrew: hebrew,
          );
    final text = group == null
        ? ChefCardText.asText(lines)
        : GroupChefCardText.asText(group);
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
                      child: SegmentedButton<ChefCardLanguage>(
                        key: chefCardLanguageToggleKey,
                        showSelectedIcon: false,
                        segments: <ButtonSegment<ChefCardLanguage>>[
                          for (final option in <ChefCardLanguage>[
                            ?tripLanguage,
                            ChefCardLanguage.he,
                            ChefCardLanguage.en,
                          ])
                            ButtonSegment<ChefCardLanguage>(
                              value: option,
                              label: Text(chefCardLanguageName(l10n, option)),
                            ),
                        ],
                        selected: <ChefCardLanguage>{language},
                        onSelectionChanged: (selection) =>
                            setState(() => _choice = selection.first),
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (group != null)
                      GroupChefCardView(
                        card: group,
                        trailingAction: sharer == null
                            ? null
                            : OutlinedButton.icon(
                                key: chefCardShareKey,
                                onPressed: () => unawaited(_share(l10n, text)),
                                icon: const Icon(Icons.ios_share),
                                label: Text(l10n.chefCardShare),
                              ),
                      )
                    else if (lines.isEmpty)
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
                    if (language.locale case final locale?
                        when !locale.nativeSpeakerReviewed &&
                            (group != null || lines.isNotEmpty)) ...[
                      const SizedBox(height: 10),
                      Text(
                        l10n.chefCardTranslatedNote,
                        key: chefCardTranslatedNoteKey,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (sharer != null && (group != null || lines.isNotEmpty))
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: OutlinedButton.icon(
                            key: chefCardShareImageKey,
                            onPressed: () => _openImage(
                              lines: lines,
                              group: group,
                              language: language,
                              text: text,
                              sharer: sharer,
                            ),
                            icon: const Icon(Icons.image_outlined),
                            label: Text(l10n.chefCardShareImage),
                          ),
                        ),
                      ),
                    if (note != null)
                      _noteSection(l10n, theme, note, hebrew: hebrew),
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
