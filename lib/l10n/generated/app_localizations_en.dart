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
  String get actionRefreshMenu => 'Refresh menu';

  @override
  String get actionBackToSearch => 'Back to search';

  @override
  String get offlineBannerMessage => 'No internet connection.';

  @override
  String get actionShareMenu => 'Share menu';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get venueSearchLabel => 'Find a restaurant';

  @override
  String get venueSearchHint => 'Search by name, or paste a Wolt link';

  @override
  String get venueSearchInvalid =>
      'KetoClub cannot read a menu from that yet. Paste a Wolt restaurant link or its slug.';

  @override
  String get venueSearchOpen => 'Show the keto menu';

  @override
  String venueSearchContinueWith(String venue) {
    return 'Continue with $venue';
  }

  @override
  String get menuLoading => 'Reading the menu…';

  @override
  String get menuEmpty => 'This menu has no dishes.';

  @override
  String get menuProgressAnalysing => 'Analysing the menu…';

  @override
  String get menuProgressAskingAi => 'Asking the AI…';

  @override
  String get menuProgressApplyingRules => 'Applying the rules…';

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
  String get settingsConsentTitle => 'What leaves this device';

  @override
  String get settingsConsentBody =>
      'When you allow AI analysis, dish names, descriptions and option labels from the menu you open are sent to KetoClub\'s server, which forwards them to Google\'s Gemini API for analysis. Nothing about you or your history is sent otherwise. Your position is sent to Wolt only when you search nearby, and is not stored. There are no analytics.';

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
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsAppearanceSystem => 'Follow device theme';

  @override
  String get settingsAppearanceLight => 'Light';

  @override
  String get settingsAppearanceDark => 'Dark';

  @override
  String get settingsNetCarbLimit => 'Net carb limit';

  @override
  String get settingsNetCarbLimitBody =>
      'Dishes above this are never green. Changing it re-analyses the next menu you open.';

  @override
  String settingsNetCarbLimitValue(int grams) {
    return '$grams g';
  }

  @override
  String get settingsNetCarbLimitDecrease => 'Lower the net carb limit';

  @override
  String get settingsNetCarbLimitIncrease => 'Raise the net carb limit';

  @override
  String get settingsKetoRules => 'Your keto rules';

  @override
  String get settingsKetoRulesBody =>
      'Each rule you turn on applies from the next menu you open.';

  @override
  String get settingsSeedOilFree => 'Strict seed-oil free';

  @override
  String get settingsSeedOilFreeHint =>
      'Flags canola, sunflower and soybean oil in fried dishes.';

  @override
  String get settingsDairyFree => 'Dairy-free keto';

  @override
  String get settingsDairyFreeHint =>
      'Treats cream, butter and cheese as a modification.';

  @override
  String get settingsCarnivoreOnly => 'Carnivore only';

  @override
  String get settingsCarnivoreOnlyHint =>
      'Greens only meat, fish, eggs — vegetables become yellow.';

  @override
  String get settingsFilter => 'Default filter';

  @override
  String settingsCacheSummary(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count menus cached · works offline',
      one: '1 menu cached · works offline',
    );
    return '$_temp0';
  }

  @override
  String get settingsClearCache => 'Clear saved menus';

  @override
  String get settingsClearCacheConfirmTitle => 'Clear saved menus?';

  @override
  String get settingsClearCacheConfirmBody =>
      'This removes every menu saved on this device, including any you can currently open offline. You can save a venue again by opening it once you have a connection.';

  @override
  String get settingsClearCacheConfirmAction => 'Clear';

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
  String get fetchFailedBackendUnreachable =>
      'KetoClub\'s server could not be reached, so the menu could not be read.';

  @override
  String get venueSearchFailedOffline =>
      'No connection, so KetoClub could not search for restaurants.';

  @override
  String get venueSearchFailedTimeout =>
      'Wolt took too long to answer the search. Try again in a moment.';

  @override
  String get venueSearchFailedRateLimited =>
      'Too many searches in a row. Wait a minute, then try again.';

  @override
  String get venueSearchFailedPlatformChanged =>
      'Wolt changed how its restaurant search works, so KetoClub could not read the results. Please report this.';

  @override
  String get venueSearchFailedBlockedByBrowser =>
      'A web browser cannot search Wolt directly. Use the KetoClub phone app, or paste a Wolt link instead.';

  @override
  String get venueSearchFailedBackendUnreachable =>
      'KetoClub\'s server could not be reached, so the search could not run.';

  @override
  String get analysisNotConfigured =>
      'AI analysis is not available on this build or server. Showing rule-based results.';

  @override
  String get analysisOffline => 'Offline. Showing rule-based results.';

  @override
  String get analysisTimeout =>
      'The AI model was too slow. Showing rule-based results.';

  @override
  String get analysisRateLimited =>
      'The daily AI limit is used up. Showing rule-based results.';

  @override
  String analysisBadResponse(String detail) {
    return 'AI analysis failed ($detail). Showing rule-based results.';
  }

  @override
  String get analysisNoDishesFound =>
      'The AI could not identify any dishes on this menu.';

  @override
  String get analysisBackendUnreachable =>
      'KetoClub\'s server could not be reached. Showing rule-based results.';

  @override
  String get analysisConsentWithheld =>
      'Allow AI analysis in Settings to analyse this menu. Showing rule-based results.';

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
  String get engineChipReasonNotConfigured => 'not configured';

  @override
  String get engineChipReasonOffline => 'offline';

  @override
  String get engineChipReasonTimeout => 'timeout';

  @override
  String get engineChipReasonRateLimited => 'rate limited';

  @override
  String get engineChipReasonBadResponse => 'AI error';

  @override
  String get engineChipReasonNoDishesFound => 'no dishes found';

  @override
  String get engineChipReasonBackendUnreachable => 'server unreachable';

  @override
  String get engineChipReasonConsentWithheld => 'AI not allowed';

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
      'Open a venue\'s menu and it appears here automatically, available for a day — even offline.';

  @override
  String get savedLoading => 'Loading your saved menus…';

  @override
  String savedEntryDishCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dishes',
      one: '1 dish',
    );
    return '$_temp0';
  }

  @override
  String get savedRemove => 'Remove';

  @override
  String savedRemoveSemanticLabel(String venue) {
    return 'Remove $venue';
  }

  @override
  String savedRemovedMessage(String venue) {
    return 'Removed $venue.';
  }

  @override
  String get savedUndo => 'Undo';

  @override
  String get discoveryTitle => 'Where to eat';

  @override
  String get discoveryEmptyTitle => 'Find somewhere to eat';

  @override
  String get discoveryEmptyBody =>
      'Use your location to see restaurants nearby, search by name, or paste a Wolt link above to open its keto-classified menu.';

  @override
  String get discoveryLookingAround => 'Looking around';

  @override
  String get discoveryAroundYou => 'Your location';

  @override
  String get discoveryLocationNotSet => 'Location not set';

  @override
  String get discoveryUseLocation => 'Use my location';

  @override
  String get discoveryChipNearby => 'Nearby';

  @override
  String get discoveryChipKetoEightPlus => 'Keto 8+';

  @override
  String get discoveryChipOpenNow => 'Open now';

  @override
  String get discoveryLocating => 'Finding your location…';

  @override
  String get discoverySearching => 'Looking for restaurants…';

  @override
  String get discoveryLocationDeniedTitle => 'Location is off for KetoClub';

  @override
  String get discoveryLocationDeniedBody =>
      'Allow location to see restaurants near you, or search by name instead.';

  @override
  String get discoveryLocationDeniedForeverBody =>
      'Location access is turned off for KetoClub. You can turn it back on in your device\'s settings, or search by name instead.';

  @override
  String get discoveryLocationUnavailableTitle =>
      'Could not find your location';

  @override
  String get discoveryLocationServicesOff =>
      'Your device\'s location is turned off. Turn it on and try again, or search by name instead.';

  @override
  String get discoveryLocationInsecureContext =>
      'This page cannot ask for your location because it is not on a secure (https) connection. Search by name instead.';

  @override
  String get discoveryLocationTimeout =>
      'Finding your location took too long. Try again, or search by name instead.';

  @override
  String get discoveryLocationUnsupported =>
      'This device could not provide a location. Search by name instead.';

  @override
  String get discoveryTypeNameInstead => 'Type a name instead';

  @override
  String get discoveryOpenSettings => 'Open Settings';

  @override
  String get discoveryTurnOnLocation => 'Turn on location';

  @override
  String get discoveryNoResultsTitle => 'No restaurants found';

  @override
  String get discoveryNoResultsBody =>
      'Try a different name, or clear the search.';

  @override
  String get discoveryClearSearch => 'Clear search';

  @override
  String get discoveryNoChipResults =>
      'No restaurant in this list matches that filter.';

  @override
  String get discoveryEstimateList => 'Estimate this list';

  @override
  String get discoveryEstimateHint =>
      'Reads each menu on this list once and scores it with the on-device rules, not the AI. Open a restaurant for the full analysis.';

  @override
  String discoveryEstimating(int done, int total) {
    return 'Estimating $done of $total…';
  }

  @override
  String get venueCardOpenNow => 'Open now';

  @override
  String get venueCardClosed => 'Closed';

  @override
  String venueCardMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String venueCardWalkMinutes(int minutes) {
    return '$minutes min walk';
  }

  @override
  String venueCardGreenCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dishes as-is',
      one: '1 dish as-is',
    );
    return '$_temp0';
  }

  @override
  String venueCardYellowCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count with changes',
      one: '1 with changes',
    );
    return '$_temp0';
  }

  @override
  String get menuKetoScoreLabel => 'Keto score';

  @override
  String menuKetoScoreSemanticLabel(String score) {
    return 'Keto score: $score out of 10';
  }

  @override
  String menuSourceLine(String platform, String age) {
    return '$platform · $age';
  }

  @override
  String menuOpenOnPlatform(String platform) {
    return 'Open on $platform';
  }

  @override
  String menuShowingAll(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Showing $count dishes',
      one: 'Showing 1 dish',
    );
    return '$_temp0';
  }

  @override
  String get menuShowingGreen => 'Showing dishes you can order as-is';

  @override
  String get menuShowingYellow => 'Showing dishes that need a change';

  @override
  String get menuShowingRed => 'Showing what to skip';

  @override
  String get menuShowingGreenAndYellow =>
      'Showing dishes you can order as-is or with a change';

  @override
  String get tileGreenLabel => 'Order as-is';

  @override
  String get tileYellowLabel => 'With changes';

  @override
  String get tileRedLabel => 'Skip';

  @override
  String tileSemanticLabel(String label, int count) {
    return '$label: $count';
  }

  @override
  String get tileSemanticHintFilter => 'Double tap to filter';

  @override
  String get tileSemanticHintClear => 'Double tap to clear the filter';

  @override
  String get ageJustNow => 'Just now';

  @override
  String ageMinutes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String ageHours(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String ageDays(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get legendToggle => 'What do the colours mean?';

  @override
  String get legendHide => 'Hide the legend';

  @override
  String get legendNote => 'The same rules KetoClub sends to the AI model.';

  @override
  String get waiterCardCopyButton => 'Copy text';

  @override
  String waiterCardAfterText(String grams) {
    return 'With these changes, about ${grams}g net carbs (estimate) — safe to order.';
  }

  @override
  String get dishCardAddNote => 'Add a note';

  @override
  String dishCardEditNoteSemanticLabel(String note) {
    return 'Edit your note: $note';
  }

  @override
  String get noteEditorTitle => 'Personal note';

  @override
  String get noteEditorHint => 'e.g. Waitstaff happily substituted cauliflower';

  @override
  String get noteEditorSave => 'Save';

  @override
  String get noteEditorClear => 'Clear note';

  @override
  String get menuSearchHint => 'Search dishes';

  @override
  String get menuSearchSemanticLabel => 'Search dishes by name or description';

  @override
  String get menuSearchClear => 'Clear search';

  @override
  String get menuNoResults => 'No dishes match your search.';

  @override
  String get menuClearFilter => 'Clear filter';

  @override
  String categoryChipSemanticLabel(String category) {
    return 'Jump to $category';
  }
}
