// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hebrew (`he`).
class AppLocalizationsHe extends AppLocalizations {
  AppLocalizationsHe([String locale = 'he']) : super(locale);

  @override
  String get settingsTitle => 'הגדרות';

  @override
  String get actionRetry => 'נסה שוב';

  @override
  String get actionReport => 'דווח על זה';

  @override
  String get actionOpenSettings => 'פתח הגדרות';

  @override
  String get actionCopy => 'העתק';

  @override
  String get actionCopied => 'הועתק';

  @override
  String get actionRefreshMenu => 'רענן תפריט';

  @override
  String get actionBackToSearch => 'חזרה לחיפוש';

  @override
  String get offlineBannerMessage => 'אין חיבור לאינטרנט.';

  @override
  String get actionShareMenu => 'שתף תפריט';

  @override
  String get actionOpenDrinksGuide => 'מדריך שתייה';

  @override
  String get actionCancel => 'ביטול';

  @override
  String get venueSearchLabel => 'חיפוש מסעדה';

  @override
  String get venueSearchHint => 'חפשו לפי שם, או הדביקו קישור מוולט';

  @override
  String get venueSearchInvalid =>
      'קטוקלאב לא יודע לקרוא תפריט משם עדיין. הדביקו קישור למסעדה בוולט או את המזהה שלה.';

  @override
  String get venueSearchOpenLink => 'פתח קישור';

  @override
  String venueSearchContinueWith(String venue) {
    return 'המשיכו עם $venue';
  }

  @override
  String get menuLoading => 'קורא את התפריט…';

  @override
  String get menuEmpty => 'בתפריט הזה אין מנות.';

  @override
  String get menuProgressAnalysing => 'מנתח את התפריט…';

  @override
  String get menuProgressAskingAi => 'שואל את הבינה המלאכותית…';

  @override
  String get menuProgressApplyingRules => 'מפעיל את הכללים…';

  @override
  String get filterGreenOnly => 'רק מנות להזמנה כמו שהן';

  @override
  String get filterGreenAndYellow => 'כמו שהן ועם שינוי';

  @override
  String get filterAll => 'הכול';

  @override
  String redGroupTitle(int count) {
    return 'לא קטוגני ($count)';
  }

  @override
  String unclassifiedTitle(int count) {
    return 'לא נקראו ($count)';
  }

  @override
  String get unclassifiedExplain =>
      'קטוקלאב ראה את המנות האלה אבל לא הצליח לסווג אותן. קראו אותן בעצמכם לפני שאתם מזמינים.';

  @override
  String get unclassifiedBadge => 'לא סווג';

  @override
  String get engineChipAi => 'בינה מלאכותית';

  @override
  String get engineChipRules => 'כללים';

  @override
  String get rulesNotVerifiedHint =>
      'תוצאה על בסיס כללים, ללא אימות בינה מלאכותית.';

  @override
  String cachedFrom(String date) {
    return 'מוצג התפריט שנשמר בתאריך $date.';
  }

  @override
  String get verdictOrderAsIs => 'להזמין כמו שזה';

  @override
  String get verdictModifiable => 'להזמין עם שינוי';

  @override
  String get verdictNonKeto => 'לא קטוגני';

  @override
  String get dishCardFullScreen => 'מסך מלא';

  @override
  String dishCardFullScreenSemanticLabel(String dish) {
    return 'הצג כרטיס למלצר עבור $dish';
  }

  @override
  String get waiterCardTitle => 'זה מה שאומרים למלצר';

  @override
  String get settingsConsentTitle => 'מה יוצא מהמכשיר הזה';

  @override
  String get settingsConsentBody =>
      'ניתוח בינה מלאכותית פועל כברירת מחדל: כשאתם פותחים או מדביקים תפריט, שמות המנות, התיאורים ושמות התוספות — וכל שאלה שאתם כותבים על תפריט — נשלחים לשרת של קטוקלאב, שמעביר אותם לניתוח ב‑Gemini API של Google. שום דבר אחר עליכם או על ההיסטוריה שלכם לא נשלח. המיקום שלכם נשלח ל‑Wolt רק כשאתם מחפשים מסעדות בקרבתכם, ואינו נשמר. אין איסוף נתונים. בטלו את הסימון כדי להשאיר כל תפריט על המכשיר.';

  @override
  String get settingsConsentAccept => 'אפשר ניתוח בינה מלאכותית';

  @override
  String get consentDisclosureOk => 'אישור';

  @override
  String get consentDisclosureTurnOff => 'כבה';

