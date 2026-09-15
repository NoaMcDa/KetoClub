// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settingsTitle => 'Settings';

  @override
  String get actionRetry => 'Try again';

  @override
  String get actionReport => 'Report this';

  @override
  String get actionOpenSettings => 'Open Settings';

  @override
  String get actionCopy => 'Copy';

  @override
  String get actionCopied => 'Copied';

  @override
  String get venueSearchLabel => 'Restaurant link';

  @override
  String get venueSearchHint => 'Paste a Wolt link, or a venue slug';

  @override
  String get venueSearchInvalid =>
      'KetoClub cannot read a menu from that yet. Paste a Wolt restaurant link or its slug.';

  @override
  String get venueSearchOpen => 'Show the keto menu';

  @override
  String get menuLoading => 'Reading the menu…';

  @override
  String get menuEmpty => 'This menu has no dishes.';

  @override
  String get filterGreenOnly => 'Order as-is only';

  @override
  String get filterGreenAndYellow => 'As-is and with changes';

  @override
  String get filterAll => 'Everything';

  @override
  String redGroupTitle(int count) {
    return 'Not keto ($count)';
  }

  @override
  String unclassifiedTitle(int count) {
    return 'Not read ($count)';
  }

  @override
  String get unclassifiedExplain =>
      'KetoClub saw these dishes but could not place them. Read them yourself before ordering.';

  @override
  String get engineChipAi => 'AI';

  @override
  String get engineChipRules => 'Rules';

  @override
  String get rulesNotVerifiedHint => 'Rule-based result, not AI-verified.';

  @override
  String cachedFrom(String date) {
    return 'Showing the menu saved on $date.';
  }

  @override
  String get verdictOrderAsIs => 'Order as-is';

  @override
  String get verdictModifiable => 'Order with a change';

  @override
  String get verdictNonKeto => 'Not keto';

  @override
  String get waiterCardOpen => 'Show the waiter card';

  @override
  String get waiterCardTitle => 'Say this to the waiter';

  @override
  String get settingsKeySection => 'OpenRouter key';

  @override
  String get settingsKeyHint => 'Paste your OpenRouter key';

  @override
  String get settingsKeySave => 'Save key';

  @override
  String get settingsKeyPresent => 'A key is stored on this device.';

  @override
  String get settingsKeyAbsent =>
      'No key stored. KetoClub will use on-device rules.';

  @override
  String get settingsKeyDelete => 'Remove key';

  @override
  String get settingsWebStorageNote =>
      'On the web the key is kept in browser storage, which protects it less well than a phone\'s keychain.';

  @override
  String get settingsConsentTitle => 'What leaves this device';

  @override
  String get settingsConsentBody =>
      'With a key, dish names, descriptions and option labels from the menu you open are sent to OpenRouter for analysis. Nothing about you, your location or your history is sent. Menus are read straight from the restaurant platform, which receives only the venue identifier. There is no other server and no analytics.';

  @override
  String get settingsConsentAccept => 'I understand';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'Match my device';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageHebrew => 'Hebrew';

  @override
  String get settingsFilter => 'Default filter';

  @override
  String get settingsClearCache => 'Clear saved menus';

  @override
  String get settingsCacheCleared => 'Saved menus cleared.';

  @override
  String get fetchFailedOffline =>
      'No connection, so the menu could not be read.';

  @override
  String fetchFailedBlockedByBrowser(String platform) {
    return 'A web browser cannot read $platform menus: $platform blocks requests from other websites. Open this link in the KetoClub phone app instead.';
  }

  @override
  String fetchFailedNotFound(String platform) {
    return 'No venue found on $platform. Check the link.';
  }

  @override
  String fetchFailedPlatformChanged(String platform, String statusCode) {
    return '$platform changed its menu format (HTTP $statusCode), so KetoClub could not read it. Please report this.';
  }

  @override
  String get fetchFailedUnsupportedSource =>
      'KetoClub cannot read menus from that site yet.';

  @override
  String get analysisNotConfigured =>
      'Add an OpenRouter key in Settings for AI analysis.';

  @override
  String get analysisOffline => 'Offline. Showing rule-based results.';

  @override
  String get analysisTimeout =>
      'The AI model was too slow. Showing rule-based results.';

  @override
  String get analysisRateLimited =>
      'The daily AI limit for this key is used up. Showing rule-based results.';

  @override
  String get analysisUnauthorised =>
      'OpenRouter rejected your key, so nothing was analysed.';

  @override
  String analysisBadResponse(String detail) {
    return 'AI analysis failed ($detail). Showing rule-based results.';
  }

  @override
  String get analysisNoDishesFound =>
      'The AI could not identify any dishes on this menu.';

  @override
  String pillSemanticLabel(String verdict) {
    return 'Verdict: $verdict';
  }

  @override
  String get dishCardAskWaiter => 'Ask your waiter';

  @override
  String get dishCardHideScript => 'Hide the waiter script';

  @override
  String get dishCardScriptFallback =>
      'Ask your waiter about a keto-friendly substitution.';

  @override
  String netCarbsChipLabel(String grams) {
    return '~${grams}g net carbs (estimate)';
  }

  @override
  String netCarbsChipSemanticLabel(String grams) {
    return 'Estimated net carbs, not confirmed: $grams grams';
  }

  @override
  String engineChipAiSemanticLabel(String model) {
    return 'AI engine, model $model';
  }

  @override
  String engineChipRulesSemanticLabel(String reason) {
    return 'Rules engine, not AI-verified: $reason';
  }

  @override
  String get engineChipReasonNotConfigured => 'no key';

  @override
  String get engineChipReasonOffline => 'offline';

  @override
  String get engineChipReasonTimeout => 'timeout';

  @override
  String get engineChipReasonRateLimited => 'rate limited';

  @override
  String get engineChipReasonUnauthorised => 'key rejected';

  @override
  String get engineChipReasonBadResponse => 'AI error';

  @override
  String get engineChipReasonNoDishesFound => 'no dishes found';

  @override
  String get navExplore => 'Explore';

  @override
  String get navScan => 'Scan';

  @override
  String get navSaved => 'Saved';

  @override
  String get navSettings => 'Settings';

  @override
  String get scanPlaceholderTitle => 'Scan a menu';

  @override
  String get scanPlaceholderBody =>
      'Photographing a physical menu is coming in a later update. For now, paste a delivery link on Explore.';

  @override
  String get savedPlaceholderTitle => 'Saved venues';

  @override
  String get savedPlaceholderBody =>
      'Save a venue to find it here later. This is coming in a later update.';

  @override
  String get waiterCardCopyButton => 'Copy text';

  @override
  String waiterCardAfterText(String grams) {
    return 'With these changes, about ${grams}g net carbs (estimate) — safe to order.';
  }
}
