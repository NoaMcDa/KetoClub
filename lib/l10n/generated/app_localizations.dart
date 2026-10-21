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

  /// No description provided for @actionMoreMenuOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get actionMoreMenuOptions;

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

  /// No description provided for @venueSearchOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Open link'**
  String get venueSearchOpenLink;

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
  /// **'Skip ({count})'**
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

  /// No description provided for @unclassifiedBadge.
  ///
  /// In en, this message translates to:
  /// **'Not classified'**
  String get unclassifiedBadge;

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
  /// **'With changes'**
  String get verdictModifiable;

  /// No description provided for @verdictNonKeto.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get verdictNonKeto;

  /// No description provided for @dishCardFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Full screen'**
  String get dishCardFullScreen;

  /// No description provided for @dishCardFullScreenSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Show the waiter card for {dish}'**
  String dishCardFullScreenSemanticLabel(String dish);

  /// No description provided for @waiterCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Say this to the waiter'**
  String get waiterCardTitle;

  /// No description provided for @settingsAiPrivacy.
  ///
  /// In en, this message translates to:
  /// **'AI & privacy'**
  String get settingsAiPrivacy;

  /// No description provided for @settingsConsentTitle.
  ///
  /// In en, this message translates to:
  /// **'What leaves this device'**
  String get settingsConsentTitle;

  /// No description provided for @settingsConsentBody.
  ///
  /// In en, this message translates to:
  /// **'AI analysis is on by default: when you open or paste a menu, dish names, descriptions and option labels — and any questions you type about a menu — are sent to KetoClub\'s server, which forwards them to Google\'s Gemini API for analysis. Nothing about you or your history is sent otherwise. Your position is sent to Wolt only when you search nearby, and is not stored. There are no analytics. The menu, its analysis, the venue name and city are also stored on KetoClub\'s server, with nothing that identifies you, so others can find them. Untick this to keep every menu on this device.'**
  String get settingsConsentBody;

  /// No description provided for @settingsConsentAccept.
  ///
  /// In en, this message translates to:
  /// **'Allow AI analysis'**
  String get settingsConsentAccept;

  /// No description provided for @consentDisclosureOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get consentDisclosureOk;

  /// No description provided for @consentDisclosureTurnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get consentDisclosureTurnOff;

  /// No description provided for @settingsConsentBodyDirect.
  ///
  /// In en, this message translates to:
  /// **'AI analysis is on by default: when you open or paste a menu, dish names, descriptions and option labels — and any questions you type about a menu — are sent straight from this device to Google\'s Gemini API, using your own API key. Nothing about you or your history is sent otherwise. Your position is sent to Wolt only when you search nearby, and is not stored. There are no analytics. The menu, its analysis, the venue name and city are also stored on KetoClub\'s server, with nothing that identifies you, so others can find them. Untick this to keep every menu on this device.'**
  String get settingsConsentBodyDirect;

  /// No description provided for @settingsConsentBodyDirectViaBackend.
  ///
  /// In en, this message translates to:
  /// **'AI analysis is on by default: when you open or paste a menu, dish names, descriptions and option labels — and any questions you type about a menu — are sent from this device to KetoClub\'s server, which forwards them to Google\'s Gemini API for analysis. Your own API key is used only if the server cannot be reached. Nothing about you or your history is sent otherwise. Your position is sent to Wolt only when you search nearby, and is not stored. There are no analytics. The menu, its analysis, the venue name and city are also stored on KetoClub\'s server, with nothing that identifies you, so others can find them. Untick this to keep every menu on this device.'**
  String get settingsConsentBodyDirectViaBackend;

  /// No description provided for @settingsKeySection.
  ///
  /// In en, this message translates to:
  /// **'Gemini API key'**
  String get settingsKeySection;

  /// No description provided for @settingsKeyBody.
  ///
  /// In en, this message translates to:
  /// **'On this phone, AI analysis calls Google\'s Gemini API directly with your own key. You can create one for free in Google AI Studio. It is kept in this device\'s secure storage and sent only to Google.'**
  String get settingsKeyBody;

  /// No description provided for @settingsKeyBodyViaBackend.
  ///
  /// In en, this message translates to:
  /// **'On this phone, AI analysis goes to KetoClub\'s server first. Your own key is used only if the server cannot be reached: then this device calls Google\'s Gemini API directly with it. You can create one for free in Google AI Studio. It is kept in this device\'s secure storage and sent only to Google.'**
  String get settingsKeyBodyViaBackend;

  /// No description provided for @settingsKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Paste your Gemini API key'**
  String get settingsKeyHint;

  /// No description provided for @settingsKeySave.
  ///
  /// In en, this message translates to:
  /// **'Save key'**
  String get settingsKeySave;

  /// No description provided for @settingsKeyPresent.
  ///
  /// In en, this message translates to:
  /// **'A key is saved on this device.'**
  String get settingsKeyPresent;

  /// No description provided for @settingsKeyAbsent.
  ///
  /// In en, this message translates to:
  /// **'No key saved. KetoClub will use on-device rules.'**
  String get settingsKeyAbsent;

  /// No description provided for @settingsKeyDelete.
  ///
  /// In en, this message translates to:
  /// **'Remove key'**
  String get settingsKeyDelete;

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

  /// Banto (ALG-02a): the Settings section listing the user's dietary restrictions.
  ///
  /// In en, this message translates to:
  /// **'My restrictions'**
  String get settingsRestrictions;

  /// No description provided for @settingsRestrictionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'You have not added a restriction yet.'**
  String get settingsRestrictionsEmpty;

  /// No description provided for @settingsRestrictionsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add restriction'**
  String get settingsRestrictionsAdd;

  /// Tooltip and screen-reader label of a restriction row's remove button.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}'**
  String settingsRestrictionsRemove(String name);

  /// No description provided for @restrictionKindAllergy.
  ///
  /// In en, this message translates to:
  /// **'Allergy'**
  String get restrictionKindAllergy;

  /// The kind label of celiac disease (the gluten restriction).
  ///
  /// In en, this message translates to:
  /// **'Autoimmune'**
  String get restrictionKindAutoimmune;

  /// No description provided for @restrictionKindIntolerance.
  ///
  /// In en, this message translates to:
  /// **'Intolerance'**
  String get restrictionKindIntolerance;

  /// No description provided for @restrictionKindDiet.
  ///
  /// In en, this message translates to:
  /// **'Diet'**
  String get restrictionKindDiet;

  /// One line under a restriction in the picker: which official allergen-labelling lists name it.
  ///
  /// In en, this message translates to:
  /// **'{lists, select, usEu{On the US and EU allergen lists} us{On the US allergen list} eu{On the EU allergen list} other{Not on any official allergen list}}'**
  String restrictionJurisdictionHint(String lists);

  /// No description provided for @restrictionPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a restriction'**
  String get restrictionPickerTitle;

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

  /// No description provided for @settingsCacheSection.
  ///
  /// In en, this message translates to:
  /// **'Recent menus'**
  String get settingsCacheSection;

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
  /// **'This removes every menu saved on this device and clears your Recent list, including any menu you can currently open offline. Open a venue again to save it.'**
  String get settingsClearCacheConfirmBody;

  /// No description provided for @settingsClearCacheConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get settingsClearCacheConfirmAction;

  /// No description provided for @settingsCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Saved menus and Recent list cleared.'**
  String get settingsCacheCleared;

  /// No description provided for @settingsAboutSection.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAboutSection;

  /// No description provided for @settingsAboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get settingsAboutVersion;

  /// No description provided for @settingsAboutVersionValue.
  ///
  /// In en, this message translates to:
  /// **'{version} (build {build})'**
  String settingsAboutVersionValue(String version, String build);

  /// No description provided for @settingsAboutLicences.
  ///
  /// In en, this message translates to:
  /// **'Open-source licences'**
  String get settingsAboutLicences;

  /// No description provided for @settingsAboutPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsAboutPrivacy;

  /// No description provided for @settingsAboutReport.
  ///
  /// In en, this message translates to:
  /// **'Report a problem'**
  String get settingsAboutReport;

  /// No description provided for @settingsAboutReportHint.
  ///
  /// In en, this message translates to:
  /// **'Opens KetoClub\'s issue tracker on GitHub'**
  String get settingsAboutReportHint;

  /// No description provided for @settingsAboutLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the link.'**
  String get settingsAboutLinkFailed;

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

  /// No description provided for @analysisBadResponseNoDetail.
  ///
  /// In en, this message translates to:
  /// **'The AI model gave an unusable answer. Showing rule-based results.'**
  String get analysisBadResponseNoDetail;

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

  /// No description provided for @analysisApiKeyMissing.
  ///
  /// In en, this message translates to:
  /// **'Add your Gemini API key in Settings to analyse this menu. Showing rule-based results.'**
  String get analysisApiKeyMissing;

  /// No description provided for @analysisApiKeyRejected.
  ///
  /// In en, this message translates to:
  /// **'Gemini rejected your API key. Check it in Settings. Showing rule-based results.'**
  String get analysisApiKeyRejected;

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
  /// **'Recent'**
  String get navSaved;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @savedPlaceholderTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent menus'**
  String get savedPlaceholderTitle;

  /// No description provided for @savedPlaceholderBody.
  ///
  /// In en, this message translates to:
  /// **'Every menu you open is listed here with its score and counts until you remove it. Menus opened in the last day also work offline.'**
  String get savedPlaceholderBody;

  /// No description provided for @savedLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading your recent menus…'**
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

  /// No description provided for @savedExpiresMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Expires in 1 minute} other{Expires in {count} minutes}}'**
  String savedExpiresMinutes(num count);

  /// No description provided for @savedExpiresHours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Expires in 1 hour} other{Expires in {count} hours}}'**
  String savedExpiresHours(num count);

  /// No description provided for @savedExpiresDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Expires in 1 day} other{Expires in {count} days}}'**
  String savedExpiresDays(num count);

  /// No description provided for @savedExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired, refreshes when opened'**
  String get savedExpired;

  /// No description provided for @savedKept.
  ///
  /// In en, this message translates to:
  /// **'Kept, no expiry'**
  String get savedKept;

  /// No description provided for @savedKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get savedKeep;

  /// No description provided for @savedKeepSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Keep {venue} past its expiry'**
  String savedKeepSemanticLabel(String venue);

  /// No description provided for @savedUnkeep.
  ///
  /// In en, this message translates to:
  /// **'Stop keeping'**
  String get savedUnkeep;

  /// No description provided for @savedUnkeepSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Stop keeping {venue}'**
  String savedUnkeepSemanticLabel(String venue);

  /// No description provided for @savedUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get savedUndo;

  /// No description provided for @savedOpenedAgo.
  ///
  /// In en, this message translates to:
  /// **'Opened {age}'**
  String savedOpenedAgo(String age);

  /// No description provided for @savedOpenCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Opened once} other{Opened {count} times}}'**
  String savedOpenCount(int count);

  /// No description provided for @savedNotOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Not on this device, opens online'**
  String get savedNotOnDevice;

  /// No description provided for @savedScanGone.
  ///
  /// In en, this message translates to:
  /// **'No longer on this device'**
  String get savedScanGone;

  /// No description provided for @savedRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get savedRename;

  /// No description provided for @savedRenameSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Rename {venue}'**
  String savedRenameSemanticLabel(String venue);

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

  /// No description provided for @discoveryDrinksGuideCard.
  ///
  /// In en, this message translates to:
  /// **'Ordering a drink? Bar and coffee guide'**
  String get discoveryDrinksGuideCard;

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

  /// No description provided for @discoveryLocationInvite.
  ///
  /// In en, this message translates to:
  /// **'Tap to use your location'**
  String get discoveryLocationInvite;

  /// No description provided for @discoveryUseLocation.
  ///
  /// In en, this message translates to:
  /// **'Use my location'**
  String get discoveryUseLocation;

  /// No description provided for @discoveryChipKetoEightPlus.
  ///
  /// In en, this message translates to:
  /// **'Keto 8+'**
  String get discoveryChipKetoEightPlus;

  /// No description provided for @discoveryChipKetoEightPlusHint.
  ///
  /// In en, this message translates to:
  /// **'Needs scores first: they appear as the list is scored, or when you open a restaurant.'**
  String get discoveryChipKetoEightPlusHint;

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
  /// **'Quick score the rest (on-device rules)'**
  String get discoveryEstimateList;

  /// No description provided for @discoveryEstimateHint.
  ///
  /// In en, this message translates to:
  /// **'The first restaurants are scored automatically with on-device rules, for food only. Open a restaurant for the full AI analysis.'**
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

  /// No description provided for @venueCardDistanceMetres.
  ///
  /// In en, this message translates to:
  /// **'{distance} m'**
  String venueCardDistanceMetres(String distance);

  /// No description provided for @venueCardDistanceKm.
  ///
  /// In en, this message translates to:
  /// **'{distance} km'**
  String venueCardDistanceKm(String distance);

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

  /// No description provided for @tileSemanticHintFilter.
  ///
  /// In en, this message translates to:
  /// **'Double tap to filter'**
  String get tileSemanticHintFilter;

  /// No description provided for @tileSemanticHintClear.
  ///
  /// In en, this message translates to:
  /// **'Double tap to clear the filter'**
  String get tileSemanticHintClear;

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

  /// No description provided for @legendEngines.
  ///
  /// In en, this message translates to:
  /// **'Rules: KetoClub\'s own keyword checks on the dish text, with no carb estimate. AI: Gemini reads the whole menu and estimates net carbs.'**
  String get legendEngines;

  /// No description provided for @legendFoodOnly.
  ///
  /// In en, this message translates to:
  /// **'The score and the counters cover food only. Drinks, sauces and extras are still judged and listed, but are not counted.'**
  String get legendFoodOnly;

  /// No description provided for @legendBudget.
  ///
  /// In en, this message translates to:
  /// **'Carb budget: after an AI analysis, a Filters field lets you set a net-carb budget for the meal. Rule-based results have no carb estimates, so it is not offered.'**
  String get legendBudget;

  /// No description provided for @waiterCardCopyButton.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get waiterCardCopyButton;

  /// No description provided for @waiterCardCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied ✓'**
  String get waiterCardCopied;

  /// No description provided for @waiterCardDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get waiterCardDone;

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

  /// No description provided for @menuFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get menuFilters;

  /// No description provided for @menuFiltersActive.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Filters · 1 active} other{Filters · {count} active}}'**
  String menuFiltersActive(num count);

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

  /// No description provided for @menuRenameAction.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get menuRenameAction;

  /// No description provided for @menuRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Name this menu'**
  String get menuRenameTitle;

  /// No description provided for @menuRenameHint.
  ///
  /// In en, this message translates to:
  /// **'Restaurant name'**
  String get menuRenameHint;

  /// No description provided for @menuRenameCityHint.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get menuRenameCityHint;

  /// No description provided for @menuRenameSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get menuRenameSave;

  /// No description provided for @categoryChipSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Jump to {category}'**
  String categoryChipSemanticLabel(String category);

  /// No description provided for @scanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan a menu'**
  String get scanTitle;

  /// No description provided for @scanPasteIntro.
  ///
  /// In en, this message translates to:
  /// **'Paste a menu from anywhere, one dish per line. KetoClub reads it the same way it reads a delivery menu.'**
  String get scanPasteIntro;

  /// No description provided for @scanPasteLabel.
  ///
  /// In en, this message translates to:
  /// **'Menu text'**
  String get scanPasteLabel;

  /// No description provided for @scanPasteHint.
  ///
  /// In en, this message translates to:
  /// **'Grilled salmon\nCaesar salad, no croutons\nPasta carbonara'**
  String get scanPasteHint;

  /// No description provided for @scanAnalyse.
  ///
  /// In en, this message translates to:
  /// **'Analyse'**
  String get scanAnalyse;

  /// No description provided for @scanEmptyPaste.
  ///
  /// In en, this message translates to:
  /// **'KetoClub found no dishes in that text. Paste the menu with one dish per line.'**
  String get scanEmptyPaste;

  /// No description provided for @sourceScanned.
  ///
  /// In en, this message translates to:
  /// **'Pasted menu'**
  String get sourceScanned;

  /// No description provided for @sourceWithCity.
  ///
  /// In en, this message translates to:
  /// **'{platform} · {city}'**
  String sourceWithCity(String platform, String city);

  /// No description provided for @fetchFailedScanNotSaved.
  ///
  /// In en, this message translates to:
  /// **'This pasted menu is no longer saved on this device. Paste it again to analyse it.'**
  String get fetchFailedScanNotSaved;

  /// No description provided for @scannedMenuTitle.
  ///
  /// In en, this message translates to:
  /// **'Scanned menu'**
  String get scannedMenuTitle;

  /// No description provided for @scannedMenuReadByAi.
  ///
  /// In en, this message translates to:
  /// **'Read by AI from your pages'**
  String get scannedMenuReadByAi;

  /// No description provided for @scannedMenuViewPages.
  ///
  /// In en, this message translates to:
  /// **'View pages'**
  String get scannedMenuViewPages;

  /// No description provided for @scannedMenuPagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Your pages'**
  String get scannedMenuPagesTitle;

  /// No description provided for @scannedMenuPagesNote.
  ///
  /// In en, this message translates to:
  /// **'Check the dish names against your pages: the AI may misread a word.'**
  String get scannedMenuPagesNote;

  /// No description provided for @scannedMenuPageLabel.
  ///
  /// In en, this message translates to:
  /// **'Page {number}'**
  String scannedMenuPageLabel(int number);

  /// No description provided for @scannedMenuPdfPage.
  ///
  /// In en, this message translates to:
  /// **'PDF document'**
  String get scannedMenuPdfPage;

  /// No description provided for @scannedMenuPagesClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get scannedMenuPagesClose;

  /// No description provided for @scannedPageHeader.
  ///
  /// In en, this message translates to:
  /// **'Page {number} of {total}'**
  String scannedPageHeader(int number, int total);

  /// No description provided for @scannedPageUnknown.
  ///
  /// In en, this message translates to:
  /// **'Page unknown'**
  String get scannedPageUnknown;

  /// No description provided for @scannedPageUnknownExplain.
  ///
  /// In en, this message translates to:
  /// **'The AI did not say which page these dishes are on.'**
  String get scannedPageUnknownExplain;

  /// No description provided for @scannedPageDishCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 dish} other{{count} dishes}}'**
  String scannedPageDishCount(int count);

  /// No description provided for @scannedPageHeaderOpen.
  ///
  /// In en, this message translates to:
  /// **'View this page'**
  String get scannedPageHeaderOpen;

  /// No description provided for @scannedPageChipAll.
  ///
  /// In en, this message translates to:
  /// **'All pages'**
  String get scannedPageChipAll;

  /// No description provided for @scannedPageChipSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Show dishes read from {page}'**
  String scannedPageChipSemanticLabel(String page);

  /// No description provided for @scannedMenuPagesGone.
  ///
  /// In en, this message translates to:
  /// **'The photographs of this scan are no longer on this device, so its pages are listed by number only.'**
  String get scannedMenuPagesGone;

  /// No description provided for @scannedPagesReadFromPage.
  ///
  /// In en, this message translates to:
  /// **'Read from this page'**
  String get scannedPagesReadFromPage;

  /// No description provided for @scanScreenIntro.
  ///
  /// In en, this message translates to:
  /// **'Photograph the pages of a menu, choose photos from your library, or choose a PDF. KetoClub reads the dishes off the pages and analyses them.'**
  String get scanScreenIntro;

  /// No description provided for @scanScreenModePages.
  ///
  /// In en, this message translates to:
  /// **'Photos & PDF'**
  String get scanScreenModePages;

  /// No description provided for @scanScreenModePaste.
  ///
  /// In en, this message translates to:
  /// **'Paste text'**
  String get scanScreenModePaste;

  /// No description provided for @scanScreenModeQr.
  ///
  /// In en, this message translates to:
  /// **'QR code'**
  String get scanScreenModeQr;

  /// No description provided for @scanScreenQrIntro.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code on your table to open the restaurant\'s menu.'**
  String get scanScreenQrIntro;

  /// No description provided for @scanScreenActionTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get scanScreenActionTakePhoto;

  /// No description provided for @scanScreenActionChoosePhotos.
  ///
  /// In en, this message translates to:
  /// **'Choose photos'**
  String get scanScreenActionChoosePhotos;

  /// No description provided for @scanScreenActionChoosePdf.
  ///
  /// In en, this message translates to:
  /// **'Choose a PDF'**
  String get scanScreenActionChoosePdf;

  /// No description provided for @scanScreenPagesHeading.
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get scanScreenPagesHeading;

  /// No description provided for @scanScreenPageCount.
  ///
  /// In en, this message translates to:
  /// **'{count} of {max} pages'**
  String scanScreenPageCount(int count, int max);

  /// No description provided for @scanScreenCapReached.
  ///
  /// In en, this message translates to:
  /// **'That is the most pages one scan can hold. Remove a page to add another.'**
  String get scanScreenCapReached;

  /// No description provided for @scanScreenPageLabel.
  ///
  /// In en, this message translates to:
  /// **'Page {number}'**
  String scanScreenPageLabel(int number);

  /// No description provided for @scanScreenPdfLabel.
  ///
  /// In en, this message translates to:
  /// **'PDF document'**
  String get scanScreenPdfLabel;

  /// No description provided for @scanScreenPageSizeKb.
  ///
  /// In en, this message translates to:
  /// **'{kb} KB'**
  String scanScreenPageSizeKb(int kb);

  /// No description provided for @scanScreenRemovePage.
  ///
  /// In en, this message translates to:
  /// **'Remove page {number}'**
  String scanScreenRemovePage(int number);

  /// No description provided for @scanScreenReorderPage.
  ///
  /// In en, this message translates to:
  /// **'Move page {number}. Drag to reorder'**
  String scanScreenReorderPage(int number);

  /// No description provided for @scanScreenPreviewPage.
  ///
  /// In en, this message translates to:
  /// **'Preview page {number}'**
  String scanScreenPreviewPage(int number);

  /// No description provided for @scanScreenTooManyPages.
  ///
  /// In en, this message translates to:
  /// **'One scan holds at most {max} pages. The pages over the limit were not added.'**
  String scanScreenTooManyPages(int max);

  /// No description provided for @scanScreenPageTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That page is larger than {mb} MB, so it was not added. Try a smaller photo or a smaller PDF.'**
  String scanScreenPageTooLarge(int mb);

  /// No description provided for @scanScreenAnalysePages.
  ///
  /// In en, this message translates to:
  /// **'Analyse pages'**
  String get scanScreenAnalysePages;

  /// No description provided for @scanScreenDisclosureWeb.
  ///
  /// In en, this message translates to:
  /// **'The pages are sent to KetoClub\'s server, which forwards them to Google\'s Gemini API to be read. The transcribed menu, its analysis, and the name and city you give it are also stored on KetoClub\'s server, anonymously.'**
  String get scanScreenDisclosureWeb;

  /// No description provided for @scanScreenDisclosureDirect.
  ///
  /// In en, this message translates to:
  /// **'The pages are sent straight from this device to Google\'s Gemini API, using your own API key. The transcribed menu, its analysis, and the name and city you give it are also stored on KetoClub\'s server, anonymously.'**
  String get scanScreenDisclosureDirect;

  /// No description provided for @scanScreenDisclosureDirectViaBackend.
  ///
  /// In en, this message translates to:
  /// **'The pages are sent from this device to KetoClub\'s server, which forwards them to Google\'s Gemini API to be read. Your own API key is used only if the server cannot be reached. The transcribed menu, its analysis, and the name and city you give it are also stored on KetoClub\'s server, anonymously.'**
  String get scanScreenDisclosureDirectViaBackend;

  /// No description provided for @scanScreenSettingsLink.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get scanScreenSettingsLink;

  /// No description provided for @scanScreenFailureNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Scanning is not available on this build.'**
  String get scanScreenFailureNotConfigured;

  /// No description provided for @scanScreenFailureNeedsServer.
  ///
  /// In en, this message translates to:
  /// **'Scanning needs KetoClub\'s server, and this build is not connected to one. Pasting the menu text still works.'**
  String get scanScreenFailureNeedsServer;

  /// No description provided for @scanScreenFailureServerNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'KetoClub\'s server is not set up to read menu pages yet. Pasting the menu text still works.'**
  String get scanScreenFailureServerNotConfigured;

  /// No description provided for @scanScreenFailureOffline.
  ///
  /// In en, this message translates to:
  /// **'You look offline. Your pages are kept; reconnect and try again.'**
  String get scanScreenFailureOffline;

  /// No description provided for @scanScreenFailureTimeout.
  ///
  /// In en, this message translates to:
  /// **'The AI model was too slow. Your pages are kept; try again.'**
  String get scanScreenFailureTimeout;

  /// No description provided for @scanScreenFailureRateLimited.
  ///
  /// In en, this message translates to:
  /// **'The daily AI limit is used up. Your pages are kept; try again later.'**
  String get scanScreenFailureRateLimited;

  /// No description provided for @scanScreenFailureBadResponse.
  ///
  /// In en, this message translates to:
  /// **'The AI model gave an unusable answer. Your pages are kept; try again.'**
  String get scanScreenFailureBadResponse;

  /// No description provided for @scanScreenFailureNoDishesFound.
  ///
  /// In en, this message translates to:
  /// **'No dishes could be read from these pages. Check that the photos are sharp and well lit, or paste the text instead.'**
  String get scanScreenFailureNoDishesFound;

  /// No description provided for @scanScreenFailureBackendUnreachable.
  ///
  /// In en, this message translates to:
  /// **'KetoClub\'s server could not be reached. Your pages are kept; try again.'**
  String get scanScreenFailureBackendUnreachable;

  /// No description provided for @scanScreenFailureConsentWithheld.
  ///
  /// In en, this message translates to:
  /// **'Scanning sends the pages to Google\'s Gemini API to be read. Allow AI analysis in Settings to scan a menu.'**
  String get scanScreenFailureConsentWithheld;

  /// No description provided for @scanScreenFailureApiKeyMissing.
  ///
  /// In en, this message translates to:
  /// **'Add your Gemini API key in Settings to scan a menu.'**
  String get scanScreenFailureApiKeyMissing;

  /// No description provided for @scanScreenFailurePagesTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Your pages are too large to send together, even after shrinking them. Remove a page and try again.'**
  String get scanScreenFailurePagesTooLarge;

  /// No description provided for @scanScreenFailureApiKeyRejected.
  ///
  /// In en, this message translates to:
  /// **'Gemini rejected your API key. Check it in Settings, then try again.'**
  String get scanScreenFailureApiKeyRejected;

  /// No description provided for @websiteMenuNotFound.
  ///
  /// In en, this message translates to:
  /// **'KetoClub could not find a menu it can read on {site}.'**
  String websiteMenuNotFound(String site);

  /// No description provided for @websiteDisallowedByRobots.
  ///
  /// In en, this message translates to:
  /// **'{site} asks apps like KetoClub not to read its pages, so KetoClub does not.'**
  String websiteDisallowedByRobots(String site);

  /// No description provided for @websiteJsOnlyPage.
  ///
  /// In en, this message translates to:
  /// **'{site} only shows its menu with JavaScript, which KetoClub cannot read yet.'**
  String websiteJsOnlyPage(String site);

  /// No description provided for @websiteUnreachable.
  ///
  /// In en, this message translates to:
  /// **'{site} did not answer. Try again later.'**
  String websiteUnreachable(String site);

  /// No description provided for @websiteTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The menu on {site} is too large for KetoClub to read.'**
  String websiteTooLarge(String site);

  /// No description provided for @websiteRateLimited.
  ///
  /// In en, this message translates to:
  /// **'KetoClub read {site} a moment ago. Wait a minute, then try again.'**
  String websiteRateLimited(String site);

  /// No description provided for @websitePdfUnread.
  ///
  /// In en, this message translates to:
  /// **'The menu on {site} is a PDF, which only AI analysis can read, and it could not be read now. Check AI analysis in Settings, then try again.'**
  String websitePdfUnread(String site);

  /// No description provided for @scanQrAction.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get scanQrAction;

  /// No description provided for @scanQrTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get scanQrTitle;

  /// No description provided for @scanQrInstruction.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the QR code on the table.'**
  String get scanQrInstruction;

  /// No description provided for @scanQrCameraDenied.
  ///
  /// In en, this message translates to:
  /// **'KetoClub cannot use the camera. Allow camera access in your device settings, or paste the menu link instead.'**
  String get scanQrCameraDenied;

  /// No description provided for @scanQrCameraUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The camera could not start. Close this screen and paste the menu link instead.'**
  String get scanQrCameraUnavailable;

  /// No description provided for @scanQrUnsupportedSource.
  ///
  /// In en, this message translates to:
  /// **'{name} menus are not supported yet. Photograph the menu instead.'**
  String scanQrUnsupportedSource(String name);

  /// No description provided for @scanQrPhotographInstead.
  ///
  /// In en, this message translates to:
  /// **'This QR code does not lead to a menu KetoClub can read. Photograph the menu instead.'**
  String get scanQrPhotographInstead;

  /// No description provided for @carbBudgetFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Budget for tonight (g)'**
  String get carbBudgetFieldLabel;

  /// No description provided for @carbBudgetFieldHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 20'**
  String get carbBudgetFieldHint;

  /// No description provided for @carbBudgetFieldClear.
  ///
  /// In en, this message translates to:
  /// **'Clear budget'**
  String get carbBudgetFieldClear;

  /// No description provided for @netCarbsChipLeavesSuffix.
  ///
  /// In en, this message translates to:
  /// **' · leaves {grams}g'**
  String netCarbsChipLeavesSuffix(int grams);

  /// No description provided for @hiddenCarbsSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Possible hidden carbs'**
  String get hiddenCarbsSectionLabel;

  /// No description provided for @hiddenCarbsCertaintySuspected.
  ///
  /// In en, this message translates to:
  /// **'Suspected'**
  String get hiddenCarbsCertaintySuspected;

  /// No description provided for @hiddenCarbsCertaintyLikely.
  ///
  /// In en, this message translates to:
  /// **'Likely'**
  String get hiddenCarbsCertaintyLikely;

  /// No description provided for @drinksGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'Drinks guide'**
  String get drinksGuideTitle;

  /// No description provided for @drinksGuideDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Typical net-carb ranges per standard serving. All figures are estimates — actual values vary by brand, size, and recipe.'**
  String get drinksGuideDisclaimer;

  /// No description provided for @drinksGuideSectionOrderAsIs.
  ///
  /// In en, this message translates to:
  /// **'ORDER AS-IS'**
  String get drinksGuideSectionOrderAsIs;

  /// No description provided for @drinksGuideSectionSwap.
  ///
  /// In en, this message translates to:
  /// **'ASK FOR A SWAP'**
  String get drinksGuideSectionSwap;

  /// No description provided for @drinksGuideSectionSkip.
  ///
  /// In en, this message translates to:
  /// **'SKIP'**
  String get drinksGuideSectionSkip;

  /// No description provided for @drinksGuideCarbsSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Estimated net carbs, not confirmed: {range}'**
  String drinksGuideCarbsSemanticLabel(String range);

  /// No description provided for @actionAskAboutMenu.
  ///
  /// In en, this message translates to:
  /// **'Ask about this menu'**
  String get actionAskAboutMenu;

  /// No description provided for @menuQuestionSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask about this menu'**
  String get menuQuestionSheetTitle;

  /// No description provided for @menuQuestionSheetHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Which dishes are dairy-free?'**
  String get menuQuestionSheetHint;

  /// No description provided for @menuQuestionSheetAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask'**
  String get menuQuestionSheetAsk;

  /// No description provided for @menuQuestionSheetLoading.
  ///
  /// In en, this message translates to:
  /// **'Asking…'**
  String get menuQuestionSheetLoading;

  /// No description provided for @menuQuestionSheetAskAnother.
  ///
  /// In en, this message translates to:
  /// **'Ask another question'**
  String get menuQuestionSheetAskAnother;

  /// No description provided for @menuQuestionFailedNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'AI is not available on this build, so the question could not be answered.'**
  String get menuQuestionFailedNotConfigured;

  /// No description provided for @menuQuestionFailedOffline.
  ///
  /// In en, this message translates to:
  /// **'You look offline. Reconnect and try asking again.'**
  String get menuQuestionFailedOffline;

  /// No description provided for @menuQuestionFailedTimeout.
  ///
  /// In en, this message translates to:
  /// **'The AI model was too slow. Try asking again.'**
  String get menuQuestionFailedTimeout;

  /// No description provided for @menuQuestionFailedRateLimited.
  ///
  /// In en, this message translates to:
  /// **'The daily AI limit is used up. Try again later.'**
  String get menuQuestionFailedRateLimited;

  /// No description provided for @menuQuestionFailedBadResponse.
  ///
  /// In en, this message translates to:
  /// **'The AI gave an unusable answer. Try asking in a different way.'**
  String get menuQuestionFailedBadResponse;

  /// No description provided for @menuQuestionFailedBackendUnreachable.
  ///
  /// In en, this message translates to:
  /// **'KetoClub\'s server could not be reached. Try asking again.'**
  String get menuQuestionFailedBackendUnreachable;

  /// No description provided for @menuQuestionFailedConsentWithheld.
  ///
  /// In en, this message translates to:
  /// **'Allow AI analysis in Settings to ask questions about a menu.'**
  String get menuQuestionFailedConsentWithheld;

  /// No description provided for @menuQuestionFailedApiKeyMissing.
  ///
  /// In en, this message translates to:
  /// **'Add your Gemini API key in Settings to ask questions about a menu.'**
  String get menuQuestionFailedApiKeyMissing;

  /// No description provided for @menuQuestionFailedApiKeyRejected.
  ///
  /// In en, this message translates to:
  /// **'Gemini rejected your API key. Check it in Settings, then try asking again.'**
  String get menuQuestionFailedApiKeyRejected;

  /// The one-sentence helper-tool statement: what the app does and does not do. Shown wherever a restriction result appears (consumed by later Banto work).
  ///
  /// In en, this message translates to:
  /// **'This app reads menus to help you choose. It cannot see the kitchen, verify a recipe or promise accuracy. Always ask the restaurant.'**
  String get helperToolSentence;

  /// Heading that sits above the helper-tool sentence.
  ///
  /// In en, this message translates to:
  /// **'A helper, not a guarantee'**
  String get helperToolTitle;

  /// Plain statement of what leaves the device once restriction profiles exist; the profile never does.
  ///
  /// In en, this message translates to:
  /// **'Your restriction profile and your own words stay on this device. When AI analysis is on, only the menu text, your keto settings and a request to list each dish\'s ingredients are sent — never which restrictions you have.'**
  String get whatLeavesDeviceBanto;

  /// Banto (ALG-08a): title of the full-screen chef card built from the dietary profile alone.
  ///
  /// In en, this message translates to:
  /// **'Your chef card'**
  String get chefCardTitle;

  /// Banto (ALG-08a): the Settings button that opens the chef card.
  ///
  /// In en, this message translates to:
  /// **'Show my chef card'**
  String get chefCardShowButton;

  /// Banto (ALG-08a): shown on the chef card page when the dietary profile is empty.
  ///
  /// In en, this message translates to:
  /// **'Add a restriction in Settings and your chef card appears here.'**
  String get chefCardEmpty;

  /// Banto (ALG-08a): button that shares the chef card as text.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get chefCardShare;

  /// Banto (ALG-08a): accessibility label of the Hebrew/English toggle on the chef card; the card text itself is in the chosen language.
  ///
  /// In en, this message translates to:
  /// **'Card language'**
  String get chefCardLanguageLabel;

  /// Title of the bottom sheet that lists the concerns behind a dish's state (Banto, ALG-06).
  ///
  /// In en, this message translates to:
  /// **'Why this result'**
  String get whySheetTitle;

  /// The dish the Why sheet is about, shown under the title.
  ///
  /// In en, this message translates to:
  /// **'{dish}'**
  String whySheetDishName(String dish);

  /// Evidence tier phrase: the platform said so. The tier phrases are words, never a percentage.
  ///
  /// In en, this message translates to:
  /// **'Declared by the platform'**
  String get whyTierDeclared;

  /// No description provided for @whyTierStated.
  ///
  /// In en, this message translates to:
  /// **'Stated on the menu'**
  String get whyTierStated;

  /// No description provided for @whyTierInferred.
  ///
  /// In en, this message translates to:
  /// **'Inferred from a typical recipe'**
  String get whyTierInferred;

  /// No description provided for @whyTierSuspected.
  ///
  /// In en, this message translates to:
  /// **'Suspected — please ask'**
  String get whyTierSuspected;

  /// No description provided for @whyTierConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed with the staff'**
  String get whyTierConfirmed;

  /// No description provided for @whyTierDenied.
  ///
  /// In en, this message translates to:
  /// **'The staff said it is not there — still ask'**
  String get whyTierDenied;

  /// No description provided for @whySourceName.
  ///
  /// In en, this message translates to:
  /// **'Found in the dish name'**
  String get whySourceName;

  /// No description provided for @whySourceDescription.
  ///
  /// In en, this message translates to:
  /// **'Found in the dish description'**
  String get whySourceDescription;

  /// No description provided for @whySourceOption.
  ///
  /// In en, this message translates to:
  /// **'Found in one of the options'**
  String get whySourceOption;

  /// No description provided for @whySourceHidden.
  ///
  /// In en, this message translates to:
  /// **'A hidden source the text implies'**
  String get whySourceHidden;

  /// No description provided for @whySourceModel.
  ///
  /// In en, this message translates to:
  /// **'Read by the AI, not in the menu text'**
  String get whySourceModel;

  /// The exact menu text a concern matched, quoted.
  ///
  /// In en, this message translates to:
  /// **'Matched: “{text}”'**
  String whyMatchedText(String text);

  /// No description provided for @whyWaiterQuestionLabel.
  ///
  /// In en, this message translates to:
  /// **'Ask the waiter'**
  String get whyWaiterQuestionLabel;

  /// No description provided for @whyEmptyStrict.
  ///
  /// In en, this message translates to:
  /// **'Nothing in the menu text points to your restrictions. Still ask the restaurant.'**
  String get whyEmptyStrict;

  /// No description provided for @whyEmptyFlexible.
  ///
  /// In en, this message translates to:
  /// **'Nothing in the menu text points to your restrictions.'**
  String get whyEmptyFlexible;

  /// Banto (ALG-02b): heading of the first-run screen where the user picks their restrictions.
  ///
  /// In en, this message translates to:
  /// **'What do you avoid?'**
  String get restrictionOnboardingTitle;

  /// No description provided for @restrictionOnboardingBody.
  ///
  /// In en, this message translates to:
  /// **'Pick everything that applies. You can change this any time in Settings. Skip it to use keto only.'**
  String get restrictionOnboardingBody;

  /// No description provided for @restrictionOnboardingContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get restrictionOnboardingContinue;

  /// No description provided for @restrictionOnboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get restrictionOnboardingSkip;

  /// Banto (ALG-02b): the menu screen's one-line summary of the restrictions the menu is read against. Tapping it opens Settings.
  ///
  /// In en, this message translates to:
  /// **'Checking for: {names}'**
  String menuProfileSummary(String names);

  /// Banto (ALG-05): the dish-state pill for a dish that fits a profile with no strict entry. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'Fits'**
  String get stateFitsBadge;

  /// Banto (ALG-05): the dish-state pill for a dish in which nothing was found, for a profile with an allergy or celiac disease. The wording floor: never 'safe', always 'ask the restaurant'.
  ///
  /// In en, this message translates to:
  /// **'No trigger found — ask the restaurant'**
  String get stateFitsStrictBadge;

  /// Banto (ALG-05): the dish-state pill for a dish that fits once something removable is left off.
  ///
  /// In en, this message translates to:
  /// **'Fits with a change'**
  String get stateFitsWithChangeBadge;

  /// Banto (ALG-05): the dish-state pill for a dish that may hide a strict restriction.
  ///
  /// In en, this message translates to:
  /// **'Ask first'**
  String get stateAskBadge;

  /// Banto (ALG-05): the dish-state pill for a dish that names a restriction in the dish itself.
  ///
  /// In en, this message translates to:
  /// **'Avoid'**
  String get stateAvoidBadge;

  /// Banto (ALG-05): counter tile label for dishes that fit (no strict entry in the profile).
  ///
  /// In en, this message translates to:
  /// **'Fit'**
  String get stateFitsTile;

  /// Banto (ALG-05): counter tile label for dishes in which nothing was found, for a strict profile. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'No trigger found'**
  String get stateFitsStrictTile;

  /// Banto (ALG-05): counter tile label for dishes that fit with a change.
  ///
  /// In en, this message translates to:
  /// **'With a change'**
  String get stateFitsWithChangeTile;

  /// Banto (ALG-05): counter tile label for dishes to ask the restaurant about.
  ///
  /// In en, this message translates to:
  /// **'To ask'**
  String get stateAskTile;

  /// Banto (ALG-05): counter tile label for dishes to avoid.
  ///
  /// In en, this message translates to:
  /// **'Avoid'**
  String get stateAvoidTile;

  /// Banto (ALG-05): legend line for the fits state (no strict entry).
  ///
  /// In en, this message translates to:
  /// **'Nothing in the menu text conflicts with your restrictions.'**
  String get stateLegendFits;

  /// Banto (ALG-05): legend line for the fits state for a strict profile. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'No trigger for your restrictions was found in the menu text. The menu text is all the app read, so ask the restaurant.'**
  String get stateLegendFitsStrict;

  /// Banto (ALG-05): legend line for the fits-with-a-change state.
  ///
  /// In en, this message translates to:
  /// **'Fits once something that can be left off is left off. The waiter line says what to ask for.'**
  String get stateLegendFitsWithChange;

  /// Banto (ALG-05): legend line for the ask state.
  ///
  /// In en, this message translates to:
  /// **'Something in the dish may hide one of your restrictions. Ask the restaurant before ordering.'**
  String get stateLegendAsk;

  /// Banto (ALG-05): legend line for the avoid state.
  ///
  /// In en, this message translates to:
  /// **'One of your restrictions is named in the dish itself, or keto, when it is in your profile, rules it out.'**
  String get stateLegendAvoid;

  /// Banto (ALG-05): legend note that the four counters count food only (D21).
  ///
  /// In en, this message translates to:
  /// **'The counters cover food only. Drinks, sauces and extras are still checked and listed, but are not counted.'**
  String get stateLegendFoodOnly;

  /// Banto (ALG-05): the 'Showing' label for the fits filter (no strict entry).
  ///
  /// In en, this message translates to:
  /// **'Showing dishes that fit'**
  String get menuShowingFits;

  /// Banto (ALG-05): the 'Showing' label for the fits filter, strict profile.
  ///
  /// In en, this message translates to:
  /// **'Showing dishes with no trigger found'**
  String get menuShowingFitsStrict;

  /// Banto (ALG-05): the 'Showing' label for the fits-with-a-change filter.
  ///
  /// In en, this message translates to:
  /// **'Showing dishes that fit with a change'**
  String get menuShowingFitsWithChange;

  /// Banto (ALG-05): the 'Showing' label for the ask filter.
  ///
  /// In en, this message translates to:
  /// **'Showing dishes to ask about'**
  String get menuShowingAsk;

  /// Banto (ALG-05): the 'Showing' label for the avoid filter.
  ///
  /// In en, this message translates to:
  /// **'Showing what to avoid'**
  String get menuShowingAvoid;

  /// Banto (ALG-05): the 'Showing' label for the default filter of a strict profile (fits, fits with a change and ask; avoid hidden).
  ///
  /// In en, this message translates to:
  /// **'Showing everything except what to avoid'**
  String get menuShowingNotAvoid;

  /// Banto (ALG-05): the menu header's counts in place of the keto score, for a profile without keto and without a strict entry.
  ///
  /// In en, this message translates to:
  /// **'{fits} fit · {change} with a change · {ask} to ask'**
  String headerStateCounts(int fits, int change, int ask);

  /// Banto (ALG-05): the menu header's counts in place of the keto score, for a profile with a strict entry. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'{fits} no trigger found · {change} with a change · {ask} to ask'**
  String headerStateCountsStrict(int fits, int change, int ask);

  /// Banto (ALG-05): where a concern was found, on the dish card's concern line.
  ///
  /// In en, this message translates to:
  /// **'in the name'**
  String get concernSourceName;

  /// Banto (ALG-05): concern source on the dish card.
  ///
  /// In en, this message translates to:
  /// **'in the description'**
  String get concernSourceDescription;

  /// Banto (ALG-05): concern source on the dish card (an option value); followed by the option text when known.
  ///
  /// In en, this message translates to:
  /// **'option'**
  String get concernSourceOption;

  /// Banto (ALG-05): concern source on the dish card (a hidden source, e.g. soy sauce); followed by the text when known.
  ///
  /// In en, this message translates to:
  /// **'hidden'**
  String get concernSourceHidden;

  /// Banto (ALG-05): concern source on the dish card (an ingredient the AI read); followed by the ingredient when known.
  ///
  /// In en, this message translates to:
  /// **'read by the AI'**
  String get concernSourceModel;

  /// Banto (ALG-05): a concern source followed by the menu text it matched.
  ///
  /// In en, this message translates to:
  /// **'{source}: {text}'**
  String concernSourceWithText(String source, String text);

  /// Banto (ALG-05): a concern's certainty in words, never a number.
  ///
  /// In en, this message translates to:
  /// **'stated'**
  String get concernCertaintyStated;

  /// Banto (ALG-05): a concern's certainty in words.
  ///
  /// In en, this message translates to:
  /// **'likely'**
  String get concernCertaintyLikely;

  /// Banto (ALG-05): a concern's certainty in words.
  ///
  /// In en, this message translates to:
  /// **'suspected — ask'**
  String get concernCertaintySuspected;

  /// Banto (ALG-05): screen-reader label of one concern line on the dish card.
  ///
  /// In en, this message translates to:
  /// **'{restriction}: {source}, {certainty}'**
  String concernLineSemanticLabel(
    String restriction,
    String source,
    String certainty,
  );

  /// Banto (ALG-05/06): the dish-card button that opens the Why sheet.
  ///
  /// In en, this message translates to:
  /// **'Why?'**
  String get dishCardWhy;

  /// Banto (ALG-05/06): screen-reader label of the Why button.
  ///
  /// In en, this message translates to:
  /// **'Why this result for {dish}'**
  String dishCardWhySemanticLabel(String dish);

  /// Banto (ALG-05): the dish card's waiter row for a dish in the ask state.
  ///
  /// In en, this message translates to:
  /// **'What to ask the waiter'**
  String get dishCardAskQuestion;

  /// Banto (ALG-05): second engine chip, shown beside the AI chip when the on-device rules also checked the menu for the profile and found something.
  ///
  /// In en, this message translates to:
  /// **'Rules checked'**
  String get engineChipRulesChecked;

  /// Banto (ALG-05): screen-reader label of the rules-checked chip.
  ///
  /// In en, this message translates to:
  /// **'The app\'s own rules also checked this menu for your restrictions'**
  String get engineChipRulesCheckedSemanticLabel;

  /// Banto (ALG-05): the words after a concern's restriction chip on the dish card: where it was found, then how sure.
  ///
  /// In en, this message translates to:
  /// **'{source} · {certainty}'**
  String concernLineText(String source, String certainty);

  /// Banto (ALG-09): the Why sheet's tier phrase for a concern lowered by the restaurant's own words (the dish text or its section heading), as opposed to whyTierDeclared, a platform tag.
  ///
  /// In en, this message translates to:
  /// **'Declared by the restaurant'**
  String get whyTierDeclaredRestaurant;

  /// Banto (ALG-09): under a concern lowered by a declaration such as gluten-free or vegan, quoting the declaration. Never says the dish is free of it.
  ///
  /// In en, this message translates to:
  /// **'Marked “{text}” — this lowers the finding but never rules it out'**
  String whyDeclaredAbsent(String text);

  /// Banto (ALG-09): dish-card chip when the delivery platform flags the dish kosher. Always attributed to the platform, never a statement by the app.
  ///
  /// In en, this message translates to:
  /// **'Declared kosher by the platform'**
  String get dishCardDeclaredKosher;

  /// Banto (ALG-08b): the Waiter Card action that opens the chef card for this dish.
  ///
  /// In en, this message translates to:
  /// **'Chef card'**
  String get waiterCardChefCard;

  /// Banto (ALG-15): the menu overflow entry that copies a short allergy note, in the menu's language, for a delivery app's note box.
  ///
  /// In en, this message translates to:
  /// **'Copy allergy note'**
  String get menuAllergyNoteAction;

  /// Banto (ALG-15): the snack bar shown once the allergy note is on the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Allergy note copied'**
  String get menuAllergyNoteCopied;

  /// Banto (ALG-15): the snack bar action that shares the allergy note as text.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get menuAllergyNoteShare;

  /// Banto (ALG-15): the subject line of a shared allergy note, where the platform shows one.
  ///
  /// In en, this message translates to:
  /// **'Allergy note'**
  String get menuAllergyNoteSubject;

  /// Banto (ALG-07): the kitchen notice's collapsed line; {things} is a list of kitchenKind* nouns joined by kitchenListSeparator and kitchenListAnd. Never says safe.
  ///
  /// In en, this message translates to:
  /// **'This kitchen has {things} — ask about cross-contact'**
  String kitchenNoticeSummary(String things);

  /// Banto (ALG-07): separator between items of a list in the kitchen notice, except before the last.
  ///
  /// In en, this message translates to:
  /// **', '**
  String get kitchenListSeparator;

  /// Banto (ALG-07): joins the last item of a list in the kitchen notice.
  ///
  /// In en, this message translates to:
  /// **'{rest} and {last}'**
  String kitchenListAnd(String rest, String last);

  /// Banto (ALG-07): kitchen signal noun inside kitchenNoticeSummary and whySourceKitchen.
  ///
  /// In en, this message translates to:
  /// **'a fryer'**
  String get kitchenKindFryer;

  /// Banto (ALG-07): kitchen signal noun.
  ///
  /// In en, this message translates to:
  /// **'a wok'**
  String get kitchenKindWok;

  /// Banto (ALG-07): kitchen signal noun (meat and fish on one grill).
  ///
  /// In en, this message translates to:
  /// **'a shared grill'**
  String get kitchenKindSharedGrill;

  /// Banto (ALG-07): kitchen signal noun (bread, pastry or pizza on the menu).
  ///
  /// In en, this message translates to:
  /// **'a bakery'**
  String get kitchenKindBakery;

  /// Banto (ALG-07): kitchen signal noun.
  ///
  /// In en, this message translates to:
  /// **'nuts'**
  String get kitchenKindNuts;

  /// Banto (ALG-07): kitchen signal noun.
  ///
  /// In en, this message translates to:
  /// **'sesame'**
  String get kitchenKindSesame;

  /// Banto (ALG-07): heading of the fryer row in the expanded kitchen notice.
  ///
  /// In en, this message translates to:
  /// **'Fryer'**
  String get kitchenTitleFryer;

  /// Banto (ALG-07): heading of the wok row in the expanded kitchen notice.
  ///
  /// In en, this message translates to:
  /// **'Wok'**
  String get kitchenTitleWok;

  /// Banto (ALG-07): heading of the shared-grill row in the expanded kitchen notice.
  ///
  /// In en, this message translates to:
  /// **'Shared grill'**
  String get kitchenTitleSharedGrill;

  /// Banto (ALG-07): heading of the bakery row in the expanded kitchen notice.
  ///
  /// In en, this message translates to:
  /// **'Bakery'**
  String get kitchenTitleBakery;

  /// Banto (ALG-07): heading of the nuts row in the expanded kitchen notice.
  ///
  /// In en, this message translates to:
  /// **'Nuts'**
  String get kitchenTitleNuts;

  /// Banto (ALG-07): heading of the sesame row in the expanded kitchen notice.
  ///
  /// In en, this message translates to:
  /// **'Sesame'**
  String get kitchenTitleSesame;

  /// Banto (ALG-07): the action that expands the kitchen notice.
  ///
  /// In en, this message translates to:
  /// **'Show questions'**
  String get kitchenNoticeShow;

  /// Banto (ALG-07): the action that collapses the kitchen notice.
  ///
  /// In en, this message translates to:
  /// **'Hide questions'**
  String get kitchenNoticeHide;

  /// Banto (ALG-07): which of the profile's strict restrictions a kitchen signal threatens, named in the UI language.
  ///
  /// In en, this message translates to:
  /// **'Matters for: {restrictions}'**
  String kitchenNoticeMattersFor(String restrictions);

  /// Banto (ALG-07): the dishes, as the menu prints them, that reveal a kitchen signal.
  ///
  /// In en, this message translates to:
  /// **'Seen in: {dishes}'**
  String kitchenNoticeSeenIn(String dishes);

  /// Banto (ALG-07): label above a kitchen signal's question, which is shown in the menu's language.
  ///
  /// In en, this message translates to:
  /// **'Ask the staff'**
  String get kitchenNoticeQuestionLabel;

  /// Banto (ALG-07): screen-reader label of a kitchen question's copy button; {thing} is a kitchenKind* noun.
  ///
  /// In en, this message translates to:
  /// **'Copy the question about {thing}'**
  String kitchenNoticeCopyLabel(String thing);

  /// Banto (ALG-07): concern source on the dish card for a kitchen cross-contact concern; followed by a kitchenKind* noun.
  ///
  /// In en, this message translates to:
  /// **'kitchen'**
  String get concernSourceKitchen;

  /// Banto (ALG-07): Why sheet line for a kitchen cross-contact concern; {thing} is a kitchenKind* noun. Never says safe.
  ///
  /// In en, this message translates to:
  /// **'This kitchen has {thing} — ask about cross-contact'**
  String whySourceKitchen(String thing);

  /// Banto (ALG-07): Why sheet line for a kitchen concern whose kind is unknown.
  ///
  /// In en, this message translates to:
  /// **'From the kitchen, not the dish — ask about cross-contact'**
  String get whySourceKitchenGeneric;

  /// Banto (ALG-12): the Settings group listing the named profiles on the device.
  ///
  /// In en, this message translates to:
  /// **'People on this device'**
  String get settingsProfiles;

  /// Banto (ALG-12): the note under the people group, with the health-data wording.
  ///
  /// In en, this message translates to:
  /// **'Add the people you eat with and check a menu for any of you together. Each profile is health data and stays on this device.'**
  String get settingsProfilesNote;

  /// Banto (ALG-12): the name of the device owner's own profile until they rename it.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get profileDefaultName;

  /// Banto (ALG-12): the summary of a profile with no restriction, which is read as keto.
  ///
  /// In en, this message translates to:
  /// **'Keto only'**
  String get profileKetoOnly;

  /// Banto (ALG-12): the button that adds a named profile.
  ///
  /// In en, this message translates to:
  /// **'Add person'**
  String get settingsProfilesAdd;

  /// Banto (ALG-12): the button that opens the import screen for a shared profile.
  ///
  /// In en, this message translates to:
  /// **'Import a profile'**
  String get settingsProfilesImport;

  /// Banto (ALG-12): title of the dialog naming a new profile.
  ///
  /// In en, this message translates to:
  /// **'Add a person'**
  String get profileNameAddTitle;

  /// Banto (ALG-12): title of the dialog renaming a profile.
  ///
  /// In en, this message translates to:
  /// **'Rename profile'**
  String get profileNameRenameTitle;

  /// Banto (ALG-12): label of the profile name field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get profileNameLabel;

  /// Banto (ALG-12): confirms the profile name dialog.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get profileNameSave;

  /// Banto (ALG-12): the profile editor's rename action.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get profileEditorRename;

  /// Banto (ALG-12): the profile editor's export action.
  ///
  /// In en, this message translates to:
  /// **'Share this profile'**
  String get profileEditorExport;

  /// Banto (ALG-12): the profile editor's delete action (not offered for the owner's own profile).
  ///
  /// In en, this message translates to:
  /// **'Delete this profile'**
  String get profileEditorDelete;

  /// Banto (ALG-12): title of the delete confirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}\'s profile?'**
  String profileDeleteTitle(String name);

  /// Banto (ALG-12): body of the delete confirmation.
  ///
  /// In en, this message translates to:
  /// **'Their restrictions are removed from this device.'**
  String get profileDeleteBody;

  /// Banto (ALG-12): confirms deleting a profile.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get profileDeleteConfirm;

  /// Banto (ALG-12): title of the dialog shown before a profile is exported.
  ///
  /// In en, this message translates to:
  /// **'Share health data?'**
  String get profileExportTitle;

  /// Banto (ALG-12): body of the export dialog.
  ///
  /// In en, this message translates to:
  /// **'This profile lists {name}\'s dietary restrictions, which are health data. It leaves this device only as the text you send, so share it only with people you trust.'**
  String profileExportBody(String name);

  /// Banto (ALG-12): confirms exporting a profile.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get profileExportConfirm;

  /// Banto (ALG-12): shown when the profile was copied because no share sheet is available.
  ///
  /// In en, this message translates to:
  /// **'Profile copied. Paste it on the other device.'**
  String get profileExportCopied;

  /// Banto (ALG-12): the import screen's title.
  ///
  /// In en, this message translates to:
  /// **'Import a profile'**
  String get profileImportTitle;

  /// Banto (ALG-12): the import screen's health-data wording.
  ///
  /// In en, this message translates to:
  /// **'A shared profile is health data: someone\'s dietary restrictions. Nothing is saved until you choose to save it, and then only on this device.'**
  String get profileImportBody;

  /// Banto (ALG-12): label of the import screen's text field.
  ///
  /// In en, this message translates to:
  /// **'Paste the shared profile'**
  String get profileImportField;

  /// Banto (ALG-12): reads the pasted text and shows what it holds.
  ///
  /// In en, this message translates to:
  /// **'Read profile'**
  String get profileImportRead;

  /// Banto (ALG-12): shown when the pasted text cannot be read as a profile.
  ///
  /// In en, this message translates to:
  /// **'This text is not a shared profile.'**
  String get profileImportInvalid;

  /// Banto (ALG-12): the question above the import preview.
  ///
  /// In en, this message translates to:
  /// **'Save this profile on this device?'**
  String get profileImportAsk;

  /// Banto (ALG-12): saves an imported profile.
  ///
  /// In en, this message translates to:
  /// **'Save on this device'**
  String get profileImportSave;

  /// Banto (ALG-12): shown when no profile can be added.
  ///
  /// In en, this message translates to:
  /// **'This device already holds as many profiles as it can.'**
  String get profileImportFull;

  /// Banto (ALG-12): the profile editor's restrictions heading.
  ///
  /// In en, this message translates to:
  /// **'Restrictions'**
  String get profileEditorRestrictions;

  /// Banto (ALG-12): title of the sheet that combines profiles for a menu.
  ///
  /// In en, this message translates to:
  /// **'Check this menu for'**
  String get groupCombineTitle;

  /// Banto (ALG-12): applies the combined profiles.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get groupCombineApply;

  /// Banto (ALG-12): opens the chef card with one section per selected person.
  ///
  /// In en, this message translates to:
  /// **'Chef card for these people'**
  String get groupCombineChefCard;

  /// Banto (ALG-12): opens Settings from the combine sheet.
  ///
  /// In en, this message translates to:
  /// **'Manage people in Settings'**
  String get groupCombineManage;

  /// Banto (ALG-12): the menu header line for a group with no strict entry. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 dish fits everyone} other{{count} dishes fit everyone}}'**
  String groupFitsEveryone(int count);

  /// Banto (ALG-12): the menu header line for a group with a strict entry. Never 'safe' and never 'fits'.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 dish with no trigger found for anyone} other{{count} dishes with no trigger found for anyone}}'**
  String groupFitsEveryoneStrict(int count);

  /// Banto (ALG-12): one person's result on a dish card's breakdown line.
  ///
  /// In en, this message translates to:
  /// **'{name}: {state}'**
  String groupBreakdownEntry(String name, String state);

  /// Banto (ALG-12): screen-reader label of the per-person breakdown line.
  ///
  /// In en, this message translates to:
  /// **'For each person: {breakdown}'**
  String groupBreakdownSemanticLabel(String breakdown);

  /// Banto (ALG-17): the picker's hint under FODMAP, histamine and small portions, which only ever mark a dish 'may be high in'. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'A heads-up from common guidance, not a measurement'**
  String get restrictionHeadsUpHint;

  /// Banto (ALG-17): the picker's hint under alpha-gal, whose dairy reaction is individual and carried by the Milk entry.
  ///
  /// In en, this message translates to:
  /// **'Mammal meat and its products. If dairy affects you too, add Milk as well'**
  String get restrictionAlphaGalHint;

  /// Banto (ALG-17): heading of the picker's free-text restriction field.
  ///
  /// In en, this message translates to:
  /// **'Add your own'**
  String get restrictionOwnTitle;

  /// Banto (ALG-17): the note above the free-text restriction field. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'Something not on the list, such as mango or coriander. Checked on this device only, as strictly as an allergy, by the words the menu prints.'**
  String get restrictionOwnNote;

  /// Banto (ALG-17): label of the free-text restriction field.
  ///
  /// In en, this message translates to:
  /// **'Food to avoid'**
  String get restrictionOwnField;

  /// Banto (ALG-17): adds the typed word as the user's own restriction.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get restrictionOwnAdd;

  /// Banto (ALG-17): subtitle of a free-text restriction row in Settings and the profile editor.
  ///
  /// In en, this message translates to:
  /// **'Your own · checked strictly'**
  String get restrictionOwnRowSubtitle;

  /// Banto (ALG-17): the certainty words of a FODMAP, histamine or small-portions concern on the dish card. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'may be high in it — a heads-up, not a measurement'**
  String get concernCertaintyHeadsUp;

  /// Banto (ALG-11): closes the helper-tool sheet shown once when the first restriction is added.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get helperToolOk;

  /// Banto (ALG-06): the Why sheet's coverage line when the dish has no description and no options.
  ///
  /// In en, this message translates to:
  /// **'The menu gives only the dish\'s name.'**
  String get whyCoverageNameOnly;

  /// Banto (ALG-06): coverage line, description but no options.
  ///
  /// In en, this message translates to:
  /// **'The menu gives the name and a description.'**
  String get whyCoverageDescription;

  /// Banto (ALG-06): coverage line, options but no description.
  ///
  /// In en, this message translates to:
  /// **'The menu gives the name and options.'**
  String get whyCoverageOptions;

  /// Banto (ALG-06): coverage line, description and options.
  ///
  /// In en, this message translates to:
  /// **'The menu gives the name, a description and options.'**
  String get whyCoverageFull;

  /// Banto (ALG-06): who read the dish when the model's ingredient list is present. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'AI listed its ingredients, and the rules read the menu text too.'**
  String get whyCoverageModelAndRules;

  /// Banto (ALG-04, ALG-06): who read the dish when no model ingredient list exists; the strictest wording. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'Only the rules read the menu text, with no AI ingredient list. Ask the restaurant.'**
  String get whyCoverageRulesOnly;

  /// Banto (ALG-17): the GLP-1 tag part for a dish built around its protein. A tag, never a colour, a state or a number.
  ///
  /// In en, this message translates to:
  /// **'Protein-forward'**
  String get glp1TagProteinForward;

  /// Banto (ALG-17): the GLP-1 tag part for a dish the menu calls small, a starter or a half portion.
  ///
  /// In en, this message translates to:
  /// **'Small portion'**
  String get glp1TagSmallPortion;

  /// Banto (ALG-17): screen-reader label of the GLP-1 tag.
  ///
  /// In en, this message translates to:
  /// **'For small portions: {tags}'**
  String glp1TagSemanticLabel(String tags);

  /// Banto (ALG-13): heading of the Settings section that sets a travel destination.
  ///
  /// In en, this message translates to:
  /// **'Trip mode'**
  String get settingsTrip;

  /// Banto (ALG-13): the note at the top of the trip section. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'Travelling? Pick where you are going: see what restaurants there must tell you and which local dishes hide your restrictions. Keto is unchanged, and your destination stays on this device.'**
  String get settingsTripNote;

  /// Banto (ALG-13): opens the destination picker when no trip is on.
  ///
  /// In en, this message translates to:
  /// **'Choose a destination'**
  String get settingsTripPick;

  /// Banto (ALG-13): the trip row's title while a trip is on.
  ///
  /// In en, this message translates to:
  /// **'Trip to {country}'**
  String settingsTripActive(String country);

  /// Banto (ALG-13): the trip row's subtitle; the row opens the briefing page.
  ///
  /// In en, this message translates to:
  /// **'Before you go: what to ask, and where your restrictions hide'**
  String get settingsTripBriefing;

  /// Banto (ALG-13): reopens the destination picker while a trip is on.
  ///
  /// In en, this message translates to:
  /// **'Change destination'**
  String get settingsTripChange;

  /// Banto (ALG-13): one tap that switches trip mode off.
  ///
  /// In en, this message translates to:
  /// **'Turn off trip mode'**
  String get settingsTripOff;

  /// Banto (ALG-13): title of the destination picker.
  ///
  /// In en, this message translates to:
  /// **'Where are you going?'**
  String get tripPickerTitle;

  /// Banto (ALG-13): a trip destination.
  ///
  /// In en, this message translates to:
  /// **'Israel'**
  String get tripCountryIsrael;

  /// Banto (ALG-13): a trip destination.
  ///
  /// In en, this message translates to:
  /// **'United States'**
  String get tripCountryUnitedStates;

  /// Banto (ALG-13): a trip destination.
  ///
  /// In en, this message translates to:
  /// **'United Kingdom'**
  String get tripCountryUnitedKingdom;

  /// Banto (ALG-13): a trip destination.
  ///
  /// In en, this message translates to:
  /// **'France'**
  String get tripCountryFrance;

  /// Banto (ALG-13): a trip destination.
  ///
  /// In en, this message translates to:
  /// **'Italy'**
  String get tripCountryItaly;

  /// Banto (ALG-13): a trip destination.
  ///
  /// In en, this message translates to:
  /// **'Spain'**
  String get tripCountrySpain;

  /// Banto (ALG-13): a trip destination.
  ///
  /// In en, this message translates to:
  /// **'Germany'**
  String get tripCountryGermany;

  /// Banto (ALG-13): a trip destination.
  ///
  /// In en, this message translates to:
  /// **'Japan'**
  String get tripCountryJapan;

  /// Banto (ALG-13): the briefing page's title.
  ///
  /// In en, this message translates to:
  /// **'Before you go: {country}'**
  String tripBriefingTitle(String country);

  /// Banto (ALG-13): heading of the regulation hints, one per allergy or celiac entry.
  ///
  /// In en, this message translates to:
  /// **'What restaurants there must tell you'**
  String get tripBriefingRulesSection;

  /// Banto (ALG-13): shown when the profile holds no strict entry. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'None of your restrictions is an allergy or celiac, so no allergen law covers them. Ask the restaurant anyway.'**
  String get tripBriefingRulesEmpty;

  /// Banto (ALG-13): an EU or UK restaurant duty. Never 'safe'; the floor is 'ask the restaurant'.
  ///
  /// In en, this message translates to:
  /// **'On the allergen list here: the restaurant must be able to tell you. Still ask the restaurant.'**
  String get tripHintRestaurantMustTell;

  /// Banto (ALG-13): on the list for packaged food, with no restaurant duty (Israel, Japan).
  ///
  /// In en, this message translates to:
  /// **'Labelled on packaged food only: restaurants don\'t have to tell you. Ask every time.'**
  String get tripHintPackagedOnly;

  /// Banto (ALG-13): the US: the FASTER Act covers packaged food, SB 68 only large Californian chains.
  ///
  /// In en, this message translates to:
  /// **'Labelled on packaged food; only large chains in California must list it. Ask every time.'**
  String get tripHintPackagedOnlyLargeChains;

  /// Banto (ALG-13): the restriction is on no list at the destination.
  ///
  /// In en, this message translates to:
  /// **'Not on the allergen list here: nobody has to tell you. Ask every time.'**
  String get tripHintNotRegulated;

  /// Banto (ALG-13): heading of the local hidden-ingredient list.
  ///
  /// In en, this message translates to:
  /// **'Where your restrictions hide here'**
  String get tripBriefingLexiconSection;

  /// Banto (ALG-13): the note above the local lexicon. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'A short list from published guidance, not a complete one. While the trip is on, menus are also read for these words; a match means ask about it.'**
  String get tripBriefingLexiconNote;

  /// Banto (ALG-13): no lexicon entry hides anything in the profile. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'Nothing on our short list for your restrictions here. That is not a clearance: ask every time.'**
  String get tripBriefingLexiconEmpty;

  /// Banto (ALG-13): what one local dish may hide, among the profile's restrictions.
  ///
  /// In en, this message translates to:
  /// **'May hide: {restrictions}'**
  String tripBriefingHides(String restrictions);

  /// Banto (ALG-13): opens the profile's chef card from the briefing.
  ///
  /// In en, this message translates to:
  /// **'Open my chef card'**
  String get tripBriefingChefCard;

  /// Banto (ALG-13): under the chef card button. Local-language cards are out of scope.
  ///
  /// In en, this message translates to:
  /// **'The card is made on this phone and opens without a connection. It is in Hebrew or English; cards in the local language are not available yet.'**
  String get tripBriefingChefCardNote;

  /// Banto (ALG-16): the menu screen's notice when the restaurant's own allergen matrix is on file; {date} is the day it holds from, formatted for the UI locale. A fact, never a badge or a rating, and never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'Allergen information from the restaurant, dated {date}'**
  String allergenMatrixNotice(String date);

  /// Banto (ALG-16): under the allergen-information notice, the matrix rows the app could not pair with exactly one dish by name, listed as the restaurant printed them. They are applied to nothing, never guessed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 line of it matches no dish on this menu: {rows}} other{{count} lines of it match no dish on this menu: {rows}}}'**
  String allergenMatrixUnmatched(int count, String rows);

  /// Banto (ALG-16): concern source on the dish card for a concern the restaurant's own allergen matrix declares (contains or may contain).
  ///
  /// In en, this message translates to:
  /// **'restaurant\'s allergen information'**
  String get concernSourceMatrix;

  /// Banto (ALG-16): Why sheet line for a concern the restaurant's allergen matrix declares.
  ///
  /// In en, this message translates to:
  /// **'Listed in the restaurant\'s own allergen information'**
  String get whySourceMatrix;

  /// Banto (ALG-16): the Why sheet's tier phrase for a concern the restaurant's allergen matrix declares or lowered.
  ///
  /// In en, this message translates to:
  /// **'Declared in the restaurant\'s allergen information'**
  String get whyTierDeclaredMatrix;

  /// Banto (ALG-16): under a concern lowered by a 'free' cell of the restaurant's allergen matrix; {row} is the matrix row's dish name as the restaurant printed it. Never says the dish is free of it.
  ///
  /// In en, this message translates to:
  /// **'Listed as free of it, as “{row}” — this lowers the finding but never rules it out'**
  String whyMatrixAbsent(String row);

  /// Banto (ALG-14): the Recent row action that opens the post-meal prompt.
  ///
  /// In en, this message translates to:
  /// **'Did you ask the staff?'**
  String get confirmPromptOpen;

  /// Banto (ALG-14): title of the post-meal prompt.
  ///
  /// In en, this message translates to:
  /// **'After your meal'**
  String get confirmPromptTitle;

  /// Banto (ALG-14): the prompt's opening sentence. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'What did the staff tell you? Your answers stay on this device and show on the dish the next time this menu opens. An answer holds for that visit only, so ask each time.'**
  String get confirmPromptIntro;

  /// Banto (ALG-14): one question per concern on a dish.
  ///
  /// In en, this message translates to:
  /// **'Did you ask about {restriction} in {dish}?'**
  String confirmPromptQuestion(String restriction, String dish);

  /// Banto (ALG-14): the staff said the restriction is in the dish.
  ///
  /// In en, this message translates to:
  /// **'Confirmed present'**
  String get confirmAnswerPresent;

  /// Banto (ALG-14): the staff said the restriction is not in the dish. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'Confirmed absent'**
  String get confirmAnswerAbsent;

  /// Banto (ALG-14): the person did not ask; nothing is recorded.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t ask'**
  String get confirmAnswerNotAsked;

  /// Banto (ALG-14): asked for a dish that carried a change to ask for.
  ///
  /// In en, this message translates to:
  /// **'They changed the dish as requested'**
  String get confirmChangeQuestion;

  /// Banto (ALG-14): the change was made.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get confirmChangeYes;

  /// Banto (ALG-14): the change was not made.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get confirmChangeNo;

  /// Banto (ALG-14): label of a dish's free-text note in the prompt.
  ///
  /// In en, this message translates to:
  /// **'Note (stays on this device)'**
  String get confirmNoteLabel;

  /// Banto (ALG-14): saves the prompt's answers.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get confirmSave;

  /// Banto (ALG-14): snack bar after the answers are saved.
  ///
  /// In en, this message translates to:
  /// **'Saved on this device'**
  String get confirmSaved;

  /// Banto (ALG-14): the prompt when no dish has a concern. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'Nothing on this menu points to your restrictions, so there is nothing to ask about.'**
  String get confirmNothing;

  /// Banto (ALG-14): the prompt when the cached menu or its analysis is gone.
  ///
  /// In en, this message translates to:
  /// **'This menu is no longer on this device. Open it again to answer.'**
  String get confirmUnavailable;

  /// Banto (ALG-14): the dish card's words for a concern the staff confirmed.
  ///
  /// In en, this message translates to:
  /// **'you confirmed it with the staff, {date}'**
  String concernConfirmedOn(DateTime date);

  /// Banto (ALG-14): the dish card's words for a concern the staff denied, which stays to ask about. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'the staff said it is not there, {date} — still ask'**
  String concernDeniedOn(DateTime date);

  /// Banto (ALG-14): the Why sheet's line for a confirmed concern.
  ///
  /// In en, this message translates to:
  /// **'You confirmed with the staff on {date}'**
  String whyConfirmedOn(DateTime date);

  /// Banto (ALG-14): the Why sheet's line for a denied concern. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'On {date} the staff told you it is not in the dish. That holds for that visit only, so ask again each time.'**
  String whyDeniedOn(DateTime date);

  /// Banto (ALG-18): the paywall's title and the Settings section label. A product name.
  ///
  /// In en, this message translates to:
  /// **'Banto Premium'**
  String get premiumTitle;

  /// Banto (ALG-18): the paywall's first line.
  ///
  /// In en, this message translates to:
  /// **'Premium adds more to Banto. Your restrictions are checked the same way on either plan.'**
  String get paywallIntro;

  /// Banto (ALG-18): why the paywall opened: adding a second restriction.
  ///
  /// In en, this message translates to:
  /// **'The free plan keeps one restriction in a profile. Premium lets you add more.'**
  String get paywallReasonRestrictions;

  /// Banto (ALG-18): why the paywall opened: adding a person or checking several.
  ///
  /// In en, this message translates to:
  /// **'Profiles for other people, and checking a menu for several people at once, are part of Premium.'**
  String get paywallReasonGroup;

  /// Banto (ALG-18): why the paywall opened: picking a trip destination.
  ///
  /// In en, this message translates to:
  /// **'Trip mode is part of Premium.'**
  String get paywallReasonTrip;

  /// Banto (ALG-18): why the paywall opened: the month's free scans are used.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You have used this month\'s free scan.} other{You have used this month\'s {count} free scans.}} Premium has no monthly limit.'**
  String paywallReasonScans(int count);

  /// Banto (ALG-18): heading of the paywall's feature list.
  ///
  /// In en, this message translates to:
  /// **'What Premium adds'**
  String get paywallFeaturesHeading;

  /// Banto (ALG-18): a Premium feature.
  ///
  /// In en, this message translates to:
  /// **'More than one restriction in your profile'**
  String get paywallFeatureRestrictions;

  /// Banto (ALG-18): a Premium feature.
  ///
  /// In en, this message translates to:
  /// **'Profiles for the people you eat with, checked together'**
  String get paywallFeatureGroup;

  /// Banto (ALG-18): a Premium feature.
  ///
  /// In en, this message translates to:
  /// **'Trip mode: local terms and labelling notes for where you are going'**
  String get paywallFeatureTrip;

  /// Banto (ALG-18): a Premium feature.
  ///
  /// In en, this message translates to:
  /// **'Menu scans with no monthly limit: photos, PDFs and pasted text'**
  String get paywallFeatureScans;

  /// Banto (ALG-18): what is never gated. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'Never locked, on any plan: every restriction already in your profile is checked on every menu, and the chef card, the waiter questions, the Why sheet and the after-meal check stay free. Always ask the restaurant.'**
  String get paywallNeverLocked;

  /// Banto (ALG-18): the store's own localized price, never a figure the app writes.
  ///
  /// In en, this message translates to:
  /// **'{price} a month'**
  String paywallPrice(String price);

  /// Banto (ALG-18): the price line before or without the store's answer.
  ///
  /// In en, this message translates to:
  /// **'The price shows once the store answers.'**
  String get paywallPriceUnknown;

  /// Banto (ALG-18): the paywall's buy button.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get paywallBuy;

  /// Banto (ALG-18): restores a purchase from the store.
  ///
  /// In en, this message translates to:
  /// **'Restore purchase'**
  String get paywallRestore;

  /// Banto (ALG-18): the billing line under the buy button.
  ///
  /// In en, this message translates to:
  /// **'Billed monthly through your App Store or Google Play account. Cancel any time in the store\'s subscription settings.'**
  String get paywallTerms;

  /// Banto (ALG-18): after a purchase or restore that found Premium.
  ///
  /// In en, this message translates to:
  /// **'Premium is active on this device. Thank you.'**
  String get paywallActive;

  /// Banto (ALG-18): a pending purchase.
  ///
  /// In en, this message translates to:
  /// **'The store is still processing the purchase. Premium opens once it is approved.'**
  String get paywallPending;

  /// Banto (ALG-18): the person closed the store's sheet.
  ///
  /// In en, this message translates to:
  /// **'The purchase was cancelled.'**
  String get paywallCancelled;

  /// Banto (ALG-18): a restore that found nothing.
  ///
  /// In en, this message translates to:
  /// **'The store has no active Premium subscription for this account.'**
  String get paywallRestoredNone;

  /// Banto (ALG-18): billing unavailable or no connection.
  ///
  /// In en, this message translates to:
  /// **'The store can\'t be reached from this device right now. Try again later.'**
  String get paywallFailedStoreUnavailable;

  /// Banto (ALG-18): the store does not know the product.
  ///
  /// In en, this message translates to:
  /// **'Premium isn\'t available in the store yet.'**
  String get paywallFailedProductNotFound;

  /// Banto (ALG-18): the store answered with an error.
  ///
  /// In en, this message translates to:
  /// **'The store reported an error. Nothing changed; try again.'**
  String get paywallFailedStoreError;

  /// Banto (ALG-18): the store did not answer.
  ///
  /// In en, this message translates to:
  /// **'The store didn\'t answer in time. Try again.'**
  String get paywallFailedTimedOut;

  /// Banto (ALG-18): a build with no store (web).
  ///
  /// In en, this message translates to:
  /// **'Premium isn\'t sold in this version of the app.'**
  String get paywallFailedNotSold;

  /// Banto (ALG-18): the Settings row's status with Premium.
  ///
  /// In en, this message translates to:
  /// **'Premium is active'**
  String get settingsPremiumActive;

  /// Banto (ALG-18): the Settings row's status without Premium.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Free plan: one restriction and one scan a month} other{Free plan: one restriction and {count} scans a month}}'**
  String settingsPremiumFree(int count);

  /// Banto (ALG-18): opens the paywall from Settings.
  ///
  /// In en, this message translates to:
  /// **'See what Premium adds'**
  String get settingsPremiumOpen;

  /// Banto (ALG-18): the Scan tab's count on the free plan.
  ///
  /// In en, this message translates to:
  /// **'{left, plural, =0{No free scans left this month} =1{1 of {total} free scans left this month} other{{left} of {total} free scans left this month}}'**
  String scanFreeScansLeft(int left, int total);

  /// Banto (ALG-15): heading of the dish's allergy note under the per-dish chef card.
  ///
  /// In en, this message translates to:
  /// **'Allergy note for this dish'**
  String get chefCardAllergyNoteTitle;

  /// Banto (ALG-15): the line under the dish allergy note's heading.
  ///
  /// In en, this message translates to:
  /// **'Short enough for a delivery app\'s note box. It follows the card\'s language.'**
  String get chefCardAllergyNoteExplain;

  /// Banto (ALG-14): the dish card's dated line when the person said the kitchen made the change they asked for. It never changes the dish's state.
  ///
  /// In en, this message translates to:
  /// **'The staff changed it as you asked, {date}'**
  String dishChangeHonouredOn(DateTime date);

  /// Banto (ALG-14): the dish card's dated line when the person said the kitchen did not make the change they asked for.
  ///
  /// In en, this message translates to:
  /// **'The staff did not make the change you asked for, {date}'**
  String dishChangeNotHonouredOn(DateTime date);

  /// Banto (ALG-14): the Why sheet's line when the person said the kitchen made the change they asked for. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'On {date} the staff changed the dish as you asked. That was for that visit, so ask for the change again each time.'**
  String whyChangeHonouredOn(DateTime date);

  /// Banto (ALG-14): the Why sheet's line when the person said the kitchen did not make the change they asked for.
  ///
  /// In en, this message translates to:
  /// **'On {date} the staff did not make the change you asked for.'**
  String whyChangeNotHonouredOn(DateTime date);

  /// Banto (#342): the picker's and onboarding's group heading over kosher, halal and Jain, and their kind label in Settings. Names no certification.
  ///
  /// In en, this message translates to:
  /// **'Religious diet'**
  String get restrictionKindReligious;

  /// Banto (#342): the picker's hint under kosher. The app flags components only and never says a dish or a kitchen is kosher; must not contain the word kosher.
  ///
  /// In en, this message translates to:
  /// **'Flags pork, shellfish and meat with dairy in the menu\'s words. Ask the restaurant about its certificate'**
  String get restrictionKosherHint;

  /// Banto (#342): the picker's hint under halal. The app flags components only and never says a dish or a kitchen is halal; must not contain the word halal.
  ///
  /// In en, this message translates to:
  /// **'Flags pork, alcohol, gelatin and blood in the menu\'s words. Ask the restaurant about its certificate'**
  String get restrictionHalalHint;

  /// Banto (issue #342): the picker's kind label of a strict restriction that is a health condition and not an allergy (fava beans for G6PD deficiency). Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'Health condition'**
  String get restrictionKindMedical;

  /// Banto (issue #342): the picker's hint under a restriction only Japan's mandatory list names (buckwheat).
  ///
  /// In en, this message translates to:
  /// **'On Japan\'s mandatory allergen list'**
  String get restrictionJapanListHint;

  /// Banto (issue #342): the picker's hint under a food on Japan's recommended (not mandatory) allergen list, such as kiwi or beef.
  ///
  /// In en, this message translates to:
  /// **'Recommended in Japan, on no mandatory allergen list'**
  String get restrictionJapanRecommendedHint;

  /// Banto (issue #342): the picker's hint under a single legume (chickpeas, lentils, peas, fenugreek) listed under Legumes.
  ///
  /// In en, this message translates to:
  /// **'One legume on its own, apart from all legumes'**
  String get restrictionLegumePartHint;

  /// Banto (issue #342): the picker's hint under fava beans. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'G6PD deficiency (favism), not an allergy. Checked as strictly as one'**
  String get restrictionFavaHint;

  /// Banto (issue #342): the label of the picker's search field.
  ///
  /// In en, this message translates to:
  /// **'Search restrictions'**
  String get restrictionSearchField;

  /// Banto (issue #342): shown in the picker when the search matches nothing; points to 'Add your own'.
  ///
  /// In en, this message translates to:
  /// **'No restriction matches. You can add it as your own below.'**
  String get restrictionSearchEmpty;

  /// Banto (issue #410): the Discovery chip beside Keto 8+ that keeps venues with at least one dish fitting the active profiles, as it is or with a change; unscored venues stay. Never 'safe'.
  ///
  /// In en, this message translates to:
  /// **'Fits my profile'**
  String get discoveryChipFitsProfile;

  /// Banto (ALG-14, issue #409): the second toggle under AI & privacy, off by default. Shares post-meal answers with KetoClub's server.
  ///
  /// In en, this message translates to:
  /// **'Share what the staff told you'**
  String get settingsShareConfirmations;

  /// Banto (ALG-14, issue #409): the one sentence under the share toggle saying exactly what is sent.
  ///
  /// In en, this message translates to:
  /// **'Each answer you save after a meal sends the venue, the dish, the restriction you asked about and yes or no, so other people see how many were told the same. Never your profile, never your note.'**
  String get settingsShareConfirmationsBody;

  /// Banto (ALG-14, issue #409): added to the AI disclosure (Explore banner, Settings) while the share toggle is on.
  ///
  /// In en, this message translates to:
  /// **'You share what the staff told you: each answer you save sends the venue, the dish, the one restriction you asked about and yes or no to KetoClub\'s server, with nothing that identifies you. Never your profile, never your note.'**
  String get whatLeavesDeviceSharedConfirmations;

  /// Banto (ALG-14, issue #409): a dish's shared line, from three people. {restriction} names what was asked about. Never 'safe'; the footer says to ask.
  ///
  /// In en, this message translates to:
  /// **'{count} people were told it has no {restriction} here'**
  String sharedConfirmationAbsent(int count, String restriction);

  /// Banto (ALG-14, issue #409): a dish's shared line when people were told the restriction's ingredient is in the dish.
  ///
  /// In en, this message translates to:
  /// **'{count} people were told it has {restriction} here'**
  String sharedConfirmationPresent(int count, String restriction);

  /// Banto (ALG-14, issue #409): the helper-tool footer under the shared lines on a dish card.
  ///
  /// In en, this message translates to:
  /// **'Shared by other diners. The app cannot check it: always ask the restaurant.'**
  String get sharedConfirmationFooter;

  /// Banto (#412): the one-line offer after a post-meal save in which every strict concern was cleared. One tap marks the venue on this device. Never a rating.
  ///
  /// In en, this message translates to:
  /// **'This place worked for me'**
  String get workedOffer;

  /// Banto (#412): declines the 'This place worked for me' offer and closes the post-meal sheet.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get workedOfferSkip;

  /// Banto (#412): the Recent tab's filter chip and the tag on a marked row or menu header when the mark is the person's own. A filter only; never a score.
  ///
  /// In en, this message translates to:
  /// **'Worked for me'**
  String get workedChip;

  /// Banto (#412): the tag on a marked row or menu header naming the people it worked for (a group, or a named profile).
  ///
  /// In en, this message translates to:
  /// **'Worked for {names}'**
  String workedTagNames(String names);

  /// Banto (#412): the overflow item that marks a venue as having worked for the people the menu is read for.
  ///
  /// In en, this message translates to:
  /// **'Mark as worked for me'**
  String get workedMark;

  /// Banto (#412): the overflow item that removes the mark.
  ///
  /// In en, this message translates to:
  /// **'Remove the \"worked for me\" mark'**
  String get workedUnmark;

  /// Banto (#411): one state count on a Recent row, such as 'No trigger found: 3'; the label is the verdict tile's own word.
  ///
  /// In en, this message translates to:
  /// **'{label}: {count}'**
  String savedStateCount(String label, int count);

  /// Banto (#411): shown on a Recent row, in place of numbers, when the profile now differs from the one the menu was last counted for.
  ///
  /// In en, this message translates to:
  /// **'Your profile has changed since. Open this menu to check it again.'**
  String get savedRecheck;

  /// Banto (#421): the notice above the dishes and above the Discovery list while the profile holds nothing but keto. Never says a dish is safe.
  ///
  /// In en, this message translates to:
  /// **'Tell Banto what you avoid to see which dishes fit you'**
  String get profileNudgeMessage;

  /// Banto (#421): the notice's action, which opens the restriction picker.
  ///
  /// In en, this message translates to:
  /// **'Add what you avoid'**
  String get profileNudgeChoose;

  /// Banto (#421): dismisses the notice for that screen; the choice is remembered on the device.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get profileNudgeDismiss;

  /// Banto (#421): the My restrictions row that reopens the first-run 'What do you avoid?' screen, pre-filled with the current profile.
  ///
  /// In en, this message translates to:
  /// **'Run the setup again'**
  String get settingsRestrictionsRerun;
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