  @override
  String get settingsConsentBodyDirect =>
      'ניתוח בינה מלאכותית פועל כברירת מחדל: כשאתם פותחים או מדביקים תפריט, שמות המנות, התיאורים ושמות התוספות — וכל שאלה שאתם כותבים על תפריט — נשלחים ישירות מהמכשיר הזה ל‑Gemini API של Google, עם מפתח ה‑API שלכם. שום דבר אחר עליכם או על ההיסטוריה שלכם לא נשלח. המיקום שלכם נשלח ל‑Wolt רק כשאתם מחפשים מסעדות בקרבתכם, ואינו נשמר. אין איסוף נתונים. בטלו את הסימון כדי להשאיר כל תפריט על המכשיר.';

  @override
  String get settingsKeySection => 'מפתח Gemini API';

  @override
  String get settingsKeyBody =>
      'בטלפון הזה, ניתוח בינה מלאכותית פונה ישירות ל‑Gemini API של Google עם המפתח שלכם. אפשר ליצור מפתח בחינם ב‑Google AI Studio. המפתח נשמר באחסון המאובטח של המכשיר ונשלח רק ל‑Google.';

  @override
  String get settingsKeyHint => 'הדביקו את מפתח ה‑Gemini API שלכם';

  @override
  String get settingsKeySave => 'שמור מפתח';

  @override
  String get settingsKeyPresent => 'מפתח שמור במכשיר הזה.';

  @override
  String get settingsKeyAbsent =>
      'אין מפתח שמור. קטוקלאב ישתמש בכללים שעל המכשיר.';

  @override
  String get settingsKeyDelete => 'הסר מפתח';

  @override
  String get settingsLanguage => 'שפה';

  @override
  String get settingsLanguageSystem => 'לפי המכשיר';

  @override
  String get settingsLanguageEnglish => 'אנגלית';

  @override
  String get settingsLanguageHebrew => 'עברית';

  @override
  String get settingsAppearance => 'מראה';

  @override
  String get settingsAppearanceSystem => 'לפי ערכת הנושא של המכשיר';

  @override
  String get settingsAppearanceLight => 'בהיר';

  @override
  String get settingsAppearanceDark => 'כהה';

  @override
  String get settingsNetCarbLimit => 'מגבלת פחמימות נטו';

  @override
  String get settingsNetCarbLimitBody =>
      'מנות מעל המגבלה לעולם לא יסומנו בירוק. שינוי שלה ינתח מחדש את התפריט הבא שתפתחו.';

  @override
  String settingsNetCarbLimitValue(int grams) {
    return '$grams גרם';
  }

  @override
  String get settingsNetCarbLimitDecrease => 'הורדת מגבלת הפחמימות נטו';

  @override
  String get settingsNetCarbLimitIncrease => 'העלאת מגבלת הפחמימות נטו';

  @override
  String get settingsKetoRules => 'כללי הקטו שלכם';

  @override
  String get settingsKetoRulesBody =>
      'כל כלל שתפעילו יחול החל מהתפריט הבא שתפתחו.';

  @override
  String get settingsSeedOilFree => 'ללא שמני זרעים, בהקפדה';

  @override
  String get settingsSeedOilFreeHint =>
      'מסמן שמן קנולה, חמניות וסויה במנות מטוגנות.';

  @override
  String get settingsDairyFree => 'קטו ללא מוצרי חלב';

  @override
  String get settingsDairyFreeHint =>
      'שמנת, חמאה וגבינה יסומנו כמנה שדורשת שינוי.';

  @override
  String get settingsCarnivoreOnly => 'קרניבור בלבד';

  @override
  String get settingsCarnivoreOnlyHint =>
      'רק בשר, דגים וביצים בירוק — ירקות הופכים לצהוב.';

  @override
  String get settingsFilter => 'סינון ברירת מחדל';

