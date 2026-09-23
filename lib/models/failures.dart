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
  /// No OpenRouter key is stored, or estimation consent was not given.
  /// The router falls back to the rules engine; the user sees "Add an
  /// OpenRouter key in Settings for AI analysis."
  notConfigured,

  /// The LLM client or router found no network route. The router falls
  /// back to the rules engine; the user sees "Offline. Showing
  /// rule-based results."
  offline,

  /// The LLM client waited past its 120-second budget. The router falls
  /// back to the rules engine; the user sees "The AI model was too
  /// slow. Showing rule-based results."
  timeout,

  /// The LLM gateway answered 429. The router falls back to the rules
  /// engine; the user sees "Daily AI limit reached for this key."
  rateLimited,

  /// The LLM gateway answered 401 or 403. There is no rules fallback;
  /// the user sees "Your OpenRouter key was rejected."
  unauthorised,

  /// The LLM gateway answered another 4xx/5xx, or the response parser
  /// rejected the body. The router falls back to the rules engine; the
  /// user sees "AI analysis failed ({detail}). Showing rule-based
  /// results."
  badResponse,

  /// The response parser found no dishes and nothing unclassified
  /// either. The user sees "The AI could not identify any dishes on
  /// this menu."
  noDishesFound,
}
