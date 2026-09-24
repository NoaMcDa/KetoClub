import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/services/venue/venue_search_service.dart';

/// The message for a menu-fetch failure (architecture.md §10).
///
/// [platform] names the source platform (e.g. "Wolt") and is required by
/// [MenuFetchFailureReason.notFound],
/// [MenuFetchFailureReason.blockedByBrowser] and
/// [MenuFetchFailureReason.platformChanged]; [statusCode] is required by
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
};

/// The message for a menu-analysis failure (architecture.md §10).
///
/// [detail] is required by [MenuAnalysisFailureReason.badResponse]; a
/// caller that omits it gets an empty placeholder rather than a thrown
/// error, since a failure screen must never itself fail.
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
  MenuAnalysisFailureReason.badResponse => l10n.analysisBadResponse(
    detail ?? '',
  ),
  MenuAnalysisFailureReason.noDishesFound => l10n.analysisNoDishesFound,
  MenuAnalysisFailureReason.backendUnreachable =>
    l10n.analysisBackendUnreachable,
  MenuAnalysisFailureReason.consentWithheld => l10n.analysisConsentWithheld,
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
