import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/screens/chef_card_screen.dart';
import 'package:ketoclub/screens/premium_gate.dart';
import 'package:ketoclub/screens/settings_premium_section.dart';
import 'package:ketoclub/screens/settings_profiles_section.dart';
import 'package:ketoclub/screens/settings_trip_section.dart';
import 'package:ketoclub/services/platform/app_info.dart';
import 'package:ketoclub/services/platform/external_link_opener.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/locale_controller.dart';
import 'package:ketoclub/state/premium_controller.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/state/theme_mode_controller.dart';
import 'package:ketoclub/theme/verdict_colors.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/banto_mode.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/utils/premium_gates.dart';
import 'package:ketoclub/widgets/content_width.dart';
import 'package:ketoclub/widgets/helper_tool_sheet.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';
import 'package:provider/provider.dart';

/// The consent section's Banto note on what of the profile leaves the
/// device (ALG-11, issue #353), present only with `bantoMode` on.
const Key consentBantoNoteKey = Key('settingsConsentBantoNote');

/// The "Share what the staff told you" toggle under AI & privacy (Banto,
/// ALG-14, issue #409), present only with `bantoMode` on and a backend.
const Key shareConfirmationsToggleKey = Key('settingsShareConfirmations');

/// The consent disclosure's note that shared confirmations are on (issue
/// #409), present only while the toggle is.
const Key consentSharedNoteKey = Key('settingsConsentSharedNote');

/// The "Show my chef card" button in the "My restrictions" section (Banto,
/// ALG-08a, issue #350), present only for a non-empty profile.
const Key restrictionsChefCardKey = Key('settingsRestrictionsChefCard');

/// Scopes a test's finder to the language section's segmented control, so
/// a label the language and appearance sections happen to share (both offer
/// a "follow the device" choice) cannot make `find.text(...)` match two
/// widgets. Public so tests can reach it without a brittle text lookup.
/// The name predates the control, which was a radio list until issue #256.
const Key languageRadioGroupKey = Key('settingsLanguageRadioGroup');

/// Scopes a test's finder to the appearance section's segmented control,
/// for the same reason as [languageRadioGroupKey].
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

/// The "What leaves this device" disclosure in the AI & privacy section
/// (issue #255), collapsed by default; a test taps it to read the consent
/// body text, which is not built while the disclosure is closed.
const Key consentDisclosureKey = Key('settingsConsentDisclosure');

/// The Gemini API key field (architecture.md D17), shown on iOS and
/// Android only.
const Key apiKeyFieldKey = Key('settingsApiKeyField');

/// The "Save key" button beside [apiKeyFieldKey].
const Key apiKeySaveKey = Key('settingsApiKeySave');

/// The "Remove key" button, shown only while a key is saved.
const Key apiKeyDeleteKey = Key('settingsApiKeyDelete');

/// The About section's version row (issue #258), showing the version and
/// build number once [AppInfo.load] answers.
const Key aboutVersionKey = Key('settingsAboutVersion');

/// The About section's "Open-source licences" row (issue #258).
const Key aboutLicencesKey = Key('settingsAboutLicences');

/// The About section's collapsed privacy disclosure (issue #258).
const Key aboutPrivacyKey = Key('settingsAboutPrivacy');

/// The About section's "Report a problem" row (issue #258).
const Key aboutReportKey = Key('settingsAboutReport');

/// The "My restrictions" section's "Add restriction" button (Banto,
/// ALG-02a, issue #344), shown only when `bantoMode` is on.
const Key restrictionsAddKey = Key('settingsRestrictionsAdd');

/// The "My restrictions" section's empty-state line.
const Key restrictionsEmptyKey = Key('settingsRestrictionsEmpty');

/// The row of [id] in the "My restrictions" section.
Key restrictionRowKey(RestrictionId id) =>
    ValueKey<String>('settingsRestrictionRow_${id.name}');

/// The remove button of [id]'s row in the "My restrictions" section.
Key restrictionRemoveKey(RestrictionId id) =>
    ValueKey<String>('settingsRestrictionRemove_${id.name}');

/// The row of [term], one of the user's own words (ALG-17), in the "My
/// restrictions" section.
Key ownTermRowKey(String term) => ValueKey<String>('settingsOwnTermRow_$term');

/// The remove button of [term]'s row in the "My restrictions" section.
Key ownTermRemoveKey(String term) =>
    ValueKey<String>('settingsOwnTermRemove_$term');

