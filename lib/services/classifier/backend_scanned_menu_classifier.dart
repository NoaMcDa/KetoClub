/// Placeholder for `BackendScannedMenuClassifier` (issue #328,
/// architecture.md D25).
///
/// The scanned-menu classifier that sends a scan's pages to KetoClub's
/// backend, `POST /v1/scan`, and reads back the menu and its analysis. The
/// path is pinned to this file by the network-boundary test in
/// `test/architecture/import_rules_test.dart` (issue #321), which needs the
/// file to exist before #328 fills it. It declares nothing yet.
library;
