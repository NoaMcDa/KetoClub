/// Why a menu could not be fetched from a restaurant platform
/// (architecture.md §10).
enum MenuFetchFailureReason {
  /// The adapter hit a socket or DNS error. Shown as "No connection.
  /// Showing the cached menu from {date}." when a cached menu exists.
  offline,

  /// The adapter ran in a browser, where the platform's missing CORS
  /// headers make the browser refuse the request before any response is
  /// seen (architecture.md §13). Kept apart from [offline] because the
  /// way out differs: no retry will help, the phone app will. Shown as
  /// "A browser cannot read {platform} menus. Use the KetoClub phone
  /// app."
  blockedByBrowser,

  /// The adapter got a 404. Shown as "Venue not found on {platform}.
  /// Check the link."
  notFound,

  /// The adapter got a non-JSON or unexpectedly shaped body. Shown as
  /// "{platform} changed its menu format. Please report this."
  platformChanged,

  /// The repository was asked to read a site with no adapter for it.
  /// Shown as "KetoClub cannot read menus from this site yet."
  unsupportedSource,

  /// The adapter was configured with a proxy base (architecture.md D11,
  /// `backend_plan.md` §4.1) and could not reach KetoClub's own backend —
  /// a socket or DNS error talking to it, never a status Wolt itself
  /// returned. KetoClub's own backend could not be reached; only possible
  /// when a proxy base is configured. Shown as "KetoClub's server could not
  /// be reached, so the menu could not be read."
  backendUnreachable,

  /// The repository was asked for a menu the user supplied as text
  /// (`MenuSource.scan`) and its cache no longer holds it — a scan has no
  /// platform to fetch from again (architecture.md D18). Shown as "This
  /// pasted menu is no longer saved on this device. Paste it again."
  scanNotSaved,

  /// A restaurant website was read, but no menu KetoClub can read was found
  /// on it: no JSON-LD menu, no menu page or PDF link, and no priced dish
  /// list in the page's own text — or the only text there was reversed
  /// Hebrew (architecture.md D19). Shown as "KetoClub could not find a menu
  /// it can read on {site}."
  menuNotFound,

  /// The website asks automated readers not to read the page: its
  /// `robots.txt` disallows KetoClub, or the page opts out of AI use
  /// (`noai`, `tdm-reservation`). Nothing is fetched past the refusal
  /// (D19). Shown as "{site} asks apps like KetoClub not to read its
  /// pages, so KetoClub does not."
  disallowedByRobots,

  /// The website builds its page with JavaScript only, which KetoClub does
  /// not run (D19). Shown as "{site} only shows its menu with JavaScript,
  /// which KetoClub cannot read yet."
  jsOnlyPage,

  /// The website itself could not be reached, timed out or answered with
  /// a server error, while KetoClub's own backend (web) was fine (D19).
  /// Shown as "{site} did not answer. Try again later."
  websiteUnreachable,

  /// The page or PDF is larger than KetoClub reads (D19). Shown as "The
  /// menu on {site} is too large for KetoClub to read."
  websiteTooLarge,

  /// KetoClub already read this site several times in the last minute,
  /// and spaces its requests to any one site (D19). Shown as "KetoClub
  /// read {site} a moment ago. Wait a minute, then try again."
  websiteRateLimited,

  /// The website's menu is a PDF, and only AI analysis can read a PDF: the
  /// vision read failed, was not allowed, or found no dish (D19; D15).
  /// Shown as "The menu on {site} is a PDF, which only AI analysis can
  /// read, and it could not be read now. Check AI analysis in Settings,
  /// then try again."
  websitePdfUnread,
}

/// Why menu analysis could not be produced, or fell back to the rules
/// engine (architecture.md §6.2, §10).
enum MenuAnalysisFailureReason {
  /// AI analysis is not available: this build has no backend URL, or
  /// KetoClub's server has no model key configured (it answers 503). The
  /// router falls back to the rules engine; the user sees "AI analysis is
  /// not available on this build or server. Showing rule-based results."
  notConfigured,

  /// No network route was found — by the device's connectivity
  /// pre-check, or by the server talking to the model provider. The
  /// router falls back to the rules engine; the user sees "Offline.
  /// Showing rule-based results."
  offline,

  /// The model call waited past its 120-second budget. The router falls
  /// back to the rules engine; the user sees "The AI model was too slow.
  /// Showing rule-based results."
  timeout,

  /// The model provider's quota is exhausted (the server answered 429).
  /// The router falls back to the rules engine; the user sees "Daily AI
  /// limit reached."
  rateLimited,

  /// The server answered another error status, or the response parser
  /// rejected the body. The router falls back to the rules engine; the
  /// user sees "AI analysis failed ({detail}). Showing rule-based
  /// results."
  badResponse,

  /// The response parser found no dishes and nothing unclassified
  /// either. The only reason with no rules fallback; the user sees "The
  /// AI could not identify any dishes on this menu."
  noDishesFound,

  /// KetoClub's server could not be reached — a socket or DNS error
  /// before any HTTP status was received. Never sent by the server
  /// itself. The router falls back to the rules engine; the user sees
  /// "KetoClub's server could not be reached. Showing rule-based
  /// results."
  backendUnreachable,

  /// The user has not allowed AI analysis in Settings. Client-only: the
  /// server is never asked, and the user can fix it themselves. The
  /// router falls back to the rules engine; the user sees "Allow AI
  /// analysis in Settings to analyse this menu. Showing rule-based
  /// results."
  consentWithheld,

  /// No Gemini API key is saved on this device (iOS and Android only,
  /// architecture.md D17). Client-only, and something the user can fix
  /// in Settings. The router falls back to the rules engine; the user
  /// sees "Add your Gemini API key in Settings to analyse this menu.
  /// Showing rule-based results."
  apiKeyMissing,

  /// Gemini refused the API key saved on this device (iOS and Android
  /// only, architecture.md D17). Something the user can fix in Settings.
  /// The router falls back to the rules engine; the user sees "Gemini
  /// rejected your API key. Check it in Settings. Showing rule-based
  /// results."
  apiKeyRejected,
}