/// Where "Report a problem" sends the user: the repository's issue tracker.
final Uri reportProblemUri = Uri.parse(
  'https://github.com/NoaMcDa/KetoClub/issues',
);

/// The Settings screen, top to bottom (issue #255): the UI language, the
/// appearance, the "Your keto rules" dietary toggles, the net-carb limit,
/// the default menu filter, "AI & privacy" (the AI-analysis consent
/// checkbox under its collapsed disclosure, and the user's Gemini API key
/// on iOS and Android), the recent-menus cache and its clearing
/// (architecture.md §6.6, §11, §12, §13, D17), and last an "About" group
/// (issue #258): the app version, the open-source licences, the privacy
/// text and where to report a problem.
///
/// With [bantoMode] on (architecture.md D26) a "My restrictions" section
/// sits between the appearance and "Your keto rules" (ALG-02a, issue #344);
/// with it off — every KetoClub build — the screen is unchanged.
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
  /// Creates the Settings screen. [appInfo] supplies the About section's
  /// version, read once after the first frame; [externalLinkOpener] opens
  /// its "Report a problem" link outside the app. [backendConfigured] is
  /// true when the build has a KetoClub backend, which on a phone changes
  /// the consent text: dish text goes to the server first and the user's
  /// own key is only the fallback (issue #330).
  const new({
    required this.appInfo,
    required this.externalLinkOpener,
    this.backendConfigured = false,
    this.bantoMode = BantoMode.enabled,
    this.screenBrightness = const NoOpScreenBrightness(),
    this.menuSharer,
    super.key,
  });

  /// Reads the app's version and build number (issue #258).
  final AppInfo appInfo;

  /// Opens the issue tracker link outside KetoClub (issue #258).
  final ExternalLinkOpener externalLinkOpener;

  /// Whether this build has a KetoClub backend (issue #330). Only read on
  /// a phone, where it picks between the direct and via-backend consent
  /// text and the key section's note (issue #331).
  final bool backendConfigured;

  /// Whether the Banto surfaces show (architecture.md D26): today, the
  /// "My restrictions" section. Defaults to the build's flag; a test
  /// passes either value with no `--dart-define`.
  final bool bantoMode;

  /// Raised while the chef card opened from the "My restrictions" section
  /// is on screen (ALG-08a, issue #350). Only used with [bantoMode] on.
  final ScreenBrightness screenBrightness;

  /// Shares the chef card as text; null leaves its Share button out. Only
  /// used with [bantoMode] on.
  final MenuSharer? menuSharer;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Whether [SettingsController.clearCache] has completed since this
  /// screen was built, so [AppLocalizations.settingsCacheCleared] can be
  /// shown once. Local UI state, not part of [SettingsController]: the
  /// controller has no notion of "just cleared", only of being busy.
  bool _cacheCleared = false;

  /// The Gemini API key as the user types it. Never prefilled from the
  /// controller, which exposes only [SettingsController.hasApiKey], and
  /// cleared once a save completes, so a typed key does not linger on
  /// screen after it is stored.
  final TextEditingController _apiKeyField = TextEditingController();

  /// The app version, null until [AppInfo.load] answers or when it cannot.
  AppVersion? _version;

  @override
  void dispose() {
    _apiKeyField.dispose();
    super.dispose();
  }

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
      unawaited(_loadVersion());
    });
  }

  /// Reads the version after the first frame (issue #258), never from a
  /// constructor, so building this screen performs no plugin I/O.
  Future<void> _loadVersion() async {
    final version = await widget.appInfo.load();
    if (!mounted) return;
    setState(() => _version = version);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.watch<SettingsController>();
    // Banto Premium (ALG-18): only in a Banto build that sells it, so never
    // on web and never in KetoClub.
    final premium = Provider.of<PremiumController?>(context, listen: false);
    final sellsPremium = widget.bantoMode && (premium?.sellsPremium ?? false);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      // A plain Column, not a lazy ListView: this screen is short and
      // every section must exist in the tree up front so a test (or a
      // screen reader) can find a control without first scrolling it
      // into the sliver viewport's cache extent.
      body: ContentWidth(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            // The order of issue #255 (`docs/UX_REVIEW.md` §2.6): the
            // settings most people open this screen for come first, the
            // privacy text — once the first thing on the page — sits in
            // its own "AI & privacy" section further down, collapsed.
            children: [
              _languageSection(context, l10n, controller),
              const SizedBox(height: 20),
              _appearanceSection(context, l10n, controller),
              const SizedBox(height: 20),
              if (widget.bantoMode) ...[
                _restrictionsSection(context, l10n, controller),
                const SizedBox(height: 20),
                _profilesSection(l10n),
                const SizedBox(height: 20),
                _tripSection(l10n),
                const SizedBox(height: 20),
                if (sellsPremium) ...[
                  _premiumSection(l10n),
                  const SizedBox(height: 20),
                ],
              ],
              _ketoRulesSection(context, l10n, controller),
              const SizedBox(height: 20),
              _netCarbLimitSection(context, l10n, controller),
              const SizedBox(height: 20),
              _filterSection(context, l10n, controller),
              const SizedBox(height: 20),
              _consentSection(context, l10n, controller),
              if (controller.supportsApiKey) ...[
                const SizedBox(height: 12),
                _apiKeySection(context, l10n, controller),
              ],
              const SizedBox(height: 20),
              _cacheSection(context, l10n, controller),
              const SizedBox(height: 20),
              _aboutSection(context, l10n, controller),
            ],
          ),
        ),
      ),
    );
  }

  /// The "About" group (issue #258), last on the screen: the version and
  /// build, the open-source licences (Flutter's own licence page, which
  /// also lists the font licence `main.dart` registers), the privacy text
  /// — the consent section's own copy, behind a collapsed disclosure — and
  /// a link to the issue tracker.
  Widget _aboutSection(
    BuildContext context,
    AppLocalizations l10n,
    SettingsController controller,
  ) {
    final version = _version;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(l10n.settingsAboutSection),
        _SettingsGroup(
          children: [
            ListTile(
              key: aboutVersionKey,
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.settingsAboutVersion),
              subtitle: version == null
                  ? null
                  : Text(
                      l10n.settingsAboutVersionValue(
                        version.version,
                        version.buildNumber,
                      ),
                    ),
            ),
            ListTile(
              key: aboutLicencesKey,
              leading: const Icon(Icons.description_outlined),
              title: Text(l10n.settingsAboutLicences),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(context: context),
            ),
            ExpansionTile(
              key: aboutPrivacyKey,
              shape: const Border(),
              collapsedShape: const Border(),
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(l10n.settingsAboutPrivacy),
              children: [
                _GroupNote(_consentBody(l10n, controller)),
                if (widget.bantoMode) _GroupNote(l10n.whatLeavesDeviceBanto),
                if (_sharesConfirmations(controller))
                  _GroupNote(l10n.whatLeavesDeviceSharedConfirmations),
              ],
            ),
            ListTile(
              key: aboutReportKey,
              leading: const Icon(Icons.bug_report_outlined),
              title: Text(l10n.settingsAboutReport),
              subtitle: Text(l10n.settingsAboutReportHint),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => unawaited(_openReport(context, l10n)),
            ),
          ],
        ),
      ],
    );
  }

  /// The consent text for this build: through KetoClub's server first with
  /// the user's own key as the fallback on a phone with a backend (issue
  /// #330), straight to Google on a phone without one (D17), through
  /// KetoClub's server on web (D12).
  String _consentBody(AppLocalizations l10n, SettingsController controller) {
    if (!controller.supportsApiKey) return l10n.settingsConsentBody;
    return widget.backendConfigured
        ? l10n.settingsConsentBodyDirectViaBackend
        : l10n.settingsConsentBodyDirect;
  }

  /// Opens [reportProblemUri] outside the app; says so when the platform
  /// had no handler for it.
  Future<void> _openReport(BuildContext context, AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await widget.externalLinkOpener.open(reportProblemUri);
    if (opened || !mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.settingsAboutLinkFailed)),
    );
  }

  /// The "AI & privacy" section's consent group (architecture.md §11, D16
  /// issue #167, issue #255): a "What leaves this device" disclosure,
  /// collapsed by default, over the same body text the consent-disclosure
  /// banner (`ConsentDisclosureBanner`) shows once on Explore, and below
  /// it the "Allow AI analysis" checkbox, which is always visible —
  /// collapsing the explanation never hides the choice. The checkbox
  /// starts ticked on a fresh install — AI analysis is on by default
  /// (D16). Unticking it here sets consent to false and stops any dish
  /// text from leaving the device. Where dish text goes depends on the
  /// build: straight to Google with the user's key on iOS and Android
  /// (D17), through KetoClub's server on web (D12) — so the disclosure
  /// follows [SettingsController.supportsApiKey].
  ///
  /// In a Banto build with a backend, a second toggle, off by default,
  /// shares what the staff told the user after a meal (ALG-14, issue
  /// #409), and the disclosure names it while it is on.
  Widget _consentSection(
    BuildContext context,
    AppLocalizations l10n,
    SettingsController controller,
  ) {
    final busy = controller.isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(l10n.settingsAiPrivacy),
        _SettingsGroup(
          children: [
            // Inside a grouped card the expansion tile's default top and
            // bottom divider lines would double the card's own edge.
            ExpansionTile(
              key: consentDisclosureKey,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(
                l10n.settingsConsentTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              children: [
                _GroupNote(_consentBody(l10n, controller)),
                // What of the profile leaves the device: nothing but the
                // flag that asks for ingredients (D26 C1, ALG-11).
                if (widget.bantoMode)
                  _GroupNote(
                    l10n.whatLeavesDeviceBanto,
                    key: consentBantoNoteKey,
                  ),
                // Named while the user shares post-meal answers (#409).
                if (_sharesConfirmations(controller))
                  _GroupNote(
                    l10n.whatLeavesDeviceSharedConfirmations,
                    key: consentSharedNoteKey,
                  ),
              ],
            ),
            CheckboxListTile(
              controlAffinity: ListTileControlAffinity.leading,
              value: controller.consentGiven,
              onChanged: busy
                  ? null
                  : (given) =>
                        unawaited(controller.setConsent(given: given ?? false)),
              title: Text(l10n.settingsConsentAccept),
            ),
            // A consent of its own, off by default (ALG-14, issue #409),
            // offered only where there is a server to share with.
            if (widget.bantoMode && widget.backendConfigured)
              SwitchListTile(
                key: shareConfirmationsToggleKey,
                value: controller.shareConfirmations,
                onChanged: busy
                    ? null
                    : (enabled) => unawaited(
                        controller.setShareConfirmations(enabled: enabled),
                      ),
                title: Text(l10n.settingsShareConfirmations),
                subtitle: Text(l10n.settingsShareConfirmationsBody),
              ),
          ],
        ),
      ],
    );
  }

  /// Whether the disclosures name the shared post-meal answers: a Banto
  /// build with a backend whose user turned sharing on (issue #409).
  bool _sharesConfirmations(SettingsController controller) =>
      widget.bantoMode &&
      widget.backendConfigured &&
      controller.shareConfirmations;

  /// The Gemini API key field, its save and remove actions and the
  /// saved/not-saved status line (architecture.md D17, §11): the second
  /// half of the "AI & privacy" section, under [_consentSection] (issue
  /// #255). Built only when [SettingsController.supportsApiKey] is true.
  ///
  /// The field is [TextField.obscureText] and never prefilled — see
  /// [_apiKeyField].
  Widget _apiKeySection(
    BuildContext context,
    AppLocalizations l10n,
    SettingsController controller,
  ) {
    final busy = controller.isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(l10n.settingsKeySection),
        _SettingsGroup(
          children: [
            // Through the server first with the key as the fallback when
            // the build has a backend (D25, issue #331).
            _GroupNote(
              widget.backendConfigured
                  ? l10n.settingsKeyBodyViaBackend
                  : l10n.settingsKeyBody,
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 4),
              child: TextField(
                key: apiKeyFieldKey,
                controller: _apiKeyField,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !busy,
                decoration: InputDecoration(hintText: l10n.settingsKeyHint),
              ),
            ),
            _GroupNote(
              controller.hasApiKey
                  ? l10n.settingsKeyPresent
                  : l10n.settingsKeyAbsent,
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    key: apiKeySaveKey,
                    onPressed: busy
                        ? null
                        : () => unawaited(_saveApiKey(controller)),
                    child: Text(l10n.settingsKeySave),
                  ),
                  if (controller.hasApiKey)
                    OutlinedButton(
                      key: apiKeyDeleteKey,
                      onPressed: busy
                          ? null
                          : () => unawaited(controller.deleteApiKey()),
                      child: Text(l10n.settingsKeyDelete),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Saves the field's text through [controller], then clears the field —
  /// whether or not the text was blank, since a blank entry is already a
  /// no-op in [SettingsController.saveApiKey] and there is nothing worth
  /// leaving on screen either way.
  Future<void> _saveApiKey(SettingsController controller) async {
    await controller.saveApiKey(_apiKeyField.text);
    if (!mounted) return;
    _apiKeyField.clear();
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
        _ThreeWayControl<String?>(
          key: languageRadioGroupKey,
          selected: controller.languageTag,
          enabled: !busy,
          onChanged: (tag) => unawaited(_setLanguage(context, controller, tag)),
          options: [
            (value: null, label: l10n.settingsLanguageSystem),
            (value: 'en', label: l10n.settingsLanguageEnglish),
            (value: 'he', label: l10n.settingsLanguageHebrew),
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
        _ThreeWayControl<AppThemeMode>(
          key: appearanceRadioGroupKey,
          selected: controller.themeMode,
          enabled: !busy,
          onChanged: (mode) =>
              unawaited(_setThemeMode(context, controller, mode)),
          options: [
            (value: AppThemeMode.system, label: l10n.settingsAppearanceSystem),
            (value: AppThemeMode.light, label: l10n.settingsAppearanceLight),
            (value: AppThemeMode.dark, label: l10n.settingsAppearanceDark),
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

  /// The "My restrictions" section (Banto, ALG-02a, issue #344), built only
  /// when [SettingsScreen.bantoMode] is on: the helper-tool sentence, one
  /// row per restriction in the profile — its name in the UI language, its
  /// kind and a remove button — or a one-line empty state, and an "Add
  /// restriction" button that opens the [RestrictionPickerSheet].
  ///
  /// Keto is not listed here: it stays the "Your keto rules" toggles below.
  /// There is no severity control; a restriction is in the profile or not.
  Widget _restrictionsSection(
    BuildContext context,
    AppLocalizations l10n,
    SettingsController controller,
  ) {
    final busy = controller.isBusy;
    final locale = Localizations.localeOf(context);
    final entries = controller.profile.entries;
    final added = <RestrictionId>{
      for (final entry in entries) entry.restrictionId,
    };
    final canAdd = canAddToProfile(controller.profile);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(l10n.settingsRestrictions),
        _SettingsGroup(
          children: [
            _GroupNote(l10n.helperToolSentence),
            if (entries.isEmpty)
              Padding(
                key: restrictionsEmptyKey,
                padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 4),
                child: Text(
                  l10n.settingsRestrictionsEmpty,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            for (final entry in entries)
              if (entry.restrictionId == RestrictionId.custom)
                for (final term in entry.terms)
                  _ownTermRow(l10n, controller, term)
              else
                _restrictionRow(
                  context,
                  l10n,
                  controller,
                  restrictionFor(entry.restrictionId),
                  locale,
                ),
            if (canAdd)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 4),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: restrictionsAddKey,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.settingsRestrictionsAdd),
                    onPressed: busy
                        ? null
                        : () => unawaited(_pickRestriction(context, added)),
                  ),
                ),
              ),
            if (entries.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 12),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    key: restrictionsChefCardKey,
                    icon: const Icon(Icons.restaurant_menu),
                    label: Text(l10n.chefCardShowButton),
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => ChefCardScreen(
                          profile: controller.profile,
                          screenBrightness: widget.screenBrightness,
                          menuSharer: widget.menuSharer,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// The "People on this device" section (Banto, ALG-12, issue #354),
  /// built only when [SettingsScreen.bantoMode] is on: the health-data
  /// note, then [SettingsProfilesList]'s rows.
  Widget _profilesSection(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionLabel(l10n.settingsProfiles),
      _SettingsGroup(
        children: [
          _GroupNote(l10n.settingsProfilesNote),
          SettingsProfilesList(
            screenBrightness: widget.screenBrightness,
            menuSharer: widget.menuSharer,
          ),
        ],
      ),
    ],
  );

  /// The "Trip mode" section (Banto, ALG-13, issue #355), built only when
  /// [SettingsScreen.bantoMode] is on: its note, then [SettingsTripRows].
  Widget _tripSection(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionLabel(l10n.settingsTrip),
      _SettingsGroup(
        children: [
          _GroupNote(l10n.settingsTripNote),
          SettingsTripRows(
            screenBrightness: widget.screenBrightness,
            menuSharer: widget.menuSharer,
          ),
        ],
      ),
    ],
  );

  /// The "Banto Premium" section (ALG-18, issue #360), built only in a
  /// Banto build that sells Premium: [SettingsPremiumRows].
  Widget _premiumSection(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionLabel(l10n.premiumTitle),
      const _SettingsGroup(children: [SettingsPremiumRows()]),
    ],
  );

  /// One row of the "My restrictions" section: [restriction]'s name in
  /// [locale]'s language, its kind under it, and a remove button.
  Widget _restrictionRow(
    BuildContext context,
    AppLocalizations l10n,
    SettingsController controller,
    Restriction restriction,
    Locale locale,
  ) {
    final name = restrictionDisplayName(restriction, locale);
    return ListTile(
      key: restrictionRowKey(restriction.id),
      title: Text(name),
      subtitle: Text(restrictionKindLabel(l10n, restriction.kind)),
      trailing: IconButton(
        key: restrictionRemoveKey(restriction.id),
        icon: const Icon(Icons.close),
        tooltip: l10n.settingsRestrictionsRemove(name),
        onPressed: controller.isBusy
            ? null
            : () => unawaited(controller.removeRestriction(restriction.id)),
      ),
    );
  }

  /// One of the user's own words (ALG-17) as a row of the "My
  /// restrictions" section: the word as typed, "Your own · checked
  /// strictly" under it, and a remove button for that word alone.
  Widget _ownTermRow(
    AppLocalizations l10n,
    SettingsController controller,
    String term,
  ) => ListTile(
    key: ownTermRowKey(term),
    title: Text(term),
    subtitle: Text(l10n.restrictionOwnRowSubtitle),
    trailing: IconButton(
      key: ownTermRemoveKey(term),
      icon: const Icon(Icons.close),
      tooltip: l10n.settingsRestrictionsRemove(term),
      onPressed: controller.isBusy
          ? null
          : () => unawaited(controller.removeCustomTerm(term)),
    ),
  );

  /// Opens the picker, leaving out [added], and adds what the user picks:
  /// a restriction, or one of their own words (ALG-17). Dismissing the
  /// sheet adds nothing.
  Future<void> _pickRestriction(
    BuildContext context,
    Set<RestrictionId> added,
  ) async {
    final controller = context.read<SettingsController>();
    final picked = await showRestrictionPickerSheet(
      context: context,
      added: added,
    );
    if (picked == null || !mounted) return;
    final term = picked.term;
    final id = picked.id;
    // The free plan keeps one restriction (ALG-18): a second one opens the
    // paywall, and is added only once Premium is active. What is already
    // saved is never touched.
    final adding = term != null ? RestrictionId.custom : id;
    if (adding != null && context.mounted) {
      final allowed = await passPremiumGate(
        context,
        PremiumFeature.restrictions,
        locks: (access) => PremiumGates.locksAddingRestriction(
          access,
          profile: controller.profile,
          adding: adding,
        ),
      );
      if (!allowed || !mounted) return;
    }
    if (term != null) {
      await controller.addCustomTerm(term);
    } else if (id != null) {
      await controller.addRestriction(id);
    }
    // The first restriction of any kind brings the helper-tool sheet, once
    // (ALG-11): marked before it opens, so a swipe away counts as seen.
    if (controller.helperToolSeen || controller.profile.isEmpty) return;
    await controller.markHelperToolSeen();
    if (!context.mounted) return;
    await showHelperToolSheet(context, bantoMode: widget.bantoMode);
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
        // Named after the tab it manages ("Recent", issue #251), so the
        // cache group is no longer the one group without a label (#255).
        _SectionLabel(l10n.settingsCacheSection),
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

/// One option of a [_ThreeWayControl]: the value it stands for and its label.
typedef _ThreeWayOption<T> = ({T value, String label});

/// A single-row segmented control for a short, mutually exclusive choice
/// (issue #256, audit S6): the language and appearance sections, which were
/// three-row radio lists. Styled like the Default filter's control
/// (chip-sized labels, compact density) so the two read as one family, and
/// wrapped in the same sideways scroll that is only the fallback for a
/// narrower screen or a longer translation (the S3 lesson: forced into
/// equal thirds, labels break mid-word).
///
/// [enabled] false (the screen is busy) removes [onChanged], which is how
/// [SegmentedButton] disables itself. A `null` option value is a legitimate
/// selection ("match my device"), so [selected] is passed through as is.
class _ThreeWayControl<T> extends StatelessWidget {
  const new({
    required this.selected,
    required this.options,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  /// The currently chosen option's value.
  final T selected;

  /// The options, in display order.
  final List<_ThreeWayOption<T>> options;

  /// Whether a tap may change the choice.
  final bool enabled;

  /// Called with the newly chosen value.
  final void Function(T value) onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<T>(
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
          for (final option in options)
            ButtonSegment<T>(value: option.value, label: Text(option.label)),
        ],
        selected: <T>{selected},
        onSelectionChanged: enabled
            ? (selection) => onChanged(selection.first)
            : null,
      ),
    );
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
  const new(this.text, {super.key});

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
