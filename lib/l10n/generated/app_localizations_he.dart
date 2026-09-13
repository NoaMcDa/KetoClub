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
  String get settingsKeySection => 'מפתח OpenRouter';

  @override
  String get settingsKeyHint => 'הדביקו את מפתח ה‑OpenRouter שלכם';

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
  String get settingsWebStorageNote =>
      'בדפדפן המפתח נשמר באחסון הדפדפן, שמגן עליו פחות טוב מהכספת של הטלפון.';

  @override
  String get settingsConsentTitle => 'מה יוצא מהמכשיר הזה';

  @override
  String get settingsConsentBody =>
      'כשיש מפתח, שמות המנות, התיאורים ושמות התוספות מהתפריט שאתם פותחים נשלחים ל‑OpenRouter לניתוח. שום דבר עליכם, על מקומכם או על ההיסטוריה שלכם לא נשלח. התפריטים נקראים ישירות מפלטפורמת המסעדה, שמקבלת רק את מזהה המסעדה. אין שרת אחר ואין איסוף נתונים.';

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
      'לא הצלחנו להגיע לשרת של קטוקלאב. נסו שוב.';

  @override
  String get analysisNotConfigured =>
      'הוסיפו מפתח OpenRouter בהגדרות כדי לקבל ניתוח בינה מלאכותית.';

  @override
  String get analysisOffline => 'לא מחוברים. מוצגות תוצאות על בסיס כללים.';

  @override
  String get analysisTimeout =>
      'מודל הבינה המלאכותית היה אטי מדי. מוצגות תוצאות על בסיס כללים.';

  @override
  String get analysisRateLimited =>
      'המגבלה היומית של הבינה המלאכותית למפתח הזה נגמרה. מוצגות תוצאות על בסיס כללים.';

  @override
  String get analysisUnauthorised =>
      'OpenRouter דחתה את המפתח שלכם, ולכן שום דבר לא נותח.';

  @override
  String analysisBadResponse(String detail) {
    return 'ניתוח הבינה המלאכותית נכשל ($detail). מוצגות תוצאות על בסיס כללים.';
  }

  @override
  String get analysisNoDishesFound =>
      'הבינה המלאכותית לא הצליחה לזהות מנות בתפריט הזה.';
}