  @override
  String settingsCacheSummary(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count תפריטים שמורים · עובד גם ללא חיבור לאינטרנט',
      two: 'שני תפריטים שמורים · עובד גם ללא חיבור לאינטרנט',
      one: 'תפריט אחד שמור · עובד גם ללא חיבור לאינטרנט',
    );
    return '$_temp0';
  }

  @override
  String get settingsClearCache => 'נקה תפריטים שמורים';

  @override
  String get settingsClearCacheConfirmTitle => 'לנקות את התפריטים השמורים?';

  @override
  String get settingsClearCacheConfirmBody =>
      'פעולה זו תמחק את כל התפריטים השמורים במכשיר הזה, כולל כל תפריט שאפשר לפתוח כרגע בלי אינטרנט. אפשר לשמור מסעדה מחדש בכל עת, על ידי פתיחתה כשיש חיבור.';

  @override
  String get settingsClearCacheConfirmAction => 'נקה';

  @override
  String get settingsCacheCleared => 'התפריטים השמורים נוקו.';

  @override
  String get fetchFailedOffline =>
      'אין חיבור, ולכן לא היה אפשר לקרוא את התפריט.';

  @override
  String fetchFailedBlockedByBrowser(String platform) {
    return 'דפדפן לא יכול לקרוא תפריטים מ$platform: $platform חוסמת בקשות מאתרים אחרים. פתחו את הקישור באפליקציית קטוקלאב בטלפון במקום.';
  }

  @override
  String fetchFailedNotFound(String platform) {
    return 'לא נמצאה מסעדה ב$platform. בדקו את הקישור.';
  }

  @override
  String fetchFailedPlatformChanged(String platform, String statusCode) {
    return '$platform שינתה את מבנה התפריט (HTTP $statusCode), ולכן קטוקלאב לא הצליח לקרוא אותו. אנא דווחו על זה.';
  }

  @override
  String get fetchFailedUnsupportedSource =>
      'קטוקלאב לא יודע לקרוא תפריטים מהאתר הזה עדיין.';

  @override
  String get fetchFailedBackendUnreachable =>
      'השרת של KetoClub לא היה זמין, ולכן לא ניתן היה לקרוא את התפריט.';

  @override
  String get venueSearchFailedOffline =>
      'אין חיבור, ולכן קטוקלאב לא הצליח לחפש מסעדות.';

  @override
  String get venueSearchFailedTimeout =>
      'וולט לא ענתה לחיפוש בזמן. נסו שוב בעוד רגע.';

  @override
  String get venueSearchFailedRateLimited =>
      'יותר מדי חיפושים ברצף. חכו דקה ונסו שוב.';

  @override
  String get venueSearchFailedPlatformChanged =>
      'וולט שינתה את אופן החיפוש שלה, ולכן קטוקלאב לא הצליח לקרוא את התוצאות. אנא דווחו על זה.';

  @override
  String get venueSearchFailedBlockedByBrowser =>
      'דפדפן לא יכול לחפש בוולט ישירות. השתמשו באפליקציית קטוקלאב בטלפון, או הדביקו קישור מוולט.';

  @override
  String get venueSearchFailedBackendUnreachable =>
      'השרת של קטוקלאב לא היה זמין, ולכן לא ניתן היה לחפש.';

  @override
  String get analysisNotConfigured =>
      'ניתוח בינה מלאכותית אינו זמין בגרסה הזו או בשרת. מוצגות תוצאות על בסיס כללים.';

  @override
  String get analysisOffline => 'לא מחוברים. מוצגות תוצאות על בסיס כללים.';

  @override
  String get analysisTimeout =>
      'מודל הבינה המלאכותית היה אטי מדי. מוצגות תוצאות על בסיס כללים.';

  @override
  String get analysisRateLimited =>
      'המגבלה היומית של הבינה המלאכותית נגמרה. מוצגות תוצאות על בסיס כללים.';

  @override
  String analysisBadResponse(String detail) {
    return 'ניתוח הבינה המלאכותית נכשל ($detail). מוצגות תוצאות על בסיס כללים.';
  }

  @override
  String get analysisBadResponseNoDetail =>
      'מודל הבינה המלאכותית החזיר תשובה לא שמישה. מוצגות תוצאות על בסיס כללים.';

  @override
  String get analysisNoDishesFound =>
      'הבינה המלאכותית לא הצליחה לזהות מנות בתפריט הזה.';

  @override
  String get analysisBackendUnreachable =>
      'לא ניתן היה להתחבר לשרת של קטוקלאב. מוצגות תוצאות על בסיס כללים.';

  @override
  String get analysisConsentWithheld =>
      'אשרו ניתוח בינה מלאכותית בהגדרות כדי לנתח את התפריט הזה. מוצגות תוצאות על בסיס כללים.';

  @override
  String get analysisApiKeyMissing =>
      'הוסיפו את מפתח ה‑Gemini API שלכם בהגדרות כדי לנתח את התפריט הזה. מוצגות תוצאות על בסיס כללים.';

  @override
  String get analysisApiKeyRejected =>
      'Gemini דחתה את מפתח ה‑API שלכם. בדקו אותו בהגדרות. מוצגות תוצאות על בסיס כללים.';

  @override
  String pillSemanticLabel(String verdict) {
    return 'פסיקה: $verdict';
  }

  @override
  String get dishCardAskWaiter => 'שאלו את המלצר';

  @override
  String get dishCardHideScript => 'הסתירו את הטקסט למלצר';

  @override
  String get dishCardScriptFallback =>
      'שאלו את המלצר לגבי תחליף קטוגני למנה הזו.';

  @override
  String netCarbsChipLabel(String grams) {
    return '~$grams גרם פחמימות נטו (הערכה)';
  }

  @override
  String netCarbsChipSemanticLabel(String grams) {
    return 'הערכת פחמימות נטו, לא מאומתת: $grams גרם';
  }

  @override
  String engineChipAiSemanticLabel(String model) {
    return 'מנוע בינה מלאכותית, מודל $model';
  }

  @override
  String engineChipRulesSemanticLabel(String reason) {
    return 'מנוע כללים, ללא אימות בינה מלאכותית: $reason';
  }

  @override
  String get engineChipReasonNotConfigured => 'לא מוגדר';

  @override
  String get engineChipReasonOffline => 'לא מקוון';

  @override
  String get engineChipReasonTimeout => 'פסק זמן';

  @override
  String get engineChipReasonRateLimited => 'המכסה היומית נוצלה';

  @override
  String get engineChipReasonBadResponse => 'שגיאת בינה מלאכותית';

  @override
  String get engineChipReasonNoDishesFound => 'לא נמצאו מנות';

  @override
  String get engineChipReasonBackendUnreachable => 'השרת לא זמין';

  @override
  String get engineChipReasonConsentWithheld => 'בינה מלאכותית לא אושרה';

  @override
  String get navExplore => 'גילוי';

  @override
  String get navScan => 'סריקה';

  @override
  String get navSaved => 'אחרונים';

  @override
  String get navSettings => 'הגדרות';

  @override
  String get savedPlaceholderTitle => 'תפריטים אחרונים';

  @override
  String get savedPlaceholderBody =>
      'פתחו תפריט של מסעדה והוא יופיע כאן אוטומטית, זמין ליממה — גם ללא חיבור לאינטרנט.';

  @override
  String get savedLoading => 'טוען את התפריטים האחרונים שלך…';

  @override
  String savedEntryDishCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count מנות',
      two: 'שתי מנות',
      one: 'מנה אחת',
    );
    return '$_temp0';
  }

  @override
  String get savedRemove => 'הסר';

  @override
  String savedRemoveSemanticLabel(String venue) {
    return 'הסר את $venue';
  }

  @override
  String savedRemovedMessage(String venue) {
    return '$venue הוסרה.';
  }

  @override
  String get savedUndo => 'בטל';

  @override
  String get discoveryTitle => 'איפה לאכול';

  @override
  String get discoveryEmptyTitle => 'מצאו איפה לאכול';

  @override
  String get discoveryEmptyBody =>
      'השתמשו במיקום שלכם כדי לראות מסעדות בסביבה, חפשו לפי שם, או הדביקו למעלה קישור מוולט כדי לפתוח את התפריט המסווג לפי קטו.';

  @override
  String get discoveryLookingAround => 'מחפשים סביב';

  @override
  String get discoveryAroundYou => 'המיקום שלך';

  @override
  String get discoveryLocationInvite => 'הקש כדי להשתמש במיקום שלך';

  @override
  String get discoveryUseLocation => 'השתמש במיקום שלי';

  @override
  String get discoveryChipKetoEightPlus => 'קטו 8+';

  @override
  String get discoveryChipKetoEightPlusHint =>
      'צריך ציונים קודם: אפשר להעריך את הרשימה או לפתוח מסעדה.';

  @override
  String get discoveryChipOpenNow => 'פתוח עכשיו';

  @override
  String get discoveryLocating => 'מאתר את המיקום שלך…';

  @override
  String get discoverySearching => 'מחפש מסעדות…';

  @override
  String get discoveryLocationDeniedTitle => 'המיקום כבוי עבור קטוקלאב';

  @override
  String get discoveryLocationDeniedBody =>
      'אפשרו גישה למיקום כדי לראות מסעדות בסביבה, או חפשו לפי שם במקום.';

  @override
  String get discoveryLocationDeniedForeverBody =>
      'הגישה למיקום כבויה עבור קטוקלאב. אפשר להפעיל אותה מחדש בהגדרות המכשיר, או לחפש לפי שם במקום.';

  @override
  String get discoveryLocationUnavailableTitle =>
      'לא הצלחנו למצוא את המיקום שלך';

  @override
  String get discoveryLocationServicesOff =>
      'שירותי המיקום במכשיר כבויים. הפעילו אותם ונסו שוב, או חפשו לפי שם במקום.';

  @override
  String get discoveryLocationInsecureContext =>
      'הדף הזה לא יכול לבקש את המיקום שלך כי החיבור אינו מאובטח (https). חפשו לפי שם במקום.';

  @override
  String get discoveryLocationTimeout =>
      'איתור המיקום לקח יותר מדי זמן. נסו שוב, או חפשו לפי שם במקום.';

  @override
  String get discoveryLocationUnsupported =>
      'המכשיר לא הצליח לספק מיקום. חפשו לפי שם במקום.';

  @override
  String get discoveryTypeNameInstead => 'הקלד שם במקום';

  @override
  String get discoveryOpenSettings => 'פתח הגדרות';

  @override
  String get discoveryTurnOnLocation => 'הפעל מיקום';

  @override
  String get discoveryOpenSettingsUnavailable =>
      'לא ניתן לפתוח את ההגדרות מכאן. אפשרו מיקום ל-KetoClub בהגדרות הדפדפן או המכשיר, ונסו שוב.';

  @override
  String get discoveryNoResultsTitle => 'לא נמצאו מסעדות';

  @override
  String get discoveryNoResultsBody => 'נסו שם אחר, או נקו את החיפוש.';

  @override
  String get discoveryClearSearch => 'נקה חיפוש';

  @override
  String get discoveryNoChipResults => 'אף מסעדה ברשימה לא מתאימה לסינון הזה.';

  @override
  String get discoveryEstimateList => 'דירוג מהיר (כללים במכשיר)';

  @override
  String get discoveryEstimateHint =>
      'לניתוח מלא עם בינה מלאכותית, פתחו מסעדה.';

  @override
  String discoveryEstimating(int done, int total) {
    return 'מעריך $done מתוך $total…';
  }

  @override
  String get venueCardOpenNow => 'פתוח עכשיו';

  @override
  String get venueCardClosed => 'סגור';

  @override
  String venueCardMinutes(int minutes) {
    return '$minutes דק׳';
  }

  @override
  String venueCardWalkMinutes(int minutes) {
    return '$minutes דק׳ הליכה';
  }

  @override
  String venueCardDistanceMetres(String distance) {
    return '$distance מ׳';
  }

  @override
  String venueCardDistanceKm(String distance) {
    return '$distance ק״מ';
  }

  @override
  String venueCardGreenCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count מנות כמו שהן',
      one: 'מנה אחת כמו שהיא',
    );
    return '$_temp0';
  }

  @override
  String venueCardYellowCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count עם שינויים',
      one: 'אחת עם שינויים',
    );
    return '$_temp0';
  }

  @override
  String get menuKetoScoreLabel => 'ציון קטוגני';

  @override
  String menuKetoScoreSemanticLabel(String score) {
    return 'ציון קטוגני: $score מתוך 10';
  }

  @override
  String menuSourceLine(String platform, String age) {
    return '$platform · $age';
  }

  @override
  String menuOpenOnPlatform(String platform) {
    return 'פתח ב-$platform';
  }

  @override
  String menuShowingAll(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'מוצגות $count מנות',
      two: 'מוצגות שתי מנות',
      one: 'מוצגת מנה אחת',
    );
    return '$_temp0';
  }

  @override
  String get menuShowingGreen => 'מוצגות מנות שאפשר להזמין כמו שהן';

  @override
  String get menuShowingYellow => 'מוצגות מנות שדורשות שינוי';

  @override
  String get menuShowingRed => 'מוצג מה כדאי לדלג עליו';

  @override
  String get menuShowingGreenAndYellow =>
      'מוצגות מנות שאפשר להזמין כמו שהן או עם שינוי';

  @override
  String get tileGreenLabel => 'להזמין כמו שהן';

  @override
  String get tileYellowLabel => 'עם שינוי';

  @override
  String get tileRedLabel => 'לדלג';

  @override
  String tileSemanticLabel(String label, int count) {
    return '$label: $count';
  }

  @override
  String get tileSemanticHintFilter => 'הקשה כפולה כדי לסנן';

  @override
  String get tileSemanticHintClear => 'הקשה כפולה כדי לנקות את הסינון';

  @override
  String get ageJustNow => 'הרגע';

  @override
  String ageMinutes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'לפני $count דקות',
      two: 'לפני דקתיים',
      one: 'לפני דקה',
    );
    return '$_temp0';
  }

  @override
  String ageHours(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'לפני $count שעות',
      two: 'לפני שעתיים',
      one: 'לפני שעה',
    );
    return '$_temp0';
  }

  @override
  String ageDays(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'לפני $count ימים',
      two: 'לפני יומיים',
      one: 'לפני יום',
    );
    return '$_temp0';
  }

  @override
  String get legendToggle => 'מה משמעות הצבעים?';

  @override
  String get legendHide => 'הסתר את המקרא';

  @override
  String get legendNote => 'אותם הכללים שקטוקלאב שולחת למודל הבינה המלאכותית.';

  @override
  String get legendEngines =>
      'כללים: בדיקות מילות מפתח של קטוקלאב על טקסט המנה, בלי הערכת פחמימות. בינה מלאכותית: Gemini קורא את כל התפריט ומעריך פחמימות נטו.';

  @override
  String get legendBudget =>
      'תקציב פחמימות: לאחר ניתוח בינה מלאכותית, שדה בסינון מאפשר לקבוע תקציב פחמימות נטו לארוחה. לתוצאות על בסיס כללים אין הערכת פחמימות, ולכן הוא לא מוצע.';

  @override
  String get waiterCardCopyButton => 'העתק טקסט';

  @override
  String waiterCardAfterText(String grams) {
    return 'עם השינויים האלו, בערך $grams גרם פחמימות נטו (הערכה) — בטוח להזמין.';
  }

  @override
  String get dishCardAddNote => 'הוסף הערה';

  @override
  String dishCardEditNoteSemanticLabel(String note) {
    return 'ערוך את ההערה שלך: $note';
  }

  @override
  String get noteEditorTitle => 'הערה אישית';

  @override
  String get noteEditorHint => 'לדוגמה: הצוות החליף בשמחה לכרובית';

  @override
  String get noteEditorSave => 'שמור';

  @override
  String get noteEditorClear => 'מחק הערה';

  @override
  String get menuFilters => 'סינון';

  @override
  String menuFiltersActive(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'סינון · $count פעילים',
      one: 'סינון · 1 פעיל',
    );
    return '$_temp0';
  }

  @override
  String get menuSearchHint => 'חפשו מנות';

  @override
  String get menuSearchSemanticLabel => 'חיפוש מנות לפי שם או תיאור';

  @override
  String get menuSearchClear => 'נקה חיפוש';

  @override
  String get menuNoResults => 'אין מנות שמתאימות לחיפוש שלכם.';

  @override
  String get menuClearFilter => 'נקה סינון';

  @override
  String categoryChipSemanticLabel(String category) {
    return 'עברו אל $category';
  }

  @override
  String get scanTitle => 'סריקת תפריט';

  @override
  String get scanPasteIntro =>
      'הדביקו תפריט מכל מקור, מנה בכל שורה. קטוקלאב קורא אותו בדיוק כמו תפריט משלוחים.';

  @override
  String get scanPasteLabel => 'טקסט התפריט';

  @override
  String get scanPasteHint =>
      'סלמון על הגריל\nסלט קיסר, בלי קרוטונים\nפסטה קרבונרה';

  @override
  String get scanAnalyse => 'נתחו';

  @override
  String get scanEmptyPaste =>
      'קטוקלאב לא מצא מנות בטקסט הזה. הדביקו את התפריט עם מנה אחת בכל שורה.';

  @override
  String get sourceScanned => 'תפריט שהודבק';

  @override
  String get fetchFailedScanNotSaved =>
      'התפריט שהודבק כבר לא שמור במכשיר הזה. הדביקו אותו שוב כדי לנתח אותו.';

  @override
  String get scannedMenuTitle => 'תפריט סרוק';

  @override
  String get scannedMenuReadByAi => 'נקרא בידי AI מהעמודים שלכם';

  @override
  String get scannedMenuViewPages => 'הצגת העמודים';

  @override
  String get scannedMenuPagesTitle => 'העמודים שלכם';

  @override
  String get scannedMenuPagesNote =>
      'השוו את שמות המנות לעמודים שלכם: ה-AI עלול לקרוא מילה לא נכון.';

  @override
  String scannedMenuPageLabel(int number) {
    return 'עמוד $number';
  }

  @override
  String get scannedMenuPdfPage => 'מסמך PDF';

  @override
  String get scannedMenuPagesClose => 'סגירה';

  @override
  String get scanScreenIntro =>
      'צלמו את דפי התפריט, בחרו תמונות מהגלריה או בחרו קובץ PDF. קטוקלאב קורא את המנות מהדפים ומנתח אותן.';

  @override
  String get scanScreenActionTakePhoto => 'צילום';

  @override
  String get scanScreenActionChoosePhotos => 'בחירת תמונות';

  @override
  String get scanScreenActionChoosePdf => 'בחירת PDF';

  @override
  String get scanScreenPagesHeading => 'דפים';

  @override
  String scanScreenPageCount(int count, int max) {
    return '$count מתוך $max דפים';
  }

  @override
  String get scanScreenCapReached =>
      'זה המספר המרבי של דפים בסריקה אחת. הסירו דף כדי להוסיף אחר.';

  @override
  String scanScreenPageLabel(int number) {
    return 'דף $number';
  }

  @override
  String get scanScreenPdfLabel => 'מסמך PDF';

  @override
  String scanScreenPageSizeKb(int kb) {
    return '$kb KB';
  }

  @override
  String scanScreenRemovePage(int number) {
    return 'הסרת דף $number';
  }

  @override
  String scanScreenTooManyPages(int max) {
    return 'סריקה אחת כוללת עד $max דפים. הדפים שמעבר למגבלה לא נוספו.';
  }

  @override
  String scanScreenPageTooLarge(int mb) {
    return 'הדף גדול מ-$mb MB ולכן לא נוסף. נסו תמונה קטנה יותר או PDF קטן יותר.';
  }

  @override
  String get scanScreenAnalysePages => 'נתחו את הדפים';

  @override
  String get scanScreenPasteHeading => 'או הדביקו את הטקסט';

  @override
  String get scanScreenDisclosureWeb =>
      'הדפים נשלחים לשרת של קטוקלאב, שמעביר אותם ל-Gemini API של גוגל לקריאה.';

  @override
  String get scanScreenDisclosureDirect =>
      'הדפים נשלחים ישירות מהמכשיר הזה ל-Gemini API של גוגל, באמצעות מפתח ה-API שלכם.';

  @override
  String get scanScreenSettingsLink => 'הגדרות';

  @override
  String get scanScreenFailureNotConfigured => 'סריקה אינה זמינה בגרסה הזאת.';

  @override
  String get scanScreenFailureNeedsServer =>
      'סריקה דורשת את השרת של קטוקלאב, והגרסה הזאת לא מחוברת לשרת. הדבקת טקסט התפריט עדיין עובדת.';

  @override
  String get scanScreenFailureOffline =>
      'נראה שאין חיבור לאינטרנט. הדפים נשמרו; התחברו ונסו שוב.';

  @override
  String get scanScreenFailureTimeout =>
      'מודל ה-AI היה איטי מדי. הדפים נשמרו; נסו שוב.';

  @override
  String get scanScreenFailureRateLimited =>
      'מכסת ה-AI היומית נוצלה. הדפים נשמרו; נסו שוב מאוחר יותר.';

  @override
  String get scanScreenFailureBadResponse =>
      'מודל ה-AI החזיר תשובה שאי אפשר להשתמש בה. הדפים נשמרו; נסו שוב.';

  @override
  String get scanScreenFailureNoDishesFound =>
      'לא ניתן היה לקרוא מנות מהדפים האלה. ודאו שהתמונות חדות ומוארות היטב, או הדביקו את הטקסט במקום.';

  @override
  String get scanScreenFailureBackendUnreachable =>
      'לא ניתן להגיע לשרת של קטוקלאב. הדפים נשמרו; נסו שוב.';

  @override
  String get scanScreenFailureConsentWithheld =>
      'סריקה שולחת את הדפים ל-Gemini API של גוגל לקריאה. אפשרו ניתוח AI בהגדרות כדי לסרוק תפריט.';

  @override
  String get scanScreenFailureApiKeyMissing =>
      'הוסיפו את מפתח ה-API של Gemini בהגדרות כדי לסרוק תפריט.';

  @override
  String get scanScreenFailureApiKeyRejected =>
      'Gemini דחה את מפתח ה-API שלכם. בדקו אותו בהגדרות ונסו שוב.';

  @override
  String websiteMenuNotFound(String site) {
    return 'קטוקלאב לא מצאה ב־$site תפריט שאפשר לקרוא.';
  }

  @override
  String websiteDisallowedByRobots(String site) {
    return '$site מבקש מאפליקציות כמו קטוקלאב לא לקרוא את הדפים שלו, ולכן קטוקלאב לא קוראת אותו.';
  }

  @override
  String websiteJsOnlyPage(String site) {
    return '$site מציג את התפריט רק באמצעות JavaScript, שקטוקלאב עדיין לא יודעת לקרוא.';
  }

  @override
  String websiteUnreachable(String site) {
    return '$site לא ענה. נסו שוב מאוחר יותר.';
  }

  @override
  String websiteTooLarge(String site) {
    return 'התפריט ב־$site גדול מדי בשביל קטוקלאב.';
  }

  @override
  String websiteRateLimited(String site) {
    return 'קטוקלאב קראה את $site לפני רגע. חכו דקה ונסו שוב.';
  }

  @override
  String websitePdfUnread(String site) {
    return 'התפריט ב־$site הוא קובץ PDF, שרק ניתוח AI יכול לקרוא, והוא לא נקרא כרגע. בדקו את ניתוח ה-AI בהגדרות ונסו שוב.';
  }

  @override
  String get scanQrAction => 'סריקת קוד QR';

  @override
  String get scanQrTitle => 'סריקת קוד QR';

  @override
  String get scanQrInstruction => 'כוונו את המצלמה אל קוד ה-QR שעל השולחן.';

  @override
  String get scanQrCameraDenied =>
      'קטוקלאב לא יכולה להשתמש במצלמה. אפשרו גישה למצלמה בהגדרות המכשיר, או הדביקו את קישור התפריט.';

  @override
  String get scanQrCameraUnavailable =>
      'לא ניתן היה להפעיל את המצלמה. סגרו את המסך והדביקו את קישור התפריט.';

  @override
  String scanQrUnsupportedSource(String name) {
    return 'תפריטי $name עדיין לא נתמכים. צלמו את התפריט במקום.';
  }

  @override
  String get scanQrPhotographInstead =>
      'קוד ה-QR הזה לא מוביל לתפריט שקטוקלאב יכולה לקרוא. צלמו את התפריט במקום.';

  @override
  String get carbBudgetFieldLabel => 'תקציב הפחמימות הלילה (גרם)';

  @override
  String get carbBudgetFieldHint => 'לדוגמה: 20';

  @override
  String get carbBudgetFieldClear => 'נקה תקציב';

  @override
  String netCarbsChipLeavesSuffix(int grams) {
    return ' · נשאר $grams גרם';
  }

  @override
  String get hiddenCarbsSectionLabel => 'פחמימות נסתרות אפשריות';

  @override
  String get hiddenCarbsCertaintySuspected => 'חשד';

  @override
  String get hiddenCarbsCertaintyLikely => 'סביר';

  @override
  String get drinksGuideTitle => 'מדריך שתייה';

  @override
  String get drinksGuideDisclaimer =>
      'טווחי פחמימות נטו טיפוסיים למנה סטנדרטית. כל הנתונים הם הערכות — הערכים האמיתיים משתנים לפי מותג, גודל ומתכון.';

  @override
  String get drinksGuideSectionOrderAsIs => 'להזמין כמו שזה';

  @override
  String get drinksGuideSectionSwap => 'לבקש החלפה';

  @override
  String get drinksGuideSectionSkip => 'לדלג';

  @override
  String get settingsDrinksGuideTitle => 'מדריך שתייה';

  @override
  String get settingsDrinksGuideSubtitle => 'מדריך בר וקפה';

  @override
  String get actionAskAboutMenu => 'שאלו על התפריט הזה';

  @override
  String get menuQuestionSheetTitle => 'שאלו על התפריט הזה';

  @override
  String get menuQuestionSheetHint => 'לדוגמה: אילו מנות הן ללא מוצרי חלב?';

  @override
  String get menuQuestionSheetAsk => 'שאל';

  @override
  String get menuQuestionSheetLoading => 'שואל…';

  @override
  String get menuQuestionSheetAskAnother => 'שאלו שאלה נוספת';

  @override
  String get menuQuestionFailedNotConfigured =>
      'בינה מלאכותית אינה זמינה בגרסה הזו, ולכן לא ניתן היה לענות על השאלה.';

  @override
  String get menuQuestionFailedOffline =>
      'נראה שאינכם מחוברים. התחברו מחדש ונסו לשאול שוב.';

  @override
  String get menuQuestionFailedTimeout =>
      'מודל הבינה המלאכותית היה איטי מדי. נסו לשאול שוב.';

  @override
  String get menuQuestionFailedRateLimited =>
      'המגבלה היומית של הבינה המלאכותית נוצלה. נסו שוב מאוחר יותר.';

  @override
  String get menuQuestionFailedBadResponse =>
      'הבינה המלאכותית החזירה תשובה לא שמישה. נסו לנסח את השאלה אחרת.';

  @override
  String get menuQuestionFailedBackendUnreachable =>
      'לא ניתן היה להתחבר לשרת של קטוקלאב. נסו לשאול שוב.';

  @override
  String get menuQuestionFailedConsentWithheld =>
      'אשרו ניתוח בינה מלאכותית בהגדרות כדי לשאול שאלות על תפריט.';

  @override
  String get menuQuestionFailedApiKeyMissing =>
      'הוסיפו את מפתח ה‑Gemini API שלכם בהגדרות כדי לשאול שאלות על תפריט.';

  @override
  String get menuQuestionFailedApiKeyRejected =>
      'Gemini דחתה את מפתח ה‑API שלכם. בדקו אותו בהגדרות ונסו לשאול שוב.';
}
