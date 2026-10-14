import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';
import 'package:ketoclub/utils/allergens/group_chef_card.dart';
import 'package:ketoclub/widgets/group_chef_card_view.dart';
import 'package:ketoclub/widgets/waiter_script_widget.dart';

/// The full-screen chef card built from the dietary profile alone (Banto,
/// ALG-08a, issue #350): "show this at any restaurant", for the days when
/// no menu can be read.
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
  /// Creates the card for [profile].
  const new({
    required this.profile,
    this.people = const <NamedProfile>[],
    this.screenBrightness = const NoOpScreenBrightness(),
    this.menuSharer,
    super.key,
  });

  /// The restrictions the card states.
  final DietaryProfile profile;

  /// With more than one person, the card is theirs instead of [profile]'s:
  /// one section per person under their name (ALG-12, issue #354;
  /// [GroupChefCardText]).
  final List<NamedProfile> people;

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
  /// app's language until then.
  bool? _hebrewChoice;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: ScreenBrightness's contract never throws.
    unawaited(widget.screenBrightness.raise());
  }

  @override
  void dispose() {
    unawaited(widget.screenBrightness.restore());
    super.dispose();
  }

  bool get _hebrew =>
      _hebrewChoice ?? Localizations.localeOf(context).languageCode == 'he';

  Future<void> _share(AppLocalizations l10n, String text) async {
    await widget.menuSharer?.shareText(text, subject: l10n.chefCardTitle);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hebrew = _hebrew;
    final lines = ChefCardText.compose(widget.profile, hebrew: hebrew);
    final group = widget.people.length > 1
        ? GroupChefCardText.compose(widget.people, hebrew: hebrew)
        : null;
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
