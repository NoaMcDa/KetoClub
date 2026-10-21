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
  String get actionMoreMenuOptions => 'אפשרויות נוספות';

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
    return 'לדלג ($count)';
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
  String get verdictOrderAsIs => 'להזמין כמו שהוא';

  @override
  String get verdictModifiable => 'עם שינויים';

  @override
  String get verdictNonKeto => 'לדלג';

  @override
  String get dishCardFullScreen => 'מסך מלא';

  @override
  String dishCardFullScreenSemanticLabel(String dish) {
    return 'הצג כרטיס למלצר עבור $dish';
  }

  @override
  String get waiterCardTitle => 'זה מה שאומרים למלצר';

  @override
  String get settingsAiPrivacy => 'בינה מלאכותית ופרטיות';

  @override
  String get settingsConsentTitle => 'מה יוצא מהמכשיר הזה';

  @override
  String get settingsConsentBody =>
      'ניתוח בינה מלאכותית פועל כברירת מחדל: כשאתם פותחים או מדביקים תפריט, שמות המנות, התיאורים ושמות התוספות — וכל שאלה שאתם כותבים על תפריט — נשלחים לשרת של קטוקלאב, שמעביר אותם לניתוח ב‑Gemini API של Google. שום דבר אחר עליכם או על ההיסטוריה שלכם לא נשלח. המיקום שלכם נשלח ל‑Wolt רק כשאתם מחפשים מסעדות בקרבתכם, ואינו נשמר. אין איסוף נתונים. התפריט, הניתוח שלו, שם המסעדה והעיר נשמרים גם בשרת של קטוקלאב, בלי שום פרט שמזהה אתכם, כדי שאחרים יוכלו למצוא אותם. בטלו את הסימון כדי להשאיר כל תפריט על המכשיר.';

  @override
  String get settingsConsentAccept => 'אפשר ניתוח בינה מלאכותית';

  @override
  String get consentDisclosureOk => 'אישור';

  @override
  String get consentDisclosureTurnOff => 'כבה';

  @override
  String get settingsConsentBodyDirect =>
      'ניתוח בינה מלאכותית פועל כברירת מחדל: כשאתם פותחים או מדביקים תפריט, שמות המנות, התיאורים ושמות התוספות — וכל שאלה שאתם כותבים על תפריט — נשלחים ישירות מהמכשיר הזה ל‑Gemini API של Google, עם מפתח ה‑API שלכם. שום דבר אחר עליכם או על ההיסטוריה שלכם לא נשלח. המיקום שלכם נשלח ל‑Wolt רק כשאתם מחפשים מסעדות בקרבתכם, ואינו נשמר. אין איסוף נתונים. התפריט, הניתוח שלו, שם המסעדה והעיר נשמרים גם בשרת של קטוקלאב, בלי שום פרט שמזהה אתכם, כדי שאחרים יוכלו למצוא אותם. בטלו את הסימון כדי להשאיר כל תפריט על המכשיר.';

  @override
  String get settingsConsentBodyDirectViaBackend =>
      'ניתוח בינה מלאכותית פועל כברירת מחדל: כשאתם פותחים או מדביקים תפריט, שמות המנות, התיאורים ושמות התוספות — וכל שאלה שאתם כותבים על תפריט — נשלחים מהמכשיר הזה לשרת של קטוקלאב, שמעביר אותם לניתוח ב‑Gemini API של Google. מפתח ה‑API שלכם משמש רק אם אי אפשר להגיע לשרת. שום דבר אחר עליכם או על ההיסטוריה שלכם לא נשלח. המיקום שלכם נשלח ל‑Wolt רק כשאתם מחפשים מסעדות בקרבתכם, ואינו נשמר. אין איסוף נתונים. התפריט, הניתוח שלו, שם המסעדה והעיר נשמרים גם בשרת של קטוקלאב, בלי שום פרט שמזהה אתכם, כדי שאחרים יוכלו למצוא אותם. בטלו את הסימון כדי להשאיר כל תפריט על המכשיר.';

  @override
  String get settingsKeySection => 'מפתח Gemini API';

  @override
  String get settingsKeyBody =>
      'בטלפון הזה, ניתוח בינה מלאכותית פונה ישירות ל‑Gemini API של Google עם המפתח שלכם. אפשר ליצור מפתח בחינם ב‑Google AI Studio. המפתח נשמר באחסון המאובטח של המכשיר ונשלח רק ל‑Google.';

  @override
  String get settingsKeyBodyViaBackend =>
      'בטלפון הזה, ניתוח בינה מלאכותית נשלח קודם לשרת של קטוקלאב. המפתח שלכם משמש רק אם אי אפשר להגיע לשרת: אז המכשיר פונה איתו ישירות ל‑Gemini API של Google. אפשר ליצור מפתח בחינם ב‑Google AI Studio. המפתח נשמר באחסון המאובטח של המכשיר ונשלח רק ל‑Google.';

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
  String get settingsRestrictions => 'ההגבלות שלי';

  @override
  String get settingsRestrictionsEmpty => 'עדיין לא הוספתם הגבלה.';

  @override
  String get settingsRestrictionsAdd => 'הוספת הגבלה';

  @override
  String settingsRestrictionsRemove(String name) {
    return 'הסרת $name';
  }

  @override
  String get restrictionKindAllergy => 'אלרגיה';

  @override
  String get restrictionKindAutoimmune => 'מחלה אוטואימונית';

  @override
  String get restrictionKindIntolerance => 'אי-סבילות';

  @override
  String get restrictionKindDiet => 'אורח תזונה';

  @override
  String restrictionJurisdictionHint(String lists) {
    String _temp0 = intl.Intl.selectLogic(lists, {
      'usEu': 'ברשימות האלרגנים של ארה״ב והאיחוד האירופי',
      'us': 'ברשימת האלרגנים של ארה״ב',
      'eu': 'ברשימת האלרגנים של האיחוד האירופי',
      'other': 'לא מופיע באף רשימת אלרגנים רשמית',
    });
    return '$_temp0';
  }

  @override
  String get restrictionPickerTitle => 'בחירת הגבלה';

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
  String get settingsCacheSection => 'תפריטים אחרונים';

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
      'פעולה זו תמחק את כל התפריטים השמורים במכשיר הזה ותנקה את רשימת האחרונים, כולל כל תפריט שאפשר לפתוח כרגע בלי אינטרנט. פתחו מסעדה שוב כדי לשמור אותה.';

  @override
  String get settingsClearCacheConfirmAction => 'נקה';

  @override
  String get settingsCacheCleared => 'התפריטים השמורים ורשימת האחרונים נוקו.';

  @override
  String get settingsAboutSection => 'אודות';

  @override
  String get settingsAboutVersion => 'גרסה';

  @override
  String settingsAboutVersionValue(String version, String build) {
    return '$version (בנייה $build)';
  }

  @override
  String get settingsAboutLicences => 'רישיונות קוד פתוח';

  @override
  String get settingsAboutPrivacy => 'פרטיות';

  @override
  String get settingsAboutReport => 'דיווח על תקלה';

  @override
  String get settingsAboutReportHint =>
      'פותח את מעקב התקלות של קטוקלאב ב-GitHub';

  @override
  String get settingsAboutLinkFailed => 'לא ניתן היה לפתוח את הקישור.';

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
      'כל תפריט שאתם פותחים מופיע כאן עם הציון ומספרי המנות שלו, עד שתסירו אותו. תפריטים שנפתחו ביממה האחרונה זמינים גם ללא חיבור לאינטרנט.';

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
  String savedExpiresMinutes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'יפוג בעוד $count דקות',
      two: 'יפוג בעוד דקתיים',
      one: 'יפוג בעוד דקה',
    );
    return '$_temp0';
  }

  @override
  String savedExpiresHours(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'יפוג בעוד $count שעות',
      two: 'יפוג בעוד שעתיים',
      one: 'יפוג בעוד שעה',
    );
    return '$_temp0';
  }

  @override
  String savedExpiresDays(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'יפוג בעוד $count ימים',
      two: 'יפוג בעוד יומיים',
      one: 'יפוג בעוד יום',
    );
    return '$_temp0';
  }

  @override
  String get savedExpired => 'פג תוקף, יתרענן בפתיחה';

  @override
  String get savedKept => 'נשמר, ללא תפוגה';

  @override
  String get savedKeep => 'שמור';

  @override
  String savedKeepSemanticLabel(String venue) {
    return 'שמור את $venue מעבר לתפוגה';
  }

  @override
  String get savedUnkeep => 'הפסק לשמור';

  @override
  String savedUnkeepSemanticLabel(String venue) {
    return 'הפסק לשמור את $venue';
  }

  @override
  String get savedUndo => 'בטל';

  @override
  String savedOpenedAgo(String age) {
    return 'נפתח $age';
  }

  @override
  String savedOpenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'נפתח $count פעמים',
      two: 'נפתח פעמיים',
      one: 'נפתח פעם אחת',
    );
    return '$_temp0';
  }

  @override
  String get savedNotOnDevice => 'לא שמור במכשיר הזה, ייפתח כשיש חיבור';

  @override
  String get savedScanGone => 'כבר לא שמור במכשיר הזה';

  @override
  String get savedRename => 'שנה שם';

  @override
  String savedRenameSemanticLabel(String venue) {
    return 'שנה את השם של $venue';
  }

  @override
  String get discoveryTitle => 'איפה לאכול';

  @override
  String get discoveryEmptyTitle => 'מצאו איפה לאכול';

  @override
  String get discoveryEmptyBody =>
      'השתמשו במיקום שלכם כדי לראות מסעדות בסביבה, חפשו לפי שם, או הדביקו למעלה קישור מוולט כדי לפתוח את התפריט המסווג לפי קטו.';

  @override
  String get discoveryDrinksGuideCard => 'מזמינים משקה? מדריך בר וקפה';

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
      'צריך ציונים קודם: הם מופיעים כשהרשימה מדורגת, או כשפותחים מסעדה.';

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
  String get discoveryEstimateList => 'דירוג מהיר לשאר (כללים במכשיר)';

  @override
  String get discoveryEstimateHint =>
      'המסעדות הראשונות מדורגות אוטומטית לפי כללים במכשיר, למנות אוכל בלבד. לניתוח מלא עם בינה מלאכותית, פתחו מסעדה.';

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
  String get tileGreenLabel => 'להזמין כמו שהוא';

  @override
  String get tileYellowLabel => 'עם שינויים';

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
  String get legendFoodOnly =>
      'הציון והמונים מתייחסים למנות אוכל בלבד. משקאות, רטבים ותוספות עדיין מסווגים ומוצגים, אך אינם נספרים.';

  @override
  String get legendBudget =>
      'תקציב פחמימות: לאחר ניתוח בינה מלאכותית, שדה בסינון מאפשר לקבוע תקציב פחמימות נטו לארוחה. לתוצאות על בסיס כללים אין הערכת פחמימות, ולכן הוא לא מוצע.';

  @override
  String get waiterCardCopyButton => 'העתק טקסט';

  @override
  String get waiterCardCopied => 'הועתק ✓';

  @override
  String get waiterCardDone => 'סיום';

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
  String get menuRenameAction => 'שנה שם';

  @override
  String get menuRenameTitle => 'תנו שם לתפריט';

  @override
  String get menuRenameHint => 'שם המסעדה';

  @override
  String get menuRenameCityHint => 'עיר';

  @override
  String get menuRenameSave => 'שמור';

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
  String sourceWithCity(String platform, String city) {
    return '$platform · $city';
  }

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
  String scannedPageHeader(int number, int total) {
    return 'עמוד $number מתוך $total';
  }

  @override
  String get scannedPageUnknown => 'עמוד לא ידוע';

  @override
  String get scannedPageUnknownExplain =>
      'ה-AI לא ציין באיזה עמוד נמצאות המנות האלה.';

  @override
  String scannedPageDishCount(int count) {
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
  String get scannedPageHeaderOpen => 'הצגת העמוד הזה';

  @override
  String get scannedPageChipAll => 'כל העמודים';

  @override
  String scannedPageChipSemanticLabel(String page) {
    return 'הצגת מנות שנקראו מ$page';
  }

  @override
  String get scannedMenuPagesGone =>
      'התמונות של הסריקה הזאת כבר אינן במכשיר, ולכן העמודים מוצגים לפי מספר בלבד.';

  @override
  String get scannedPagesReadFromPage => 'נקרא מהעמוד הזה';

  @override
  String get scanScreenIntro =>
      'צלמו את דפי התפריט, בחרו תמונות מהגלריה או בחרו קובץ PDF. קטוקלאב קורא את המנות מהדפים ומנתח אותן.';

  @override
  String get scanScreenModePages => 'תמונות ו-PDF';

  @override
  String get scanScreenModePaste => 'הדבקת טקסט';

  @override
  String get scanScreenModeQr => 'קוד QR';

  @override
  String get scanScreenQrIntro =>
      'סרקו את קוד ה-QR שעל השולחן כדי לפתוח את התפריט של המסעדה.';

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
  String scanScreenReorderPage(int number) {
    return 'הזזת דף $number. גררו כדי לסדר מחדש';
  }

  @override
  String scanScreenPreviewPage(int number) {
    return 'תצוגה מקדימה של דף $number';
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
  String get scanScreenDisclosureWeb =>
      'הדפים נשלחים לשרת של קטוקלאב, שמעביר אותם ל-Gemini API של גוגל לקריאה. התפריט שתומלל, הניתוח שלו, והשם והעיר שתתנו לו נשמרים גם בשרת של קטוקלאב, באופן אנונימי.';

  @override
  String get scanScreenDisclosureDirect =>
      'הדפים נשלחים ישירות מהמכשיר הזה ל-Gemini API של גוגל, באמצעות מפתח ה-API שלכם. התפריט שתומלל, הניתוח שלו, והשם והעיר שתתנו לו נשמרים גם בשרת של קטוקלאב, באופן אנונימי.';

  @override
  String get scanScreenDisclosureDirectViaBackend =>
      'הדפים נשלחים מהמכשיר הזה לשרת של קטוקלאב, שמעביר אותם ל-Gemini API של גוגל לקריאה. מפתח ה-API שלכם משמש רק אם אי אפשר להגיע לשרת. התפריט שתומלל, הניתוח שלו, והשם והעיר שתתנו לו נשמרים גם בשרת של קטוקלאב, באופן אנונימי.';

  @override
  String get scanScreenSettingsLink => 'הגדרות';

  @override
  String get scanScreenFailureNotConfigured => 'סריקה אינה זמינה בגרסה הזאת.';

  @override
  String get scanScreenFailureNeedsServer =>
      'סריקה דורשת את השרת של קטוקלאב, והגרסה הזאת לא מחוברת לשרת. הדבקת טקסט התפריט עדיין עובדת.';

  @override
  String get scanScreenFailureServerNotConfigured =>
      'השרת של קטוקלאב עדיין לא מוגדר לקריאת דפי תפריט. הדבקת טקסט התפריט עדיין עובדת.';

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
  String get scanScreenFailurePagesTooLarge =>
      'העמודים גדולים מכדי להישלח יחד, גם לאחר הקטנתם. הסירו עמוד ונסו שוב.';

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
  String drinksGuideCarbsSemanticLabel(String range) {
    return 'הערכת פחמימות נטו, לא מאומתת: $range';
  }

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

  @override
  String get helperToolSentence =>
      'האפליקציה קוראת תפריטים כדי לעזור לך לבחור. היא לא רואה את המטבח, לא מאמתת מתכון ולא מבטיחה דיוק. תמיד לשאול את המסעדה.';

  @override
  String get helperToolTitle => 'כלי עזר, לא הבטחה';

  @override
  String get whatLeavesDeviceBanto =>
      'פרופיל ההגבלות שלך והמילים שהוספת נשארים במכשיר. כשניתוח AI פועל, נשלחים רק טקסט התפריט, הגדרות הקטו ובקשה לפרט את רכיבי כל מנה — לעולם לא אילו הגבלות יש לך.';

  @override
  String get chefCardTitle => 'כרטיס השף שלך';

  @override
  String get chefCardShowButton => 'הצגת כרטיס השף שלי';

  @override
  String get chefCardEmpty => 'הוסיפו הגבלה בהגדרות וכרטיס השף יופיע כאן.';

  @override
  String get chefCardShare => 'שיתוף';

  @override
  String get chefCardLanguageLabel => 'שפת הכרטיס';

  @override
  String get whySheetTitle => 'למה התוצאה הזו';

  @override
  String whySheetDishName(String dish) {
    return '$dish';
  }

  @override
  String get whyTierDeclared => 'הוצהר על ידי הפלטפורמה';

  @override
  String get whyTierStated => 'כתוב בתפריט';

  @override
  String get whyTierInferred => 'משוער ממתכון אופייני';

  @override
  String get whyTierSuspected => 'חשד — כדאי לשאול';

  @override
  String get whyTierConfirmed => 'אושר מול הצוות';

  @override
  String get whyTierDenied => 'הצוות אמר שאין — עדיין לשאול';

  @override
  String get whySourceName => 'נמצא בשם המנה';

  @override
  String get whySourceDescription => 'נמצא בתיאור המנה';

  @override
  String get whySourceOption => 'נמצא באחת האפשרויות';

  @override
  String get whySourceHidden => 'מקור נסתר שהטקסט רומז עליו';

  @override
  String get whySourceModel =>
      'נקרא על ידי הבינה המלאכותית, לא מופיע בטקסט התפריט';

  @override
  String whyMatchedText(String text) {
    return 'נמצא: “$text”';
  }

  @override
  String get whyWaiterQuestionLabel => 'לשאול את המלצר';

  @override
  String get whyEmptyStrict =>
      'שום דבר בטקסט התפריט לא מצביע על ההגבלות שלך. עדיין כדאי לשאול את המסעדה.';

  @override
  String get whyEmptyFlexible =>
      'שום דבר בטקסט התפריט לא מצביע על ההגבלות שלך.';

  @override
  String get restrictionOnboardingTitle => 'ממה אתם נמנעים?';

  @override
  String get restrictionOnboardingBody =>
      'בחרו כל מה שרלוונטי. אפשר לשנות זאת בכל עת בהגדרות. דלגו כדי להשתמש בקטו בלבד.';

  @override
  String get restrictionOnboardingContinue => 'המשך';

  @override
  String get restrictionOnboardingSkip => 'דלגו';

  @override
  String menuProfileSummary(String names) {
    return 'בודקים עבור: $names';
  }

  @override
  String get stateFitsBadge => 'מתאימה';

  @override
  String get stateFitsStrictBadge => 'לא נמצא חשש — לשאול את המסעדה';

  @override
  String get stateFitsWithChangeBadge => 'מתאימה עם שינוי';

  @override
  String get stateAskBadge => 'לשאול קודם';

  @override
  String get stateAvoidBadge => 'להימנע';

  @override
  String get stateFitsTile => 'מתאימות';

  @override
  String get stateFitsStrictTile => 'ללא חשש';

  @override
  String get stateFitsWithChangeTile => 'עם שינוי';

  @override
  String get stateAskTile => 'לשאול';

  @override
  String get stateAvoidTile => 'להימנע';

  @override
  String get stateLegendFits => 'שום דבר בטקסט התפריט לא סותר את ההגבלות שלך.';

  @override
  String get stateLegendFitsStrict =>
      'בטקסט התפריט לא נמצא חשש להגבלות שלך. האפליקציה קראה רק את הטקסט, אז לשאול את המסעדה.';

  @override
  String get stateLegendFitsWithChange =>
      'מתאימה אם מוותרים על משהו שאפשר להוריד. שורת המלצר אומרת מה לבקש.';

  @override
  String get stateLegendAsk =>
      'משהו במנה עלול להסתיר אחת מההגבלות שלך. לשאול את המסעדה לפני שמזמינים.';

  @override
  String get stateLegendAvoid =>
      'אחת ההגבלות שלך מופיעה במנה עצמה, או שהמנה לא קטו כשקטו בפרופיל שלך.';

  @override
  String get stateLegendFoodOnly =>
      'המונים סופרים רק אוכל. משקאות, רטבים ותוספות עדיין נבדקים ומוצגים, אבל לא נספרים.';

  @override
  String get menuShowingFits => 'מוצגות מנות שמתאימות';

  @override
  String get menuShowingFitsStrict => 'מוצגות מנות שלא נמצא בהן חשש';

  @override
  String get menuShowingFitsWithChange => 'מוצגות מנות שמתאימות עם שינוי';

  @override
  String get menuShowingAsk => 'מוצגות מנות שכדאי לשאול עליהן';

  @override
  String get menuShowingAvoid => 'מוצג ממה להימנע';

  @override
  String get menuShowingNotAvoid => 'מוצג הכול חוץ ממה שכדאי להימנע ממנו';

  @override
  String headerStateCounts(int fits, int change, int ask) {
    return '$fits מתאימות · $change עם שינוי · $ask לשאול';
  }

  @override
  String headerStateCountsStrict(int fits, int change, int ask) {
    return '$fits ללא חשש · $change עם שינוי · $ask לשאול';
  }

  @override
  String get concernSourceName => 'בשם המנה';

  @override
  String get concernSourceDescription => 'בתיאור';

  @override
  String get concernSourceOption => 'תוספת לבחירה';

  @override
  String get concernSourceHidden => 'רכיב נסתר';

  @override
  String get concernSourceModel => 'לפי ה-AI';

  @override
  String concernSourceWithText(String source, String text) {
    return '$source: $text';
  }

  @override
  String get concernCertaintyStated => 'כתוב במפורש';

  @override
  String get concernCertaintyLikely => 'סביר';

  @override
  String get concernCertaintySuspected => 'חשד — לשאול';

  @override
  String concernLineSemanticLabel(
    String restriction,
    String source,
    String certainty,
  ) {
    return '$restriction: $source, $certainty';
  }

  @override
  String get dishCardWhy => 'למה?';

  @override
  String dishCardWhySemanticLabel(String dish) {
    return 'למה זו התוצאה עבור $dish';
  }

  @override
  String get dishCardAskQuestion => 'מה לשאול את המלצר';

  @override
  String get engineChipRulesChecked => 'נבדק גם בכללים';

  @override
  String get engineChipRulesCheckedSemanticLabel =>
      'גם הכללים של האפליקציה בדקו את התפריט לפי ההגבלות שלך';

  @override
  String concernLineText(String source, String certainty) {
    return '$source · $certainty';
  }

  @override
  String get whyTierDeclaredRestaurant => 'הוצהר על ידי המסעדה';

  @override
  String whyDeclaredAbsent(String text) {
    return 'מסומן “$text” — זה מפחית את החשש אבל לא שולל אותו';
  }

  @override
  String get dishCardDeclaredKosher => 'כשר לפי הצהרת הפלטפורמה';

  @override
  String get waiterCardChefCard => 'כרטיס שף';

  @override
  String get menuAllergyNoteAction => 'העתקת הערת אלרגיה';

  @override
  String get menuAllergyNoteCopied => 'הערת האלרגיה הועתקה';

  @override
  String get menuAllergyNoteShare => 'שיתוף';

  @override
  String get menuAllergyNoteSubject => 'הערת אלרגיה';

  @override
  String kitchenNoticeSummary(String things) {
    return 'במטבח הזה יש $things — כדאי לשאול על מגע צולב';
  }

  @override
  String get kitchenListSeparator => ', ';

  @override
  String kitchenListAnd(String rest, String last) {
    return '$rest ו$last';
  }

  @override
  String get kitchenKindFryer => 'מטגנת';

  @override
  String get kitchenKindWok => 'מחבת ווק';

  @override
  String get kitchenKindSharedGrill => 'גריל משותף';

  @override
  String get kitchenKindBakery => 'מאפייה';

  @override
  String get kitchenKindNuts => 'אגוזים';

  @override
  String get kitchenKindSesame => 'שומשום';

  @override
  String get kitchenTitleFryer => 'מטגנת';

  @override
  String get kitchenTitleWok => 'ווק';

  @override
  String get kitchenTitleSharedGrill => 'גריל משותף';

  @override
  String get kitchenTitleBakery => 'מאפייה';

  @override
  String get kitchenTitleNuts => 'אגוזים';

  @override
  String get kitchenTitleSesame => 'שומשום';

  @override
  String get kitchenNoticeShow => 'הצגת השאלות';

  @override
  String get kitchenNoticeHide => 'הסתרת השאלות';

  @override
  String kitchenNoticeMattersFor(String restrictions) {
    return 'רלוונטי עבור: $restrictions';
  }

  @override
  String kitchenNoticeSeenIn(String dishes) {
    return 'לפי המנות: $dishes';
  }

  @override
  String get kitchenNoticeQuestionLabel => 'לשאול את הצוות';

  @override
  String kitchenNoticeCopyLabel(String thing) {
    return 'העתקת השאלה על $thing';
  }

  @override
  String get concernSourceKitchen => 'מטבח';

  @override
  String whySourceKitchen(String thing) {
    return 'במטבח הזה יש $thing — כדאי לשאול על מגע צולב';
  }

  @override
  String get whySourceKitchenGeneric =>
      'מהמטבח, לא מהמנה — כדאי לשאול על מגע צולב';

  @override
  String get settingsProfiles => 'אנשים במכשיר הזה';

  @override
  String get settingsProfilesNote =>
      'אפשר להוסיף את מי שאוכלים איתו ולבדוק תפריט לכמה אנשים יחד. כל פרופיל הוא מידע רפואי ונשמר רק במכשיר הזה.';

  @override
  String get profileDefaultName => 'אני';

  @override
  String get profileKetoOnly => 'קטו בלבד';

  @override
  String get settingsProfilesAdd => 'הוספת אדם';

  @override
  String get settingsProfilesImport => 'ייבוא פרופיל';

  @override
  String get profileNameAddTitle => 'הוספת אדם';

  @override
  String get profileNameRenameTitle => 'שינוי שם הפרופיל';

  @override
  String get profileNameLabel => 'שם';

  @override
  String get profileNameSave => 'שמירה';

  @override
  String get profileEditorRename => 'שינוי שם';

  @override
  String get profileEditorExport => 'שיתוף הפרופיל';

  @override
  String get profileEditorDelete => 'מחיקת הפרופיל';

  @override
  String profileDeleteTitle(String name) {
    return 'למחוק את הפרופיל של $name?';
  }

  @override
  String get profileDeleteBody => 'ההגבלות שבפרופיל יימחקו מהמכשיר הזה.';

  @override
  String get profileDeleteConfirm => 'מחיקה';

  @override
  String get profileExportTitle => 'לשתף מידע רפואי?';

  @override
  String profileExportBody(String name) {
    return 'הפרופיל הזה מפרט את הגבלות התזונה של $name, וזה מידע רפואי. הוא יוצא מהמכשיר רק כטקסט שתשלחו, אז כדאי לשתף אותו רק עם מי שסומכים עליו.';
  }

  @override
  String get profileExportConfirm => 'שיתוף';

  @override
  String get profileExportCopied =>
      'הפרופיל הועתק. אפשר להדביק אותו במכשיר השני.';

  @override
  String get profileImportTitle => 'ייבוא פרופיל';

  @override
  String get profileImportBody =>
      'פרופיל משותף הוא מידע רפואי: הגבלות התזונה של מישהו. שום דבר לא נשמר עד שבוחרים לשמור, ואז רק במכשיר הזה.';

  @override
  String get profileImportField => 'הדביקו את הפרופיל ששותף';

  @override
  String get profileImportRead => 'קריאת הפרופיל';

  @override
  String get profileImportInvalid => 'הטקסט הזה אינו פרופיל משותף.';

  @override
  String get profileImportAsk => 'לשמור את הפרופיל הזה במכשיר?';

  @override
  String get profileImportSave => 'שמירה במכשיר';

  @override
  String get profileImportFull => 'במכשיר כבר שמורים כל הפרופילים האפשריים.';

  @override
  String get profileEditorRestrictions => 'הגבלות';

  @override
  String get groupCombineTitle => 'לבדוק את התפריט עבור';

  @override
  String get groupCombineApply => 'החלה';

  @override
  String get groupCombineChefCard => 'כרטיס שף לאנשים האלה';

  @override
  String get groupCombineManage => 'ניהול האנשים בהגדרות';

  @override
  String groupFitsEveryone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count מנות מתאימות לכולם',
      one: 'מנה אחת מתאימה לכולם',
    );
    return '$_temp0';
  }

  @override
  String groupFitsEveryoneStrict(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count מנות שלא נמצא בהן חשש לאף אחד',
      one: 'מנה אחת שלא נמצא בה חשש לאף אחד',
    );
    return '$_temp0';
  }

  @override
  String groupBreakdownEntry(String name, String state) {
    return '$name: $state';
  }

  @override
  String groupBreakdownSemanticLabel(String breakdown) {
    return 'לכל אחד: $breakdown';
  }

  @override
  String get restrictionHeadsUpHint => 'התראה לפי הנחיות מקובלות, לא מדידה';

  @override
  String get restrictionAlphaGalHint =>
      'בשר יונקים ומוצריו. אם גם מוצרי חלב משפיעים עליך, כדאי להוסיף גם חלב';

  @override
  String get restrictionOwnTitle => 'להוסיף משלך';

  @override
  String get restrictionOwnNote =>
      'משהו שאינו ברשימה, כמו מנגו או כוסברה. נבדק רק במכשיר הזה, בקפדנות כמו אלרגיה, לפי המילים שכתובות בתפריט.';

  @override
  String get restrictionOwnField => 'מזון שיש להימנע ממנו';

  @override
  String get restrictionOwnAdd => 'הוספה';

  @override
  String get restrictionOwnRowSubtitle => 'משלך · נבדק בקפדנות';

  @override
  String get concernCertaintyHeadsUp => 'ייתכן שיש בזה הרבה — התראה, לא מדידה';

  @override
  String get helperToolOk => 'הבנתי';

  @override
  String get whyCoverageNameOnly => 'בתפריט מופיע רק שם המנה.';

  @override
  String get whyCoverageDescription => 'בתפריט מופיעים שם המנה ותיאור.';

  @override
  String get whyCoverageOptions => 'בתפריט מופיעים שם המנה ואפשרויות בחירה.';

  @override
  String get whyCoverageFull =>
      'בתפריט מופיעים שם המנה, תיאור ואפשרויות בחירה.';

  @override
  String get whyCoverageModelAndRules =>
      'ה-AI פירט את הרכיבים, וגם הכללים קראו את טקסט התפריט.';

  @override
  String get whyCoverageRulesOnly =>
      'רק הכללים קראו את טקסט התפריט, בלי רשימת רכיבים מ-AI. לשאול את המסעדה.';

  @override
  String get glp1TagProteinForward => 'החלבון במרכז';

  @override
  String get glp1TagSmallPortion => 'מנה קטנה';

  @override
  String glp1TagSemanticLabel(String tags) {
    return 'למנות קטנות: $tags';
  }

  @override
  String get settingsTrip => 'מצב טיול';

  @override
  String get settingsTripNote =>
      'נוסעים? בחרו יעד: תראו מה מסעדות שם חייבות לומר לכם ואילו מנות מקומיות מסתירות את ההגבלות שלכם. הקטו לא משתנה, והיעד נשמר רק במכשיר הזה.';

  @override
  String get settingsTripPick => 'בחירת יעד';

  @override
  String settingsTripActive(String country) {
    return 'טיול ל$country';
  }

  @override
  String get settingsTripBriefing =>
      'לפני היציאה: מה לשאול, ואיפה ההגבלות שלכם מסתתרות';

  @override
  String get settingsTripChange => 'החלפת יעד';

  @override
  String get settingsTripOff => 'כיבוי מצב טיול';

  @override
  String get tripPickerTitle => 'לאן נוסעים?';

  @override
  String get tripCountryIsrael => 'ישראל';

  @override
  String get tripCountryUnitedStates => 'ארצות הברית';

  @override
  String get tripCountryUnitedKingdom => 'בריטניה';

  @override
  String get tripCountryFrance => 'צרפת';

  @override
  String get tripCountryItaly => 'איטליה';

  @override
  String get tripCountrySpain => 'ספרד';

  @override
  String get tripCountryGermany => 'גרמניה';

  @override
  String get tripCountryJapan => 'יפן';

  @override
  String tripBriefingTitle(String country) {
    return 'לפני היציאה: $country';
  }

  @override
  String get tripBriefingRulesSection => 'מה מסעדות שם חייבות לומר לכם';

  @override
  String get tripBriefingRulesEmpty =>
      'אף אחת מההגבלות שלכם אינה אלרגיה או צליאק, ולכן אף חוק אלרגנים לא חל עליהן. שאלו את המסעדה בכל זאת.';

  @override
  String get tripHintRestaurantMustTell =>
      'ברשימת האלרגנים כאן: המסעדה חייבת לדעת לומר לכם. ובכל זאת, שאלו את המסעדה.';

  @override
  String get tripHintPackagedOnly =>
      'מסומן רק על מזון ארוז: מסעדות לא חייבות לומר לכם. שאלו בכל פעם.';

  @override
  String get tripHintPackagedOnlyLargeChains =>
      'מסומן על מזון ארוז; רק רשתות גדולות בקליפורניה חייבות לפרט אותו. שאלו בכל פעם.';

  @override
  String get tripHintNotRegulated =>
      'לא ברשימת האלרגנים כאן: אף אחד לא חייב לומר לכם. שאלו בכל פעם.';

  @override
  String get tripBriefingLexiconSection => 'איפה ההגבלות שלכם מסתתרות כאן';

  @override
  String get tripBriefingLexiconNote =>
      'רשימה קצרה מהנחיות שפורסמו, לא רשימה מלאה. בזמן הטיול התפריטים נקראים גם לפי המילים האלה; התאמה פירושה לשאול עליה.';

  @override
  String get tripBriefingLexiconEmpty =>
      'אין ברשימה הקצרה שלנו פריטים להגבלות שלכם כאן. זה לא אישור: שאלו בכל פעם.';

  @override
  String tripBriefingHides(String restrictions) {
    return 'עלול להכיל: $restrictions';
  }

  @override
  String get tripBriefingChefCard => 'פתיחת כרטיס השף שלי';

  @override
  String get tripBriefingChefCardNote =>
      'הכרטיס נוצר בטלפון הזה ונפתח גם בלי חיבור.';

  @override
  String allergenMatrixNotice(String date) {
    return 'מידע על אלרגנים מהמסעדה, מתאריך $date';
  }

  @override
  String allergenMatrixUnmatched(int count, String rows) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count שורות בו לא תואמות אף מנה בתפריט הזה: $rows',
      one: 'שורה אחת בו לא תואמת אף מנה בתפריט הזה: $rows',
    );
    return '$_temp0';
  }

  @override
  String get concernSourceMatrix => 'מידע האלרגנים של המסעדה';

  @override
  String get whySourceMatrix => 'מופיע במידע האלרגנים של המסעדה עצמה';

  @override
  String get whyTierDeclaredMatrix => 'הוצהר במידע האלרגנים של המסעדה';

  @override
  String whyMatrixAbsent(String row) {
    return 'מופיע כנטול ממנו, בשם “$row” — זה מפחית את החשש אבל לא שולל אותו';
  }

  @override
  String get confirmPromptOpen => 'שאלת את הצוות?';

  @override
  String get confirmPromptTitle => 'אחרי הארוחה';

  @override
  String get confirmPromptIntro =>
      'מה הצוות אמר לך? התשובות נשמרות רק במכשיר הזה ויופיעו על המנה בפעם הבאה שהתפריט ייפתח. תשובה נכונה לביקור ההוא בלבד, לכן כדאי לשאול בכל פעם.';

  @override
  String confirmPromptQuestion(String restriction, String dish) {
    return 'שאלת על $restriction במנה $dish?';
  }

  @override
  String get confirmAnswerPresent => 'אושר שיש';

  @override
  String get confirmAnswerAbsent => 'אושר שאין';

  @override
  String get confirmAnswerNotAsked => 'לא שאלתי';

  @override
  String get confirmChangeQuestion => 'שינו את המנה כפי שביקשתי';

  @override
  String get confirmChangeYes => 'כן';

  @override
  String get confirmChangeNo => 'לא';

  @override
  String get confirmNoteLabel => 'הערה (נשמרת רק במכשיר הזה)';

  @override
  String get confirmSave => 'שמירה';

  @override
  String get confirmSaved => 'נשמר במכשיר הזה';

  @override
  String get confirmNothing =>
      'שום דבר בתפריט הזה לא מצביע על ההגבלות שלך, לכן אין על מה לשאול.';

  @override
  String get confirmUnavailable =>
      'התפריט הזה כבר לא שמור במכשיר. אפשר לפתוח אותו שוב כדי לענות.';

  @override
  String concernConfirmedOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'אישרת עם הצוות, $dateString';
  }

  @override
  String concernDeniedOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'הצוות אמר שאין, $dateString — עדיין לשאול';
  }

  @override
  String whyConfirmedOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'אישרת עם הצוות ב־$dateString';
  }

  @override
  String whyDeniedOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'ב־$dateString הצוות אמר לך שזה לא במנה. זה נכון לביקור ההוא בלבד, לכן כדאי לשאול שוב בכל פעם.';
  }

  @override
  String get premiumTitle => 'Banto Premium';

  @override
  String get paywallIntro =>
      'פרימיום מוסיף עוד ל־Banto. ההגבלות שלך נבדקות באותו אופן בשתי התוכניות.';

  @override
  String get paywallReasonRestrictions =>
      'בתוכנית החינמית יש בפרופיל הגבלה אחת. בפרימיום אפשר להוסיף עוד.';

  @override
  String get paywallReasonGroup =>
      'פרופילים לאנשים אחרים, ובדיקת תפריט לכמה אנשים יחד, הם חלק מפרימיום.';

  @override
  String get paywallReasonTrip => 'מצב טיול הוא חלק מפרימיום.';

  @override
  String paywallReasonScans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'השתמשת ב־$count הסריקות החינמיות של החודש.',
      one: 'השתמשת בסריקה החינמית של החודש.',
    );
    return '$_temp0 בפרימיום אין מגבלה חודשית.';
  }

  @override
  String get paywallFeaturesHeading => 'מה פרימיום מוסיף';

  @override
  String get paywallFeatureRestrictions => 'יותר מהגבלה אחת בפרופיל';

  @override
  String get paywallFeatureGroup => 'פרופילים לאנשים שאוכלים איתך, שנבדקים יחד';

  @override
  String get paywallFeatureTrip =>
      'מצב טיול: מונחים מקומיים והערות על חוקי הסימון ביעד';

  @override
  String get paywallFeatureScans =>
      'סריקות תפריט בלי מגבלה חודשית: תמונות, PDF וטקסט מודבק';

  @override
  String get paywallNeverLocked =>
      'בשום תוכנית לא נועלים: כל הגבלה שכבר שמורה בפרופיל נבדקת בכל תפריט, וכרטיס השף, השאלות למלצר, ההסבר \"למה\" והבדיקה אחרי הארוחה נשארים בחינם. תמיד כדאי לשאול את המסעדה.';

  @override
  String paywallPrice(String price) {
    return '$price לחודש';
  }

  @override
  String get paywallPriceUnknown => 'המחיר יוצג כשהחנות תענה.';

  @override
  String get paywallBuy => 'הרשמה למינוי';

  @override
  String get paywallRestore => 'שחזור רכישה';

  @override
  String get paywallTerms =>
      'החיוב חודשי דרך חשבון ה־App Store או Google Play. אפשר לבטל בכל עת בהגדרות המינויים של החנות.';

  @override
  String get paywallActive => 'פרימיום פעיל במכשיר הזה. תודה.';

  @override
  String get paywallPending =>
      'החנות עדיין מעבדת את הרכישה. פרימיום ייפתח כשהיא תאושר.';

  @override
  String get paywallCancelled => 'הרכישה בוטלה.';

  @override
  String get paywallRestoredNone => 'בחנות אין מינוי פרימיום פעיל לחשבון הזה.';

  @override
  String get paywallFailedStoreUnavailable =>
      'אי אפשר להגיע לחנות מהמכשיר הזה כרגע. אפשר לנסות שוב מאוחר יותר.';

  @override
  String get paywallFailedProductNotFound => 'פרימיום עדיין לא זמין בחנות.';

  @override
  String get paywallFailedStoreError =>
      'החנות החזירה שגיאה. שום דבר לא השתנה; אפשר לנסות שוב.';

  @override
  String get paywallFailedTimedOut => 'החנות לא ענתה בזמן. אפשר לנסות שוב.';

  @override
  String get paywallFailedNotSold => 'פרימיום לא נמכר בגרסה הזו של האפליקציה.';

  @override
  String get settingsPremiumActive => 'פרימיום פעיל';

  @override
  String settingsPremiumFree(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'תוכנית חינמית: הגבלה אחת ו־$count סריקות בחודש',
      one: 'תוכנית חינמית: הגבלה אחת וסריקה אחת בחודש',
    );
    return '$_temp0';
  }

  @override
  String get settingsPremiumOpen => 'מה פרימיום מוסיף';

  @override
  String scanFreeScansLeft(int left, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      left,
      locale: localeName,
      other: 'נשארו $left מתוך $total סריקות חינמיות החודש',
      one: 'נשארה סריקה חינמית אחת מתוך $total החודש',
      zero: 'לא נשארו סריקות חינמיות החודש',
    );
    return '$_temp0';
  }

  @override
  String get chefCardAllergyNoteTitle => 'הודעת אלרגיה למנה הזו';

  @override
  String get chefCardAllergyNoteExplain =>
      'קצרה מספיק לתיבת ההערות באפליקציית משלוחים. היא בשפת הכרטיס.';

  @override
  String dishChangeHonouredOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'הצוות שינה את המנה כפי שביקשת, $dateString';
  }

  @override
  String dishChangeNotHonouredOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'הצוות לא שינה את המנה כפי שביקשת, $dateString';
  }

  @override
  String whyChangeHonouredOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'ב־$dateString הצוות שינה את המנה כפי שביקשת. זה היה לביקור ההוא, לכן כדאי לבקש את השינוי שוב בכל פעם.';
  }

  @override
  String whyChangeNotHonouredOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'ב־$dateString הצוות לא שינה את המנה כפי שביקשת.';
  }

  @override
  String get restrictionKindReligious => 'תזונה דתית';

  @override
  String get restrictionKosherHint =>
      'מסמן חזיר, פירות ים ובשר עם חלב לפי מילות התפריט. על תעודה יש לשאול את המסעדה';

  @override
  String get restrictionHalalHint =>
      'מסמן חזיר, אלכוהול, ג\'לטין ודם לפי מילות התפריט. על תעודה יש לשאול את המסעדה';

  @override
  String get restrictionKindMedical => 'מצב בריאותי';

  @override
  String get restrictionJapanListHint => 'ברשימת החובה של האלרגנים ביפן';

  @override
  String get restrictionJapanRecommendedHint =>
      'מומלץ לסימון ביפן, לא באף רשימת חובה';

  @override
  String get restrictionLegumePartHint => 'קטנית אחת בנפרד, לא כל הקטניות';

  @override
  String get restrictionFavaHint =>
      'חסר G6PD (פביזם), לא אלרגיה. נבדק באותה הקפדה';

  @override
  String get restrictionSearchField => 'חיפוש הגבלה';

  @override
  String get restrictionSearchEmpty =>
      'אין הגבלה מתאימה. אפשר להוסיף אותה כמילה משלך למטה.';

  @override
  String get discoveryChipFitsProfile => 'מתאים לפרופיל שלי';

  @override
  String get settingsShareConfirmations => 'שיתוף מה שהצוות אמר לך';

  @override
  String get settingsShareConfirmationsBody =>
      'כל תשובה שנשמרת אחרי ארוחה שולחת את המסעדה, את המנה, את ההגבלה ששאלת עליה ואם כן או לא, כדי שאחרים יראו כמה אנשים שמעו אותו דבר. לעולם לא את הפרופיל שלך, לעולם לא את ההערה שלך.';

  @override
  String get whatLeavesDeviceSharedConfirmations =>
      'שיתוף מה שהצוות אמר לך פועל: כל תשובה שנשמרת שולחת לשרת של קטוקלאב את המסעדה, את המנה, את ההגבלה האחת ששאלת עליה ואם כן או לא, בלי שום פרט שמזהה אותך. לעולם לא את הפרופיל שלך, לעולם לא את ההערה שלך.';

  @override
  String sharedConfirmationAbsent(int count, String restriction) {
    return '$count אנשים שאלו כאן ונאמר להם שאין במנה $restriction';
  }

  @override
  String sharedConfirmationPresent(int count, String restriction) {
    return '$count אנשים שאלו כאן ונאמר להם שיש במנה $restriction';
  }

  @override
  String get sharedConfirmationFooter =>
      'שותף על ידי סועדים אחרים. האפליקציה לא יכולה לבדוק את זה: תמיד לשאול במסעדה.';

  @override
  String get workedOffer => 'המקום הזה עבד לי';

  @override
  String get workedOfferSkip => 'לא עכשיו';

  @override
  String get workedChip => 'עבד לי';

  @override
  String workedTagNames(String names) {
    return 'עבד עבור $names';
  }

  @override
  String get workedMark => 'לסמן כמקום שעבד לי';

  @override
  String get workedUnmark => 'להסיר את הסימון \"עבד לי\"';

  @override
  String savedStateCount(String label, int count) {
    return '$label: $count';
  }

  @override
  String get savedRecheck =>
      'הפרופיל שלך השתנה מאז. אפשר לפתוח את התפריט כדי לבדוק שוב.';

  @override
  String exceptionsSheetTitle(String name) {
    return 'חריגים: $name';
  }

  @override
  String get exceptionsExplain =>
      'מנות שההתאמה היחידה שלהן היא אחת המילים האלה לא יסומנו עבור ההגבלה הזו.';

  @override
  String get exceptionsWholeWord =>
      'מילה נספרת רק כפי שהיא כתובה, ולכן כדאי להוסיף גם את הרבים אם רוצים שגם הוא יכוסה.';

  @override
  String get exceptionsCurrentHeading => 'החריגים שלך';

  @override
  String get exceptionsNone => 'אין עדיין';

  @override
  String get exceptionsSuggestionsHeading => 'הצעות';

  @override
  String get exceptionsField => 'מילה נוספת';

  @override
  String get exceptionsAdd => 'הוספה';

  @override
  String get exceptionsSave => 'שמירה';

  @override
  String exceptionsRemove(String word) {
    return 'הסרת $word';
  }

  @override
  String exceptionsFull(int max) {
    return 'אפשר לשמור עד $max חריגים להגבלה אחת. כדאי להסיר אחד כדי להוסיף אחר.';
  }

  @override
  String get exceptionsStrictNote =>
      'חריג אומר שהאפליקציה מפסיקה לסמן את המילה הזו. עדיין כדאי לשאול במסעדה.';

  @override
  String exceptionsRowLine(String words) {
    return 'למעט $words';
  }

  @override
  String get exceptionsEditHint => 'עריכת חריגים';

  @override
  String get orderAdd => 'להוסיף להזמנה שלי';

  @override
  String get orderRemove => 'להסיר מההזמנה שלי';

  @override
  String orderPill(int count) {
    return 'ההזמנה שלי · $count';
  }

  @override
  String orderPillSemantic(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ההזמנה שלי, $count מנות. פותח את כרטיס ההזמנה.',
      one: 'ההזמנה שלי, מנה אחת. פותח את כרטיס ההזמנה.',
    );
    return '$_temp0';
  }

  @override
  String get orderCardTitle => 'ההזמנה שלי';

  @override
  String orderCardRemoveDish(String dish) {
    return 'להסיר את $dish מההזמנה שלי';
  }

  @override
  String get orderCardAllergyTitle => 'לכל ההזמנה';

  @override
  String get orderCardCopy => 'העתקה';

  @override
  String get orderCardCopied => 'ההזמנה הועתקה';

  @override
  String get orderCardShare => 'שיתוף';

  @override
  String get orderCardClear => 'ניקוי ההזמנה';

  @override
  String get chefCardLanguageFrench => 'צרפתית';

  @override
  String get chefCardLanguageItalian => 'איטלקית';

  @override
  String get chefCardLanguageSpanish => 'ספרדית';

  @override
  String get chefCardLanguageGerman => 'גרמנית';

  @override
  String get chefCardLanguageJapanese => 'יפנית';

  @override
  String get chefCardTranslatedNote =>
      'תורגם על ידי האפליקציה ולא נבדק על ידי דובר/ת השפה — הציגו את הכרטיס ושאלו.';

  @override
  String get chefCardShareImage => 'שיתוף כתמונה';

  @override
  String get chefCardImageTitle => 'הכרטיס כתמונה';

  @override
  String get chefCardImageExplain =>
      'זו התמונה שתשותף. האפליקציה לא שומרת אותה.';

  @override
  String get chefCardImageShareButton => 'שיתוף התמונה';

  @override
  String get chefCardImageTextFallback =>
      'המכשיר הזה לא יכול לשתף תמונות, ולכן הכרטיס שותף כטקסט.';

  @override
  String get chefCardImageFailed =>
      'לא ניתן היה ליצור את התמונה. אפשר עדיין לשתף את הכרטיס כטקסט.';

  @override
  String tripBriefingChefCardLocalNote(String language) {
    return 'הכרטיס נפתח ב$language, בתרגום של האפליקציה שלא נבדק על ידי דובר/ת השפה. עברית ואנגלית זמינות בלחיצה.';
  }
}
