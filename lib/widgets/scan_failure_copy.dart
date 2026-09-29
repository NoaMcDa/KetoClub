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
/// [directToGoogle] is true on iOS and Android (D17), where the pages go
/// straight to Google; it only changes [MenuAnalysisFailureReason
/// .notConfigured], which on web means there is no KetoClub server to send
/// them through.
///
/// An exhaustive switch with no `default`: adding a reason without adding
/// its scan copy here is a compile error, never a silently collapsed
/// message (architecture.md §10, "collapsing reasons is a bug").
String scanFailureMessage(
  MenuAnalysisFailureReason reason,
  AppLocalizations l10n, {
  required bool directToGoogle,
}) => switch (reason) {
  MenuAnalysisFailureReason.notConfigured =>
    directToGoogle
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
