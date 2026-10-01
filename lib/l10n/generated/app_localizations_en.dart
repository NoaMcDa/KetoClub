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
  String get actionOpenDrinksGuide => 'Drinks guide';

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
  String get venueSearchOpenLink => 'Open link';

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
      'AI analysis is on by default: when you open or paste a menu, dish names, descriptions and option labels — and any questions you type about a menu — are sent to KetoClub\'s server, which forwards them to Google\'s Gemini API for analysis. Nothing about you or your history is sent otherwise. Your position is sent to Wolt only when you search nearby, and is not stored. There are no analytics. Untick this to keep every menu on this device.';

  @override
  String get settingsConsentAccept => 'Allow AI analysis';

  @override
  String get consentDisclosureOk => 'OK';

  @override
  String get consentDisclosureTurnOff => 'Turn off';

  @override
  String get settingsConsentBodyDirect =>
      'AI analysis is on by default: when you open or paste a menu, dish names, descriptions and option labels — and any questions you type about a menu — are sent straight from this device to Google\'s Gemini API, using your own API key. Nothing about you or your history is sent otherwise. Your position is sent to Wolt only when you search nearby, and is not stored. There are no analytics. Untick this to keep every menu on this device.';

  @override
  String get settingsKeySection => 'Gemini API key';

  @override
  String get settingsKeyBody =>
      'On this phone, AI analysis calls Google\'s Gemini API directly with your own key. You can create one for free in Google AI Studio. It is kept in this device\'s secure storage and sent only to Google.';

  @override
  String get settingsKeyHint => 'Paste your Gemini API key';

  @override
  String get settingsKeySave => 'Save key';

  @override
  String get settingsKeyPresent => 'A key is saved on this device.';

  @override
  String get settingsKeyAbsent =>
      'No key saved. KetoClub will use on-device rules.';

  @override
  String get settingsKeyDelete => 'Remove key';

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
  String get analysisBadResponseNoDetail =>
      'The AI model gave an unusable answer. Showing rule-based results.';

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
  String get analysisApiKeyMissing =>
      'Add your Gemini API key in Settings to analyse this menu. Showing rule-based results.';

  @override
  String get analysisApiKeyRejected =>
      'Gemini rejected your API key. Check it in Settings. Showing rule-based results.';

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
  String get navSaved => 'Recent';

  @override
  String get navSettings => 'Settings';

  @override
  String get savedPlaceholderTitle => 'Recent menus';

  @override
  String get savedPlaceholderBody =>
      'Open a venue\'s menu and it appears here automatically, available for a day — even offline.';

  @override
  String get savedLoading => 'Loading your recent menus…';

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
  String get discoveryOpenSettingsUnavailable =>
      'This device could not open its settings from here. Allow location for KetoClub in your browser\'s or device\'s settings, then try again.';

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
  String get legendEngines =>
      'Rules: KetoClub\'s own keyword checks on the dish text, with no carb estimate. AI: Gemini reads the whole menu and estimates net carbs.';

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
  String get menuFilters => 'Filters';

  @override
  String menuFiltersActive(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Filters · $count active',
      one: 'Filters · 1 active',
    );
    return '$_temp0';
  }

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

  @override
  String get scanTitle => 'Scan a menu';

  @override
  String get scanPasteIntro =>
      'Paste a menu from anywhere, one dish per line. KetoClub reads it the same way it reads a delivery menu.';

  @override
  String get scanPasteLabel => 'Menu text';

  @override
  String get scanPasteHint =>
      'Grilled salmon\nCaesar salad, no croutons\nPasta carbonara';

  @override
  String get scanAnalyse => 'Analyse';

  @override
  String get scanEmptyPaste =>
      'KetoClub found no dishes in that text. Paste the menu with one dish per line.';

  @override
  String get sourceScanned => 'Pasted menu';

  @override
  String get fetchFailedScanNotSaved =>
      'This pasted menu is no longer saved on this device. Paste it again to analyse it.';

  @override
  String get scannedMenuTitle => 'Scanned menu';

  @override
  String get scannedMenuReadByAi => 'Read by AI from your pages';

  @override
  String get scannedMenuViewPages => 'View pages';

  @override
  String get scannedMenuPagesTitle => 'Your pages';

  @override
  String get scannedMenuPagesNote =>
      'Check the dish names against your pages: the AI may misread a word.';

  @override
  String scannedMenuPageLabel(int number) {
    return 'Page $number';
  }

  @override
  String get scannedMenuPdfPage => 'PDF document';

  @override
  String get scannedMenuPagesClose => 'Close';

  @override
  String get scanScreenIntro =>
      'Photograph the pages of a menu, choose photos from your library, or choose a PDF. KetoClub reads the dishes off the pages and analyses them.';

  @override
  String get scanScreenActionTakePhoto => 'Take a photo';

  @override
  String get scanScreenActionChoosePhotos => 'Choose photos';

  @override
  String get scanScreenActionChoosePdf => 'Choose a PDF';

  @override
  String get scanScreenPagesHeading => 'Pages';

  @override
  String scanScreenPageCount(int count, int max) {
    return '$count of $max pages';
  }

  @override
  String get scanScreenCapReached =>
      'That is the most pages one scan can hold. Remove a page to add another.';

  @override
  String scanScreenPageLabel(int number) {
    return 'Page $number';
  }

  @override
  String get scanScreenPdfLabel => 'PDF document';

  @override
  String scanScreenPageSizeKb(int kb) {
    return '$kb KB';
  }

  @override
  String scanScreenRemovePage(int number) {
    return 'Remove page $number';
  }

  @override
  String scanScreenTooManyPages(int max) {
    return 'One scan holds at most $max pages. The pages over the limit were not added.';
  }

  @override
  String scanScreenPageTooLarge(int mb) {
    return 'That page is larger than $mb MB, so it was not added. Try a smaller photo or a smaller PDF.';
  }

  @override
  String get scanScreenAnalysePages => 'Analyse pages';

  @override
  String get scanScreenPasteHeading => 'Or paste the text';

  @override
  String get scanScreenDisclosureWeb =>
      'The pages are sent to KetoClub\'s server, which forwards them to Google\'s Gemini API to be read.';

  @override
  String get scanScreenDisclosureDirect =>
      'The pages are sent straight from this device to Google\'s Gemini API, using your own API key.';

  @override
  String get scanScreenSettingsLink => 'Settings';

  @override
  String get scanScreenFailureNotConfigured =>
      'Scanning is not available on this build.';

  @override
  String get scanScreenFailureNeedsServer =>
      'Scanning needs KetoClub\'s server, and this build is not connected to one. Pasting the menu text still works.';

  @override
  String get scanScreenFailureOffline =>
      'You look offline. Your pages are kept; reconnect and try again.';

  @override
  String get scanScreenFailureTimeout =>
      'The AI model was too slow. Your pages are kept; try again.';

  @override
  String get scanScreenFailureRateLimited =>
      'The daily AI limit is used up. Your pages are kept; try again later.';

  @override
  String get scanScreenFailureBadResponse =>
      'The AI model gave an unusable answer. Your pages are kept; try again.';

  @override
  String get scanScreenFailureNoDishesFound =>
      'No dishes could be read from these pages. Check that the photos are sharp and well lit, or paste the text instead.';

  @override
  String get scanScreenFailureBackendUnreachable =>
      'KetoClub\'s server could not be reached. Your pages are kept; try again.';

  @override
  String get scanScreenFailureConsentWithheld =>
      'Scanning sends the pages to Google\'s Gemini API to be read. Allow AI analysis in Settings to scan a menu.';

  @override
  String get scanScreenFailureApiKeyMissing =>
      'Add your Gemini API key in Settings to scan a menu.';

  @override
  String get scanScreenFailureApiKeyRejected =>
      'Gemini rejected your API key. Check it in Settings, then try again.';

  @override
  String websiteMenuNotFound(String site) {
    return 'KetoClub could not find a menu it can read on $site.';
  }

  @override
  String websiteDisallowedByRobots(String site) {
    return '$site asks apps like KetoClub not to read its pages, so KetoClub does not.';
  }

  @override
  String websiteJsOnlyPage(String site) {
    return '$site only shows its menu with JavaScript, which KetoClub cannot read yet.';
  }

  @override
  String websiteUnreachable(String site) {
    return '$site did not answer. Try again later.';
  }

  @override
  String websiteTooLarge(String site) {
    return 'The menu on $site is too large for KetoClub to read.';
  }

  @override
  String websiteRateLimited(String site) {
    return 'KetoClub read $site a moment ago. Wait a minute, then try again.';
  }

  @override
  String websitePdfUnread(String site) {
    return 'The menu on $site is a PDF, which only AI analysis can read, and it could not be read now. Check AI analysis in Settings, then try again.';
  }

  @override
  String get scanQrAction => 'Scan QR code';

  @override
  String get scanQrTitle => 'Scan QR code';

  @override
  String get scanQrInstruction =>
      'Point the camera at the QR code on the table.';

  @override
  String get scanQrCameraDenied =>
      'KetoClub cannot use the camera. Allow camera access in your device settings, or paste the menu link instead.';

  @override
  String get scanQrCameraUnavailable =>
      'The camera could not start. Close this screen and paste the menu link instead.';

  @override
  String scanQrUnsupportedSource(String name) {
    return '$name menus are not supported yet. Photograph the menu instead.';
  }

  @override
  String get scanQrPhotographInstead =>
      'This QR code does not lead to a menu KetoClub can read. Photograph the menu instead.';

  @override
  String get carbBudgetFieldLabel => 'Budget for tonight (g)';

  @override
  String get carbBudgetFieldHint => 'e.g. 20';

  @override
  String get carbBudgetFieldClear => 'Clear budget';

  @override
  String get carbBudgetDisabledReason =>
      'Set a budget after AI analysis — rule-based results have no carb estimates.';

  @override
  String netCarbsChipLeavesSuffix(int grams) {
    return ' · leaves ${grams}g';
  }

  @override
  String get hiddenCarbsSectionLabel => 'Possible hidden carbs';

  @override
  String get hiddenCarbsCertaintySuspected => 'Suspected';

  @override
  String get hiddenCarbsCertaintyLikely => 'Likely';

  @override
  String get drinksGuideTitle => 'Drinks guide';

  @override
  String get drinksGuideDisclaimer =>
      'Typical net-carb ranges per standard serving. All figures are estimates — actual values vary by brand, size, and recipe.';

  @override
  String get drinksGuideSectionOrderAsIs => 'ORDER AS-IS';

  @override
  String get drinksGuideSectionSwap => 'ASK FOR A SWAP';

  @override
  String get drinksGuideSectionSkip => 'SKIP';

  @override
  String get settingsDrinksGuideTitle => 'DRINKS GUIDE';

  @override
  String get settingsDrinksGuideSubtitle => 'Bar and coffee reference';

  @override
  String get actionAskAboutMenu => 'Ask about this menu';

  @override
  String get menuQuestionSheetTitle => 'Ask about this menu';

  @override
  String get menuQuestionSheetHint => 'e.g. Which dishes are dairy-free?';

  @override
  String get menuQuestionSheetAsk => 'Ask';

  @override
  String get menuQuestionSheetLoading => 'Asking…';

  @override
  String get menuQuestionSheetAskAnother => 'Ask another question';

  @override
  String get menuQuestionFailedNotConfigured =>
      'AI is not available on this build, so the question could not be answered.';

  @override
  String get menuQuestionFailedOffline =>
      'You look offline. Reconnect and try asking again.';

  @override
  String get menuQuestionFailedTimeout =>
      'The AI model was too slow. Try asking again.';

  @override
  String get menuQuestionFailedRateLimited =>
      'The daily AI limit is used up. Try again later.';

  @override
  String get menuQuestionFailedBadResponse =>
      'The AI gave an unusable answer. Try asking in a different way.';

  @override
  String get menuQuestionFailedBackendUnreachable =>
      'KetoClub\'s server could not be reached. Try asking again.';

  @override
  String get menuQuestionFailedConsentWithheld =>
      'Allow AI analysis in Settings to ask questions about a menu.';

  @override
  String get menuQuestionFailedApiKeyMissing =>
      'Add your Gemini API key in Settings to ask questions about a menu.';

  @override
  String get menuQuestionFailedApiKeyRejected =>
      'Gemini rejected your API key. Check it in Settings, then try asking again.';
}
