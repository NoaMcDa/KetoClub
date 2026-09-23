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
  String get venueSearchLabel => 'קישור למסעדה';

  @override
  String get venueSearchHint => 'הדביקו קישור מוולט, או מזהה מסעדה';

  @override
  String get venueSearchInvalid =>
      'קטוקלאב לא יודע לקרוא תפריט משם עדיין. הדביקו קישור למסעדה בוולט או את המזהה שלה.';

  @override
  String get venueSearchOpen => 'הצג תפריט קטוגני';

  @override
  String get menuLoading => 'קורא את התפריט…';

  @override
  String get menuEmpty => 'בתפריט הזה אין מנות.';

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
  String get waiterCardOpen => 'הצג כרטיס למלצר';

  @override
  String get waiterCardTitle => 'זה מה שאומרים למלצר';

  @override
  String get settingsConsentTitle => 'מה יוצא מהמכשיר הזה';

  @override
  String get settingsConsentBody =>
      'כשאתם מאשרים ניתוח בינה מלאכותית, שמות המנות, התיאורים ושמות התוספות מהתפריט שאתם פותחים נשלחים לשרת של קטוקלאב, שמעביר אותם לניתוח ב‑Gemini API של Google. שום דבר עליכם, על מקומכם או על ההיסטוריה שלכם לא נשלח. אין איסוף נתונים.';

  @override
  String get settingsConsentAccept => 'הבנתי';

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
  String get settingsFilter => 'סינון ברירת מחדל';

  @override
  String get settingsClearCache => 'נקה תפריטים שמורים';

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
  String get analysisNoDishesFound =>
      'הבינה המלאכותית לא הצליחה לזהות מנות בתפריט הזה.';

  @override
  String get analysisBackendUnreachable =>
      'לא ניתן היה להתחבר לשרת של קטוקלאב. מוצגות תוצאות על בסיס כללים.';

  @override
  String get analysisConsentWithheld =>
      'אשרו ניתוח בינה מלאכותית בהגדרות כדי לנתח את התפריט הזה. מוצגות תוצאות על בסיס כללים.';

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
  String get navSaved => 'שמורים';

  @override
  String get navSettings => 'הגדרות';

  @override
  String get scanPlaceholderTitle => 'סריקת תפריט';

  @override
  String get scanPlaceholderBody =>
      'צילום תפריט פיזי יתאפשר בעדכון עתידי. בינתיים, הדביקו קישור למשלוח במסך גילוי.';

  @override
  String get savedPlaceholderTitle => 'מסעדות שמורות';

  @override
  String get savedPlaceholderBody =>
      'שמרו מסעדה כדי למצוא אותה כאן בהמשך. האפשרות הזו תגיע בעדכון עתידי.';

  @override
  String get discoveryTitle => 'איפה לאכול';

  @override
  String get discoveryEmptyTitle => 'הדביקו קישור כדי להתחיל';

  @override
  String get discoveryEmptyBody =>
      'חיפוש עדיין לא זמין — הדביקו למעלה קישור למסעדה בוולט, או את המזהה שלה, כדי לראות תפריט מסווג לפי קטו.';

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
}
