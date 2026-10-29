import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../core/config.dart';

/// Ola Maps (free tier): map pictures, place search and address lookup.
bool get mapsReady => olaMapsKey.isNotEmpty;

const _host = 'api.olamaps.io';

String _rid() => '${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 30)}';

/// Picture of the map around a point (PNG).
String staticMapUrl(double lat, double lng, {int width = 600, int height = 300, int zoom = 16}) =>
    'https://$_host/tiles/v1/styles/default-light-standard/static/${lng.toStringAsFixed(6)},${lat.toStringAsFixed(6)},$zoom/${width}x$height.png?api_key=$olaMapsKey';

/// Metres per screen pixel of a static map at [zoom] (512-px tiles).
double metersPerPixel(double lat, int zoom) => 78271.517 * math.cos(lat * math.pi / 180) / math.pow(2, zoom);

class PlaceHit {
  const PlaceHit({required this.title, required this.subtitle, required this.placeId, this.lat, this.lng});
  final String title, subtitle, placeId;
  final double? lat, lng;
}

Future<Map<String, dynamic>> _get(String path, Map<String, String> q) async {
  final uri = Uri.https(_host, path, {...q, 'api_key': olaMapsKey});
  final r = await http.get(uri, headers: {'X-Request-Id': _rid()}).timeout(const Duration(seconds: 15));
  if (r.statusCode != 200) throw Exception('maps ${r.statusCode}');
  return jsonDecode(r.body) as Map<String, dynamic>;
}

double? _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v');

/// Search places by name (biased near [nearLat],[nearLng] when given).
Future<List<PlaceHit>> searchPlaces(String text, {double? nearLat, double? nearLng}) async {
  final j = await _get('/places/v1/autocomplete', {
    'input': text,
    if (nearLat != null && nearLng != null) 'location': '$nearLat,$nearLng',
  });
  final list = (j['predictions'] as List? ?? const []).whereType<Map>();
  return [
    for (final p in list)
      PlaceHit(
        title: '${(p['structured_formatting'] as Map?)?['main_text'] ?? p['description'] ?? ''}',
        subtitle: '${(p['structured_formatting'] as Map?)?['secondary_text'] ?? ''}',
        placeId: '${p['place_id'] ?? ''}',
        lat: _d(((p['geometry'] as Map?)?['location'] as Map?)?['lat']),
        lng: _d(((p['geometry'] as Map?)?['location'] as Map?)?['lng']),
      ),
  ];
}

/// Exact point of a search result.
Future<(double, double)?> placeLocation(PlaceHit h) async {
  if (h.lat != null && h.lng != null) return (h.lat!, h.lng!);
  final j = await _get('/places/v1/details', {'place_id': h.placeId});
  final loc = ((j['result'] as Map?)?['geometry'] as Map?)?['location'] as Map?;
  final lat = _d(loc?['lat']), lng = _d(loc?['lng']);
  return lat == null || lng == null ? null : (lat, lng);
}

/// Address of a point, e.g. "Laheriasarai Road, Darbhanga".
Future<String> addressOf(double lat, double lng) async {
  try {
    final j = await _get('/places/v1/reverse-geocode', {'latlng': '$lat,$lng'});
    final r = (j['results'] as List? ?? const []).whereType<Map>().firstOrNull;
    return '${r?['formatted_address'] ?? ''}';
  } catch (_) {
    return '';
  }
}
