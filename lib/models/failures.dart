/// Why a menu could not be fetched from a restaurant platform
/// (architecture.md §10).
enum MenuFetchFailureReason {
  /// The adapter hit a socket or DNS error. Shown as "No connection.
  /// Showing the cached menu from {date}." when a cached menu exists.
  offline,

  /// The adapter got a 404. Shown as "Venue not found on {platform}.
  /// Check the link."
  notFound,

  /// The adapter got a non-JSON or unexpectedly shaped body. Shown as
  /// "{platform} changed its menu format. Please report this."
  platformChanged,

  /// The repository was asked to read a site with no adapter for it.
  /// Shown as "KetoClub cannot read menus from this site yet."
  unsupportedSource,
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
