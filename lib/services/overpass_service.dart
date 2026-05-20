import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/bridge_restriction.dart';
import 'radar_service.dart';

class OverpassService {
  static const _endpoint = 'https://overpass-api.de/api/interpreter';
  static const _corridorM = 80.0;

  /// Consulta o Overpass (OSM) por restrições físicas de vias (maxheight,
  /// maxweight, maxwidth) no corredor da rota. Retorna lista vazia em caso
  /// de falha — nunca propaga exceção.
  static Future<List<BridgeRestriction>> queryAlongRoute(
      List<LatLng> polyline) async {
    if (polyline.isEmpty) return [];

    final bbox  = _routeBbox(polyline);
    final query = _buildQuery(bbox);

    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'data=${Uri.encodeQueryComponent(query)}',
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];

      final elements =
          (jsonDecode(response.body)['elements'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>();

      final restrictions = <BridgeRestriction>[];
      for (final el in elements) {
        final r = _parseElement(el);
        if (r != null) restrictions.add(r);
      }

      // Mantém só as restrições que estão dentro do corredor da rota.
      return restrictions
          .where((r) => _distToRoute(r.lat, r.lng, polyline) <= _corridorM)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Parsing ───────────────────────────────────────────────────────────────

  static BridgeRestriction? _parseElement(Map<String, dynamic> el) {
    final tags = el['tags'] as Map<String, dynamic>? ?? {};

    double? lat, lng;
    if (el['type'] == 'node') {
      lat = (el['lat'] as num?)?.toDouble();
      lng = (el['lon'] as num?)?.toDouble();
    } else {
      final center = el['center'] as Map<String, dynamic>?;
      lat = (center?['lat'] as num?)?.toDouble();
      lng = (center?['lon'] as num?)?.toDouble();
    }
    if (lat == null || lng == null) return null;

    final roadName = tags['name'] as String? ?? tags['ref'] as String?;

    for (final type in ['maxheight', 'maxweight', 'maxwidth']) {
      final raw = tags[type] as String?;
      if (raw == null) continue;
      final value = _parseValue(raw);
      if (value == null) continue;
      return BridgeRestriction(
          lat: lat, lng: lng, type: type, value: value, roadName: roadName);
    }
    return null;
  }

  /// Interpreta valores OSM: "4.5", "4.5 m", "10 t", "4'6\"", "default"…
  static double? _parseValue(String raw) {
    raw = raw.trim().toLowerCase();
    if (raw == 'default' || raw == 'none' || raw == 'no') return null;

    raw = raw.replaceAll(RegExp(r'\s*(m|t|kg|tonnes?)\s*$'), '').trim();

    // Pés e polegadas: 4'6 ou 4'6" — improvável no Brasil, mas tratamos por segurança.
    final ftIn = RegExp(r'''^(\d+)'(\d+)"?$''').firstMatch(raw);
    if (ftIn != null) {
      final feet   = double.tryParse(ftIn.group(1)!) ?? 0;
      final inches = double.tryParse(ftIn.group(2)!) ?? 0;
      return (feet * 12 + inches) * 0.0254;
    }

    return double.tryParse(raw);
  }

  // ── Bounding box da rota ──────────────────────────────────────────────────

  static ({double s, double w, double n, double e}) _routeBbox(
      List<LatLng> pts) {
    var s = pts[0].latitude,  n = pts[0].latitude;
    var w = pts[0].longitude, e = pts[0].longitude;
    for (final p in pts) {
      if (p.latitude  < s) s = p.latitude;
      if (p.latitude  > n) n = p.latitude;
      if (p.longitude < w) w = p.longitude;
      if (p.longitude > e) e = p.longitude;
    }
    const pad = 0.001; // ~110 m de margem em cada lado
    return (s: s - pad, w: w - pad, n: n + pad, e: e + pad);
  }

  static String _buildQuery(
          ({double s, double w, double n, double e}) b) =>
      '[out:json][timeout:15];\n'
      '(\n'
      '  way["maxheight"](${b.s},${b.w},${b.n},${b.e});\n'
      '  way["maxweight"](${b.s},${b.w},${b.n},${b.e});\n'
      '  way["maxwidth"](${b.s},${b.w},${b.n},${b.e});\n'
      '  node["maxheight"](${b.s},${b.w},${b.n},${b.e});\n'
      '  node["maxweight"](${b.s},${b.w},${b.n},${b.e});\n'
      '  node["maxwidth"](${b.s},${b.w},${b.n},${b.e});\n'
      ');\n'
      'out center;\n';

  // ── Spatial ───────────────────────────────────────────────────────────────

  static double _distToRoute(double lat, double lng, List<LatLng> pts) {
    var minD = double.infinity;
    for (final p in pts) {
      final d = RadarService.haversine(lat, lng, p.latitude, p.longitude);
      if (d < minD) minD = d;
    }
    return minD;
  }
}
