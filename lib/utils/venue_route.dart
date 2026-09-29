import 'package:ketoclub/models/venue.dart';

/// The route that opens [ref]'s menu: `/venue/{source}/{platformId}`, with
/// the platform id percent-encoded so a website's URL (architecture.md
/// D19) stays one path segment. `app.dart`'s `venueRefFromPath` reads it
/// back; a slug, a numeric id or a scan's hex id is unchanged by the
/// encoding.
String venueRoutePath(VenueRef ref) =>
    '/venue/${ref.source.name}/${Uri.encodeComponent(ref.platformId)}';
