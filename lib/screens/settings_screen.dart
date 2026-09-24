import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/locale_controller.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/state/theme_mode_controller.dart';
import 'package:ketoclub/theme/verdict_colors.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:provider/provider.dart';

/// Scopes a test's finder to the language section's radio group, so a
/// label the language and appearance sections happen to share (both offer
/// a "follow the device" choice) cannot make `find.text(...)` match two
/// widgets. Public so tests can reach it without a brittle text lookup.
const Key languageRadioGroupKey = Key('settingsLanguageRadioGroup');

/// Scopes a test's finder to the appearance section's radio group, for the
/// same reason as [languageRadioGroupKey].
const Key appearanceRadioGroupKey = Key('settingsAppearanceRadioGroup');

/// The net-carb limit stepper's minus button (issue #57), public so a test
/// can tap it without relying on an icon or tooltip lookup.
const Key netCarbLimitDecreaseKey = Key('settingsNetCarbLimitDecrease');

/// The net-carb limit stepper's plus button (issue #57).
const Key netCarbLimitIncreaseKey = Key('settingsNetCarbLimitIncrease');

/// The net-carb limit stepper's value label (issue #57), e.g. "6 g".
const Key netCarbLimitValueKey = Key('settingsNetCarbLimitValue');

/// The "Strict seed-oil free" switch (issue #56), public so a test can tap
/// it without a text lookup that the hint line could make ambiguous.
const Key seedOilFreeSwitchKey = Key('settingsSeedOilFreeSwitch');

/// The "Dairy-free keto" switch (issue #56).
const Key dairyFreeSwitchKey = Key('settingsDairyFreeSwitch');

/// The "Carnivore only" switch (issue #56).
const Key carnivoreOnlySwitchKey = Key('settingsCarnivoreOnlySwitch');

