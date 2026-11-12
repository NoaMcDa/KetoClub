import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ketoclub/models/place.dart';
import 'package:ketoclub/services/place/photon/photon_place_mapper.dart';
import 'package:ketoclub/services/place/place_search_service.dart';

/// Searches for streets in Israel with Photon, komoot's public
/// OpenStreetMap geocoder, straight from the device (issue #449,
/// architecture.md D27).
///
/// This class does HTTP and the failure mapping only; reading Photon's
/// reply is [PhotonPlaceMapper]'s job. It works in a browser too: Photon
/// answers every origin with `Access-Control-Allow-Origin: *`.
///
/// One request per search: `GET https://photon.komoot.io/api/` with the
/// query, `limit=15`, `lang=en` for an English UI and `lang=default` for
/// any other (Photon has no Hebrew; `default` gives local, mostly Hebrew,
/// names), a bounding box around Israel, and `layer=house` and
/// `layer=street`. Nothing else is sent: no install id, no key and no
/// position — the query is the only thing that leaves the device.
///
/// Failure mapping: a `ClientException` is
/// [PlaceSearchFailureReason.offline], the time budget running out is
/// [PlaceSearchFailureReason.timeout], `429` is
/// [PlaceSearchFailureReason.rateLimited], and any other non-2xx status or
/// a body [PhotonPlaceMapper] cannot read is
/// [PlaceSearchFailureReason.providerChanged].
final class PhotonPlaceSearchService implements PlaceSearchService {
  /// Creates a service that sends its requests through [client].
  new({required http.Client client, this.timeout = const Duration(seconds: 10)})
    // The field is private and the parameter is not, so an initializing
    // formal is not available.
    // ignore: prefer_initializing_formals
    : _client = client;

  /// How long a search waits for Photon before reporting
  /// [PlaceSearchFailureReason.timeout].
  final Duration timeout;

  final http.Client _client;

  /// Photon's host.
  static const String host = 'photon.komoot.io';

  /// A box around Israel (west, south, east, north), so a query is not
  /// answered with a street of the same name abroad.
  static const String israelBoundingBox = '34.2,29.4,35.9,33.4';

  /// How many features Photon is asked for: more than are shown, since
  /// several are dropped or merged by [PhotonPlaceMapper].
  static const String requestLimit = '15';

  @override
  Future<PlaceSearchResult> search(
    String query, {
    required String language,
  }) async {
    final q = placeSearchQuery(query);
    if (q == null) return const PlacesFound(<StreetPlace>[]);
    final uri = Uri.https(host, '/api/', <String, Object>{
      'q': q,
      'limit': requestLimit,
      'lang': language == 'en' ? 'en' : 'default',
      'bbox': israelBoundingBox,
      'layer': const <String>['house', 'street'],
    });

    final http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(timeout);
    } on http.ClientException {
      return const PlaceSearchFailed(PlaceSearchFailureReason.offline);
    } on TimeoutException {
      return const PlaceSearchFailed(PlaceSearchFailureReason.timeout);
    }

    final status = response.statusCode;
    if (status == 429) {
      return const PlaceSearchFailed(
        PlaceSearchFailureReason.rateLimited,
        statusCode: 429,
      );
    }
    if (status < 200 || status >= 300) {
      return PlaceSearchFailed(
        PlaceSearchFailureReason.providerChanged,
        statusCode: status,
      );
    }
    final Object? decoded;
    try {
      // Photon sends `application/json` with no charset, which `body` would
      // read as Latin-1; JSON is UTF-8.
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return const PlaceSearchFailed(PlaceSearchFailureReason.providerChanged);
    }
    final places = PhotonPlaceMapper.map(decoded);
    if (places == null) {
      return const PlaceSearchFailed(PlaceSearchFailureReason.providerChanged);
    }
    return PlacesFound(List<StreetPlace>.unmodifiable(places));
  }
}
