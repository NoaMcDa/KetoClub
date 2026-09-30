import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';

/// The message for a menu-fetch failure (architecture.md §10).
///
/// [platform] names the source platform (e.g. "Wolt") and is required by
/// [MenuFetchFailureReason.notFound],
/// [MenuFetchFailureReason.blockedByBrowser] and
/// [MenuFetchFailureReason.platformChanged], and — as the site's host —
/// by every website reason (architecture.md D19); [statusCode] is required
/// by
/// [MenuFetchFailureReason.platformChanged].
/// A caller that omits one where it is expected gets an empty
/// placeholder rather than a thrown error, since a failure screen must
/// never itself fail.
///
/// An exhaustive switch with no `default`: adding a reason without adding
/// its copy here is a compile error, never a silently collapsed message
/// (architecture.md §10, "collapsing reasons is a bug").
String fetchFailureMessage(
  MenuFetchFailureReason reason,
  AppLocalizations l10n, {
  String? platform,
  int? statusCode,
}) => switch (reason) {
  MenuFetchFailureReason.offline => l10n.fetchFailedOffline,
  MenuFetchFailureReason.blockedByBrowser => l10n.fetchFailedBlockedByBrowser(
    platform ?? '',
  ),
  MenuFetchFailureReason.notFound => l10n.fetchFailedNotFound(platform ?? ''),
  MenuFetchFailureReason.platformChanged => l10n.fetchFailedPlatformChanged(
    platform ?? '',
    statusCode?.toString() ?? '',
  ),
  MenuFetchFailureReason.unsupportedSource => l10n.fetchFailedUnsupportedSource,
  MenuFetchFailureReason.backendUnreachable =>
    l10n.fetchFailedBackendUnreachable,
  MenuFetchFailureReason.scanNotSaved => l10n.fetchFailedScanNotSaved,
  MenuFetchFailureReason.menuNotFound => l10n.websiteMenuNotFound(
    platform ?? '',
  ),
  MenuFetchFailureReason.disallowedByRobots => l10n.websiteDisallowedByRobots(
    platform ?? '',
  ),
  MenuFetchFailureReason.jsOnlyPage => l10n.websiteJsOnlyPage(platform ?? ''),
  MenuFetchFailureReason.websiteUnreachable => l10n.websiteUnreachable(
    platform ?? '',
  ),
  MenuFetchFailureReason.websiteTooLarge => l10n.websiteTooLarge(
    platform ?? '',
  ),
  MenuFetchFailureReason.websiteRateLimited => l10n.websiteRateLimited(
    platform ?? '',
  ),
  MenuFetchFailureReason.websitePdfUnread => l10n.websitePdfUnread(
    platform ?? '',
  ),
};

/// The message for a menu-analysis failure (architecture.md §10).
///
/// [detail] is read only by [MenuAnalysisFailureReason.badResponse]; a
/// caller that omits it, or passes a blank one, gets the detail-free
/// sentence rather than "AI analysis failed ()" — which is what every
/// rules-fallback banner rendered, since a `RulesEngine` carries no
/// detail to pass (issue #189).
///
/// An exhaustive switch with no `default`: adding a reason without adding
/// its copy here is a compile error, never a silently collapsed message
/// (architecture.md §10, "collapsing reasons is a bug").
String analysisFailureMessage(
  MenuAnalysisFailureReason reason,
  AppLocalizations l10n, {
  String? detail,
}) => switch (reason) {
  MenuAnalysisFailureReason.notConfigured => l10n.analysisNotConfigured,
  MenuAnalysisFailureReason.offline => l10n.analysisOffline,
  MenuAnalysisFailureReason.timeout => l10n.analysisTimeout,
  MenuAnalysisFailureReason.rateLimited => l10n.analysisRateLimited,
  MenuAnalysisFailureReason.badResponse =>
    detail == null || detail.trim().isEmpty
        ? l10n.analysisBadResponseNoDetail
        : l10n.analysisBadResponse(detail),
  MenuAnalysisFailureReason.noDishesFound => l10n.analysisNoDishesFound,
  MenuAnalysisFailureReason.backendUnreachable =>
    l10n.analysisBackendUnreachable,
  MenuAnalysisFailureReason.consentWithheld => l10n.analysisConsentWithheld,
  MenuAnalysisFailureReason.apiKeyMissing => l10n.analysisApiKeyMissing,
  MenuAnalysisFailureReason.apiKeyRejected => l10n.analysisApiKeyRejected,
};

/// The message for a menu question failure (architecture.md §9.5; issue #214).
///
/// Distinct copy per reason with no rules-fallback path: unlike menu
/// analysis, a free-text question has no on-device equivalent, so every
/// message says the question could not be answered rather than offering
/// an alternative.
///
/// An exhaustive switch with no `default`: adding a reason without adding
/// its copy here is a compile error, never a silently collapsed message
/// (architecture.md §10, "collapsing reasons is a bug").
String menuQuestionFailureMessage(
  MenuAnalysisFailureReason reason,
  AppLocalizations l10n,
) => switch (reason) {
  MenuAnalysisFailureReason.notConfigured =>
    l10n.menuQuestionFailedNotConfigured,
  MenuAnalysisFailureReason.offline => l10n.menuQuestionFailedOffline,
  MenuAnalysisFailureReason.timeout => l10n.menuQuestionFailedTimeout,
  MenuAnalysisFailureReason.rateLimited => l10n.menuQuestionFailedRateLimited,
  MenuAnalysisFailureReason.badResponse => l10n.menuQuestionFailedBadResponse,
  MenuAnalysisFailureReason.noDishesFound => l10n.menuQuestionFailedBadResponse,
  MenuAnalysisFailureReason.backendUnreachable =>
    l10n.menuQuestionFailedBackendUnreachable,
  MenuAnalysisFailureReason.consentWithheld =>
    l10n.menuQuestionFailedConsentWithheld,
  MenuAnalysisFailureReason.apiKeyMissing =>
    l10n.menuQuestionFailedApiKeyMissing,
  MenuAnalysisFailureReason.apiKeyRejected =>
    l10n.menuQuestionFailedApiKeyRejected,
};

/// The message for a venue-search failure (`phase2_discovery_research.md`
/// §5, issue #39).
///
/// Takes no placeholders: venue search is Wolt's alone, and a status
/// code on [VenueSearchFailed] is for a log, not for the user.
///
/// An exhaustive switch with no `default`: adding a reason without adding
/// its copy here is a compile error, never a silently collapsed message
/// (architecture.md §10, "collapsing reasons is a bug").
String venueSearchFailureMessage(
  VenueSearchFailureReason reason,
  AppLocalizations l10n,
) => switch (reason) {
  VenueSearchFailureReason.offline => l10n.venueSearchFailedOffline,
  VenueSearchFailureReason.timeout => l10n.venueSearchFailedTimeout,
  VenueSearchFailureReason.rateLimited => l10n.venueSearchFailedRateLimited,
  VenueSearchFailureReason.platformChanged =>
    l10n.venueSearchFailedPlatformChanged,
  VenueSearchFailureReason.blockedByBrowser =>
    l10n.venueSearchFailedBlockedByBrowser,
  VenueSearchFailureReason.backendUnreachable =>
    l10n.venueSearchFailedBackendUnreachable,
};