/// The Settings screen: the AI-analysis consent disclosure, the UI
/// language, the appearance, the net-carb limit, the "Your keto rules"
/// dietary toggles, the default menu filter, and cache clearing
/// (architecture.md §6.6, §11, §12, §13).
///
/// Reads its [SettingsController] from `provider` and calls
/// [SettingsController.load] once, after the first frame, the same way
/// `MenuScreen` calls `open`: a `StatefulWidget` with an `initState` that
/// defers to a post-frame callback, so building this screen never itself
/// starts I/O. A plain `StatelessWidget` cannot do this on its own —
/// `provider`'s `create` runs once per controller, not once per screen
/// mount, and has no hook that fires after the first frame — so this
/// screen is stateful for that one reason alone. This file's tests build
/// an unloaded controller and pump this screen exactly as the app does,
/// then let the load settle with `pumpAndSettle`, rather than pre-loading
/// the controller themselves — so a regression in this wiring fails a
/// test here, not only in a flow test.
class SettingsScreen extends StatefulWidget {
  /// Creates the Settings screen.
  const new({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Whether [SettingsController.clearCache] has completed since this
  /// screen was built, so [AppLocalizations.settingsCacheCleared] can be
  /// shown once. Local UI state, not part of [SettingsController]: the
  /// controller has no notion of "just cleared", only of being busy.
  bool _cacheCleared = false;

  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame, so building this screen never
    // itself starts the load — a widget's build method must stay free of
    // side effects. See the class doc for why this must be a
    // StatefulWidget rather than provider's create.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<SettingsController>().load());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.watch<SettingsController>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      // A plain Column, not a lazy ListView: this screen is short and
      // every section must exist in the tree up front so a test (or a
      // screen reader) can find a control without first scrolling it
      // into the sliver viewport's cache extent.
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _consentSection(context, l10n, controller),
            const SizedBox(height: 20),
            _languageSection(context, l10n, controller),
            const SizedBox(height: 20),
            _appearanceSection(context, l10n, controller),
            const SizedBox(height: 20),
            _netCarbLimitSection(context, l10n, controller),
            const SizedBox(height: 20),
            _ketoRulesSection(context, l10n, controller),
            const SizedBox(height: 20),
            _filterSection(context, l10n, controller),
            const SizedBox(height: 20),
            _cacheSection(context, l10n, controller),
          ],
        ),
      ),
    );
  }

  /// The consent disclosure: what leaves the device, and the
  /// acknowledgement checkbox wired to [SettingsController.setConsent]
  /// (architecture.md §11).
  Widget _consentSection(
    BuildContext context,
    AppLocalizations l10n,
    SettingsController controller,
  ) {
    final busy = controller.isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(l10n.settingsConsentTitle),
        _SettingsGroup(
          children: [
            _GroupNote(l10n.settingsConsentBody),
            CheckboxListTile(
              controlAffinity: ListTileControlAffinity.leading,
              value: controller.consentGiven,
              onChanged: busy
                  ? null
                  : (given) =>
                        unawaited(controller.setConsent(given: given ?? false)),
              title: Text(l10n.settingsConsentAccept),
            ),
          ],
        ),
      ],
    );
  }

  /// The three-way UI language choice: system, English, or Hebrew
  /// (architecture.md §12). "Match my device" is `null` in
  /// [SettingsController.setLanguage], never a sentinel tag.
  ///
  /// [SettingsController] stays the only writer of the persisted tag; once
  /// its write lands, [LocaleController.applyTag] is told directly, so
  /// `MaterialApp.locale` (owned by the app-level [LocaleController], not by
  /// this screen's own controller) updates without a second write path —
  /// see the class doc on `LocaleController`.
  Widget _languageSection(
    BuildContext context,
    AppLocalizations l10n,
    SettingsController controller,
  ) {
    final busy = controller.isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(l10n.settingsLanguage),
        _SettingsGroup(
          children: [
            RadioGroup<String?>(
              key: languageRadioGroupKey,
              groupValue: controller.languageTag,
              onChanged: (tag) =>
                  unawaited(_setLanguage(context, controller, tag)),
              child: Column(
                children: [
                  RadioListTile<String?>(
                    title: Text(l10n.settingsLanguageSystem),
                    value: null,
                    enabled: !busy,
                  ),
                  RadioListTile<String?>(
                    title: Text(l10n.settingsLanguageEnglish),
                    value: 'en',
                    enabled: !busy,
                  ),
                  RadioListTile<String?>(
                    title: Text(l10n.settingsLanguageHebrew),
                    value: 'he',
                    enabled: !busy,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Persists [tag] through [controller] — the sole writer of the stored
  /// language tag — then applies it to the app-level [LocaleController], so
  /// `MaterialApp.locale` picks it up. Never the other way around: this
  /// screen never writes a locale directly, only relays a write that has
  /// already completed.
  Future<void> _setLanguage(
    BuildContext context,
    SettingsController controller,
    String? tag,
  ) async {
    await controller.setLanguage(tag);
    if (!context.mounted) return;
    context.read<LocaleController>().applyTag(tag);
  }

  /// The three-way appearance choice: system, light, or dark
  /// (issue #58). Copies [_languageSection]'s shape exactly, down to the
  /// same "persist through the screen's own controller, then relay to the
  /// app-level controller" pattern — see [_setThemeMode] and
  /// [_setLanguage].
  Widget _appearanceSection(
    BuildContext context,
    AppLocalizations l10n,
    SettingsController controller,
  ) {
    final busy = controller.isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(l10n.settingsAppearance),
        _SettingsGroup(
          children: [
            RadioGroup<AppThemeMode>(
              key: appearanceRadioGroupKey,
              groupValue: controller.themeMode,
              onChanged: (mode) =>
                  unawaited(_setThemeMode(context, controller, mode)),
              child: Column(
                children: [
                  RadioListTile<AppThemeMode>(
                    title: Text(l10n.settingsAppearanceSystem),
                    value: AppThemeMode.system,
                    enabled: !busy,
                  ),
                  RadioListTile<AppThemeMode>(
                    title: Text(l10n.settingsAppearanceLight),
                    value: AppThemeMode.light,
                    enabled: !busy,
                  ),
                  RadioListTile<AppThemeMode>(
                    title: Text(l10n.settingsAppearanceDark),
                    value: AppThemeMode.dark,
                    enabled: !busy,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Persists [mode] through [controller] — the sole writer of the stored
  /// appearance mode — then applies it to the app-level
  /// [ThemeModeController], so `MaterialApp.themeMode` picks it up. Never
  /// the other way around, for the same reason [_setLanguage] documents.
  Future<void> _setThemeMode(
    BuildContext context,
    SettingsController controller,
    AppThemeMode? mode,
  ) async {
    if (mode == null) return;
    await controller.setThemeMode(mode);
    if (!context.mounted) return;
    context.read<ThemeModeController>().applyMode(mode);
  }

  /// The net-carb limit stepper (issue #57): minus, the value ("6 g"),
  /// plus, bounded by [minNetCarbLimitGrams] and [maxNetCarbLimitGrams],
  /// under a one-line explanation that dishes above it are never green and
  /// that a change re-analyses the next menu opened.
  ///
  /// Each button is disabled at its own bound — not merely clamped on
  /// tap — so the control shows the user where the range ends, and while
  /// the controller is busy, so two quick taps cannot race one write.
  /// [SettingsController.setNetCarbLimit] clamps as well, so the bound
  /// holds even for a caller that is not this stepper.
  Widget _netCarbLimitSection(
    BuildContext context,
    AppLocalizations l10n,
    SettingsController controller,
  ) {
    final busy = controller.isBusy;
    final grams = controller.netCarbLimitGrams;
    final canDecrease = !busy && grams > minNetCarbLimitGrams;
    final canIncrease = !busy && grams < maxNetCarbLimitGrams;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(l10n.settingsNetCarbLimit),
        _SettingsGroup(
          children: [
            _GroupNote(l10n.settingsNetCarbLimitBody),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 10),
              child: Row(
                children: [
                  IconButton.outlined(
                    key: netCarbLimitDecreaseKey,
                    tooltip: l10n.settingsNetCarbLimitDecrease,
                    onPressed: canDecrease
                        ? () => unawaited(controller.setNetCarbLimit(grams - 1))
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      l10n.settingsNetCarbLimitValue(grams),
                      key: netCarbLimitValueKey,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton.outlined(
                    key: netCarbLimitIncreaseKey,
                    tooltip: l10n.settingsNetCarbLimitIncrease,
                    onPressed: canIncrease
                        ? () => unawaited(controller.setNetCarbLimit(grams + 1))
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The "Your keto rules" section (issue #56, `.design/Settings.dc.html`):
  /// three switches — strict seed-oil free, dairy-free keto, carnivore
  /// only — each with its one-line hint, under a line saying a change
  /// applies from the next menu opened.
  ///
  /// Each switch writes through its own [SettingsController] setter and is
  /// disabled while the controller is busy, like every other control on
  /// this screen, so two quick taps cannot race one write. Which prompt
  /// text and which rules each toggle adds is `constants.dart`'s business
  /// (architecture.md §9.1); this section only records the choice.
  Widget _ketoRulesSection(
    BuildContext context,
    AppLocalizations l10n,
    SettingsController controller,
  ) {
    final busy = controller.isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(l10n.settingsKetoRules),
        _SettingsGroup(
          children: [
            _GroupNote(l10n.settingsKetoRulesBody),
            SwitchListTile(
              key: seedOilFreeSwitchKey,
              title: Text(l10n.settingsSeedOilFree),
              subtitle: Text(l10n.settingsSeedOilFreeHint),
              value: controller.seedOilFree,
              onChanged: busy
                  ? null
                  : (enabled) =>
                        unawaited(controller.setSeedOilFree(enabled: enabled)),
            ),
            SwitchListTile(
              key: dairyFreeSwitchKey,
              title: Text(l10n.settingsDairyFree),
              subtitle: Text(l10n.settingsDairyFreeHint),
              value: controller.dairyFree,
              onChanged: busy
                  ? null
                  : (enabled) =>
                        unawaited(controller.setDairyFree(enabled: enabled)),
            ),
            SwitchListTile(
              key: carnivoreOnlySwitchKey,
              title: Text(l10n.settingsCarnivoreOnly),
              subtitle: Text(l10n.settingsCarnivoreOnlyHint),
              value: controller.carnivoreOnly,
              onChanged: busy
                  ? null
                  : (enabled) => unawaited(
                      controller.setCarnivoreOnly(enabled: enabled),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  /// The [MenuFilter] default, offering exactly the four values the menu
  /// screen's own verdict counter tiles can produce
  /// ([MenuFilter.greenOnly], [MenuFilter.yellowOnly], [MenuFilter.redOnly]
  /// and [MenuFilter.all]) — issue #35 dropped [MenuFilter.greenAndYellow]
  /// from this control since no tile can reproduce it either, and reused
  /// the tiles' own labels so the two controls read as the same vocabulary
  /// (architecture.md §6.6). [MenuFilter.greenAndYellow] itself is
  /// untouched: still a real, correctly-decoding value for a filter
  /// persisted by an install that predates issue #35, just not one this
  /// control (or any tile) offers any more.
  Widget _filterSection(
    BuildContext context,
    AppLocalizations l10n,
    SettingsController controller,
  ) {
    final busy = controller.isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(l10n.settingsFilter),
        // At phone width the four segments were forced into equal quarters
        // and their labels broke mid-word ("Ever/ythin/g") — found by the
        // visual audit. The artboard's chip-sized label and tighter
        // padding let all four fit a 390px screen; the sideways scroll is
        // only the fallback for a narrower one or a longer translation.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<MenuFilter>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            segments: [
              ButtonSegment(
                value: MenuFilter.greenOnly,
                label: Text(l10n.tileGreenLabel),
              ),
              ButtonSegment(
                value: MenuFilter.yellowOnly,
                label: Text(l10n.tileYellowLabel),
              ),
              ButtonSegment(
                value: MenuFilter.redOnly,
                label: Text(l10n.tileRedLabel),
              ),
              ButtonSegment(value: MenuFilter.all, label: Text(l10n.filterAll)),
            ],
            selected: <MenuFilter>{controller.filter},
            onSelectionChanged: busy
                ? null
                : (selection) =>
                      unawaited(controller.setFilter(selection.first)),
          ),
        ),
      ],
    );
  }

  /// The cached-menu count and its "works offline" note (issue #61), the
  /// Clear action gated by a confirmation dialog, and the one-shot
  /// confirmation line shown once clearing has actually happened.
  ///
  /// The count comes from [SettingsController.cachedMenuCount], read on
  /// [SettingsController.load] and refreshed by
  /// [SettingsController.clearCache] itself, so this widget renders
  /// whatever the controller already holds and never counts anything on
  /// its own.
  Widget _cacheSection(
    BuildContext context,
    AppLocalizations l10n,
    SettingsController controller,
  ) {
    final busy = controller.isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsGroup(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(15, 8, 6, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.settingsCacheSummary(controller.cachedMenuCount),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  // The artboard's "Clear" is a quiet `--red-ink` text
                  // action at the row's end, not a filled button: it is
                  // destructive, and the dialog behind it asks first.
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: VerdictColors.of(context).red.ink,
                    ),
                    onPressed: busy
                        ? null
                        : () => unawaited(
                            _confirmAndClearCache(context, controller),
                          ),
                    child: Text(l10n.settingsClearCache),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_cacheCleared) ...[
          const SizedBox(height: 8),
          Text(l10n.settingsCacheCleared),
        ],
      ],
    );
  }

  /// Asks for confirmation before clearing every saved menu — an
  /// irreversible action, since a cached menu is what makes the Saved tab
  /// (issue #48) work offline in the first place. Clears through
  /// [_clearCache] only when the dialog's own confirm action is chosen;
  /// dismissing the dialog any other way (its cancel action, the barrier,
  /// or the back gesture) clears nothing.
  Future<void> _confirmAndClearCache(
    BuildContext context,
    SettingsController controller,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.settingsClearCacheConfirmTitle),
        content: Text(l10n.settingsClearCacheConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.settingsClearCacheConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await _clearCache(controller);
  }

  /// Clears the cache through [controller], then shows the confirmation
  /// line for the rest of this screen's lifetime.
  Future<void> _clearCache(SettingsController controller) async {
    await controller.clearCache();
    if (!mounted) return;
    setState(() => _cacheCleared = true);
  }
}

/// A section heading in the artboard's style (`.design/Settings.dc.html`):
/// small, extra-bold, letter-spaced and muted, sitting just above its
/// group rather than a full-size title. The artboard also upper-cases it;
/// Flutter has no text-transform, and the string must stay findable
/// verbatim, so it keeps its own case.
class _SectionLabel extends StatelessWidget {
  const new(this.text);

  /// The section's title.
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 2, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(fontSize: 12, letterSpacing: 0.6),
      ),
    );
  }
}

/// One of the artboard's grouped cards: `--surface`, a `--line` edge and
/// a 15px radius, holding a section's controls. A themed [Card] (a
/// [Material]), so the list tiles inside it keep their ink splashes.
class _SettingsGroup extends StatelessWidget {
  const new({required this.children});

  /// The section's controls, top to bottom.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// A section's explanatory line inside its group, in the artboard's
/// muted hint style (13px `--ink2`).
class _GroupNote extends StatelessWidget {
  const new(this.text);

  /// The explanation.
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(fontSize: 13, height: 1.45),
      ),
    );
  }
}
