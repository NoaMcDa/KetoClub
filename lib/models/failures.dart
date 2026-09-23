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
}
