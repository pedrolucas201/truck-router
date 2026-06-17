import 'package:google_maps_flutter/google_maps_flutter.dart';

typedef GeoLocation = ({LatLng coords, String? label});

typedef MapsRoute = ({LatLng? origin, LatLng destination});

enum DeepLinkType { route, destination, unknown }

/// Classifica uma URL maps.google.com por tipo de conteúdo.
///
/// - [route]       — tem saddr + daddr (rota compartilhada pelo despachante)
/// - [destination] — tem q= (pin de localização simples)
/// - [unknown]     — formato não reconhecido
DeepLinkType classifyMapsUri(Uri uri) {
  if (uri.host != 'maps.google.com') return DeepLinkType.unknown;
  final p = uri.queryParameters;
  if (p.containsKey('saddr') && p.containsKey('daddr')) return DeepLinkType.route;
  if (p.containsKey('q'))                               return DeepLinkType.destination;
  return DeepLinkType.unknown;
}

/// Parses a `geo:` URI into coordinates and optional label.
///
/// Handles the four common variants:
///   geo:lat,lng
///   geo:lat,lng?z=15
///   geo:0,0?q=lat,lng
///   geo:0,0?q=lat,lng(Label)
///
/// Returns null for malformed or text-search-only URIs (e.g. geo:0,0?q=Coffee).
GeoLocation? parseGeoUri(Uri uri) {
  if (uri.scheme != 'geo') return null;

  final q = uri.queryParameters['q'];
  if (q != null) return _parseQ(q);

  final latLng = _parseLatLng(uri.path);
  if (latLng == null) return null;
  return (coords: latLng, label: null);
}

/// Parses a `https://maps.google.com/maps?q=LAT,LNG(Label)` URI — o formato de
/// pin de localização nativo do WhatsApp (sem saddr/daddr).
///
/// Returns null se não for maps.google.com, se não houver `q`, ou se o `q` for
/// busca textual sem coordenadas (ex: `q=pizzaria`).
GeoLocation? parseMapsDestination(Uri uri) {
  if (uri.host != 'maps.google.com') return null;
  final q = uri.queryParameters['q'];
  if (q == null) return null;
  return _parseQ(q);
}

/// Extrai coords + label opcional de um parâmetro `q` (`LAT,LNG` ou
/// `LAT,LNG(Label)`), compartilhado entre `geo:` e `maps.google.com?q=`.
GeoLocation? _parseQ(String q) {
  String? label;
  String coords = q;
  final parenIdx = q.indexOf('(');
  if (parenIdx != -1) {
    label = q.substring(parenIdx + 1, q.endsWith(')') ? q.length - 1 : q.length);
    coords = q.substring(0, parenIdx).trim();
  }
  final latLng = _parseLatLng(coords);
  if (latLng == null) return null;
  return (coords: latLng, label: label?.isNotEmpty == true ? label : null);
}

/// Parses a `https://maps.google.com/maps?saddr=...&daddr=...` URI.
/// Returns null if daddr is missing or unparseable.
MapsRoute? parseMapsUri(Uri uri) {
  if (uri.host != 'maps.google.com') return null;

  final daddrStr = uri.queryParameters['daddr'];
  if (daddrStr == null) return null;
  final destination = _parseLatLng(daddrStr);
  if (destination == null) return null;

  final saddrStr = uri.queryParameters['saddr'];
  final origin = saddrStr != null ? _parseLatLng(saddrStr) : null;

  return (origin: origin, destination: destination);
}

LatLng? _parseLatLng(String s) {
  final parts = s.split(',');
  if (parts.length < 2) return null;
  final lat = double.tryParse(parts[0].trim());
  final lng = double.tryParse(parts[1].trim());
  if (lat == null || lng == null) return null;
  if (lat == 0.0 && lng == 0.0) return null;
  return LatLng(lat, lng);
}
