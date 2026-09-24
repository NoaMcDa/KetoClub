import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_he.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('he'),
  ];

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionRetry;

  /// No description provided for @actionReport.
  ///
  /// In en, this message translates to:
  /// **'Report this'**
  String get actionReport;

  /// No description provided for @actionOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get actionOpenSettings;

  /// No description provided for @actionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// No description provided for @actionCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get actionCopied;

  /// No description provided for @actionRefreshMenu.
  ///
  /// In en, this message translates to:
  /// **'Refresh menu'**
  String get actionRefreshMenu;

  /// No description provided for @actionBackToSearch.
  ///
  /// In en, this message translates to:
  /// **'Back to search'**
  String get actionBackToSearch;

  /// No description provided for @offlineBannerMessage.
  ///
  /// In en, this message translates to:
  /// **'No internet connection.'**
  String get offlineBannerMessage;

  /// No description provided for @actionShareMenu.
  ///
  /// In en, this message translates to:
  /// **'Share menu'**
  String get actionShareMenu;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @venueSearchLabel.
  ///
  /// In en, this message translates to:
  /// **'Find a restaurant'**
  String get venueSearchLabel;

  /// No description provided for @venueSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name, or paste a Wolt link'**
  String get venueSearchHint;

  /// No description provided for @venueSearchInvalid.
  ///
  /// In en, this message translates to:
  /// **'KetoClub cannot read a menu from that yet. Paste a Wolt restaurant link or its slug.'**
  String get venueSearchInvalid;

  /// No description provided for @venueSearchOpen.
  ///
  /// In en, this message translates to:
  /// **'Show the keto menu'**
  String get venueSearchOpen;

  /// No description provided for @venueSearchContinueWith.
  ///
  /// In en, this message translates to:
  /// **'Continue with {venue}'**
  String venueSearchContinueWith(String venue);

  /// No description provided for @menuLoading.
  ///
  /// In en, this message translates to:
  /// **'Reading the menu…'**
  String get menuLoading;

  /// No description provided for @menuEmpty.
  ///
  /// In en, this message translates to:
  /// **'This menu has no dishes.'**
  String get menuEmpty;

  /// No description provided for @menuProgressAnalysing.
  ///
  /// In en, this message translates to:
  /// **'Analysing the menu…'**
  String get menuProgressAnalysing;

  /// No description provided for @menuProgressAskingAi.
  ///
  /// In en, this message translates to:
  /// **'Asking the AI…'**
  String get menuProgressAskingAi;

  /// No description provided for @menuProgressApplyingRules.
  ///
  /// In en, this message translates to:
  /// **'Applying the rules…'**
  String get menuProgressApplyingRules;

  /// No description provided for @filterGreenOnly.
  ///
  /// In en, this message translates to:
  /// **'Order as-is only'**
  String get filterGreenOnly;

  /// No description provided for @filterGreenAndYellow.
  ///
  /// In en, this message translates to:
  /// **'As-is and with changes'**
  String get filterGreenAndYellow;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'Everything'**
  String get filterAll;

  /// No description provided for @redGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Not keto ({count})'**
  String redGroupTitle(int count);

  /// No description provided for @unclassifiedTitle.
  ///
  /// In en, this message translates to:
  /// **'Not read ({count})'**
  String unclassifiedTitle(int count);

  /// No description provided for @unclassifiedExplain.
  ///
  /// In en, this message translates to:
  /// **'KetoClub saw these dishes but could not place them. Read them yourself before ordering.'**
  String get unclassifiedExplain;

  /// No description provided for @engineChipAi.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get engineChipAi;

  /// No description provided for @engineChipRules.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get engineChipRules;

  /// No description provided for @rulesNotVerifiedHint.
  ///
  /// In en, this message translates to:
  /// **'Rule-based result, not AI-verified.'**
  String get rulesNotVerifiedHint;

  /// No description provided for @cachedFrom.
  ///
  /// In en, this message translates to:
  /// **'Showing the menu saved on {date}.'**
  String cachedFrom(String date);

  /// No description provided for @verdictOrderAsIs.
  ///
  /// In en, this message translates to:
  /// **'Order as-is'**
  String get verdictOrderAsIs;

  /// No description provided for @verdictModifiable.
  ///
  /// In en, this message translates to:
  /// **'Order with a change'**
  String get verdictModifiable;

  /// No description provided for @verdictNonKeto.
  ///
  /// In en, this message translates to:
  /// **'Not keto'**
  String get verdictNonKeto;

  /// No description provided for @waiterCardOpen.
  ///
  /// In en, this message translates to:
  /// **'Show the waiter card'**
  String get waiterCardOpen;

  /// No description provided for @waiterCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Say this to the waiter'**
  String get waiterCardTitle;

  /// No description provided for @settingsConsentTitle.
  ///
  /// In en, this message translates to:
  /// **'What leaves this device'**
  String get settingsConsentTitle;

  /// No description provided for @settingsConsentBody.
  ///
  /// In en, this message translates to:
  /// **'When you allow AI analysis, dish names, descriptions and option labels from the menu you open are sent to KetoClub\'s server, which forwards them to Google\'s Gemini API for analysis. Nothing about you or your history is sent otherwise. Your position is sent to Wolt only when you search nearby, and is not stored. There are no analytics.'**
  String get settingsConsentBody;

  /// No description provided for @settingsConsentAccept.
  ///
  /// In en, this message translates to:
  /// **'I understand'**
  String get settingsConsentAccept;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'Match my device'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsLanguageHebrew.
  ///
  /// In en, this message translates to:
  /// **'Hebrew'**
  String get settingsLanguageHebrew;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsAppearanceSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow device theme'**
  String get settingsAppearanceSystem;

  /// No description provided for @settingsAppearanceLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsAppearanceLight;

  /// No description provided for @settingsAppearanceDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsAppearanceDark;

  /// No description provided for @settingsNetCarbLimit.
  ///
  /// In en, this message translates to:
  /// **'Net carb limit'**
  String get settingsNetCarbLimit;

  /// No description provided for @settingsNetCarbLimitBody.
  ///
  /// In en, this message translates to:
  /// **'Dishes above this are never green. Changing it re-analyses the next menu you open.'**
  String get settingsNetCarbLimitBody;

  /// No description provided for @settingsNetCarbLimitValue.
  ///
  /// In en, this message translates to:
  /// **'{grams} g'**
  String settingsNetCarbLimitValue(int grams);

  /// No description provided for @settingsNetCarbLimitDecrease.
  ///
  /// In en, this message translates to:
  /// **'Lower the net carb limit'**
  String get settingsNetCarbLimitDecrease;

  /// No description provided for @settingsNetCarbLimitIncrease.
  ///
  /// In en, this message translates to:
  /// **'Raise the net carb limit'**
  String get settingsNetCarbLimitIncrease;

  /// No description provided for @settingsKetoRules.
  ///
  /// In en, this message translates to:
  /// **'Your keto rules'**
  String get settingsKetoRules;

  /// No description provided for @settingsKetoRulesBody.
  ///
  /// In en, this message translates to:
  /// **'Each rule you turn on applies from the next menu you open.'**
  String get settingsKetoRulesBody;

  /// No description provided for @settingsSeedOilFree.
  ///
  /// In en, this message translates to:
  /// **'Strict seed-oil free'**
  String get settingsSeedOilFree;

  /// No description provided for @settingsSeedOilFreeHint.
  ///
  /// In en, this message translates to:
  /// **'Flags canola, sunflower and soybean oil in fried dishes.'**
  String get settingsSeedOilFreeHint;

  /// No description provided for @settingsDairyFree.
  ///
  /// In en, this message translates to:
  /// **'Dairy-free keto'**
  String get settingsDairyFree;

  /// No description provided for @settingsDairyFreeHint.
  ///
  /// In en, this message translates to:
  /// **'Treats cream, butter and cheese as a modification.'**
  String get settingsDairyFreeHint;

  /// No description provided for @settingsCarnivoreOnly.
  ///
  /// In en, this message translates to:
  /// **'Carnivore only'**
  String get settingsCarnivoreOnly;

  /// No description provided for @settingsCarnivoreOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Greens only meat, fish, eggs — vegetables become yellow.'**
  String get settingsCarnivoreOnlyHint;

  /// No description provided for @settingsFilter.
  ///
  /// In en, this message translates to:
  /// **'Default filter'**
  String get settingsFilter;

  /// No description provided for @settingsCacheSummary.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 menu cached · works offline} other{{count} menus cached · works offline}}'**
  String settingsCacheSummary(num count);

  /// No description provided for @settingsClearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear saved menus'**
  String get settingsClearCache;

  /// No description provided for @settingsClearCacheConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear saved menus?'**
  String get settingsClearCacheConfirmTitle;

  /// No description provided for @settingsClearCacheConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This removes every menu saved on this device, including any you can currently open offline. You can save a venue again by opening it once you have a connection.'**
  String get settingsClearCacheConfirmBody;

  /// No description provided for @settingsClearCacheConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get settingsClearCacheConfirmAction;

  /// No description provided for @settingsCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Saved menus cleared.'**
  String get settingsCacheCleared;

  /// No description provided for @fetchFailedOffline.
  ///
  /// In en, this message translates to:
  /// **'No connection, so the menu could not be read.'**
  String get fetchFailedOffline;

  /// No description provided for @fetchFailedBlockedByBrowser.
  ///
  /// In en, this message translates to:
  /// **'A web browser cannot read {platform} menus: {platform} blocks requests from other websites. Open this link in the KetoClub phone app instead.'**
  String fetchFailedBlockedByBrowser(String platform);

  /// No description provided for @fetchFailedNotFound.
  ///
  /// In en, this message translates to:
  /// **'No venue found on {platform}. Check the link.'**
  String fetchFailedNotFound(String platform);

  /// No description provided for @fetchFailedPlatformChanged.
  ///
  /// In en, this message translates to:
  /// **'{platform} changed its menu format (HTTP {statusCode}), so KetoClub could not read it. Please report this.'**
  String fetchFailedPlatformChanged(String platform, String statusCode);

  /// No description provided for @fetchFailedUnsupportedSource.
  ///
  /// In en, this message translates to:
  /// **'KetoClub cannot read menus from that site yet.'**
  String get fetchFailedUnsupportedSource;

  /// No description provided for @fetchFailedBackendUnreachable.
  ///
  /// In en, this message translates to:
  /// **'KetoClub\'s server could not be reached, so the menu could not be read.'**
  String get fetchFailedBackendUnreachable;

  /// No description provided for @venueSearchFailedOffline.
  ///
  /// In en, this message translates to:
  /// **'No connection, so KetoClub could not search for restaurants.'**
  String get venueSearchFailedOffline;

  /// No description provided for @venueSearchFailedTimeout.
  ///
  /// In en, this message translates to:
  /// **'Wolt took too long to answer the search. Try again in a moment.'**
  String get venueSearchFailedTimeout;

  /// No description provided for @venueSearchFailedRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many searches in a row. Wait a minute, then try again.'**
  String get venueSearchFailedRateLimited;

  /// No description provided for @venueSearchFailedPlatformChanged.
  ///
  /// In en, this message translates to:
  /// **'Wolt changed how its restaurant search works, so KetoClub could not read the results. Please report this.'**
  String get venueSearchFailedPlatformChanged;

  /// No description provided for @venueSearchFailedBlockedByBrowser.
  ///
  /// In en, this message translates to:
  /// **'A web browser cannot search Wolt directly. Use the KetoClub phone app, or paste a Wolt link instead.'**
  String get venueSearchFailedBlockedByBrowser;

  /// No description provided for @venueSearchFailedBackendUnreachable.
  ///
  /// In en, this message translates to:
  /// **'KetoClub\'s server could not be reached, so the search could not run.'**
  String get venueSearchFailedBackendUnreachable;

  /// No description provided for @analysisNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'AI analysis is not available on this build or server. Showing rule-based results.'**
  String get analysisNotConfigured;

  /// No description provided for @analysisOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline. Showing rule-based results.'**
  String get analysisOffline;

  /// No description provided for @analysisTimeout.
  ///
  /// In en, this message translates to:
  /// **'The AI model was too slow. Showing rule-based results.'**
  String get analysisTimeout;

  /// No description provided for @analysisRateLimited.
  ///
  /// In en, this message translates to:
  /// **'The daily AI limit is used up. Showing rule-based results.'**
  String get analysisRateLimited;

  /// No description provided for @analysisBadResponse.
  ///
  /// In en, this message translates to:
  /// **'AI analysis failed ({detail}). Showing rule-based results.'**
  String analysisBadResponse(String detail);

  /// No description provided for @analysisNoDishesFound.
  ///
  /// In en, this message translates to:
  /// **'The AI could not identify any dishes on this menu.'**
  String get analysisNoDishesFound;

  /// No description provided for @analysisBackendUnreachable.
  ///
  /// In en, this message translates to:
  /// **'KetoClub\'s server could not be reached. Showing rule-based results.'**
  String get analysisBackendUnreachable;

  /// No description provided for @analysisConsentWithheld.
  ///
  /// In en, this message translates to:
  /// **'Allow AI analysis in Settings to analyse this menu. Showing rule-based results.'**
  String get analysisConsentWithheld;

  /// No description provided for @pillSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Verdict: {verdict}'**
  String pillSemanticLabel(String verdict);

  /// No description provided for @dishCardAskWaiter.
  ///
  /// In en, this message translates to:
  /// **'Ask your waiter'**
  String get dishCardAskWaiter;

  /// No description provided for @dishCardHideScript.
  ///
  /// In en, this message translates to:
  /// **'Hide the waiter script'**
  String get dishCardHideScript;

  /// No description provided for @dishCardScriptFallback.
  ///
  /// In en, this message translates to:
  /// **'Ask your waiter about a keto-friendly substitution.'**
  String get dishCardScriptFallback;

  /// No description provided for @netCarbsChipLabel.
  ///
  /// In en, this message translates to:
  /// **'~{grams}g net carbs (estimate)'**
  String netCarbsChipLabel(String grams);

  /// No description provided for @netCarbsChipSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Estimated net carbs, not confirmed: {grams} grams'**
  String netCarbsChipSemanticLabel(String grams);

  /// No description provided for @engineChipAiSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'AI engine, model {model}'**
  String engineChipAiSemanticLabel(String model);

  /// No description provided for @engineChipRulesSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Rules engine, not AI-verified: {reason}'**
  String engineChipRulesSemanticLabel(String reason);

  /// No description provided for @engineChipReasonNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'not configured'**
  String get engineChipReasonNotConfigured;

  /// No description provided for @engineChipReasonOffline.
  ///
  /// In en, this message translates to:
  /// **'offline'**
  String get engineChipReasonOffline;

  /// No description provided for @engineChipReasonTimeout.
  ///
  /// In en, this message translates to:
  /// **'timeout'**
  String get engineChipReasonTimeout;

  /// No description provided for @engineChipReasonRateLimited.
  ///
  /// In en, this message translates to:
  /// **'rate limited'**
  String get engineChipReasonRateLimited;

  /// No description provided for @engineChipReasonBadResponse.
  ///
  /// In en, this message translates to:
  /// **'AI error'**
  String get engineChipReasonBadResponse;

  /// No description provided for @engineChipReasonNoDishesFound.
  ///
  /// In en, this message translates to:
  /// **'no dishes found'**
  String get engineChipReasonNoDishesFound;

  /// No description provided for @engineChipReasonBackendUnreachable.
  ///
  /// In en, this message translates to:
  /// **'server unreachable'**
  String get engineChipReasonBackendUnreachable;

  /// No description provided for @engineChipReasonConsentWithheld.
  ///
  /// In en, this message translates to:
  /// **'AI not allowed'**
  String get engineChipReasonConsentWithheld;

  /// No description provided for @navExplore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get navExplore;

  /// No description provided for @navScan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get navScan;

  /// No description provided for @navSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get navSaved;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @scanPlaceholderTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan a menu'**
  String get scanPlaceholderTitle;

  /// No description provided for @scanPlaceholderBody.
  ///
  /// In en, this message translates to:
  /// **'Photographing a physical menu is coming in a later update. For now, paste a delivery link on Explore.'**
  String get scanPlaceholderBody;

  /// No description provided for @savedPlaceholderTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved venues'**
  String get savedPlaceholderTitle;

  /// No description provided for @savedPlaceholderBody.
  ///
  /// In en, this message translates to:
  /// **'Open a venue\'s menu and it appears here automatically, available for a day — even offline.'**
  String get savedPlaceholderBody;

  /// No description provided for @savedLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading your saved menus…'**
  String get savedLoading;

  /// No description provided for @savedEntryDishCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 dish} other{{count} dishes}}'**
  String savedEntryDishCount(num count);

  /// No description provided for @savedRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get savedRemove;

  /// No description provided for @savedRemoveSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Remove {venue}'**
  String savedRemoveSemanticLabel(String venue);

  /// No description provided for @savedRemovedMessage.
  ///
  /// In en, this message translates to:
  /// **'Removed {venue}.'**
  String savedRemovedMessage(String venue);

  /// No description provided for @savedUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get savedUndo;

  /// No description provided for @discoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Where to eat'**
  String get discoveryTitle;

  /// No description provided for @discoveryEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Find somewhere to eat'**
  String get discoveryEmptyTitle;

  /// No description provided for @discoveryEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Use your location to see restaurants nearby, search by name, or paste a Wolt link above to open its keto-classified menu.'**
  String get discoveryEmptyBody;

  /// No description provided for @discoveryLookingAround.
  ///
  /// In en, this message translates to:
  /// **'Looking around'**
  String get discoveryLookingAround;

  /// No description provided for @discoveryAroundYou.
  ///
  /// In en, this message translates to:
  /// **'Your location'**
  String get discoveryAroundYou;

  /// No description provided for @discoveryLocationNotSet.
  ///
  /// In en, this message translates to:
  /// **'Location not set'**
  String get discoveryLocationNotSet;

  /// No description provided for @discoveryUseLocation.
  ///
  /// In en, this message translates to:
  /// **'Use my location'**
  String get discoveryUseLocation;

  /// No description provided for @discoveryChipNearby.
  ///
  /// In en, this message translates to:
  /// **'Nearby'**
  String get discoveryChipNearby;

  /// No description provided for @discoveryChipKetoEightPlus.
  ///
  /// In en, this message translates to:
  /// **'Keto 8+'**
  String get discoveryChipKetoEightPlus;

  /// No description provided for @discoveryChipOpenNow.
  ///
  /// In en, this message translates to:
  /// **'Open now'**
  String get discoveryChipOpenNow;

  /// No description provided for @discoveryLocating.
  ///
  /// In en, this message translates to:
  /// **'Finding your location…'**
  String get discoveryLocating;

  /// No description provided for @discoverySearching.
  ///
  /// In en, this message translates to:
  /// **'Looking for restaurants…'**
  String get discoverySearching;

  /// No description provided for @discoveryLocationDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'Location is off for KetoClub'**
  String get discoveryLocationDeniedTitle;

  /// No description provided for @discoveryLocationDeniedBody.
  ///
  /// In en, this message translates to:
  /// **'Allow location to see restaurants near you, or search by name instead.'**
  String get discoveryLocationDeniedBody;

  /// No description provided for @discoveryLocationDeniedForeverBody.
  ///
  /// In en, this message translates to:
  /// **'Location access is turned off for KetoClub. You can turn it back on in your device\'s settings, or search by name instead.'**
  String get discoveryLocationDeniedForeverBody;

  /// No description provided for @discoveryLocationUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not find your location'**
  String get discoveryLocationUnavailableTitle;

  /// No description provided for @discoveryLocationServicesOff.
  ///
  /// In en, this message translates to:
  /// **'Your device\'s location is turned off. Turn it on and try again, or search by name instead.'**
  String get discoveryLocationServicesOff;

  /// No description provided for @discoveryLocationInsecureContext.
  ///
  /// In en, this message translates to:
  /// **'This page cannot ask for your location because it is not on a secure (https) connection. Search by name instead.'**
  String get discoveryLocationInsecureContext;

  /// No description provided for @discoveryLocationTimeout.
  ///
  /// In en, this message translates to:
  /// **'Finding your location took too long. Try again, or search by name instead.'**
  String get discoveryLocationTimeout;

  /// No description provided for @discoveryLocationUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This device could not provide a location. Search by name instead.'**
  String get discoveryLocationUnsupported;

  /// No description provided for @discoveryTypeNameInstead.
  ///
  /// In en, this message translates to:
  /// **'Type a name instead'**
  String get discoveryTypeNameInstead;

  /// No description provided for @discoveryOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get discoveryOpenSettings;

  /// No description provided for @discoveryTurnOnLocation.
  ///
  /// In en, this message translates to:
  /// **'Turn on location'**
  String get discoveryTurnOnLocation;

  /// No description provided for @discoveryOpenSettingsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This device could not open its settings from here. Allow location for KetoClub in your browser\'s or device\'s settings, then try again.'**
  String get discoveryOpenSettingsUnavailable;

  /// No description provided for @discoveryNoResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'No restaurants found'**
  String get discoveryNoResultsTitle;

  /// No description provided for @discoveryNoResultsBody.
  ///
  /// In en, this message translates to:
  /// **'Try a different name, or clear the search.'**
  String get discoveryNoResultsBody;

  /// No description provided for @discoveryClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get discoveryClearSearch;

  /// No description provided for @discoveryNoChipResults.
  ///
  /// In en, this message translates to:
  /// **'No restaurant in this list matches that filter.'**
  String get discoveryNoChipResults;

  /// No description provided for @discoveryEstimateList.
  ///
  /// In en, this message translates to:
  /// **'Estimate this list'**
  String get discoveryEstimateList;

  /// No description provided for @discoveryEstimateHint.
  ///
  /// In en, this message translates to:
  /// **'Reads each menu on this list once and scores it with the on-device rules, not the AI. Open a restaurant for the full analysis.'**
  String get discoveryEstimateHint;

  /// No description provided for @discoveryEstimating.
  ///
  /// In en, this message translates to:
  /// **'Estimating {done} of {total}…'**
  String discoveryEstimating(int done, int total);

  /// No description provided for @venueCardOpenNow.
  ///
  /// In en, this message translates to:
  /// **'Open now'**
  String get venueCardOpenNow;

  /// No description provided for @venueCardClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get venueCardClosed;

  /// No description provided for @venueCardMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String venueCardMinutes(int minutes);

  /// No description provided for @venueCardWalkMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min walk'**
  String venueCardWalkMinutes(int minutes);

  /// No description provided for @venueCardGreenCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 dish as-is} other{{count} dishes as-is}}'**
  String venueCardGreenCount(num count);

  /// No description provided for @venueCardYellowCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 with changes} other{{count} with changes}}'**
  String venueCardYellowCount(num count);

  /// No description provided for @menuKetoScoreLabel.
  ///
  /// In en, this message translates to:
  /// **'Keto score'**
  String get menuKetoScoreLabel;

  /// No description provided for @menuKetoScoreSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Keto score: {score} out of 10'**
  String menuKetoScoreSemanticLabel(String score);

  /// No description provided for @menuSourceLine.
  ///
  /// In en, this message translates to:
  /// **'{platform} · {age}'**
  String menuSourceLine(String platform, String age);

  /// No description provided for @menuOpenOnPlatform.
  ///
  /// In en, this message translates to:
  /// **'Open on {platform}'**
  String menuOpenOnPlatform(String platform);

  /// No description provided for @menuShowingAll.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Showing 1 dish} other{Showing {count} dishes}}'**
  String menuShowingAll(num count);

  /// No description provided for @menuShowingGreen.
  ///
  /// In en, this message translates to:
  /// **'Showing dishes you can order as-is'**
  String get menuShowingGreen;

  /// No description provided for @menuShowingYellow.
  ///
  /// In en, this message translates to:
  /// **'Showing dishes that need a change'**
  String get menuShowingYellow;

  /// No description provided for @menuShowingRed.
  ///
  /// In en, this message translates to:
  /// **'Showing what to skip'**
  String get menuShowingRed;

  /// No description provided for @menuShowingGreenAndYellow.
  ///
  /// In en, this message translates to:
  /// **'Showing dishes you can order as-is or with a change'**
  String get menuShowingGreenAndYellow;

  /// No description provided for @tileGreenLabel.
  ///
  /// In en, this message translates to:
  /// **'Order as-is'**
  String get tileGreenLabel;

  /// No description provided for @tileYellowLabel.
  ///
  /// In en, this message translates to:
  /// **'With changes'**
  String get tileYellowLabel;

  /// No description provided for @tileRedLabel.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get tileRedLabel;

  /// No description provided for @tileSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'{label}: {count}'**
  String tileSemanticLabel(String label, int count);

  /// No description provided for @ageJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get ageJustNow;

  /// No description provided for @ageMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 minute ago} other{{count} minutes ago}}'**
  String ageMinutes(num count);

  /// No description provided for @ageHours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 hour ago} other{{count} hours ago}}'**
  String ageHours(num count);

  /// No description provided for @ageDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 day ago} other{{count} days ago}}'**
  String ageDays(num count);

  /// No description provided for @legendToggle.
  ///
  /// In en, this message translates to:
  /// **'What do the colours mean?'**
  String get legendToggle;

  /// No description provided for @legendHide.
  ///
  /// In en, this message translates to:
  /// **'Hide the legend'**
  String get legendHide;

  /// No description provided for @legendNote.
  ///
  /// In en, this message translates to:
  /// **'The same rules KetoClub sends to the AI model.'**
  String get legendNote;

  /// No description provided for @waiterCardCopyButton.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get waiterCardCopyButton;

  /// No description provided for @waiterCardAfterText.
  ///
  /// In en, this message translates to:
  /// **'With these changes, about {grams}g net carbs (estimate) — safe to order.'**
  String waiterCardAfterText(String grams);

  /// No description provided for @dishCardAddNote.
  ///
  /// In en, this message translates to:
  /// **'Add a note'**
  String get dishCardAddNote;

  /// No description provided for @dishCardEditNoteSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Edit your note: {note}'**
  String dishCardEditNoteSemanticLabel(String note);

  /// No description provided for @noteEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'Personal note'**
  String get noteEditorTitle;

  /// No description provided for @noteEditorHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Waitstaff happily substituted cauliflower'**
  String get noteEditorHint;

  /// No description provided for @noteEditorSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get noteEditorSave;

  /// No description provided for @noteEditorClear.
  ///
  /// In en, this message translates to:
  /// **'Clear note'**
  String get noteEditorClear;

  /// No description provided for @menuSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search dishes'**
  String get menuSearchHint;

  /// No description provided for @menuSearchSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Search dishes by name or description'**
  String get menuSearchSemanticLabel;

  /// No description provided for @menuSearchClear.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get menuSearchClear;

  /// No description provided for @menuNoResults.
  ///
  /// In en, this message translates to:
  /// **'No dishes match your search.'**
  String get menuNoResults;

  /// No description provided for @menuClearFilter.
  ///
  /// In en, this message translates to:
  /// **'Clear filter'**
  String get menuClearFilter;

  /// No description provided for @categoryChipSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Jump to {category}'**
  String categoryChipSemanticLabel(String category);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'he'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'he':
      return AppLocalizationsHe();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
