import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/locale_controller.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/state/theme_mode_controller.dart';
import 'package:provider/provider.dart';

/// Scopes a test's finder to the language section's radio group, so a
/// label the language and appearance sections happen to share (both offer
/// a "follow the device" choice) cannot make `find.text(...)` match two
/// widgets. Public so tests can reach it without a brittle text lookup.
const Key languageRadioGroupKey = Key('settingsLanguageRadioGroup');

/// Scopes a test's finder to the appearance section's radio group, for the
/// same reason as [languageRadioGroupKey].
const Key appearanceRadioGroupKey = Key('settingsAppearanceRadioGroup');

/// The Settings screen: the AI-analysis consent disclosure, the UI
/// language, the default menu filter, and cache
/// clearing (architecture.md §6.6, §11, §12, §13).
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _consentSection(context, l10n, controller),
            const SizedBox(height: 24),
            _languageSection(context, l10n, controller),
            const SizedBox(height: 24),
            _appearanceSection(context, l10n, controller),
            const SizedBox(height: 24),
            _filterSection(context, l10n, controller),
            const SizedBox(height: 24),
            _cacheSection(l10n, controller),
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
        Text(
          l10n.settingsConsentTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(l10n.settingsConsentBody),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: controller.consentGiven,
          onChanged: busy
              ? null
              : (given) =>
                    unawaited(controller.setConsent(given: given ?? false)),
          title: Text(l10n.settingsConsentAccept),
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
        Text(
          l10n.settingsLanguage,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        RadioGroup<String?>(
          key: languageRadioGroupKey,
          groupValue: controller.languageTag,
          onChanged: (tag) => unawaited(_setLanguage(context, controller, tag)),
          child: Column(
            children: [
              RadioListTile<String?>(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.settingsLanguageSystem),
                value: null,
                enabled: !busy,
              ),
              RadioListTile<String?>(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.settingsLanguageEnglish),
                value: 'en',
                enabled: !busy,
              ),
              RadioListTile<String?>(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.settingsLanguageHebrew),
                value: 'he',
                enabled: !busy,
              ),
            ],
          ),
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
        Text(
          l10n.settingsAppearance,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        RadioGroup<AppThemeMode>(
          key: appearanceRadioGroupKey,
          groupValue: controller.themeMode,
          onChanged: (mode) =>
              unawaited(_setThemeMode(context, controller, mode)),
          child: Column(
            children: [
              RadioListTile<AppThemeMode>(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.settingsAppearanceSystem),
                value: AppThemeMode.system,
                enabled: !busy,
              ),
              RadioListTile<AppThemeMode>(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.settingsAppearanceLight),
                value: AppThemeMode.light,
                enabled: !busy,
              ),
              RadioListTile<AppThemeMode>(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.settingsAppearanceDark),
                value: AppThemeMode.dark,
                enabled: !busy,
              ),
            ],
          ),
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
        Text(
          l10n.settingsFilter,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SegmentedButton<MenuFilter>(
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
              : (selection) => unawaited(controller.setFilter(selection.first)),
        ),
      ],
    );
  }

  /// The clear-cache action and its one-shot confirmation line.
  Widget _cacheSection(AppLocalizations l10n, SettingsController controller) {
    final busy = controller.isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton(
          onPressed: busy ? null : () => unawaited(_clearCache(controller)),
          child: Text(l10n.settingsClearCache),
        ),
        if (_cacheCleared) ...[
          const SizedBox(height: 8),
          Text(l10n.settingsCacheCleared),
        ],
      ],
    );
  }

  /// Clears the cache through [controller], then shows the confirmation
  /// line for the rest of this screen's lifetime.
  Future<void> _clearCache(SettingsController controller) async {
    await controller.clearCache();
    if (!mounted) return;
    setState(() => _cacheCleared = true);
  }
}
