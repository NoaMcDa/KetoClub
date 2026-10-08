/// Placeholder for `BackendMenuAdapter` (issue #327, architecture.md D25).
///
/// The adapter that asks KetoClub's backend for a complete platform menu,
/// `GET /v1/venue-menus/{source}/{platformId}`, and for a restaurant
/// website's menu, `POST /v1/website-menu`. Both paths are pinned to this
/// file by the network-boundary test in
/// `test/architecture/import_rules_test.dart` (issue #321), which needs the
/// file to exist before #327 fills it. It declares nothing yet.
library;
