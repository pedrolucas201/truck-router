import 'dart:math';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/radar_point.dart';

class RadarService {
  static List<RadarPoint>? _cache;

  static Future<List<RadarPoint>> load() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString('assets/maparadar.csv');
    _cache = _parse(raw);
    return _cache!;
  }

  static List<RadarPoint> _parse(String csv) {
    final result = <RadarPoint>[];
    for (final line in csv.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final commaIdx1 = trimmed.indexOf(',');
      if (commaIdx1 == -1) continue;
      final commaIdx2 = trimmed.indexOf(',', commaIdx1 + 1);
      if (commaIdx2 == -1) continue;
      final lng = double.tryParse(trimmed.substring(0, commaIdx1));
      final lat = double.tryParse(trimmed.substring(commaIdx1 + 1, commaIdx2));
      if (lng == null || lat == null) continue;
      final desc = trimmed.substring(commaIdx2 + 1);
      final atIdx = desc.lastIndexOf('@');
      final type = atIdx > 0 ? desc.substring(0, atIdx).trim() : desc.trim();
      final speed = atIdx > 0 ? int.tryParse(desc.substring(atIdx + 1).trim()) ?? 0 : 0;
      result.add(RadarPoint(lat: lat, lng: lng, type: type, speedKmh: speed));
    }
    return result;
  }

  static List<RadarPoint> deduplicateNearby(
    List<RadarPoint> radares, {
    double minDistanceMeters = 150,
  }) {
    final result = <RadarPoint>[];
    for (final r in radares) {
      var tooClose = false;
      for (final kept in result) {
        if (haversine(r.lat, r.lng, kept.lat, kept.lng) < minDistanceMeters) {
          tooClose = true;
          break;
        }
      }
      if (!tooClose) { result.add(r); }
    }
    return result;
  }

  static List<RadarPoint> filterNearRoute(
    List<RadarPoint> all,
    List<LatLng> polyline, {
    double radiusMeters = 500,
  }) {
    if (polyline.isEmpty) return [];

    // Bounding box com buffer (~500m em graus)
    const buffer = 0.005;
    var minLat = polyline[0].latitude;
    var maxLat = polyline[0].latitude;
    var minLng = polyline[0].longitude;
    var maxLng = polyline[0].longitude;
    for (final p in polyline) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    minLat -= buffer; maxLat += buffer;
    minLng -= buffer; maxLng += buffer;

    // Amostra a polyline a cada 5 pontos para reduzir cálculos
    final sampled = <LatLng>[];
    for (var i = 0; i < polyline.length; i += 5) {
      sampled.add(polyline[i]);
    }
    if (sampled.isEmpty || sampled.last != polyline.last) {
      sampled.add(polyline.last);
    }


    final result = <RadarPoint>[];
    for (final radar in all) {
      // Filtro rápido por bounding box
      if (radar.lat < minLat || radar.lat > maxLat ||
          radar.lng < minLng || radar.lng > maxLng) { continue; }
      // Verifica distância real a algum ponto amostrado
      for (final p in sampled) {
        if (haversine(radar.lat, radar.lng, p.latitude, p.longitude) <= radiusMeters) {
          result.add(radar);
          break;
        }
      }
    }
    return result;
  }

  static double haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
        sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}
