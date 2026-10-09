import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/failures.dart';

/// The message for a scan that produced no menu (architecture.md §10, D15;
/// issue #82).
///
/// Separate from `analysisFailureMessage` because that copy ends "Showing
/// rule-based results", and a photographed menu has no rules fallback: the
/// rule engine needs text the pages do not have, so nothing is shown at
/// all. These sentences say instead that the pages are kept.
///
/// [directToGoogle] is true on iOS and Android, where the user's own key
/// can reach Google (D17), and [backendConfigured] when the build has a
/// KetoClub backend, which every platform asks first (D25). Together they
/// change only [MenuAnalysisFailureReason.notConfigured]: with a backend
/// it means the server has no model set up to read pages; without one, on
/// web, that there is no server to send them through, and on a phone that
/// scanning is unavailable on this build.
///
/// An exhaustive switch with no `default`: adding a reason without adding
/// its scan copy here is a compile error, never a silently collapsed
/// message (architecture.md §10, "collapsing reasons is a bug").
String scanFailureMessage(
  MenuAnalysisFailureReason reason,
  AppLocalizations l10n, {
  required bool directToGoogle,
  bool backendConfigured = false,
}) => switch (reason) {
  MenuAnalysisFailureReason.notConfigured =>
    backendConfigured
        ? l10n.scanScreenFailureServerNotConfigured
        : directToGoogle
        ? l10n.scanScreenFailureNotConfigured
        : l10n.scanScreenFailureNeedsServer,
  MenuAnalysisFailureReason.offline => l10n.scanScreenFailureOffline,
  MenuAnalysisFailureReason.timeout => l10n.scanScreenFailureTimeout,
  MenuAnalysisFailureReason.rateLimited => l10n.scanScreenFailureRateLimited,
  MenuAnalysisFailureReason.badResponse => l10n.scanScreenFailureBadResponse,
  MenuAnalysisFailureReason.noDishesFound =>
    l10n.scanScreenFailureNoDishesFound,
  MenuAnalysisFailureReason.backendUnreachable =>
    l10n.scanScreenFailureBackendUnreachable,
  MenuAnalysisFailureReason.consentWithheld =>
    l10n.scanScreenFailureConsentWithheld,
  MenuAnalysisFailureReason.apiKeyMissing =>
    l10n.scanScreenFailureApiKeyMissing,
  MenuAnalysisFailureReason.apiKeyRejected =>
    l10n.scanScreenFailureApiKeyRejected,
};
